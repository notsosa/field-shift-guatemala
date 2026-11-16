/// Textos de la interfaz en español e inglés. Se usa una clase simple en lugar
/// de archivos de traducción para poder añadir idiomas mayas con poco esfuerzo.
library;

import 'datos/mapa.dart';
import 'modelos.dart';
import 'motor/fao56.dart';
import 'motor/recomendador.dart';

class Txt {
  const Txt(this.en, {this.manzanas = true});

  /// Verdadero si la interfaz está en inglés.
  final bool en;

  /// Verdadero si las áreas y la escala del plano van en manzanas; si no, en
  /// hectáreas y kilómetros.
  final bool manzanas;

  String _(String es, String ingles) => en ? ingles : es;

  String bilingue(String es, String ingles) => _(es, ingles);

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
  String get lema => _(
    'Decisiones de riego y manejo para tu parcela, sin depender de la señal.',
    'Irrigation and crop decisions for your plot, without depending on signal.',
  );
  String get ventaja1 => _('Funciona sin conexión', 'Works offline');
  String get ventaja1d => _(
    'Tus datos se guardan en el teléfono. El clima se actualiza solo con wifi.',
    'Your data stays on the phone. Weather updates only over Wi-Fi.',
  );
  String get ventaja2 => _('Un registro por semana', 'One log per week');
  String get ventaja2d => _(
    'Riego, plaga y fertilizante en menos de un minuto.',
    'Irrigation, pests and fertilizer in under a minute.',
  );
  String get ventaja3 => _('Recomendación clara', 'A clear recommendation');
  String get ventaja3d => _(
    'Cuánta agua le queda al cultivo y qué conviene hacer.',
    'How much water your crop has left and what to do next.',
  );
  String get empezar => _('Empezar', 'Get started');
  String get verEjemplo => _('Ver un ejemplo', 'See an example');

  // Parcela
  String get tuParcela => _('Tu parcela', 'Your plot');
  String get parcelaAyuda => _(
    'Fija el punto de tu finca: con tu ubicación si estás en ella, o buscándola en el mapa. Sirve para traer el clima de ese lugar.',
    'Set your farm location: with your position if you are there, or by finding it on the map. It is used to fetch the weather for that place.',
  );
  String get elegirEnMapa => _('Elegir en el mapa', 'Choose on the map');
  String get ubicarFinca => _('Ubicar la finca', 'Locate the farm');
  String get ayudaUbicar => _(
    'Arrastra el mapa hasta dejar la marca sobre tu finca. Acerca con dos dedos o con los botones.',
    'Drag the map until the marker is over your farm. Zoom with two fingers or the buttons.',
  );
  String get usarEstePunto => _('Usar este punto', 'Use this location');
  String get sinWifiMapa => _(
    'Sin wifi no se puede cargar el mapa. Conéctate o escribe las coordenadas.',
    'The map cannot load without Wi-Fi. Connect or enter the coordinates.',
  );
  String get nombre => _('Nombre', 'Name');
  String get nombreEjemplo => _('La Vega', 'North field');
  String get usarUbicacion => _('Usar mi ubicación', 'Use my location');
  String get buscandoUbicacion => _('Buscando ubicación…', 'Finding location…');
  String get latitud => _('Latitud', 'Latitude');
  String get longitud => _('Longitud', 'Longitude');
  String get coordenadas => _('Coordenadas', 'Coordinates');
  String get puntoFijado => _('Punto fijado', 'Location set');
  String get sinUbicacion => _(
    'No se pudo obtener la ubicación. Escribe las coordenadas o revisa el permiso.',
    'Could not get the location. Enter the coordinates or check the permission.',
  );
  String get coordenadasInvalidas =>
      _('Revisa las coordenadas.', 'Check the coordinates.');

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
  // Finca y croquis
  String get finca => _('Finca', 'Farm');
  String get plantaciones => _('Plantaciones', 'Plantings');
  String cuantasPlantaciones(int n) => _(
    '$n ${n == 1 ? 'plantación' : 'plantaciones'}',
    '$n ${n == 1 ? 'planting' : 'plantings'}',
  );
  String get nuevaPlantacion => _('Nueva plantación', 'New planting');
  String get contornoFinca => _('Contorno de la finca', 'Farm outline');
  String get dibujarContorno =>
      _('Dibujar el contorno de la finca', 'Draw the farm outline');
  String get editarContorno =>
      _('Cambiar el contorno de la finca', 'Change the farm outline');
  String get perimetro => _('Perímetro', 'Perimeter');
  String get sinDibujar => _('Sin dibujar', 'Not drawn');
  String get dibujado => _('Dibujado', 'Drawn');
  String get ayudaTrazoFinca => _(
    'Toca las esquinas de tu finca, una por una, para dibujar su contorno. Si no cabe, agranda el mapa con el botón +.',
    'Tap the corners of your farm, one by one, to draw its outline. If it does not fit, enlarge the map with the + button.',
  );
  String get ayudaTrazoPlantacion => _(
    'Toca las esquinas del área sembrada para marcar su perímetro dentro de la finca.',
    'Tap the corners of the planted area to mark its perimeter inside the farm.',
  );
  String puntosMarcados(int n) => n < 3
      ? _('Marca 3 puntos o más', 'Mark 3 or more points')
      : _('$n puntos', '$n points');
  String get deshacer => _('Deshacer', 'Undo');
  String get borrarTrazo => _('Borrar todo', 'Clear');
  String get omitir => _('Omitir', 'Skip');
  String get croquisNota => _(
    'El mapa se descarga con wifi y queda guardado en el teléfono para usarlo sin conexión.',
    'The map downloads over Wi-Fi and stays on the phone for offline use.',
  );
  String nombreCapa(CapaMapa c) => switch (c) {
    CapaMapa.mapa => _('Mapa', 'Map'),
    CapaMapa.satelite => _('Satélite', 'Satellite'),
    CapaMapa.relieve3d => _('3D', '3D'),
  };
  String _numero(double v) => v >= 10
      ? v.round().toString()
      : v >= 1
      ? v.toStringAsFixed(1)
      : v.toStringAsFixed(2);

  /// Rótulo del control de escala del plano.
  String get escalaMapa => manzanas
      ? _('Área del mapa', 'Map area')
      : _('Ancho del mapa', 'Map width');

  /// Tamaño del plano: en manzanas, el área del cuadrado; en métrico, su ancho.
  String nombreLado(double m) {
    if (manzanas) return '${_numero(m * m / metrosPorManzana)} mz';
    return m >= 1000
        ? '${_numero(m / 1000).replaceAll('.0', '')} km'
        : '${m.round()} m';
  }

  String get unidades => _('Unidades', 'Units');
  String nombreUnidad(Unidad u) => switch (u) {
    Unidad.manzanas => _('Manzanas', 'Manzanas'),
    Unidad.metrico => _('Hectáreas y km', 'Hectares and km'),
  };
  String get paraCualPlantacion =>
      _('¿Para cuál plantación?', 'Which planting is it for?');
  String get sinMapa => _(
    'Sin mapa guardado. Conéctate a wifi para descargarlo.',
    'No saved map. Connect to Wi-Fi to download it.',
  );
  String area(double m2) => manzanas
      ? '${_numero(m2 / metrosPorManzana)} mz'
      : '${_numero(m2 / 10000)} ha';
  String porcentajeAgua(int n) => _('$n % de agua', '$n % water');
  String get nombreLote => _('Nombre', 'Name');
  String get ejemploLote => _('Lote norte (opcional)', 'North lot (optional)');
  String get borrarPlantacion => _('Borrar plantación', 'Delete planting');
  String get borrarPlantacionPregunta => _(
    'Se borrará esta plantación con sus registros semanales.',
    'This planting and its weekly logs will be erased.',
  );
  String nombrePlantacion(Plantacion p) =>
      p.nombre.isNotEmpty ? p.nombre : nombreCultivo(p.cultivoId);

  String get siembra => _('Siembra', 'Planting');
  String get sueloYRiego => _('Suelo y riego', 'Soil and irrigation');
  String get plagaAyuda => _('Insectos o enfermedad', 'Insects or disease');
  String get ejemploPlaga => _('Gusano cogollero', 'Fall armyworm');
  String get desdeCuando => _('Desde cuándo', 'Since');
  String get danio => _('Daño', 'Damage');
  String get yaTratada => _('Ya la trataste', 'Already treated');
  String get conQue => _('¿Con qué?', 'With what?');
  String get fertilizanteAyuda =>
      _('Abono de esta siembra', 'For this planting');
  String get claseFertilizante => _('Tipo', 'Type');
  String get producto => _('Producto', 'Product');
  String get ejemploFertilizante => _('Urea, 15-15-15…', 'Urea, 15-15-15…');
  String get fechaAplicacion => _('Fecha de aplicación', 'Date applied');
  String nombreFertilizante(TipoFertilizante f) => switch (f) {
    TipoFertilizante.quimico => _('Químico', 'Chemical'),
    TipoFertilizante.organico => _('Orgánico', 'Organic'),
    TipoFertilizante.ambos => _('Ambos', 'Both'),
  };

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

  String get noSeGuardo => _(
    'No se pudo guardar. Vuelve a intentarlo.',
    'Could not save. Try again.',
  );
  String get registroAgua =>
      _('Agua y riego por fecha', 'Dated water and irrigation');
  String get aguaFinca => _('Agua compartida de la finca', 'Shared farm water');
  String get aguaCompartidaAyuda => _(
    'Indica el suministro para esta fecha. El saldo, si lo conoces, se reparte entre todos los lotes. No se asume disponible otro día.',
    'Record supply for this date. The remaining volume, if known, is shared across all plots. It is not assumed available on other days.',
  );
  String get riegoDiarioAyuda => _(
    'La disponibilidad y haber regado son datos distintos. Si no conoces los milímetros aplicados, se usa una lámina supuesta por tipo y se indica como estimada. El resumen semanal conserva fechas estimadas.',
    'Availability and actual irrigation are different observations. Without a known applied depth, an assumed depth by type is marked as estimated. Weekly summaries retain estimated dates.',
  );
  String get sinDato => _('Sin dato', 'Unknown');
  String get opcional => _('Opcional', 'Optional');
  String get saldoM3 => _('Saldo (m³)', 'Remaining (m³)');
  String get laminaMm => _('Aplicado (mm)', 'Applied (mm)');
  String get fechaObservacion => _('Fecha', 'Date');
  String get necesitoRiego => _(
    '¿Se necesitó regar en esta fecha?',
    'Was irrigation needed on this date?',
  );
  String get regasteFecha =>
      _('¿Regaste en esta fecha?', 'Did you irrigate on this date?');
  String get datosAguaInvalidos => _(
    'Revisa los datos: el saldo admite cero; la lámina aplicada debe ser positiva. Puedes dejar cantidades desconocidas en blanco.',
    'Check the data: remaining volume may be zero; applied depth must be positive. Leave unknown amounts blank.',
  );
  String nombreDisponibilidad(DisponibilidadAgua d) => switch (d) {
    DisponibilidadAgua.desconocida => sinDato,
    DisponibilidadAgua.si => _('Hay agua', 'Available'),
    DisponibilidadAgua.no => _('Sin agua', 'Unavailable'),
  };
  String get aguaHoy => _('Suministro de agua hoy', 'Water supply today');
  String get lluviaDesconocida => _('Lluvia incompleta', 'Incomplete rain');
  String get escenarioLluvia => _(
    'Faltan observaciones de lluvia. El balance muestra un escenario sin aporte en esos días; la reserva de agua del suelo es una estimación.',
    'Rain observations are missing. The balance shows a scenario without rain input on those days; soil water reserves are an estimate.',
  );
  String get copiarGeoJson => _('Copiar GeoJSON', 'Copy GeoJSON');
  String get geoJsonCopiado => _('Geometrías copiadas', 'Geometries copied');
  String get geoJsonAyuda => _(
    'Coordenadas geográficas y áreas aproximadas de los lotes.',
    'Geographic coordinates and approximate plot areas.',
  );
  String get vistaMapaAyuda => _(
    'Pellizca para acercar y arrastra para explorar. Toca para marcar una esquina.',
    'Pinch to zoom and drag to explore. Tap to mark a corner.',
  );
  String get centroNoMueve => _(
    'Cambiar el punto ajusta la vista y la consulta de clima. Los contornos ya dibujados permanecen en su ubicación.',
    'Changing this point updates the view and weather location. Existing outlines stay at their geographic locations.',
  );
  String errorGeometria(ErrorGeometria e) => switch (e) {
    ErrorGeometria.pocosPuntos => _(
      'Marca al menos tres esquinas.',
      'Mark at least three corners.',
    ),
    ErrorGeometria.coordenadas => _(
      'Revisa las coordenadas del contorno.',
      'Check the outline coordinates.',
    ),
    ErrorGeometria.degenerado => _(
      'El contorno necesita superficie; evita puntos repetidos o alineados.',
      'The outline needs an area; avoid repeated or collinear points.',
    ),
    ErrorGeometria.cruce => _(
      'El contorno se cruza consigo mismo. Deshaz y corrige las esquinas.',
      'The outline crosses itself. Undo and correct the corners.',
    ),
    ErrorGeometria.fueraFinca => _(
      'Un lote queda fuera de la finca. Revisa ambos contornos.',
      'A plot lies outside the farm. Check both outlines.',
    ),
    ErrorGeometria.solapamiento => _(
      'Este lote se superpone con otro. Pueden compartir borde, pero no superficie.',
      'This plot overlaps another. Shared borders are allowed, shared area is not.',
    ),
    ErrorGeometria.fincaInvalida => _(
      'Revisa primero los contornos existentes; hay una geometría inválida.',
      'Check existing outlines first; a geometry is invalid.',
    ),
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
    NivelAgua.atencion => _(
      'Se acerca al límite',
      'Getting close to the limit',
    ),
    NivelAgua.estres => _('Le falta agua', 'Your crop needs water'),
  };

  String detalleNivel(Recomendacion r, TipoRiego riego) {
    if (r.diasLluviaFaltante > 0 && r.nivel == NivelAgua.bien) {
      return _(
        'El escenario estimado no pide riego por ahora. Confirma los días sin lluvia observada.',
        'The estimated scenario does not require irrigation for now. Check days without observed rain.',
      );
    }
    switch (r.nivel) {
      case NivelAgua.sinDatos:
        return _(
          'Conéctate a wifi una vez para traer el clima de tu parcela.',
          'Connect to Wi-Fi once to fetch the weather for your plot.',
        );
      case NivelAgua.bien:
        if (r.etapa == Etapa.cosechado) {
          return _(
            'El ciclo terminó. Registra la nueva siembra cuando la tengas.',
            'The cycle is over. Add the next planting when you have it.',
          );
        }
        return _(
          'No hace falta regar por ahora.',
          'No need to irrigate for now.',
        );
      case NivelAgua.atencion:
      case NivelAgua.estres:
        if (riego == TipoRiego.ninguno) {
          return _(
            'No tienes riego. Cubrir el suelo ayuda a guardar la humedad que queda.',
            'You have no irrigation. Mulching helps keep the moisture that is left.',
          );
        }
        if (r.disponibilidad == DisponibilidadAgua.desconocida) {
          return _(
            'Hay necesidad estimada de agua. Confirma el suministro de hoy antes de planificar riegos.',
            'There is estimated water demand. Confirm today’s supply before planning irrigation.',
          );
        }
        if (r.disponibilidad == DisponibilidadAgua.no) {
          return _(
            'Registraste que no hay agua disponible hoy. La necesidad del cultivo sigue visible, pero no se propone aplicar un riego.',
            'You recorded no water supply today. Crop demand remains visible, but no irrigation is proposed.',
          );
        }
        if (r.avisos.contains(Aviso.areaPendiente)) {
          return _(
            'Falta un perímetro válido para repartir el volumen compartido. Dibuja o corrige el lote.',
            'A valid outline is needed to allocate shared water. Draw or correct this plot.',
          );
        }
        final mm = r.riegoSugerido.toStringAsFixed(1);
        final condicion = r.diasLluviaFaltante > 0
            ? _(
                'Si no llovió en los días sin dato: ',
                'If it did not rain on days with missing data: ',
              )
            : '';
        if (r.avisos.contains(Aviso.capacidadLimitada)) {
          return _(
            '${condicion}reparto disponible de hasta $mm mm para este lote; la necesidad es mayor. Ajusta la cantidad aplicada.',
            '${condicion}available allocation of up to $mm mm for this plot; demand is higher. Adjust the applied amount.',
          );
        }
        return _(
          '${condicion}necesidad aproximada de $mm mm. Confirma el caudal y la cantidad aplicada; las láminas por tipo de riego son supuestos.',
          '${condicion}approximate demand of $mm mm. Confirm flow and applied amount; depths per irrigation type are assumptions.',
        );
    }
  }

  String get etapa => _('Etapa', 'Stage');
  String get cosecha => _('Cosecha', 'Harvest');
  String enDias(int n) =>
      n <= 0 ? _('Ahora', 'Now') : _('En $n días', 'In $n days');
  String get dia => _('Día', 'Day');
  String get rendimiento => _('Rendimiento', 'Yield');
  String get ultimosDias => _('Últimos 14 días', 'Last 14 days');
  String get leyendaReserva =>
      _('Agua en la zona de raíces', 'Water in the root zone');
  String get lluvia => _('Lluvia', 'Rain');
  String get necesidad => _('Necesidad', 'Demand');
  String get estaSemana => _('Esta semana', 'This week');
  String mm(double v) => '${v.round()} mm';
  String diasEstres(int n) => n == 0
      ? _('Sin días de estrés', 'No stress days')
      : _(
          '$n ${n == 1 ? 'día' : 'días'} con estrés',
          '$n stress ${n == 1 ? 'day' : 'days'}',
        );
  String get porHacer => _('Por hacer', 'To do');
  String get registroSemanal => _('Registro semanal', 'Weekly log');
  String get llenarRegistro =>
      _('Llenar el registro de esta semana', 'Fill in this week’s log');

  String tituloAviso(Aviso a) => switch (a) {
    Aviso.registroPendiente => _(
      'Registro semanal pendiente',
      'Weekly log due',
    ),
    Aviso.climaViejo => _('Clima desactualizado', 'Weather out of date'),
    Aviso.plaga => _('Plaga reportada', 'Pest reported'),
    Aviso.fertilizar => _('Momento de fertilizar', 'Time to fertilize'),
    Aviso.cosechaCerca => _('Cosecha cercana', 'Harvest is near'),
    Aviso.aguaSinConfirmar => _(
      'Confirma el agua de hoy',
      'Confirm today’s water',
    ),
    Aviso.sinAgua => _('Suministro no disponible', 'Supply unavailable'),
    Aviso.lluviaFaltante => lluviaDesconocida,
    Aviso.riegoEstimado => _(
      'Riegos con cantidad o fecha estimada',
      'Irrigation with estimated amount or date',
    ),
    Aviso.capacidadLimitada => _(
      'El saldo limita el riego',
      'Remaining water limits irrigation',
    ),
    Aviso.areaPendiente => _('Perímetro pendiente', 'Outline needed'),
  };

  String detalleAviso(Aviso a) => switch (a) {
    Aviso.aguaSinConfirmar => _(
      'El sistema instalado no confirma que haya agua hoy.',
      'An installed system does not confirm water is available today.',
    ),
    Aviso.sinAgua => _(
      'La disponibilidad se guarda por fecha.',
      'Availability is recorded by date.',
    ),
    Aviso.lluviaFaltante => escenarioLluvia,
    Aviso.riegoEstimado => riegoDiarioAyuda,
    Aviso.capacidadLimitada => _(
      'El volumen se reparte entre los lotes según su necesidad; no cubre toda la demanda.',
      'Volume is shared across plots by demand; it does not cover all demand.',
    ),
    Aviso.areaPendiente => _(
      'Dibuja el contorno del lote en Finca para repartir el volumen de agua por área.',
      'Draw the plot outline in Farm to distribute water volume by area.',
    ),
    Aviso.registroPendiente => _(
      'Con él la estimación mejora cada semana.',
      'It improves the estimate every week.',
    ),
    Aviso.climaViejo => _(
      'Conéctate a wifi para actualizarlo.',
      'Connect to Wi-Fi to update it.',
    ),
    Aviso.plaga => _(
      'Revísala con un extensionista y regístrala de nuevo.',
      'Check it with an extension agent and log it again.',
    ),
    Aviso.fertilizar => _(
      'El cultivo está en desarrollo y no hay fertilización registrada.',
      'The crop is developing and no fertilizer has been logged.',
    ),
    Aviso.cosechaCerca => _(
      'Evita regar de más y vigila la lluvia.',
      'Avoid over-irrigating and watch the rain.',
    ),
  };

  String get precision => _('Calidad de datos', 'Data quality');
  String nombrePrecision(Precision p) => switch (p) {
    Precision.baja => _('Baja', 'Low'),
    Precision.media => _('Media', 'Medium'),
    Precision.alta => _('Alta', 'High'),
  };
  String get precisionAyuda => _(
    'Describe cobertura y registros; no es una exactitud medida. Baja cuando hay días o riegos estimados.',
    'Describes coverage and logs, not measured accuracy. Lower when days or irrigation are estimated.',
  );
  String get apoyaNoReemplaza => _(
    'Esta estimación apoya tu decisión; no la reemplaza.',
    'This estimate supports your decision; it does not replace it.',
  );

  // Sincronización
  String get clima => _('Clima', 'Weather');
  String get sincronizar => _('Actualizar clima', 'Update weather');
  String get sincronizando => _('Actualizando…', 'Updating…');
  String get nuncaSincronizado => _('Aún sin clima', 'No weather yet');
  String estimados(int n) => _(
    '$n ${n == 1 ? 'día estimado' : 'días estimados'}',
    '$n ${n == 1 ? 'day' : 'days'} estimated',
  );
  String get sinWifi => _(
    'Sin wifi. El clima se actualiza solo con wifi para no gastar datos.',
    'No Wi-Fi. Weather updates only over Wi-Fi to save mobile data.',
  );
  String get errorSync => _(
    'No se pudo actualizar. Se usa el clima guardado.',
    'Could not update. Using saved weather.',
  );
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
  String get sinRegistrosAyuda => _(
    'Llena uno por semana para afinar la estimación.',
    'Fill one in each week to sharpen the estimate.',
  );
  String get nuevo => _('Nuevo', 'New');
  String resumenRegistro(RegistroSemanal r) {
    final partes = <String>[
      r.riegos == 0
          ? _('Sin riego', 'No irrigation')
          : _(
              '${r.riegos} ${r.riegos == 1 ? 'riego' : 'riegos'}',
              '${r.riegos} ${r.riegos == 1 ? 'irrigation' : 'irrigations'}',
            ),
      if (r.plaga != NivelPlaga.ninguna)
        _(
          'plaga ${nombrePlaga(r.plaga).toLowerCase()}',
          '${nombrePlaga(r.plaga).toLowerCase()} pest',
        ),
      if (r.fertilizo) _('fertilizó', 'fertilized'),
    ];
    return partes.join(' · ');
  }

  // Ajustes
  String get idioma => _('Idioma', 'Language');
  String get datos => _('Datos', 'Data');
  String get metodos => _('Métodos y fuentes', 'Methods and sources');
  String get borrarDatos => _('Borrar todos los datos', 'Erase all data');
  String get borrarPregunta => _(
    'Se borrarán la parcela, la plantación, los registros y el clima guardado.',
    'The plot, planting, logs and saved weather will be erased.',
  );
  String get borrar => _('Borrar', 'Erase');
  String get borrarRegistroPregunta =>
      _('Se borrará este registro semanal.', 'This weekly log will be erased.');
  String get editar => _('Editar', 'Edit');

  // Métodos
  List<(String, String)> get metodosTexto => [
    (
      _('Agua del cultivo', 'Crop water'),
      _(
        'Se calcula la evapotranspiración de referencia con Penman-Monteith y un balance diario de agua en la zona de raíces, según el manual FAO-56. El rendimiento por agua usa el factor de FAO-33.',
        'Reference evapotranspiration is computed with Penman-Monteith and a daily root-zone water balance, following FAO-56. Water-limited yield uses the FAO-33 factor.',
      ),
    ),
    (
      _('Clima', 'Weather'),
      _(
        'Temperatura, humedad, viento, radiación y lluvia diarios de NASA POWER para el punto de la parcela. Representa una celda de unos 50 km, no la parcela exacta. La lluvia de esta fuente puede estar sobreestimada en el oriente de Guatemala.',
        'Daily temperature, humidity, wind, radiation and rain from NASA POWER for the plot location. It represents a cell of about 50 km, not the exact plot. Rain from this source may be overestimated in eastern Guatemala.',
      ),
    ),
    (
      _('Mapa de la finca', 'Farm map'),
      _(
        'El plano muestra un cuadrado centrado en el punto de la finca, con el norte arriba. El fondo viene de OpenStreetMap (mapa) o de Esri World Imagery (satélite); se descarga solo con wifi y se guarda en el teléfono. Las áreas se calculan a partir de lo que dibujas, así que son aproximadas.',
        'The plan shows a square centred on the farm location, north up. The background comes from OpenStreetMap (map) or Esri World Imagery (satellite); it downloads only over Wi-Fi and is stored on the phone. Areas are computed from what you draw, so they are approximate.',
      ),
    ),
    (
      _('Días estimados', 'Estimated days'),
      _(
        'Los huecos de ET₀ usan el promedio reciente. La lluvia faltante se conserva desconocida; el balance usa un escenario sin aporte de lluvia y lo señala.',
        'ET₀ gaps use the recent average. Missing rain remains unknown; the balance uses and labels a scenario without rainfall input.',
      ),
    ),
    (
      _('Riego', 'Irrigation'),
      _(
        'Cada riego registrado se convierte en una lámina de agua supuesta según el tipo: manual 4 mm, goteo 6 mm, aspersión 12 mm y surcos 30 mm.',
        'Each logged irrigation is converted to an assumed depth by type: by hand 4 mm, drip 6 mm, sprinkler 12 mm and furrow 30 mm.',
      ),
    ),
    (
      _('Cultivos', 'Crops'),
      _(
        'Coeficientes de cultivo, raíces y etapas de FAO-56; variedades y ciclos del ICTA para maíz y frijol.',
        'Crop coefficients, roots and stages from FAO-56; ICTA varieties and cycles for maize and beans.',
      ),
    ),
    (
      _('Límites', 'Limits'),
      _(
        'Es una estimación sin validar en campo. No considera suelos compactados, laderas ni enfermedades. Consulta a un extensionista antes de una decisión importante.',
        'This is an estimate not validated in the field. It does not account for compacted soils, slopes or diseases. Consult an extension agent before an important decision.',
      ),
    ),
  ];

  // Fechas
  static const _mesesEs = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  static const _mesesEn = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String fechaCorta(DateTime f) => en
      ? '${_mesesEn[f.month - 1]} ${f.day}'
      : '${f.day} ${_mesesEs[f.month - 1]}';

  String fechaLarga(DateTime f) => en
      ? '${_mesesEn[f.month - 1]} ${f.day}, ${f.year}'
      : '${f.day} ${_mesesEs[f.month - 1]} ${f.year}';
}
