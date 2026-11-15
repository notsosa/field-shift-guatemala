import sys, unittest
from pathlib import Path
from datetime import date
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
from scripts import auditar_ajonjoli_maiz_2025 as a


class AuditChecks(unittest.TestCase):
    def program(self,seq='ajonjoli_maiz',sesame=110,corn=90,gap=14,start=date(2025,5,15)):
        return next(p for p in a.programs() if p['seq']==seq and p['start']==start and p['durations']=={'ajonjoli':sesame,'maiz':corn} and p['gap']==gap)

    def test_source_duration_discrepancy_stays_explicit(self):
        for crop in a.PARAM['cultivos'].values():
            for total,stages in crop['etapas'].items():self.assertEqual(sum(stages),int(total))
        self.assertEqual(a.PARAM['inconsistencias'][0]['suma_real'],110)
        self.assertEqual(a.PARAM['inconsistencias'][0]['dato_publicado']['total_columna'],100)

    def test_complete_gap_and_no_double_drying(self):
        p=self.program();cal=a.calendar(p);sesame,corn=cal['segmentos']
        self.assertEqual(sesame['fin'],'2025-09-01')
        self.assertEqual(corn['inicio'],'2025-09-16')
        self.assertEqual(corn['fin'],'2025-12-14')
        self.assertEqual((date.fromisoformat(corn['inicio'])-date.fromisoformat(sesame['fin'])).days,15)
        a.configure(p);sched=a.m.schedule(p['crops'],p['start'],False)
        self.assertEqual(sched[1]['start'].isoformat(),corn['inicio'])

    def test_each_gap_changes_maize_start_by_seven_days(self):
        starts=[date.fromisoformat(a.calendar(self.program(gap=g))['segmentos'][1]['inicio']) for g in [7,14,21]]
        self.assertEqual((starts[1]-starts[0]).days,7)
        self.assertEqual((starts[2]-starts[1]).days,7)

    def test_paired_programs_have_same_end_and_active_duration(self):
        for p in a.programs():
            q=self.program('maiz_ajonjoli' if p['seq']=='ajonjoli_maiz' else 'ajonjoli_maiz',p['durations']['ajonjoli'],p['durations']['maiz'],p['gap'],p['start'])
            self.assertEqual(a.calendar(p)['fin_ciclo'],a.calendar(q)['fin_ciclo'])

    def test_long_cycle_is_calendar_only_and_engine_rejects_it(self):
        p=self.program(sesame=180)
        self.assertFalse(a.calendar(p)['ciclo_cabe_en_2025'])
        a.configure(p)
        with self.assertRaises(AssertionError):a.m.schedule(p['crops'],p['start'],False)

    def physics(self,rain,et0,initial):
        p=self.program();a.configure(p)
        rows=[{'P_chirps_mm':rain,'et0_power_fao56_mm':et0} for _ in a.m.DAYS]
        soil=[{'desde_m':0.,'hasta_m':1.,'agua_disponible_mm':100.}]
        return a.m.simulate(rows,soil,'chirps',p['seq'],p['crops'],('fixture',p['start'],False),('fixture',1.,1.),0.,initial,False,True)

    def test_no_flux_keeps_reserve_across_harvest_gap_and_new_crop(self):
        result,daily=self.physics(0.,0.,.25)
        self.assertEqual(result['deficit_ET_mm'],0.)
        self.assertTrue(all(abs(d['agua_disponible_perfil_final_mm']-25)<1e-9 for d in daily))

    def test_no_water_cannot_supply_et(self):
        result,_=self.physics(0.,4.,0.)
        self.assertEqual(result['ET_real_cultivo_mm'],0.)
        self.assertEqual(result['deficit_ET_mm'],result['ET_potencial_cultivo_mm'])

    def test_excess_water_has_no_unaccounted_sink(self):
        result,_=self.physics(10.,0.,.25)
        self.assertAlmostEqual(result['drenaje_profundo_modelo_mm'],3650+25-100)
        self.assertLess(result['max_error_balance_mm'],1e-9)

    def test_paired_comparison_uses_identical_conditions(self):
        rows=[dict(inicio='2025-05-15',ajonjoli_dias=110,maiz_dias=90,intervalo_dias=14,fuente_lluvia='chirps',suelo_escenario='x',fraccion_escorrentia_supuesta=.15,fraccion_agua_inicial_enero01=.25,riego_hipotetico=False,secuencia=s,programa=s,deficit_ET_mm=v,maiz_deficit_mm=v,riego_neto_mm=0) for s,v in [('ajonjoli_maiz',10),('maiz_ajonjoli',3)]]
        self.assertEqual(a.pairs(rows)[0]['diferencia_deficit_inverso_menos_directo_mm'],7)

    def test_direct_order_matches_published_four_rains_and_irrigation_modes(self):
        site,soil=a.m.static_site();rows,_,_=a.m.weather(site['elevacion_dsm_m'])
        fixture=a.m.load(ROOT/'tests/referencia_directa_publicada.json')
        p=self.program('maiz_ajonjoli',gap=7)
        for ref in fixture['valores']:
            got,_=a.run_one(p,rows,soil,ref['fuente_lluvia'],('perfil_referencia',1.,1.),.15,.25,ref['riego_hipotetico'])
            for key in ['deficit_ET_mm','ET_real_cultivo_mm','riego_neto_mm','drenaje_profundo_modelo_mm']:
                self.assertAlmostEqual(got[key],ref[key],places=4)
            self.assertEqual(got['dias_Ks_menor_095'],ref['dias_Ks_menor_095'])


if __name__=='__main__':unittest.main()
