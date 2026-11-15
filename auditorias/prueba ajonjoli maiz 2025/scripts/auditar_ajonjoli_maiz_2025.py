"""Comparación retrospectiva ajonjolí→maíz y maíz→ajonjolí, sin calibración local."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
cache=ROOT.parents[1]/'tmp/sim-deps'
if cache.exists():sys.path.insert(0,str(cache))
from scripts import motor_hidrico_base as m
import csv, gzip, hashlib, io, itertools, json
from datetime import date, timedelta, datetime, timezone
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import numpy as np

OUT=ROOT/'resultados'
OUT.mkdir(exist_ok=True)
m.OUT=OUT
PARAM=m.load(ROOT/'datos/cultivos/parametros_auditados.json')
DATES=[date(2025,5,1),date(2025,5,15),date(2025,6,1),date(2025,6,15)]
NAMES={'ajonjoli_maiz':'Ajonjolí → maíz','maiz_ajonjoli':'Maíz → ajonjolí'}


def programs():
    result=[]
    for start,sesame,corn,gap,seq in itertools.product(DATES,[100,110,150,180],[90,125],[7,14,21],NAMES):
        crops=['ajonjoli','maiz'] if seq=='ajonjoli_maiz' else ['maiz','ajonjoli']
        durations={'ajonjoli':sesame,'maiz':corn}
        identifier='_'.join(f'{c}{durations[c]}' for c in crops)+f'_gap{gap}_{start}'
        result.append({'id':identifier,'seq':seq,'start':start,'durations':durations,'crops':crops,'gap':gap})
    return result


def configure(program):
    m.INTERVAL_DAYS=program['gap']
    m.CROPS={}
    for crop in program['crops']:
        p=PARAM['cultivos'][crop]
        m.CROPS[crop]={'stages':p['etapas'][str(program['durations'][crop])],
                       'kc':p['kc'],'zr':p['zr'],'p':p['p']}


def calendar(program):
    current=program['start'];segments=[]
    for crop in program['crops']:
        end=current+timedelta(days=program['durations'][crop]-1)
        segments.append({'cultivo':crop,'inicio':current.isoformat(),'fin':end.isoformat()})
        current=end+timedelta(days=program['gap']+1)
    end=date.fromisoformat(segments[-1]['fin'])
    first_end=date.fromisoformat(segments[0]['fin'])
    return {'programa':program['id'],'secuencia':program['seq'],
            'inicio':program['start'].isoformat(),'ajonjoli_dias':program['durations']['ajonjoli'],
            'maiz_dias':program['durations']['maiz'],'intervalo_dias':program['gap'],
            'intervalo_inicio':(first_end+timedelta(days=1)).isoformat(),
            'intervalo_fin':(first_end+timedelta(days=program['gap'])).isoformat(),
            'fin_ciclo':end.isoformat(),'ciclo_cabe_en_2025':end<=m.DAYS[-1],
            'liberacion_final_parcela':'sin_verificar',
            'funcion_intervalo':'secado_y_retiro_ajonjoli' if program['seq']=='ajonjoli_maiz' else 'retiro_maiz_y_preparacion',
            'segmentos':segments,'estado':'fechas_supuestas_sin_fenologia_observada'}


def exposure(program,rows,source):
    """Lluvia descriptiva: no equivale a humedad del grano, infección o anegamiento."""
    cal=calendar(program)
    def rain_between(start,end):
        return sum(r[f'P_{source}_mm'] for r in rows if start<=date.fromisoformat(r['fecha'])<=end)
    result={'P_intervalo_mm':rain_between(date.fromisoformat(cal['intervalo_inicio']),date.fromisoformat(cal['intervalo_fin']))}
    for seg in cal['segmentos']:
        crop=seg['cultivo'];start=date.fromisoformat(seg['inicio']);end=date.fromisoformat(seg['fin'])
        stages=PARAM['cultivos'][crop]['etapas'][str(program['durations'][crop])]
        mid=start+timedelta(days=sum(stages[:2]))
        result[f'P_primeros20_{crop}_mm']=rain_between(start,start+timedelta(days=19))
        result[f'P_ultimos10_{crop}_mm']=rain_between(end-timedelta(days=9),end)
        result[f'P_etapa_media_{crop}_mm']=rain_between(mid,mid+timedelta(days=stages[2]-1))
    return result


def run_one(program,rows,soil,source,soilcase,runoff,initial,irrigate,keep=False):
    configure(program)
    result,detail=m.simulate(rows,soil,source,program['seq'],program['crops'],
                           (program['id'],program['start'],False),soilcase,runoff,initial,irrigate,keep)
    cal=calendar(program)
    result.update(programa=program['id'],inicio=cal['inicio'],fin_ciclo=cal['fin_ciclo'],
                  ajonjoli_dias=cal['ajonjoli_dias'],maiz_dias=cal['maiz_dias'],intervalo_dias=program['gap'],
                  **exposure(program,rows,source))
    for crop in program['crops']:
        segment=next(s for s in result['segmentos'] if s['cultivo']==crop)
        for key in ['ETc_mm','ETa_mm','deficit_mm','riego_mm','dias_Ks_menor_095']:
            result[f'{crop}_{key}']=segment[key]
    for row in detail:row['programa']=program['id']
    return result,detail


def pairs(results):
    fields=['inicio','ajonjoli_dias','maiz_dias','intervalo_dias','fuente_lluvia','suelo_escenario',
            'fraccion_escorrentia_supuesta','fraccion_agua_inicial_enero01','riego_hipotetico']
    groups={}
    for r in results:groups.setdefault(tuple(r[k] for k in fields),{})[r['secuencia']]=r
    output=[]
    for key,group in groups.items():
        assert set(group)==set(NAMES), 'Comparación incompleta'
        a=group['ajonjoli_maiz'];b=group['maiz_ajonjoli']
        output.append({**dict(zip(fields,key)),'programa_inverso':a['programa'],'programa_directo':b['programa'],
                       'deficit_inverso_mm':a['deficit_ET_mm'],'deficit_directo_mm':b['deficit_ET_mm'],
                       'diferencia_deficit_inverso_menos_directo_mm':round(a['deficit_ET_mm']-b['deficit_ET_mm'],5),
                       'deficit_maiz_inverso_mm':a['maiz_deficit_mm'],'deficit_maiz_directo_mm':b['maiz_deficit_mm'],
                       'riego_inverso_mm':a['riego_neto_mm'],'riego_directo_mm':b['riego_neto_mm']})
    return output


def write_gzip(path,payload):
    with gzip.GzipFile(filename=str(path),mode='wb',mtime=0) as stream:stream.write(payload.encode('utf-8'))


def render(calendars,core,daily):
    colors={'imerg':'#2b6cb0','chirps':'#237a57','era5':'#b7791f','power':'#8c4da8'}
    fig,axs=plt.subplots(2,1,figsize=(11,8),layout='constrained')
    for i,source in enumerate(m.LABELS):
        selected=[r for r in core if r['fuente_lluvia']==source and r['intervalo_dias']==14 and not r['riego_hipotetico']]
        vals=[next(r['deficit_ET_mm'] for r in selected if r['secuencia']==seq) for seq in NAMES]
        axs[0].bar(np.arange(2)+(i-1.5)*.18,vals,.18,color=colors[source],label=m.LABELS[source])
    axs[0].set(xticks=[0,1],xticklabels=list(NAMES.values()),ylabel='Déficit simulado de ET (mm)',
               title='Inicio 15 mayo · ajonjolí 110 d · maíz 90 d · intervalo 14 d\nSecano; mismo inicio y duraciones; sin estimación de rendimiento')
    axs[0].legend(ncol=2,frameon=False,fontsize=8)
    ref='ajonjoli110_maiz90_gap14_2025-05-15'
    for source in m.LABELS:
        d=[r for r in daily if r['programa']==ref and r['fuente_lluvia']==source and not r['riego_hipotetico']]
        axs[1].plot([date.fromisoformat(r['fecha']) for r in d],[r['agua_disponible_perfil_final_mm'] for r in d],color=colors[source],lw=1.4)
    axs[1].axvspan(date(2025,9,16),date(2025,12,14),color='#b7791f',alpha=.08)
    axs[1].text(date(2025,10,28),138,'Maíz: ciclo supuesto',ha='center',fontsize=9)
    axs[1].set(xlim=(date(2025,5,1),m.DAYS[-1]),ylim=(0,145),ylabel='Agua disponible simulada\n0–100 cm (mm)',xlabel='Mes de 2025',title='Ajonjolí → maíz: reserva continua, sin reiniciar el suelo')
    axs[1].xaxis.set_major_locator(mdates.MonthLocator());axs[1].xaxis.set_major_formatter(mdates.DateFormatter('%m'))
    for ax in axs:ax.grid(axis='y',alpha=.18)
    fig.savefig(OUT/'comparacion_hidrica.png',dpi=150);plt.close(fig)
    selected=[c for c in calendars if c['secuencia']=='ajonjoli_maiz' and c['maiz_dias']==90 and c['inicio']=='2025-05-15']
    fig,ax=plt.subplots(figsize=(11,7),layout='constrained')
    for i,c in enumerate(selected):
        one,two=c['segmentos'];first=date.fromisoformat(one['inicio']);second=date.fromisoformat(two['inicio'])
        ax.barh(i,c['ajonjoli_dias'],left=mdates.date2num(first),height=.55,color='#237a57')
        ax.barh(i,c['intervalo_dias'],left=mdates.date2num(date.fromisoformat(one['fin'])+timedelta(days=1)),height=.55,color='#aaaaaa')
        ax.barh(i,c['maiz_dias'],left=mdates.date2num(second),height=.55,color='#b7791f' if c['ciclo_cabe_en_2025'] else '#a74532')
    ax.set(yticks=range(len(selected)),yticklabels=[f"Ajonjolí {c['ajonjoli_dias']} d · intervalo {c['intervalo_dias']} d" for c in selected],
           xlabel='Mes y año · fechas supuestas',title='Ajonjolí → maíz · inicio 15 mayo · maíz de 90 días\nVerde: ajonjolí · gris: secado/retiro · amarillo/rojo: maíz dentro/fuera de 2025')
    ax.axvline(date(2025,12,31),color='#222',ls='--',label='Fin de datos');ax.legend(frameon=False)
    ax.xaxis.set_major_locator(mdates.MonthLocator());ax.xaxis.set_major_formatter(mdates.DateFormatter('%m/%Y'));ax.grid(axis='x',alpha=.18)
    fig.savefig(OUT/'calendarios_y_limite_2025.png',dpi=150);plt.close(fig)


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    site,soil=m.static_site();rows,_,_=m.weather(site['elevacion_dsm_m']);m.events(rows)
    plans=programs();calendars=[calendar(p) for p in plans]
    eligible=[p for p,c in zip(plans,calendars) if c['ciclo_cabe_en_2025']]
    results=[];daily=[]
    for p,source,soilcase,runoff,initial,water in itertools.product(eligible,m.LABELS,m.SOILS,[0.,.15,.30],[.25,.75],[False,True]):
        keep=p['start']==date(2025,5,15) and p['durations']=={'ajonjoli':110,'maiz':90} and soilcase[0]=='perfil_referencia' and runoff==.15 and initial==.25
        result,detail=run_one(p,rows,soil,source,soilcase,runoff,initial,water,keep)
        results.append(result);daily.extend(detail)
    core=[r for r in results if r['inicio']=='2025-05-15' and r['ajonjoli_dias']==110 and r['maiz_dias']==90 and r['suelo_escenario']=='perfil_referencia' and r['fraccion_escorrentia_supuesta']==.15 and r['fraccion_agua_inicial_enero01']==.25]
    m.write_json(OUT/'calendarios_evaluados.json',calendars)
    m.write_csv(OUT/'calendarios_evaluados.csv',[{k:v for k,v in c.items() if k!='segmentos'} for c in calendars])
    m.write_csv(OUT/'resultados_escenarios.csv',[{k:v for k,v in r.items() if k!='segmentos'} for r in results])
    write_gzip(OUT/'resultados_escenarios.json.gz',json.dumps(results,ensure_ascii=False,allow_nan=False))
    table=io.StringIO();writer=csv.DictWriter(table,fieldnames=list(daily[0]));writer.writeheader();writer.writerows(daily)
    write_gzip(OUT/'balances_referencia.csv.gz',table.getvalue())
    m.write_json(OUT/'comparacion_referencia.json',core)
    paired=pairs(results);m.write_csv(OUT/'comparacion_pareada.csv',paired)
    dry_pairs=[r for r in paired if not r['riego_hipotetico']]
    differences=[r['diferencia_deficit_inverso_menos_directo_mm'] for r in dry_pairs]
    m.write_json(OUT/'hallazgos.json',{
        'calendarios_por_direccion':len(plans)//2,'completos_por_direccion':len(eligible)//2,
        'inconclusos_por_direccion':(len(plans)-len(eligible))//2,
        'pares_secano':len(dry_pairs),'inverso_mayor_deficit':sum(d>1e-4 for d in differences),
        'inverso_menor_deficit':sum(d<-1e-4 for d in differences),
        'tolerancia_diferencia_mm':1e-4,'pares_dentro_tolerancia':sum(abs(d)<=1e-4 for d in differences),
        'diferencia_min_mm':min(differences),'diferencia_max_mm':max(differences),
        'nota':'Conteos de una malla de supuestos; no son probabilidades ni frecuencias de campo.',
        'referencia_secano_gap14':[{k:v for k,v in r.items() if k!='segmentos'} for r in core if r['intervalo_dias']==14 and not r['riego_hipotetico']]})
    render(calendars,core,daily)
    inputs=[p for p in (ROOT/'datos').rglob('*') if p.is_file()]
    inputs += [ROOT/'scripts/motor_hidrico_base.py',Path(__file__),ROOT/'requirements-simulacion.txt',ROOT/'tests/referencia_directa_publicada.json']
    manifest={'fecha_utc':datetime.now(timezone.utc).isoformat(),'fecha_local_auditoria':'2026-11-15',
              'alternativa_solicitada':'ajonjolí→maíz','comparador':'maíz→ajonjolí recalculado con el mismo intervalo',
              'sitio':site,'modo':'hindcast retrospectivo de 2025; sin calibración ni validación de finca',
              'programas_calendario':len(plans),'programas_completos_2025':len(eligible),
              'programas_fuera_2025':len(plans)-len(eligible),'combinaciones_por_programa':144,
              'escenarios_simulados':len(results),'comparaciones_pareadas':len(paired),'pasos_diarios':len(results)*365,
              'max_error_balance_mm':max(r['max_error_balance_mm'] for r in results),
              'motor_base_commit':'244ef10e99d8d8375aeebfcdced94cfae6fdc5f5',
              'cambios_motor':['Salida en resultados/ y parámetro INTERVAL_DAYS; contabilidad y ecuaciones conservadas.'],
              'supuestos':['Misma meteorología y suelo de 14.8250, −89.5312; no se consultaron de nuevo las API.',
                           'Intervalo 7/14/21 días completos. En ajonjolí→maíz incluye secado, retiro y preparación; no se añade otro margen encima.',
                           'Los ciclos MAGA 150/180 podrían incluir cosecha: añadir intervalo es sensibilidad operativa, no duración validada.',
                           'Cierre del último ciclo no garantiza cosecha seca ni parcela liberada; sin margen final validado.',
                           'Kc único; raíces por calendario, profundidad máxima 1 m; sin respuesta térmica ni nutrientes.',
                           'Balance de cinco capas continuo desde 1 enero, sin reinicio entre cultivos; Kc sin cultivo 0.20.',
                           'Drenaje instantáneo del exceso; no simula anegamiento ni secado de grano, residuos o tallos.',
                           'Escorrentía 0/15/30%, reserva inicial 25/75%, raíces 40 cm y almacenamiento -25% como sensibilidades.',
                           'Riego hipotético de 20 mm netos al superar RAW, suministro ilimitado; sin plan operativo ni dosis recomendada.',
                           'No se extrapola a 2026 ni se simulan ciclos incompletos con lluvia cero.',
                           'Sin bono de nitrógeno, ruptura sanitaria, rendimiento, rentabilidad ni probabilidad de éxito.'],
              'archivos_fuente_sha256':[{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(inputs)]}
    m.write_json(OUT/'metodo_y_validacion.json',manifest)
    print(json.dumps({k:manifest[k] for k in ['programas_calendario','programas_completos_2025','programas_fuera_2025','escenarios_simulados','comparaciones_pareadas','pasos_diarios','max_error_balance_mm']},ensure_ascii=False,indent=2))
    print(json.dumps([{k:r[k] for k in ['secuencia','intervalo_dias','fuente_lluvia','deficit_ET_mm','maiz_deficit_mm','dias_Ks_menor_095','P_intervalo_mm']} for r in core if r['intervalo_dias']==14 and not r['riego_hipotetico']],ensure_ascii=False,indent=2))


if __name__=='__main__':main()
