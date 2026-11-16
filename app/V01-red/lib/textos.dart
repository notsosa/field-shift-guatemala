/// Textos de la interfaz en español e inglés. Se usa una clase simple en lugar
/// de archivos de traducción para poder añadir idiomas mayas con poco esfuerzo.
library;

import 'datos/mapa.dart';
import 'lenguas.dart';
import 'modelos.dart';
import 'motor/cafe.dart';
import 'motor/fao56.dart';
import 'motor/recomendador.dart';

class Txt {
  const Txt(this.en, {this.manzanas = true, this.lengua = 'es'});

  /// Verdadero si la interfaz está en inglés.
  final bool en;

  /// Código del idioma elegido. Con una lengua maya la base es el español y
  /// solo cambian los términos del glosario (lenguas.dart).
  final String lengua;
  bool get esMaya => esLenguaMaya(lengua);
  String get nombreMaya => esMaya ? nombreLengua(lengua) : '';

  /// Término del glosario con el español al lado; igual al español si no hay
  /// lengua maya activa o no hay borrador de esa palabra.
  String _m(String id, String es) => esMaya ? conEspanol(lengua, id, es) : es;

  /// Solo el término maya (para espacios justos); español si no hay borrador.
  String _solo(String id, String es) => esMaya ? (palabraMaya(lengua, id) ?? es) : es;

  /// Verdadero si las áreas y la escala del plano van en manzanas; si no, en
  /// hectáreas y kilómetros.
  final bool manzanas;

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
  String get parcelaAyuda => _('Fija el punto de tu finca: con tu ubicación si estás en ella, o buscándola en el mapa. Sirve para traer el clima de ese lugar.',
      'Set your farm location: with your position if you are there, or by finding it on the map. It is used to fetch the weather for that place.');
  String get elegirEnMapa => _('Elegir en el mapa', 'Choose on the map');
  String get ubicarFinca => _('Ubicar la finca', 'Locate the farm');
  String get ayudaUbicar => _('Arrastra el mapa hasta dejar la marca sobre tu finca. Acerca con dos dedos o con los botones.',
      'Drag the map until the marker is over your farm. Zoom with two fingers or the buttons.');
  String get usarEstePunto => _('Usar este punto', 'Use this location');
  String get sinWifiMapa => _('Sin wifi no se puede cargar el mapa. Conéctate o escribe las coordenadas.',
      'The map cannot load without Wi-Fi. Connect or enter the coordinates.');
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
  String get suelo => _m('suelo', _('Suelo', 'Soil'));
  String get riego => _('Riego', 'Irrigation');
  String get tipoRiego => _('Tipo de riego', 'Irrigation type');
  String get temporadaRiego => _('Cuándo riegas', 'When you irrigate');
  String get plagaReciente => _('Plaga reciente', 'Recent pest');
  String get cualPlaga => _('¿Cuál?', 'Which one?');
  String get fertilizacion => _('Ya fertilizaste', 'Already fertilized');
  String get manejo => _('Manejo', 'Management');
  // Finca y croquis
  String get finca => _('Finca', 'Farm');
  String get plantaciones => _('Plantaciones', 'Plantings');
  String cuantasPlantaciones(int n) =>
      _('$n ${n == 1 ? 'plantación' : 'plantaciones'}', '$n ${n == 1 ? 'planting' : 'plantings'}');
  String get nuevaPlantacion => _('Nueva plantación', 'New planting');
  String get contornoFinca => _('Contorno de la finca', 'Farm outline');
  String get dibujarContorno => _('Dibujar el contorno de la finca', 'Draw the farm outline');
  String get editarContorno => _('Cambiar el contorno de la finca', 'Change the farm outline');
  String get perimetro => _('Perímetro', 'Perimeter');
  String get sinDibujar => _('Sin dibujar', 'Not drawn');
  String get dibujado => _('Dibujado', 'Drawn');
  String get ayudaTrazoFinca => _('Toca las esquinas de tu finca, una por una, para dibujar su contorno. Si no cabe, agranda el mapa con el botón +.',
      'Tap the corners of your farm, one by one, to draw its outline. If it does not fit, enlarge the map with the + button.');
  String get ayudaTrazoPlantacion => _('Toca las esquinas del área sembrada para marcar su perímetro dentro de la finca.',
      'Tap the corners of the planted area to mark its perimeter inside the farm.');
  String puntosMarcados(int n) => n < 3
      ? _('Marca 3 puntos o más', 'Mark 3 or more points')
      : _('$n puntos', '$n points');
  String get deshacer => _('Deshacer', 'Undo');
  String get borrarTrazo => _('Borrar todo', 'Clear');
  String get omitir => _('Omitir', 'Skip');
  String get croquisNota => _('El mapa se descarga con wifi y queda guardado en el teléfono para usarlo sin conexión.',
      'The map downloads over Wi-Fi and stays on the phone for offline use.');
  String nombreCapa(CapaMapa c) => switch (c) {
        CapaMapa.mapa => _('Mapa', 'Map'),
        CapaMapa.satelite => _('Satélite', 'Satellite'),
        CapaMapa.croquis => _('Croquis', 'Sketch'),
      };
  String _numero(double v) => v >= 10
      ? v.round().toString()
      : v >= 1
          ? v.toStringAsFixed(1)
          : v.toStringAsFixed(2);

  /// Rótulo del control de escala del plano.
  String get escalaMapa => manzanas ? _('Área del mapa', 'Map area') : _('Ancho del mapa', 'Map width');

  /// Tamaño del plano: en manzanas, el área del cuadrado; en métrico, su ancho.
  String nombreLado(double m) {
    if (manzanas) return '${_numero(m * m / metrosPorManzana)} mz';
    return m >= 1000 ? '${_numero(m / 1000).replaceAll('.0', '')} km' : '${m.round()} m';
  }

  String get unidades => _('Unidades', 'Units');
  String nombreUnidad(Unidad u) => switch (u) {
        Unidad.manzanas => _('Manzanas', 'Manzanas'),
        Unidad.metrico => _('Hectáreas y km', 'Hectares and km'),
      };
  String get paraCualPlantacion => _('¿Para cuál plantación?', 'Which planting is it for?');
  String get sinMapa => _('Sin mapa guardado. Conéctate a wifi para descargarlo.',
      'No saved map. Connect to Wi-Fi to download it.');
  String area(double m2) =>
      manzanas ? '${_numero(m2 / metrosPorManzana)} mz' : '${_numero(m2 / 10000)} ha';
  String get tocaParaElegir => _('Toca una plantación en el mapa para elegirla.', 'Tap a planting on the map to select it.');
  String porcentajeAgua(int n) => _('$n % de agua', '$n % water');
  String get nombreLote => _('Nombre', 'Name');
  String get ejemploLote => _('Lote norte (opcional)', 'North lot (optional)');
  String get borrarPlantacion => _('Borrar plantación', 'Delete planting');
  String get borrarPlantacionPregunta => _('Se borrará esta plantación con sus registros semanales.',
      'This planting and its weekly logs will be erased.');
  String nombrePlantacion(Plantacion p) => p.nombre.isNotEmpty ? p.nombre : nombreCultivo(p.cultivoId);

  /// Para espacios justos (rótulos del plano): solo el término maya.
  String nombrePlantacionCorto(Plantacion p) => p.nombre.isNotEmpty ? p.nombre : nombreCultivoCorto(p.cultivoId);

  String get siembra => _m('siembra', _('Siembra', 'Planting'));
  String get sueloYRiego => _('Suelo y riego', 'Soil and irrigation');
  String get plagaAyuda => _('Insectos o enfermedad', 'Insects or disease');
  String get ejemploPlaga => _('Gusano cogollero', 'Fall armyworm');
  String get desdeCuando => _('Desde cuándo', 'Since');
  String get danio => _('Daño', 'Damage');
  String get yaTratada => _('Ya la trataste', 'Already treated');
  String get conQue => _('¿Con qué?', 'With what?');
  String get fertilizanteAyuda => _('Abono de esta siembra', 'For this planting');
  String get claseFertilizante => _('Tipo', 'Type');
  String get producto => _('Producto', 'Product');
  String get ejemploFertilizante => _('Urea, 15-15-15…', 'Urea, 15-15-15…');
  String get fechaAplicacion => _('Fecha de aplicación', 'Date applied');
  String nombreFertilizante(TipoFertilizante f) => switch (f) {
        TipoFertilizante.quimico => _('Químico', 'Chemical'),
        TipoFertilizante.organico => _('Orgánico', 'Organic'),
        TipoFertilizante.ambos => _('Ambos', 'Both'),
      };

  String _cultivoEs(String id) => switch (id) {
        'maiz' => _('Maíz', 'Maize'),
        'frijol' => _('Frijol', 'Beans'),
        'tomate' => _('Tomate', 'Tomato'),
        'cafe' => _('Café', 'Coffee'),
        _ => id,
      };

  /// En lengua maya: «ixim · Maíz». Si no, el nombre normal.
  String nombreCultivo(String id) => _m(id, _cultivoEs(id));

  /// En lengua maya, solo el término («ixim»); para el plano y chips.
  String nombreCultivoCorto(String id) => _solo(id, _cultivoEs(id));

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

  // Pestañas
  String get hoy => _solo('hoy', _('Hoy', 'Today'));

  /// Título grande de Hoy: con lengua maya lleva el español al lado.
  String get hoyTitulo => _m('hoy', _('Hoy', 'Today'));
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
  String get lluvia => _m('lluvia', _('Lluvia', 'Rain'));
  String get necesidad => _('Necesidad', 'Demand');
  String get estaSemana => _('Esta semana', 'This week');

  // Próximos días: lo que estima la red del equipo (solo donde se midió).
  String get proximos7 => _('Próximos 7 días', 'Next 7 days');
  String get estresEsperado => _('Se espera estrés por falta de agua en la próxima semana',
      'Water stress is expected next week');
  String get sinEstresEsperado => _('No se espera estrés por falta de agua en la próxima semana',
      'No water stress is expected next week');
  String estresEn14(double v) {
    final n = v.round();
    return n == 0
        ? _('En 14 días: sin días de estrés', 'In 14 days: no stress days')
        : _('En 14 días: unos $n ${n == 1 ? 'día' : 'días'} con estrés',
            'In 14 days: about $n stress ${n == 1 ? 'day' : 'days'}');
  }

  String rendimientoFinal(double f) => _('Rendimiento esperado al final del ciclo: ${(f * 100).round()} %',
      'Expected yield at the end of the cycle: ${(f * 100).round()} %');
  String get leyendaRed => _(
      'Estimado por la red del equipo con el clima de las últimas semanas. No es un pronóstico del tiempo; se midió contra el balance de agua de esta misma app.',
      'Estimated by the team’s neural network from the last weeks of weather. It is not a weather forecast; it was measured against this app’s own water balance.');
  // Café: formulario de la plantación.
  String get cafeSeccion => _('Café', 'Coffee');
  String get sombra => _m('sombra', _('Sombra', 'Shade'));
  String nombreSombra(Sombra s) => switch (s) {
        Sombra.ninguna => _('Sin sombra', 'No shade'),
        Sombra.arbolesPerennes => _('Árboles de hoja perenne', 'Evergreen trees'),
        Sombra.arbolesCaducos => _('Árboles de hoja caduca', 'Deciduous trees'),
        Sombra.bananoRegulado => _('Banano regulado con mulch', 'Managed banana with mulch'),
        Sombra.bananoDenso => _('Banano denso sin deshije', 'Dense banana, not thinned'),
      };
  String get bananoReferencia => _('Valores de referencia de FAO-56 de la auditoría del asesor, sin medición en campo',
      'FAO-56 reference values from the advisor’s audit, not measured in the field');
  String get sueloSurcos => _('Suelo entre los surcos', 'Ground between the rows');
  String nombreSueloSurcos(SueloSurcos s) => switch (s) {
        SueloSurcos.limpio => _('Limpio o con mulch', 'Clean or mulched'),
        SueloSurcos.malezas => _('Con malezas', 'With weeds'),
      };
  String get sueloSurcosConArboles => _('Con árboles de sombra, el modelo no distingue las malezas.',
      'With shade trees, the model does not tell weeds apart.');
  String get prioridadRiego => _('Al regar, qué pesa más', 'When irrigating, what matters more');
  String nombrePrioridad(PrioridadRiego p) => switch (p) {
        PrioridadRiego.ahorrarAgua => _('Ahorrar agua', 'Save water'),
        PrioridadRiego.protegerCultivo => _('Proteger el cultivo', 'Protect the crop'),
      };
  String get prioridadAyuda => _(
      'Ahorrar agua: se riega solo si evita varios días de estrés. Proteger el cultivo: se riega aunque evite pocos.',
      'Save water: irrigate only if it avoids several stress days. Protect the crop: irrigate even if it avoids few.');

  // Café: tarjeta de Hoy.
  String get tarjetaCafe => _('Café', 'Coffee');
  String get conviene20 => _('Conviene regar unos 20 mm ahora', 'Irrigating about 20 mm now is advisable');
  String get noHaceFaltaRegar => _('No hace falta regar ahora', 'No need to irrigate now');
  String diasEvitadosCafe(double v) {
    final n = v.round();
    return n <= 0
        ? _('La red estima que regar no evitaría días de estrés en los próximos 30 días.',
            'The network estimates that irrigating would not avoid stress days in the next 30 days.')
        : _('La red estima que regar evitaría unos $n ${n == 1 ? 'día' : 'días'} de estrés en los próximos 30 días.',
            'The network estimates that irrigating would avoid about $n stress ${n == 1 ? 'day' : 'days'} in the next 30 days.');
  }

  String prioridadUsada(int precio) => precio == PrioridadRiego.protegerCultivo.precio
      ? _('Prioridad usada: proteger el cultivo.', 'Priority used: protect the crop.')
      : _('Prioridad usada: ahorrar agua.', 'Priority used: save water.');
  String get antracnosisCambioPrioridad => _(
      'Hay aviso de antracnosis por estrés: se usó «proteger el cultivo» aunque elegiste ahorrar agua.',
      'There is an anthracnose notice due to stress: “protect the crop” was used although you chose to save water.');
  String reglaFao(bool riega) => riega
      ? _('Regla FAO-56 (el suelo gastó más del 40 % de su agua disponible): regar.',
          'FAO-56 rule (the soil used more than 40 % of its available water): irrigate.')
      : _('Regla FAO-56 (el suelo gastó menos del 40 % de su agua disponible): no regar.',
          'FAO-56 rule (the soil used less than 40 % of its available water): do not irrigate.');
  String get redCafeNoAplica => _(
      'La recomendación de riego solo está disponible entre 20 y 100 días después de una floración de febrero a mayo, que es donde se entrenó la red.',
      'The irrigation recommendation is only available 20 to 100 days after a February-to-May flowering, which is where the network was trained.');
  String get avisosDelCafe => _('Avisos', 'Notices');
  String tituloAvisoCafe(AvisoCafe a) => switch (a.tipo) {
        TipoAvisoCafe.abono => a.nivel == NivelAvisoCafe.abonarYa
            ? _('Abono: conviene aplicarlo ahora', 'Fertilizer: a good time to apply it')
            : _('Abono en espera: suelo seco', 'Fertilizer on hold: dry soil'),
        TipoAvisoCafe.antracnosis => _('Antracnosis: la planta está bajo estrés por falta de agua',
            'Anthracnose: the plant is under water stress'),
        TipoAvisoCafe.roya => _('Roya posible: temperatura en su rango de germinación',
            'Rust possible: temperature in its germination range'),
      };
  String detalleAvisoCafe(AvisoCafe a) {
    final n = a.numeros;
    return switch (a.tipo) {
      TipoAvisoCafe.abono => _('Lluvia de 7 días: ${n['lluvia7']!.round()} mm.', 'Rain in 7 days: ${n['lluvia7']!.round()} mm.'),
      TipoAvisoCafe.antracnosis => _('Con estrés ${n['diasEstres28']!.round()} de los últimos 28 días.',
          'Under stress ${n['diasEstres28']!.round()} of the last 28 days.'),
      TipoAvisoCafe.roya => _('Temperatura media de 14 días: ${n['tempMedia14']!.toStringAsFixed(1)} °C.',
          '14-day mean temperature: ${n['tempMedia14']!.toStringAsFixed(1)} °C.'),
    };
  }

  String nivelConfianza(String nivel) => switch (nivel) {
        'alta' => _('alta', 'high'),
        'media-alta' => _('media-alta', 'medium-high'),
        'media' => _('media', 'medium'),
        'baja-media' => _('baja-media', 'low-medium'),
        'baja' => _('baja', 'low'),
        'orientativa' => _('orientativa', 'indicative'),
        _ => nivel,
      };
  String fuenteAviso(String fuente, String nivel) =>
      _('Fuente: $fuente · confianza ${nivelConfianza(nivel)}', 'Source: $fuente · confidence ${nivelConfianza(nivel)}');
  String get leyendaAvisosCafe => _(
      'Los avisos dicen lo que favorece el clima; no dicen cuánta plaga hay ni cuánto daño habrá.',
      'Notices say what the weather favours; they do not say how much pest there is or how much damage will follow.');
  String get leyendaRedCafe => _(
      'Estimado por la red del equipo con el clima de NASA POWER. La red se entrenó con otra fuente de lluvia (ERA5) y con temperaturas corregidas a la parcela: aquí es una vista previa, no está validada.',
      'Estimated by the team’s neural network from NASA POWER weather. The network was trained with another rain source (ERA5) and plot-corrected temperatures: here it is a preview and has not been validated.');
  String get leyendaBananoCafe => _(
      'Según la auditoría del asesor del equipo, el banano regulado con mulch gasta menos agua que un cafetal al sol con malezas, y más que un cafetal con suelo limpio. No es una promesa de ahorro de agua: los valores son de referencia (FAO-56) y no están medidos en campo.',
      'According to the team advisor’s audit, managed banana with mulch uses less water than sun-grown coffee with weeds, and more than coffee on clean ground. It is not a promise of water savings: the values are FAO-56 references, not field measurements.');

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
        Aviso.cosechaCerca => _('Cosecha cercana', 'Harvest is near'),
      };

  String detalleAviso(Aviso a) => switch (a) {
        Aviso.registroPendiente => _('Con él la estimación mejora cada semana.', 'It improves the estimate every week.'),
        Aviso.climaViejo => _('Conéctate a wifi para actualizarlo.', 'Connect to Wi-Fi to update it.'),
        Aviso.plaga => _('Revísala con un extensionista y regístrala de nuevo.',
            'Check it with an extension agent and log it again.'),
        Aviso.fertilizar => _('El cultivo está en desarrollo y no hay fertilización registrada.',
            'The crop is developing and no fertilizer has been logged.'),
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
      if (r.plaga != NivelPlaga.ninguna) _('plaga ${nombrePlaga(r.plaga).toLowerCase()}', '${nombrePlaga(r.plaga).toLowerCase()} pest'),
      if (r.fertilizo) _('fertilizó', 'fertilized'),
    ];
    return partes.join(' · ');
  }

  // Ajustes
  String get idioma => _('Idioma', 'Language');

  // Lenguas mayas (borrador). Siempre en español: con una lengua maya activa la base es el español.
  String get lenguasMayasRotulo => _('Lenguas mayas (borrador)', 'Mayan languages (draft)');
  String get avisoBorrador =>
      'Traducción en borrador: solo algunas palabras están en $nombreMaya y ningún hablante las ha revisado. Lo demás se muestra en español.';
  String get palabrasEn => 'Palabras en $nombreMaya';
  String get avisoRevision =>
      'Estas palabras deben revisarlas hablantes y la Academia de Lenguas Mayas de Guatemala antes de usarse con productores. El equipo entrena aparte un traductor experimental que aprende de las correcciones de los hablantes.';
  String get sinBorrador => 'Sin borrador: se muestra en español';
  String estadoCotejo(Cotejo c) => switch (c) {
        Cotejo.verificado => 'Coincide con un diccionario del equipo',
        Cotejo.variante => 'Coincide con otra escritura',
        Cotejo.sinVerificar => 'Sin verificar',
      };
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
          _('Mapa de la finca', 'Farm map'),
          _('El plano muestra un cuadrado centrado en el punto de la finca, con el norte arriba. El fondo viene de OpenStreetMap (mapa) o de Esri World Imagery (satélite); se descarga solo con wifi y se guarda en el teléfono. Las áreas se calculan a partir de lo que dibujas, así que son aproximadas.',
              'The plan shows a square centred on the farm location, north up. The background comes from OpenStreetMap (map) or Esri World Imagery (satellite); it downloads only over Wi-Fi and is stored on the phone. Areas are computed from what you draw, so they are approximate.')
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
