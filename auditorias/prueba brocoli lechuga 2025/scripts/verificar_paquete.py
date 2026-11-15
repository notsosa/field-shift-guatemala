"""Verificación reproducible de integridad, malla y regresión; inventario de publicación."""
from pathlib import Path
import collections,csv,gzip,hashlib,json,re,subprocess,sys
from datetime import datetime,timezone
from urllib.parse import unquote
ROOT=Path(__file__).resolve().parent.parent


def load(name):return json.loads((ROOT/name).read_text(encoding='utf-8'))


def main():
    sys.stdout.reconfigure(encoding='utf-8');errors=[]
    manifest=load('resultados/metodo_y_validacion.json');summary=manifest['resultados_resumen']
    calendars=load('resultados/calendarios_evaluados.json')
    rows=json.loads(gzip.decompress((ROOT/'resultados/resultados_escenarios.json.gz').read_bytes()))
    for f in manifest['archivos_fuente_sha256']:
        if hashlib.sha256((ROOT/f['path']).read_bytes()).hexdigest()!=f['sha256']:errors.append('Hash distinto: '+f['path'])
    eligible={c['programa'] for c in calendars if c['ciclo_cabe_en_2025']}
    if len(rows)!=len(eligible)*144 or len(rows)!=summary['corridas']:errors.append('Conteo de malla')
    if len(calendars)!=summary['programas'] or len(eligible)!=summary['completos_2025']:errors.append('Conteo de calendarios')
    keys=set();counts=collections.Counter()
    for r in rows:
        key=tuple(r[k] for k in ['programa','fuente_lluvia','suelo_escenario','fraccion_escorrentia_supuesta','fraccion_agua_inicial_enero01','riego_hipotetico'])
        if key in keys:errors.append('Duplicado')
        keys.add(key);counts[r['programa']]+=1
        if r['programa'] not in eligible or any(s['fin']>'2025-12-31' for s in r['segmentos']):errors.append('Ciclo incompleto simulado')
        if r['max_error_balance_mm']>=1e-7 or r['deficit_ET_mm']<0 or not 0<=r['ETa_sobre_ETc']<=1:errors.append('Límite físico')
    if set(counts)!=eligible or set(counts.values())!={144}:errors.append('Programas incompletos')
    for name,expected in [('resultados_escenarios.csv.gz',len(rows)),('comparacion_pareada.csv.gz',len(rows)//2),('balances_referencia.csv.gz',48*365)]:
        with gzip.open(ROOT/'resultados'/name,'rt',encoding='utf-8',newline='') as stream:
            records=list(csv.DictReader(stream))
        if len(records)!=expected:errors.append('Conteo distinto: '+name)
        if name.startswith('balances') and max(abs(float(r['residuo_balance_mm'])) for r in records)>=1e-7:errors.append('Residuo diario')
    with (ROOT/'resultados/exposicion_climatica.csv').open(encoding='utf-8',newline='') as stream:exposures=list(csv.DictReader(stream))
    if len(exposures)!=len(eligible)*4:errors.append('Exposición climática incompleta')
    for target in re.findall(r'\]\(([^)]+)\)',(ROOT/'README.md').read_text(encoding='utf-8')):
        target=unquote(target.split('#')[0])
        if target and not re.match(r'^[a-z]+:',target,re.I) and target not in {'inventario.json','control_paquete.json'} and not (ROOT/target).exists():errors.append('Enlace ausente: '+target)
    check=subprocess.run([sys.executable,'-m','unittest','discover','-s',str(ROOT/'tests'),'-v'],capture_output=True,text=True,encoding='utf-8')
    match=re.search(r'Ran (\d+) tests?',check.stderr)
    if check.returncode or not match or int(match.group(1))!=10:errors.append('Pruebas: '+check.stderr)
    if errors:raise RuntimeError(json.dumps(errors,ensure_ascii=False))
    control={'fecha_utc':datetime.now(timezone.utc).isoformat(),'alternativa':summary['alternativa'],
             **{k:summary[k] for k in ['programas','completos_2025','inconclusos_sin_simular','corridas','pares','pasos_diarios','max_error_balance_mm']},
             'pruebas':10,'resultado_pruebas':'OK','fuentes_sha_comprobadas':len(manifest['archivos_fuente_sha256']),
             'balances_referencia':48*365,'regresion':'4 lluvias y 2 modos de riego del comparador publicado; coincide a 4 decimales.',
             'malla_csv_json_y_enlaces':'comprobados','errores':[]}
    (ROOT/'control_paquete.json').write_text(json.dumps(control,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    files=[]
    for path in sorted(ROOT.rglob('*')):
        rel=path.relative_to(ROOT)
        if not path.is_file() or any(p in {'.git','.venv','__pycache__','tmp'} for p in rel.parts) or path.suffix in {'.pyc','.pdf'} or rel.as_posix()=='inventario.json':continue
        data=path.read_bytes();files.append({'ruta':rel.as_posix(),'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),
                                            'git_blob_sha':hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()})
    (ROOT/'inventario.json').write_text(json.dumps({'fecha_utc':control['fecha_utc'],'nota':'Excluye el propio inventario, cachés y PDF consultados; se conservan sus fuentes y huellas de acceso.','archivos':files},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({**control,'archivos_publicables':len(files)+1,'bytes':sum(f['bytes'] for f in files)},ensure_ascii=False,indent=2))


if __name__=='__main__':main()
