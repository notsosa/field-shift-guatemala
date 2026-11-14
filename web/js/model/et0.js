// FAO-56 Penman-Monteith reference evapotranspiration (daily step). Units: mm, degC, MJ/m2/day, m/s, kPa.
const GSC = 0.0820; // MJ m-2 min-1
const SIGMA = 4.903e-9; // MJ K-4 m-2 day-1

/** Eq. 11: saturation vapour pressure (kPa) at temperature tC. */
export function satVaporPressure(tC) {
  return 0.6108 * Math.exp((17.27 * tC) / (tC + 237.3));
}

/** Eq. 13: slope of the saturation vapour pressure curve (kPa/degC). */
export function slopeVaporPressure(tC) {
  return (4098 * satVaporPressure(tC)) / Math.pow(tC + 237.3, 2);
}

/** Eq. 7: atmospheric pressure (kPa) from elevation (m). */
export function pressureFromElevation(z) {
  return 101.3 * Math.pow((293 - 0.0065 * z) / 293, 5.26);
}

/** Eq. 21: extraterrestrial radiation Ra (MJ/m2/day). */
export function extraterrestrialRadiation(latDeg, doy) {
  const phi = (latDeg * Math.PI) / 180;
  const dr = 1 + 0.033 * Math.cos(((2 * Math.PI) / 365) * doy);
  const delta = 0.409 * Math.sin(((2 * Math.PI) / 365) * doy - 1.39);
  const ws = Math.acos(Math.max(-1, Math.min(1, -Math.tan(phi) * Math.tan(delta))));
  const ra = ((24 * 60) / Math.PI) * GSC * dr *
    (ws * Math.sin(phi) * Math.sin(delta) + Math.cos(phi) * Math.cos(delta) * Math.sin(ws));
  return Math.max(0, ra);
}

/** Eq. 37: clear-sky radiation Rso. */
export function clearSkyRadiation(ra, elevation = 0) {
  return (0.75 + 2e-5 * elevation) * ra;
}

/** Eq. 39: net longwave radiation Rnl (MJ/m2/day). rso is passed explicitly. */
export function netLongwave({ tmax, tmin, ea, rs, rso }) {
  const tk = (Math.pow(tmax + 273.16, 4) + Math.pow(tmin + 273.16, 4)) / 2;
  const ratio = rso > 0 ? Math.min(rs / rso, 1) : 0.5;
  return SIGMA * tk * (0.34 - 0.14 * Math.sqrt(Math.max(ea, 0))) * (1.35 * ratio - 0.35);
}

/**
 * Eq. 6: daily ET0 (mm/day). Actual vapour pressure from `ea`, else `tdew`, else `rhMean`.
 * `pressure` in kPa; when absent it is derived from `elevation` (eq. 7). G = 0.
 */
export function et0PenmanMonteith({ tmax, tmin, ea, tdew, rhMean, rs, u2, elevation = 0, pressure, latDeg, doy }) {
  const tmean = (tmax + tmin) / 2;
  const es = (satVaporPressure(tmax) + satVaporPressure(tmin)) / 2;
  let eaV = ea;
  if (!Number.isFinite(eaV)) {
    if (Number.isFinite(tdew)) eaV = satVaporPressure(tdew);
    else if (Number.isFinite(rhMean)) eaV = (rhMean / 100) * es;
    else throw new Error('et0PenmanMonteith: need ea, tdew or rhMean');
  }
  const p = Number.isFinite(pressure) ? pressure : pressureFromElevation(elevation);
  const gamma = 0.000665 * p; // eq. 8
  const ra = extraterrestrialRadiation(latDeg, doy);
  const rso = clearSkyRadiation(ra, elevation);
  const rns = (1 - 0.23) * rs; // eq. 38
  const rn = rns - netLongwave({ tmax, tmin, ea: eaV, rs, rso }); // eq. 40
  const delta = slopeVaporPressure(tmean);
  const et0 = (0.408 * delta * rn + gamma * (900 / (tmean + 273)) * u2 * (es - eaV)) /
    (delta + gamma * (1 + 0.34 * u2));
  return Math.max(0, et0);
}
