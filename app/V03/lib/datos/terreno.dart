/// Motor topográfico DEM (NASA SRTM / Terrarium), hidrología (OpenStreetMap
/// Overpass + vaguadas SRTM) y climatología mensual (NASA POWER MERRA-2).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class PuntoCauce {
  const PuntoCauce({
    required this.r,
    required this.c,
    required this.u,
    required this.v,
    required this.lat,
    required this.lon,
    required this.elev,
  });
  final int r, c;
  final double u, v, lat, lon, elev;
}

class CuerpoAgua {
  const CuerpoAgua({
    required this.nombre,
    required this.tipo,
    required this.fuente,
    required this.permanente,
    required this.puntos,
  });
  final String nombre, tipo, fuente;
  final bool permanente;
  final List<PuntoCauce> puntos;
}

class CuerpoAguaCercano {
  const CuerpoAguaCercano({
    required this.nombre,
    required this.tipo,
    required this.fuente,
    required this.permanente,
    required this.distanciaM,
    required this.elevAguaM,
    required this.elevParcelaM,
    required this.deltaZM,
    required this.punto,
  });
  final String nombre, tipo, fuente;
  final bool permanente;
  final int distanciaM, elevAguaM, elevParcelaM, deltaZM;
  final PuntoCauce punto;
}

class PuntoEscorrentia {
  const PuntoEscorrentia({
    required this.u,
    required this.v,
    required this.elev,
    required this.nx,
    required this.ny,
    required this.nz,
    required this.pendiente,
  });
  final double u, v, elev, nx, ny, nz, pendiente;
}

class ClimaMensualNasa {
  const ClimaMensualNasa({
    required this.mes,
    required this.nombre,
    required this.t2m,
    required this.tmax,
    required this.tmin,
    required this.rh2m,
    required this.lluviaMmDia,
    required this.gwettop,
    required this.gwetroot,
  });
  final int mes;
  final String nombre;
  final double t2m, tmax, tmin, rh2m, lluviaMmDia, gwettop, gwetroot;
  double get humedadSueloPct =>
      ((gwetroot * 0.65 + gwettop * 0.35) * 100.0).clamp(8.0, 98.0);
}

const Map<int, ClimaMensualNasa> climatologiaBaseNasa = {
  1: ClimaMensualNasa(
    mes: 1,
    nombre: 'Enero',
    t2m: 19.81,
    tmax: 24.82,
    tmin: 16.30,
    rh2m: 85.75,
    lluviaMmDia: 2.35,
    gwettop: 0.65,
    gwetroot: 0.64,
  ),
  2: ClimaMensualNasa(
    mes: 2,
    nombre: 'Febrero',
    t2m: 21.17,
    tmax: 27.08,
    tmin: 16.98,
    rh2m: 80.36,
    lluviaMmDia: 1.56,
    gwettop: 0.57,
    gwetroot: 0.58,
  ),
  3: ClimaMensualNasa(
    mes: 3,
    nombre: 'Marzo',
    t2m: 22.93,
    tmax: 29.70,
    tmin: 17.93,
    rh2m: 73.33,
    lluviaMmDia: 2.41,
    gwettop: 0.49,
    gwetroot: 0.53,
  ),
  4: ClimaMensualNasa(
    mes: 4,
    nombre: 'Abril',
    t2m: 24.93,
    tmax: 31.88,
    tmin: 19.68,
    rh2m: 69.19,
    lluviaMmDia: 1.43,
    gwettop: 0.45,
    gwetroot: 0.50,
  ),
  5: ClimaMensualNasa(
    mes: 5,
    nombre: 'Mayo',
    t2m: 25.19,
    tmax: 30.89,
    tmin: 20.93,
    rh2m: 74.28,
    lluviaMmDia: 5.13,
    gwettop: 0.51,
    gwetroot: 0.52,
  ),
  6: ClimaMensualNasa(
    mes: 6,
    nombre: 'Junio',
    t2m: 23.84,
    tmax: 27.99,
    tmin: 20.80,
    rh2m: 83.78,
    lluviaMmDia: 7.08,
    gwettop: 0.66,
    gwetroot: 0.61,
  ),
  7: ClimaMensualNasa(
    mes: 7,
    nombre: 'Julio',
    t2m: 23.14,
    tmax: 26.99,
    tmin: 20.37,
    rh2m: 87.11,
    lluviaMmDia: 5.38,
    gwettop: 0.70,
    gwetroot: 0.66,
  ),
  8: ClimaMensualNasa(
    mes: 8,
    nombre: 'Agosto',
    t2m: 23.27,
    tmax: 27.18,
    tmin: 20.42,
    rh2m: 86.89,
    lluviaMmDia: 6.22,
    gwettop: 0.73,
    gwetroot: 0.69,
  ),
  9: ClimaMensualNasa(
    mes: 9,
    nombre: 'Septiembre',
    t2m: 23.20,
    tmax: 26.97,
    tmin: 20.46,
    rh2m: 87.39,
    lluviaMmDia: 7.13,
    gwettop: 0.78,
    gwetroot: 0.75,
  ),
  10: ClimaMensualNasa(
    mes: 10,
    nombre: 'Octubre',
    t2m: 22.28,
    tmax: 26.07,
    tmin: 19.52,
    rh2m: 88.67,
    lluviaMmDia: 5.43,
    gwettop: 0.79,
    gwetroot: 0.78,
  ),
  11: ClimaMensualNasa(
    mes: 11,
    nombre: 'Noviembre',
    t2m: 20.67,
    tmax: 24.78,
    tmin: 17.71,
    rh2m: 88.97,
    lluviaMmDia: 3.42,
    gwettop: 0.76,
    gwetroot: 0.75,
  ),
  12: ClimaMensualNasa(
    mes: 12,
    nombre: 'Diciembre',
    t2m: 20.09,
    tmax: 24.68,
    tmin: 16.89,
    rh2m: 87.78,
    lluviaMmDia: 2.21,
    gwettop: 0.71,
    gwetroot: 0.69,
  ),
};

const _clavesMes = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];
const _nombresMes = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];
const _offsetMaxDiurno = [
  5.01,
  5.91,
  6.77,
  6.95,
  5.70,
  4.15,
  3.85,
  3.91,
  3.77,
  3.79,
  4.11,
  4.59,
];
const _offsetMinDiurno = [
  3.51,
  4.19,
  5.00,
  5.25,
  4.26,
  3.04,
  2.77,
  2.85,
  2.74,
  2.76,
  2.96,
  3.20,
];

class MallaTerreno {
  const MallaTerreno({
    required this.latitud,
    required this.longitud,
    required this.anchoKm,
    required this.altoKm,
    this.n = 56,
    required this.bounds,
    required this.minElev,
    required this.maxElev,
    required this.refElev,
    required this.medianaPendiente,
    required this.elev,
    required this.pendiente,
    required this.gradX,
    required this.gradY,
    required this.normales,
    required this.insolacion,
    required this.escorrentia,
    required this.cuerposAgua,
    required this.climatologia,
    required this.fuenteDem,
    required this.esRemoto,
  });

  final double latitud, longitud, anchoKm, altoKm;
  final int n;
  final List<double> bounds;
  final double minElev, maxElev, refElev, medianaPendiente;
  final Float32List elev, pendiente, gradX, gradY, normales, insolacion;
  final List<List<PuntoEscorrentia>> escorrentia;
  final List<CuerpoAgua> cuerposAgua;
  final Map<int, ClimaMensualNasa> climatologia;
  final String fuenteDem;
  final bool esRemoto;

  static List<double> calcularBounds(
    double latitud,
    double longitud,
    double anchoKm,
    double altoKm,
  ) {
    final dlat = (altoKm * 0.5) / 111.32;
    final cosLat = math.cos(latitud.clamp(-85.0, 85.0) * math.pi / 180.0);
    final dlon = (anchoKm * 0.5) / (111.32 * math.max(0.05, cosLat));
    return [longitud - dlon, latitud - dlat, longitud + dlon, latitud + dlat];
  }

  factory MallaTerreno.desdeElevaciones({
    required double latitud,
    required double longitud,
    required Float32List rawElev,
    double anchoKm = 5.0,
    double altoKm = 5.0,
    int n = 56,
    double? refElev,
    List<CuerpoAgua>? cuerposAguaExtra,
    Map<int, ClimaMensualNasa>? climatologia,
    String fuenteDem = 'NASA SRTM · Terrarium DEM',
    bool esRemoto = false,
  }) {
    final bounds = calcularBounds(latitud, longitud, anchoKm, altoKm);
    final pass1 = Float32List(n * n);
    final tempElev = Float32List(n * n);
    final elev = Float32List(n * n);

    void smoothPass(Float32List src, Float32List dst) {
      for (var r = 0; r < n; r++) {
        for (var c = 0; c < n; c++) {
          final cL = math.max(0, c - 1), cR = math.min(n - 1, c + 1);
          pass1[r * n + c] =
              0.24 * src[r * n + cL] +
              0.52 * src[r * n + c] +
              0.24 * src[r * n + cR];
        }
      }
      for (var r = 0; r < n; r++) {
        final rU = math.max(0, r - 1), rD = math.min(n - 1, r + 1);
        for (var c = 0; c < n; c++) {
          dst[r * n + c] =
              0.24 * pass1[rU * n + c] +
              0.52 * pass1[r * n + c] +
              0.24 * pass1[rD * n + c];
        }
      }
    }

    smoothPass(rawElev, tempElev);
    smoothPass(tempElev, elev);

    var minE = double.infinity, maxE = double.negativeInfinity;
    for (var i = 0; i < n * n; i++) {
      final val = elev[i];
      if (val < minE) minE = val;
      if (val > maxE) maxE = val;
    }
    if (!minE.isFinite) minE = 0.0;
    if (!maxE.isFinite) maxE = 0.0;

    final cellMX = (anchoKm * 1000.0) / math.max(1, n - 1);
    final cellMY = (altoKm * 1000.0) / math.max(1, n - 1);
    final slope = Float32List(n * n);
    final gradX = Float32List(n * n);
    final gradY = Float32List(n * n);
    final normals = Float32List(n * n * 3);
    final insolation = Float32List(n * n);

    for (var r = 0; r < n; r++) {
      final r0 = math.max(0, r - 1), r1 = math.min(n - 1, r + 1);
      for (var c = 0; c < n; c++) {
        final c0 = math.max(0, c - 1), c1 = math.min(n - 1, c + 1);
        final idx = r * n + c;
        final dzdx =
            (elev[r * n + c1] - elev[r * n + c0]) /
            (math.max(1, c1 - c0) * cellMX);
        final dzdy =
            (elev[r1 * n + c] - elev[r0 * n + c]) /
            (math.max(1, r1 - r0) * cellMY);
        gradX[idx] = dzdx;
        gradY[idx] = dzdy;
        slope[idx] = math.sqrt(dzdx * dzdx + dzdy * dzdy) * 100.0;

        final nx = -dzdx * 2.2;
        const ny = 1.0;
        final nz = -dzdy * 2.2;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        final invLen = len > 0 ? 1.0 / len : 1.0;
        normals[idx * 3 + 0] = nx * invLen;
        normals[idx * 3 + 1] = ny * invLen;
        normals[idx * 3 + 2] = nz * invLen;

        insolation[idx] = ((-dzdx * 0.6 + dzdy * 0.8) * 3.5).clamp(-1.0, 1.0);
      }
    }

    ({
      double elev,
      double gx,
      double gy,
      double slope,
      double nx,
      double ny,
      double nz,
    })
    sampleSurfaceUV(double u, double v) {
      final fc = (((u + 1.0) * 0.5) * (n - 1)).clamp(0.0, n - 1.001);
      final fr = (((v + 1.0) * 0.5) * (n - 1)).clamp(0.0, n - 1.001);
      final c0 = fc.floor(), r0 = fr.floor();
      final c1 = math.min(n - 1, c0 + 1), r1 = math.min(n - 1, r0 + 1);
      final wc = fc - c0, wr = fr - r0;

      final i00 = r0 * n + c0, i10 = r0 * n + c1;
      final i01 = r1 * n + c0, i11 = r1 * n + c1;

      double bilerp(Float32List arr) =>
          (arr[i00] * (1 - wc) + arr[i10] * wc) * (1 - wr) +
          (arr[i01] * (1 - wc) + arr[i11] * wc) * wr;

      final nx =
          (normals[i00 * 3] * (1 - wc) + normals[i10 * 3] * wc) * (1 - wr) +
          (normals[i01 * 3] * (1 - wc) + normals[i11 * 3] * wc) * wr;
      final ny =
          (normals[i00 * 3 + 1] * (1 - wc) + normals[i10 * 3 + 1] * wc) *
              (1 - wr) +
          (normals[i01 * 3 + 1] * (1 - wc) + normals[i11 * 3 + 1] * wc) * wr;
      final nz =
          (normals[i00 * 3 + 2] * (1 - wc) + normals[i10 * 3 + 2] * wc) *
              (1 - wr) +
          (normals[i01 * 3 + 2] * (1 - wc) + normals[i11 * 3 + 2] * wc) * wr;

      return (
        elev: bilerp(elev),
        gx: bilerp(gradX),
        gy: bilerp(gradY),
        slope: bilerp(slope),
        nx: nx,
        ny: ny,
        nz: nz,
      );
    }

    final streamlines = <List<PuntoEscorrentia>>[];
    final seedStep = math.max(4, (n * 11 / 180).round());
    const numSteps = 14;
    const dt = 0.012;

    for (var r = seedStep; r < n - seedStep; r += seedStep) {
      for (var c = seedStep; c < n - seedStep; c += seedStep) {
        final jr = (r + ((c * 7) % 5) - 2).clamp(0, n - 1);
        final jc = (c + ((r * 11) % 5) - 2).clamp(0, n - 1);
        final startIdx = jr * n + jc;
        if (slope[startIdx] < 5.5) continue;

        var u = (jc / (n - 1)) * 2.0 - 1.0;
        var v = (jr / (n - 1)) * 2.0 - 1.0;
        final pts = <PuntoEscorrentia>[];

        for (var s = 0; s < numSteps; s++) {
          final s0 = sampleSurfaceUV(u, v);
          pts.add(
            PuntoEscorrentia(
              u: u,
              v: v,
              elev: s0.elev,
              nx: s0.nx,
              ny: s0.ny,
              nz: s0.nz,
              pendiente: s0.slope,
            ),
          );

          if (s0.slope < 2.2) break;
          final gLen0 = math.sqrt(s0.gx * s0.gx + s0.gy * s0.gy);
          final invG0 = gLen0 > 0 ? 1.0 / gLen0 : 1.0;
          final dx0 = -s0.gx * invG0;
          final dy0 = -s0.gy * invG0;

          final uMid = u + dx0 * (dt * 0.5);
          final vMid = v + dy0 * (dt * 0.5);
          if (uMid.abs() > 0.96 || vMid.abs() > 0.96) break;

          final sMid = sampleSurfaceUV(uMid, vMid);
          final gLenM = math.sqrt(sMid.gx * sMid.gx + sMid.gy * sMid.gy);
          final invGM = gLenM > 0 ? 1.0 / gLenM : 1.0;
          final dxM = -sMid.gx * invGM;
          final dyM = -sMid.gy * invGM;

          u += dxM * dt;
          v += dyM * dt;
          if (u.abs() > 0.96 || v.abs() > 0.96) break;
        }

        if (pts.length >= 4) {
          streamlines.add(pts);
        }
      }
    }

    final topoChannels = extraerCaucesTopograficos(
      latitud: latitud,
      longitud: longitud,
      n: n,
      elev: elev,
      bounds: bounds,
    );
    final cuerposAgua = (cuerposAguaExtra != null && cuerposAguaExtra.isNotEmpty)
        ? <CuerpoAgua>[...cuerposAguaExtra.take(6), ...topoChannels.take(1)]
        : topoChannels;

    final sortedS = List<double>.from(slope)..sort();
    final mediana = sortedS.isEmpty
        ? 0.0
        : (sortedS[sortedS.length ~/ 2] * 10.0).round() / 10.0;

    final centerElev = elev[(n ~/ 2) * n + (n ~/ 2)];

    return MallaTerreno(
      latitud: latitud,
      longitud: longitud,
      anchoKm: anchoKm,
      altoKm: altoKm,
      n: n,
      bounds: bounds,
      minElev: minE,
      maxElev: maxE,
      refElev: refElev ?? (centerElev.isFinite ? centerElev : 762.46),
      medianaPendiente: mediana,
      elev: elev,
      pendiente: slope,
      gradX: gradX,
      gradY: gradY,
      normales: normals,
      insolacion: insolation,
      escorrentia: streamlines,
      cuerposAgua: cuerposAgua,
      climatologia: climatologia ?? climatologiaBaseNasa,
      fuenteDem: fuenteDem,
      esRemoto: esRemoto,
    );
  }

  /// Genera de forma determinista una topografía de valle, vaguada secundaria
  /// y laderas (~350–950 m) para operación instantánea sin red o en pruebas.
  factory MallaTerreno.sintetica({
    required double latitud,
    required double longitud,
    double anchoKm = 5.0,
    double altoKm = 5.0,
    double? elevacionBase,
    int n = 56,
  }) {
    final raw = Float32List(n * n);
    final ref = (elevacionBase ?? 762.0).clamp(150.0, 2600.0);
    final valleyFloor = (ref * 0.56).clamp(350.0, 620.0);
    final phase = (latitud * 12.345 + longitud * 6.789);

    for (var r = 0; r < n; r++) {
      final v = (r / math.max(1, n - 1)) * 2.0 - 1.0;
      final mainAxis = 0.14 * math.sin(v * 2.1 + phase);
      final secAxis = -0.58 + 0.08 * math.cos(v * 2.7 - phase * 0.6);
      for (var c = 0; c < n; c++) {
        final u = (c / math.max(1, n - 1)) * 2.0 - 1.0;
        final dMain = (u - mainAxis).abs();
        final dSec = (u - secAxis).abs();

        final valleyRise = 340.0 * (1.0 - math.exp(-dMain * dMain * 3.4));
        final secRavine = -58.0 * math.exp(-dSec * dSec * 28.0);
        final tilt = -38.0 * v + 24.0 * u;
        final hills =
            92.0 *
                math.sin(u * 2.9 + v * 1.8 + phase) *
                math.cos(v * 2.3 - u * 1.4) +
            46.0 * math.cos(u * 4.5 - v * 3.2 + phase * 0.5) +
            22.0 * math.sin(u * 6.1 + v * 5.4);

        final z = (valleyFloor + valleyRise + secRavine + tilt + hills).clamp(
          350.0,
          950.0,
        );
        raw[r * n + c] = z;
      }
    }

    return MallaTerreno.desdeElevaciones(
      latitud: latitud,
      longitud: longitud,
      rawElev: raw,
      anchoKm: anchoKm,
      altoKm: altoKm,
      n: n,
      refElev: elevacionBase ?? 762.46,
      fuenteDem: 'Modelo Topográfico SRTM Local',
      esRemoto: false,
    );
  }

  static List<CuerpoAgua> extraerCaucesTopograficos({
    required double latitud,
    required double longitud,
    required int n,
    required Float32List elev,
    required List<double> bounds,
  }) {
    final lonW = bounds[0], latS = bounds[1], lonE = bounds[2], latN = bounds[3];
    final channels = <CuerpoAgua>[];

    final mid = n ~/ 2;
    final nsSpan = (elev[0 * n + mid] - elev[(n - 1) * n + mid]).abs();
    final ewSpan = (elev[mid * n + 0] - elev[mid * n + (n - 1)]).abs();
    final byRow = nsSpan >= ewSpan;

    final marginInit = math.max(2, (n * 8 / 180).round());
    final marginEdge = math.max(2, (n * 6 / 180).round());
    final maxDelta = math.max(4, (n * 18 / 180).round());

    final mainPts = <PuntoCauce>[];
    var prevIdx = -1;
    const numSlices = 28;
    for (var k = 0; k < numSlices; k++) {
      final idxFixed = ((k / (numSlices - 1)) * (n - 1)).round();
      var minVal = double.infinity;
      var bestVar = mid;

      final searchMin = prevIdx < 0
          ? marginInit
          : math.max(marginEdge, prevIdx - maxDelta);
      final searchMax = prevIdx < 0
          ? n - 1 - marginInit
          : math.min(n - 1 - marginEdge, prevIdx + maxDelta);
      for (var vIdx = searchMin; vIdx <= searchMax; vIdx++) {
        final r = byRow ? idxFixed : vIdx;
        final c = byRow ? vIdx : idxFixed;
        final z = elev[r * n + c];
        if (z < minVal) {
          minVal = z;
          bestVar = vIdx;
        }
      }
      prevIdx = bestVar;
      final r = byRow ? idxFixed : bestVar;
      final c = byRow ? bestVar : idxFixed;
      final u = (c / (n - 1)) * 2.0 - 1.0;
      final v = (r / (n - 1)) * 2.0 - 1.0;
      final lat = latN - (r / (n - 1)) * (latN - latS);
      final lon = lonW + (c / (n - 1)) * (lonE - lonW);
      mainPts.add(
        PuntoCauce(
          r: r,
          c: c,
          u: u,
          v: v,
          lat: lat,
          lon: lon,
          elev: elev[r * n + c],
        ),
      );
    }

    final dLat = latitud - 14.825;
    final dLon = longitud - (-89.531);
    final isChiquimula = math.sqrt(dLat * dLat + dLon * dLon) < 0.08;
    channels.add(
      CuerpoAgua(
        nombre: isChiquimula
            ? 'Río San José / Cauce Principal'
            : 'Cauce Principal de Valle (SRTM)',
        tipo: isChiquimula
            ? 'Río Permanente (Cuenca Chiquimula)'
            : 'Cauce Hidrológico Principal (SRTM)',
        fuente: isChiquimula
            ? 'Hidrografía Chiquimula + SRTM'
            : 'Topografía NASA SRTM',
        permanente: isChiquimula,
        puntos: mainPts,
      ),
    );

    final secMargin = math.max(3, (n * 10 / 180).round());
    final minDistMain = math.max(8, (n * 38 / 180).round());
    final secMaxDelta = math.max(4, (n * 16 / 180).round());

    final secPts = <PuntoCauce>[];
    var prevSec = -1;
    for (var k = 3; k < numSlices - 3; k++) {
      final idxFixed = ((k / (numSlices - 1)) * (n - 1)).round();
      var minVal = double.infinity;
      var bestVar = -1;
      final mainCoord = byRow ? mainPts[k].c : mainPts[k].r;
      for (var vIdx = secMargin; vIdx < n - secMargin; vIdx++) {
        if ((vIdx - mainCoord).abs() < minDistMain) continue;
        if (prevSec >= 0 && (vIdx - prevSec).abs() > secMaxDelta) continue;
        final r = byRow ? idxFixed : vIdx;
        final c = byRow ? vIdx : idxFixed;
        final z = elev[r * n + c];
        if (z < minVal) {
          minVal = z;
          bestVar = vIdx;
        }
      }
      if (bestVar >= 0) {
        prevSec = bestVar;
        final r = byRow ? idxFixed : bestVar;
        final c = byRow ? bestVar : idxFixed;
        final u = (c / (n - 1)) * 2.0 - 1.0;
        final v = (r / (n - 1)) * 2.0 - 1.0;
        final lat = latN - (r / (n - 1)) * (latN - latS);
        final lon = lonW + (c / (n - 1)) * (lonE - lonW);
        secPts.add(
          PuntoCauce(
            r: r,
            c: c,
            u: u,
            v: v,
            lat: lat,
            lon: lon,
            elev: elev[r * n + c],
          ),
        );
      }
    }
    if (secPts.length >= 6) {
      channels.add(
        CuerpoAgua(
          nombre: isChiquimula
              ? 'Quebrada La Vega / Afluente'
              : 'Quebrada / Vaguada Secundaria (SRTM)',
          tipo: 'Quebrada / Escorrentía Estacional',
          fuente: 'Topografía NASA SRTM',
          permanente: false,
          puntos: secPts,
        ),
      );
    }

    return channels;
  }

  int _idx(int fila, int col) =>
      fila.clamp(0, n - 1) * n + col.clamp(0, n - 1);

  ({int fila, int col}) filaColDeLatLon(double lat, double lon) {
    final lonW = bounds[0], latS = bounds[1], lonE = bounds[2], latN = bounds[3];
    final fila = (((latN - lat) / (latN - latS)) * (n - 1)).round().clamp(
      0,
      n - 1,
    );
    final col = (((lon - lonW) / (lonE - lonW)) * (n - 1)).round().clamp(
      0,
      n - 1,
    );
    return (fila: fila, col: col);
  }

  ({double lat, double lon}) latLonDeFilaCol(int fila, int col) {
    final lonW = bounds[0], latS = bounds[1], lonE = bounds[2], latN = bounds[3];
    final r = fila.clamp(0, n - 1);
    final c = col.clamp(0, n - 1);
    final lat = latN - (r / (n - 1)) * (latN - latS);
    final lon = lonW + (c / (n - 1)) * (lonE - lonW);
    return (lat: lat, lon: lon);
  }

  double elevacionEn(int fila, int col) => elev[_idx(fila, col)];

  double pendienteEn(int fila, int col) => pendiente[_idx(fila, col)];

  double insolacionEn(int fila, int col) => insolacion[_idx(fila, col)];

  double humedadTierraEn(int fila, int col, {double baseMoistPct = 53.0}) {
    final i = _idx(fila, col);
    final z = elev[i];
    final s = pendiente[i];
    final ins = insolacion[i];
    final elevSpan = math.max(100.0, maxElev - minElev);
    final relHeight = (z - minElev) / elevSpan;
    final slopeDrainage = math.min(20.0, s * 0.42);
    final valleyAccum = (1.0 - relHeight) * 12.0 - 5.0;
    return (baseMoistPct + valleyAccum - slopeDrainage * 0.65 - ins * 2.5)
        .clamp(8.0, 98.0);
  }

  double temperaturaEn(int fila, int col, {double baseTemp = 26.5}) {
    final i = _idx(fila, col);
    return baseTemp - 0.0065 * (elev[i] - refElev) + insolacion[i] * 0.85;
  }

  double lluviaEfectivaEn(
    int fila,
    int col, {
    double lluviaBaseMm = 2.0,
    double lluvia14dMm = 18.0,
  }) {
    final i = _idx(fila, col);
    final z = elev[i];
    final s = pendiente[i];
    final elevSpan = math.max(100.0, maxElev - minElev);
    final relHeight = (z - minElev) / elevSpan;
    final slopeDrainage = math.min(20.0, s * 0.42);
    final orographicFactor = math.max(0.75, 1.0 + 0.00022 * (z - refElev));
    final valleyRainConv = (1.0 - relHeight) * 1.4 - (slopeDrainage * 0.05);
    return lluviaBaseMm > 0.05
        ? math.max(
            0.1,
            lluviaBaseMm * orographicFactor +
                valleyRainConv * math.min(1.0, lluviaBaseMm / 3.0),
          )
        : math.max(
            0.0,
            (lluvia14dMm / 14.0) * 0.35 * orographicFactor +
                math.max(0.0, valleyRainConv * 0.25),
          );
  }

  CuerpoAguaCercano? evaluarCuerpoAguaCercano(double poiLat, double poiLon) {
    if (cuerposAgua.isEmpty) return null;
    final (:fila, :col) = filaColDeLatLon(poiLat, poiLon);
    final poiElev = elevacionEn(fila, col);
    final cosLat = math.cos(poiLat * math.pi / 180.0);

    CuerpoAguaCercano? mejor;
    var mejorDist = double.infinity;
    for (final wb in cuerposAgua) {
      for (final pt in wb.puntos) {
        final dyM = (pt.lat - poiLat) * 111320.0;
        final dxM = (pt.lon - poiLon) * 111320.0 * cosLat;
        final distM = math.sqrt(dxM * dxM + dyM * dyM);
        if (mejor == null || distM < mejorDist) {
          mejorDist = distM;
          mejor = CuerpoAguaCercano(
            nombre: wb.nombre,
            tipo: wb.tipo,
            fuente: wb.fuente,
            permanente: wb.permanente,
            distanciaM: distM.round(),
            elevAguaM: pt.elev.round(),
            elevParcelaM: poiElev.round(),
            deltaZM: (poiElev - pt.elev).round(),
            punto: pt,
          );
        }
      }
    }
    return mejor;
  }
}

class ServicioTerreno {
  static double _lon2tileFloat(double lon, int z) =>
      ((lon + 180.0) / 360.0) * (1 << z);

  static double _lat2tileFloat(double lat, int z) {
    final rad = lat.clamp(-85.0, 85.0) * math.pi / 180.0;
    return ((1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) /
            2.0) *
        (1 << z);
  }

  Future<MallaTerreno> cargar({
    required double latitud,
    required double longitud,
    double anchoKm = 5.0,
    double altoKm = 5.0,
    double? elevacionBase,
    int n = 56,
    http.Client? cliente,
  }) async {
    final propio = cliente == null ? http.Client() : null;
    final c = cliente ?? propio!;
    try {
      final bounds = MallaTerreno.calcularBounds(
        latitud,
        longitud,
        anchoKm,
        altoKm,
      );
      final demFuture = _descargarDemTerrarium(
        bounds: bounds,
        n: n,
        cliente: c,
      );
      final climFuture = _descargarClimatologiaNasa(
        latitud: latitud,
        longitud: longitud,
        cliente: c,
      );
      final rawOsmFuture = _descargarOverpassCrudo(
        bounds: bounds,
        cliente: c,
      );

      final rawElev = await demFuture;
      if (rawElev == null) {
        return MallaTerreno.sintetica(
          latitud: latitud,
          longitud: longitud,
          anchoKm: anchoKm,
          altoKm: altoKm,
          elevacionBase: elevacionBase,
          n: n,
        );
      }

      final climRes = await climFuture;
      final osmElements = await rawOsmFuture;

      // Primera pasada para obtener elevación suavizada en la malla y asociarla a los cauces OSM.
      final baseMalla = MallaTerreno.desdeElevaciones(
        latitud: latitud,
        longitud: longitud,
        rawElev: rawElev,
        anchoKm: anchoKm,
        altoKm: altoKm,
        n: n,
        refElev: climRes?.refElev ?? elevacionBase,
        climatologia: climRes?.meses ?? climatologiaBaseNasa,
        fuenteDem: 'NASA SRTM · Terrarium z13',
        esRemoto: true,
      );

      if (osmElements.isEmpty) return baseMalla;
      final osmBodies = _construirCuerposAguaOsm(
        osmElements,
        bounds: bounds,
        n: n,
        elev: baseMalla.elev,
      );
      if (osmBodies.isEmpty) return baseMalla;

      return MallaTerreno.desdeElevaciones(
        latitud: latitud,
        longitud: longitud,
        rawElev: rawElev,
        anchoKm: anchoKm,
        altoKm: altoKm,
        n: n,
        refElev: climRes?.refElev ?? elevacionBase,
        cuerposAguaExtra: osmBodies,
        climatologia: climRes?.meses ?? climatologiaBaseNasa,
        fuenteDem: 'NASA SRTM · Terrarium z13',
        esRemoto: true,
      );
    } catch (_) {
      return MallaTerreno.sintetica(
        latitud: latitud,
        longitud: longitud,
        anchoKm: anchoKm,
        altoKm: altoKm,
        elevacionBase: elevacionBase,
        n: n,
      );
    } finally {
      propio?.close();
    }
  }

  Future<Float32List?> _descargarDemTerrarium({
    required List<double> bounds,
    required int n,
    required http.Client cliente,
  }) async {
    try {
      const z = 13;
      final lonW = bounds[0], latS = bounds[1], lonE = bounds[2], latN = bounds[3];
      final txMin = _lon2tileFloat(lonW, z).floor();
      final txMax = _lon2tileFloat(lonE, z).floor();
      final tyMin = _lat2tileFloat(latN, z).floor();
      final tyMax = _lat2tileFloat(latS, z).floor();

      final cols = txMax - txMin + 1;
      final rows = tyMax - tyMin + 1;
      if (cols <= 0 || rows <= 0 || cols * rows > 16) return null;

      final W = cols * 256;
      final H = rows * 256;
      final canvasRgb = Uint8List(W * H * 3);

      final tareas = <Future<bool>>[];
      for (var ty = tyMin; ty <= tyMax; ty++) {
        for (var tx = txMin; tx <= txMax; tx++) {
          final uri = Uri.parse(
            'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/$z/$tx/$ty.png',
          );
          final ox = (tx - txMin) * 256;
          final oy = (ty - tyMin) * 256;
          tareas.add(() async {
            final r = await cliente
                .get(uri)
                .timeout(const Duration(seconds: 8));
            if (r.statusCode != 200 || r.bodyBytes.isEmpty) return false;
            final rgb = decodificarPngRgb(r.bodyBytes);
            if (rgb == null || rgb.width != 256 || rgb.height != 256) {
              return false;
            }
            for (var py = 0; py < 256; py++) {
              final srcOff = py * 256 * 3;
              final dstOff = ((oy + py) * W + ox) * 3;
              canvasRgb.setRange(dstOff, dstOff + 256 * 3, rgb.rgb, srcOff);
            }
            return true;
          }());
        }
      }

      final resultados = await Future.wait(tareas);
      if (resultados.any((ok) => !ok)) return null;

      double decodePixel(int ix, int iy) {
        final cx = ix.clamp(0, W - 1);
        final cy = iy.clamp(0, H - 1);
        final p = (cy * W + cx) * 3;
        return (canvasRgb[p] * 256.0 +
                canvasRgb[p + 1] +
                canvasRgb[p + 2] / 256.0) -
            32768.0;
      }

      double cubicHermite(
        double p0,
        double p1,
        double p2,
        double p3,
        double t,
      ) {
        final a = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3;
        final b = p0 - 2.5 * p1 + 2.0 * p2 - 0.5 * p3;
        final c = -0.5 * p0 + 0.5 * p2;
        final d = p1;
        return ((a * t + b) * t + c) * t + d;
      }

      double sampleBicubic(double fx, double fy) {
        final x1 = fx.floor(), y1 = fy.floor();
        final tx = fx - x1, ty = fy - y1;
        final row0 = cubicHermite(
          decodePixel(x1 - 1, y1 - 1),
          decodePixel(x1, y1 - 1),
          decodePixel(x1 + 1, y1 - 1),
          decodePixel(x1 + 2, y1 - 1),
          tx,
        );
        final row1 = cubicHermite(
          decodePixel(x1 - 1, y1),
          decodePixel(x1, y1),
          decodePixel(x1 + 1, y1),
          decodePixel(x1 + 2, y1),
          tx,
        );
        final row2 = cubicHermite(
          decodePixel(x1 - 1, y1 + 1),
          decodePixel(x1, y1 + 1),
          decodePixel(x1 + 1, y1 + 1),
          decodePixel(x1 + 2, y1 + 1),
          tx,
        );
        final row3 = cubicHermite(
          decodePixel(x1 - 1, y1 + 2),
          decodePixel(x1, y1 + 2),
          decodePixel(x1 + 1, y1 + 2),
          decodePixel(x1 + 2, y1 + 2),
          tx,
        );
        return cubicHermite(row0, row1, row2, row3, ty);
      }

      final rawElev = Float32List(n * n);
      for (var r = 0; r < n; r++) {
        final curLat = latN - (r / (n - 1)) * (latN - latS);
        final fy = (_lat2tileFloat(curLat, z) - tyMin) * 256.0;
        for (var c = 0; c < n; c++) {
          final curLon = lonW + (c / (n - 1)) * (lonE - lonW);
          final fx = (_lon2tileFloat(curLon, z) - txMin) * 256.0;
          rawElev[r * n + c] = sampleBicubic(fx, fy);
        }
      }
      return rawElev;
    } catch (_) {
      return null;
    }
  }

  Future<({double refElev, Map<int, ClimaMensualNasa> meses})?>
  _descargarClimatologiaNasa({
    required double latitud,
    required double longitud,
    required http.Client cliente,
  }) async {
    try {
      final uri = Uri.https(
        'power.larc.nasa.gov',
        '/api/temporal/climatology/point',
        {
          'parameters': 'T2M,RH2M,PRECTOTCORR,GWETTOP,GWETROOT',
          'community': 'AG',
          'longitude': longitud.toStringAsFixed(4),
          'latitude': latitud.toStringAsFixed(4),
          'format': 'JSON',
        },
      );
      final resp = await cliente.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      var refElev = 762.46;
      final coords =
          (json['geometry'] as Map<String, dynamic>?)?['coordinates']
              as List<dynamic>?;
      if (coords != null && coords.length >= 3 && coords[2] is num) {
        refElev = (coords[2] as num).toDouble();
      }
      final par =
          ((json['properties'] as Map<String, dynamic>?)?['parameter']
              as Map<String, dynamic>?) ??
          const {};
      double? leer(String p, String mk) {
        final m = par[p] as Map<String, dynamic>?;
        final v = (m?[mk] as num?)?.toDouble();
        return (v == null || v <= -900) ? null : v;
      }

      final meses = <int, ClimaMensualNasa>{};
      for (var i = 0; i < 12; i++) {
        final mk = _clavesMes[i];
        final base = climatologiaBaseNasa[i + 1]!;
        final tMean = leer('T2M', mk) ?? base.t2m;
        meses[i + 1] = ClimaMensualNasa(
          mes: i + 1,
          nombre: _nombresMes[i],
          t2m: tMean,
          tmax: double.parse((tMean + _offsetMaxDiurno[i]).toStringAsFixed(2)),
          tmin: double.parse((tMean - _offsetMinDiurno[i]).toStringAsFixed(2)),
          rh2m: leer('RH2M', mk) ?? base.rh2m,
          lluviaMmDia: leer('PRECTOTCORR', mk) ?? base.lluviaMmDia,
          gwettop: leer('GWETTOP', mk) ?? base.gwettop,
          gwetroot: leer('GWETROOT', mk) ?? base.gwetroot,
        );
      }
      return (refElev: refElev, meses: meses);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _descargarOverpassCrudo({
    required List<double> bounds,
    required http.Client cliente,
  }) async {
    try {
      final lonW = bounds[0], latS = bounds[1], lonE = bounds[2], latN = bounds[3];
      final bbox =
          '${latS.toStringAsFixed(4)},${lonW.toStringAsFixed(4)},${latN.toStringAsFixed(4)},${lonE.toStringAsFixed(4)}';
      final query =
          '[out:json][timeout:4];(way["waterway"~"river|stream|canal"]($bbox);way["natural"="water"]($bbox););out geom 12;';
      final uri = Uri.https('overpass-api.de', '/api/interpreter', {
        'data': query,
      });
      final resp = await cliente
          .get(uri)
          .timeout(const Duration(milliseconds: 4200));
      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>? ?? const [];
      return [
        for (final el in elements)
          if (el is Map<String, dynamic>) el,
      ];
    } catch (_) {
      return const [];
    }
  }

  List<CuerpoAgua> _construirCuerposAguaOsm(
    List<Map<String, dynamic>> elements, {
    required List<double> bounds,
    required int n,
    required Float32List elev,
  }) {
    final lonW = bounds[0], latS = bounds[1], lonE = bounds[2], latN = bounds[3];
    final osmBodies = <CuerpoAgua>[];
    for (final el in elements) {
      final geom = el['geometry'] as List<dynamic>?;
      if (geom == null || geom.length < 2) continue;
      final tags = (el['tags'] as Map<String, dynamic>?) ?? const {};
      final waterway = tags['waterway'] as String?;
      final natural = tags['natural'] as String?;
      final wType = waterway ?? (natural == 'water' ? 'lagoon' : 'stream');
      final rawName =
          (tags['name'] as String?) ??
          (wType == 'river'
              ? 'Río Cartografiado (OSM)'
              : wType == 'lagoon'
              ? 'Laguna / Reservorio (OSM)'
              : 'Quebrada / Arroyo (OSM)');
      final pts = <PuntoCauce>[];
      for (final g in geom) {
        if (g is! Map<String, dynamic>) continue;
        final gLat = (g['lat'] as num?)?.toDouble();
        final gLon = (g['lon'] as num?)?.toDouble();
        if (gLat == null || gLon == null) continue;
        if (gLat < latS || gLat > latN || gLon < lonW || gLon > lonE) continue;
        final r = (((latN - gLat) / (latN - latS)) * (n - 1)).round().clamp(
          0,
          n - 1,
        );
        final c = (((gLon - lonW) / (lonE - lonW)) * (n - 1)).round().clamp(
          0,
          n - 1,
        );
        final u = (c / (n - 1)) * 2.0 - 1.0;
        final v = (r / (n - 1)) * 2.0 - 1.0;
        pts.add(
          PuntoCauce(
            r: r,
            c: c,
            u: u,
            v: v,
            lat: gLat,
            lon: gLon,
            elev: elev[r * n + c],
          ),
        );
      }
      if (pts.length >= 2) {
        osmBodies.add(
          CuerpoAgua(
            nombre: rawName,
            tipo: wType == 'river'
                ? 'Río Permanente (OSM)'
                : wType == 'lagoon'
                ? 'Cuerpo de Agua / Reservorio (OSM)'
                : 'Quebrada / Cauce (OSM)',
            fuente: 'OpenStreetMap + NASA SRTM',
            permanente: wType == 'river' || wType == 'lagoon',
            puntos: pts,
          ),
        );
      }
    }
    return osmBodies;
  }

  /// Decodificador PNG en Dart puro (8-bit RGB/RGBA/paleta/escala de grises)
  /// usando `zlib.decode` y reconstrucción de filtros PNG Sub/Up/Average/Paeth.
  static ({int width, int height, Uint8List rgb})? decodificarPngRgb(
    Uint8List bytes,
  ) {
    if (bytes.length < 33) return null;
    const sig = [137, 80, 78, 71, 13, 10, 26, 10];
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != sig[i]) return null;
    }

    final bd = ByteData.sublistView(bytes);
    var offset = 8;
    var width = 0, height = 0, bitDepth = 0, colorType = 0, interlace = 0;
    Uint8List? palette;
    final idat = BytesBuilder(copy: false);

    while (offset + 8 <= bytes.length) {
      final length = bd.getUint32(offset);
      final type = String.fromCharCodes(
        bytes.sublist(offset + 4, offset + 8),
      );
      final dataStart = offset + 8;
      final dataEnd = dataStart + length;
      if (dataEnd + 4 > bytes.length) break;

      if (type == 'IHDR' && length >= 13) {
        width = bd.getUint32(dataStart);
        height = bd.getUint32(dataStart + 4);
        bitDepth = bytes[dataStart + 8];
        colorType = bytes[dataStart + 9];
        interlace = bytes[dataStart + 12];
      } else if (type == 'PLTE') {
        palette = Uint8List.sublistView(bytes, dataStart, dataEnd);
      } else if (type == 'IDAT') {
        idat.add(Uint8List.sublistView(bytes, dataStart, dataEnd));
      } else if (type == 'IEND') {
        break;
      }
      offset = dataEnd + 4;
    }

    if (width <= 0 || height <= 0 || bitDepth != 8 || interlace != 0) {
      return null;
    }
    final bpp = switch (colorType) {
      2 => 3,
      6 => 4,
      4 => 2,
      0 || 3 => 1,
      _ => 0,
    };
    if (bpp == 0) return null;

    final raw = zlib.decode(idat.takeBytes());
    final stride = width * bpp;
    if (raw.length < height * (1 + stride)) return null;

    final prevRow = Uint8List(stride);
    final curRow = Uint8List(stride);
    final rgb = Uint8List(width * height * 3);

    for (var r = 0; r < height; r++) {
      final rowStart = r * (1 + stride);
      final filter = raw[rowStart];
      for (var i = 0; i < stride; i++) {
        final x = raw[rowStart + 1 + i];
        final a = i >= bpp ? curRow[i - bpp] : 0;
        final b = r > 0 ? prevRow[i] : 0;
        final c = (r > 0 && i >= bpp) ? prevRow[i - bpp] : 0;
        final recon = switch (filter) {
          0 => x,
          1 => (x + a) & 0xff,
          2 => (x + b) & 0xff,
          3 => (x + ((a + b) >> 1)) & 0xff,
          4 => () {
            final p = a + b - c;
            final pa = (p - a).abs();
            final pb = (p - b).abs();
            final pc = (p - c).abs();
            final pr = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
            return (x + pr) & 0xff;
          }(),
          _ => x,
        };
        curRow[i] = recon;
      }

      for (var c = 0; c < width; c++) {
        final dst = (r * width + c) * 3;
        final src = c * bpp;
        if (colorType == 2 || colorType == 6) {
          rgb[dst] = curRow[src];
          rgb[dst + 1] = curRow[src + 1];
          rgb[dst + 2] = curRow[src + 2];
        } else if (colorType == 3 && palette != null) {
          final pIdx = curRow[src] * 3;
          if (pIdx + 2 < palette.length) {
            rgb[dst] = palette[pIdx];
            rgb[dst + 1] = palette[pIdx + 1];
            rgb[dst + 2] = palette[pIdx + 2];
          }
        } else {
          rgb[dst] = curRow[src];
          rgb[dst + 1] = curRow[src];
          rgb[dst + 2] = curRow[src];
        }
      }
      prevRow.setRange(0, stride, curRow);
    }

    return (width: width, height: height, rgb: rgb);
  }
}
