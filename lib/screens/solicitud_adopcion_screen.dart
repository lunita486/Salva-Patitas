import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/sp_widgets.dart';
import '../widgets/chips_seleccionables.dart';
import '../domain/reglas_negocio.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/fotos.dart';
import '../data/creator_role.dart';
import '../data/solicitudes_repository.dart';
import '../data/preferencias_repository.dart';

class SolicitudAdopcionScreen extends StatefulWidget {
  final Map<String, dynamic> animal;
  const SolicitudAdopcionScreen({super.key, required this.animal});
  @override
  State<SolicitudAdopcionScreen> createState() =>
      _SolicitudAdopcionScreenState();
}

class _SolicitudAdopcionScreenState extends State<SolicitudAdopcionScreen> {
  final _solicitudesRepo = SolicitudesRepository();
  int _step = 0;

  String _vivienda = '';
  String _ninos = '';
  String _mascotas = '';
  String _experienciaPrevia = '';
  final _integrantesCtl = TextEditingController();
  final _horasCtl = TextEditingController();
  final _motivacionCtl = TextEditingController();
  late String _tipoSolicitud;
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  bool _enviando = false;
  bool _verificando = true;
  bool _errorVerificacion = false;
  bool _yaAplico = false;
  String _estadoExistente = '';

  @override
  void initState() {
    super.initState();
    _tipoSolicitud =
        (widget.animal['tipoSolicitud'] as String?) == 'hogar_de_paso'
        ? 'hogar_de_paso'
        : 'adopcion';
    _verificarDuplicado();
  }

  Future<void> _verificarDuplicado() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _verificando = false);
      return;
    }
    setState(() {
      _verificando = true;
      _errorVerificacion = false;
    });
    try {
      final estado = await _solicitudesRepo.estadoExistente(
        uid: uid,
        animalNombre: widget.animal['nombre'] as String,
        rescateId: widget.animal['rescateId'] as String?,
      );
      if (!mounted) return;
      setState(() {
        _yaAplico = estado != null;
        _estadoExistente = estado ?? '';
        _verificando = false;
      });
    } catch (_) {
      // Antes esto no tenía ningún try/catch: si estadoExistente() fallaba
      // (o, sin este arreglo, se quedaba esperando sin señal — ver el
      // mismo respaldo por caché que ya tiene _hayAlguna en el
      // repositorio), _verificando quedaba en true para siempre y esta
      // pantalla — el paso final para pedir adoptar, la acción más
      // importante de un adoptante en toda la app — se quedaba en un
      // spinner sin botón de volver ni de reintentar. Hallazgo de
      // auditoría de código.
      if (!mounted) return;
      setState(() {
        _verificando = false;
        _errorVerificacion = true;
      });
    }
  }

  static const _viviendaOpts = [
    'Finca',
    'Casa con jardín',
    'Casa sin jardín',
    'Apartamento con balcón',
    'Apartamento sin área exterior',
  ];
  static const _ninosOpts = ['Sí', 'No'];
  static const _mascotasOpts = ['Sí', 'No'];
  static const _experienciaOpts = ['Sí', 'No, sería mi primera mascota'];

  /// El tipo se compara en varios lugares de esta pantalla (qué preguntar,
  /// si pedir fechas, si el formulario está completo). Con nombre, para no
  /// repetir el literal.
  bool get _esHogarDePaso => _tipoSolicitud == 'hogar_de_paso';

  bool get _completo =>
      _integrantesCtl.text.trim().isNotEmpty &&
      _horasCtl.text.trim().isNotEmpty &&
      _vivienda.isNotEmpty &&
      _ninos.isNotEmpty &&
      _mascotas.isNotEmpty &&
      _experienciaPrevia.isNotEmpty &&
      _motivacionCtl.text.trim().isNotEmpty &&
      (!_esHogarDePaso || (_fechaInicio != null && _fechaFin != null));

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    final user = FirebaseAuth.instance.currentUser;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user?.uid)
          .get();
      final nombreAdoptante =
          (userDoc.data()?['nombre'] as String?)?.isNotEmpty == true
          ? userDoc.data()!['nombre'] as String
          : user?.displayName ?? user?.email ?? 'Adoptante';
      await _solicitudesRepo.crear(
        adoptanteUid: user?.uid ?? '',
        rescatistaId: widget.animal['rescatistaId'] as String? ?? '',
        creadoPor: creatorRoleFromFirestore(
          widget.animal['creadoPor'] as String?,
        ),
        datos: {
          'animalNombre': widget.animal['nombre'],
          'rescateId': widget.animal['rescateId'] ?? '',
          'nombre': nombreAdoptante,
          'email': user?.email ?? '',
          'integrantes': _integrantesCtl.text.trim(),
          'horasFuera': _horasCtl.text.trim(),
          'vivienda': _vivienda,
          'tieneNinos': _ninos == 'Sí',
          'tieneMascotas': _mascotas == 'Sí',
          'experienciaPrevia': _experienciaPrevia == 'Sí',
          'motivacion': _motivacionCtl.text.trim(),
          'tipoSolicitud': _tipoSolicitud,
          if (_tipoSolicitud == 'hogar_de_paso' && _fechaInicio != null)
            'fechaInicioHogar': Timestamp.fromDate(_fechaInicio!),
          if (_tipoSolicitud == 'hogar_de_paso' && _fechaFin != null)
            'fechaFinHogar': Timestamp.fromDate(_fechaFin!),
          'fotoUrl': widget.animal['fotoUrl'],
          // `especie` se LEÍA en 6 lugares y no se escribía en ninguno —
          // era el único camino de creación de esta colección, así que el
          // campo no existía nunca. Consecuencia: el chat que nace de
          // aprobar o rechazar esta solicitud se creaba sin especie, y la
          // lista de chats del adoptante cae al default 'Perro' — un gato
          // aparecía con 🐶 en la conversación sobre él mismo.
          'especie': widget.animal['especie'],
          // etiquetas del animal para calcular compatibilidad
          'animalEnergia': widget.animal['energia'],
          'animalTamano': widget.animal['tamano'],
          'animalOkConNinos': widget.animal['okConNinos'],
          'animalOkConMascotas': widget.animal['okConMascotas'],
          'animalRequiereExp': widget.animal['requiereExperiencia'],
        },
      );
      FirebaseAnalytics.instance
          .logEvent(
            name: 'solicitud_enviada',
            parameters: {
              'tipo': _tipoSolicitud,
              'rescatista_id': widget.animal['rescatistaId'] as String? ?? '',
            },
          )
          .catchError((_) {});
      // Guarda el perfil para el score de compatibilidad en el feed. Va en
      // preferencias/{uid} (privado, solo lo lee el dueño) y NO en
      // usuarios/{uid} — ese doc es legible por cualquier usuario logueado
      // (hay perfiles públicos), y estos datos son sensibles: vivienda, si
      // hay niños en casa, cuántas horas queda solo el animal.
      await PreferenciasRepository().actualizar(user?.uid ?? '', {
        'perfilAdopcion': {
          'vivienda': _vivienda,
          'horasFuera': _horasCtl.text.trim(),
          'tieneNinos': _ninos == 'Sí',
          'tieneMascotas': _mascotas == 'Sí',
          'experienciaPrevia': _experienciaPrevia == 'Sí',
        },
      });
      if (!mounted) return;
      setState(() => _step = 2);
    } on YaAplicoException catch (e) {
      // El repositorio frenó un duplicado. Puede pasar sin que sea culpa de
      // nadie: dos toques seguidos en Enviar, o volver atrás y entrar de
      // nuevo. Se muestra como información, no como error, y se refleja en
      // la pantalla para que el botón deje de ofrecer lo que ya está hecho.
      if (!mounted) return;
      setState(() {
        _yaAplico = true;
        _estadoExistente = e.estado;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.sp.msgAdvertencia,
          content: Text(
            e.estado == 'aprobada'
                ? 'Tu solicitud por este animalito ya fue aprobada.'
                : 'Ya tenés una solicitud pendiente por este animalito.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.sp.msgError,
          content: Text('Error al enviar: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  void dispose() {
    _integrantesCtl.dispose();
    _horasCtl.dispose();
    _motivacionCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    if (_verificando) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(child: CircularProgressIndicator(color: c.primary)),
      );
    }
    if (_errorVerificacion) {
      return Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Column(
            children: [
              const SpScreenHeader(title: 'Solicitud'),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        errorFeedState(
                          mensaje:
                              'No pudimos verificar si ya pediste adoptar a '
                              '${widget.animal['nombre']}. Revisá tu conexión e intentá de nuevo.',
                        ),
                        const SizedBox(height: 12),
                        SpButton(
                          label: 'Reintentar',
                          icon: Icons.refresh_rounded,
                          onTap: _verificarDuplicado,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_yaAplico) {
      final aprobada = _estadoExistente == 'aprobada';
      return Scaffold(
        backgroundColor: c.bg,
        body: Stack(
          children: [
            const Positioned.fill(child: SpPawBackground()),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: _mensajeFinal(
                    animal: aprobada ? SpAnimalKind.casa : SpAnimalKind.huella,
                    tono: aprobada ? SpTone.mint : SpTone.peach,
                    titulo: aprobada
                        ? '¡Solicitud aprobada!'
                        : 'Ya enviaste una solicitud',
                    texto: aprobada
                        ? 'Tu solicitud para ${widget.animal['nombre']} fue aprobada. Revisa el chat para coordinar el encuentro.'
                        : 'Tu solicitud para ${widget.animal['nombre']} está pendiente de revisión. Te avisaremos por el chat.',
                    boton: 'Volver',
                    onTap: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: SpPawBackground()),
          SafeArea(
            child: Column(
              children: [
                SpScreenHeader(
                  title: _step == 0
                      ? 'Antes de continuar'
                      : _step == 1
                      ? 'Cuéntanos sobre ti'
                      : '¡Solicitud enviada!',
                  subtitle: _step < 2 ? 'Paso ${_step + 1} de 2' : null,
                  onBack: () {
                    if (_step == 1) {
                      setState(() => _step = 0);
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
                if (_step < 2)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: List.generate(
                        2,
                        (i) => Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 8,
                            margin: EdgeInsets.only(right: i == 0 ? 6 : 0),
                            decoration: BoxDecoration(
                              color: i <= _step ? c.primary : c.surfaceSunken,
                              borderRadius: BorderRadius.circular(
                                SpRadius.full,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: _step == 0
                      ? _stepConciencia()
                      : _step == 1
                      ? _stepCuestionario()
                      : _stepExito(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Animalito 3D, título, texto y un botón: la pantalla de "ya enviaste"
  /// y la de "¡Solicitud enviada!".
  Widget _mensajeFinal({
    required SpAnimalKind animal,
    required SpTone tono,
    required String titulo,
    required String texto,
    required String boton,
    required VoidCallback onTap,
  }) {
    final c = context.sp;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          alignment: Alignment.center,
          decoration: SpDeco.tone(c, tono, radius: SpRadius.full),
          child: SpAnimal(animal, size: 84),
        ),
        const SizedBox(height: 24),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: SpText.title.copyWith(color: c.ink),
        ),
        const SizedBox(height: 10),
        Text(
          texto,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: c.inkMuted, height: 1.55),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: SpButton(label: boton, onTap: onTap),
        ),
      ],
    );
  }

  Widget _stepConciencia() {
    final c = context.sp;
    final nombre = widget.animal['nombre'] as String;
    final fotoUrl = widget.animal['fotoUrl'] as String?;
    final especie = widget.animal['especie'] as String?;
    final esAdopcion = _tipoSolicitud == 'adopcion';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: [
          // FotoAnimal (no recorte): un retrato con el animal abajo se veía
          // como un bloque de color sin ningún animal (caso "Bruno Diaz").
          Container(
            height: 200,
            decoration: SpDeco.card(c, radius: SpRadius.xl),
            clipBehavior: Clip.antiAlias,
            child: fotoUrl != null
                ? FotoAnimal(
                    url: fotoUrl,
                    height: 200,
                    width: double.infinity,
                    fallback: SpFotoVacia(especie: especie, size: 110),
                  )
                : SpFotoVacia(especie: especie, size: 110),
          ),
          const SizedBox(height: 20),
          // Héroe verde con el mensaje de conciencia.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: SpDeco.primary(c, radius: SpRadius.xl, gradient: true),
            child: Column(
              children: [
                SpPaw(
                  size: 30,
                  angle: -12,
                  color: SpDeco.shine.withValues(alpha: .85),
                ),
                const SizedBox(height: 12),
                Text(
                  '${nombreDeAnimal(nombre, enFrase: true)} te está esperando.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: c.onPrimary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Un animal no es un juguete ni decoración.\nTe amará sin condiciones, en los buenos momentos y en los difíciles.\n\nAdoptar es una promesa de por vida.\n\n¿Estás listo?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.onPrimary.withValues(alpha: .8),
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _opcionTipo(
                  titulo: 'Adoptar',
                  animal: SpAnimalKind.casa,
                  tono: SpTone.butter,
                  elegida: esAdopcion,
                  onTap: () => setState(() => _tipoSolicitud = 'adopcion'),
                ),
              ),
              const SizedBox(width: SpSpace.s3),
              Expanded(
                child: _opcionTipo(
                  titulo: 'Hogar de paso',
                  animal: SpAnimalKind.huella,
                  tono: SpTone.sky,
                  elegida: !esAdopcion,
                  onTap: () {
                    // Solo en la transición real hacia hogar_de_paso — no en
                    // cada tap repetido sobre la misma opción ya activa.
                    if (_tipoSolicitud != 'hogar_de_paso') {
                      FirebaseAnalytics.instance
                          .logEvent(name: 'toco_ser_hogar_de_paso')
                          .catchError((_) {});
                    }
                    setState(() => _tipoSolicitud = 'hogar_de_paso');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: SpButton(
              label: esAdopcion ? 'Quiero adoptar' : 'Quiero dar hogar de paso',
              icon: Icons.favorite_rounded,
              onTap: () => setState(() => _step = 1),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: c.inkMuted),
            child: const Text(
              'Aún no estoy seguro/a',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Baldosa de "Adoptar" / "Hogar de paso"; la elegida con borde verde y ✓.
  Widget _opcionTipo({
    required String titulo,
    required SpAnimalKind animal,
    required SpTone tono,
    required bool elegida,
    required VoidCallback onTap,
  }) {
    final c = context.sp;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SpToneBox(
          tone: tono,
          radius: 22,
          padding: const EdgeInsets.symmetric(vertical: 14),
          onTap: onTap,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                SpAnimal(animal, size: 52),
                const SizedBox(height: 6),
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (elegida) ...[
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: c.primary, width: 3),
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 22,
              height: 22,
              decoration: SpDeco.primary(c, radius: SpRadius.full),
              child: Icon(Icons.check_rounded, size: 14, color: c.onPrimary),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepCuestionario() {
    final c = context.sp;
    // La mitad del ancho de la pantalla, no un píxel fijo — pedido explícito
    // de Eliza: "yo quiero que ocupe al menos la mitad de la pantalla".
    final anchoCampoNumerico = MediaQuery.of(context).size.width / 2;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SpNotice(
            fondo: c.primarySoft,
            tinta: c.primaryStrong,
            child: Row(
              children: [
                const Icon(Icons.person_rounded, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    FirebaseAuth.instance.currentUser?.displayName ??
                        'Tu nombre de Google',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  'vía Gmail',
                  style: TextStyle(fontSize: 12, color: c.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpSpace.s4),
          const SpSectionTitle('Tu hogar'),
          const SizedBox(height: SpSpace.s3),
          SpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 3 y 2 dígitos: nadie vive con cientos de personas y un día
                // tiene 24 horas (hallazgo real de Eliza, 2026-08-04).
                _campoTexto(
                  '¿Cuántas personas en casa?',
                  _integrantesCtl,
                  'ej. 3',
                  teclado: TextInputType.number,
                  maxLength: 3,
                  ancho: anchoCampoNumerico,
                ),
                const SizedBox(height: 18),
                _campoTexto(
                  '¿Cuántas horas al día estás fuera de casa?',
                  _horasCtl,
                  'ej. 4',
                  teclado: TextInputType.number,
                  maxLength: 2,
                  ancho: anchoCampoNumerico,
                ),
                const SizedBox(height: 18),
                _pregunta(
                  '¿Dónde vives?',
                  _viviendaOpts,
                  _vivienda,
                  (v) => setState(() => _vivienda = v),
                ),
                const SizedBox(height: 18),
                _pregunta(
                  '¿Tienes niños menores de 8 años?',
                  _ninosOpts,
                  _ninos,
                  (v) => setState(() => _ninos = v),
                ),
                const SizedBox(height: 18),
                _pregunta(
                  '¿Tienes otras mascotas?',
                  _mascotasOpts,
                  _mascotas,
                  (v) => setState(() => _mascotas = v),
                ),
                const SizedBox(height: 18),
                _pregunta(
                  '¿Has tenido mascotas antes?',
                  _experienciaOpts,
                  _experienciaPrevia,
                  (v) => setState(() => _experienciaPrevia = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpSpace.s6),
          SpSectionTitle(_esHogarDePaso ? 'Hogar de paso' : 'Tu motivación'),
          const SizedBox(height: SpSpace.s3),
          SpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // La pregunta y el ejemplo cambian según el tipo: antes, al
                // elegir hogar de paso te preguntaba por qué querías ADOPTARLO.
                _campoTexto(
                  _esHogarDePaso
                      ? '¿Por qué querés darle hogar de paso?'
                      : '¿Por qué quieres adoptarlo?',
                  _motivacionCtl,
                  _esHogarDePaso
                      ? 'ej. Tengo espacio y experiencia, puedo cuidarlo mientras encuentra familia...'
                      : 'ej. Siempre quise tener un perro, tengo espacio y mucho amor...',
                  maxLines: 3,
                  maxLength: 600,
                ),
                if (_esHogarDePaso) ...[
                  const SizedBox(height: 18),
                  _etiqueta('Período del hogar de paso', obligatorio: true),
                  const SizedBox(height: 4),
                  Text(
                    '¿Cuándo puedes recibirlo y hasta cuándo?',
                    style: SpText.caption.copyWith(color: c.inkMuted),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _selectorFecha(
                          label: 'Desde',
                          fecha: _fechaInicio,
                          onPick: (d) => setState(() {
                            _fechaInicio = d;
                            if (_fechaFin != null && _fechaFin!.isBefore(d)) {
                              _fechaFin = null;
                            }
                          }),
                          firstDate: DateTime.now(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _selectorFecha(
                          label: 'Hasta',
                          fecha: _fechaFin,
                          onPick: (d) => setState(() => _fechaFin = d),
                          firstDate: _fechaInicio ?? DateTime.now(),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: SpSpace.s6),
          SizedBox(
            width: double.infinity,
            child: SpButton(
              label: 'Enviar solicitud',
              icon: Icons.send_rounded,
              cargando: _enviando,
              onTap: _completo ? _enviar : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Título de una pregunta, con asterisco coral si es obligatoria.
  Widget _etiqueta(String texto, {bool obligatorio = false}) {
    final c = context.sp;
    return Text.rich(
      TextSpan(
        text: texto,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: c.ink,
        ),
        children: [
          if (obligatorio)
            TextSpan(
              text: ' *',
              style: TextStyle(color: c.accent),
            ),
        ],
      ),
    );
  }

  // maxLength obligatorio (no con default) a propósito: sin tope acá, ni el
  // cliente ni firestore.rules frenaban un pegado gigante en "motivación".
  // Hallazgo de auditoría de código.
  // [ancho]: null = todo el ancho (texto libre). Con un valor, el campo se
  // achica a ese ancho — para 2-3 dígitos no tiene sentido una caja del
  // ancho de la pantalla.
  Widget _campoTexto(
    String titulo,
    TextEditingController ctl,
    String hint, {
    TextInputType teclado = TextInputType.text,
    int maxLines = 1,
    required int maxLength,
    double? ancho,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta(titulo, obligatorio: true),
        const SizedBox(height: 8),
        SizedBox(
          width: ancho,
          child: TextField(
            controller: ctl,
            keyboardType: teclado,
            maxLines: maxLines,
            maxLength: maxLength,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: hint,
              // Sin contador en los campos angostos: Flutter le reserva una
              // línea entera abajo y el campo parecía de varias líneas.
              // Hallazgo real de Eliza.
              counterText: ancho != null ? '' : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _pregunta(
    String titulo,
    List<String> opciones,
    String seleccion,
    ValueChanged<String> onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta(titulo),
        const SizedBox(height: 10),
        ChipsSeleccionables(
          opciones: opciones,
          seleccion: seleccion,
          onSeleccionar: onSelect,
          paddingChip: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
      ],
    );
  }

  Widget _selectorFecha({
    required String label,
    required DateTime? fecha,
    required ValueChanged<DateTime> onPick,
    required DateTime firstDate,
  }) {
    final c = context.sp;
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: fecha ?? firstDate,
          firstDate: firstDate,
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        // El picker puede tardar (o la pantalla cerrarse mientras está
        // abierto) — sin este chequeo, onPick (que hace setState) se llamaba
        // igual sobre un State ya destruido y crasheaba.
        if (picked != null && mounted) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: SpDeco.sunken(c).copyWith(
          border: fecha != null ? Border.all(color: c.primary, width: 2) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: SpText.caption.copyWith(
                color: c.inkMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 15,
                  color: fecha != null ? c.primary : c.inkFaint,
                ),
                const SizedBox(width: 6),
                Text(
                  fecha != null ? formatearFecha(fecha) : 'Seleccionar',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: fecha != null ? c.ink : c.inkFaint,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepExito() {
    final nombre = widget.animal['nombre'] as String;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: _mensajeFinal(
          animal: SpAnimalKind.casa,
          tono: SpTone.mint,
          titulo: '¡Solicitud enviada!',
          texto:
              'Le avisamos a la rescatista.\nPronto sabrás si ${nombreDeAnimal(nombre, enFrase: true)} encontró su hogar contigo.',
          boton: 'Ver más animales',
          onTap: () => Navigator.popUntil(context, (r) => r.isFirst),
        ),
      ),
    );
  }
}
