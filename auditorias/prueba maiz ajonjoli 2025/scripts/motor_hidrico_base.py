"""Hindcast exploratorio de agua y calendario; no predicción de rendimiento ni diagnóstico.

Ejecutar desde la raíz con Python, numpy, Pillow y matplotlib.
Si se instalaron dependencias en tmp/sim-deps se incorporan solo a este proceso.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if (ROOT / 'tmp/sim-deps').exists():
    sys.path.insert(0, str(ROOT / 'tmp/sim-deps'))
import csv
import hashlib
import itertools
import json
import math
from datetime import date, datetime, timedelta, timezone
from statistics import mean
import numpy as np
from PIL import Image
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

BASE = ROOT / 'datos/escenarios/chiquimula_2025'
OUT = ROOT / 'investigacion/escenarios-chiquimula-2025'
OUT.mkdir(parents=True, exist_ok=True)
LAT, LON = 14.8250, -89.5312
DAYS = [date(2025, 1, 1) + timedelta(days=i) for i in range(365)]
LABELS = {'imerg': 'NASA IMERG V07 Late', 'chirps': 'CHIRPS v2', 'era5': 'ERA5', 'power': 'NASA POWER'}


def load(p):
    return json.loads(Path(p).read_text(encoding='utf-8'))


def write_json(p, obj):
    Path(p).write_text(json.dumps(obj, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8')


def write_csv(p, rows):
    with Path(p).open('w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


def sample_tiff(p):
    im = Image.open(p)
    sx, sy, _ = im.tag_v2[33550]
    tie = im.tag_v2[33922]
    col, row = int((LON-tie[3])/sx+tie[0]), int((tie[4]-LAT)/sy+tie[1])
    assert 0 <= col < im.width and 0 <= row < im.height, str(p)
    value = float(im.getpixel((col, row)))
    assert math.isfinite(value) and value >= 0, (p, value)
    return value


def inside_ring(pt, ring):
    x, y = pt
    inside = False
    for a, b in zip(ring, ring[1:]+ring[:1]):
        if (a[1] > y) != (b[1] > y) and x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:
            inside = not inside
    return inside


def in_geometry(g):
    polys = [g['coordinates']] if g['type'] == 'Polygon' else g['coordinates']
    return any(inside_ring((LON, LAT), p[0]) and not any(inside_ring((LON, LAT), h) for h in p[1:]) for p in polys)


def static_site():
    depths = [('0-5cm', 0, 5), ('5-15cm', 5, 15), ('15-30cm', 15, 30), ('30-60cm', 30, 60), ('60-100cm', 60, 100)]
    soil = []
    for dep, a, b in depths:
        values = {p: sample_tiff(BASE / 'suelo_wcs' / f'{p}_{dep}.tif')/factor for p, factor in [('wv0033', 1000), ('wv1500', 1000), ('cfvo', 10)]}
        assert 0 <= values['wv1500'] < values['wv0033'] < 1
        soil.append({'profundidad': dep, 'desde_m': a/100, 'hasta_m': b/100, **values, 'agua_disponible_mm': (b-a)*10*(values['wv0033']-values['wv1500'])})
    surface = {p: sample_tiff(BASE / 'suelo_wcs' / f'{p}_0-5cm.tif')/factor for p, factor in [('clay', 10), ('sand', 10), ('silt', 10), ('phh2o', 10), ('soc', 10), ('bdod', 100)]}
    cover = load(ROOT / 'datos/maga/chiquimula_cobertura_uso_tierra_2025.geojson')
    matches = [f['properties'] for f in cover['features'] if in_geometry(f['geometry'])]
    thematic = {}
    for layer in ['fisiografia', 'taxonomia_suelos', 'capacidad_uso_tierra_usda', 'amenaza_sequia', 'zonas_de_vida']:
        data = load(ROOT / 'datos/maga' / f'chiquimula_{layer}.geojson')
        thematic[layer] = [f['properties'] for f in data['features'] if in_geometry(f['geometry'])]
    dsm_path = ROOT / 'datos/relieve/chiquimula_aw3d30_dsm.tif'
    elev = sample_tiff(dsm_path)
    im = Image.open(dsm_path)
    arr = np.array(im, dtype=float)
    sx, sy, _ = im.tag_v2[33550]
    tie = im.tag_v2[33922]
    col, row = int((LON-tie[3])/sx), int((tie[4]-LAT)/sy)
    dx, dy = sx*111320*math.cos(math.radians(LAT)), sy*111320
    patch = arr[row-1:row+2, col-1:col+2]
    dzdx = ((patch[0, 2]+2*patch[1, 2]+patch[2, 2])-(patch[0, 0]+2*patch[1, 0]+patch[2, 0]))/(8*dx)
    dzdy = ((patch[2, 0]+2*patch[2, 1]+patch[2, 2])-(patch[0, 0]+2*patch[0, 1]+patch[0, 2]))/(8*dy)
    wc = sample_tiff(ROOT / 'datos/cobertura/chiquimula_worldcover2021.tif')
    result = {'lat': LAT, 'lon': LON, 'caracter': 'candidato agrícola elegido por el usuario; sin delimitación de finca ni verificación de campo', 'elevacion_dsm_m': elev, 'pendiente_dsm_local_pct': 100*math.hypot(dzdx, dzdy), 'maga_cobertura_2025_en_punto': matches, 'worldcover_2021_clase': wc, 'suelo_superficial_estimado': surface, 'perfil_soilgrids': soil, 'agua_disponible_0_100cm_mm': sum(x['agua_disponible_mm'] for x in soil), 'fuentes_estaticas': 'SoilGrids 2.0 WCS; MAGA cobertura 2025; JAXA AW3D30 v4.1; ESA WorldCover 2021 v200', 'limites': ['DSM incluye vegetación y construcciones; pendiente no mide drenaje ni inundabilidad.', 'SoilGrids es predicción espacial estática, no análisis del suelo en 2025.', 'wv0033 se usa como aproximación de capacidad de campo, no medición de campo.', 'No se aplica una corrección adicional por fragmentos gruesos a wv; almacenamiento se perturba en sensibilidad.', 'Las discrepancias MAGA/WorldCover no demuestran cuál clasificación es correcta en campo.']}
    result['contexto_tematico_maga'] = thematic
    result['unidades'] = {'clay_sand_silt_cfvo': '%', 'wv0033_wv1500': 'm³/m³', 'soc': 'g/kg', 'bdod': 'g/cm³', 'phh2o': 'pH', 'agua_disponible': 'mm'}
    write_json(BASE / 'sitio_y_suelo.json', result)
    write_csv(BASE / 'perfil_suelo.csv', soil)
    return result, soil


def et0_fao(r, elevation):
    """FAO-56 ecuaciones 6, 11, 13, 14, 21, 23, 25, 37–40. G diario = 0."""
    tmax, tmin = r['T2M_MAX'], r['T2M_MIN']
    t = (tmax+tmin)/2
    es = lambda v: .6108*math.exp(17.27*v/(v+237.3))
    ea = es(r['T2MDEW'])
    vapour = max(0, (es(tmax)+es(tmin))/2-ea)
    delta = 4098*es(t)/(t+237.3)**2
    pressure_site = 101.3*((293-.0065*elevation)/293)**5.26  # FAO-56 ec. 7; PS regional se conserva como dato bruto.
    gamma = .000665*pressure_site
    doy = date.fromisoformat(r['fecha']).timetuple().tm_yday
    phi = math.radians(LAT)
    dr = 1+.033*math.cos(2*math.pi*doy/365)
    dec = .409*math.sin(2*math.pi*doy/365-1.39)
    omega = math.acos(-math.tan(phi)*math.tan(dec))
    ra = 24*60/math.pi*.0820*dr*(omega*math.sin(phi)*math.sin(dec)+math.cos(phi)*math.cos(dec)*math.sin(omega))
    rso = (.75+2e-5*elevation)*ra
    rs = r['ALLSKY_SFC_SW_DWN']  # API community AG: MJ/m²/día; no multiplicar por 3.6.
    rnl = 4.903e-9*((tmax+273.16)**4+(tmin+273.16)**4)/2*(.34-.14*math.sqrt(ea))*(1.35*min(1, max(.3, rs/rso))-.35)
    rn = .77*rs-rnl
    value = (.408*delta*rn+gamma*900/(t+273)*r['WS2M']*vapour)/(delta+gamma*(1+.34*r['WS2M']))
    return max(0, value)


def weather(elevation):
    power, era = load(BASE/'power_2025.json'), load(BASE/'era5_2025.json')
    pars = power['properties']['parameter']
    assert power['parameters']['ALLSKY_SFC_SW_DWN']['units'] == 'MJ/m^2/day'
    assert power['parameters']['PS']['units'] == 'kPa'
    rains = {}
    for key, filename in [('imerg', 'imerg_v07_late'), ('chirps', 'chirps_v2')]:
        j = load(BASE/(filename+'_2025.json'))
        assert j['datatype'] == (226 if key == 'imerg' else 0), j['datatype']
        rows = {date(x['year'], x['month'], x['day']): x['value']['avg'] for x in j['data']}
        assert len(rows) == 365 and set(rows) == set(DAYS)
        assert all(isinstance(v, (float, int)) and v >= 0 and math.isfinite(v) for v in rows.values())
        rains[key] = rows
    ed = {date.fromisoformat(d): i for i, d in enumerate(era['daily']['time'])}
    assert set(ed) == set(DAYS)
    soil_h = era['hourly']
    daily_soil = {}
    for k in soil_h:
        if k == 'time':
            continue
        byday = {}
        for t, value in zip(soil_h['time'], soil_h[k]):
            assert value is not None
            byday.setdefault(t[:10], []).append(value)
        daily_soil[k] = {d: mean(vs) for d, vs in byday.items()}
    out = []
    for day in DAYS:
        key = day.strftime('%Y%m%d')
        row = {'fecha': day.isoformat(), **{p: values[key] for p, values in pars.items()}}
        assert all(isinstance(v, (float, int)) and v != -999 and math.isfinite(v) for p, v in row.items() if p != 'fecha')
        row.update({f'P_{k}_mm': rains[k][day] for k in rains})
        i = ed[day]
        row.update(P_power_mm=row['PRECTOTCORR'], P_era5_mm=era['daily']['precipitation_sum'][i], et0_era5_mm=era['daily']['et0_fao_evapotranspiration'][i], tmax_era5_C=era['daily']['temperature_2m_max'][i], tmin_era5_C=era['daily']['temperature_2m_min'][i])
        row['et0_power_fao56_mm'] = et0_fao(row, elevation)
        row.update({k: vals[row['fecha']] for k, vals in daily_soil.items()})
        out.append(row)
    write_csv(BASE/'entorno_diario_2025.csv', out)
    return out, power, era


def longest_dry(rows, rain_key):
    best, run = [], []
    for r in rows:
        if r[rain_key] < 1:
            run.append(r)
            if len(run) > len(best):
                best = list(run)
        else:
            run = []
    return {'inicio': best[0]['fecha'], 'fin': best[-1]['fecha'], 'dias': len(best), 'lluvia_mm': sum(r[rain_key] for r in best)} if best else None


def events(rows):
    heat = max((rows[i:i+14] for i in range(352)), key=lambda w: mean(r['T2M_MAX'] for r in w))
    out = {'calor_14_dias_POWER': {'inicio': heat[0]['fecha'], 'fin': heat[-1]['fecha'], 'Tmax_media_C': mean(r['T2M_MAX'] for r in heat), 'Tmax_pico_C': max(r['T2M_MAX'] for r in heat)}, 'por_fuente_lluvia': {}}
    for key in LABELS:
        col = 'P_'+key+'_mm'
        wet = max((rows[i:i+7] for i in range(359)), key=lambda w: sum(r[col] for r in w))
        out['por_fuente_lluvia'][key] = {'acumulado_anual_mm': sum(r[col] for r in rows), 'racha_seca_mayo_octubre_P_menor_1mm': longest_dry([r for r in rows if '2025-05-01' <= r['fecha'] <= '2025-10-31'], col), 'semana_mas_lluviosa': {'inicio': wet[0]['fecha'], 'fin': wet[-1]['fecha'], 'lluvia_mm': sum(r[col] for r in wet)}}
    monthly = []
    for m in range(1, 13):
        sub = [r for r in rows if int(r['fecha'][5:7]) == m]
        monthly.append({'mes': f'2025-{m:02}', **{f'P_{k}_mm': sum(r[f'P_{k}_mm'] for r in sub) for k in LABELS}, 'Tmax_media_POWER_C': mean(r['T2M_MAX'] for r in sub), 'Tmin_media_POWER_C': mean(r['T2M_MIN'] for r in sub), 'et0_POWER_mm': sum(r['et0_power_fao56_mm'] for r in sub), 'GWETROOT_MEDIA': mean(r['GWETROOT'] for r in sub)})
    write_csv(OUT/'resumen_mensual.csv', monthly)
    out['mensual'] = monthly
    out['definiciones'] = 'Máximos dentro de las series de 2025; P<1 mm/día es umbral analítico de racha seca. No son diagnósticos de desastre, inicio de invierno ni canícula oficial.'
    write_json(OUT/'episodios_2025.json', out)
    return out


CROPS = {'maiz': {'stages': [20, 35, 40, 30], 'kc': [.30, 1.20, .35], 'zr': 1., 'p': .55}, 'frijol': {'stages': [15, 25, 35, 20], 'kc': [.40, 1.15, .35], 'zr': .60, 'p': .45}}
CALENDARS = [('FAO_125_95_mayo15', date(2025, 5, 15), False), ('corto_90_70_mayo15', date(2025, 5, 15), True), ('corto_90_70_junio01', date(2025, 6, 1), True), ('corto_90_70_junio15', date(2025, 6, 15), True)]
SEQS = [('maiz_solo', ['maiz']), ('maiz_frijol', ['maiz', 'frijol']), ('frijol_maiz', ['frijol', 'maiz'])]
SOILS = [('perfil_referencia', 1., 1.), ('raiz_limitada_40cm', .40, 1.), ('almacenamiento_menos25pct', 1., .75)]


def schedule(crops, start, short):
    result = []
    for crop in crops:
        params = dict(CROPS[crop])
        if short:
            params['stages'] = [14, 25, 29, 22] if crop == 'maiz' else [11, 18, 26, 15]
        length = sum(params['stages'])
        end = start+timedelta(days=length-1)
        assert end <= DAYS[-1], (crop, start, end)
        result.append({'crop': crop, 'start': start, 'end': end, 'params': params})
        start = end+timedelta(days=8)  # siete días completos de intervalo.
    return result


def kc_and_root(age, p):
    ini, dev, mid, late = p['stages']
    k0, km, ke = p['kc']
    if age < ini:
        kc = k0
    elif age < ini+dev:
        kc = k0+(km-k0)*(age-ini+1)/dev
    elif age < ini+dev+mid:
        kc = km
    else:
        kc = km+(ke-km)*(age-ini-dev-mid+1)/late
    zr = .15+(p['zr']-.15)*min(1, (age+1)/(ini+dev))
    return kc, zr


def simulate(rows, profile, rain, seqname, crops, cal, soil_case, runoff, init, irrigate, keep=False):
    calname, start, short = cal
    soilname, root_cap, store_factor = soil_case
    caps = [p['agua_disponible_mm']*store_factor for p in profile]
    state = [c*init for c in caps]
    sched = schedule(crops, start, short)
    totals = {k: 0. for k in ['P_mm', 'riego_neto_mm', 'escorrentia_supuesta_mm', 'drenaje_profundo_modelo_mm', 'ET_potencial_cultivo_mm', 'ET_real_cultivo_mm', 'deficit_ET_mm']}
    stress, active, mass_error = 0, 0, 0.
    details = []
    crop_summaries = [{k: 0. for k in ['ETc_mm', 'ETa_mm', 'deficit_mm', 'riego_mm', 'lluvia_mm', 'dias_Ks_menor_095', 'lluvia_ultimos10dias_mm']} for _ in sched]
    for weather_row, day in zip(rows, DAYS):
        before = sum(state)
        precipitation = weather_row[f'P_{rain}_mm']
        overflow, rain_runoff = precipitation*(1-runoff), precipitation*runoff
        for i, cap in enumerate(caps):
            added = min(cap-state[i], overflow)
            state[i] += added
            overflow -= added
        drain = overflow
        selected = next(((n, s) for n, s in enumerate(sched) if s['start'] <= day <= s['end']), None)
        crop = selected[1]['crop'] if selected else 'suelo_sin_cultivo'
        if selected:
            n, current = selected
            kc, zr = kc_and_root((day-current['start']).days, current['params'])
            zr = min(zr, root_cap)
            p0 = current['params']['p']
        else:
            kc, zr, p0 = .20, .15, .5
        rooted = [max(0, min(1, (zr-p['desde_m'])/(p['hasta_m']-p['desde_m']))) for p in profile]
        taw = sum(c*f for c, f in zip(caps, rooted))
        available = sum(s*f for s, f in zip(state, rooted))
        etc = kc*weather_row['et0_power_fao56_mm']
        p = min(.8, max(.1, p0+.04*(5-etc)))
        irrigation = 20. if selected and irrigate and available < (1-p)*taw else 0.
        to_add = irrigation
        for i, cap in enumerate(caps):
            added = min(cap-state[i], to_add)
            state[i] += added
            to_add -= added
        drain += to_add
        accessible = [s*f for s, f in zip(state, rooted)]
        available = sum(accessible)
        ks = min(1, available/((1-p)*taw)) if selected else 1.
        eta = min(etc*ks, available)
        if available > 0:
            for i in range(len(state)):
                state[i] -= eta*accessible[i]/available
        after = sum(state)
        residual = before+precipitation+irrigation-rain_runoff-drain-eta-after
        mass_error = max(mass_error, abs(residual))
        assert mass_error < 1e-7 and all(-1e-8 <= s <= c+1e-8 for s, c in zip(state, caps))
        totals['P_mm'] += precipitation
        totals['riego_neto_mm'] += irrigation
        totals['escorrentia_supuesta_mm'] += rain_runoff
        totals['drenaje_profundo_modelo_mm'] += drain
        if selected:
            active += 1
            deficit = etc-eta
            stress += int(ks < .95)
            for k, value in [('ET_potencial_cultivo_mm', etc), ('ET_real_cultivo_mm', eta), ('deficit_ET_mm', deficit)]:
                totals[k] += value
            for k, value in [('ETc_mm', etc), ('ETa_mm', eta), ('deficit_mm', deficit), ('riego_mm', irrigation), ('lluvia_mm', precipitation), ('dias_Ks_menor_095', int(ks < .95)), ('lluvia_ultimos10dias_mm', precipitation if (current['end']-day).days < 10 else 0)]:
                crop_summaries[n][k] += value
        if keep:
            details.append({'fecha': day.isoformat(), 'fuente_lluvia': rain, 'secuencia': seqname, 'riego_hipotetico': irrigate, 'cultivo': crop, 'P_mm': precipitation, 'ET0_mm': weather_row['et0_power_fao56_mm'], 'Kc': kc, 'Zr_m': zr, 'TAW_raices_mm': taw, 'agua_disponible_raices_antes_ET_mm': available, 'Ks': ks, 'ETc_mm': etc, 'ETa_mm': eta, 'riego_neto_mm': irrigation, 'agua_disponible_perfil_final_mm': after, 'residuo_balance_mm': residual})
    stages = [{**values, 'cultivo': s['crop'], 'inicio': s['start'].isoformat(), 'fin': s['end'].isoformat()} for values, s in zip(crop_summaries, sched)]
    ratio = round(totals['ET_real_cultivo_mm']/totals['ET_potencial_cultivo_mm'], 6) if totals['ET_potencial_cultivo_mm'] else None
    result = {'calendario': calname, 'secuencia': seqname, 'fuente_lluvia': rain, 'suelo_escenario': soilname, 'fraccion_escorrentia_supuesta': runoff, 'fraccion_agua_inicial_enero01': init, 'riego_hipotetico': irrigate, 'dias_con_cultivo': active, 'dias_Ks_menor_095': stress, **{k: round(v, 5) for k, v in totals.items()}, 'ETa_sobre_ETc': ratio, 'max_error_balance_mm': mass_error, 'segmentos': stages, 'decision_compatibilidad': 'requiere_evaluacion_local_y_sanitaria'}
    assert active == sum((s['end']-s['start']).days+1 for s in sched)
    return result, details


