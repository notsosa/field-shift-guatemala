import sys,unittest
from pathlib import Path
from datetime import date
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
from scripts import auditar_hortalizas_2025 as a


class AuditChecks(unittest.TestCase):
    def program(self,gap=14,reverse=False):
        return next(p for p in a.programs() if a.is_reference(p) and p['gap']==gap and (p['seq']==a.REVERSE)==reverse)

    def test_parameters_fit_documented_ranges_and_stage_lengths(self):
        for p in a.PARAM['cultivos'].values():
            self.assertTrue(p['rango_zr_fao'][0]<=p['zr']<=p['rango_zr_fao'][1])
            self.assertTrue(0<p['p']<1)
            for days,stages in p['etapas'].items():self.assertEqual(int(days),sum(stages))

    def test_model_calendar_matches_report_and_has_complete_gap(self):
        for gap in a.CONFIG['intervalos_dias']:
            p=self.program(gap);c=a.calendar(p);a.configure(p);s=a.m.schedule(p['crops'],p['start'],False)
            self.assertEqual((s[1]['start']-s[0]['end']).days,gap+1)
            self.assertEqual(s[1]['end'].isoformat(),c['fin_ciclo'])

    def test_opposite_orders_have_equal_end_dates(self):
        for gap in a.CONFIG['intervalos_dias']:
            one=a.calendar(self.program(gap));two=a.calendar(self.program(gap,True))
            self.assertEqual(one['fin_ciclo'],two['fin_ciclo'])

    def test_no_incomplete_program_can_enter_engine(self):
        p=next(p for p in a.programs() if not a.calendar(p)['ciclo_cabe_en_2025']);a.configure(p)
        with self.assertRaises(AssertionError):a.m.schedule(p['crops'],p['start'],False)

    def physics(self,rain,et0,initial):
        p=self.program();a.configure(p)
        rows=[{'P_chirps_mm':rain,'et0_power_fao56_mm':et0} for _ in a.m.DAYS]
        soil=[{'desde_m':0.,'hasta_m':1.,'agua_disponible_mm':100.}]
        return a.m.simulate(rows,soil,'chirps',p['seq'],p['crops'],('fixture',p['start'],False),('fixture',1.,1.),0.,initial,False,True)

    def test_no_flux_preserves_water_across_crop_change(self):
        r,d=self.physics(0.,0.,.25)
        self.assertEqual(r['deficit_ET_mm'],0.)
        self.assertTrue(all(abs(v['agua_disponible_perfil_final_mm']-25)<1e-9 for v in d))

    def test_no_water_means_zero_actual_et(self):
        r,_=self.physics(0.,4.,0.)
        self.assertEqual(r['ET_real_cultivo_mm'],0.)
        self.assertEqual(r['deficit_ET_mm'],r['ET_potencial_cultivo_mm'])

    def test_excess_rain_is_accounted_in_drainage(self):
        r,_=self.physics(10.,0.,.25)
        self.assertAlmostEqual(r['drenaje_profundo_modelo_mm'],3650+25-100)
        self.assertLess(r['max_error_balance_mm'],1e-9)

    def test_astronomical_daylength_equator_and_seasons(self):
        self.assertAlmostEqual(a.daylength(date(2025,1,15),0),12.)
        self.assertGreater(a.daylength(date(2025,6,21)),a.daylength(date(2025,12,21)))
        self.assertTrue(11<a.daylength(date(2025,12,21))<12)

    def test_daily_mean_and_maximum_are_not_confused(self):
        rows=[{'fecha':d.isoformat(),'T2M':22.,'T2M_MAX':31.,'tmax_era5_C':29.,'tmin_era5_C':11.,**{f'P_{s}_mm':0 for s in a.m.LABELS}} for d in a.m.DAYS]
        got=a.exposure(self.program(),rows)
        power,era=got[:2]
        self.assertEqual(power['dias_Tmedia_mayor_30C'],0)
        self.assertEqual(power['dias_Tmax_mayor_30C'],power['dias'])
        self.assertEqual(era['Tmedia_C'],20.)
        self.assertEqual(era['dias_Tmedia_mayor_20C'],0)

    def test_legacy_published_balance_four_rains_two_modes(self):
        site,soil=a.m.static_site();rows,_,_=a.m.weather(site['elevacion_dsm_m'])
        fixture=a.m.load(ROOT/'tests/referencia_publicada.json')
        for ref in fixture['valores']:
            a.m.INTERVAL_DAYS=7
            a.m.CROPS={c:{'stages':fixture['parametros'][c]['etapas'][str(days)],**{k:fixture['parametros'][c][k] for k in ['kc','zr','p']}} for c,days in [('maiz',90),('ajonjoli',110)]}
            r,_=a.m.simulate(rows,soil,ref['fuente_lluvia'],'maiz_ajonjoli',['maiz','ajonjoli'],('fixture',date(2025,5,15),False),('perfil_referencia',1.,1.),.15,.25,ref['riego_hipotetico'])
            for key in ['deficit_ET_mm','ET_real_cultivo_mm','riego_neto_mm','drenaje_profundo_modelo_mm']:self.assertAlmostEqual(r[key],ref[key],places=4)
            self.assertEqual(r['dias_Ks_menor_095'],ref['dias_Ks_menor_095'])


if __name__=='__main__':unittest.main()
