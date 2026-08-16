import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';
import '../theme.dart';
import '../widgets/chips_seleccionables.dart';
import '../widgets/confirmar_ciudad_resuelta.dart';
import '../widgets/elegir_foto_animal.dart';
import '../widgets/tardando_mucho_mixin.dart';
import '../data/creator_role.dart';
import '../data/rescates_repository.dart';
import '../data/usuarios_repository.dart';
import '../data/foto_normalizador.dart';
import '../services/ubicacion_service.dart';
import '../services/ubicacion_lifecycle.dart';

class SubirRescateScreen extends StatefulWidget {
  final bool esAlbergue;
  const SubirRescateScreen({super.key, this.esAlbergue = false});
  @override
  State<SubirRescateScreen> createState() => _SubirRescateScreenState();
}

class _SubirRescateScreenState extends State<SubirRescateScreen>
    with
        TardandoMuchoMixin,
        WidgetsBindingObserver,
        ReintentoUbicacionTrasAjustes {
  final _nombreCtl = TextEditingController();
  final _lugarCtl = TextEditingController();
  final _descCtl = TextEditingController();

  final _razaCtl = TextEditingController();
  final List<XFile> _fotos = [];
  String _especie = 'Perro';
  String _estado = 'Sano';
  String _urgencia = 'Alta';
  String _energia = 'Tranquilo';
  String _tamano = 'Mediano';
  String _edad = 'Cachorro';
  String _genero = 'No sé';
  String _okNinos = 'Sí';
  String _okMascotas = 'Sí';
  String _requiereExp = 'No';
  String _tipoRaza = 'Criolla';
  // 'Aún no lo sé' por defecto, no 'No' — un animal recién rescatado de la
  // calle todavía no pasó por veterinario, y forzar Sí/No hacía que la
  // gente adivinara o dejara el dato mal puesto sin querer (sugerencia
  // real de un tester que rescató un gato de la calle y no tenía cómo
  // saberlo en el momento de publicar).
  String _vacunado = 'Aún no lo sé';
  String _desparasitado = 'Aún no lo sé';

  // Del repositorio, no declaradas acá: son los valores válidos del dominio
  // y tienen que ser LOS MISMOS que usa editar_rescate_screen.dart. Cuando
  // cada pantalla tenía su propia copia ya se habían desincronizado (ver el
  // comentario en RescatesRepository) y un animal publicado como 'Herido'
  // se abría en Editar sin ningún estado marcado.
  static const _especies = RescatesRepository.especies;
  static const _estados = RescatesRepository.estados;
  static const _urgencias = RescatesRepository.urgencias;
  static const _energias = RescatesRepository.energias;
  static const _tamanos = RescatesRepository.tamanos;
  static const _edades = RescatesRepository.edades;
  static const _generos = RescatesRepository.generos;
  static const _siNoOpts = RescatesRepository.siNo;
  static const _saludOpts = RescatesRepository.salud;
  static const _tipoRazaOpts = RescatesRepository.tiposRaza;

  Color _urgenciaColor(String u) => switch (u) {
    'Alta' => const Color(0xFFD32F2F),
    'Media' => const Color(0xFFE65100),
    _ => appTeal,
  };

  /// elegirFotoAnimal (widgets/elegir_foto_animal.dart) muestra la hoja y hace el pickImage,
  /// con el manejo de "cámara no disponible" que antes vivía sólo acá — la
  /// pantalla de editar tenía su propia copia SIN ese try/catch. El tope de
  /// 2 fotos se queda de este lado: depende del estado propio de esta
  /// pantalla (una lista), no del picker.
  Future<void> _mostrarOpcionesFoto() async {
    if (_fotos.length >= 2) return;
    final img = await elegirFotoAnimal(context);
    if (img != null && mounted) setState(() => _fotos.add(img));
  }

  bool _publicando = false;
  double _progreso = 0;
  // Mientras no hay señal, la subida no tiene bytes que transferir todavía
  // — _progreso se queda en 0 y el botón solo muestra un círculo girando,
  // sin ningún texto, hasta que el timeout de 45s se cumple. Sin este
  // aviso parecía que la app estaba colgada (el bug real que reportó
  // Eliza: "el mensaje se demora mucho en presentarse").
  bool _detectandoUbicacion = false;
  double? _latitud;
  double? _longitud;
  String _paisCodigo = '';

  // Se prende apenas la persona toca el campo de texto a mano, y se apaga
  // cada vez que texto y coordenadas vuelven a quedar sincronizados entre
  // sí (por GPS o por el geocodificador en _publicar()) — ver ese comentario
  // para el porqué completo. Mismo patrón que editar_rescate_screen.dart.
  bool _ubicacionTocadaAMano = false;

  @override
  void initState() {
    super.initState();
    _lugarCtl.addListener(() => _ubicacionTocadaAMano = true);
    if (widget.esAlbergue)
      _cargarCiudadAlbergue();
    else
      _obtenerUbicacionGPS();
  }

  // El botón "Abrir Ajustes" del aviso de permiso bloqueado saca a la
  // persona de la app; sin esto, volver de Ajustes con el permiso recién
  // otorgado la dejaba igual, con el aviso rojo todavía en pantalla, sin
  // ninguna señal de que ahora sí podía funcionar — tenía que darse cuenta
  // sola de tocar el campo de ubicación de nuevo. El reintento (solo una
  // vez, solo tras volver de Ajustes) vive en ReintentoUbicacionTrasAjustes
  // — ver ese archivo para el hallazgo completo del bucle que esto evita
  // (real de Eliza, 2026-08-06: "parpadeaba sin parar y la pantalla
  // quedaba inusable").
  @override
  bool get yaTieneUbicacion => widget.esAlbergue || _latitud != null;
  @override
  bool get detectandoUbicacion => _detectandoUbicacion;
  @override
  void reintentarConPermiso() => _obtenerUbicacionGPS();

  Future<void> _cargarCiudadAlbergue() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    final data = doc.data();
    final ciudad = (data?['ciudad'] as String?) ?? '';
    if (!mounted) return;
    setState(() {
      if (ciudad.isNotEmpty) _lugarCtl.text = ciudad;
      // Reusa las coordenadas del perfil del albergue (ver
      // albergue_perfil_screen.dart) — sin esto, un animal publicado por
      // un albergue nunca tenía latitud/longitud, así que "a X km de ti"
      // no podía calcularse para NINGÚN animal suyo. Hallazgo real de
      // Eliza: notó que le pasaba a todos los albergues, no a uno solo.
      _latitud = (data?['latitud'] as num?)?.toDouble();
      _longitud = (data?['longitud'] as num?)?.toDouble();
      _ubicacionTocadaAMano = false;
    });
    // Red de seguridad para los albergues que YA existen: su perfil se creó
    // antes de que guardar la ciudad exigiera geocodificarla, así que tiene
    // ciudad pero no coordenadas — y sin coordenadas en el perfil, ninguno
    // de sus animales puede mostrar distancia. Acá se resuelven una vez y
    // se guardan de vuelta en el perfil, así el arreglo es permanente y no
    // hay que pedirle a nadie que vaya a editar su perfil a mano.
    //
    // Silencioso a propósito: si falla (sin señal, o una ciudad vieja que
    // ya no geocodifica), publicar sigue funcionando igual, solo que ese
    // animal queda sin distancia — exactamente como está hoy. Nunca debe
    // trabar la publicación por un dato que es un extra.
    if (_latitud != null || ciudad.isEmpty) return;
    try {
      final resuelta = await UbicacionService.desdeTexto(ciudad);
      if (resuelta == null || !mounted) return;
      setState(() {
        _latitud = resuelta.lat;
        _longitud = resuelta.lng;
        if (resuelta.paisCodigo.isNotEmpty) _paisCodigo = resuelta.paisCodigo;
      });
      await UsuariosRepository().completarCoordenadas(
        uid: uid,
        latitud: resuelta.lat,
        longitud: resuelta.lng,
      );
    } catch (_) {}
  }

  /// Aviso con botón que lleva derecho al ajuste que hace falta —
  /// "Habilítalo en Ajustes" a secas no dice QUÉ tocar ni A DÓNDE ir.
  /// `marcarVolviendoDeAjustes()` (ReintentoUbicacionTrasAjustes) es lo que
  /// habilita el reintento automático al volver.
  void _avisarConAjustes(String mensaje, Future<bool> Function() abrirAjustes) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: msgError,
        action: SnackBarAction(
          label: 'Abrir Ajustes',
          textColor: Colors.white,
          onPressed: () {
            marcarVolviendoDeAjustes();
            abrirAjustes();
          },
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  /// GPS-first: un rescate se publica desde donde está el animal, así que
  /// acá la ubicación se detecta sola al abrir la pantalla (ver initState) y
  /// el texto es el respaldo, no el camino principal. `precision: high` por
  /// el mismo motivo: la distancia que va a ver cada adoptante sale de acá.
  ///
  /// Toda la secuencia de servicio/permiso/GPS/geocoding y sus reintentos
  /// vive en UbicacionService. Lo único que queda acá es la UI, que es lo
  /// que de verdad distingue a esta pantalla: avisos con botón a Ajustes, y
  /// la ubicación como algo opcional que nunca bloquea publicar.
  Future<void> _obtenerUbicacionGPS() async {
    // Limpia cualquier aviso de un intento anterior (ej. "permiso
    // bloqueado" todavía en pantalla) antes de mostrar el resultado de
    // este — sin esto, reintentar varias veces (o el reintento automático
    // al volver de Ajustes) los apilaba uno atrás de otro.
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _detectandoUbicacion = true);

    final resultado = await UbicacionService.actual(
      conCiudad: true,
      precision: LocationAccuracy.high,
    );

    // La detección puede tardar y la usuaria puede haber salido de la
    // pantalla mientras tanto (setState tras dispose es una excepción).
    if (!mounted) return;
    setState(() => _detectandoUbicacion = false);

    if (!resultado.ok) {
      switch (resultado.fallo!) {
        case FalloUbicacion.servicioApagado:
          // El GPS del sistema apagado no es lo mismo que el permiso de la
          // app: lleva a los ajustes de ubicación del teléfono, no a los de
          // la app.
          _avisarConAjustes(
            'Activa el GPS en tu dispositivo',
            Geolocator.openLocationSettings,
          );
        case FalloUbicacion.permisoBloqueado:
          _avisarConAjustes(
            'Permiso de ubicación bloqueado.',
            Geolocator.openAppSettings,
          );
        case FalloUbicacion.permisoDenegado:
          // Acaba de decir que no: se le puede volver a preguntar tocando
          // el campo otra vez, no hace falta un aviso rojo.
          break;
        case FalloUbicacion.sinRespuesta:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo detectar tu ubicación. Podés tocar para '
                'reintentar, o publicar igual sin ubicación exacta.',
              ),
              backgroundColor: msgError,
            ),
          );
      }
      return;
    }

    setState(() {
      _latitud = resultado.posicion!.latitude;
      _longitud = resultado.posicion!.longitude;
      // El orden importa: escribir el texto dispara el listener que prende
      // _ubicacionTocadaAMano, así que el reset va DESPUÉS. Acá texto y
      // coordenadas quedan sincronizados por definición (salieron del mismo
      // punto), que es justo lo contrario de una edición a mano.
      _lugarCtl.text = resultado.ciudad;
      _ubicacionTocadaAMano = false;
      _paisCodigo = resultado.paisCodigo;
    });
  }

  // Cuando la usuaria confirma "Publicar igual" habiendo un duplicado, se
  // guarda el rastro en el nuevo doc (con qué otro animal se cruzó y
  // cuándo) — un aviso que se puede ignorar sin dejar huella se siente
  // como "¿entonces para qué avisó?", y sin este dato no hay forma de
  // encontrar después, desde la base, qué publicaciones fueron duplicados
  // confirmados a propósito para poder limpiarlas.
  String? _duplicadoDeId;

  Future<void> _publicar() async {
    if (_fotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes agregar al menos una foto del animal'),
          backgroundColor: msgError,
        ),
      );
      return;
    }
    _duplicadoDeId = null;
    // El spinner arranca ACÁ, antes del chequeo de duplicado (una consulta
    // a Firestore de TODOS tus animales publicados bajo este rol, que
    // tarda más cuanto más historial tengas — un albergue con muchos
    // animales ya publicados la nota más) — no recién en publicarConFotos.
    // Antes el botón se quedaba con su apariencia normal, sin ningún
    // spinner ni aviso, durante todo ese chequeo (y el diálogo de GPS más
    // abajo, si aplica): parecía que tocar "Publicar" no había hecho nada,
    // aunque sí estuviera trabajando. Hallazgo real de Eliza: "se demora
    // mucho en almacenarlo" al publicar sin GPS y al publicar como
    // albergue — los dos casos pasan por este mismo tramo silencioso.
    setState(() => _publicando = true);
    // Aviso, no bloqueo: si ya tenés otro animal publicado con este mismo
    // nombre EN ESTE MISMO ROL, lo más común es que sea una carga duplicada
    // por accidente — pero un nombre repetido entre dos animales reales
    // también puede pasar, así que se deja publicar igual si es a
    // propósito. No cruza rescatista con albergue de la misma cuenta: son
    // dos "negocios" distintos aunque el login sea el mismo.
    final nombreIngresado = _nombreCtl.text.trim();
    if (nombreIngresado.isNotEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final duplicado = await RescatesRepository().buscarDuplicado(
        uid: uid,
        nombre: nombreIngresado,
        role: widget.esAlbergue ? CreatorRole.albergue : CreatorRole.rescatista,
        especie: _especie,
      );
      if (!mounted) return;
      if (duplicado != null) {
        // 3 salidas en vez de 2: "Ver ficha existente" además de
        // cancelar/continuar, para no dejar a la usuaria adivinando cuál
        // es el otro animal — antes solo podía cancelar y buscarlo ella
        // misma en "Mis animales".
        final accion = await showDialog<String>(
          context: context,
          builder: (dlgCtx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Posible animal duplicado'),
            content: Text(
              'Ya tenés otro animal llamado "$nombreIngresado" '
              '($_especie). Si es a propósito (dos animales distintos con '
              'el mismo nombre, uno que volvió, etc.) podés publicar igual. '
              'Si fue sin querer, revisá la ficha existente primero.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, 'cancelar'),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, 'ver'),
                child: const Text('Ver ficha existente'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, 'continuar'),
                child: const Text(
                  'Publicar igual',
                  style: TextStyle(color: appTeal),
                ),
              ),
            ],
          ),
        );
        if (accion == 'ver') {
          if (!mounted) return;
          setState(() => _publicando = false);
          context.push(
            AppRoutes.editarRescate,
            extra: (docId: duplicado.id, data: duplicado.data()),
          );
          return;
        }
        if (accion != 'continuar') {
          setState(() => _publicando = false);
          return;
        }
        _duplicadoDeId = duplicado.id;
      }
    }
    // El diálogo de "posible duplicado" de arriba también es un await —
    // sin este chequeo, si la persona salía de la pantalla justo mientras
    // decidía "Publicar igual", el showDialog de abajo (unas líneas más)
    // usaba un context que ya no era válido (use_build_context_synchronously,
    // hallazgo real de la auditoría previa a subir a Play).
    if (!mounted) return;
    // Si el texto de ubicación se tocó a mano (nunca se usó el ícono de
    // GPS, o se usó y DESPUÉS se retocó el texto), hay que validarlo contra
    // un geocodificador real antes de guardar — sin esto, cualquier texto
    // (incluida "verduras") se guardaba tal cual, sin haber existido nunca
    // de verdad. El ícono de detección automática es un atajo para no
    // escribir a mano, no la única barrera contra datos falsos — esa
    // barrera tiene que vivir acá, en la validación, sea cual sea el
    // camino que se usó para llegar al texto. Mismo patrón ya probado en
    // editar_rescate_screen.dart, albergue_perfil_screen.dart y
    // aliado_perfil_screen.dart.
    if (_ubicacionTocadaAMano && _lugarCtl.text.trim().isNotEmpty) {
      String? errorUbicacion;
      try {
        // null y excepción significan cosas distintas (ver desdeTexto): lo
        // primero es "eso no existe como lugar" y bloquea con un mensaje
        // puntual; lo segundo es "no se pudo verificar", que bloquea con
        // otro texto para no confundir un problema de señal con un dato
        // inventado.
        final resultado = await UbicacionService.desdeTexto(
          _lugarCtl.text.trim(),
        );
        if (resultado == null) {
          errorUbicacion =
              'No encontramos ese lugar. Revisá cómo lo escribiste.';
        } else {
          // Un texto mal escrito puede coincidir con OTRO lugar real del
          // mundo (no da null) — hallazgo real de Eliza escribiendo
          // "Nedellin" y quedando guardado a 9077km de Medellín.
          if (!mounted) return;
          final confirmo = await confirmarCiudadResuelta(
            context,
            escribiste: _lugarCtl.text.trim(),
            resuelta: resultado.ciudadResuelta,
            paisCodigo: resultado.paisCodigo,
            region: resultado.regionResuelta,
          );
          if (!confirmo) {
            if (!mounted) return;
            setState(() => _publicando = false);
            return;
          }
          _latitud = resultado.lat;
          _longitud = resultado.lng;
          _ubicacionTocadaAMano = false;
          // Vacío si el país no se pudo resolver: se conserva el que ya
          // hubiera en vez de pisarlo con nada.
          if (resultado.paisCodigo.isNotEmpty)
            _paisCodigo = resultado.paisCodigo;
        }
      } catch (_) {
        errorUbicacion =
            'No pudimos verificar esa ubicación. Revisá tu conexión e intentá de nuevo.';
      }
      if (errorUbicacion != null) {
        if (!mounted) return;
        setState(() => _publicando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorUbicacion), backgroundColor: msgError),
        );
        return;
      }
    }
    // La ubicación ya no bloquea la publicación — antes, si el GPS fallaba
    // o tardaba (señal débil, permiso recién concedido, lo que sea), el
    // rescatista quedaba sin poder publicar y sin un aviso claro de por qué.
    // Ahora se avisa y se deja elegir: publicar igual (sin distancia en el
    // feed hasta que se agregue la ubicación editando) o cancelar y reintentar.
    // mounted otra vez acá: la validación de arriba agregó sus propios
    // await (geocodificarCiudad, placemarkFromCoordinates) después del
    // último chequeo — mismo tipo de bug que ya se encontró en la
    // auditoría previa a subir a Play (ver el diálogo de duplicado, más
    // arriba en esta función).
    if (!mounted) return;
    if (_latitud == null && !widget.esAlbergue) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (dlgCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Sin ubicación detectada'),
          content: const Text(
            'No se detectó tu ubicación GPS. Podés publicar igual. El animal '
            'no va a aparecer con distancia en el feed hasta que agregues la '
            'ubicación más tarde, editando la publicación.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx, false),
              child: const Text('Volver y detectar de nuevo'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx, true),
              child: const Text(
                'Publicar sin ubicación',
                style: TextStyle(color: appTeal),
              ),
            ),
          ],
        ),
      );
      // "Volver y detectar de nuevo" antes solo cerraba el diálogo y
      // dejaba al rescatista de nuevo en el formulario sin indicar qué
      // hacer — el botón decía "reintentar" pero no reintentaba nada.
      // Ahora dispara la detección de GPS de una, en vez de obligarlo a
      // encontrar y tocar el campo de ubicación por su cuenta.
      if (continuar != true) {
        setState(() => _publicando = false);
        if (mounted && !_detectandoUbicacion) _obtenerUbicacionGPS();
        return;
      }
    }
    setState(() => _progreso = 0);
    iniciarTimerTardando(const Duration(seconds: 6));

    try {
      // Las dos fotos se normalizan en paralelo — normalizarFoto() corre
      // en su propio isolate (compute()), así que esto sí es paralelismo
      // real, no solo dos await seguidos en el mismo hilo.
      final normalizadas = await Future.wait([
        normalizarFoto(_fotos[0].path),
        if (_fotos.length > 1) normalizarFoto(_fotos[1].path),
      ]);

      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      var nombrePublicador =
          FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista';
      String? fotoPublicadorBase64;
      String? fotoPublicadorUrl;
      if (widget.esAlbergue) {
        final userDoc = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .get();
        final albergueNombre = userDoc.data()?['albergueNombre'] as String?;
        if (albergueNombre != null && albergueNombre.isNotEmpty)
          nombrePublicador = albergueNombre;
        fotoPublicadorBase64 = userDoc.data()?['fotoBase64'] as String?;
      } else {
        fotoPublicadorUrl = FirebaseAuth.instance.currentUser?.photoURL;
      }

      // "Crear doc sin fotos → subir en paralelo → vincular", con rollback
      // automático si algo falla, vive en RescatesRepository.publicarConFotos
      // — antes esa secuencia estaba duplicada acá y en
      // subir_lote_screen.dart (hallazgo de auditoría de código).
      final resultado = await RescatesRepository().publicarConFotos(
        uid: uid,
        role: widget.esAlbergue ? CreatorRole.albergue : CreatorRole.rescatista,
        datos: {
          'nombre': _nombreCtl.text.trim(),
          'especie': _especie,
          'raza': _tipoRaza == 'Criolla'
              ? 'Criolla'
              : _razaCtl.text.trim().isEmpty
              ? 'Raza definida'
              : _razaCtl.text.trim(),
          'estado': _estado,
          'urgencia': _urgencia,
          'ubicacion': _lugarCtl.text.trim(),
          'descripcion': _descCtl.text.trim(),
          'estadoAdopcion': 'Rescatado',
          'rescatistaNombre': nombrePublicador,
          if (fotoPublicadorBase64 != null)
            'rescatistaFotoBase64': fotoPublicadorBase64,
          if (fotoPublicadorUrl != null) 'rescatistaFotoUrl': fotoPublicadorUrl,
          if (_latitud != null) 'latitud': _latitud,
          if (_longitud != null) 'longitud': _longitud,
          if (_paisCodigo.isNotEmpty) 'paisCodigo': _paisCodigo,
          'edad': _edad,
          'genero': _genero,
          'energia': _energia,
          'tamano': _tamano,
          'okConNinos': _okNinos == 'Sí',
          'okConMascotas': _okMascotas == 'Sí',
          'requiereExperiencia': _requiereExp == 'Sí',
          // String, no bool: a diferencia de los de arriba, acá "Aún no lo
          // sé" es una tercera respuesta honesta y real, no una falta de
          // dato — un animal recién rescatado de la calle todavía no pasó
          // por veterinario cuando se publica.
          'vacunado': _vacunado,
          'desparasitado': _desparasitado,
          if (_duplicadoDeId != null) 'duplicadoDeId': _duplicadoDeId,
          if (_duplicadoDeId != null)
            'duplicadoConfirmadoEn': FieldValue.serverTimestamp(),
        },
        fotos: normalizadas,
        onProgreso: (p) {
          if (mounted) setState(() => _progreso = p);
        },
      );

      FirebaseAnalytics.instance
          .logEvent(
            name: 'animal_publicado',
            parameters: {
              'especie': _especie,
              'creado_por': widget.esAlbergue ? 'albergue' : 'rescatista',
            },
          )
          .catchError((_) {});

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('¡Rescate publicado! 🐾'),
          content: Text(
            '${_nombreCtl.text.isEmpty ? "El animal" : _nombreCtl.text} '
            'fue publicado con urgencia $_urgencia'
            '${_lugarCtl.text.isNotEmpty ? ' en ${_lugarCtl.text}' : ''}.'
            '${resultado.foto2Fallo ? ' La segunda foto no se pudo subir. Podés agregarla después editando la publicación.' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text(
                'Ver rescates',
                style: TextStyle(color: appTeal),
              ),
            ),
          ],
        ),
      );
    } catch (_) {
      // El rollback (borrar doc + fotos si algo falló a mitad de camino)
      // ya lo hace RescatesRepository.publicarConFotos internamente —
      // acá solo queda avisar.
      if (!mounted) return;
      // Mismo estilo y comportamiento que subir_lote_screen.dart (a
      // propósito, ver ese archivo): vuelve a la pantalla principal en vez
      // de dejar a la persona parada en el formulario con el error — antes
      // los dos flujos (uno y en lote) reaccionaban distinto ante la misma
      // falla de conexión, algo que reportó Eliza probando en modo avión.
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo publicar ${_nombreCtl.text.isEmpty ? "el animal" : _nombreCtl.text}. '
            'Revisá tu conexión e intentá de nuevo.',
          ),
          backgroundColor: msgError,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      cancelarTimerTardando();
      if (mounted)
        setState(() {
          _publicando = false;
          tardandoMucho = false;
        });
    }
  }

  // Sin esto, un aviso como "Activa el GPS en tu dispositivo" (duration: 8s)
  // seguía visible sobre la pantalla de ATRÁS si la persona volvía antes de
  // que se cerrara solo — MaterialApp usa un solo ScaffoldMessenger para
  // toda la app por default, así que un SnackBar no "pertenece" a la
  // pantalla que lo mostró. Capturado en didChangeDependencies (no en
  // dispose directamente): ScaffoldMessenger.of(context) necesita un
  // context todavía válido en el árbol, y dispose() ya no lo garantiza.
  // Hallazgo real de Eliza: "estoy en la pagina inicial del rescatista y el
  // mensaje sigue ahi".
  ScaffoldMessengerState? _scaffoldMessenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    // El removeObserver de WidgetsBindingObserver ahora lo hace
    // ReintentoUbicacionTrasAjustes.dispose(), alcanzado por el
    // super.dispose() de acá abajo.
    _scaffoldMessenger?.clearSnackBars();
    _nombreCtl.dispose();
    _lugarCtl.dispose();
    _descCtl.dispose();
    _razaCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(
          children: [
            _appBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _section('Fotos del animal'),
                    const SizedBox(height: 10),
                    _fotoGrid(),
                    const SizedBox(height: 20),
                    _campoNombre(),
                    const SizedBox(height: 16),
                    _section('Raza'),
                    const SizedBox(height: 8),
                    _chips(
                      _tipoRazaOpts,
                      _tipoRaza,
                      (v) => setState(() {
                        _tipoRaza = v;
                        _razaCtl.clear();
                      }),
                      appTeal,
                    ),
                    if (_tipoRaza == 'Raza definida') ...[
                      const SizedBox(height: 10),
                      _field(
                        '¿Cuál raza?',
                        _razaCtl,
                        hint: 'ej. Golden Retriever, Siamés...',
                      ),
                    ],
                    const SizedBox(height: 16),
                    _section('Especie'),
                    const SizedBox(height: 8),
                    _chips(
                      _especies,
                      _especie,
                      (v) => setState(() => _especie = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('Edad aproximada'),
                    const SizedBox(height: 8),
                    _chips(
                      _edades,
                      _edad,
                      (v) => setState(() => _edad = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('Género'),
                    const SizedBox(height: 8),
                    _chips(
                      _generos,
                      _genero,
                      (v) => setState(() => _genero = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('Estado de salud'),
                    const SizedBox(height: 8),
                    _chips(
                      _estados,
                      _estado,
                      (v) => setState(() => _estado = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('¿Está vacunado?'),
                    const SizedBox(height: 8),
                    _chips(
                      _saludOpts,
                      _vacunado,
                      (v) => setState(() => _vacunado = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('¿Está desparasitado?'),
                    const SizedBox(height: 8),
                    _chips(
                      _saludOpts,
                      _desparasitado,
                      (v) => setState(() => _desparasitado = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('Urgencia'),
                    const SizedBox(height: 8),
                    _chips(
                      _urgencias,
                      _urgencia,
                      (v) => setState(() => _urgencia = v),
                      _urgenciaColor(_urgencia),
                    ),
                    const SizedBox(height: 28),
                    _sectionLabel('Compatibilidad para adopción'),
                    const SizedBox(height: 4),
                    Text(
                      'Estas etiquetas ayudan a encontrar el hogar ideal',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _section('Nivel de energía'),
                    const SizedBox(height: 8),
                    _chips(
                      _energias,
                      _energia,
                      (v) => setState(() => _energia = v),
                      const Color(0xFF7C4DFF),
                    ),
                    const SizedBox(height: 20),
                    _section('Tamaño'),
                    const SizedBox(height: 8),
                    _chips(
                      _tamanos,
                      _tamano,
                      (v) => setState(() => _tamano = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('¿Es amigable con niños?'),
                    const SizedBox(height: 8),
                    _chips(
                      _siNoOpts,
                      _okNinos,
                      (v) => setState(() => _okNinos = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('¿Es sociable con otros animales?'),
                    const SizedBox(height: 8),
                    _chips(
                      _siNoOpts,
                      _okMascotas,
                      (v) => setState(() => _okMascotas = v),
                      appTeal,
                    ),
                    const SizedBox(height: 20),
                    _section('¿Requiere adoptante con experiencia?'),
                    const SizedBox(height: 8),
                    _chips(
                      _siNoOpts,
                      _requiereExp,
                      (v) => setState(() => _requiereExp = v),
                      appOrange,
                    ),
                    const SizedBox(height: 28),
                    if (!widget.esAlbergue) ...[
                      _section('Ubicación'),
                      const SizedBox(height: 8),
                      _locationField(),
                      const SizedBox(height: 20),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Descripción',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            final nombre = _nombreCtl.text.trim().isNotEmpty
                                ? _nombreCtl.text.trim()
                                : '[Nombre]';
                            final plantilla =
                                '$nombre fue encontrado/a [contá cómo o dónde lo/la encontraste]. '
                                'Lo/la que lo/la hace único/a es [una costumbre, gesto o anécdota que lo/la describa]. '
                                'Ya pasó por mucho. Ahora solo le falta alguien que decida quedarse. '
                                '¿Serás vos?';
                            _descCtl.value = TextEditingValue(
                              text: plantilla,
                              selection: TextSelection.collapsed(
                                offset: plantilla.length,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: appTeal.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: appTeal.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('✨', style: TextStyle(fontSize: 13)),
                                SizedBox(width: 4),
                                Text(
                                  'Usar plantilla',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: appTeal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _field(
                      '',
                      _descCtl,
                      hint:
                          'Estado del animal, dónde fue encontrado, necesidades especiales...',
                      maxLines: 5,
                      maxLength: 1000,
                    ),
                    const SizedBox(height: 28),
                    _publishBtn(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appBar(BuildContext ctx) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
    child: Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          tooltip: 'Volver',
          // Apagado mientras se publica: sin esto, se podía salir de la
          // pantalla con el publish todavía corriendo de fondo — si terminaba
          // bien, el animal quedaba publicado sin que la persona lo viera (ni
          // el SnackBar de éxito, que ya no tiene dónde mostrarse), así que
          // podía creer que falló y reintentar, publicando el mismo animal
          // dos veces. Hallazgo de auditoría de código.
          onPressed: _publicando ? null : () => Navigator.pop(ctx),
        ),
        const Expanded(
          child: Text(
            'Subir un rescate',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: appInk,
              fontFamily: 'Baloo2',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _section(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: Color(0xFF222222),
    ),
  );

  Widget _sectionLabel(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: Color(0xFF7C4DFF),
    ),
  );

  Widget _fotoGrid() {
    final items = List<Widget>.from(_fotos.map((f) => _fotoThumb(f)));
    if (_fotos.length < 2) items.add(_fotoAddBtn());
    return Wrap(spacing: 10, runSpacing: 10, children: items);
  }

  Widget _fotoThumb(XFile f) => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(f.path),
          width: 90,
          height: 90,
          fit: BoxFit.cover,
        ),
      ),
      Positioned(
        top: 4,
        right: 4,
        child: GestureDetector(
          onTap: () => setState(() => _fotos.remove(f)),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(3),
            child: const Icon(Icons.close, size: 14, color: Colors.white),
          ),
        ),
      ),
    ],
  );

  Widget _fotoAddBtn() => GestureDetector(
    onTap: _mostrarOpcionesFoto,
    child: Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: appTeal.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_a_photo_outlined, color: appTeal, size: 28),
          const SizedBox(height: 4),
          Text(
            _fotos.isEmpty ? 'Agregar' : '${_fotos.length}/2',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    ),
  );

  // ChipsSeleccionables (widgets/chips_seleccionables.dart) — antes esto tenía su propia copia de
  // la grilla, una de tres iguales repartidas en otras tantas pantallas.
  // Ver el comentario en tipo_animal_screen.dart/_grupo para el hallazgo
  // completo.
  Widget _chips(
    List<String> options,
    String selected,
    ValueChanged<String> onSelect,
    Color activeColor,
  ) => ChipsSeleccionables(
    opciones: options,
    seleccion: selected,
    onSeleccionar: onSelect,
    colorActivo: activeColor,
    colorInactivo: Colors.white.withValues(alpha: 0.85),
    duracion: const Duration(milliseconds: 160),
  );

  // maxLength sin tope antes: un pegado gigante en nombre/descripción se
  // guardaba entero, inflando el tamaño del documento sin ninguna razón
  // real. Hallazgo de auditoría de código.
  // Mismo estilo exacto que editar_rescate_screen.dart (_campo): el campo
  // de nombre se ve distinto al crear y al editar un animal, aunque es la
  // misma pregunta en las dos pantallas (rescatista Y albergue, esta
  // pantalla es compartida por las dos — ver widget.esAlbergue). Pedido
  // real de Eliza: que se vea "exactamente el mismo campo de Nombre" en
  // toda la app. Campo aparte en vez de tocar _field() de acá abajo, que
  // sigue usándose para Raza y otros campos que no pidió cambiar.
  Widget _campoNombre() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Nombre del animal (opcional)',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: appInk,
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _nombreCtl,
        maxLength: 30,
        decoration: InputDecoration(
          hintText: 'ej. Luna, sin nombre...',
          hintStyle: TextStyle(color: Colors.grey.shade400),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    ],
  );

  Widget _field(
    String label,
    TextEditingController ctl, {
    String hint = '',
    int maxLines = 1,
    int? maxLength,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _section(label),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
            ),
          ],
        ),
        child: TextField(
          controller: ctl,
          maxLines: maxLines,
          maxLength: maxLength,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    ],
  );

  Widget _locationField() {
    final obtenida = _latitud != null;
    final ciudad = _lugarCtl.text;
    return GestureDetector(
      onTap: _detectandoUbicacion ? null : _obtenerUbicacionGPS,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: obtenida
              ? appTeal.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: obtenida ? appTeal : Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          children: [
            if (_detectandoUbicacion)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: appTeal,
                ),
              )
            else
              Icon(
                obtenida ? Icons.check_circle : Icons.my_location,
                color: obtenida ? appTeal : Colors.grey.shade700,
                size: 22,
              ),
            const SizedBox(width: 12),
            Text(
              _detectandoUbicacion
                  ? 'Detectando ubicación...'
                  : obtenida
                  ? (ciudad.isNotEmpty ? '$ciudad ✓' : 'Ubicación detectada ✓')
                  : 'Toca para detectar tu ubicación',
              style: TextStyle(
                fontSize: 14,
                color: obtenida || _detectandoUbicacion
                    ? appTeal
                    : Colors.grey.shade700,
                fontWeight: obtenida ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _publishBtn() => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: _publicando ? null : _publicar,
      style: ElevatedButton.styleFrom(
        backgroundColor: appDark,
        foregroundColor: Colors.white,
        // Mientras publica, el botón queda deshabilitado (onPressed: null)
        // para no permitir un segundo toque — pero sin esto, Material pinta
        // un botón deshabilitado con SUS propios colores grises de tema en
        // vez de los de acá arriba, y el texto blanco de "tardando más de
        // lo normal" quedaba casi ilegible sobre ese gris apagado. Mismos
        // colores que el botón habilitado: sigue pareciendo el mismo botón,
        // solo que ocupado. Hallazgo real de Eliza, en modo avión.
        disabledBackgroundColor: appDark,
        disabledForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      child: _publicando
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                        value: _progreso > 0 ? _progreso : null,
                      ),
                    ),
                    if (_progreso > 0) ...[
                      const SizedBox(width: 10),
                      Text(
                        '${(_progreso * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
                // Sin señal, la subida no tiene bytes que transferir todavía
                // — _progreso se queda en 0 y el círculo gira sin ningún
                // texto durante hasta 45s (el timeout de la foto). Sin este
                // aviso parecía que la app estaba colgada.
                if (tardandoMucho) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Esto está tardando más de lo normal. Revisá tu conexión',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ],
            )
          : const Text(
              'Publicar rescate 🐾',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
    ),
  );
}
