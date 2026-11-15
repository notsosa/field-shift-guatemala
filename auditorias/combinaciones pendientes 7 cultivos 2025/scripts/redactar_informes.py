"""Genera informes, cobertura y tablas descriptivas a partir de salidas verificables."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
cache=ROOT.parents[1]/'tmp/sim-deps'
if cache.exists():sys.path.insert(0,str(cache))
from scripts import auditar_7_cultivos_2025 as a
import csv,json,itertools,math
from datetime import date,timedelta
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
from matplotlib.patches import Patch

N=a.NAMES
EVIDENCE=a.m.load(ROOT/'fuentes/criterios_7_cultivos.json')
SOURCES={'imerg':'IMERG V07 Late','chirps':'CHIRPS v2','era5':'ERA5','power':'POWER'}
OLD={frozenset(['maiz','frijol']):'prueba frijol maiz 2025',frozenset(['maiz','ajonjoli']):'prueba ajonjoli maiz 2025',frozenset(['papa','cebolla']):'prueba papa cebolla 2025',frozenset(['brocoli','lechuga']):'prueba brocoli lechuga 2025'}


def csv_rows(path):
    with path.open(encoding='utf-8',newline='') as stream:return list(csv.DictReader(stream))


def pair_report(pair,weather):
    key='_'.join(pair);out=ROOT/'parejas'/key;summary=a.m.load(out/'resumen.json');core=a.m.load(out/'referencia.json');cal=a.m.load(out/'calendarios.json')
    direct=key;reverse='_'.join(pair[::-1]);title=' ↔ '.join(N[c] for c in pair)
    refs=[p for p in a.programs(pair) if a.is_reference(p)];refcal=[a.calendar(p) for p in refs]
    def r(seq,source,water=False):return next(x for x in core if x['secuencia']==seq and x['fuente_lluvia']==source and x['riego_hipotetico']==water)
    parameters='\n'.join(f"| {N[c]} | {a.PARAM[c]['especie']} · {a.PARAM[c]['familia']} | {' / '.join(str(x) for x in a.PARAM[c]['kc'])} | {a.PARAM[c]['zr']} m | {a.PARAM[c]['p']} | {', '.join(a.PARAM[c]['etapas'])} |" for c in pair)
    dates='\n'.join('| '+' → '.join(N[s['cultivo']] for s in x['segmentos'])+' | '+' | '.join(s['inicio']+' a '+s['fin'] for s in x['segmentos'])+' |' for x in refcal)
    water_table='\n'.join(f"| {name} | {r(direct,s)['deficit_ET_mm']:.2f} | {r(reverse,s)['deficit_ET_mm']:.2f} | {r(direct,s)['dias_Ks_menor_095']} / {r(reverse,s)['dias_Ks_menor_095']} | {r(direct,s,True)['riego_neto_mm']:.0f} / {r(reverse,s,True)['riego_neto_mm']:.0f} |" for s,name in SOURCES.items())
    climate=csv_rows(out/'exposicion_referencia.csv')
    temp_table='\n'.join(f"| {'Directa' if x['secuencia']==direct else 'Inversa'} · {N[x['cultivo']]} | {x['fuente_temperatura'].upper()} | {float(x['Tmedia_C']):.2f} | {x['dias_Tmedia_mayor_24C']} / {x['dias']} | {x['dias_Tmax_mayor_30C']} / {x['dias']} |" for x in climate)
    intervals=[]
    for c in refcal:
        first,second=c['segmentos'];start=date.fromisoformat(first['fin'])+timedelta(days=1);end=date.fromisoformat(second['inicio'])-timedelta(days=1)
        sub=[w for w in weather if start.isoformat()<=w['fecha']<=end.isoformat()];assert len(sub)==14
        for source in SOURCES:
            intervals.append({'secuencia':c['secuencia'],'inicio':start.isoformat(),'fin':end.isoformat(),'dias':len(sub),'fuente_lluvia':source,
                              'P_intervalo_mm':sum(float(w['P_'+source+'_mm']) for w in sub),'dias_P_ge1mm':sum(float(w['P_'+source+'_mm'])>=1 for w in sub)})
    a.m.write_csv(out/'intervalos_referencia.csv',intervals)
    gaps='\n'.join(f"| {'Directa' if x['secuencia']==direct else 'Inversa'} | {x['inicio']} a {x['fin']} | {SOURCES[x['fuente_lluvia']]} | {x['P_intervalo_mm']:.1f} |" for x in intervals)
    shared=set(pair)<=set(EVIDENCE['regla_hospedaje_compartido']['cultivos'])
    if shared:
        sanitary='**Alerta potencial por hospedaje compartido de *Meloidogyne incognita*.** Las fuentes por cultivo/grupo están en el registro común. Se necesita identificar organismo/población y susceptibilidad del material local; no demuestra infección en esta parcela. Para frijol la evidencia es de Dry Beans y para brócoli del grupo de coles. No se asigna una penalización ni un efecto sanitario del orden.'
    else:
        sanitary='**Sanidad sin resolver para esta pareja.** La revisión selectiva no incorpora una alerta de hospedaje compartido para ambos cultivos en su regla actual. Eso no acredita ausencia de organismos compartidos, inocuidad ni ruptura sanitaria. Ajonjolí y maíz no se clasifican como no hospedantes por falta de una alerta. Hace falta diagnóstico dirigido y comprobar el material.'
    alerts='\n'.join('- **'+N[c]+':** '+' '.join(EVIDENCE['cultivos'][c]['alertas']) for c in pair)
    source_links='\n'.join('- '+N[c]+': '+', '.join(f'[fuente {i+1}]({url})' for i,url in enumerate(EVIDENCE['cultivos'][c]['fuentes']))+'. Alcance de lectura y límites en [criterios comunes](../../fuentes/criterios_7_cultivos.json).' for c in pair)
    direct_wins=[name for s,name in SOURCES.items() if r(direct,s)['deficit_ET_mm']<r(reverse,s)['deficit_ET_mm']-1e-4]
    reverse_wins=[name for s,name in SOURCES.items() if r(reverse,s)['deficit_ET_mm']<r(direct,s)['deficit_ET_mm']-1e-4]
    verdict=f"En la referencia, la dirección directa acumula menor déficit con {len(direct_wins)} de las cuatro lluvias y la inversa con {len(reverse_wins)}. Esto describe ese calendario y no una superioridad general."
    cool=set(pair)&{'papa','brocoli','lechuga'}
    if cool:verdict+=' La adaptación al candidato cálido de '+', '.join(N[c] for c in sorted(cool))+' debe comprobarse antes de recomendar la sucesión.'
    text=f'''# Auditoría {title} · Chiquimula · 2025

**Direcciones evaluadas:** {' → '.join(N[c] for c in pair)} y {' → '.join(N[c] for c in pair[::-1])}. Entrega del 15 de noviembre de 2026, punto **14.8250, −89.5312**. Sucesiones estrictas, sin coexistencia y sin repeticiones. [Volver a la cobertura de los siete cultivos](../../README.md).

**Dictamen:** {verdict} La compatibilidad sanitaria, el rendimiento y la rentabilidad permanecen sin validar. Esta entrega no incorpora un ensayo local específico de esta pareja; compara agua/calendario y conserva las condiciones documentadas por mecanismo.

## Alcance y parámetros

**{summary['programas']:,} calendarios**; **{summary['completos_2025']:,} completos** en 2025 y **{summary['inconclusos_sin_simular']:,} inconclusos**, conservados solo como fechas. Se ejecutaron **{summary['corridas']:,} corridas** y **{summary['pares']:,} comparaciones pareadas**. Ambos sentidos tienen la misma cantidad de escenarios.

| Cultivo/producto | Identidad y familia | Kc inicial / medio / final | Raíz | p | Duraciones (días) |
|---|---|---:|---:|---:|---|
{parameters}

Los productos, etapas y notas se conservan en [parámetros](../../datos/cultivos/parametros_auditados.json). [FAO-56, tablas 11/12](https://www.fao.org/4/x0490e/x0490e0b.htm) y [tabla 22](https://www.fao.org/4/x0490e/x0490e0e.htm) son referencias sin calibración de parcela. Kc inicial puede proceder del grupo. El cambio de familia no genera premio, veto ni crédito de nitrógeno.

## Caso de referencia

Inicio común **1 de marzo de 2025**, duraciones de referencia {'; '.join(N[c]+' '+str(a.CONFIG['referencia_duraciones'][c])+' días' for c in pair)}, **14 días completos** entre cultivos. Perfil de referencia, escorrentía supuesta 15%, reserva al 1 de enero 25%. El agua se conserva entre cultivos.

| Dirección | Primer cultivo | Segundo cultivo |
|---|---|---|
{dates}

| Lluvia | Déficit directo secano (mm) | Déficit inverso secano (mm) | Días Ks<0.95 directo/inverso | Riego idealizado directo/inverso (mm netos) |
|---|---:|---:|---:|---:|
{water_table}

La última columna corresponde a corridas separadas con pulsos de 20 mm netos al superar RAW y suministro ilimitado; no es una dosis recomendada o agua confirmada. Ver el déficit residual de cada corrida en [referencia](referencia.csv). Un déficit de ET menor no equivale a mayor cosecha o calidad comercial.

![Comparación de referencia](comparacion_hidrica.png)

En los **{summary['pares_secano']:,} pares de secano** de toda la malla, la inversa tiene mayor déficit en **{summary['inverso_mayor_deficit']:,}**, menor en **{summary['inverso_menor_deficit']:,}** y diferencia absoluta de hasta 0.0001 mm en **{summary['pares_en_tolerancia']:,}**. Estos conteos son escenarios diseñados, sin probabilidad de éxito ni representatividad estadística de fincas.

## Temperatura, establecimiento y operaciones

| Dirección y cultivo | Producto térmico | Media del período (°C) | Días media>24 / total | Días Tmax>30 / total |
|---|---|---:|---:|---:|
{temp_table}

POWER T2M es media diaria del producto regional. ERA5 usa semisuma Tmax/Tmin, una aproximación diferente. Tmax no equivale a temperatura media ni de órgano. Los umbrales son indicadores descriptivos; no son una función de daño. El fotoperíodo está en [exposición de referencia](exposicion_referencia.csv); es duración astronómica del día, sin respuesta del cultivo ni nubosidad.

Lluvia durante los intervalos de retiro/preparación del caso de referencia:

| Dirección | Intervalo completo | Lluvia | Total (mm) |
|---|---|---|---:|
{gaps}

Reservar días no demuestra que permitan secado, curado, retiro o entrada de maquinaria. La lluvia acumulada tampoco demuestra anegamiento. El motor drena instantáneamente el exceso; es necesario observar drenaje y humedad reales.

## Condiciones documentales y sanitarias

{alerts}

{sanitary}

Fuentes primarias por cultivo y alcance:

{source_links}

Los documentos de otra región, las fichas comerciales y la evidencia de grupo conservan sus límites. No se atribuye a esta pareja un efecto experimental no leído, una bonificación de N o un saneamiento automático. La [evidencia común](../../fuentes/criterios_7_cultivos.json) conserva antecedentes y vacíos.

## Archivos y reproducción

- [Resumen](resumen.json), [calendarios CSV](calendarios.csv) y [JSON](calendarios.json), incluidos los inconclusos.
- [Todas las corridas CSV.gz](escenarios.csv.gz) y [JSON.gz](escenarios.json.gz); este último conserva segmentos por cultivo.
- [Comparaciones pareadas](comparacion_pareada.csv.gz): diferencia de déficit inverso menos directo.
- [Referencia CSV](referencia.csv) y [JSON](referencia.json): 16 corridas, dos direcciones × cuatro lluvias × secano/riego.
- [Balances de referencia](balances_referencia.csv.gz): 5,840 registros diarios, con reserva y residuo de balance.
- [Exposición de todos los calendarios completos](exposicion_climatica.csv.gz), [exposición de referencia](exposicion_referencia.csv) e [intervalos](intervalos_referencia.csv).

La metodología, código, versiones, datos y reproducción están en el [README común](../../README.md). Cada calendario completo tiene **144 casos**: cuatro lluvias, tres hipótesis de suelo/raíces, tres escorrentías, dos reservas iniciales y secano/riego. Las fechas son supuestas; almácigo externo, cosecha y liberación real se deben comprobar. Los ciclos fuera de 2025 no se completan con lluvia cero.

El modelo no altera crecimiento o cosecha por estrés, temperatura o fotoperíodo. Tampoco calcula patógenos, residuos, nutrientes, rendimiento o ingresos. Estos resultados son sintéticos, sin etiquetas observadas de éxito/fracaso. El agua contablemente conservada y la equivalencia entre implementaciones no sustituyen validación de campo.
'''
    (out/'README.md').write_text(text,encoding='utf-8')


def coverage():
    output=[];master=a.CONFIG['cultivos'];new={frozenset(p):p for p in a.CONFIG['parejas_nuevas']}
    for first,second in itertools.permutations(master,2):
        key=frozenset([first,second]);old=key in OLD
        path='../'+OLD[key]+'/README.md' if old else 'parejas/'+'_'.join(new[key])+'/README.md'
        output.append({'antecesor':first,'sucesor':second,'estado':'evaluacion_exploratoria_anterior' if old else 'evaluacion_exploratoria_nueva',
                       'auditoria':path,'decision_compatibilidad':'requiere_evaluacion_local_y_sanitaria'})
    assert len(output)==42 and len({(r['antecesor'],r['sucesor']) for r in output})==42
    a.m.write_csv(ROOT/'resultados/cobertura_42_sucesiones.csv',output);a.m.write_json(ROOT/'resultados/cobertura_42_sucesiones.json',output)
    matrix=[]
    for first in master:
        matrix.append([0 if first==second else 1 if frozenset([first,second]) in OLD else 2 for second in master])
    fig,ax=plt.subplots(figsize=(9,8),layout='constrained');ax.imshow(matrix,cmap=ListedColormap(['#ededed','#3c6a91','#8a6aa6']),vmin=0,vmax=2)
    for i,row in enumerate(matrix):
        for j,value in enumerate(row):ax.text(j,i,['—','P','N'][value],ha='center',va='center',color='#666' if value==0 else 'white',fontsize=13)
    ax.set(xticks=range(7),xticklabels=[N[c] for c in master],yticks=range(7),yticklabels=[N[c] for c in master],xlabel='Cultivo sucesor',ylabel='Cultivo antecesor',title='Cobertura de 42 sucesiones entre siete cultivos\nEstado de evaluación exploratoria; no puntuación de aptitud')
    ax.legend(handles=[Patch(color='#3c6a91',label='P: 8 previas'),Patch(color='#8a6aa6',label='N: 34 nuevas'),Patch(color='#ededed',label='Repetición fuera del alcance')],loc='upper center',bbox_to_anchor=(.5,-.11),ncol=2,frameon=False)
    fig.savefig(ROOT/'resultados/matriz_cobertura.png',dpi=160);plt.close(fig)
    return output


def main():
    weather=csv_rows(ROOT/'datos/escenarios/chiquimula_2025/entorno_diario_2025.csv')
    for pair in a.CONFIG['parejas_nuevas']:pair_report(pair,weather)
    coverage()
    common_report()
    print('17 informes y cobertura de 42 sucesiones generados.')


def common_report():
    summary=a.m.load(ROOT/'resultados/resumen_general.json')
    table='\n'.join(f"| [{' ↔ '.join(N[c] for c in s['cultivos'])}](parejas/{s['pareja']}/README.md) | {s['programas']:,} | {s['completos_2025']:,} | {s['corridas']:,} |" for s in summary['parejas'])
    parameters='\n'.join(f"| {N[c]} | {a.PARAM[c]['producto']} | {a.PARAM[c]['familia']} | {', '.join(a.PARAM[c]['etapas'])} |" for c in a.CONFIG['cultivos'])
    text=f'''# Combinaciones pendientes de siete cultivos · Chiquimula · 2025

**Fecha:** 15 de noviembre de 2026. Esta entrega completa las **34 sucesiones pendientes**, agrupadas en **17 parejas evaluadas en ambos órdenes**. Con las **8 sucesiones anteriores** queda cubierta la evaluación exploratoria de las **42 sucesiones entre cultivos distintos** de maíz, frijol, ajonjolí, papa, cebolla, brócoli y lechuga.

**Alcance científico:** cobertura de evaluación no equivale a 42 rotaciones aprobadas. Cada dirección tiene resultados de calendario/agua, exposición climática y condiciones documentales. Compatibilidad sanitaria, adaptación de variedad, rendimiento y viabilidad comercial necesitan validación local. Los otros 11 cultivos del catálogo de 18 y las siete repeticiones quedan fuera de esta entrega.

Se evaluaron **{summary['programas']:,} calendarios nuevos**: **{summary['completos_2025']:,} completos** y **{summary['inconclusos_sin_simular']:,} fuera de cobertura de 2025**. Se ejecutaron **{summary['corridas']:,} corridas hídricas nuevas**, **{summary['pares']:,} comparaciones pareadas** y **{summary['pasos_diarios']:,} pasos diarios**.

![Cobertura de las 42 sucesiones](resultados/matriz_cobertura.png)

La [matriz CSV](resultados/cobertura_42_sucesiones.csv) y el [JSON](resultados/cobertura_42_sucesiones.json) tienen una fila por dirección y enlace a su auditoría. P indica evaluación previa y N evaluación nueva; los colores no expresan aptitud o riesgo. Las ocho previas conservan su malla y versiones originales. Las cifras entre carpetas no conforman un ranking homogéneo sin armonizar fechas y supuestos.

## Los 17 informes nuevos

Cada enlace incluye ambas direcciones, datos numéricos, gráficas, fuentes y condiciones pendientes. Por ejemplo, maíz↔cebolla comprende maíz→cebolla y cebolla→maíz.

| Pareja, ambos órdenes | Calendarios | Completos en 2025 | Corridas hídricas |
|---|---:|---:|---:|
{table}

## Entradas y método común

Se conserva el candidato **14.8250, −89.5312**, elegido por el usuario, con los originales congelados del commit `ef51faf83a975656a927bc4934673b668c3a94e9`. El DSM da **373 m**, pendiente local aproximada de 2.6%; SoilGrids estima **130.7 mm de agua disponible en 0–100 cm** y pH superficial cercano a 7. Son estimaciones cartográficas, sin linderos o mediciones de finca confirmados.

La meteorología de 2025 incluye NASA POWER, IMERG V07 **Late**, CHIRPS v2 y ERA5. Las API no se consultaron de nuevo. ET0 se calcula con FAO-56 y meteorología POWER, con presión estimada a 373 m; la temperatura regional no se corrige arbitrariamente por altitud. Las cuatro lluvias son alternativas y no cuatro estaciones o réplicas independientes de campo. GWET, humedad volumétrica ERA5 y agua disponible simulada son magnitudes distintas.

| Cultivo | Producto modelado | Familia | Ciclos supuestos (días) |
|---|---|---|---|
{parameters}

Los [parámetros auditados](datos/cultivos/parametros_auditados.json) preservan etapas, Kc, raíces, p, notas y procedencia. Hay referencias extranjeras y reescalados; no constituyen fenología observada. La inconsistencia de ajonjolí FAO (etapas que suman 110 y total publicado 100) se conserva. En brócoli, 75/90 corresponde a sensibilidad de cosecha principal tras trasplante; 135 es la referencia FAO extranjera. No se usa el ciclo general de 120 días con laterales/semilla como cabeza principal.

Las fechas iniciales son 15 de enero, 1 de marzo, 1/15 de mayo, 1/15 de junio y 1 de septiembre de 2025. Se prueban intervalos de **7/14/21 días completos**. Son escenarios de ocupación del campo, sin almácigo en el sublote. El intervalo incluye retiro/preparación y secado/curado cuando corresponda, sin garantizar su cumplimiento. El cierre del ciclo tampoco garantiza grano seco o liberación efectiva.

Cada calendario completo tiene **144 casos**: cuatro lluvias × tres hipótesis de suelo/raíces × tres escorrentías (0/15/30%) × dos reservas iniciales (25/75%) × secano/riego. Los tres casos de suelo son referencia, profundidad radical limitada a **30 cm** y almacenamiento 25% menor. El límite de 30 cm es una sensibilidad común nueva; algunas auditorías anteriores de granos usaron 40 cm.

El balance conserva agua en cinco capas desde el **1 de enero**, sin reinicio al cosechar. Para cada día calcula lluvia infiltrada, escorrentía supuesta, drenaje, ETc, limitación hídrica, ETa y riego idealizado. Usa raíces por calendario y Kc único. El riego aplica 20 mm netos al superar RAW, con suministro ilimitado; no es una dosis recomendada ni confirma agua entregable.

La [implementación vectorizada](scripts/motor_vectorizado.py) calcula escenarios independientes en columnas, conservando las ecuaciones del [motor original](scripts/motor_hidrico_base.py). Ningún escenario comparte agua con otro. Las pruebas contrastan las 144 variantes de un calendario, los siete cultivos y 48 corridas publicadas con la implementación original.

## Indicadores, evidencia y límites

- **Calendario:** fechas por cultivo y cobertura de datos. Los calendarios que llegan a 2026 se guardan sin rellenar el clima con ceros o extrapolaciones.
- **Agua:** déficit acumulado ETc−ETa, relación ETa/ETc, días Ks<0.95 y riego hipotético. El umbral Ks es descriptivo y no una función validada de daño o pérdida.
- **Temperatura:** POWER aporta media diaria regional; ERA5 usa semisuma Tmax/Tmin como aproximación. Se conservan máximas separadas. Los umbrales de exposición no son límites universales de viabilidad ni temperatura de órgano.
- **Fotoperíodo y labores:** duración astronómica del día y lluvia en intervalos de referencia. No se simulan bulbificación, espigado, secado de grano, días de maquinaria o calidad comercial.
- **Sanidad:** fuentes por cultivo/grupo y alertas potenciales. No se convierten familias o ausencia de una alerta en ruptura sanitaria, inocuidad o un puntaje.

El [registro de criterios](fuentes/criterios_7_cultivos.json) enlaza fuentes primarias, limita la lectura y conserva los antecedentes. Para *Meloidogyne incognita* hay una alerta potencial entre algunos cultivos; para frijol y brócoli parte del respaldo es de grupo. No acredita infección local ni susceptibilidad de todo cultivar. Las combinaciones sin esta alerta siguen requiriendo diagnóstico. Las referencias favorables de ajonjolí o brócoli en otros sistemas no se extrapolan a las parejas nuevas.

No se incorpora un ensayo local específico de cada pareja nueva. Las fechas y raíces no se retrasan por estrés o calor; la temperatura y el fotoperíodo no modifican duración, Kc o rendimiento. El exceso drena instantáneamente, sin anegamiento, nivel freático o flujo lateral. No se modelan residuos, patógenos, fertilidad, fijación/mineralización de N, cosecha, ingresos o costos. Frijol no recibe un crédito fijo de N.

Los conteos de escenarios no son probabilidades de éxito. Un déficit bajo no demuestra aptitud térmica, drenaje adecuado o una cosecha vendible. Las fuentes espaciales y pruebas de software deben contrastarse con mediciones y resultados de campo. Las corridas son sintéticas, sin etiquetas observadas de éxito/fracaso para entrenar una red neuronal.

## Comparación de referencia

Cada pareja utiliza ambos órdenes desde el **1 de marzo**, intervalo de **14 días** y duraciones de referencia explícitas en [configuración](configuracion.json). Hay 16 corridas por pareja: dos órdenes × cuatro lluvias × secano/riego, con suelo de referencia, escorrentía 15% y reserva inicial 25%. Se conservan **5,840 registros diarios por pareja** para verificar continuidad y balance.

La comparación cambia únicamente el orden dentro de cada par equivalente. El número de días y la demanda entre parejas distintas pueden cambiar; no se debe construir un ranking global solo con déficit acumulado. Los siete inicios y todas las duraciones están incluidos en los resultados completos, no únicamente la referencia de marzo.

## Reproducción y controles

Desde esta carpeta, con Python 3.12:

```sh
python -m venv .venv
# Activar el entorno según el sistema operativo.
python -m pip install -r requirements-simulacion.txt
python scripts/auditar_7_cultivos_2025.py
python scripts/redactar_informes.py
python scripts/verificar_paquete.py
```

La simulación lee los originales incluidos, sin credenciales ni nuevas descargas. Si existe `tmp/sim-deps` del workspace, se incorpora al proceso; una copia independiente usa las dependencias fijadas. Las fechas de ejecución e inventarios pueden cambiar. Los scripts de adquisición se conservan como referencia; ejecutarlos otra vez puede descargar otra revisión del producto.

Las **12 pruebas** comprueban cobertura exacta 34+8=42, calendarios de cada dirección, referencias completas, duraciones, intervalos, rechazo de ciclos fuera de 2025, equivalencia vector/escalar, 48 corridas publicadas, límites físicos y separación de media/máxima. El máximo residuo numérico del balance fue **{summary['max_error_balance_mm']:.3g} mm**: prueba contabilidad, no exactitud agronómica.

El [control](control_paquete.json) verifica mallas, conteos, equivalencia de CSV/JSON, referencias diarias, enlaces, cobertura y hashes. El [inventario](inventario.json) identifica los archivos publicados con SHA-256 y SHA de objetos Git; excluye su propia huella. Los originales científicos del [método](resultados/metodo_y_validacion.json), la [configuración](configuracion.json), las [fuentes](fuentes/criterios_7_cultivos.json) y el [resumen general](resultados/resumen_general.json) permiten revisar la entrega.

Antes de recomendar, comprobar material, parcela, fechas reales, almácigo, retiro, residuos, perfil físico, análisis de suelo, drenaje, temperatura y diagnóstico sanitario. Confirmar agua, trabajo/equipo, destino/comprador y costos. Una parcela más fresca o un manejo protegido requiere otra auditoría con sus propias entradas.
'''
    (ROOT/'README.md').write_text(text,encoding='utf-8')


if __name__=='__main__':main()
