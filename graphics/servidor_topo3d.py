"""Servidor local ligero (sin dependencias externas) para el Motor Gráfico 2D/3D Multicapa (Field Shift Guatemala).

Ejecución:
  python graphics/servidor_topo3d.py --port 8090

Sirve:
  - GET /                        -> graphics/topo3d.html (Visor Topográfico 2D/3D WebGL Ultra-HD + NASA POWER)
  - GET /api/aw3d30?lat=..&lon=..&radius_km=5&n=68
      Endpoint auxiliar de respaldo que recorta una malla de N×N puntos de JAXA ALOS AW3D30 v4.1:
      1) Si el recorte cae dentro de `datos/relieve/chiquimula_aw3d30_dsm.tif`, lo lee directo desde disco.
      2) Si cae fuera, descarga bajo demanda únicamente los bloques 256×256 necesarios del
         Cloud-Optimized GeoTIFF (COG) oficial de JAXA ALOS AW3D30 v4.1 vía peticiones HTTP Range
         y los almacena en caché local en `datos/relieve/jaxa_cog_cache/`.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import math
from pathlib import Path
import ssl
import struct
import urllib.parse
import urllib.request
import zlib

RAIZ = Path(__file__).resolve().parent.parent
TIF_PATH = RAIZ / "datos" / "relieve" / "chiquimula_aw3d30_dsm.tif"
CACHE_DIR = RAIZ / "datos" / "relieve" / "jaxa_cog_cache"
GRAPHICS_HTML = RAIZ / "graphics" / "topo3d.html"
WEB_HTML_FALLBACK = RAIZ / "web" / "topo3d.html"

JE_COG_BASE = "https://s3.ap-northeast-1.wasabisys.com/je-pds/cog/v1/JAXA.EORC_ALOS.PRISM_AW3D30.v4.1_global/2024-04/3"
SSL_CTX = ssl._create_unverified_context()


class LocalGeoTIFF:
    """Lector puro en Python (struct + zlib) para el recorte local chiquimula_aw3d30_dsm.tif."""

    def __init__(self, path: Path):
        self.path = path
        self.width = 0
        self.height = 0
        self.scale_x = 0.0
        self.scale_y = 0.0
        self.origin_lon = 0.0
        self.origin_lat = 0.0
        self.grid = []
        if self.path.exists():
            self._load()

    def _load(self):
        data = self.path.read_bytes()
        endian = "<" if data[:2] == b"II" else ">"
        _, ifd_offset = struct.unpack(endian + "HI", data[2:8])
        num_entries = struct.unpack(endian + "H", data[ifd_offset : ifd_offset + 2])[0]

        tags = {}
        type_sizes = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8}
        type_fmt = {1: "B", 3: "H", 4: "I", 8: "h", 9: "i", 11: "f", 12: "d"}

        pos = ifd_offset + 2
        for _ in range(num_entries):
            tag, ttype, count, val_off = struct.unpack(endian + "HHII", data[pos : pos + 12])
            pos += 12
            total_bytes = count * type_sizes.get(ttype, 1)
            fmt = type_fmt.get(ttype)
            if total_bytes <= 4 and fmt:
                raw = struct.pack(endian + "I", val_off)[:total_bytes]
                tags[tag] = struct.unpack(endian + fmt * count, raw)
            elif fmt:
                raw = data[val_off : val_off + total_bytes]
                tags[tag] = struct.unpack(endian + fmt * count, raw)

        self.width = tags[256][0]
        self.height = tags[257][0]
        rows_per_strip = tags[278][0]
        strip_offsets = tags[273]
        strip_byte_counts = tags[279]
        self.scale_x, self.scale_y = tags[33550][0], tags[33550][1]
        self.origin_lon, self.origin_lat = tags[33922][3], tags[33922][4]

        rows = []
        for idx, (off, bcount) in enumerate(zip(strip_offsets, strip_byte_counts)):
            raw_strip = zlib.decompress(data[off : off + bcount])
            expected_rows = min(rows_per_strip, self.height - idx * rows_per_strip)
            vals = struct.unpack(endian + f"{expected_rows * self.width}h", raw_strip)
            for r in range(expected_rows):
                rows.append(vals[r * self.width : (r + 1) * self.width])
        self.grid = rows

    @property
    def bounds(self):
        lon_min = self.origin_lon
        lon_max = self.origin_lon + self.width * self.scale_x
        lat_max = self.origin_lat
        lat_min = self.origin_lat - self.height * self.scale_y
        return (lon_min, lat_min, lon_max, lat_max)

    def covers_box(self, lon_min: float, lat_min: float, lon_max: float, lat_max: float) -> bool:
        if not self.grid:
            return False
        b_lon_min, b_lat_min, b_lon_max, b_lat_max = self.bounds
        return (
            lon_min >= b_lon_min
            and lon_max <= b_lon_max
            and lat_min >= b_lat_min
            and lat_max <= b_lat_max
        )

    def sample_point(self, lat: float, lon: float) -> float:
        px = (lon - self.origin_lon) / self.scale_x
        py = (self.origin_lat - lat) / self.scale_y
        ix = max(0, min(self.width - 1, int(round(px))))
        iy = max(0, min(self.height - 1, int(round(py))))
        return float(self.grid[iy][ix])


class JaxaRemoteCOGManager:
    """Descarga bajo demanda bloques 256×256 del COG oficial de JAXA AW3D30 v4.1 vía HTTP Range."""

    def __init__(self, cache_dir: Path):
        self.cache_dir = cache_dir
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.headers_cache = {}
        self.tiles_mem = {}

    @staticmethod
    def _tile_name_for_latlon(lat: float, lon: float) -> str:
        lat_floor = int(math.floor(lat))
        lon_floor = int(math.floor(lon))
        ns = "N" if lat_floor >= 0 else "S"
        ew = "E" if lon_floor >= 0 else "W"
        return f"{ns}{abs(lat_floor):03d}{ew}{abs(lon_floor):03d}"

    @staticmethod
    def _folder_for_latlon(lat: float, lon: float) -> str:
        lat_band = int(math.floor(lat / 5.0) * 5)
        lon_band = int(math.floor(lon / 5.0) * 5)
        ns = "N" if lat_band >= 0 else "S"
        ew = "E" if lon_band >= 0 else "W"
        return f"{ns}{abs(lat_band):03d}{ew}{abs(lon_band):03d}"

    def _get_cog_url(self, tile_name: str, lat: float, lon: float) -> str:
        folder = self._folder_for_latlon(lat, lon)
        return f"{JE_COG_BASE}/{folder}/{tile_name}/ALPSMLC30_{tile_name}_DSM.tif"

    def _fetch_range(self, url: str, start: int, end: int) -> bytes:
        req = urllib.request.Request(
            url,
            headers={
                "Range": f"bytes={start}-{end}",
                "User-Agent": "FieldShiftGuatemala/1.0",
            },
        )
        with urllib.request.urlopen(req, timeout=20, context=SSL_CTX) as resp:
            return resp.read()

    def _get_header(self, tile_name: str, lat: float, lon: float) -> dict:
        if tile_name in self.headers_cache:
            return self.headers_cache[tile_name]

        hdr_file = self.cache_dir / f"{tile_name}_header.json"
        if hdr_file.exists():
            info = json.loads(hdr_file.read_text(encoding="utf-8"))
            self.headers_cache[tile_name] = info
            return info

        url = self._get_cog_url(tile_name, lat, lon)
        data = self._fetch_range(url, 0, 32767)
        endian = "<" if data[:2] == b"II" else ">"
        _, ifd_offset = struct.unpack(endian + "HI", data[2:8])
        num_entries = struct.unpack(endian + "H", data[ifd_offset : ifd_offset + 2])[0]

        tags = {}
        type_sizes = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8}
        type_fmt = {1: "B", 3: "H", 4: "I", 8: "h", 9: "i", 11: "f", 12: "d"}

        pos = ifd_offset + 2
        for _ in range(num_entries):
            tag, ttype, count, val_off = struct.unpack(endian + "HHII", data[pos : pos + 12])
            pos += 12
            total_bytes = count * type_sizes.get(ttype, 1)
            fmt = type_fmt.get(ttype)
            if total_bytes <= 4 and fmt:
                raw = struct.pack(endian + "I", val_off)[:total_bytes]
                tags[tag] = list(struct.unpack(endian + fmt * count, raw))
            elif fmt:
                raw = data[val_off : val_off + total_bytes]
                tags[tag] = list(struct.unpack(endian + fmt * count, raw))

        info = {
            "url": url,
            "endian": endian,
            "width": tags[256][0],
            "height": tags[257][0],
            "tile_w": tags[322][0],
            "tile_h": tags[323][0],
            "offsets": tags[324],
            "byte_counts": tags[325],
            "predictor": tags.get(317, [1])[0],
            "scale_x": tags[33550][0],
            "scale_y": tags[33550][1],
            "origin_lon": tags[33922][3],
            "origin_lat": tags[33922][4],
        }
        hdr_file.write_text(json.dumps(info), encoding="utf-8")
        self.headers_cache[tile_name] = info
        return info

    def _get_block(self, tile_name: str, hdr: dict, block_idx: int) -> list:
        key = (tile_name, block_idx)
        if key in self.tiles_mem:
            return self.tiles_mem[key]

        blk_file = self.cache_dir / f"{tile_name}_blk_{block_idx}.bin"
        tw, th = hdr["tile_w"], hdr["tile_h"]
        endian = hdr["endian"]

        if blk_file.exists():
            raw_bytes = blk_file.read_bytes()
            vals = list(struct.unpack(endian + f"{tw * th}h", raw_bytes))
            self.tiles_mem[key] = vals
            return vals

        off = hdr["offsets"][block_idx]
        bc = hdr["byte_counts"][block_idx]
        comp = self._fetch_range(hdr["url"], off, off + bc - 1)
        decomp = zlib.decompress(comp)
        vals = list(struct.unpack(endian + f"{tw * th}h", decomp))

        if hdr.get("predictor", 1) == 2:
            for r in range(th):
                row_start = r * tw
                acc = vals[row_start]
                for c in range(1, tw):
                    acc = (acc + vals[row_start + c]) & 0xFFFF
                    if acc >= 0x8000:
                        acc -= 0x10000
                    vals[row_start + c] = acc

        blk_file.write_bytes(struct.pack(endian + f"{tw * th}h", *vals))
        self.tiles_mem[key] = vals
        return vals

    def prefetch_box(self, lon_min: float, lat_min: float, lon_max: float, lat_max: float):
        corners = [
            (lat_min, lon_min),
            (lat_min, lon_max),
            (lat_max, lon_min),
            (lat_max, lon_max),
        ]
        needed_tiles = {}
        for lat, lon in corners:
            tname = self._tile_name_for_latlon(lat, lon)
            needed_tiles[tname] = (lat, lon)

        blocks_to_fetch = []
        for tname, (lat, lon) in needed_tiles.items():
            hdr = self._get_header(tname, lat, lon)
            tw, th = hdr["tile_w"], hdr["tile_h"]
            tiles_across = (hdr["width"] + tw - 1) // tw
            tiles_down = (hdr["height"] + th - 1) // th

            px_min = max(0, int(math.floor((lon_min - hdr["origin_lon"]) / hdr["scale_x"])))
            px_max = min(hdr["width"] - 1, int(math.ceil((lon_max - hdr["origin_lon"]) / hdr["scale_x"])))
            py_min = max(0, int(math.floor((hdr["origin_lat"] - lat_max) / hdr["scale_y"])))
            py_max = min(hdr["height"] - 1, int(math.ceil((hdr["origin_lat"] - lat_min) / hdr["scale_y"])))

            if px_min > px_max or py_min > py_max:
                continue

            tx0, tx1 = px_min // tw, px_max // tw
            ty0, ty1 = py_min // th, py_max // th
            for ty in range(max(0, ty0), min(tiles_down - 1, ty1) + 1):
                for tx in range(max(0, tx0), min(tiles_across - 1, tx1) + 1):
                    b_idx = ty * tiles_across + tx
                    if (tname, b_idx) not in self.tiles_mem:
                        blocks_to_fetch.append((tname, hdr, b_idx))

        if blocks_to_fetch:
            with ThreadPoolExecutor(max_workers=6) as pool:
                list(pool.map(lambda args: self._get_block(*args), blocks_to_fetch))

        return len(blocks_to_fetch)

    def sample_point(self, lat: float, lon: float) -> float:
        tname = self._tile_name_for_latlon(lat, lon)
        hdr = self._get_header(tname, lat, lon)
        px = int(round((lon - hdr["origin_lon"]) / hdr["scale_x"]))
        py = int(round((hdr["origin_lat"] - lat) / hdr["scale_y"]))
        px = max(0, min(hdr["width"] - 1, px))
        py = max(0, min(hdr["height"] - 1, py))

        tw, th = hdr["tile_w"], hdr["tile_h"]
        tiles_across = (hdr["width"] + tw - 1) // tw
        b_idx = (py // th) * tiles_across + (px // tw)
        blk = self._get_block(tname, hdr, b_idx)
        val = float(blk[(py % th) * tw + (px % tw)])
        return 0.0 if val < -1000 else val


DEM_LOCAL = LocalGeoTIFF(TIF_PATH)
COG_REMOTE = JaxaRemoteCOGManager(CACHE_DIR)


def extract_grid(lat: float, lon: float, radius_km: float = 5.0, n: int = 68) -> dict:
    dlat = radius_km / 111.32
    dlon = radius_km / (111.32 * math.cos(math.radians(lat)))

    lat_min, lat_max = lat - dlat, lat + dlat
    lon_min, lon_max = lon - dlon, lon + dlon

    use_local = DEM_LOCAL.covers_box(lon_min, lat_min, lon_max, lat_max)
    tiles_fetched = 0
    if not use_local:
        tiles_fetched = COG_REMOTE.prefetch_box(lon_min, lat_min, lon_max, lat_max)

    out_grid = []
    min_elev = 99999.0
    max_elev = -99999.0

    for r in range(n):
        sample_lat = lat_max - (r / (n - 1)) * (lat_max - lat_min)
        row_vals = []
        for c in range(n):
            sample_lon = lon_min + (c / (n - 1)) * (lon_max - lon_min)
            if use_local:
                val = DEM_LOCAL.sample_point(sample_lat, sample_lon)
            else:
                val = COG_REMOTE.sample_point(sample_lat, sample_lon)
            row_vals.append(round(val, 1))
            if val < min_elev:
                min_elev = val
            if val > max_elev:
                max_elev = val
        out_grid.append(row_vals)

    center_elev = out_grid[n // 2][n // 2]

    return {
        "source": (
            "JAXA ALOS AW3D30 v4.1 (30m DSM local)"
            if use_local
            else f"JAXA ALOS AW3D30 v4.1 (30m COG remoto + caché local, {tiles_fetched} bloques)"
        ),
        "center": {"lat": lat, "lon": lon, "elev_m": center_elev},
        "radius_km": radius_km,
        "n": n,
        "inside_coverage": True,
        "used_remote_cog": not use_local,
        "tif_bounds": list(DEM_LOCAL.bounds) if DEM_LOCAL.grid else [],
        "req_bounds": [lon_min, lat_min, lon_max, lat_max],
        "min_elev_m": min_elev,
        "max_elev_m": max_elev,
        "grid": out_grid,
    }


class TopoHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path in ("/", "/index.html", "/topo3d.html", "/graphics", "/graphics/"):
            target_html = GRAPHICS_HTML if GRAPHICS_HTML.exists() else WEB_HTML_FALLBACK
            content = target_html.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(content)
            return

        if parsed.path == "/api/aw3d30":
            qs = urllib.parse.parse_qs(parsed.query)
            lat = float(qs.get("lat", ["14.8000"])[0])
            lon = float(qs.get("lon", ["-89.5400"])[0])
            radius_km = float(qs.get("radius_km", ["5.0"])[0])
            n = max(16, min(120, int(qs.get("n", ["68"])[0])))

            payload = json.dumps(extract_grid(lat, lon, radius_km, n)).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)
            return

        return super().do_GET()

    def log_message(self, format, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description="Servidor local del Visor Topográfico 2D/3D Multicapa")
    parser.add_argument("--port", type=int, default=8090, help="Puerto HTTP local (por defecto: 8090)")
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), TopoHandler)
    print(f"Servidor Topo3D activo en http://localhost:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
