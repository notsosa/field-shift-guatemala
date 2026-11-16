# Field Shift — submission text (English)

NASA Space Apps Challenge 2026 · Challenge: Field Shift: Adapting Farms with NASA Data · Team Feliz_cumpleaños · Guatemala

Copy each block into the matching field of the project page. Replace the two `[link]` marks before submitting.

## Project name

Field Shift

## High-level summary (short)

Field Shift is an offline Android app for farmers in Guatemala. The farmer draws the farm and its plantations on a map, and the app uses NASA POWER daily weather with a FAO-56 water balance to show how much water each plantation has left and how much to irrigate. Small neural networks that run on the phone add what the balance cannot show: whether the crop will run short of water next week, whether to irrigate a coffee plot now, and which crop to resow after a loss. The app works without signal and downloads weather only on wifi. It gives evidence and states its limits. The farmer makes the decision.

## Demo

30-second video: [link]

## Final project

Repository: https://github.com/notsosa/field-shift-guatemala
Model, results and the app copy with the networks: branch `modelo-keu` (`proyecto/resultados-modelo-keu.md`, `app/V01-red/`)

## Detailed description

### The problem

In Guatemala's Dry Corridor the mid-summer dry spell can last for weeks. In 2018 it ran from late June to mid-August, and FEWS NET reported that about 200,000 subsistence farmers lost almost all of their crop. A farmer facing that has a few choices for each plantation: irrigate if there is water, wait, or resow something that still fits in the season. Most have no agronomist to ask and no signal in the field.

### What it does

- The farmer places the farm on a map (GPS, coordinates, or by dragging a satellite view) and draws each plantation. Every plantation has its own crop, sowing date, soil, irrigation type and weekly record of irrigation, pests and fertilizer.
- With weather from NASA POWER, the app runs a daily root-zone water balance (FAO-56) for each plantation. It shows the water left, the stress days, a suggested irrigation depth in the farmer's own units, and a water-limited yield factor (FAO-33).
- A neural network estimates water stress for the next 7 and 14 days. It has 5,283 parameters and runs in pure Dart, with no native module and no cloud.
- For coffee, the app recommends whether to irrigate now, and shows notices for leaf rust, leaf miner, anthracnose and fertilizing. Each notice shows its source and how much to trust it. Shade trees and banana are inputs.
- After a lost maize crop, a network compares eight options (resow maize, beans, sesame, potato, onion, broccoli or lettuce, or leave the field) and ranks them by expected water-limited yield. A companion web tool compares crop rotations over 24 years of weather.
- A second network, a farm-management policy, scores 25 actions per plantation each day (19 sowing profiles for 18 crops, plus wait, continue, cover crop, irrigate, fertilize and pest control). It is trained by neuroevolution on full simulated seasons.
- The app is in Spanish and English. The team also trained an experimental translator between Spanish and K'iche', Kaqchikel, Q'eqchi' and Mam. It makes frequent errors and needs review by native speakers before use.

### How it works

Weather comes from NASA POWER (temperature, humidity, wind, solar radiation, precipitation). Reference evapotranspiration uses Penman-Monteith. The simulator behind the networks adds crop stages by thermal time, two soil water stores, SCS curve-number runoff, soil properties from ISRIC SoilGrids and temperature corrected to the plot's elevation. The networks are small dense networks trained on that simulator with NASA weather from 2001 to 2024. Years 2019 to 2024 and separate sites were held out for testing, with three random seeds reported every time.

### What we measured

- Next-week water stress (rainfed maize, beans, tomato; 201,600 held-out cases): F1 0.86 to 0.87, against 0.69 when using only the app's reading for today. Mean error 0.18 to 0.21 days against 0.27.
- Resowing after a lost maize crop (54 held-out cases, simulated): the network's choice reaches 0.94 to 0.97 relative yield against 0.80 for a simple agronomic rule. The best choice in hindsight is 0.97.
- Coffee irrigation (1,620 held-out cases, simulated): the network beats the FAO-56 rule under both farmer priorities (0.52 against 0.04 when saving water, 1.22 against 0.82 when protecting the crop, in stress days avoided net of the cost of irrigating).
- The farm-management policy took no infeasible actions in held-out seasons from 2022 to 2025. It did not show an improvement over the baseline rule on the full test set.

### What we checked, and where it falls short

We wanted to know how close the simulator is to real life, so we tested it against things we did not build.

- Against FAO AquaCrop, year rankings for maize agree in the lowlands (Spearman 0.89 at Chiquimula) and do not agree in the highlands (−0.09 at San Martín Jilotepeque). The simulator is not valid above about 1,500 m.
- Against ten documented drought years from FEWS NET, MAGA, SESAN and FAO reports, the simulator placed the bad year in the worst third of its site 44% of the time (144 of 331 site-years). Chance would be 33%. It does not reproduce the documented second-season loss of 2009.
- One piece of advice that looked good in our simulator, delaying sowing, was contradicted by AquaCrop. We removed it.
- The simulator sees water only. Pests, fertilizer response, costs and seed availability enter as notices or as conditions the farmer states, because we found no published damage or cost numbers for Guatemala that we could defend. Margin is not computed.
- The banana-shade effect is an assumption, not a measurement.
- Nothing here has been validated on a farm. The networks have been tested in the app's web build and in unit tests, not yet on a phone in the field.

### Benefits

A farmer gets a weekly reading per plantation that works without signal, in their own units (manzanas, number of irrigations). The warning for next week gives time to act. Every recommendation comes with what it is based on and what it cannot see, so local extension staff can review it.

### Tools and languages

Flutter and Dart (app), JavaScript and Node (simulator, evaluation), Python and PyTorch with CUDA (training), AquaCrop-OSPy and DSSAT (external checks), OpenStreetMap and Esri imagery (map background).

## Space agency data

- NASA POWER daily meteorology (core input of the app and of training).
- NASA GPM IMERG through ClimateSERV (rain comparison).
- JAXA GSMaP (monthly rain scaling in the policy network's scenarios) and JAXA AW3D30 (relief).
- ESA WorldCover 2021 (land cover) and Copernicus ERA5 (rain used to train the predictive networks).
- Other open data: CHIRPS, ISRIC SoilGrids, MAGA and ICTA publications.

## Use of artificial intelligence

We used AI tools and declare them here. Claude (Anthropic) and Codex (OpenAI) assisted with code, analysis and documentation; team members reviewed and ran the results. The terrain sequence in the video was generated with Gemini and carries a visible "AI-generated" label. The rest of the video uses real screenshots of the app and music synthesized in code. No NASA logos or branding are used.

## References

- Allen, R. G., Pereira, L. S., Raes, D., Smith, M. (1998). Crop evapotranspiration. FAO Irrigation and Drainage Paper 56.
- Doorenbos, J., Kassam, A. H. (1979). Yield response to water. FAO Irrigation and Drainage Paper 33.
- Steduto, P., Hsiao, T. C., Fereres, E., Raes, D. (2012). Crop yield response to water. FAO Irrigation and Drainage Paper 66. AquaCrop v7.3 reference manual.
- USDA NRCS (1986). Urban Hydrology for Small Watersheds, TR-55.
- NASA POWER Project, NASA Langley Research Center. https://power.larc.nasa.gov
- Huffman, G. J. et al. GPM IMERG. NASA GES DISC. SERVIR ClimateSERV. https://climateserv.servirglobal.net
- Hersbach, H. et al. (2020). The ERA5 global reanalysis. Q. J. R. Meteorol. Soc. 146.
- Funk, C. et al. (2015). The climate hazards infrared precipitation with stations. Scientific Data 2.
- Poggio, L. et al. (2021). SoilGrids 2.0. SOIL 7.
- Jones, J. W. et al. (2003). The DSSAT cropping system model. European Journal of Agronomy 18.
- Loshchilov, I., Glasmachers, T., Beyer, H.-G. (2019). Large scale black-box optimization by limited-memory matrix adaptation. IEEE Trans. Evol. Comput. 23.
- Avelino, J. et al. (2015). The coffee rust crises in Colombia and Central America (2008–2013). Food Security 7.
- Padovan, M. P. et al. (2018). Water loss by transpiration and soil evaporation in coffee shaded by Tabebuia rosea and Simarouba glauca. Agric. For. Meteorol. 248.
- Anacafé and Cedicafé technical bulletins on coffee leaf rust, fertilization and flowering.
- FEWS NET Guatemala food security outlooks (2018, 2024); MAGA crop monitoring reports (2014, 2018, 2023); FAO/WFP crop assessment for Guatemala (2010).
- ICTA publications on maize and bean for eastern Guatemala.
- Full list with links: `proyecto/resultados-modelo-keu.md` and `modelos matemáticos red neuronal/README.md` in the repository.
