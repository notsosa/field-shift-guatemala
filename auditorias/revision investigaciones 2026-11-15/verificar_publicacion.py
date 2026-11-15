"""Comprueba la entrega conservada, sin consultar API ni validar biología."""
from pathlib import Path
from collections import Counter
import hashlib
import json

root = Path(__file__).resolve().parents[2]
folder = root / 'investigacion/plagas-7-cultivos-guatemala/confirmadas'
def read(name):
    return json.loads((folder / name).read_text(encoding='utf-8'))

manifest = read('verificacion.json')
for item in manifest['archivos']:
    assert hashlib.sha256((folder / item['ruta']).read_bytes()).hexdigest() == item['sha256'], item['ruta']
rows = read('plagas_confirmadas.json')['registros']
sources = {s['id'] for s in read('fuentes.json')}
coverage = read('cobertura_por_cultivo.json')['cultivos']
assert len(rows) == len({r['id'] for r in rows}) == manifest['relaciones']
assert dict(Counter(r['resolucion'] for r in rows)) == manifest['por_resolucion']
assert len({c['cultivo_id'] for c in coverage}) == 7
for c in coverage:
    assert c['estado'] == 'hay_antecedentes_documentales' and c['fuentes_referencia']
    assert all(c[k] is None for k in ['ausencia_de_plagas', 'presencia_en_parcela_chiquimula', 'riesgo_fitosanitario_estimado'])
    assert all(ref['id'] in sources for ref in c['fuentes_referencia'])
    assert c['registros_directos_en_esta_tabla'] == sum(r['cultivo_id'] == c['cultivo_id'] for r in rows)
for row in rows:
    assert row['evidencia'] == 'D' and row['tipo_vinculo_documentado']
    assert row['frecuencia_nacional'] is None and row['presencia_en_parcela_chiquimula'] is None
    assert row['referencias'] and all(r['fuente'] in sources and r['localizador'] for r in row['referencias'])
by_id = {r['id']: r for r in rows}
assert by_id['lechuga-02']['tipo_vinculo_documentado'] == 'captura_en_trampas_en_parcela'
assert all(by_id[k]['fecha_evento_reportada'] is None for k in ['maiz-05', 'maiz-06', 'lechuga-01'])
assert manifest['validacion_experimental_agronomica'] is False
print(json.dumps(dict(resultado='integridad_documental_correcta', relaciones=len(rows),
    cobertura_cultivos=len(coverage), limite='No valida biologia, prevalencia ni compatibilidad agronomica.'), ensure_ascii=True))
