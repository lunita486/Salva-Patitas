import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../theme.dart';
import '../data/rescates_repository.dart';
import '../data/rescate_fotos_repository.dart';
import '../data/foto_normalizador.dart';
import 'visor_foto_completa.dart';

class EditarRescateScreen extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  const EditarRescateScreen({super.key, required this.docId, required this.data});
  @override
  State<EditarRescateScreen> createState() => _EditarRescateScreenState();
}

class _EditarRescateScreenState extends State<EditarRescateScreen> with TardandoMuchoMixin {
  late TextEditingController _nombreCtl;
  late TextEditingController _descCtl;
  late TextEditingController _lugarCtl;
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
  final _picker = ImagePicker();

  // Publicar un rescate nuevo (subir_rescate_screen.dart) ya exige al
  // menos una foto, pero acá al editar se podía quitar la única que tenía
  // y guardar igual — el animal quedaba sin ninguna foto para siempre
  // (sugerencia real de Eliza: la foto debería ser requerida, no opcional,
  // en todos los flujos, no solo al publicar por primera vez).
  bool get _tieneAlMenosUnaFoto =>
      _nuevaFoto != null || _fotoUrlExistente != null ||
      _nuevaFoto2 != null || _foto2UrlExistente != null;

  bool _detectandoUbicacion = false;
  double? _latitud;
  double? _longitud;
  String _paisCodigo = '';

  static const _especies  = ['Perro', 'Gato', 'Otro'];
  static const _estados   = ['Sano', 'En tratamiento', 'Recuperado'];
  static const _urgencias = ['Alta', 'Media', 'Baja'];
  static const _energias  = ['Tranquilo', 'Activo', 'Muy activo'];
  static const _tamanos   = ['Pequeño', 'Mediano', 'Grande'];
  static const _edades    = ['Cachorro', 'Adulto', 'Senior'];
  static const _generos   = ['Macho', 'Hembra', 'No sé'];
  static const _siNo      = ['Sí', 'No'];
  static const _saludOpts = ['Sí', 'No', 'Aún no lo sé'];

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _nombreCtl = TextEditingController(text: d['nombre'] ?? '');
    _descCtl   = TextEditingController(text: d['descripcion'] ?? '');
    _lugarCtl  = TextEditingController(text: d['ubicacion'] ?? '');
    _especie   = d['especie']   ?? 'Perro';
    _estado    = d['estado']    ?? 'Sano';
    _urgencia  = d['urgencia']  ?? 'Media';
    _energia   = d['energia']   ?? 'Tranquilo';
    _tamano    = d['tamano']    ?? 'Mediano';
    _edad      = d['edad']      ?? 'Cachorro';
    _genero    = d['genero']    ?? 'No sé';
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
    _okNinos   = (d['okConNinos']    as bool? ?? true) ? 'Sí' : 'No';
    _okMascotas= (d['okConMascotas'] as bool? ?? true) ? 'Sí' : 'No';
    _requiereExp=(d['requiereExperiencia'] as bool? ?? false) ? 'Sí' : 'No';
    // String, no bool — y con fallback a 'Aún no lo sé' para animales
    // publicados antes de que existiera este campo, no a 'No' (que
    // afirmaría algo que no se sabe).
    _vacunado      = d['vacunado']      as String? ?? 'Aún no lo sé';
    _desparasitado = d['desparasitado'] as String? ?? 'Aún no lo sé';
    _fotoUrlExistente  = d['fotoUrl']  as String?;
    _foto2UrlExistente = d['fotoUrl2'] as String?;
    // num→toDouble y no "as double": si algún doc trae la coordenada como
    // entero (dato legado o escrito a mano), un cast estricto tira una
    // excepción en initState y rompe la pantalla de editar completa.
    _latitud     = (d['latitud']  as num?)?.toDouble();
    _longitud    = (d['longitud'] as num?)?.toDouble();
    _paisCodigo  = d['paisCodigo'] as String? ?? '';
  }

  /// Igual que en subir_rescate_screen.dart: con timeLimit para que un GPS
  /// lento o que falla no se quede esperando para siempre sin avisar nada.
  /// Totalmente opcional acá — guardar nunca depende de esto.
  Future<void> _obtenerUbicacionGPS() async {
    setState(() => _detectandoUbicacion = true);
    // Después de cada await hay que re-verificar mounted antes de setState:
    // la detección puede tardar y la usuaria puede haber salido de la
    // pantalla mientras tanto (setState tras dispose es una excepción).
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activa el GPS en tu dispositivo'), backgroundColor: msgError));
      setState(() => _detectandoUbicacion = false);
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() => _detectandoUbicacion = false);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      // Mismo criterio que subir_rescate_screen.dart: un botón que abre
      // directo la pantalla de permisos, no solo el texto "andá a Ajustes".
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Permiso de ubicación bloqueado.'),
        backgroundColor: msgError,
        action: SnackBarAction(
          label: 'Abrir Ajustes',
          textColor: Colors.white,
          onPressed: () => Geolocator.openAppSettings(),
        ),
        duration: const Duration(seconds: 8),
      ));
      setState(() => _detectandoUbicacion = false);
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ));
      String ciudad = '';
      String paisCodigo = '';
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          ciudad = placemarks.first.locality?.isNotEmpty == true
              ? placemarks.first.locality!
              : placemarks.first.administrativeArea ?? '';
          paisCodigo = placemarks.first.isoCountryCode ?? '';
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _latitud  = pos.latitude;
        _longitud = pos.longitude;
        if (ciudad.isNotEmpty) _lugarCtl.text = ciudad;
        _paisCodigo = paisCodigo;
        _detectandoUbicacion = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _detectandoUbicacion = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo detectar tu ubicación. Podés reintentar tocando de nuevo.'),
          backgroundColor: msgError));
    }
  }

  @override
  void dispose() {
    _nombreCtl.dispose(); _descCtl.dispose(); _lugarCtl.dispose();
    super.dispose();
  }

  Future<void> _pickFoto(ImageSource src, {int slot = 1}) async {
    final img = await _picker.pickImage(source: src, imageQuality: 80, maxWidth: 1000, maxHeight: 1000);
    if (img == null || !mounted) return;
    setState(() {
      if (slot == 1) { _nuevaFoto  = img; }
      else           { _nuevaFoto2 = img; }
    });
  }

  void _mostrarOpcionesFoto(int slot) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: appTeal),
            title: const Text('Tomar foto'),
            onTap: () { Navigator.pop(context); _pickFoto(ImageSource.camera, slot: slot); },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: appTeal),
            title: const Text('Elegir de la galería'),
            onTap: () { Navigator.pop(context); _pickFoto(ImageSource.gallery, slot: slot); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // Guard de reentrada — mismo motivo que en mis_rescates_screen.dart: el
  // chequeo de solicitudes pendientes tarda un momento sin mostrar nada, y
  // un segundo toque a "Eliminar publicación" en esa ventana apilaba dos
  // diálogos de confirmación (uno seguía preguntando por un animal que el
  // otro ya había borrado).
  bool _eliminando = false;

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
    final nombre = _nombreCtl.text.trim().isNotEmpty ? _nombreCtl.text.trim() : 'este animal';

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
        rescatistaId: FirebaseAuth.instance.currentUser?.uid ?? '',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No pudimos verificar si se puede eliminar. Revisá tu conexión e intentá de nuevo.'),
          backgroundColor: msgError));
      return;
    }
    if (!mounted) return;
    if (bloqueo != null) {
      await showDialog<void>(
        context: context,
        builder: (dlgCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(bloqueo!.$1),
          content: Text(bloqueo.$2),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Entendido')),
          ],
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar publicación'),
        content: Text('¿Seguro que quieres eliminar a $nombre? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() => _guardando = true);
    // Mismo feedback persistente que en mis_rescates_screen.dart: sin
    // señal hay hasta ~20s de timeouts encadenados, y el spinner de
    // _guardando (pensado para el botón de guardar) no le dice a nadie
    // que hay un BORRADO en curso. Los desenlaces lo reemplazan con
    // hideCurrentSnackBar antes de mostrarse.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Eliminando a $nombre…'),
      duration: const Duration(seconds: 30),
    ));
    try {
      // Fotos ANTES que el documento, a propósito: storage.rules verifica
      // el dueño de una foto leyendo el documento de rescates — con el doc
      // ya borrado, esa lectura falla y el borrado de fotos era rechazado
      // en silencio: cada animal eliminado dejaba sus fotos huérfanas
      // pagando almacenamiento para siempre. Best-effort igual (try/catch,
      // no .catchError — un catchError mal tipado revienta acá y el flujo
      // muere en silencio antes del SnackBar).
      try {
        await RescateFotosRepository().eliminarTodas(widget.docId)
            .timeout(const Duration(seconds: 10));
      } catch (_) {}
      // Con timeout: sin señal, .delete() se encola y su Future no
      // resuelve hasta reconectar — sin límite, la pantalla quedaba con el
      // spinner para siempre. El TimeoutException cae al catch de abajo,
      // que para ese caso muestra el mensaje honesto ("se va a completar
      // al volver la señal") — el borrado encolado SÍ se aplica solo.
      await RescatesRepository().eliminar(widget.docId)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Publicación eliminada'), backgroundColor: msgExito));
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
          const SnackBar(content: Text('Publicación eliminada'), backgroundColor: msgExito));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(RescatesRepository.mensajeErrorEliminar(e)),
          backgroundColor: msgError,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Resuelve un slot de foto comparando estado inicial vs. final: foto
  /// nueva → subirla (sobreescribe el mismo path); sin cambios → mantener
  /// la URL que ya había, sin tocar Storage; se quitó sin reemplazarla →
  /// borrarla de Storage para no dejarla huérfana pagando almacenamiento.
  // Timeouts a propósito (mismo motivo que subir_rescate_screen.dart): a
  // diferencia del `.update()` de Firestore de más abajo, Storage NO
  // encola solo las subidas/borrados sin señal — sin este límite, una foto
  // nueva o un borrado se quedaban esperando para siempre en modo avión, y
  // el catch de _guardar() nunca llegaba a dispararse.
  Future<String?> _resolverSlot({
    required int slot,
    required XFile? nuevaFoto,
    required String? urlExistente,
  }) async {
    if (nuevaFoto != null) {
      // Mismo normalizador que subir_rescate_screen.dart/subir_lote_screen.dart
      // (recorte a 1000px, JPEG q80, corrige orientación) — antes esta
      // pantalla subía los bytes crudos del picker, así que una foto podía
      // quedar con distinta calidad/orientación según si se agregó al
      // publicar o al editar después (hallazgo de auditoría de código).
      final bytes = await normalizarFoto(nuevaFoto.path);
      // El timeout vive DENTRO de subir() (cancela la subida real al
      // vencer) — no se vuelve a envolver acá, ver el doc del método.
      return RescateFotosRepository()
          .subir(rescateId: widget.docId, slot: slot, bytes: bytes);
    }
    if (urlExistente != null) return urlExistente;
    // Red de seguridad, independiente de la detección de promoción de
    // _guardar: JAMÁS borrar un archivo que la ficha va a seguir
    // referenciando desde el otro campo. Si por cualquier camino futuro
    // este slot se resuelve como "vacío" mientras el otro campo todavía
    // apunta a su archivo, borrar dejaría la ficha apuntando a una foto
    // muerta (el emoji en el feed) — el modo de falla del bug de
    // "rarito 2" / "eddy 2.0". Con este guard el peor caso pasa a ser
    // benigno: queda un archivo con nombre "cruzado" pero la foto se
    // sigue viendo. Para que una foto se rompa tendrían que fallar la
    // detección de _guardar Y este chequeo a la vez.
    //
    // Si el otro slot tiene una foto NUEVA elegida, su campo va a quedar
    // apuntando a su propio archivo recién subido — este archivo queda
    // sin referencias y sí se puede borrar.
    final urlDelOtroSlot   = slot == 1 ? _foto2UrlExistente : _fotoUrlExistente;
    final nuevaDelOtroSlot = slot == 1 ? _nuevaFoto2 : _nuevaFoto;
    final referenciadoPorOtroSlot = nuevaDelOtroSlot == null &&
        RescateFotosRepository.urlApuntaASlot(urlDelOtroSlot, slot);
    if (!referenciadoPorOtroSlot) {
      await RescateFotosRepository()
          .eliminar(rescateId: widget.docId, slot: slot)
          .timeout(const Duration(seconds: 10));
    }
    return null;
  }

  Future<void> _guardar() async {
    if (!_tieneAlMenosUnaFoto) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('El animal necesita al menos una foto. Agregá una antes de guardar.'),
          backgroundColor: msgError));
      return;
    }
    setState(() { _guardando = true; });
    iniciarTimerTardando(const Duration(seconds: 8));
    try {
      final String? fotoUrl;
      final String? fotoUrl2;
      // Se quitó la foto 1 y la 2 quedó ocupando su lugar (la "promoción"
      // de _fotoSection): _fotoUrlExistente apunta al archivo foto2.jpg.
      // Hay que mover el archivo de verdad — si solo se copiara la URL
      // entre campos, la resolución del slot 2 de abajo borraría foto2.jpg
      // como "slot vacío" y fotoUrl quedaría apuntando a un archivo
      // borrado (bug real: "rarito 2" mostrando el emoji en el feed con
      // su ficha apuntando a una foto que ya no existía). El chequeo por
      // path (y no comparando contra la URL inicial) también repara docs
      // que ya quedaron cruzados por este bug antes del arreglo.
      final promocionPendiente = _nuevaFoto == null &&
          RescateFotosRepository.urlApuntaASlot(_fotoUrlExistente, 2);
      if (promocionPendiente) {
        // Secuencial a propósito: moverFoto lee y borra foto2.jpg, y la
        // resolución del slot 2 puede subir una foto nueva a ese mismo
        // path (quitar la 1 y agregar otra segunda foto en la misma
        // edición) — en paralelo se pisarían.
        //
        // Sin `.timeout()` acá afuera a propósito: moverFoto() ya está
        // acotado por dentro (20s la descarga + el timeout propio de
        // subir(), que cancela la subida real al vencer). Envolverlo acá
        // TAMBIÉN podía "darse por vencido" unos segundos antes de que la
        // cancelación interna llegara a correr — dos relojes corriendo a
        // la vez para lo mismo, y el de afuera no cancela nada real.
        final fotoMovida = await RescateFotosRepository()
            .moverFoto(rescateId: widget.docId, deSlot: 2, aSlot: 1);
        // moverFoto() devuelve null tanto si movió con éxito "nada" (no
        // hay archivo de origen) como si el archivo ya no estaba en
        // Storage por un desfasaje previo — en ese segundo caso, este
        // campo YA tenía una URL válida en Firestore (por eso se detectó
        // la promoción). Null acá no significa "sin foto": significa "no
        // hubo nada que mover", así que se mantiene la URL existente en
        // vez de borrarla — perder la referencia sería peor que dejarla
        // como estaba (hallazgo de auditoría de código).
        fotoUrl = fotoMovida ?? _fotoUrlExistente;
        fotoUrl2 = await _resolverSlot(
            slot: 2, nuevaFoto: _nuevaFoto2, urlExistente: _foto2UrlExistente);
      } else {
        // Los dos slots se resuelven en paralelo, no uno atrás del otro — son
        // independientes (cada uno sube/borra su propio archivo), así que
        // esperarlos de a uno duplicaba el tiempo de espera sin necesidad.
        final resultados = await Future.wait([
          _resolverSlot(slot: 1, nuevaFoto: _nuevaFoto, urlExistente: _fotoUrlExistente),
          _resolverSlot(slot: 2, nuevaFoto: _nuevaFoto2, urlExistente: _foto2UrlExistente),
        ]);
        fotoUrl  = resultados[0];
        fotoUrl2 = resultados[1];
      }

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
        await RescatesRepository().actualizar(widget.docId, {
          'nombre':      _nombreCtl.text.trim(),
          'descripcion': _descCtl.text.trim(),
          'ubicacion':   _lugarCtl.text.trim(),
          'especie':     _especie,
          'estado':      _estado,
          'urgencia':    _urgencia,
          'energia':     _energia,
          'tamano':      _tamano,
          'edad':        _edad,
          'genero':      _genero,
          'okConNinos':          _okNinos    == 'Sí',
          'okConMascotas':       _okMascotas == 'Sí',
          'requiereExperiencia': _requiereExp == 'Sí',
          'vacunado':            _vacunado,
          'desparasitado':       _desparasitado,
          'fotoUrl':  fotoUrl  ?? FieldValue.delete(),
          'fotoUrl2': fotoUrl2 ?? FieldValue.delete(),
          if (_latitud    != null) 'latitud':    _latitud,
          if (_longitud   != null) 'longitud':   _longitud,
          if (_paisCodigo.isNotEmpty) 'paisCodigo': _paisCodigo,
        }).timeout(const Duration(seconds: 20));
      } on TimeoutException {
        guardadoConfirmado = false;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(guardadoConfirmado
            ? '¡Cambios guardados!'
            : 'Esto está tardando. Tu cambio se va a guardar solo apenas vuelva la señal.'),
        backgroundColor: guardadoConfirmado ? msgExito : msgAdvertencia,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: guardadoConfirmado ? 4 : 6),
      ));
      Navigator.pop(context);
    } catch (_) {
      // Acá sí es una falla real de verdad (subir/borrar una foto en
      // Storage, que a diferencia de Firestore no se reintenta solo sin
      // señal) — mismo estilo y comportamiento que
      // subir_rescate_screen.dart/subir_lote_screen.dart.
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('No se pudo guardar. Revisá tu conexión e intentá de nuevo.'),
        backgroundColor: msgError,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ));
    } finally {
      cancelarTimerTardando();
      if (mounted) setState(() { _guardando = false; tardandoMucho = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 20, 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                tooltip: 'Volver',
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(child: Text('Editar animal',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: appInk,
                      fontFamily: 'Baloo2'))),
              if (_guardando)
                const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: appTeal, strokeWidth: 2))
              else
                TextButton(
                  onPressed: _guardar,
                  child: const Text('Guardar', style: TextStyle(color: appTeal, fontWeight: FontWeight.w700, fontSize: 15)),
                ),
            ]),
          ),
          if (tardandoMucho)
            Container(
              width: double.infinity,
              color: Colors.orange.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text('Esto está tardando más de lo normal. Revisá tu conexión',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: Colors.orange.shade900)),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _seccion('FOTOS'),
                const SizedBox(height: 10),
                _fotoSection(),
                const SizedBox(height: 20),
                _campo('Nombre', _nombreCtl, 'ej. Luna'),
                const SizedBox(height: 16),
                _campoUbicacion(),
                const SizedBox(height: 16),
                _campo('Descripción', _descCtl, 'Cuéntanos sobre el animal...', maxLines: 3),
                const SizedBox(height: 20),
                _seccion('INFORMACIÓN'),
                const SizedBox(height: 12),
                _selector('Especie', _especie, _especies, (v) => setState(() => _especie = v)),
                const SizedBox(height: 12),
                _selector('Estado de salud', _estado, _estados, (v) => setState(() => _estado = v)),
                const SizedBox(height: 12),
                _selector('¿Vacunado?', _vacunado, _saludOpts, (v) => setState(() => _vacunado = v)),
                const SizedBox(height: 12),
                _selector('¿Desparasitado?', _desparasitado, _saludOpts, (v) => setState(() => _desparasitado = v)),
                const SizedBox(height: 12),
                _selector('Urgencia', _urgencia, _urgencias, (v) => setState(() => _urgencia = v)),
                const SizedBox(height: 20),
                _seccion('COMPATIBILIDAD'),
                const SizedBox(height: 12),
                _selector('Energía', _energia, _energias, (v) => setState(() => _energia = v)),
                const SizedBox(height: 12),
                _selector('Tamaño', _tamano, _tamanos, (v) => setState(() => _tamano = v)),
                const SizedBox(height: 12),
                _selector('Edad', _edad, _edades, (v) => setState(() => _edad = v)),
                const SizedBox(height: 12),
                _selector('Género', _genero, _generos, (v) => setState(() => _genero = v)),
                const SizedBox(height: 12),
                _selector('¿Amigable con niños?', _okNinos, _siNo, (v) => setState(() => _okNinos = v)),
                const SizedBox(height: 12),
                _selector('¿Sociable con animales?', _okMascotas, _siNo, (v) => setState(() => _okMascotas = v)),
                const SizedBox(height: 12),
                _selector('¿Requiere experiencia?', _requiereExp, _siNo, (v) => setState(() => _requiereExp = v)),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: _guardando ? null : _eliminar,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.delete_outline, color: Colors.red.shade400, size: 18),
                      const SizedBox(width: 8),
                      Text('Eliminar publicación',
                          style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _seccion(String t) => Text(t,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.grey.shade700));

  Widget _fotoSection() {
    final bool tiene1 = _nuevaFoto != null || _fotoUrlExistente != null;
    final bool tiene2 = _nuevaFoto2 != null || _foto2UrlExistente != null;
    final int total   = (tiene1 ? 1 : 0) + (tiene2 ? 1 : 0);
    final items       = <Widget>[];

    if (tiene1) {
      items.add(_fotoThumbEdit(
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
      ));
    }
    if (tiene2) {
      items.add(_fotoThumbEdit(
        file: _nuevaFoto2,
        url: _foto2UrlExistente,
        slot: 2,
        onRemove: () => setState(() { _nuevaFoto2 = null; _foto2UrlExistente = null; }),
      ));
    }
    if (total < 2) {
      items.add(_fotoAddBtnEdit(nextSlot: tiene1 ? 2 : 1));
    }

    return Wrap(spacing: 10, runSpacing: 10, children: items);
  }

  Widget _fotoThumbEdit({XFile? file, String? url, required int slot, required VoidCallback onRemove}) {
    return Stack(children: [
      GestureDetector(
        // Tocar la foto misma la reemplaza directo (cámara/galería) — antes
        // solo se podía quitar con la "x" y agregar de nuevo aparte, un
        // flujo de 2 pasos que invitaba a guardar a mitad de camino.
        onTap: () => _mostrarOpcionesFoto(slot),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: file != null
              ? Image.file(File(file.path), width: 90, height: 90, fit: BoxFit.cover)
              : FotoUrl(
                  url: url!,
                  width: 90, height: 90,
                  alignment: Alignment.topCenter,
                  fallback: Container(
                    width: 90, height: 90,
                    color: Colors.grey.shade200,
                    child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade400),
                  ),
                ),
        ),
      ),
      Positioned(
        top: 4, right: 4,
        child: GestureDetector(
          onTap: onRemove,
          child: Container(
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            padding: const EdgeInsets.all(3),
            child: const Icon(Icons.close, size: 14, color: Colors.white),
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
          bottom: 4, left: 4,
          child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => VisorFotoCompleta(fotos: [url], indiceInicial: 0))),
            child: Container(
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.zoom_in, size: 14, color: Colors.white),
            ),
          ),
        ),
    ]);
  }

  Widget _fotoAddBtnEdit({required int nextSlot}) {
    return GestureDetector(
      onTap: () => _mostrarOpcionesFoto(nextSlot),
      child: Container(
        width: 90, height: 90,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: appTeal.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.add_a_photo_outlined, color: appTeal, size: 28),
          const SizedBox(height: 4),
          Text(
            nextSlot == 1 ? 'Agregar' : '1/2',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ]),
      ),
    );
  }

  Widget _campo(String label, TextEditingController ctl, String hint, {int maxLines = 1}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: appInk)),
      const SizedBox(height: 6),
      TextField(
        controller: ctl,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    ]);

  /// Un solo campo, no dos: el texto se puede escribir a mano (como
  /// siempre) O completar solo tocando el ícono de GPS a la derecha. Antes
  /// había un campo de texto Y, debajo, una tarjeta aparte solo para el
  /// detector — quedaba "ubicación" pedida dos veces en la misma pantalla.
  Widget _campoUbicacion() {
    final obtenida = _latitud != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Ubicación', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: appInk)),
      const SizedBox(height: 6),
      TextField(
        controller: _lugarCtl,
        decoration: InputDecoration(
          hintText: 'ej. Laureles',
          hintStyle: TextStyle(color: Colors.grey.shade400),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          suffixIcon: _detectandoUbicacion
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: appTeal)))
              : IconButton(
                  tooltip: 'Detectar mi ubicación',
                  icon: Icon(obtenida ? Icons.check_circle : Icons.my_location,
                      color: obtenida ? appTeal : Colors.grey.shade700),
                  onPressed: _obtenerUbicacionGPS,
                ),
        ),
      ),
    ]);
  }

  Widget _selector(String label, String valor, List<String> opts, ValueChanged<String> onChanged) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: appInk)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: opts.map((o) {
        final sel = o == valor;
        return GestureDetector(
          onTap: () => onChanged(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? appTeal : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? appTeal : Colors.grey.shade300),
            ),
            child: Text(o, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: sel ? Colors.white : Colors.grey.shade700)),
          ),
        );
      }).toList()),
    ]);
}
