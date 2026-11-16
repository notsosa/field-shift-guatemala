// Entradas de las 3 pruebas fijas del port de la app (Tarea 34, parte B). Clima sintético determinista (no es dato real: sirve solo para comparar
// el código Dart con el port JS), con días de lluvia, días con la humedad ausente, días ausentes del todo, huecos al final y al inicio, y un cruce de año.
// Uso: node scripts/app/fixture/make_input.mjs <salida.json>   y luego, con los archivos de la app copiados (ver fixture.dart): dart fixture.dart entrada.json salida.json
import { writeFileSync } from 'node:fs';
import { isoToDay, dayToIso } from '../../../web/js/model/appEngine.js';

function lcg(seed) { let s = seed >>> 0; return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; }; }
const r1 = (x) => Math.round(x * 100) / 100;

function weather({ from, to, seed, wetStart, drop, noHumidity }) {
  const rnd = lcg(seed); const out = [];
  for (let d = isoToDay(from); d <= isoToDay(to); d++) {
    const iso = dayToIso(d); const doy = d - isoToDay(`${iso.slice(0, 4)}-01-01`);
    const season = Math.sin((2 * Math.PI * (doy - 100)) / 365);
    if (drop.includes(iso)) continue;
    const wet = doy > wetStart && doy < wetStart + 170;
    const rain = wet && rnd() < 0.45 ? r1(-Math.log(1 - rnd()) * 11) : (rnd() < 0.03 ? r1(rnd() * 4) : 0);
    out.push({ f: iso, x: r1(30 + 3 * season + 2 * rnd()), n: r1(19 + 2 * season + 1.5 * rnd()), h: noHumidity.includes(iso) ? null : r1(55 + 20 * (wet ? 1 : 0) + 10 * rnd()),
      v: r1(1.2 + 1.8 * rnd()), r: r1(16 + 6 * (wet ? -0.5 : 1) + 3 * rnd()), l: rain });
  }
  return out;
}

const cases = [
  { id: 'maiz120_franco_cruce_lluvias', cultivo: 'maiz', ciclo: 120, aguaDisponible: 150, siembra: '2023-06-05', hoy: '2023-08-20', latitud: 14.825, elevacion: 407, riegos: {},
    clima: weather({ from: '2023-04-06', to: '2023-08-20', seed: 11, wetStart: 130, drop: ['2023-05-10', '2023-07-02', '2023-07-03', '2023-07-04'], noHumidity: ['2023-06-20', '2023-08-01'] }) },
  { id: 'frijol80_arenoso_pasa_cosecha_riegos', cultivo: 'frijol', ciclo: 80, aguaDisponible: 100, siembra: '2022-07-01', hoy: '2022-10-15', latitud: 14.29, elevacion: 903,
    riegos: { '2022-07-20': 12, '2022-07-27': 12, '2022-08-03': 6, '2022-09-10': 30 },
    clima: weather({ from: '2022-05-02', to: '2022-10-10', seed: 23, wetStart: 125, drop: ['2022-07-05', '2022-08-15', '2022-08-16'], noHumidity: ['2022-09-01'] }) },
  { id: 'tomate145_arcilloso_cruce_de_anio_inicio_tardio', cultivo: 'tomate', ciclo: 145, aguaDisponible: 180, siembra: '2021-09-01', hoy: '2022-01-20', latitud: 14.78, elevacion: 1787, riegos: {},
    clima: weather({ from: '2021-09-03', to: '2022-01-20', seed: 37, wetStart: 120, drop: ['2021-10-12', '2021-12-31', '2022-01-01'], noHumidity: ['2021-09-03', '2021-11-11'] }) },
];
writeFileSync(process.argv[2], JSON.stringify({ cases }));
console.log(`escrito ${process.argv[2]} (${cases.map((c) => `${c.id}: ${c.clima.length} dias`).join('; ')})`);
