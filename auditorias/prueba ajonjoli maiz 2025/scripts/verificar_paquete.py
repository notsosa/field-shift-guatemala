"""Comprueba la integridad de las salidas y ejecuta las pruebas antes de inventariar."""
from pathlib import Path
import collections, csv, gzip, hashlib, json, re, subprocess, sys
from datetime import datetime, timezone
from urllib.parse import unquote

ROOT=Path(__file__).resolve().parent.parent


def load(name):return json.loads((ROOT/name).read_text(encoding='utf-8'))


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    manifest=load('resultados/metodo_y_validacion.json')
    results=json.loads(gzip.decompress((ROOT/'resultados/resultados_escenarios.json.gz').read_bytes()))
    calendars=load('resultados/calendarios_evaluados.json')
    errors=[]
    for item in manifest['archivos_fuente_sha256']:
        if hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest()!=item['sha256']:
            errors.append('Hash distinto: '+item['path'])
    expected={'programas_calendario':192,'programas_completos_2025':42,'programas_fuera_2025':150,
              'escenarios_simulados':6048,'comparaciones_pareadas':3024,'pasos_diarios':2207520}
    for key,value in expected.items():
        if manifest[key]!=value:errors.append('Conteo distinto: '+key)
    if len(calendars)!=192 or len(results)!=6048:errors.append('Conteo de registros')
    counts=collections.Counter();keys=set()
    for row in results:
        key=tuple(row[k] for k in ['programa','fuente_lluvia','suelo_escenario','fraccion_escorrentia_supuesta','fraccion_agua_inicial_enero01','riego_hipotetico'])
        if key in keys:errors.append('Corrida duplicada')
        keys.add(key);counts[row['programa']]+=1
        if any(s['fin']>'2025-12-31' for s in row['segmentos']):errors.append('Ciclo inconcluso simulado')
        if row['max_error_balance_mm']>=1e-7 or row['deficit_ET_mm']<0 or not 0<=row['ETa_sobre_ETc']<=1:errors.append('Balance o límites')
    if len(counts)!=42 or set(counts.values())!={144}:errors.append('Malla incompleta')
    with (ROOT/'resultados/resultados_escenarios.csv').open(encoding='utf-8',newline='') as stream:
        if sum(1 for _ in csv.DictReader(stream))!=6048:errors.append('CSV incompleto')
    with (ROOT/'resultados/comparacion_pareada.csv').open(encoding='utf-8',newline='') as stream:
        if sum(1 for _ in csv.DictReader(stream))!=3024:errors.append('Pares incompletos')
    with gzip.open(ROOT/'resultados/balances_referencia.csv.gz','rt',encoding='utf-8',newline='') as stream:
        daily=list(csv.DictReader(stream))
    if len(daily)!=17520:errors.append('Balances de referencia incompletos')
    if max(abs(float(r['residuo_balance_mm'])) for r in daily)>=1e-7:errors.append('Residuo diario')
    for destination in re.findall(r'\]\(([^)]+)\)',(ROOT/'README.md').read_text(encoding='utf-8')):
        destination=unquote(destination.split('#')[0])
        if destination and not re.match(r'^[a-z]+:',destination,re.I) and destination not in {'inventario.json','control_paquete.json'} and not (ROOT/destination).exists():
            errors.append('Enlace local ausente: '+destination)
    checks=subprocess.run([sys.executable,'-m','unittest','discover','-s',str(ROOT/'tests'),'-v'],capture_output=True,text=True,encoding='utf-8')
    if checks.returncode:errors.append('Pruebas fallaron: '+checks.stderr)
    match=re.search(r'Ran (\d+) tests?',checks.stderr)
    if not match or int(match.group(1))!=10:errors.append('Conteo de pruebas inesperado')
    if errors:raise RuntimeError(json.dumps(errors,ensure_ascii=False))
    control={'fecha_utc':datetime.now(timezone.utc).isoformat(),'alternativa':'ajonjolí→maíz',**expected,
             'max_error_balance_mm':manifest['max_error_balance_mm'],'pruebas':10,'resultado_pruebas':'OK',
             'regresion':'Cuatro lluvias × dos modos de riego de maíz→ajonjolí, intervalo 7 días, commit 244ef10e99d8d8375aeebfcdced94cfae6fdc5f5',
             'fuentes_sha_comprobadas':len(manifest['archivos_fuente_sha256']),'enlaces_locales':'comprobados',
             'csv_json_conteos':'coinciden','balances_referencia_registros':len(daily),'errores':errors}
    (ROOT/'control_paquete.json').write_text(json.dumps(control,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    files=[]
    for path in sorted(ROOT.rglob('*')):
        relative=path.relative_to(ROOT)
        if not path.is_file() or any(p in {'.git','.venv','__pycache__','tmp'} for p in relative.parts) or path.suffix in {'.pyc','.pdf'} or relative.as_posix()=='inventario.json':continue
        data=path.read_bytes()
        files.append({'ruta':relative.as_posix(),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),
                      'git_blob_sha':hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()})
    (ROOT/'inventario.json').write_text(json.dumps({'fecha_utc':control['fecha_utc'],
          'nota':'Excluye el propio inventario, cachés y PDF consultados; enlaces y registros de acceso conservados.',
          'archivos':files},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({**control,'archivos_publicables':len(files)+1,'bytes_sin_inventario':sum(f['bytes'] for f in files)},ensure_ascii=False,indent=2))


if __name__=='__main__':main()
