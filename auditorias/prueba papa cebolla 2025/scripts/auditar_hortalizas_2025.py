"""Auditoría de sucesiones de hortalizas: agua, calendario y exposición climática."""
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
DIRECT='_'.join(CROPS);REVERSE='_'.join(reversed(CROPS))
NAMES={'papa':'Papa','cebolla':'Cebolla','brocoli':'Brócoli','lechuga':'Lechuga'}


def programs():
    result=[]
    for start,d1,d2,gap,reverse in itertools.product(CONFIG['inicios'],PARAM['cultivos'][CROPS[0]]['etapas'],PARAM['cultivos'][CROPS[1]]['etapas'],CONFIG['intervalos_dias'],[False,True]):
        order=CROPS[::-1] if reverse else CROPS[:]
        durations={CROPS[0]:int(d1),CROPS[1]:int(d2)}
        ident='_'.join(f'{c}{durations[c]}' for c in order)+f'_gap{gap}_{start}'
        result.append({'id':ident,'seq':'_'.join(order),'start':date.fromisoformat(start),'durations':durations,'crops':order,'gap':gap})
    return result


def configure(program):
    m.INTERVAL_DAYS=program['gap'];m.CROPS={}
    for crop in program['crops']:
        p=PARAM['cultivos'][crop]
        m.CROPS[crop]={'stages':p['etapas'][str(program['durations'][crop])],'kc':p['kc'],'zr':p['zr'],'p':p['p']}


def calendar(program):
    current=program['start'];segments=[]
    for crop in program['crops']:
        end=current+timedelta(days=program['durations'][crop]-1)
        segments.append({'cultivo':crop,'inicio':current.isoformat(),'fin':end.isoformat()})
        current=end+timedelta(days=program['gap']+1)
    end=date.fromisoformat(segments[-1]['fin']);first_end=date.fromisoformat(segments[0]['fin'])
    return {'programa':program['id'],'secuencia':program['seq'],'inicio':program['start'].isoformat(),
            **{f'duracion_{c}_dias':program['durations'][c] for c in CROPS},'intervalo_dias':program['gap'],
            'intervalo_inicio':(first_end+timedelta(days=1)).isoformat(),'intervalo_fin':(first_end+timedelta(days=program['gap'])).isoformat(),
            'fin_ciclo':end.isoformat(),'ciclo_cabe_en_2025':end<=m.DAYS[-1],'segmentos':segments,
            'liberacion_parcela':'sin_verificar','almacigo':'externo_excluido_del_balance_y_ocupacion',
            'estado':'calendario_supuesto_sin_validacion_de_variedad_o_adaptacion'}


def daylength(day,lat=m.LAT):
    """Duración astronómica FAO-56, N=24/pi*acos(-tan(phi)*tan(delta)); sin nubosidad."""
    dec=.409*math.sin(2*math.pi*day.timetuple().tm_yday/365-1.39)
    return 24/math.pi*math.acos(-math.tan(math.radians(lat))*math.tan(dec))


def exposure(program,rows):
    result=[]
    for seg in calendar(program)['segmentos']:
        sub=[r for r in rows if seg['inicio']<=r['fecha']<=seg['fin']]
        assert len(sub)==program['durations'][seg['cultivo']]
        light=[daylength(date.fromisoformat(r['fecha'])) for r in sub]
        for source in ['power','era5']:
            means=[r['T2M'] if source=='power' else (r['tmax_era5_C']+r['tmin_era5_C'])/2 for r in sub]
            highs=[r['T2M_MAX'] if source=='power' else r['tmax_era5_C'] for r in sub]
            result.append({'programa':program['id'],'cultivo':seg['cultivo'],'inicio':seg['inicio'],'fin':seg['fin'],'fuente_temperatura':source,
                           'definicion_media':'T2M_media_diaria_producto' if source=='power' else 'aproximacion_semisuma_Tmax_Tmin',
                           'dias':len(sub),'Tmedia_C':sum(means)/len(means),'Tmax_pico_C':max(highs),
                           **{f'dias_Tmedia_mayor_{t}C':sum(v>t for v in means) for t in [18,20,24,30]},
                           **{f'dias_Tmax_mayor_{t}C':sum(v>t for v in highs) for t in [24,30,35]},
                           'fotoperiodo_min_h':min(light),'fotoperiodo_max_h':max(light),
                           **{f'P_{rain}_durante_cultivo_mm':sum(r[f'P_{rain}_mm'] for r in sub) for rain in m.LABELS},
                           'interpretacion':'exposicion_regional_sin_probabilidad_de_dano_ni_correccion_de_fenologia'})
    return result


def run_one(program,rows,soil,source,soilcase,runoff,initial,irrigate,keep=False):
    configure(program)
    result,details=m.simulate(rows,soil,source,program['seq'],program['crops'],(program['id'],program['start'],False),soilcase,runoff,initial,irrigate,keep)
    result.update(programa=program['id'],inicio=program['start'].isoformat(),fin_ciclo=calendar(program)['fin_ciclo'],intervalo_dias=program['gap'],
                  **{f'duracion_{c}_dias':program['durations'][c] for c in CROPS})
    for s in result['segmentos']:
        for key in ['ETc_mm','ETa_mm','deficit_mm','riego_mm','dias_Ks_menor_095']:result[f"{s['cultivo']}_{key}"]=s[key]
    for r in details:r['programa']=program['id']
    return result,details


def pairs(results):
    fields=['inicio',*[f'duracion_{c}_dias' for c in CROPS],'intervalo_dias','fuente_lluvia','suelo_escenario','fraccion_escorrentia_supuesta','fraccion_agua_inicial_enero01','riego_hipotetico']
    groups={}
    for r in results:groups.setdefault(tuple(r[k] for k in fields),{})[r['secuencia']]=r
    output=[]
    for key,group in groups.items():
        assert set(group)=={DIRECT,REVERSE}
        a,b=group[DIRECT],group[REVERSE]
        output.append({**dict(zip(fields,key)),'programa_directo':a['programa'],'programa_inverso':b['programa'],
                       'deficit_directo_mm':a['deficit_ET_mm'],'deficit_inverso_mm':b['deficit_ET_mm'],
                       'diferencia_inverso_menos_directo_mm':round(b['deficit_ET_mm']-a['deficit_ET_mm'],5),
                       'riego_directo_mm':a['riego_neto_mm'],'riego_inverso_mm':b['riego_neto_mm']})
    return output


def gzip_text(path,text):
    with gzip.GzipFile(filename=str(path),mode='wb',mtime=0) as stream:stream.write(text.encode('utf-8'))


def csv_gzip(path,rows):
    buf=io.StringIO();writer=csv.DictWriter(buf,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows);gzip_text(path,buf.getvalue())


def is_reference(program):
    return program['start'].isoformat()==CONFIG['referencia_inicio'] and program['durations']==CONFIG['referencia_duraciones']


def render(calendars,core,rows):
    fig,ax=plt.subplots(figsize=(10,5),layout='constrained');colors=['#2b6cb0','#237a57','#b7791f','#8c4da8']
    for i,source in enumerate(m.LABELS):
        selected=[r for r in core if r['fuente_lluvia']==source and r['intervalo_dias']==14 and not r['riego_hipotetico']]
        ax.bar(np.arange(2)+(i-1.5)*.18,[next(r['deficit_ET_mm'] for r in selected if r['secuencia']==s) for s in [DIRECT,REVERSE]],.18,color=colors[i],label=m.LABELS[source])
    labels=[' → '.join(NAMES[c] for c in order) for order in [CROPS,CROPS[::-1]]]
    ax.set(xticks=[0,1],xticklabels=labels,ylabel='Déficit simulado de ET (mm)',title=f"Inicio {CONFIG['referencia_inicio']} · intervalo 14 d · secano\nComparación hídrica condicional; adaptación térmica sin validar")
    ax.legend(ncol=2,fontsize=8,frameon=False);ax.grid(axis='y',alpha=.2);fig.savefig(OUT/'comparacion_hidrica.png',dpi=150);plt.close(fig)
    fig,ax=plt.subplots(figsize=(11,5),layout='constrained');days=[date.fromisoformat(r['fecha']) for r in rows]
    ax.plot(days,[r['T2M'] for r in rows],label='POWER: media diaria regional',lw=1)
    ax.plot(days,[(r['tmax_era5_C']+r['tmin_era5_C'])/2 for r in rows],label='ERA5: semisuma Tmax/Tmin',lw=1,alpha=.7)
    low,high=(18,20) if CROPS[0]=='papa' else (16,18)
    ax.axhspan(low,high,color='#237a57',alpha=.15,label=f'Referencia de {NAMES[CROPS[0]]}: {low}–{high} °C')
    ax.set(title='Exposición térmica del candidato · sin corrección de temperatura por altitud\nReferencia bibliográfica; no umbral universal de daño ni medición de finca',ylabel='Temperatura (°C)',xlabel='Mes de 2025')
    ax.xaxis.set_major_locator(mdates.MonthLocator());ax.xaxis.set_major_formatter(mdates.DateFormatter('%m'));ax.legend(fontsize=8,ncol=2,frameon=False);ax.grid(alpha=.15)
    fig.savefig(OUT/'exposicion_termica.png',dpi=150);plt.close(fig)
    selected=[c for c in calendars if c['secuencia']==DIRECT and c['intervalo_dias']==14 and all(c[f'duracion_{crop}_dias']==d for crop,d in CONFIG['referencia_duraciones'].items())]
    fig,ax=plt.subplots(figsize=(11,5),layout='constrained')
    for i,c in enumerate(selected):
        for j,s in enumerate(c['segmentos']):
            length=(date.fromisoformat(s['fin'])-date.fromisoformat(s['inicio'])).days+1
            ax.barh(i,length,left=mdates.date2num(date.fromisoformat(s['inicio'])),height=.55,color=['#237a57','#b7791f'][j] if c['ciclo_cabe_en_2025'] else ['#8eaaa0','#a74532'][j])
    ax.set(yticks=range(len(selected)),yticklabels=[c['inicio'] for c in selected],xlabel='Mes/año; inicio indicado en cada fila',title='Calendarios supuestos de la dirección solicitada · intervalo 14 d\nRojo: ciclo final fuera de los datos de 2025; liberación real sin verificar')
    ax.axvline(date(2025,12,31),color='#333',ls='--');ax.xaxis.set_major_locator(mdates.MonthLocator(interval=2));ax.xaxis.set_major_formatter(mdates.DateFormatter('%m/%Y'));ax.grid(axis='x',alpha=.2)
    fig.savefig(OUT/'calendarios_y_cobertura.png',dpi=150);plt.close(fig)


def main():
    sys.stdout.reconfigure(encoding='utf-8');site,soil=m.static_site();rows,_,_=m.weather(site['elevacion_dsm_m']);m.events(rows)
    plans=programs();calendars=[calendar(p) for p in plans];eligible=[p for p,c in zip(plans,calendars) if c['ciclo_cabe_en_2025']]
    exposures=[record for p in eligible for record in exposure(p,rows)]
    results=[];daily=[]
    for p,source,soilcase,runoff,initial,water in itertools.product(eligible,m.LABELS,CONFIG['suelo_escenarios'],[0.,.15,.30],[.25,.75],[False,True]):
        keep=is_reference(p) and soilcase[0]=='perfil_referencia' and runoff==.15 and initial==.25
        result,detail=run_one(p,rows,soil,source,soilcase,runoff,initial,water,keep);results.append(result);daily.extend(detail)
    core=[r for r in results if r['inicio']==CONFIG['referencia_inicio'] and all(r[f'duracion_{c}_dias']==d for c,d in CONFIG['referencia_duraciones'].items()) and r['suelo_escenario']=='perfil_referencia' and r['fraccion_escorrentia_supuesta']==.15 and r['fraccion_agua_inicial_enero01']==.25]
    paired=pairs(results)
    m.write_json(OUT/'calendarios_evaluados.json',calendars);m.write_csv(OUT/'calendarios_evaluados.csv',[{k:v for k,v in c.items() if k!='segmentos'} for c in calendars])
    m.write_csv(OUT/'exposicion_climatica.csv',exposures)
    gzip_text(OUT/'resultados_escenarios.json.gz',json.dumps(results,ensure_ascii=False,allow_nan=False))
    csv_gzip(OUT/'resultados_escenarios.csv.gz',[{k:v for k,v in r.items() if k!='segmentos'} for r in results]);csv_gzip(OUT/'comparacion_pareada.csv.gz',paired);csv_gzip(OUT/'balances_referencia.csv.gz',daily)
    m.write_json(OUT/'comparacion_referencia.json',core);m.write_csv(OUT/'comparacion_referencia.csv',[{k:v for k,v in r.items() if k!='segmentos'} for r in core])
    render(calendars,core,rows)
    dry=[r for r in paired if not r['riego_hipotetico']];diff=[r['diferencia_inverso_menos_directo_mm'] for r in dry]
    refs=[r for r in core if r['intervalo_dias']==14 and not r['riego_hipotetico']]
    summary={'alternativa':CONFIG['alternativa_solicitada'],'comparador':CONFIG['comparador'],'programas':len(plans),'completos_2025':len(eligible),
             'inconclusos_sin_simular':len(plans)-len(eligible),'corridas':len(results),'pares':len(paired),'pares_secano':len(dry),
             'inverso_mayor_deficit':sum(d>1e-4 for d in diff),'inverso_menor_deficit':sum(d<-1e-4 for d in diff),'pares_en_tolerancia':sum(abs(d)<=1e-4 for d in diff),'tolerancia_mm':1e-4,
             'pasos_diarios':len(results)*365,'max_error_balance_mm':max(r['max_error_balance_mm'] for r in results),
             'referencia':[{'secuencia':r['secuencia'],'fuente':r['fuente_lluvia'],'deficit_mm':r['deficit_ET_mm'],'dias_estres':r['dias_Ks_menor_095']} for r in refs],
             'nota':'Malla de sensibilidades; sin probabilidades, aprobación térmica/sanitaria, rendimiento ni beneficio económico.'}
    m.write_json(OUT/'resumen_ejecutivo.json',summary)
    inputs=[p for p in (ROOT/'datos').rglob('*') if p.is_file()]+[Path(__file__),ROOT/'scripts/motor_hidrico_base.py',ROOT/'configuracion.json',ROOT/'requirements-simulacion.txt',ROOT/'tests/referencia_publicada.json']
    manifest={'fecha_utc':datetime.now(timezone.utc).isoformat(),'fecha_local_auditoria':CONFIG['fecha_auditoria'],'sitio':site,'configuracion':CONFIG,'resultados_resumen':summary,
              'metodo':'Balance diario de cinco capas del commit '+CONFIG['fuente_motor_commit']+'; contabilidad conservada. Exposición térmica y fotoperíodo descriptivos añadidos fuera del balance.',
              'limites':['Hindcast de 2025, sin validación de finca.','Temperatura no modifica crecimiento, Kc, duración o rendimiento: resultados de agua condicionales incluso donde hay alerta térmica.',
                        'POWER T2M es media diaria regional; ERA5 usa semisuma de máximas/mínimas, aproximación distinta. No igualar Tmax con temperatura diaria media ni temperatura de órgano.',
                        'Sin almácigo en el sublote. Duraciones de campo supuestas; inicio original de cada referencia se debe verificar.','Intervalos 7/14/21 incluyen retiro/preparación y curado si corresponde; no garantizan su cumplimiento.',
                        'No extrapolación a 2026 ni lluvia cero para completar ciclos.','Reserva continua desde enero 1, sin reinicio al cambiar de cultivo.','Kc único sin ajuste climático; raíces por calendario y profundidad de referencia no medida.',
                        'Drenaje instantáneo, sin anegamiento, ascenso capilar o flujo lateral; sin modelación de sanidad, residuos, nutrientes, rendimiento o ingresos.',
                        'Riego hipotético de 20 mm netos con suministro ilimitado al superar RAW; no recomendación operativa.','Fotoperíodo astronómico sin nubosidad/refacción; no modela bulbificación o espigado.','Sanidad requiere diagnóstico; sin bonificaciones o penalizaciones por familia.'],
              'archivos_fuente_sha256':[{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(inputs)]}
    m.write_json(OUT/'metodo_y_validacion.json',manifest)
    print(json.dumps(summary,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
