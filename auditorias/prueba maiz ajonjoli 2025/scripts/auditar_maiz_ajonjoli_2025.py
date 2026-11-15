"""Auditoría reproducible de maíz→ajonjolí. Ejecutar desde la carpeta de la prueba."""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
if (ROOT.parents[1]/'tmp/sim-deps').exists():
    sys.path.insert(0, str(ROOT.parents[1]/'tmp/sim-deps'))
from scripts import motor_hidrico_base as m
import copy
import csv
import gzip
import hashlib
import itertools
import json
from datetime import date, timedelta, datetime, timezone
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

OUT = ROOT/'resultados'
OUT.mkdir(exist_ok=True)
m.OUT = OUT
PARAM = m.load(ROOT/'datos/cultivos/parametros_auditados.json')
DATES = [date(2025,5,1),date(2025,5,15),date(2025,6,1),date(2025,6,15)]
NAME = {'maiz_solo':'Maíz solo', 'maiz_frijol':'Maíz → frijol', 'maiz_ajonjoli':'Maíz → ajonjolí'}


def programs():
    out=[]
    for start, corn in itertools.product(DATES,[90,125]):
        out.append({'id':f'maiz{corn}_{start.isoformat()}', 'seq':'maiz_solo', 'start':start, 'durations':{'maiz':corn}, 'crops':['maiz']})
        bean=70 if corn==90 else 95
        out.append({'id':f'maiz{corn}_frijol{bean}_{start.isoformat()}', 'seq':'maiz_frijol', 'start':start, 'durations':{'maiz':corn,'frijol':bean}, 'crops':['maiz','frijol']})
        for sesame in [100,110,150,180]:
            out.append({'id':f'maiz{corn}_ajonjoli{sesame}_{start.isoformat()}', 'seq':'maiz_ajonjoli', 'start':start, 'durations':{'maiz':corn,'ajonjoli':sesame}, 'crops':['maiz','ajonjoli']})
    return out


def configure(program):
    m.CROPS={}
    for crop in program['crops']:
        p=PARAM['cultivos'][crop]
        m.CROPS[crop]={'stages':p['etapas'][str(program['durations'][crop])], 'kc':p['kc'], 'zr':p['zr'], 'p':p['p']}


def calendar(program):
    current=program['start']; seg=[]
    for crop in program['crops']:
        end=current+timedelta(days=program['durations'][crop]-1)
        seg.append({'cultivo':crop,'inicio':current.isoformat(),'fin':end.isoformat()})
        current=end+timedelta(days=8)
    final=date.fromisoformat(seg[-1]['fin'])
    dry_end=final+timedelta(days=14) if program['seq']=='maiz_ajonjoli' else final
    return {'programa':program['id'],'secuencia':program['seq'],'inicio':program['start'].isoformat(),'maiz_dias':program['durations']['maiz'],'segundo_cultivo_dias':program['durations'].get('ajonjoli',program['durations'].get('frijol',0)),'fin_ciclo':final.isoformat(),'fin_con_margen_secado_14d':dry_end.isoformat(),'ciclo_cabe_en_2025':final<=m.DAYS[-1],'con_margen_secado_cabe_2025':dry_end<=m.DAYS[-1],'segmentos':seg,'estado':'calendario_supuesto_sin_fenologia_observada'}


def exposure(rows,segments,source):
    """Exposición meteorológica; no calcula anegamiento, infección ni pérdidas."""
    if len(segments)<2:return {}
    s=segments[-1]; start=date.fromisoformat(s['inicio']); end=date.fromisoformat(s['fin']); first=[r for r in rows if start<=date.fromisoformat(r['fecha'])<=start+timedelta(days=19)];last=[r for r in rows if end-timedelta(days=9)<=date.fromisoformat(r['fecha'])<=end]
    return {'P_primeros20dias_segundo_mm':sum(r[f'P_{source}_mm'] for r in first),'dias_P_ge20_primeros20':sum(r[f'P_{source}_mm']>=20 for r in first),'P_ultimos10dias_segundo_mm':sum(r[f'P_{source}_mm'] for r in last),'Tmax_media_primeros20_C':float(np.mean([r['T2M_MAX'] for r in first])),'drenaje_parcela':'no_medido','comprador':'no_identificado'}


def run_one(program,rows,soil,source,soilcase,runoff,initial,water,keep=False):
    configure(program)
    # short=False: las etapas se fijaron por cultivo en configure, sin usar el atajo maíz/frijol del motor.
    result,detail=m.simulate(rows,soil,source,program['seq'],program['crops'],(program['id'],program['start'],False),soilcase,runoff,initial,water,keep)
    c=calendar(program)
    result.update(programa=program['id'],fin_ciclo=c['fin_ciclo'],con_margen_secado_cabe_2025=c['con_margen_secado_cabe_2025'],**exposure(rows,result['segmentos'],source))
    for d in detail:d['programa']=program['id']
    return result,detail


def render(calendars,results,daily,events):
    colors={'imerg':'#2b6cb0','chirps':'#237a57','era5':'#b7791f','power':'#8c4da8'}
    core=[r for r in results if r['programa'] in ['maiz90_frijol70_2025-05-15','maiz90_ajonjoli110_2025-05-15'] and r['suelo_escenario']=='perfil_referencia' and r['fraccion_escorrentia_supuesta']==.15 and r['fraccion_agua_inicial_enero01']==.25 and not r['riego_hipotetico']]
    fig,axs=plt.subplots(2,1,figsize=(11,8),layout='constrained')
    for i,source in enumerate(m.LABELS):
        values=[next(r['deficit_ET_mm'] for r in core if r['secuencia']==seq and r['fuente_lluvia']==source) for seq in ['maiz_frijol','maiz_ajonjoli']]
        axs[0].bar(np.arange(2)+(i-1.5)*.18,values,.18,color=colors[source],label=m.LABELS[source])
    axs[0].set(xticks=[0,1],xticklabels=['Maíz → frijol\n90 + 70 días','Maíz → ajonjolí\n90 + 110 días'],ylabel='Déficit simulado de ET (mm)',title='Inicio 15 de mayo · secano · intervalo de 7 días\nDuraciones diferentes; déficit acumulado no equivale a pérdida de cosecha')
    axs[0].legend(ncol=2,frameon=False,fontsize=8)
    for source in m.LABELS:
        d=[r for r in daily if r['programa']=='maiz90_ajonjoli110_2025-05-15' and r['fuente_lluvia']==source and not r['riego_hipotetico']]
        axs[1].plot([date.fromisoformat(r['fecha']) for r in d],[r['agua_disponible_perfil_final_mm'] for r in d],color=colors[source],label=m.LABELS[source],lw=1.3)
    axs[1].set(xlim=(date(2025,5,1),m.DAYS[-1]),ylim=(0,145),ylabel='Agua disponible simulada\n0–100 cm (mm)',xlabel='Mes de 2025',title='Maíz → ajonjolí: continuidad del agua; drenaje real sin verificar')
    axs[1].axvspan(date(2025,8,20),date(2025,12,7),color='#777777',alpha=.06)
    axs[1].text(date(2025,10,10),138,'Ajonjolí: ciclo supuesto',ha='center',fontsize=9)
    axs[1].xaxis.set_major_locator(mdates.MonthLocator());axs[1].xaxis.set_major_formatter(mdates.DateFormatter('%m'))
    for ax in axs:ax.grid(axis='y',alpha=.18)
    fig.savefig(OUT/'comparacion_hidrica.png',dpi=150);plt.close(fig)
    selected=[c for c in calendars if c['secuencia']=='maiz_ajonjoli' and c['maiz_dias']==90 and (c['segundo_cultivo_dias']==110 or c['inicio']=='2025-05-15')]
    fig,ax=plt.subplots(figsize=(11,7),layout='constrained')
    for i,c in enumerate(selected):
        a,b=c['segmentos'];x0=date.fromisoformat(a['inicio']);x1=date.fromisoformat(b['inicio']);xe=date.fromisoformat(b['fin']);
        ax.barh(i,c['maiz_dias'],left=mdates.date2num(x0),height=.5,color='#b7791f')
        ax.barh(i,c['segundo_cultivo_dias'],left=mdates.date2num(x1),height=.5,color='#237a57' if c['ciclo_cabe_en_2025'] else '#a74532')
        ax.barh(i,14,left=mdates.date2num(xe+timedelta(days=1)),height=.5,color='#999999',alpha=.5)
    ax.set(yticks=range(len(selected)),yticklabels=[f"{c['inicio'][5:]} · ajonjolí {c['segundo_cultivo_dias']} d" for c in selected],title='Calendarios supuestos: maíz de 90 días y ajonjolí\nGris: margen de secado de 14 días; rojo: ciclo fuera de 2025',xlabel='Mes y año · fechas calculadas, sin simular clima de 2026')
    ax.axvline(date(2025,12,31),color='#222222',ls='--',label='Fin de datos: 31 dic 2025');ax.legend(frameon=False)
    ax.xaxis.set_major_locator(mdates.MonthLocator());ax.xaxis.set_major_formatter(mdates.DateFormatter('%m/%Y'));ax.grid(axis='x',alpha=.18)
    fig.savefig(OUT/'calendarios_y_limite_2025.png',dpi=150);plt.close(fig)


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    site,soil=m.static_site();rows,power,era=m.weather(site['elevacion_dsm_m']);events=m.events(rows)
    plans=programs();calendars=[calendar(p) for p in plans];eligible=[p for p,c in zip(plans,calendars) if c['ciclo_cabe_en_2025']]
    results=[];daily=[]
    for p,source,soilcase,runoff,initial,water in itertools.product(eligible,m.LABELS,m.SOILS,[0.,.15,.30],[.25,.75],[False,True]):
        keep=p['id'] in ['maiz90_frijol70_2025-05-15','maiz90_ajonjoli110_2025-05-15','maiz90_ajonjoli110_2025-06-01'] and soilcase[0]=='perfil_referencia' and runoff==.15 and initial==.25
        result,detail=run_one(p,rows,soil,source,soilcase,runoff,initial,water,keep)
        results.append(result);daily.extend(detail)
    m.write_json(OUT/'calendarios_evaluados.json',calendars)
    m.write_csv(OUT/'calendarios_evaluados.csv',[{k:v for k,v in c.items() if k!='segmentos'} for c in calendars])
    fields=sorted({k for r in results for k in r if k!='segmentos'})
    with (OUT/'resultados_escenarios.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows({k:r.get(k) for k in fields} for r in results)
    with gzip.GzipFile(filename=str(OUT/'resultados_escenarios.json.gz'),mode='wb',mtime=0) as f:f.write(json.dumps(results,ensure_ascii=False,allow_nan=False).encode('utf-8'))
    with gzip.GzipFile(filename=str(OUT/'balances_referencia.csv.gz'),mode='wb',mtime=0) as f:
        import io
        text=io.StringIO();w=csv.DictWriter(text,fieldnames=list(daily[0]));w.writeheader();w.writerows(daily);f.write(text.getvalue().encode('utf-8'))
    core=[r for r in results if r['programa'] in ['maiz90_frijol70_2025-05-15','maiz90_ajonjoli110_2025-05-15','maiz90_ajonjoli110_2025-06-01'] and r['suelo_escenario']=='perfil_referencia' and r['fraccion_escorrentia_supuesta']==.15 and r['fraccion_agua_inicial_enero01']==.25]
    m.write_json(OUT/'comparacion_referencia.json',core)
    render(calendars,results,daily,events)
    originals=ROOT.parents[0]/'prueba frijol maiz 2025'
    # Rutas del paquete, sin depender de que la prueba anterior siga presente.
    srcfiles=[p for p in (ROOT/'datos').rglob('*') if p.is_file()]+[ROOT/'scripts/motor_hidrico_base.py',Path(__file__),ROOT/'requirements-simulacion.txt']
    manifest={'fecha_utc':datetime.now(timezone.utc).isoformat(),'fecha_local_auditoria':'2026-11-15','alternativa_solicitada':'maíz→ajonjolí','sitio':site,'modo':'hindcast retrospectivo de 2025 con parámetros no calibrados','programas_calendario':len(plans),'programas_completos_2025':len(eligible),'programas_fuera_2025':len(plans)-len(eligible),'combinaciones_por_programa':144,'escenarios_simulados':len(results),'pasos_diarios':len(results)*365,'max_error_balance_mm':max(r['max_error_balance_mm'] for r in results),'calendarios_ajonjoli_2025':[c for c in calendars if c['secuencia']=='maiz_ajonjoli' and c['ciclo_cabe_en_2025']],'metodo_base':'Balance de cinco capas de la prueba frijol/maíz publicada en commit 7c18ff91b52bca410ea37552143881f699ac4d44; motor conservado para comparabilidad.','supuestos':['Misma meteorología 2025 y mismo suelo del candidato 14.8250, −89.5312.','Kc único, raíces crecen por calendario y no por estrés; sin fertilidad ni rendimiento.','Drenaje instantáneo del exceso y escorrentía supuesta: no permite diagnosticar anegamiento.','Suelo sin cultivo Kc=0.20; raíces de ajonjolí limitadas a 1 m por profundidad del perfil.','Reserva inicial 25/75%, escorrentía 0/15/30%, raíces limitadas a 40 cm o almacenamiento -25% como sensibilidad.','Riego hipotético de 20 mm al superar RAW, sin límite de suministro: no dosis recomendada.','No se extrapola clima a 2026 ni se completan con ceros los calendarios inconclusos.','Margen de 14 días de secado es sensibilidad externa NC State; no fenología local validada.','Fecha final del maíz es retiro supuesto; ciclo de variedad no garantiza terreno liberado.','No se asignan probabilidad de éxito, margen comercial, saneamiento ni compatibilidad aprobada.'],'archivos_fuente_sha256':[{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in srcfiles]}
    m.write_json(OUT/'metodo_y_validacion.json',manifest)
    print(json.dumps({'programas':len(plans),'completos_2025':len(eligible),'corridas':len(results),'error_balance':manifest['max_error_balance_mm'],'referencia':[{'programa':r['programa'],'fuente':r['fuente_lluvia'],'riego':r['riego_hipotetico'],'deficit_ET_mm':r['deficit_ET_mm'],'dias_estres':r['dias_Ks_menor_095'],'secado_cabe_2025':r['con_margen_secado_cabe_2025'],'P_primeros20dias_segundo_mm':r.get('P_primeros20dias_segundo_mm')} for r in core]},ensure_ascii=False,indent=2))


if __name__=='__main__':main()
