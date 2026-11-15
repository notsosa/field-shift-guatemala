/// Textos de la interfaz en español e inglés. Se usa una clase simple en lugar
/// de archivos de traducción para poder añadir idiomas mayas con poco esfuerzo.
library;

import 'modelos.dart';
import 'motor/fao56.dart';
import 'motor/recomendador.dart';

class Txt {
  const Txt(this.en);

  /// Verdadero si la interfaz está en inglés.
  final bool en;

  String _(String es, String ingles) => en ? ingles : es;

  // General
  String get app => 'Field Shift';
  String get continuar => _('Continuar', 'Continue');
  String get guardar => _('Guardar', 'Save');
  String get cancelar => _('Cancelar', 'Cancel');
  String get listo => _('Listo', 'Done');
  String get atras => _('Atrás', 'Back');
  String get si => _('Sí', 'Yes');
  String get no => _('No', 'No');

  // Bienvenida
  String get lema => _('Decisiones de riego y manejo para tu parcela, sin depender de la señal.',
      'Irrigation and crop decisions for your plot, without depending on signal.');
  String get ventaja1 => _('Funciona sin conexión', 'Works offline');
  String get ventaja1d => _('Tus datos se guardan en el teléfono. El clima se actualiza solo con wifi.',
      'Your data stays on the phone. Weather updates only over Wi-Fi.');
  String get ventaja2 => _('Un registro por semana', 'One log per week');
  String get ventaja2d => _('Riego, plaga y fertilizante en menos de un minuto.',
      'Irrigation, pests and fertilizer in under a minute.');
  String get ventaja3 => _('Recomendación clara', 'A clear recommendation');
  String get ventaja3d => _('Cuánta agua le queda al cultivo y qué conviene hacer.',
      'How much water your crop has left and what to do next.');
  String get empezar => _('Empezar', 'Get started');
  String get verEjemplo => _('Ver un ejemplo', 'See an example');

  // Parcela
  String get tuParcela => _('Tu parcela', 'Your plot');
  String get parcelaAyuda => _('Fija el punto de tu parcela. Sirve para traer el clima de ese lugar.',
      'Set your plot location. It is used to fetch the weather for that place.');
  String get nombre => _('Nombre', 'Name');
  String get nombreEjemplo => _('La Vega', 'North field');
  String get usarUbicacion => _('Usar mi ubicación', 'Use my location');
  String get buscandoUbicacion => _('Buscando ubicación…', 'Finding location…');
  String get latitud => _('Latitud', 'Latitude');
  String get longitud => _('Longitud', 'Longitude');
  String get coordenadas => _('Coordenadas', 'Coordinates');
  String get puntoFijado => _('Punto fijado', 'Location set');
  String get sinUbicacion => _('No se pudo obtener la ubicación. Escribe las coordenadas o revisa el permiso.',
      'Could not get the location. Enter the coordinates or check the permission.');
  String get coordenadasInvalidas => _('Revisa las coordenadas.', 'Check the coordinates.');

  // Plantación
  String get plantacion => _('Plantación', 'Planting');
  String get cultivo => _('Cultivo', 'Crop');
  String get tipoCultivo => _('Tipo', 'Type');
  String get deTemporada => _('De temporada', 'Seasonal');
  String get fijo => _('Fijo', 'Perennial');
  String get fechaSiembra => _('Fecha de siembra', 'Planting date');
  String get fechaReferencia => _('Última floración', 'Last flowering');
  String get ciclo => _('Ciclo', 'Cycle');
  String dias(int n) => _('$n días', '$n days');
  String get suelo => _('Suelo', 'Soil');
  String get riego => _('Riego', 'Irrigation');
  String get tipoRiego => _('Tipo de riego', 'Irrigation type');
  String get temporadaRiego => _('Cuándo riegas', 'When you irrigate');
  String get plagaReciente => _('Plaga reciente', 'Recent pest');
  String get cualPlaga => _('¿Cuál?', 'Which one?');
  String get fertilizacion => _('Ya fertilizaste', 'Already fertilized');
  String get manejo => _('Manejo', 'Management');

  String nombreCultivo(String id) => switch (id) {
        'maiz' => _('Maíz', 'Maize'),
        'frijol' => _('Frijol', 'Beans'),
        'tomate' => _('Tomate', 'Tomato'),
        'cafe' => _('Café', 'Coffee'),
        _ => id,
      };

  String nombreSuelo(Suelo s) => switch (s) {
        Suelo.arenoso => _('Arenoso', 'Sandy'),
        Suelo.franco => _('Franco', 'Loam'),
        Suelo.arcilloso => _('Arcilloso', 'Clay'),
      };

  String nombreRiego(TipoRiego r) => switch (r) {
        TipoRiego.ninguno => _('Sin riego', 'Rainfed'),
        TipoRiego.manual => _('Manual', 'By hand'),
        TipoRiego.goteo => _('Goteo', 'Drip'),
        TipoRiego.aspersion => _('Aspersión', 'Sprinkler'),
        TipoRiego.gravedad => _('Por surcos', 'Furrow'),
      };

  String nombreTemporada(TemporadaRiego t) => switch (t) {
        TemporadaRiego.todoElAnio => _('Todo el año', 'All year'),
        TemporadaRiego.epocaSeca => _('Época seca', 'Dry season'),
        TemporadaRiego.auxilio => _('De auxilio', 'As backup'),
      };

  String nombreEtapa(Etapa e) => switch (e) {
        Etapa.inicial => _('Inicial', 'Initial'),
        Etapa.desarrollo => _('Desarrollo', 'Development'),
        Etapa.media => _('Floración y llenado', 'Flowering and fill'),
        Etapa.finalCiclo => _('Maduración', 'Ripening'),
        Etapa.cosechado => _('Ciclo terminado', 'Cycle complete'),
        Etapa.establecido => _('Establecido', 'Established'),
      };

  String nombrePlaga(NivelPlaga p) => switch (p) {
        NivelPlaga.ninguna => _('Ninguna', 'None'),
        NivelPlaga.leve => _('Leve', 'Mild'),
        NivelPlaga.moderada => _('Media', 'Medium'),
        NivelPlaga.fuerte => _('Fuerte', 'Severe'),
      };

  String get tipoPlaga => _('Tipo de plaga', 'Pest type');
  String nombreTipoPlaga(String id) => switch (id) {
        'roya' => _('Roya', 'Rust'),
        'minador' => _('Minador', 'Leaf miner'),
        'antracnosis' => _('Antracnosis', 'Anthracnose'),
        _ => _('Otra', 'Other'),
      };

  // Pestañas
  String get hoy => _('Hoy', 'Today');
  String get registros => _('Registros', 'Logs');
  String get ajustes => _('Ajustes', 'Settings');

  // Hoy
  String get aguaDisponible => _('agua disponible', 'water available');
  String tituloNivel(NivelAgua n) => switch (n) {
        NivelAgua.sinDatos => _('Falta el clima', 'Weather needed'),
        NivelAgua.bien => _('Tu cultivo tiene agua', 'Your crop has water'),
        NivelAgua.atencion => _('Se acerca al límite', 'Getting close to the limit'),
        NivelAgua.estres => _('Le falta agua', 'Your crop needs water'),
      };

  String detalleNivel(Recomendacion r, TipoRiego riego) {
    switch (r.nivel) {
      case NivelAgua.sinDatos:
        return _('Conéctate a wifi una vez para traer el clima de tu parcela.',
            'Connect to Wi-Fi once to fetch the weather for your plot.');
      case NivelAgua.bien:
        if (r.etapa == Etapa.cosechado) {
          return _('El ciclo terminó. Registra la nueva siembra cuando la tengas.',
              'The cycle is over. Add the next planting when you have it.');
        }
        return _('No hace falta regar por ahora.', 'No need to irrigate for now.');
      case NivelAgua.atencion:
      case NivelAgua.estres:
        if (riego == TipoRiego.ninguno) {
          return _('No tienes riego. Cubrir el suelo ayuda a guardar la humedad que queda.',
              'You have no irrigation. Mulching helps keep the moisture that is left.');
        }
        final mm = r.riegoSugerido.round();
        final n = r.riegosSugeridos;
        return _('Faltan unos $mm mm para salir del estrés: cerca de $n ${n == 1 ? 'riego' : 'riegos'} de ${nombreRiego(riego).toLowerCase()}, repartidos en los próximos días.',
            'About $mm mm are needed to end the stress: roughly $n ${nombreRiego(riego).toLowerCase()} ${n == 1 ? 'irrigation' : 'irrigations'}, spread over the next few days.');
    }
  }

  String get etapa => _('Etapa', 'Stage');
  String get cosecha => _('Cosecha', 'Harvest');
  String enDias(int n) => n <= 0 ? _('Ahora', 'Now') : _('En $n días', 'In $n days');
  String get dia => _('Día', 'Day');
  String get rendimiento => _('Rendimiento', 'Yield');
  String get ultimosDias => _('Últimos 14 días', 'Last 14 days');
  String get leyendaReserva => _('Agua en la zona de raíces', 'Water in the root zone');
  String get lluvia => _('Lluvia', 'Rain');
  String get necesidad => _('Necesidad', 'Demand');
  String get estaSemana => _('Esta semana', 'This week');
  String mm(double v) => '${v.round()} mm';
  String diasEstres(int n) => n == 0
      ? _('Sin días de estrés', 'No stress days')
      : _('$n ${n == 1 ? 'día' : 'días'} con estrés', '$n stress ${n == 1 ? 'day' : 'days'}');
  String get porHacer => _('Por hacer', 'To do');
  String get registroSemanal => _('Registro semanal', 'Weekly log');
  String get llenarRegistro => _('Llenar el registro de esta semana', 'Fill in this week’s log');

  String tituloAviso(Aviso a) => switch (a) {
        Aviso.registroPendiente => _('Registro semanal pendiente', 'Weekly log due'),
        Aviso.climaViejo => _('Clima desactualizado', 'Weather out of date'),
        Aviso.plaga => _('Plaga reportada', 'Pest reported'),
        Aviso.fertilizar => _('Momento de fertilizar', 'Time to fertilize'),
        Aviso.fertilizarEnEspera => _('Fertilizar: en espera', 'Fertilizing: on hold'),
        Aviso.cosechaCerca => _('Cosecha cercana', 'Harvest is near'),
      };

  String detalleAviso(Aviso a) => switch (a) {
        Aviso.registroPendiente => _('Con él la estimación mejora cada semana.', 'It improves the estimate every week.'),
        Aviso.climaViejo => _('Conéctate a wifi para actualizarlo.', 'Connect to Wi-Fi to update it.'),
        Aviso.plaga => _('Revísala con un extensionista y regístrala de nuevo.',
            'Check it with an extension agent and log it again.'),
        Aviso.fertilizar => _('El cultivo está en desarrollo y no hay fertilización registrada.',
            'The crop is developing and no fertilizer has been logged.'),
        Aviso.fertilizarEnEspera => _('No ha llovido en la última semana ni hay riego: espera a que haya agua.',
            'No rain in the last week and no irrigation: wait until there is water.'),
        Aviso.cosechaCerca => _('Evita regar de más y vigila la lluvia.', 'Avoid over-irrigating and watch the rain.'),
      };

  String get precision => _('Precisión de la estimación', 'Estimate accuracy');
  String nombrePrecision(Precision p) => switch (p) {
        Precision.baja => _('Baja', 'Low'),
        Precision.media => _('Media', 'Medium'),
        Precision.alta => _('Alta', 'High'),
      };
  String get precisionAyuda => _('Sube con clima reciente y registros semanales al día.',
      'It improves with recent weather and up-to-date weekly logs.');
  String get apoyaNoReemplaza => _('Esta estimación apoya tu decisión; no la reemplaza.',
      'This estimate supports your decision; it does not replace it.');

  // Sincronización
  String get clima => _('Clima', 'Weather');
  String get sincronizar => _('Actualizar clima', 'Update weather');
  String get sincronizando => _('Actualizando…', 'Updating…');
  String get nuncaSincronizado => _('Aún sin clima', 'No weather yet');
  String climaHasta(String f) => _('Clima hasta el $f', 'Weather through $f');
  String estimados(int n) => _('$n ${n == 1 ? 'día estimado' : 'días estimados'}', '$n ${n == 1 ? 'day' : 'days'} estimated');
  String get sinWifi => _('Sin wifi. El clima se actualiza solo con wifi para no gastar datos.',
      'No Wi-Fi. Weather updates only over Wi-Fi to save mobile data.');
  String get errorSync => _('No se pudo actualizar. Se usa el clima guardado.',
      'Could not update. Using saved weather.');
  String get soloWifi => _('Solo con wifi', 'Wi-Fi only');

  // Registro
  String get vecesRiego => _('Veces que regaste', 'Times you irrigated');
  String get plaga => _('Plaga', 'Pest');
  String get nota => _('Nota', 'Note');
  String get notaOpcional => _('Opcional', 'Optional');
  String get fertilizaste => _('Fertilizaste', 'Fertilized');
  String get queAplicaste => _('¿Qué aplicaste?', 'What did you apply?');
  String get ultimaSemana => _('Últimos 7 días', 'Last 7 days');
  String get sinRegistros => _('Aún no hay registros', 'No logs yet');
  String get sinRegistrosAyuda => _('Llena uno por semana para afinar la estimación.',
      'Fill one in each week to sharpen the estimate.');
  String get nuevo => _('Nuevo', 'New');
  String resumenRegistro(RegistroSemanal r) {
    final partes = <String>[
      r.riegos == 0 ? _('Sin riego', 'No irrigation') : _('${r.riegos} ${r.riegos == 1 ? 'riego' : 'riegos'}', '${r.riegos} ${r.riegos == 1 ? 'irrigation' : 'irrigations'}'),
      if (r.plaga != NivelPlaga.ninguna)
        _('plaga ${nombrePlaga(r.plaga).toLowerCase()}${r.tipoPlaga.isEmpty ? '' : ' (${nombreTipoPlaga(r.tipoPlaga).toLowerCase()})'}',
            '${nombrePlaga(r.plaga).toLowerCase()} pest${r.tipoPlaga.isEmpty ? '' : ' (${nombreTipoPlaga(r.tipoPlaga).toLowerCase()})'}'),
      if (r.fertilizo) _('fertilizó', 'fertilized'),
    ];
    return partes.join(' · ');
  }

  // Ajustes
  String get idioma => _('Idioma', 'Language');
  String get datos => _('Datos', 'Data');
  String get metodos => _('Métodos y fuentes', 'Methods and sources');
  String get borrarDatos => _('Borrar todos los datos', 'Erase all data');
  String get borrarPregunta => _('Se borrarán la parcela, la plantación, los registros y el clima guardado.',
      'The plot, planting, logs and saved weather will be erased.');
  String get borrar => _('Borrar', 'Erase');
  String get borrarRegistroPregunta => _('Se borrará este registro semanal.', 'This weekly log will be erased.');
  String get editar => _('Editar', 'Edit');

  // Métodos
  List<(String, String)> get metodosTexto => [
        (
          _('Agua del cultivo', 'Crop water'),
          _('Se calcula la evapotranspiración de referencia con Penman-Monteith y un balance diario de agua en la zona de raíces, según el manual FAO-56. El rendimiento por agua usa el factor de FAO-33.',
              'Reference evapotranspiration is computed with Penman-Monteith and a daily root-zone water balance, following FAO-56. Water-limited yield uses the FAO-33 factor.')
        ),
        (
          _('Clima', 'Weather'),
          _('Temperatura, humedad, viento, radiación y lluvia diarios de NASA POWER para el punto de la parcela. Representa una celda de unos 50 km, no la parcela exacta. La lluvia de esta fuente puede estar sobreestimada en el oriente de Guatemala.',
              'Daily temperature, humidity, wind, radiation and rain from NASA POWER for the plot location. It represents a cell of about 50 km, not the exact plot. Rain from this source may be overestimated in eastern Guatemala.')
        ),
        (
          _('Días estimados', 'Estimated days'),
          _('NASA POWER publica con unos días de retraso. Los días sin dato se completan con el promedio reciente y lluvia cero.',
              'NASA POWER publishes with a delay of a few days. Days without data are filled with the recent average and zero rain.')
        ),
        (
          _('Riego', 'Irrigation'),
          _('Cada riego registrado se convierte en una lámina de agua supuesta según el tipo: manual 4 mm, goteo 6 mm, aspersión 12 mm y surcos 30 mm.',
              'Each logged irrigation is converted to an assumed depth by type: by hand 4 mm, drip 6 mm, sprinkler 12 mm and furrow 30 mm.')
        ),
        (
          _('Cultivos', 'Crops'),
          _('Coeficientes de cultivo, raíces y etapas de FAO-56; variedades y ciclos del ICTA para maíz y frijol.',
              'Crop coefficients, roots and stages from FAO-56; ICTA varieties and cycles for maize and beans.')
        ),
        (
          _('Límites', 'Limits'),
          _('Es una estimación sin validar en campo. No considera suelos compactados, laderas ni enfermedades. Consulta a un extensionista antes de una decisión importante.',
              'This is an estimate not validated in the field. It does not account for compacted soils, slopes or diseases. Consult an extension agent before an important decision.')
        ),
      ];

  // Fechas
  static const _mesesEs = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  static const _mesesEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String fechaCorta(DateTime f) => en ? '${_mesesEn[f.month - 1]} ${f.day}' : '${f.day} ${_mesesEs[f.month - 1]}';

  String fechaLarga(DateTime f) => en
      ? '${_mesesEn[f.month - 1]} ${f.day}, ${f.year}'
      : '${f.day} ${_mesesEs[f.month - 1]} ${f.year}';
}
