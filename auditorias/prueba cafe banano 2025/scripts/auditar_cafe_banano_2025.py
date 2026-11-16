"""Auditoría de Café solo vs. Café + Banano (Musa spp.): agua, calendario, variantes de manejo y exposición agroclimática."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
cache=ROOT.parents[1]/'tmp/sim-deps'
if cache.exists():sys.path.insert(0,str(cache))
from scripts import motor_hidrico_base as m
import csv,gzip,hashlib,io,itertools,json,math
from datetime import date,timedelta,datetime,timezone
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import numpy as np

OUT=ROOT/'resultados';OUT.mkdir(exist_ok=True);m.OUT=OUT
CONFIG=m.load(ROOT/'configuracion.json')
PARAM=m.load(ROOT/'datos/cultivos/parametros_auditados.json')
CROPS=CONFIG['cultivos']
DIRECT=CROPS[0];REVERSE=CROPS[1]
NAMES={'cafe_solo':'Solo Café','cafe_banano':'Café + Banano (Musa)'}
VARIANT_NAMES={
    'limpio_vs_regulado':'Base: Limpio vs. Musa regulado + mulch',
    'cobertura_viva_vs_musa_denso':'Alta demanda: Cobertura viva vs. Musa denso',
    'establecimiento_renovacion_anio1':'Establecimiento / Recepa Año 1'
}


def programs():
    result=[]
    for start,dur,variant,crop in itertools.product(CONFIG['inicios'],CONFIG['duraciones_dias'],CONFIG['variantes_manejo'],CROPS):
        dur=int(dur)
        ident=f'{crop}_{dur}d_{variant}_{start}'
        result.append({
            'id':ident,
            'seq':crop,
            'start':date.fromisoformat(start),
            'duration':dur,
            'durations':{'cafe_solo':dur,'cafe_banano':dur},
            'crops':[crop],
            'variant':variant,
            'gap':0
        })
    return result


def configure(program):
    m.INTERVAL_DAYS=0;m.CROPS={}
    crop=program['seq']
    p=PARAM['cultivos'][crop]
    v=p['variantes'][program['variant']]
    m.CROPS[crop]={
        'stages':p['etapas'][str(program['duration'])],
        'kc':v['kc'],
        'zr':v['zr'],
        'p':v['p']
    }


def calendar(program):
    start=program['start']
    end=start+timedelta(days=program['duration']-1)
    segments=[{
        'cultivo':program['seq'],
        'variante_manejo':program['variant'],
        'inicio':start.isoformat(),
        'fin':end.isoformat()
    }]
    return {
        'programa':program['id'],
        'secuencia':program['seq'],
        'variante_manejo':program['variant'],
        'inicio':start.isoformat(),
        'duracion_dias':program['duration'],
        'duracion_cafe_solo_dias':program['duration'],
        'duracion_cafe_banano_dias':program['duration'],
        'intervalo_dias':0,
        'fin_ciclo':end.isoformat(),
        'ciclo_cabe_en_2025':end<=m.DAYS[-1],
        'segmentos':segments,
        'tipo_ciclo':'anual_establecido_2025' if (start.isoformat()=='2025-01-01' and program['duration']==365) else 'ventana_establecimiento_o_renovacion',
        'liberacion_parcela':'plantacion_perenne_permanece_en_parcela',
        'almacigo':'semillero_y_almacigo_externos_excluidos_del_balance',
        'estado':'calendario_supuesto_sin_validacion_de_variedad_sombra_o_adaptacion'
    }


def daylength(day,lat=m.LAT):
    """Duración astronómica FAO-56, N=24/pi*acos(-tan(phi)*tan(delta)); sin nubosidad."""
    dec=.409*math.sin(2*math.pi*day.timetuple().tm_yday/365-1.39)
    return 24/math.pi*math.acos(-math.tan(math.radians(lat))*math.tan(dec))


def exposure(program,rows):
    result=[]
    for seg in calendar(program)['segmentos']:
        sub=[r for r in rows if seg['inicio']<=r['fecha']<=seg['fin']]
        assert len(sub)==program['duration']
        light=[daylength(date.fromisoformat(r['fecha'])) for r in sub]
        for source in ['power','era5']:
            means=[r['T2M'] if source=='power' else (r['tmax_era5_C']+r['tmin_era5_C'])/2 for r in sub]
            highs=[r['T2M_MAX'] if source=='power' else r['tmax_era5_C'] for r in sub]
            lows=[r['T2M_MIN'] if source=='power' else r['tmin_era5_C'] for r in sub]
            tmean=sum(means)/len(means)
            phase_stats={}
            for ph in CONFIG['fases_fenologicas_2025']:
                ph_rows=[r for r in sub if ph['inicio']<=r['fecha']<=ph['fin']]
                ph_means=[r['T2M'] if source=='power' else (r['tmax_era5_C']+r['tmin_era5_C'])/2 for r in ph_rows]
                phase_stats[f"dias_{ph['id']}"]=len(ph_rows)
                phase_stats[f"Tmedia_{ph['id']}_C"]=round(sum(ph_means)/len(ph_means),4) if ph_means else None
                phase_stats[f"P_imerg_{ph['id']}_mm"]=round(sum(r['P_imerg_mm'] for r in ph_rows),3)
            result.append({
                'programa':program['id'],
                'cultivo':seg['cultivo'],
                'variante_manejo':program['variant'],
                'inicio':seg['inicio'],
                'fin':seg['fin'],
                'fuente_temperatura':source,
                'definicion_media':'T2M_media_diaria_producto' if source=='power' else 'aproximacion_semisuma_Tmax_Tmin',
                'dias':len(sub),
                'Tmedia_C':round(tmean,4),
                'Tmedia_amortiguada_dosel_menos2C':round(tmean-2.0,4) if seg['cultivo']=='cafe_banano' else round(tmean,4),
                'Tmax_pico_C':round(max(highs),4),
                'Tmin_min_C':round(min(lows),4),
                **{f'dias_Tmedia_mayor_{t}C':sum(v>t for v in means) for t in [18,20,22,24,26,30]},
                **{f'dias_Tmax_mayor_{t}C':sum(v>t for v in highs) for t in [24,30,32,35]},
                'fotoperiodo_min_h':round(min(light),4),
                'fotoperiodo_max_h':round(max(light),4),
                **{f'P_{rain}_durante_cultivo_mm':round(sum(r[f'P_{rain}_mm'] for r in sub),4) for rain in m.LABELS},
                **phase_stats,
                'alerta_altitud_373m':'sitio_373m_calido_fuera_rango_arabica_estandar_compatible_robusta_nemaya_sujeto_a_validacion',
                'interpretacion':'exposicion_regional_sin_probabilidad_de_dano_ni_correccion_de_fenologia'
            })
    return result


def run_one(program,rows,soil,source,soilcase,runoff,initial,irrigate,keep=False):
    configure(program)
    result,details=m.simulate(rows,soil,source,program['seq'],program['crops'],(program['id'],program['start'],False),soilcase,runoff,initial,irrigate,keep)
    v=PARAM['cultivos'][program['seq']]['variantes'][program['variant']]
    result.update(
        programa=program['id'],
        variante_manejo=program['variant'],
        inicio=program['start'].isoformat(),
        fin_ciclo=calendar(program)['fin_ciclo'],
        duracion_dias=program['duration'],
        duracion_cafe_solo_dias=program['duration'],
        duracion_cafe_banano_dias=program['duration'],
        intervalo_dias=0,
        kc_ini=v['kc'][0],
        kc_mid=v['kc'][1],
        kc_end=v['kc'][2],
        zr_referencia_m=v['zr'],
        p_referencia=v['p']
    )
    for c in CROPS:
        for key in ['ETc_mm','ETa_mm','deficit_mm','riego_mm','dias_Ks_menor_095']:
            result[f"{c}_{key}"]=None
    for s in result['segmentos']:
        for key in ['ETc_mm','ETa_mm','deficit_mm','riego_mm','dias_Ks_menor_095']:
            result[f"{s['cultivo']}_{key}"]=s[key]
    for r in details:
        r['programa']=program['id']
        r['variante_manejo']=program['variant']
    return result,details


def pairs(results):
    fields=['inicio','duracion_dias','variante_manejo','fuente_lluvia','suelo_escenario','fraccion_escorrentia_supuesta','fraccion_agua_inicial_enero01','riego_hipotetico']
    groups={}
    for r in results:
        groups.setdefault(tuple(r[k] for k in fields),{})[r['secuencia']]=r
    output=[]
    for key,group in groups.items():
        assert set(group)=={DIRECT,REVERSE}
        a,b=group[DIRECT],group[REVERSE]
        diff=round(b['deficit_ET_mm']-a['deficit_ET_mm'],5)
        output.append({
            **dict(zip(fields,key)),
            'programa_directo':a['programa'],
            'programa_inverso':b['programa'],
            'programa_cafe_solo':a['programa'],
            'programa_cafe_banano':b['programa'],
            'deficit_directo_mm':a['deficit_ET_mm'],
            'deficit_inverso_mm':b['deficit_ET_mm'],
            'deficit_cafe_solo_mm':a['deficit_ET_mm'],
            'deficit_cafe_banano_mm':b['deficit_ET_mm'],
            'diferencia_inverso_menos_directo_mm':diff,
            'diferencia_asocio_menos_solo_mm':diff,
            'dias_Ks_menor_095_solo':a['dias_Ks_menor_095'],
            'dias_Ks_menor_095_asocio':b['dias_Ks_menor_095'],
            'riego_directo_mm':a['riego_neto_mm'],
            'riego_inverso_mm':b['riego_neto_mm']
        })
    return output


def gzip_text(path,text):
    with gzip.GzipFile(filename=str(path),mode='wb',mtime=0) as stream:
        stream.write(text.encode('utf-8'))


def csv_gzip(path,rows):
    buf=io.StringIO(newline='\n')
    writer=csv.DictWriter(buf,fieldnames=list(rows[0]),lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
    gzip_text(path,buf.getvalue())


def is_reference(program):
    return program['start'].isoformat()==CONFIG['referencia_inicio'] and program['duration']==365


def render(calendars,core,rows):
    fig,axes=plt.subplots(1,3,figsize=(13.5,5.2),sharey=True,layout='constrained')
    colors=['#2b6cb0','#237a57','#b7791f','#8c4da8']
    for idx,variant in enumerate(CONFIG['variantes_manejo']):
        ax=axes[idx]
        for i,source in enumerate(m.LABELS):
            selected=[r for r in core if r['variante_manejo']==variant and r['fuente_lluvia']==source and not r['riego_hipotetico']]
            vals=[next(r['deficit_ET_mm'] for r in selected if r['secuencia']==s) for s in [DIRECT,REVERSE]]
            ax.bar(np.arange(2)+(i-1.5)*.18,vals,.18,color=colors[i],label=m.LABELS[source])
        ax.set_xticks([0,1])
        ax.set_xticklabels(['Solo Café','Café + Banano'])
        ax.set_title(VARIANT_NAMES[variant],fontsize=9.5)
        ax.grid(axis='y',alpha=.2)
        if idx==0:
            ax.set_ylabel('Déficit anual simulado de ET (mm)')
    axes[1].legend(ncol=2,fontsize=8,frameon=False,loc='upper left')
    fig.suptitle('Ciclo anual 2025 (inicio 2025-01-01, 365 d) · secano · perfil de referencia · escorrentía 15 %\nComparación hídrica por variante de manejo y fuente de lluvia (sin bono automático de familia)',fontsize=10.5)
    fig.savefig(OUT/'comparacion_hidrica.png',dpi=150)
    plt.close(fig)

    fig,ax=plt.subplots(figsize=(11.5,5.2),layout='constrained')
    days=[date.fromisoformat(r['fecha']) for r in rows]
    t_power=[r['T2M'] for r in rows]
    t_era5=[(r['tmax_era5_C']+r['tmin_era5_C'])/2 for r in rows]
    ax.plot(days,t_power,label='POWER T2M: media diaria regional (373 m DSM)',color='#1a365d',lw=1.2)
    ax.plot(days,[v-2.0 for v in t_power],label='Hipótesis bajo dosel Musa (−2 °C sobre POWER)',color='#2b6cb0',ls='--',lw=1.0)
    ax.plot(days,t_era5,label='ERA5: semisuma Tmax/Tmin',color='#b7791f',lw=1.0,alpha=.75)
    ax.axhspan(18,22,color='#237a57',alpha=.16,label='Rango térmico óptimo C. arabica (18–22 °C, Anacafé)')
    ax.axhspan(22,28,color='#d69e2e',alpha=.12,label='Rango térmico C. canephora Robusta / Nemaya (22–28 °C)')
    for ph_date,ph_label in [(date(2025,5,1),'Inicio expansión / lluvias'),(date(2025,8,16),'Llenado grano (K)'),(date(2025,11,1),'Maduración / cosecha')]:
        ax.axvline(ph_date,color='#555',ls=':',lw=.9)
        ax.text(ph_date,31.2,ph_label,fontsize=7.5,rotation=0,ha='left',va='top',color='#333')
    ax.set(
        title='Exposición térmica en el candidato (373 m DSM) y fases fenológicas del café en 2025\nAlerta de baja altitud para C. arabica; la amortiguación de sombra (−2 °C) requiere medición bajo dosel en finca',
        ylabel='Temperatura (°C)',
        xlabel='Mes de 2025'
    )
    ax.xaxis.set_major_locator(mdates.MonthLocator())
    ax.xaxis.set_major_formatter(mdates.DateFormatter('%m'))
    ax.legend(fontsize=7.8,ncol=2,frameon=False,loc='lower left')
    ax.grid(alpha=.15)
    fig.savefig(OUT/'exposicion_termica.png',dpi=150)
    plt.close(fig)

    selected=[c for c in calendars if c['secuencia']=='cafe_banano' and c['variante_manejo']=='limpio_vs_regulado']
    fig,ax=plt.subplots(figsize=(11.5,6.2),layout='constrained')
    for i,c in enumerate(selected):
        s=c['segmentos'][0]
        length=(date.fromisoformat(s['fin'])-date.fromisoformat(s['inicio'])).days+1
        color='#237a57' if c['ciclo_cabe_en_2025'] else '#a74532'
        ax.barh(i,length,left=mdates.date2num(date.fromisoformat(s['inicio'])),height=.62,color=color)
    ax.set(
        yticks=range(len(selected)),
        yticklabels=[f"{c['inicio']} ({c['duracion_dias']} d)" for c in selected],
        xlabel='Mes/año de 2025–2026',
        title='Calendarios evaluados (ciclo anual 365 d y ventanas de establecimiento/recepa 180–365 d)\nVerde: cubierto íntegramente en 2025; Rojo: excede el 31/12/2025 y se excluye sin extrapolar lluvias'
    )
    ax.axvline(date(2025,12,31),color='#222',ls='--',lw=1.2)
    ax.xaxis.set_major_locator(mdates.MonthLocator(interval=2))
    ax.xaxis.set_major_formatter(mdates.DateFormatter('%m/%Y'))
    ax.grid(axis='x',alpha=.2)
    fig.savefig(OUT/'calendarios_y_cobertura.png',dpi=150)
    plt.close(fig)


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    site,soil=m.static_site()
    rows,_,_=m.weather(site['elevacion_dsm_m'])
    m.events(rows)
    plans=programs()
    calendars=[calendar(p) for p in plans]
    eligible=[p for p,c in zip(plans,calendars) if c['ciclo_cabe_en_2025']]
    exposures=[record for p in eligible for record in exposure(p,rows)]
    results=[];daily=[]
    for p,source,soilcase,runoff,initial,water in itertools.product(eligible,m.LABELS,CONFIG['suelo_escenarios'],[0.,.15,.30],[.25,.75],[False,True]):
        keep=is_reference(p) and soilcase[0]=='perfil_referencia' and runoff==.15 and initial==.25
        result,detail=run_one(p,rows,soil,source,soilcase,runoff,initial,water,keep)
        results.append(result)
        daily.extend(detail)
    core=[r for r in results if r['inicio']==CONFIG['referencia_inicio'] and r['duracion_dias']==365 and r['suelo_escenario']=='perfil_referencia' and r['fraccion_escorrentia_supuesta']==.15 and r['fraccion_agua_inicial_enero01']==.25]
    paired=pairs(results)
    m.write_json(OUT/'calendarios_evaluados.json',calendars)
    m.write_csv(OUT/'calendarios_evaluados.csv',[{k:v for k,v in c.items() if k!='segmentos'} for c in calendars])
    m.write_csv(OUT/'exposicion_climatica.csv',exposures)
    gzip_text(OUT/'resultados_escenarios.json.gz',json.dumps(results,ensure_ascii=False,allow_nan=False))
    csv_gzip(OUT/'resultados_escenarios.csv.gz',[{k:v for k,v in r.items() if k!='segmentos'} for r in results])
    csv_gzip(OUT/'comparacion_pareada.csv.gz',paired)
    csv_gzip(OUT/'balances_referencia.csv.gz',daily)
    m.write_json(OUT/'comparacion_referencia.json',core)
    m.write_csv(OUT/'comparacion_referencia.csv',[{k:v for k,v in r.items() if k!='segmentos'} for r in core])
    render(calendars,core,rows)

    dry=[r for r in paired if not r['riego_hipotetico']]
    diff=[r['diferencia_inverso_menos_directo_mm'] for r in dry]
    refs=[r for r in core if not r['riego_hipotetico']]
    est_refs=[r for r in results if r['inicio']==CONFIG['referencia_establecimiento_inicio'] and r['duracion_dias']==CONFIG['referencia_establecimiento_duracion_dias'] and r['variante_manejo']=='establecimiento_renovacion_anio1' and r['suelo_escenario']=='perfil_referencia' and r['fraccion_escorrentia_supuesta']==.15 and r['fraccion_agua_inicial_enero01']==.25 and not r['riego_hipotetico']]
    by_variant={}
    for v in CONFIG['variantes_manejo']:
        sub_d=[r['diferencia_inverso_menos_directo_mm'] for r in dry if r['variante_manejo']==v]
        by_variant[v]={
            'pares_secano':len(sub_d),
            'asocio_mayor_deficit':sum(d>1e-4 for d in sub_d),
            'asocio_menor_deficit':sum(d<-1e-4 for d in sub_d),
            'diferencia_media_mm':round(sum(sub_d)/len(sub_d),4),
            'diferencia_min_mm':round(min(sub_d),4),
            'diferencia_max_mm':round(max(sub_d),4)
        }
    summary={
        'alternativa':CONFIG['alternativa_solicitada'],
        'comparador':CONFIG['comparador'],
        'programas':len(plans),
        'completos_2025':len(eligible),
        'inconclusos_sin_simular':len(plans)-len(eligible),
        'corridas':len(results),
        'pares':len(paired),
        'pares_secano':len(dry),
        'inverso_mayor_deficit':sum(d>1e-4 for d in diff),
        'inverso_menor_deficit':sum(d<-1e-4 for d in diff),
        'pares_en_tolerancia':sum(abs(d)<=1e-4 for d in diff),
        'tolerancia_mm':1e-4,
        'pasos_diarios':len(results)*365,
        'max_error_balance_mm':max(r['max_error_balance_mm'] for r in results),
        'por_variante_secano':by_variant,
        'referencia_anual_2025':[
            {
                'variante_manejo':r['variante_manejo'],
                'secuencia':r['secuencia'],
                'fuente':r['fuente_lluvia'],
                'ETc_mm':r['ET_potencial_cultivo_mm'],
                'ETa_mm':r['ET_real_cultivo_mm'],
                'deficit_mm':r['deficit_ET_mm'],
                'dias_estres':r['dias_Ks_menor_095']
            } for r in refs
        ],
        'referencia_establecimiento_mayo15_180d':[
            {
                'variante_manejo':r['variante_manejo'],
                'secuencia':r['secuencia'],
                'fuente':r['fuente_lluvia'],
                'ETc_mm':r['ET_potencial_cultivo_mm'],
                'ETa_mm':r['ET_real_cultivo_mm'],
                'deficit_mm':r['deficit_ET_mm'],
                'dias_estres':r['dias_Ks_menor_095']
            } for r in est_refs
        ],
        'nota':'Malla de sensibilidades; evalúa de forma separada el costo hídrico transpiratorio del dosel de Musa frente a la cobertura de mulch y al establecimiento de primer año. No asigna bono automático por familia ni certifica rendimiento o sanidad.'
    }
    m.write_json(OUT/'resumen_ejecutivo.json',summary)
    inputs=[p for p in (ROOT/'datos').rglob('*') if p.is_file()]+[Path(__file__),ROOT/'scripts/motor_hidrico_base.py',ROOT/'configuracion.json',ROOT/'requirements-simulacion.txt',ROOT/'tests/referencia_publicada.json']
    manifest={
        'fecha_utc':datetime.now(timezone.utc).isoformat(),
        'fecha_local_auditoria':CONFIG['fecha_auditoria'],
        'sitio':site,
        'configuracion':CONFIG,
        'resultados_resumen':summary,
        'metodo':'Balance diario de cinco capas del commit '+CONFIG['fuente_motor_commit']+'; contabilidad conservada. Compara Solo Café frente a Café + Banano (Musa spp.) bajo tres variantes explícitas de Kc/Zr/p y cuatro duraciones (180–365 d).',
        'limites':[
            'Hindcast de 2025 en el punto candidato (373 m DSM), sin delimitación de finca ni validación de campo.',
            'A 373 m DSM, la temperatura media regional (24.42 °C POWER / 27.60 °C ERA5) excede el rango óptimo de Coffea arabica estándar (18–22 °C, 600–1,600 m s. n. m.) y se ubica en el piso térmico de Coffea canephora (Robusta / portainjerto Nemaya, 200–1,000 m).',
            'La amortiguación térmica bajo dosel de Musa (−1.5 a −3.0 °C documentada en literatura) se reporta como referencia descriptiva; no modifica automáticamente ET0 ni la fenología en el motor.',
            'El motor usa un Kc compuesto efectivo por variante; no resuelve la partición bidimensional de raíces entre hileras de café y matas de banano ni el escurrimiento caulinar concentrado (stemflow) al pie del pseudotallo.',
            'Semillero (90–120 d) y almácigo en bolsa (6–9 meses) ocurren fuera del sublote antes del trasplante y no se descuentan del balance de la parcela.',
            'No se extrapolan lluvias a 2026 ni se rellenan con ceros los calendarios de establecimiento iniciados después del 1 de enero que superan el 31 de diciembre de 2025.',
            'La diferencia de familia botánica (Rubiaceae + Musaceae) no otorga bono fitosanitario ni cancela el riesgo de nematodos compartidos (Pratylenchus coffeae, Meloidogyne spp.) o volcamiento por Radopholus similis y Cosmopolites sordidus.',
            'El aporte de flujo de caja temprano del banano (9–14 meses) y el reciclaje de potasio (K) en pseudotallos/hojas picados requieren validar densidad, costos locales y precios en finca.'
        ],
        'archivos_fuente_sha256':[{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(inputs)]
    }
    m.write_json(OUT/'metodo_y_validacion.json',manifest)
    print(json.dumps(summary,ensure_ascii=False,indent=2))


if __name__=='__main__':
    main()
