"""Completa 34 sucesiones pendientes entre siete cultivos con entradas congeladas de 2025."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
cache=ROOT.parents[1]/'tmp/sim-deps'
if cache.exists():sys.path.insert(0,str(cache))
from scripts import motor_hidrico_base as m
from scripts import motor_vectorizado as v
import csv,gzip,hashlib,io,itertools,json,math,time
from datetime import date,timedelta,datetime,timezone
import numpy as np
import matplotlib.pyplot as plt

CONFIG=m.load(ROOT/'configuracion.json');PARAM=m.load(ROOT/'datos/cultivos/parametros_auditados.json')['cultivos']
NAMES={'maiz':'Maíz','frijol':'Frijol','ajonjoli':'Ajonjolí','papa':'Papa','cebolla':'Cebolla','brocoli':'Brócoli','lechuga':'Lechuga'}
CASES=v.scenario_grid(CONFIG['suelo_escenarios'],CONFIG['escorrentias'],CONFIG['reservas_iniciales'],CONFIG['riego'])
OUT=ROOT/'resultados';OUT.mkdir(exist_ok=True);m.OUT=OUT


def programs(pair):
    out=[]
    for start,a,b,gap,reverse in itertools.product(CONFIG['inicios'],PARAM[pair[0]]['etapas'],PARAM[pair[1]]['etapas'],CONFIG['intervalos_dias'],[False,True]):
        crops=pair[::-1] if reverse else pair[:];durations={pair[0]:int(a),pair[1]:int(b)}
        ident='_'.join(f'{c}{durations[c]}' for c in crops)+f'_gap{gap}_{start}'
        out.append({'id':ident,'seq':'_'.join(crops),'start':date.fromisoformat(start),'durations':durations,'crops':crops,'gap':gap})
    return out


def configure(program):
    m.INTERVAL_DAYS=program['gap'];m.CROPS={}
    for crop in program['crops']:
        p=PARAM[crop];m.CROPS[crop]={'stages':p['etapas'][str(program['durations'][crop])],'kc':p['kc'],'zr':p['zr'],'p':p['p']}


def calendar(program):
    current=program['start'];segments=[]
    for crop in program['crops']:
        end=current+timedelta(days=program['durations'][crop]-1);segments.append({'cultivo':crop,'inicio':current.isoformat(),'fin':end.isoformat()});current=end+timedelta(days=program['gap']+1)
    return {'programa':program['id'],'secuencia':program['seq'],'inicio':program['start'].isoformat(),
            **{f'duracion_{c}_dias':days for c,days in program['durations'].items()},'intervalo_dias':program['gap'],
            'fin_ciclo':segments[-1]['fin'],'ciclo_cabe_en_2025':date.fromisoformat(segments[-1]['fin'])<=m.DAYS[-1],
            'segmentos':segments,'estado':'calendario_supuesto; madurez_comercial_y_retiro_sin_verificar'}


def daylength(day,lat=m.LAT):
    dec=.409*math.sin(2*math.pi*day.timetuple().tm_yday/365-1.39)
    return 24/math.pi*math.acos(-math.tan(math.radians(lat))*math.tan(dec))


def exposure(program,rows):
    records=[]
    for s in calendar(program)['segmentos']:
        sub=[r for r in rows if s['inicio']<=r['fecha']<=s['fin']]
        assert len(sub)==program['durations'][s['cultivo']]
        light=[daylength(date.fromisoformat(r['fecha'])) for r in sub]
        for source in ['power','era5']:
            means=[r['T2M'] if source=='power' else (r['tmax_era5_C']+r['tmin_era5_C'])/2 for r in sub]
            highs=[r['T2M_MAX'] if source=='power' else r['tmax_era5_C'] for r in sub]
            records.append({'programa':program['id'],'secuencia':program['seq'],'cultivo':s['cultivo'],'inicio':s['inicio'],'fin':s['fin'],'fuente_temperatura':source,
                            'definicion_media':'T2M_producto' if source=='power' else 'aproximacion_semisuma_Tmax_Tmin','dias':len(sub),'Tmedia_C':sum(means)/len(means),'Tmax_pico_C':max(highs),
                            **{f'dias_Tmedia_mayor_{t}C':sum(x>t for x in means) for t in [18,20,24,30]},**{f'dias_Tmax_mayor_{t}C':sum(x>t for x in highs) for t in [24,30,35]},
                            'fotoperiodo_min_h':min(light),'fotoperiodo_max_h':max(light),**{f'P_{rain}_durante_cultivo_mm':sum(r['P_'+rain+'_mm'] for r in sub) for rain in m.LABELS}})
    return records


def run_program(program,rows,soil,cases=CASES,keep_indices=()):
    configure(program);schedule=m.schedule(program['crops'],program['start'],False)
    results,daily=v.simulate_many(rows,soil,schedule,cases,program['id'],program['seq'],keep_indices)
    for r in results:
        r.update(programa=program['id'],inicio=program['start'].isoformat(),fin_ciclo=calendar(program)['fin_ciclo'],intervalo_dias=program['gap'],**{f'duracion_{c}_dias':d for c,d in program['durations'].items()})
        for s in r['segmentos']:
            for key in ['ETc_mm','ETa_mm','deficit_mm','riego_mm','dias_Ks_menor_095']:r[s['cultivo']+'_'+key]=s[key]
    return results,daily


def paired_results(results,pair):
    fields=['inicio',*[f'duracion_{c}_dias' for c in pair],'intervalo_dias','fuente_lluvia','suelo_escenario','fraccion_escorrentia_supuesta','fraccion_agua_inicial_enero01','riego_hipotetico']
    groups={}
    for r in results:groups.setdefault(tuple(r[k] for k in fields),{})[r['secuencia']]=r
    output=[];direct='_'.join(pair);reverse='_'.join(pair[::-1])
    for key,group in groups.items():
        assert set(group)=={direct,reverse};a,b=group[direct],group[reverse]
        output.append({**dict(zip(fields,key)),'programa_directo':a['programa'],'programa_inverso':b['programa'],
                       'deficit_directo_mm':a['deficit_ET_mm'],'deficit_inverso_mm':b['deficit_ET_mm'],
                       'diferencia_inverso_menos_directo_mm':round(b['deficit_ET_mm']-a['deficit_ET_mm'],5),
                       'riego_directo_mm':a['riego_neto_mm'],'riego_inverso_mm':b['riego_neto_mm']})
    return output


def write_gzip(path,text):
    with gzip.GzipFile(filename=str(path),mode='wb',mtime=0) as stream:stream.write(text.encode('utf-8'))


def csv_gzip(path,rows):
    buf=io.StringIO();writer=csv.DictWriter(buf,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows);write_gzip(path,buf.getvalue())


def is_reference(p):
    return p['start'].isoformat()==CONFIG['referencia_inicio'] and p['gap']==14 and all(d==CONFIG['referencia_duraciones'][c] for c,d in p['durations'].items())


def plot_reference(path,core,pair):
    fig,ax=plt.subplots(figsize=(10,5),layout='constrained');colors=['#2b6cb0','#237a57','#b7791f','#8c4da8']
    for i,source in enumerate(m.LABELS):
        subset=[r for r in core if r['fuente_lluvia']==source and not r['riego_hipotetico']]
        ax.bar(np.arange(2)+(i-1.5)*.18,[next(r['deficit_ET_mm'] for r in subset if r['secuencia']=='_'.join(s)) for s in [pair,pair[::-1]]],.18,color=colors[i],label=m.LABELS[source])
    labels=[' → '.join(NAMES[c] for c in seq) for seq in [pair,pair[::-1]]]
    ax.set(xticks=[0,1],xticklabels=labels,ylabel='Déficit simulado de ET (mm)',title='Inicio 1 marzo 2025 · intervalo 14 días · secano\nMismo inicio y duraciones; adaptación, sanidad y rendimiento sin validar')
    ax.legend(ncol=2,fontsize=8,frameon=False);ax.grid(axis='y',alpha=.2);fig.savefig(path,dpi=140);plt.close(fig)


def audit_pair(pair,rows,soil):
    out=ROOT/'parejas'/'_'.join(pair);out.mkdir(parents=True,exist_ok=True)
    plans=programs(pair);calendars=[calendar(p) for p in plans];eligible=[p for p,c in zip(plans,calendars) if c['ciclo_cabe_en_2025']]
    results=[];daily=[];exposures=[];core=[]
    keep=[i for i,c in enumerate(CASES) if c[1][0]=='perfil_referencia' and c[2]==.15 and c[3]==.25]
    for p in eligible:
        selected=is_reference(p)
        got,detail=run_program(p,rows,soil,keep_indices=keep if selected else ())
        results.extend(got);daily.extend(detail);exposures.extend(exposure(p,rows))
        if selected:core.extend(r for r in got if r['suelo_escenario']=='perfil_referencia' and r['fraccion_escorrentia_supuesta']==.15 and r['fraccion_agua_inicial_enero01']==.25)
    assert len(core)==16 and len(daily)==16*365
    paired=paired_results(results,pair);dry=[r for r in paired if not r['riego_hipotetico']];diff=[r['diferencia_inverso_menos_directo_mm'] for r in dry]
    m.write_json(out/'calendarios.json',calendars);m.write_csv(out/'calendarios.csv',[{k:x for k,x in c.items() if k!='segmentos'} for c in calendars])
    write_gzip(out/'escenarios.json.gz',json.dumps(results,ensure_ascii=False,allow_nan=False));csv_gzip(out/'escenarios.csv.gz',[{k:x for k,x in r.items() if k!='segmentos'} for r in results])
    csv_gzip(out/'comparacion_pareada.csv.gz',paired);csv_gzip(out/'balances_referencia.csv.gz',daily);csv_gzip(out/'exposicion_climatica.csv.gz',exposures)
    m.write_json(out/'referencia.json',core);m.write_csv(out/'referencia.csv',[{k:x for k,x in r.items() if k!='segmentos'} for r in core])
    ref_ids={r['programa'] for r in core};m.write_csv(out/'exposicion_referencia.csv',[r for r in exposures if r['programa'] in ref_ids])
    plot_reference(out/'comparacion_hidrica.png',core,pair)
    summary={'pareja':'_'.join(pair),'cultivos':pair,'sucesiones':[' → '.join(s) for s in [pair,pair[::-1]]],'programas':len(plans),'completos_2025':len(eligible),
             'inconclusos_sin_simular':len(plans)-len(eligible),'corridas':len(results),'pares':len(paired),'pares_secano':len(dry),
             'inverso_mayor_deficit':sum(d>1e-4 for d in diff),'inverso_menor_deficit':sum(d<-1e-4 for d in diff),'pares_en_tolerancia':sum(abs(d)<=1e-4 for d in diff),'tolerancia_mm':1e-4,
             'pasos_diarios':len(results)*365,'max_error_balance_mm':max(r['max_error_balance_mm'] for r in results),'registros_balance_referencia':len(daily),
             'cobertura':'ambas_direcciones_evaluadas_exploratoriamente','decision_compatibilidad':'requiere_evaluacion_local_y_sanitaria'}
    m.write_json(out/'resumen.json',summary)
    return summary


def main():
    sys.stdout.reconfigure(encoding='utf-8');started=time.monotonic();site,soil=m.static_site();rows,_,_=m.weather(site['elevacion_dsm_m']);m.events(rows)
    summaries=[]
    for i,pair in enumerate(CONFIG['parejas_nuevas'],1):
        summary=audit_pair(pair,rows,soil);summaries.append(summary)
        print(json.dumps({'terminada':i,'total':17,'pareja':summary['pareja'],'corridas':summary['corridas'],'segundos':round(time.monotonic()-started,1)},ensure_ascii=False),flush=True)
    summary={'fecha_utc':datetime.now(timezone.utc).isoformat(),'cultivos':CONFIG['cultivos'],'parejas_nuevas':len(summaries),'sucesiones_nuevas':len(summaries)*2,'sucesiones_anteriores':8,'sucesiones_totales':42,
             **{k:sum(s[k] for s in summaries) for k in ['programas','completos_2025','inconclusos_sin_simular','corridas','pares','pasos_diarios']},
             'max_error_balance_mm':max(s['max_error_balance_mm'] for s in summaries),'parejas':summaries,'segundos_ejecucion':time.monotonic()-started}
    m.write_json(OUT/'resumen_general.json',summary)
    inputs=[p for p in (ROOT/'datos').rglob('*') if p.is_file()]+[ROOT/'configuracion.json',Path(__file__),ROOT/'scripts/motor_hidrico_base.py',ROOT/'scripts/motor_vectorizado.py',ROOT/'requirements-simulacion.txt',ROOT/'tests/referencias_publicadas.json']
    m.write_json(OUT/'metodo_y_validacion.json',{'fecha_utc':summary['fecha_utc'],'sitio':site,'configuracion':CONFIG,
                 'metodo':'Balance de cinco capas, mismo motor publicado, vectorizado sobre 144 escenarios independientes por programa. Pruebas de equivalencia incluidas.',
                 'limites':['Datos abiertos regionales y cartográficos, sin medición de finca.','Calendarios fuera de 2025 conservados sin completar clima.','Sin reinicio de suelo; raíces y etapas por calendario, no por estrés.',
                           'Kc único sin ajuste climático, drenaje instantáneo del exceso; sin anegamiento.','Riego idealizado de 20 mm netos con suministro ilimitado; no diseño operativo.',
                           'Temperatura y fotoperíodo descriptivos, sin modificar desarrollo, rendimiento o calidad.','Sin modelos de sanidad, residuos, nutrientes, rendimiento o ingresos.',
                           'Familia botánica sin premio/veto y frijol sin crédito fijo de N.','Ocupación de campo supuesta; almácigo externo y liberación real/curado sin verificar.',
                           'Intervalos 7/14/21 son sensibilidad de operaciones, no garantías de secado ni descanso sanitario.','No etiqueta observada de éxito/fracaso, probabilidad ni recomendación validada.'],
                 'archivos_fuente_sha256':[{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(inputs)]})
    print(json.dumps({k:x for k,x in summary.items() if k!='parejas'},ensure_ascii=False,indent=2),flush=True)


if __name__=='__main__':main()
