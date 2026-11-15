"""Pruebas físicas y de límites del balance; no validación de campo."""
import unittest
from datetime import date
from scripts import simular_chiquimula_2025 as m


class BalanceLimits(unittest.TestCase):
    profile = [{'desde_m': 0., 'hasta_m': 1., 'agua_disponible_mm': 100.}]

    def run_case(self, rain, et0, initial, irrigation=False):
        rows = [{'P_chirps_mm': rain, 'et0_power_fao56_mm': et0} for _ in m.DAYS]
        return m.simulate(rows, self.profile, 'chirps', 'maiz_frijol', ['maiz', 'frijol'], ('fixture', date(2025,6,1), True), ('fixture', 1., 1.), 0., initial, irrigation, True)

    def test_no_flux_preserves_storage_across_crop_changes(self):
        result, daily = self.run_case(0., 0., .25)
        self.assertEqual(result['deficit_ET_mm'], 0.)
        for row in daily:
            self.assertAlmostEqual(row['agua_disponible_perfil_final_mm'], 25.)
        self.assertEqual({row['cultivo'] for row in daily}, {'maiz', 'frijol', 'suelo_sin_cultivo'})

    def test_empty_soil_without_inputs_cannot_evaporate_water(self):
        result, daily = self.run_case(0., 4., 0.)
        self.assertEqual(result['ET_real_cultivo_mm'], 0.)
        self.assertAlmostEqual(result['deficit_ET_mm'], result['ET_potencial_cultivo_mm'])
        self.assertTrue(all(row['ETa_mm'] == 0 for row in daily))

    def test_rain_above_capacity_becomes_drainage(self):
        result, daily = self.run_case(10., 0., .25)
        self.assertAlmostEqual(daily[-1]['agua_disponible_perfil_final_mm'], 100.)
        self.assertAlmostEqual(result['drenaje_profundo_modelo_mm'], 3650+25-100)
        self.assertLess(result['max_error_balance_mm'], 1e-9)

    def test_supplemental_water_has_finite_accounted_volume(self):
        dry, _ = self.run_case(0., 4., 0.)
        wet, daily = self.run_case(0., 4., 0., True)
        self.assertLess(wet['deficit_ET_mm'], dry['deficit_ET_mm'])
        self.assertGreater(wet['riego_neto_mm'], 0)
        self.assertAlmostEqual(wet['riego_neto_mm'], sum(row['riego_neto_mm'] for row in daily))
        self.assertTrue(all(0 <= row['Ks'] <= 1 and 0 <= row['ETa_mm'] <= row['ETc_mm']+1e-9 for row in daily))


if __name__ == '__main__':
    unittest.main()
