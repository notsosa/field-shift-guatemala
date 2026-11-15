import sys,unittest,itertools
from pathlib import Path
from datetime import date,timedelta
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
from scripts import auditar_7_cultivos_2025 as a
import numpy as np


class AuditChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.site,cls.soil=a.m.static_site();cls.rows,_,_=a.m.weather(cls.site['elevacion_dsm_m'])

    def ref_program(self,pair=None):return next(p for p in a.programs(pair or ['maiz','cebolla']) if a.is_reference(p))

    def compare(self,got,expected):
        for key in ['P_mm','riego_neto_mm','escorrentia_supuesta_mm','drenaje_profundo_modelo_mm','ET_potencial_cultivo_mm','ET_real_cultivo_mm','deficit_ET_mm']:
            self.assertAlmostEqual(got[key],expected[key],places=4,msg=key)
        self.assertEqual(got['dias_Ks_menor_095'],expected['dias_Ks_menor_095'])
        self.assertEqual(got['dias_con_cultivo'],expected['dias_con_cultivo'])
        for x,y in zip(got['segmentos'],expected['segmentos']):
            self.assertEqual((x['cultivo'],x['inicio'],x['fin']),(y['cultivo'],y['inicio'],y['fin']))
            for key in ['ETc_mm','ETa_mm','deficit_mm','riego_mm','lluvia_mm']:self.assertAlmostEqual(x[key],y[key],places=6)

    def test_exactly_34_new_and_42_total_directed_successions(self):
        old={tuple(p) for pair in a.CONFIG['parejas_anteriores'] for p in [pair,pair[::-1]]}
        new={tuple(p) for pair in a.CONFIG['parejas_nuevas'] for p in [pair,pair[::-1]]}
        self.assertEqual(len(old),8);self.assertEqual(len(new),34);self.assertFalse(old & new)
        self.assertEqual(old|new,set(itertools.permutations(a.CONFIG['cultivos'],2)))

    def test_every_new_direction_has_complete_program_and_reference(self):
        for pair in a.CONFIG['parejas_nuevas']:
            eligible=[p for p in a.programs(pair) if a.calendar(p)['ciclo_cabe_en_2025']]
            self.assertEqual({p['seq'] for p in eligible},{'_'.join(pair),'_'.join(pair[::-1])})
            self.assertEqual(sum(a.is_reference(p) for p in eligible),2)

    def test_parameter_stage_lengths(self):
        for p in a.PARAM.values():
            self.assertTrue(0<p['p']<1)
            for days,stages in p['etapas'].items():self.assertEqual(sum(stages),int(days))
        self.assertEqual(a.PARAM['ajonjoli']['etapas']['110'],[20,30,40,20])
        self.assertIn('75',a.PARAM['brocoli']['etapas']);self.assertNotIn('120',a.PARAM['brocoli']['etapas'])

    def test_gap_complete_and_paired_end_dates(self):
        for pair in a.CONFIG['parejas_nuevas']:
            p=self.ref_program(pair);a.configure(p);s=a.m.schedule(p['crops'],p['start'],False)
            self.assertEqual((s[1]['start']-s[0]['end']).days,15)
            q=next(q for q in a.programs(pair) if a.is_reference(q) and q['seq']!=p['seq'])
            self.assertEqual(a.calendar(p)['fin_ciclo'],a.calendar(q)['fin_ciclo'])

    def test_incomplete_program_rejected(self):
        p=next(p for p in a.programs(['ajonjoli','cebolla']) if not a.calendar(p)['ciclo_cabe_en_2025']);a.configure(p)
        with self.assertRaises(AssertionError):a.m.schedule(p['crops'],p['start'],False)

    def test_vector_matches_scalar_all_144_scenarios(self):
        p=self.ref_program();batch,_=a.run_program(p,self.rows,self.soil)
        self.assertEqual(len(batch),144)
        for c,got in zip(a.CASES,batch):
            a.configure(p)
            expected,_=a.m.simulate(self.rows,self.soil,c[0],p['seq'],p['crops'],(p['id'],p['start'],False),c[1],c[2],c[3],c[4])
            self.compare(got,expected)

    def test_vector_matches_scalar_all_seven_crops(self):
        covered=set()
        for pair in [['frijol','ajonjoli'],['papa','brocoli'],['cebolla','lechuga']]:
            p=self.ref_program(pair);covered.update(pair)
            cases=[('chirps',('fixture',.3,.75),.3,.75,water) for water in [False,True]]
            got,_=a.run_program(p,self.rows,self.soil,cases)
            for case,record in zip(cases,got):
                a.configure(p);expected,_=a.m.simulate(self.rows,self.soil,case[0],p['seq'],p['crops'],(p['id'],p['start'],False),case[1],case[2],case[3],case[4]);self.compare(record,expected)
        self.assertEqual(covered|{'maiz'},set(a.CONFIG['cultivos']))

    def test_reproduces_48_published_cases(self):
        fixture=a.m.load(ROOT/'tests/referencias_publicadas.json')
        count=0
        for f in fixture['casos']:
            p={'id':'published','seq':'_'.join(f['cultivos']),'start':date.fromisoformat(f['inicio']),'crops':f['cultivos'],'durations':f['duraciones'],'gap':f['intervalo']}
            cases=[(r['fuente_lluvia'],('perfil_referencia',1.,1.),.15,.25,r['riego_hipotetico']) for r in f['resultados']]
            got,_=a.run_program(p,self.rows,self.soil,cases)
            for record,expected in zip(got,f['resultados']):self.compare(record,expected);count+=1
        self.assertEqual(count,48)

    def physics(self,rain,et0,initial):
        p=self.ref_program();rows=[{**{f'P_{s}_mm':rain for s in a.m.LABELS},'et0_power_fao56_mm':et0} for _ in a.m.DAYS]
        soil=[{'desde_m':0.,'hasta_m':1.,'agua_disponible_mm':100.}]
        return a.run_program(p,rows,soil,[('chirps',('fixture',1.,1.),0.,initial,False)],[0])

    def test_no_flux_conserves_reserve_across_both_crops(self):
        r,d=self.physics(0.,0.,.25);self.assertEqual(r[0]['deficit_ET_mm'],0.)
        self.assertTrue(all(abs(x['agua_disponible_perfil_final_mm']-25)<1e-9 for x in d))

    def test_no_water_means_zero_et(self):
        r,_=self.physics(0.,4.,0.);self.assertEqual(r[0]['ET_real_cultivo_mm'],0.)
        self.assertEqual(r[0]['ET_potencial_cultivo_mm'],r[0]['deficit_ET_mm'])

    def test_excess_water_balance(self):
        r,_=self.physics(10.,0.,.25);self.assertAlmostEqual(r[0]['drenaje_profundo_modelo_mm'],3650+25-100)
        self.assertLess(r[0]['max_error_balance_mm'],1e-9)

    def test_solar_daylength_and_temperature_definitions(self):
        self.assertAlmostEqual(a.daylength(date(2025,1,1),0),12.)
        self.assertGreater(a.daylength(date(2025,6,21)),a.daylength(date(2025,12,21)))
        p=self.ref_program();rows=[{'fecha':d.isoformat(),'T2M':22.,'T2M_MAX':31.,'tmax_era5_C':29.,'tmin_era5_C':11.,**{f'P_{s}_mm':0. for s in a.m.LABELS}} for d in a.m.DAYS]
        power,era=a.exposure(p,rows)[:2]
        self.assertEqual(power['dias_Tmedia_mayor_30C'],0);self.assertEqual(power['dias_Tmax_mayor_30C'],power['dias']);self.assertEqual(era['Tmedia_C'],20.)


if __name__=='__main__':unittest.main()
