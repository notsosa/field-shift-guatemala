import sys
from pathlib import Path
import unittest
from datetime import date
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
from scripts import auditar_maiz_ajonjoli_2025 as a


class AuditChecks(unittest.TestCase):
    def test_stage_lengths_and_fao_discrepancy_are_explicit(self):
        for p in a.PARAM['cultivos'].values():
            for total,stages in p['etapas'].items():self.assertEqual(sum(stages),int(total))
        self.assertEqual(a.PARAM['inconsistencias'][0]['suma_real'],110)
        self.assertEqual(a.PARAM['inconsistencias'][0]['dato_publicado']['total_columna'],100)

    def test_long_calendar_is_not_a_complete_2025_trial(self):
        p=next(p for p in a.programs() if p['id']=='maiz90_ajonjoli150_2025-05-15')
        c=a.calendar(p)
        self.assertFalse(c['ciclo_cabe_en_2025'])
        self.assertEqual(c['fin_ciclo'],'2026-01-16')

    def test_growth_completion_and_dry_margin_are_separate(self):
        p=next(p for p in a.programs() if p['id']=='maiz90_ajonjoli110_2025-06-01')
        c=a.calendar(p)
        self.assertTrue(c['ciclo_cabe_en_2025'])
        self.assertFalse(c['con_margen_secado_cabe_2025'])
        self.assertEqual(c['fin_con_margen_secado_14d'],'2026-01-07')

    def test_gap_has_seven_complete_days(self):
        p=next(p for p in a.programs() if p['id']=='maiz90_ajonjoli110_2025-05-15')
        c=a.calendar(p);one,two=c['segmentos']
        self.assertEqual((date.fromisoformat(two['inicio'])-date.fromisoformat(one['fin'])).days,8)

    def run_physics(self,rain,et0,init):
        p=next(p for p in a.programs() if p['id']=='maiz90_ajonjoli110_2025-05-15')
        a.configure(p)
        rows=[{'P_chirps_mm':rain,'et0_power_fao56_mm':et0} for _ in a.m.DAYS]
        soil=[{'desde_m':0.,'hasta_m':1.,'agua_disponible_mm':100.}]
        return a.m.simulate(rows,soil,'chirps','maiz_ajonjoli',p['crops'],('fixture',p['start'],False),('fixture',1.,1.),0.,init,False,True)

    def test_no_flux_preserves_water_through_change(self):
        result,daily=self.run_physics(0.,0.,.25)
        self.assertEqual(result['deficit_ET_mm'],0.)
        self.assertTrue(all(abs(d['agua_disponible_perfil_final_mm']-25)<1e-9 for d in daily))

    def test_no_water_cannot_meet_demand(self):
        result,daily=self.run_physics(0.,4.,0.)
        self.assertEqual(result['ET_real_cultivo_mm'],0.)
        self.assertEqual(result['deficit_ET_mm'],result['ET_potencial_cultivo_mm'])

    def test_excess_water_is_accounted_for(self):
        result,daily=self.run_physics(10.,0.,.25)
        self.assertAlmostEqual(result['drenaje_profundo_modelo_mm'],3650+25-100)
        self.assertLess(result['max_error_balance_mm'],1e-9)

    def test_bean_comparator_matches_published_run(self):
        site,soil=a.m.static_site();rows,_,_=a.m.weather(site['elevacion_dsm_m'])
        fixture=a.m.load(ROOT/'tests/referencia_frijol_publicada.json')
        p=next(p for p in a.programs() if p['id']=='maiz90_frijol70_2025-06-01')
        for ref in fixture['valores']:
            got,_=a.run_one(p,rows,soil,ref['fuente'],('perfil_referencia',1.,1.),.15,.25,False)
            self.assertAlmostEqual(got['deficit_ET_mm'],ref['deficit_ET_mm'],places=4)
            self.assertEqual(got['dias_Ks_menor_095'],ref['dias_estres'])


if __name__=='__main__':unittest.main()
