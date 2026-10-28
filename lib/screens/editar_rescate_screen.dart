import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/sp_widgets.dart';
import '../widgets/aviso_animal_duplicado.dart';
import '../widgets/chips_seleccionables.dart';
import '../widgets/confirmar_ciudad_resuelta.dart';
import '../widgets/dialogos_eliminar_rescate.dart';
import '../widgets/elegir_foto_animal.dart';
import '../widgets/fotos.dart';
import '../widgets/tardando_mucho_mixin.dart';
import '../data/contexto_albergue.dart';
import '../data/creator_role.dart';
import '../data/rescates_repository.dart';
import '../data/rescate_fotos_repository.dart';
import '../data/foto_normalizador.dart';
import '../services/ubicacion_lifecycle.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/campo_ciudad.dart';

/// "Usar plantilla" (ver subir_rescate_screen.dart/subir_lote_screen.dart)
/// escribía el nombre del animal DENTRO del texto de la descripción, como
/// "Pacolin fue encontrado/a [...]" — a partir de ahí quedaba como texto
/// plano guardado, sin ninguna relación con el campo `nombre`. Renombrar
/// el animal después no lo tocaba, así que la descripción se quedaba con
/// el nombre viejo para siempre. La plantilla ya no repite el nombre
/// (arranca directo con "Fue encontrado/a...") — el nombre ya se ve arriba
/// en su propio campo, repetirlo ahí adentro era la única razón por la
/// que este problema podía existir. Esto migra a ese formato nuevo los
/// animales que se publicaron ANTES de ese cambio: si la descripción
/// todavía tiene el nombre pegado adelante, se lo saca. No intenta
/// reemplazar por el nombre nuevo (ya no hace falta, el nombre no vuelve a
/// escribirse ahí) — solo migra, y solo el caso SIN ambigüedad: la
/// descripción tiene que empezar exactamente con "{nombre} fue
/// encontrado/a" (nadie la reescribió a mano); cualquier otra cosa se deja
/// intacta, mejor no arriesgar un recorte equivocado en medio de una frase
/// real. Hallazgo real de Eliza: editó "lino" (antes "Hermoso") y la
/// descripción seguía "Hermoso fue encontrado/a...".
String descripcionSinNombreDePlantillaVieja({
  required String descripcion,
  required String nombreOriginal,
}) {
  if (nombreOriginal.isEmpty) return descripcion;
  final prefijoViejo = '$nombreOriginal fue encontrado/a';
  if (!descripcion.startsWith(prefijoViejo)) return descripcion;
  return 'Fue encontrado/a${descripcion.substring(prefijoViejo.length)}';
}

/// ¿Hay que ir al mapa a resolver la ciudad que quedó escrita?
///
/// Es la decisión que gobierna cuándo aparece la lista de ciudades. Vale la
/// pena tenerla aparte y probada porque los dos errores posibles duelen de
/// formas distintas:
///
///  · resolver de más pisa lo que la persona escribió (se siente como
///    "siempre me lo reemplaza");
///  · resolver de menos deja guardar un texto que el mapa nunca confirmó,
///    y entonces el animalito dice una ciudad y aparece en otra.
///
/// [tocadaAMano] viene del listener del campo: si la persona no lo tocó, no
/// hay nada nuevo que verificar. Un campo VACÍO tampoco se resuelve: hay
/// animalitos sin ubicación y borrarla tiene que poder hacerse.
bool hayQueResolverCiudad({required String texto, required String original}) {
  final limpio = texto.trim();
  if (limpio.isEmpty) return false;
  // Ya es la que estaba guardada: el mapa ya la confirmó en su momento.
  return limpio != original.trim();
}

class EditarRescateScreen extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  const EditarRescateScreen({
    super.key,
    required this.docId,
    required this.data,
  });
  @override
  State<EditarRescateScreen> createState() => _EditarRescateScreenState();
}

class _EditarRescateScreenState extends State<EditarRescateScreen>
    with
        TardandoMuchoMixin,
        WidgetsBindingObserver,
        ReintentoUbicacionTrasAjustes {
  late TextEditingController _nombreCtl;
  late TextEditingController _descCtl;
  late TextEditingController _lugarCtl;

  /// La ciudad se resuelve al SALIR del campo, no al guardar.
  ///
  /// Antes la lista de ciudades aparecía recién al tocar "Guardar", así que
  /// elegir una de la lista era, sin que se notara, aceptar el guardado
  /// entero: la pantalla se cerraba y volvías a Mis rescates. Vos creías
  /// que estabas eligiendo una ciudad, no confirmando todo. Hallazgo real
  /// de Eliza editando un animalito en Medellín.
  ///
  /// Ahora se resuelve cuando dejás el campo: ves en pantalla qué ciudad
  /// quedó, la podés volver a cambiar, y Guardar guarda lo que estás
  /// viendo. Importa especialmente acá porque el mapa a veces devuelve el
  /// barrio en vez de la ciudad, y sin verlo antes te enterás demasiado
  /// tarde.
  final _lugarFocus = FocusNode();

  /// Para dispararle la detección al campo desde acá (el reintento al
  /// volver de los Ajustes). Ver CampoCiudadControlador.
  final _ciudadCtrl = CampoCiudadControlador();

  /// Evita que se abra la lista dos veces a la vez: el foco se pierde
  /// también al tocar "Guardar", así que sin esto ese toque podía disparar
  /// una segunda resolución encima de la que ya estaba corriendo.
  bool _resolviendoCiudad = false;
  // El texto que estaba en el campo la última vez que quedó sincronizado
  // con _latitud/_longitud — arranca con lo que el animal ya tenía
  // guardado, y se actualiza cada vez que el GPS o el geocodificador
  // dejan texto y coordenadas consistentes entre sí de nuevo. Es a donde
  // se vuelve si la persona cancela la confirmación de una ciudad nueva
  // (ver _guardar): revertir el texto SIN tocar lat/lng los deja
  // consistentes entre sí, en vez de dejar el campo con un texto sin
  // confirmar que vuelve a disparar el mismo diálogo en cada intento de
  // guardar. Mismo patrón que _lugarSincronizado en subir_rescate_screen.dart.
  late String _lugarOriginal;
  late String _especie;
  late String _estado;
  late String _urgencia;
  late String _energia;
  late String _tamano;
  late String _edad;
  late String _genero;
  late String _okNinos;
  late String _okMascotas;
  late String _requiereExp;
  late String _vacunado;
  late String _desparasitado;
  bool _guardando = false;
  String? _fotoUrlExistente;
  String? _foto2UrlExistente;
  XFile? _nuevaFoto;
  XFile? _nuevaFoto2;

  // Publicar un rescate nuevo (subir_rescate_screen.dart) ya exige al
  // menos una foto, pero acá al editar se podía quitar la única que tenía
  // y guardar igual — el animal quedaba sin ninguna foto para siempre
  // (sugerencia real de Eliza: la foto debería ser requerida, no opcional,
  // en todos los flujos, no solo al publicar por primera vez).
  bool get _tieneAlMenosUnaFoto =>
      _nuevaFoto != null ||
      _fotoUrlExistente != null ||
      _nuevaFoto2 != null ||
      _foto2UrlExistente != null;

  // A diferencia de subir_rescate_screen.dart, acá la detección es manual
  // (no arranca sola en initState) — este flag evita que el reintento
  // automático al volver de Ajustes dispare un pedido de ubicación que la
  // persona nunca inició, si solo estaba editando otro campo y volvió de
  // background por cualquier otro motivo.
  bool _sePidioUbicacion = false;
  double? _latitud;
  double? _longitud;
  String _paisCodigo = '';

  // Del repositorio, no declaradas acá — ver el comentario en
  // RescatesRepository. La lista de estados de ESTA pantalla era la que
  // estaba incompleta: le faltaban 'Herido' y 'Crítico', que sí se pueden
  // elegir al publicar, así que esos animales se abrían acá sin ningún
  // estado marcado y tocar otra opción pisaba el valor real.
  static const _especies = RescatesRepository.especies;
  static const _estados = RescatesRepository.estados;
  static const _urgencias = RescatesRepository.urgencias;
  static const _energias = RescatesRepository.energias;
  static const _tamanos = RescatesRepository.tamanos;
  static const _edades = RescatesRepository.edades;
  static const _generos = RescatesRepository.generos;
  static const _siNo = RescatesRepository.siNo;
  static const _saludOpts = RescatesRepository.salud;

  // Un animal de albergue hereda ciudad/coordenadas del PERFIL del
  // albergue al publicarse (subir_rescate_screen.dart:_cargarCiudadAlbergue)
  // — por eso esa pantalla ni siquiera muestra el campo de Ubicación al
  // publicar. Acá al editar sí se mostraba, siempre, para cualquier
  // animal — dejaba tocar a mano un dato que en realidad vive en el
  // perfil, animal por animal, en vez de en un solo lugar. Pedido real de
  // Eliza: para cambiar la ciudad de los animales de un albergue, se edita
  // el perfil del albergue, no cada animal suyo.
  late final bool _esDeAlbergue;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _esDeAlbergue = esRescateDeAlbergue(d);
    _nombreCtl = TextEditingController(text: d['nombre'] ?? '');
    _descCtl = TextEditingController(text: d['descripcion'] ?? '');
    _lugarOriginal = d['ubicacion'] ?? '';
    _lugarCtl = TextEditingController(text: _lugarOriginal);
    _especie = d['especie'] ?? 'Perro';
    _estado = d['estado'] ?? 'Sano';
    _urgencia = d['urgencia'] ?? 'Media';
    _energia = d['energia'] ?? 'Tranquilo';
    _tamano = d['tamano'] ?? 'Mediano';
    _edad = d['edad'] ?? 'Cachorro';
    _genero = d['genero'] ?? 'No sé';
    // ?? true, no ?? false: en compatibilidad.dart y en el resto de la app,
    // un animal sin este campo (publicado antes de que existiera) se
    // asume apto con niños/mascotas por defecto. Acá abajo era el único
    // lugar que asumía lo contrario — un animal viejo se abría en Editar
    // mostrando "No" sin que nadie lo hubiera dicho nunca, y si el
    // rescatista/albergue guardaba sin darse cuenta (ej. solo cambió la
    // descripción), quedaba "No" escrito de verdad para siempre, bajando
    // su puntaje de compatibilidad sin motivo real (hallazgo de auditoría
    // de código). requiereExperiencia sí se queda en ?? false — ese
    // default ya es el mismo en toda la app.
    _okNinos = (d['okConNinos'] as bool? ?? true) ? 'Sí' : 'No';
    _okMascotas = (d['okConMascotas'] as bool? ?? true) ? 'Sí' : 'No';
    _requiereExp = (d['requiereExperiencia'] as bool? ?? false) ? 'Sí' : 'No';
    // String, no bool — y con fallback a 'Aún no lo sé' para animales
    // publicados antes de que existiera este campo, no a 'No' (que
    // afirmaría algo que no se sabe).
    _vacunado = d['vacunado'] as String? ?? 'Aún no lo sé';
    _desparasitado = d['desparasitado'] as String? ?? 'Aún no lo sé';
    _fotoUrlExistente = d['fotoUrl'] as String?;
    _foto2UrlExistente = d['fotoUrl2'] as String?;
    // num→toDouble y no "as double": si algún doc trae la coordenada como
    // entero (dato legado o escrito a mano), un cast estricto tira una
    // excepción en initState y rompe la pantalla de editar completa.
    _latitud = (d['latitud'] as num?)?.toDouble();
    _longitud = (d['longitud'] as num?)?.toDouble();
    _paisCodigo = d['paisCodigo'] as String? ?? '';
    // Qué cuenta como "ciudad sin confirmar" lo decide _ciudadSinConfirmar,
    // comparando el texto con _lugarOriginal. Ver su doc: antes esto era una
    // bandera que prendía un listener del campo, y se reencendía sola
    // después de cerrarse el diálogo.
    _lugarFocus.addListener(() {
      if (!_lugarFocus.hasFocus) _resolverCiudadAlSalir();
    });
  }

  /// ¿El texto de ciudad dice algo que el mapa todavía no confirmó?
  ///
  /// **Por qué es una comparación y no una bandera.** Acá vivía
  /// `_ubicacionTocadaAMano`, un bool que prendía el listener de _lugarCtl al
  /// escribir y que cada camino apagaba a mano después de resolver. Se veía
  /// correcto y no lo era: al cerrarse el diálogo el foco vuelve al campo, el
  /// controller notifica otra vez y la bandera se reencendía DESPUÉS del
  /// reset. El siguiente Guardar volvía a preguntar la ciudad, la resolvías,
  /// y otra vez. Bucle sin salida que reportó Eliza:
  /// "selecciono la ciudad, veo Tocá Guardar para confirmar, toco guardar y
  /// me muestra de nuevo cuál es tu ciudad".
  ///
  /// Lo reproduje en el emulador: con el primer intento de arreglo (que le
  /// tapaba la boca al camino del foco) el bucle seguía igual. La bandera no
  /// se podía sincronizar con quien la prendía.
  ///
  /// Esto no tiene ese problema porque no hay nada que sincronizar:
  /// [_lugarOriginal] es la última ciudad que el mapa confirmó, y si el texto
  /// coincide, no hay nada que preguntar. Nadie puede reencenderlo por
  /// detrás.
  bool get _ciudadSinConfirmar =>
      _lugarCtl.text.trim() != _lugarOriginal.trim();

  // El reintento (una sola vez, solo tras volver de Ajustes) vive en
  // ReintentoUbicacionTrasAjustes — mismo motivo (y mismo bucle infinito
  // ya corregido) que subir_rescate_screen.dart. Ver ese archivo para el
  // hallazgo completo.
  @override
  bool get yaTieneUbicacion => !_sePidioUbicacion || _latitud != null;
  @override
  bool get detectandoUbicacion => _ciudadCtrl.detectando;
  @override
  void reintentarConPermiso() => _ciudadCtrl.detectar();

  /// Toda la secuencia de servicio/permiso/GPS/geocoding vive en
  /// UbicacionService; acá queda solo la UI propia de esta pantalla.

  // Mismo motivo que subir_rescate_screen.dart: un SnackBar como "Activa el
  // GPS en tu dispositivo" (8s) queda visible sobre la pantalla de ATRÁS si
  // se vuelve antes de que se cierre solo, porque MaterialApp comparte un
  // solo ScaffoldMessenger para toda la app. Capturado acá (no directo en
  // dispose) porque ScaffoldMessenger.of(context) necesita un context
  // todavía válido en el árbol.
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  /// Resuelve contra el mapa la ciudad que se acaba de escribir, al salir
  /// del campo. Ver el doc de [_lugarFocus] para el porqué de que sea acá y
  /// no al guardar.
  ///
  /// Si se cancela la lista, el texto vuelve al que el animalito YA tenía
  /// guardado, no al que se tecleó: un texto sin verificar no puede quedar
  /// en pantalla como si fuera válido, porque después Guardar lo tomaría
  /// por bueno. Mismo criterio que tenía el guardado antes.
  Future<void> _resolverCiudadAlSalir() async {
    if (_resolviendoCiudad) return;
    final texto = _lugarCtl.text.trim();
    if (!hayQueResolverCiudad(texto: texto, original: _lugarOriginal)) return;
    setState(() => _resolviendoCiudad = true);
    try {
      final elegida = await resolverCiudadEscrita(context, texto);
      if (!mounted) return;
      setState(() {
        if (elegida == null) {
          // Se deja lo tecleado tal cual, a propósito. Acá `null` significa
          // tres cosas distintas —no existe ese lugar, no hubo señal, o
          // cerró el diálogo sin elegir— y en las tres borrar el texto es
          // perder trabajo de alguien que solo movió el foco de campo.
          //
          // Era contradictorio además: el aviso dice "revisá cómo la
          // escribiste" y acto seguido se borraba lo que había que revisar,
          // dejando de nuevo el nombre viejo. Así se veía "no me deja poner
          // Medellín, siempre me lo reemplaza por Los Olivos" — hallazgo
          // real de Eliza. Lo tecleado queda, ella corrige una letra en vez
          // de escribir todo otra vez.
          //
          // No se pierde la red de seguridad: el texto sigue difiriendo de
          // _lugarOriginal, así que _ciudadSinConfirmar sigue dando true y
          // Guardar vuelve a resolver antes de escribir nada. Las
          // coordenadas siguen siendo las del lugar viejo hasta que alguna
          // resolución termine bien. Nunca se guarda un texto sin confirmar.
        } else {
          // Los tres datos del MISMO candidato, siempre — ver el
          // invariante en confirmar_ciudad_resuelta.dart. El nombre es el
          // que resolvió el mapa, nunca el texto tecleado: si alguien
          // escribió "Córdoba, Argentina" para desambiguar de Córdoba,
          // España, se guarda "Córdoba" y el país sale de la bandera 🇦🇷, no
          // repetido en el texto. paisCodigo se asigna aunque venga vacío:
          // pertenece al lugar nuevo, y conservar el del lugar viejo sería
          // justamente la mezcla que este invariante prohíbe.
          _latitud = elegida.lat;
          _longitud = elegida.lng;
          _lugarCtl.text = elegida.ciudadResuelta;
          _paisCodigo = elegida.paisCodigo;
          _lugarOriginal = _lugarCtl.text;
          // Solo se apaga cuando el mapa CONFIRMÓ el lugar. Si quedó texto
          // sin resolver, la marca sigue prendida para que Guardar lo
          // vuelva a intentar: es lo que impide que un nombre sin confirmar
          // llegue a Firestore con las coordenadas del lugar anterior.
        }
        _resolviendoCiudad = false;
      });
    } catch (_) {
      // Sin señal o el mapa no contesta: se deja lo que había, sin
      // bloquear. Guardar volverá a intentarlo, que es el respaldo.
      if (mounted) setState(() => _resolviendoCiudad = false);
    } finally {
      // Si salió por !mounted, el setState de arriba no corrió.
      _resolviendoCiudad = false;
    }
  }

  @override
  void dispose() {
    // El removeObserver de WidgetsBindingObserver ahora lo hace
    // ReintentoUbicacionTrasAjustes.dispose(), alcanzado por el
    // super.dispose() de acá abajo.
    _scaffoldMessenger?.clearSnackBars();
    _nombreCtl.dispose();
    _descCtl.dispose();
    _lugarCtl.dispose();
    _lugarFocus.dispose();
    super.dispose();
  }

  /// elegirFotoAnimal (widgets/elegir_foto_animal.dart) muestra la hoja y hace el pickImage.
  /// Antes esta pantalla tenía su propia copia de las dos cosas, y esa
  /// copia NO envolvía la cámara en un try/catch (la de publicar sí): en
  /// un dispositivo sin cámara, con el permiso denegado, o un emulador sin
  /// cámara configurada, tocar "Tomar foto" acá lanzaba una excepción que
  /// nadie atrapaba y no pasaba nada, sin ningún aviso. Hallazgo de
  /// auditoría de código.
  Future<void> _mostrarOpcionesFoto(int slot) async {
    final img = await elegirFotoAnimal(context);
    if (img == null || !mounted) return;
    setState(() {
      if (slot == 1) {
        _nuevaFoto = img;
      } else {
        _nuevaFoto2 = img;
      }
    });
  }

  // Guard de reentrada — mismo motivo que en mis_rescates_screen.dart: el
  // chequeo de solicitudes pendientes tarda un momento sin mostrar nada, y
  // un segundo toque a "Eliminar publicación" en esa ventana apilaba dos
  // diálogos de confirmación (uno seguía preguntando por un animal que el
  // otro ya había borrado).
  bool _eliminando = false;

  /// Dueño del animal: el albergue si es del albergue (el de la
  /// responsable en modo equipo), si no la cuenta propia.
  late final String _dueno = uidDueno(esAlbergue: esRescateDeAlbergue(widget.data));

  /// Modo equipo (fase 2): solo borra lo que cargó esta persona.
  late final ContextoAlbergue? _equipo = esRescateDeAlbergue(widget.data) ? SesionEquipo.actual.value : null;
  bool get _puedeBorrar => _equipo == null || widget.data['autorUid'] == _equipo.autorUid;

  /// "Cargado por Ana", solo del lado del albergue.
  late final String? _cargadoPor = esRescateDeAlbergue(widget.data) ? ContextoAlbergue.autorDe(widget.data) : null;

  Future<void> _eliminar() async {
    // Silencioso a propósito (el aviso de "hay una eliminación en curso"
    // que hubo acá un tiempo generaba confusión y se quitó — ver la
    // historia completa del guard en mis_rescates_screen.dart). Esta
    // pantalla es de UN solo animal, así que el guard solo puede frenar
    // el doble toque sobre ese mismo animal — y ese caso no necesita
    // aviso: el primer toque ya está mostrando el diálogo de confirmación
    // o el "Eliminando a…" un instante después.
    if (_eliminando) return;
    _eliminando = true;
    try {
      await _eliminarImpl();
    } finally {
      _eliminando = false;
    }
  }

  Future<void> _eliminarImpl() async {
    // nombreDeAnimal, no un texto propio: acá había una OCTAVA variante
    // del mismo relleno ('este animal'), distinta de las otras siete.
    final nombre = nombreDeAnimal(_nombreCtl.text, enFrase: true);

    // Los 3 chequeos de elegibilidad viven centralizados en
    // RescatesRepository.bloqueoParaEliminar — antes estaban duplicados
    // acá y en mis_rescates_screen.dart (hallazgo de auditoría de código).
    // Sin este bloqueo, aprobar una solicitud después revienta contra un
    // rescate que ya no existe (tx.update de aprobarSiDisponible tira
    // invalid-argument) — el bug real que reportó Eliza.
    (String, String)? bloqueo;
    try {
      bloqueo = await RescatesRepository().bloqueoParaEliminar(
        rescateId: widget.docId,
        nombre: nombre,
        rescatistaId: _dueno,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No pudimos verificar si se puede eliminar. Revisá tu conexión e intentá de nuevo.',
          ),
          backgroundColor: context.sp.msgError,
        ),
      );
      return;
    }
    if (!mounted) return;
    if (bloqueo != null) {
      await mostrarBloqueoEliminarRescate(context, bloqueo);
      return;
    }

    final confirmar = await confirmarEliminarRescate(context, nombre);
    if (!confirmar || !mounted) return;
    setState(() => _guardando = true);
    // Mismo feedback persistente que en mis_rescates_screen.dart: sin
    // señal hay hasta ~20s de timeouts encadenados, y el spinner de
    // _guardando (pensado para el botón de guardar) no le dice a nadie
    // que hay un BORRADO en curso. Los desenlaces lo reemplazan con
    // hideCurrentSnackBar antes de mostrarse.
    //
    // hideCurrentSnackBar TAMBIÉN acá (no solo en los desenlaces): los
    // SnackBar se ENCOLAN, no se pisan — sin esto, un aviso de error de un
    // guardado anterior en esta misma pantalla se quedaría en la cola y
    // este "Eliminando a…" esperaría a que termine su duración antes de
    // mostrarse. Mismo arreglo que ya tenía mis_rescates_screen.dart,
    // hallazgo de auditoría de código: esta copia nunca lo recibió.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Eliminando a $nombre…'),
          duration: const Duration(seconds: 30),
        ),
      );
    try {
      // Fotos ANTES que el documento, a propósito: storage.rules verifica
      // el dueño de una foto leyendo el documento de rescates — con el doc
      // ya borrado, esa lectura falla y el borrado de fotos era rechazado
      // en silencio: cada animal eliminado dejaba sus fotos huérfanas
      // pagando almacenamiento para siempre. Best-effort igual (try/catch,
      // no .catchError — un catchError mal tipado revienta acá y el flujo
      // muere en silencio antes del SnackBar).
      try {
        await RescateFotosRepository()
            .eliminarTodas(widget.docId)
            .timeout(const Duration(seconds: 10));
      } catch (_) {}
      // Con timeout: sin señal, .delete() se encola y su Future no
      // resuelve hasta reconectar — sin límite, la pantalla quedaba con el
      // spinner para siempre. El TimeoutException cae al catch de abajo,
      // que para ese caso muestra el mensaje honesto ("se va a completar
      // al volver la señal") — el borrado encolado SÍ se aplica solo.
      await RescatesRepository()
          .eliminar(widget.docId)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Publicación eliminada'),
            backgroundColor: context.sp.msgExito,
          ),
        );
      Navigator.pop(context);
    } on TimeoutException {
      // Timeout ≠ error: el borrado quedó encolado y se completa solo al
      // reconectar (y la Cloud Function onRescateEliminado limpia fotos y
      // favoritos en el servidor cuando eso pase). El animal ya
      // desapareció de las listas, así que para la persona esto ES un
      // borrado exitoso — mismo mensaje y misma salida que el camino con
      // señal. Acá hubo un tiempo un aviso naranja de "está tardando" y
      // generaba confusión (ver mis_rescates_screen.dart).
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Publicación eliminada'),
            backgroundColor: context.sp.msgExito,
          ),
        );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(RescatesRepository.mensajeErrorEliminar(e)),
            backgroundColor: context.sp.msgError,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Resuelve un slot de foto comparando estado inicial vs. final: foto
  /// nueva → subirla (sobreescribe el mismo path); sin cambios → mantener
  /// la URL que ya había, sin tocar Storage; se quitó sin reemplazarla →
  /// borrarla de Storage para no dejarla huérfana pagando almacenamiento.
  /// False si hay que cortar el guardado (había un duplicado y decidió no
  /// seguir). True si se puede guardar, sea porque no hay duplicado o porque
  /// dijo que son dos animales distintos con el mismo nombre.
  ///
  /// `excluyendoId` es imprescindible: sin él, este animal se encontraría a
  /// sí mismo y CUALQUIER guardado avisaría "ya tenés otro llamado así",
  /// incluso sin haber tocado el nombre.
  Future<bool> _pasaElChequeoDeDuplicado() async {
    final nombre = _nombreCtl.text.trim();
    if (nombre.isEmpty) return true;
    final duplicado = await RescatesRepository().buscarDuplicado(
      uid: _dueno,
      nombre: nombre,
      role: creatorRoleFromFirestore(widget.data['creadoPor'] as String?),
      especie: _especie,
      excluyendoId: widget.docId,
    );
    if (!mounted) return false;
    if (duplicado == null) return true;
    final accion = await avisarAnimalDuplicado(
      context,
      nombre: nombre,
      especie: _especie,
      etiquetaSeguir: 'Guardar igual',
    );
    if (!mounted) return false;
    if (accion == AccionDuplicado.verFicha) {
      setState(() => _guardando = false);
      context.push(
        AppRoutes.editarRescate,
        extra: (docId: duplicado.id, data: duplicado.data()),
      );
      return false;
    }
    if (accion != AccionDuplicado.seguir) {
      setState(() => _guardando = false);
      return false;
    }
    return true;
  }

  Future<void> _guardar() async {
    if (!_tieneAlMenosUnaFoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'El animal necesita al menos una foto. Agregá una antes de guardar.',
          ),
          backgroundColor: context.sp.msgError,
        ),
      );
      return;
    }
    setState(() {
      _guardando = true;
    });
    // El mismo aviso que al publicar. Antes esta pantalla no lo hacía, así
    // que renombrar un animal para que coincidiera con otro dejaba el
    // duplicado sin que nadie dijera nada — la validación cubría la puerta
    // de entrada y no la de al lado. Pregunta de Eliza.
    //
    // El spinner ya está prendido a propósito (mismo criterio que al
    // publicar): esto es una consulta de red y sin spinner el botón parece
    // muerto mientras corre.
    if (!await _pasaElChequeoDeDuplicado()) return;
    iniciarTimerTardando(const Duration(seconds: 8));
    try {
      // _ciudadSinConfirmar: si el texto dice algo distinto de la última
      // ciudad que el mapa confirmó (la carga inicial, o el último GPS), las
      // coordenadas guardadas ya no corresponden a lo que dice el texto.
      // Guardarlas así dejaría al feed de adopción calculando distancia con
      // datos viejos. Acá se resuelve el texto contra un geocodificador
      // real — de paso valida que sea un lugar que existe, no cualquier
      // cosa escrita.
      //
      // `&& _lugarCtl.text.trim().isNotEmpty` — le faltaba (subir_rescate_
      // screen.dart sí lo tenía). Sin esto, tocar el campo y dejarlo vacío
      // (la ubicación siempre fue opcional) igual mandaba geocodificar un
      // texto VACÍO — y lo que sea que tirara eso caía en el mensaje
      // genérico de "revisá tu conexión", sin ninguna relación real con el
      // GPS ni la red. Hallazgo real de Eliza editando un animal sin
      // ciudad: el guardado quedaba bloqueado por un campo que nunca debió
      // bloquear nada.
      // La carrera al revés: tocar Guardar puede apagar el foco del campo
      // ANTES de llegar acá, con lo cual _resolverCiudadAlSalir() ya está
      // preguntando por la ciudad. Apilarle un segundo diálogo idéntico es
      // el mismo bucle por la otra puerta. Se deja que termine el que ya
      // está, y el siguiente toque de Guardar encuentra la ciudad resuelta.
      if (_resolviendoCiudad) {
        cancelarTimerTardando();
        if (mounted) setState(() => _guardando = false);
        return;
      }
      if (_ciudadSinConfirmar && _lugarCtl.text.trim().isNotEmpty) {
        // UbicacionService.desdeTexto es la única fuente de "¿esto es un
        // lugar real?" para toda la app — antes acá CUALQUIER excepción
        // (incluida la falta de señal) se trataba exactamente igual que
        // "no es un lugar real", así que sin conexión no se podía guardar
        // NINGÚN cambio de esta pantalla, aunque el texto escrito fuera
        // una ciudad perfectamente válida. Ahora se distingue: "no
        // encontrado" bloquea con un mensaje claro de que no es un lugar,
        // cualquier otro error (sin señal, timeout) bloquea igual — sigue
        // sin poder guardarse un cambio de ubicación sin poder verificarlo,
        // ver el comentario de más arriba sobre por qué esto bloquea en
        // vez de guardar con coordenadas viejas — pero con un mensaje que
        // no confunde "no hay señal" con "eso no es una ciudad".
        // Misma función compartida que las otras 3 pantallas que piden una
        // ciudad — ver el comentario de resolverCiudadEscrita(). Antes acá
        // vivía una copia a mano de esta secuencia.
        // ── Por qué esta bandera se prende ACÁ ─────────────────────────
        //
        // Abrir un diálogo le quita el foco al campo de texto que quedó
        // abajo. Eso dispara el listener de _lugarFocus, que llama a
        // _resolverCiudadAlSalir(), que abre un SEGUNDO diálogo pidiendo la
        // misma ciudad. Contestabas uno, aparecía el otro, y no se podía
        // guardar nunca. Bucle real que reportó Eliza: "selecciono la
        // ciudad, veo Tocá Guardar para confirmar, toco guardar y me
        // muestra de nuevo cuál es tu ciudad".
        //
        // Los dos caminos resuelven la ciudad y no se conocían entre sí.
        // _resolverCiudadAlSalir() ya arrancaba con `if (_resolviendoCiudad)
        // return;`, o sea que la defensa existía: lo que faltaba era que
        // ESTE camino la levantara también. Hay un test que comprueba que
        // abrir un diálogo apaga el foco (dialogo_roba_el_foco_test.dart);
        // el día que eso deje de pasar, esta bandera deja de hacer falta.
        _resolviendoCiudad = true;
        // Sin try/finally a propósito: resolverCiudadEscrita() atrapa todo
        // adentro y devuelve null en vez de lanzar (ver su doc), así que no
        // hay camino por el que la bandera quede prendida. Envolverlo
        // rompía además la promoción de tipo del `elegida == null` de abajo.
        final elegida = await resolverCiudadEscrita(
          context,
          _lugarCtl.text.trim(),
        );
        _resolviendoCiudad = false;
        // null = canceló ("No, corregir"), o no se pudo verificar
        // (resolverCiudadEscrita ya explicó por qué). Ninguno de los dos
        // debe dejar a la persona TRABADA sin forma de guardar nada — se
        // vuelve al texto que el animal YA tenía guardado (no al que se
        // tecleó, que quedó sin confirmar) y se corta ACÁ, sin tocar
        // Firestore ni salir de la pantalla. Antes seguía derecho a guardar
        // el resto de los cambios y cerraba la pantalla igual — así que
        // tocar "No, corregir" (que suena a "dejame corregir eso") te
        // sacaba igual a Mis rescates, sin darte la chance de reintentar
        // la ciudad ni de revisar qué se guardó. Hallazgo real de Eliza
        // editando un animal, escribiendo "mora": tocó "No, corregir" y la
        // pantalla se cerró sola. Ahora, si de verdad no querés resolver la
        // ciudad, un segundo toque de "Guardar" sin volver a tocar ese
        // campo guarda el resto igual (el texto ya quedó revertido a uno
        // válido) — se sigue pudiendo salir del paso sin quedar en bucle,
        // solo que ya no de forma silenciosa en el mismo toque.
        if (elegida == null) {
          _lugarCtl.text = _lugarOriginal;
          cancelarTimerTardando();
          if (mounted) setState(() => _guardando = false);
          return;
        }
        // Elegir una ciudad NO es aceptar el guardado. Se llenan los datos,
        // se corta acá, y la pantalla queda abierta para que se vea qué
        // quedó antes de confirmar. Antes seguía derecho a guardar y
        // cerraba: elegir de la lista te sacaba a Mis rescates sin haber
        // pedido nunca guardar. Hallazgo real de Eliza en Medellín.
        //
        // Este camino es el RESPALDO: normalmente la ciudad ya se resolvió
        // al salir del campo (ver _resolverCiudadAlSalir) y acá no se
        // pregunta nada. Solo entra si el foco nunca se perdió, por ejemplo
        // si se toca Guardar con el teclado todavía abierto.
        if (mounted) {
          setState(() {
            _latitud = elegida.lat;
            _longitud = elegida.lng;
            _lugarCtl.text = elegida.ciudadResuelta;
            _paisCodigo = elegida.paisCodigo;
            _lugarOriginal = _lugarCtl.text;
            _guardando = false;
          });
          cancelarTimerTardando();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: context.sp.msgAdvertencia,
              content: Text(
                'Ubicación: ${elegida.ciudadResuelta}. '
                'Tocá Guardar para confirmar los cambios.',
              ),
            ),
          );
        }
        return;
      }
      // normalizarFoto corre en su propio isolate (recorte a 1000px, JPEG
      // q80, corrige orientación) — igual que al publicar. Las dos en
      // paralelo, cada una solo si hay foto nueva para ese slot.
      final bytes = await Future.wait([
        _nuevaFoto != null
            ? normalizarFoto(_nuevaFoto!.path)
            : Future<Uint8List?>.value(),
        _nuevaFoto2 != null
            ? normalizarFoto(_nuevaFoto2!.path)
            : Future<Uint8List?>.value(),
      ]);
      // Toda la coreografía de Storage (subir, conservar, promocionar la
      // foto 2 al lugar de la 1, borrar lo que dejó de referenciarse) vive
      // en RescatesRepository.resolverFotosAlEditar — la contraparte de
      // publicarConFotos, que ya estaba en el repositorio. Antes esto era
      // ~90 líneas acá adentro, o sea la parte que BORRA y MUEVE archivos
      // sin ningún test posible. Ver su doc para las 3 reglas que la
      // gobiernan.
      final fotos = await RescatesRepository().resolverFotosAlEditar(
        rescateId: widget.docId,
        nuevaFoto1: bytes[0],
        nuevaFoto2: bytes[1],
        urlExistente1: _fotoUrlExistente,
        urlExistente2: _foto2UrlExistente,
      );
      final fotoUrl = fotos.fotoUrl;
      final fotoUrl2 = fotos.fotoUrl2;

      // Sin timeout a propósito, a diferencia de todo lo demás en esta
      // función: un `.update()` de Firestore sin señal NO se pierde — el
      // SDK lo encola solo y lo aplica apenas vuelva la conexión (esto es
      // justo lo que pasó probando en modo avión: el cambio terminó
      // guardándose al recuperar señal). Cortarlo con un timeout y avisar
      // "no se pudo guardar" sería mentirle a la persona — el cambio SÍ se
      // va a guardar. `guardadoConfirmado` distingue si ya llegó la
      // confirmación del servidor o si sigue en cola, para avisar la
      // verdad en cada caso — pero en los dos se libera la pantalla, que
      // es el problema real que reportó Eliza (spinner sin salida).
      var guardadoConfirmado = true;
      try {
        await RescatesRepository()
            .actualizar(widget.docId, {
              'nombre': _nombreCtl.text.trim(),
              'descripcion': descripcionSinNombreDePlantillaVieja(
                descripcion: _descCtl.text.trim(),
                nombreOriginal:
                    (widget.data['nombre'] as String?)?.trim() ?? '',
              ),
              'especie': _especie,
              'estado': _estado,
              'urgencia': _urgencia,
              'energia': _energia,
              'tamano': _tamano,
              'edad': _edad,
              'genero': _genero,
              'okConNinos': _okNinos == 'Sí',
              'okConMascotas': _okMascotas == 'Sí',
              'requiereExperiencia': _requiereExp == 'Sí',
              'vacunado': _vacunado,
              'desparasitado': _desparasitado,
              'fotoUrl': fotoUrl ?? FieldValue.delete(),
              'fotoUrl2': fotoUrl2 ?? FieldValue.delete(),
              // Un animal de albergue NUNCA manda estos 4 campos desde
              // ACÁ — su ubicación es siempre la del perfil del albergue
              // (la propaga el trigger onPerfilActualizado, ver
              // functions/propagar_copias.js), y esta pantalla ni siquiera le muestra el campo
              // para tocarla (_esDeAlbergue arriba). Sin este chequeo,
              // _lugarCtl/_latitud/_longitud/_paisCodigo — cargados UNA
              // vez al abrir la pantalla, nunca actualizados después —
              // se reescribían en cada guardado con lo que sea que
              // tuvieran en ese momento, pisando cualquier sincronización
              // más reciente del perfil. Hallazgo real de Eliza: cambió
              // la ciudad del albergue a Santiago de los Caballeros
              // (confirmado guardado), después editó nombre/descripción
              // de un animal de ese albergue, y el feed volvió a mostrar
              // Montería — el guardado del animal la pisó de vuelta.
              if (!_esDeAlbergue)
                ...ubicacionParaGuardar(
                  ciudad: _lugarCtl.text,
                  latitud: _latitud,
                  longitud: _longitud,
                  paisCodigo: _paisCodigo,
                ),
            })
            .timeout(const Duration(seconds: 20));
      } on TimeoutException {
        guardadoConfirmado = false;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            guardadoConfirmado
                ? '¡Cambios guardados!'
                : 'Esto está tardando. Tu cambio se va a guardar solo apenas vuelva la señal.',
          ),
          backgroundColor: guardadoConfirmado
              ? context.sp.msgExito
              : context.sp.msgAdvertencia,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: guardadoConfirmado ? 4 : 6),
        ),
      );
      Navigator.pop(context);
    } catch (_) {
      // Acá sí es una falla real de verdad (subir/borrar una foto en
      // Storage, que a diferencia de Firestore no se reintenta solo sin
      // señal) — mismo estilo y comportamiento que
      // subir_rescate_screen.dart/subir_lote_screen.dart.
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No se pudo guardar. Revisá tu conexión e intentá de nuevo.',
          ),
          backgroundColor: context.sp.msgError,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      cancelarTimerTardando();
      if (mounted)
        setState(() {
          _guardando = false;
          tardandoMucho = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    // Gemela de "Subir uno" (subir_rescate_screen.dart): mismas secciones,
    // mismas tarjetas y el mismo botón verde abajo (pedido de Eliza).
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: SpPawBackground()),
          SafeArea(
            child: Column(
              children: [
                // Volver apagado mientras se guarda, mismo motivo que en
                // Subir uno: salir a mitad de camino hacía creer que no se
                // había guardado.
                SpScreenHeader(
                  title: 'Editar animal',
                  subtitle: 'Cambia lo que necesites y guarda',
                  onBack: _guardando ? () {} : null,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Fotos ────────────────────────────────────────
                        const SpSectionTitle('Fotos'),
                        const SizedBox(height: SpSpace.s3),
                        _fotoSection(),

                        // ── Especie ──────────────────────────────────────
                        const SizedBox(height: SpSpace.s6),
                        const SpSectionTitle('¿Qué animal es?'),
                        const SizedBox(height: SpSpace.s3),
                        SpSelectorEspecie(
                          especies: _especies,
                          seleccion: _especie,
                          onSeleccionar: (v) => setState(() => _especie = v),
                        ),

                        // ── Sobre el animal ──────────────────────────────
                        const SizedBox(height: SpSpace.s6),
                        const SpSectionTitle('Sobre el animal'),
                        const SizedBox(height: SpSpace.s3),
                        SpCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _campo(
                                'Nombre',
                                _nombreCtl,
                                'ej. Luna',
                                maxLength: 30,
                              ),
                              _selector(
                                'Edad',
                                _edad,
                                _edades,
                                (v) => setState(() => _edad = v),
                              ),
                              _selector(
                                'Género',
                                _genero,
                                _generos,
                                (v) => setState(() => _genero = v),
                              ),
                              _selector(
                                'Estado de salud',
                                _estado,
                                _estados,
                                (v) => setState(() => _estado = v),
                              ),
                              _selector(
                                '¿Vacunado?',
                                _vacunado,
                                _saludOpts,
                                (v) => setState(() => _vacunado = v),
                              ),
                              _selector(
                                '¿Desparasitado?',
                                _desparasitado,
                                _saludOpts,
                                (v) => setState(() => _desparasitado = v),
                              ),
                              _selector(
                                'Urgencia',
                                _urgencia,
                                _urgencias,
                                (v) => setState(() => _urgencia = v),
                                spColorUrgencia(c, _urgencia),
                              ),
                            ],
                          ),
                        ),

                        // ── Compatibilidad ───────────────────────────────
                        const SizedBox(height: SpSpace.s6),
                        const SpSectionTitle('Compatibilidad para adopción'),
                        const SizedBox(height: SpSpace.s3),
                        SpCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _selector(
                                'Energía',
                                _energia,
                                _energias,
                                (v) => setState(() => _energia = v),
                                null,
                                true,
                              ),
                              _selector(
                                'Tamaño',
                                _tamano,
                                _tamanos,
                                (v) => setState(() => _tamano = v),
                              ),
                              _selector(
                                '¿Amigable con niños?',
                                _okNinos,
                                _siNo,
                                (v) => setState(() => _okNinos = v),
                              ),
                              _selector(
                                '¿Sociable con animales?',
                                _okMascotas,
                                _siNo,
                                (v) => setState(() => _okMascotas = v),
                              ),
                              _selector(
                                '¿Requiere experiencia?',
                                _requiereExp,
                                _siNo,
                                (v) => setState(() => _requiereExp = v),
                              ),
                            ],
                          ),
                        ),

                        // ── Su historia (y ubicación, si es rescatista) ──
                        const SizedBox(height: SpSpace.s6),
                        const SpSectionTitle('Su historia'),
                        const SizedBox(height: SpSpace.s3),
                        SpCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // El albergue no elige ubicación: todos sus
                              // animales heredan la ciudad de su perfil.
                              if (!_esDeAlbergue) ...[
                                _campoUbicacion(),
                                const SizedBox(height: 8),
                              ],
                              _campo(
                                'Descripción',
                                _descCtl,
                                'Cuéntanos sobre el animal...',
                                maxLines: 5,
                                maxLength: 1000,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: SpSpace.s6),
                        _botonGuardar(c),
                        if (_puedeBorrar) ...[
                          const SizedBox(height: SpSpace.s3),
                          SizedBox(
                            width: double.infinity,
                            child: SpButton(
                              label: 'Eliminar publicación',
                              icon: Icons.delete_outline_rounded,
                              peligro: true,
                              onTap: _guardando ? null : _eliminar,
                            ),
                          ),
                        ],
                        if (_cargadoPor != null) ...[
                          const SizedBox(height: SpSpace.s3),
                          Center(
                            child: Text(
                              'Cargado por $_cargadoPor',
                              style: SpText.caption.copyWith(color: c.lilacInk, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Botón verde 3D "Guardar cambios" (antes era un texto arriba a la
  /// derecha). Mientras guarda no se puede tocar pero sigue verde, con el
  /// aviso de "tardando" adentro — mismo criterio que "Publicar rescate".
  Widget _botonGuardar(SpColors c) {
    final contenido = _guardando
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: c.onPrimary,
                  strokeWidth: 2,
                ),
              ),
              if (tardandoMucho) ...[
                const SizedBox(height: 6),
                Text(
                  'Esto está tardando más de lo normal. Revisá tu conexión',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: c.onPrimary),
                ),
              ],
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 20, color: c.onPrimary),
              const SizedBox(width: 8),
              Text(
                'Guardar cambios',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: c.onPrimary,
                ),
              ),
            ],
          );
    final caja = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      alignment: Alignment.center,
      decoration: SpDeco.primary(c, radius: SpRadius.md),
      child: contenido,
    );
    return Semantics(
      button: true,
      enabled: !_guardando,
      label: _guardando ? null : 'Guardar',
      child: _guardando ? caja : SpPressable(onTap: _guardar, child: caja),
    );
  }

  /// Etiqueta de un campo dentro de una tarjeta (`.field > span`).
  Widget _etiqueta(String t) => Text(
    t,
    style: SpText.label.copyWith(
      color: context.sp.inkMuted,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _fotoSection() {
    final bool tiene1 = _nuevaFoto != null || _fotoUrlExistente != null;
    final bool tiene2 = _nuevaFoto2 != null || _foto2UrlExistente != null;
    final int total = (tiene1 ? 1 : 0) + (tiene2 ? 1 : 0);
    final items = <Widget>[];

    if (tiene1) {
      items.add(
        _fotoThumbEdit(
          file: _nuevaFoto,
          url: _fotoUrlExistente,
          slot: 1,
          // Si se borra la foto 1 y la 2 existe, la 2 pasa a ocupar el slot 1
          // en vez de dejar un hueco: todas las pantallas que muestran "la
          // foto" del animal (Mis animales, solicitudes, chats, etc.) solo
          // miran fotoUrl (slot 1), nunca fotoUrl2 — un hueco ahí las deja
          // mostrando el emoji de repuesto aunque sí haya una foto guardada.
          onRemove: () => setState(() {
            if (_nuevaFoto2 != null || _foto2UrlExistente != null) {
              _nuevaFoto = _nuevaFoto2;
              _fotoUrlExistente = _foto2UrlExistente;
              _nuevaFoto2 = null;
              _foto2UrlExistente = null;
            } else {
              _nuevaFoto = null;
              _fotoUrlExistente = null;
            }
          }),
        ),
      );
    }
    if (tiene2) {
      items.add(
        _fotoThumbEdit(
          file: _nuevaFoto2,
          url: _foto2UrlExistente,
          slot: 2,
          onRemove: () => setState(() {
            _nuevaFoto2 = null;
            _foto2UrlExistente = null;
          }),
        ),
      );
    }
    if (total < 2) {
      items.add(_fotoAddBtnEdit(nextSlot: tiene1 ? 2 : 1));
    }

    return Wrap(spacing: SpSpace.s3, runSpacing: SpSpace.s3, children: items);
  }

  Widget _fotoThumbEdit({
    XFile? file,
    String? url,
    required int slot,
    required VoidCallback onRemove,
  }) {
    final c = context.sp;
    return Stack(
      children: [
        GestureDetector(
          // Tocar la foto misma la reemplaza directo (cámara/galería) — antes
          // solo se podía quitar con la "x" y agregar de nuevo aparte, un
          // flujo de 2 pasos que invitaba a guardar a mitad de camino.
          onTap: () => _mostrarOpcionesFoto(slot),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: file != null
                ? Image.file(
                    File(file.path),
                    width: 140,
                    height: 168,
                    fit: BoxFit.cover,
                  )
                : FotoUrl(
                    url: url!,
                    width: 140,
                    height: 168,
                    alignment: Alignment.topCenter,
                    fallback: Container(
                      width: 140,
                      height: 168,
                      color: c.surfaceSunken,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: c.inkFaint,
                      ),
                    ),
                  ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Tooltip(
            message: 'Quitar foto',
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 30,
                height: 30,
                decoration: SpDeco.soft(c, radius: SpRadius.full),
                child: Icon(Icons.close_rounded, size: 17, color: c.ink),
              ),
            ),
          ),
        ),
        // Ver ampliada — solo para la foto ya subida (file == null); una foto
        // recién elegida de la galería no tiene URL de red que mostrarle al
        // visor, y ya se ve completa en el picker mismo. Ícono aparte (no el
        // mismo toque que la foto) porque acá tocar la foto ya reemplaza —
        // pedido de Eliza al agregar esto también para rescatista/albergue,
        // igual que ya existía para el adoptante.
        if (file == null && url != null)
          Positioned(
            bottom: 8,
            left: 8,
            child: Tooltip(
              message: 'Ver foto completa',
              child: GestureDetector(
                onTap: () => context.push(
                  AppRoutes.visorFoto,
                  extra: (fotos: [url], indiceInicial: 0),
                ),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: SpDeco.soft(c, radius: SpRadius.full),
                  child: Icon(
                    Icons.zoom_out_map_rounded,
                    size: 16,
                    color: c.ink,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Recuadro punteado para agregar foto, como en Subir uno.
  Widget _fotoAddBtnEdit({required int nextSlot}) {
    final c = context.sp;
    return GestureDetector(
      onTap: () => _mostrarOpcionesFoto(nextSlot),
      child: CustomPaint(
        foregroundPainter: SpBordePunteado(c.mintDeep),
        child: Container(
          width: 140,
          height: 168,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: SpDeco.primary(c, radius: 16, gradient: true),
                child: Icon(
                  Icons.add_a_photo_rounded,
                  size: 24,
                  color: c.onPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                nextSlot == 1 ? 'Agregar' : 'Agregar otra',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
              Text(
                nextSlot == 1 ? 'Obligatoria' : '1 de 2',
                style: SpText.caption.copyWith(
                  color: c.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // maxLength sin tope antes: un pegado gigante en nombre/descripción se
  // guardaba entero, inflando el tamaño del documento sin ninguna razón
  // real. Hallazgo de auditoría de código. El estilo del campo viene del
  // tema (inputDecorationTheme), igual que en Subir uno.
  Widget _campo(
    String label,
    TextEditingController ctl,
    String hint, {
    int maxLines = 1,
    int? maxLength,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _etiqueta(label),
      const SizedBox(height: 8),
      TextField(
        controller: ctl,
        maxLines: maxLines,
        maxLength: maxLength,
        decoration: InputDecoration(hintText: hint),
      ),
    ],
  );

  /// Un solo campo, no dos: el texto se puede escribir a mano (como
  /// siempre) O completar solo tocando el ícono de GPS a la derecha. Antes
  /// había un campo de texto Y, debajo, una tarjeta aparte solo para el
  /// detector — quedaba "ubicación" pedida dos veces en la misma pantalla.
  Widget _campoUbicacion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta('Ubicación'),
        const SizedBox(height: 8),
        // CampoCiudad: el mismo campo que usan los perfiles y publicar.
        // Antes acá había una versión propia con su copia entera de la
        // detección por GPS — eran tres, una por pantalla.
        CampoCiudad(
          controller: _lugarCtl,
          focusNode: _lugarFocus,
          hint: 'ej. Laureles',
          maxLength: 60,
          controlador: _ciudadCtrl,
          antesDeAbrirAjustes: marcarVolviendoDeAjustes,
          // Mismo criterio que al publicar: los tres datos del MISMO punto.
          onDetectado: (r) => setState(() {
            _latitud = r.posicion?.latitude;
            _longitud = r.posicion?.longitude;
            _paisCodigo = r.paisCodigo;
            // El listener de _lugarCtl prende la marca al escribir el
            // texto, así que apagarla va DESPUÉS: esto no es una edición a
            // mano, texto y coordenadas salieron del mismo lugar.
            _lugarOriginal = _lugarCtl.text;
          }),
        ),
      ],
    );
  }

  /// Una pregunta con sus opciones (ChipsSeleccionables, el verde 3D del
  /// tema), separada de la anterior — igual que `_grupo` en Subir uno.
  Widget _selector(
    String label,
    String valor,
    List<String> opts,
    ValueChanged<String> onChanged, [
    Color? colorActivo,
    bool primero = false,
  ]) => Padding(
    padding: EdgeInsets.only(top: primero ? 0 : 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta(label),
        const SizedBox(height: 10),
        ChipsSeleccionables(
          opciones: opts,
          seleccion: valor,
          onSeleccionar: onChanged,
          colorActivo: colorActivo,
          duracion: const Duration(milliseconds: 160),
        ),
      ],
    ),
  );
}
