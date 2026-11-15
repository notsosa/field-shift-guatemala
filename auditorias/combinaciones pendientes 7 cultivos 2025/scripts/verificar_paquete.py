"""Verifica cobertura, mallas, salidas, fuentes y pruebas; crea control e inventario."""
from pathlib import Path
import collections,csv,gzip,hashlib,itertools,json,re,subprocess,sys
from datetime import datetime,timezone
from urllib.parse import unquote
ROOT=Path(__file__).resolve().parent.parent


def load(path):return json.loads(path.read_text(encoding='utf-8'))


def csv_records(path):
    opener=gzip.open if path.suffix=='.gz' else open
    with opener(path,'rt',encoding='utf-8',newline='') as stream:return list(csv.DictReader(stream))


def main():
    sys.stdout.reconfigure(encoding='utf-8');errors=[];config=load(ROOT/'configuracion.json');general=load(ROOT/'resultados/resumen_general.json')
    manifest=load(ROOT/'resultados/metodo_y_validacion.json');seen_directions=set();all_cases=0;all_calendars=0;all_eligible=0;daily_count=0
    for item in manifest['archivos_fuente_sha256']:
        if hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest()!=item['sha256']:errors.append('Fuente distinta: '+item['path'])
    for pair in config['parejas_nuevas']:
        folder=ROOT/'parejas'/'_'.join(pair);summary=load(folder/'resumen.json');calendars=load(folder/'calendarios.json')
        eligible={c['programa'] for c in calendars if c['ciclo_cabe_en_2025']}
        rows=json.loads(gzip.decompress((folder/'escenarios.json.gz').read_bytes()))
        counts=collections.Counter();keys=set();directions=set()
        for row in rows:
            key=tuple(row[k] for k in ['programa','fuente_lluvia','suelo_escenario','fraccion_escorrentia_supuesta','fraccion_agua_inicial_enero01','riego_hipotetico'])
            if key in keys:errors.append('Duplicado: '+folder.name)
            keys.add(key);counts[row['programa']]+=1;directions.add(row['secuencia'])
            if row['programa'] not in eligible or any(s['fin']>'2025-12-31' for s in row['segmentos']):errors.append('Fuera de cobertura: '+folder.name)
            if row['max_error_balance_mm']>=1e-7 or row['deficit_ET_mm']<0 or not 0<=row['ETa_sobre_ETc']<=1:errors.append('Límite físico: '+folder.name)
        if set(counts)!=eligible or set(counts.values())!={144}:errors.append('Malla incompleta: '+folder.name)
        if len(rows)!=summary['corridas'] or len(rows)!=len(eligible)*144 or len(calendars)!=summary['programas']:errors.append('Resumen distinto: '+folder.name)
        if directions!={'_'.join(pair),'_'.join(pair[::-1])}:errors.append('Dirección faltante: '+folder.name)
        seen_directions.update(tuple(s.split('_')) for s in directions)
        csv_rows=csv_records(folder/'escenarios.csv.gz')
        if len(csv_rows)!=len(rows):errors.append('CSV/JSON conteo: '+folder.name)
        else:
            for j,row in enumerate(rows):
                if any(float(csv_rows[j][k])!=row[k] for k in ['deficit_ET_mm','ET_real_cultivo_mm','riego_neto_mm']):errors.append('CSV/JSON valores: '+folder.name);break
        if len(csv_records(folder/'comparacion_pareada.csv.gz'))!=len(rows)//2:errors.append('Pares incompletos: '+folder.name)
        if len(csv_records(folder/'exposicion_climatica.csv.gz'))!=len(eligible)*4:errors.append('Exposición incompleta: '+folder.name)
        references=load(folder/'referencia.json');daily=csv_records(folder/'balances_referencia.csv.gz')
        if len(references)!=16 or len(daily)!=5840:errors.append('Referencia incompleta: '+folder.name)
        traces=collections.defaultdict(list)
        for row in daily:traces[(row['programa'],row['fuente_lluvia'],row['riego_hipotetico'])].append(row)
        if len(traces)!=16 or any(len(trace)!=365 or len({r['fecha'] for r in trace})!=365 for trace in traces.values()):errors.append('Traza diaria incompleta: '+folder.name)
        if max(abs(float(r['residuo_balance_mm'])) for r in daily)>=1e-7:errors.append('Residuo diario: '+folder.name)
        if len(csv_records(folder/'intervalos_referencia.csv'))!=8:errors.append('Intervalos incompletos: '+folder.name)
        all_cases+=len(rows);all_calendars+=len(calendars);all_eligible+=len(eligible);daily_count+=len(daily)
    old={tuple(s) for pair in config['parejas_anteriores'] for s in [pair,pair[::-1]]}
    universe=set(itertools.permutations(config['cultivos'],2))
    if len(seen_directions)!=34 or seen_directions&old or old|seen_directions!=universe:errors.append('Cobertura no equivale a 34+8=42')
    coverage=load(ROOT/'resultados/cobertura_42_sucesiones.json')
    if len(coverage)!=42 or {(r['antecesor'],r['sucesor']) for r in coverage}!=universe:errors.append('Índice de cobertura incompleto')
    for record in coverage:
        if not (ROOT/record['auditoria']).is_file():errors.append('Auditoría no enlazada: '+record['auditoria'])
    if (all_cases,all_calendars,all_eligible)!=(general['corridas'],general['programas'],general['completos_2025']):errors.append('Conteo general distinto')
    for file in ROOT.rglob('*.md'):
        for target in re.findall(r'\]\(([^)]+)\)',file.read_text(encoding='utf-8')):
            target=unquote(target.split('#')[0])
            if target and not re.match(r'^[a-z]+:',target,re.I) and target not in {'inventario.json','control_paquete.json'} and not (file.parent/target).exists():errors.append('Enlace ausente: '+str(file.relative_to(ROOT))+' -> '+target)
    tests=subprocess.run([sys.executable,'-m','unittest','discover','-s',str(ROOT/'tests'),'-v'],capture_output=True,text=True,encoding='utf-8')
    count=re.search(r'Ran (\d+) tests?',tests.stderr)
    if tests.returncode or not count or int(count.group(1))!=12:errors.append('Pruebas fallidas: '+tests.stderr)
    if errors:raise RuntimeError(json.dumps(errors[:40],ensure_ascii=False))
    control={'fecha_utc':datetime.now(timezone.utc).isoformat(),'sucesiones_nuevas':34,'sucesiones_previas':8,'sucesiones_cubiertas':42,
             'parejas_nuevas':17,'programas':all_calendars,'completos_2025':all_eligible,'corridas':all_cases,'pasos_diarios':all_cases*365,
             'registros_diarios_referencia':daily_count,'max_error_balance_mm':general['max_error_balance_mm'],
             'pruebas':12,'resultado_pruebas':'OK','equivalencia':'144 variantes de un calendario contra motor escalar; todos los cultivos; 48 resultados publicados.',
             'fuentes_sha_comprobadas':len(manifest['archivos_fuente_sha256']),'csv_json':'conteos y valores numéricos comprobados en todas las corridas',
             'cobertura_y_enlaces':'42 direcciones enlazadas; 34 nuevas sin duplicados ni faltantes','errores':[]}
    (ROOT/'control_paquete.json').write_text(json.dumps(control,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    files=[]
    for file in sorted(ROOT.rglob('*')):
        rel=file.relative_to(ROOT)
        if not file.is_file() or any(p in {'.git','.venv','__pycache__','tmp'} for p in rel.parts) or file.suffix in {'.pyc','.pdf'} or rel.as_posix()=='inventario.json':continue
        data=file.read_bytes();files.append({'ruta':rel.as_posix(),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),
                                            'git_blob_sha':hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()})
    (ROOT/'inventario.json').write_text(json.dumps({'fecha_utc':control['fecha_utc'],'nota':'Excluye el propio inventario, cachés y PDF no republicados.','archivos':files},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({**control,'archivos_publicables':len(files)+1,'bytes':sum(f['bytes'] for f in files)},ensure_ascii=False,indent=2))


if __name__=='__main__':main()
