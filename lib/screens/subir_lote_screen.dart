import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../domain/tareas_en_paralelo.dart';
import '../widgets/tardando_mucho_mixin.dart';
import '../data/contexto_albergue.dart';
import '../data/creator_role.dart';
import '../data/rescates_repository.dart';
import '../data/usuarios_repository.dart';
import '../data/foto_normalizador.dart';
import '../services/ubicacion_service.dart';
import '../widgets/elegir_foto_animal.dart';
import '../widgets/chips_seleccionables.dart';
import '../widgets/sp_widgets.dart';
import '../theme/salva_patitas_theme.dart';

class SubirLoteScreen extends StatefulWidget {
  const SubirLoteScreen({super.key});
  @override
  State<SubirLoteScreen> createState() => _SubirLoteScreenState();
}

class _AnimalDraft {
  XFile foto1;
  XFile? foto2;
  final TextEditingController nombreCtl = TextEditingController();
  final TextEditingController descCtl = TextEditingController();
  String? especieOverride;
  String? urgenciaOverride;
  // foto2 se asigna siempre después, por separado (ver _pickSegundaFoto
  // más abajo) — nunca al construir el draft, así que el constructor no
  // lo recibe como parámetro (el campo en sí sí se usa, y mucho).
  _AnimalDraft({required this.foto1});
  void dispose() {
    nombreCtl.dispose();
    descCtl.dispose();
  }
}

class _SubirLoteScreenState extends State<SubirLoteScreen>
    with TardandoMuchoMixin {
  int _paso = 0;

  String _especie = 'Perro';
  String _urgencia = 'Alta';
  String _ciudad = '';
  double? _latitud;
  double? _longitud;
  String _paisCodigo = '';

  final List<_AnimalDraft> _animales = [];
  bool _publicando = false;
  int _procesados = 0;
  // Mismo motivo que en subir_rescate_screen.dart: sin señal, el contador
  // "Publicando X de N" se queda pegado en el animal que está trabado
  // (hasta 45s en la foto obligatoria) sin ningún otro aviso — parecía
  // colgada.

  @override
  void initState() {
    super.initState();
    _cargarCiudad();
  }

  Future<void> _cargarCiudad() async {
    // Esta pantalla es solo del albergue: el del panel (el de la
    // responsable en modo equipo).
    final uid = contextoAlbergue().albergueId;
    if (uid.isEmpty) return;
    // UsuariosRepository.ubicacionDeAlbergue — la MISMA función que usa el
    // alta individual. Antes acá se leían los mismos campos a mano pero SIN
    // la red de seguridad que repara los perfiles viejos sin coordenadas:
    // el mismo albergue, con el mismo perfil, publicaba animales con
    // distancia y bandera si los cargaba de a uno, y sin nada si los
    // cargaba en lote — y como el lote no reparaba, seguía así siempre.
    final ubi = await UsuariosRepository().ubicacionDeAlbergue(
      uid: uid,
      geocodificar: UbicacionService.desdeTexto,
    );
    if (!mounted) return;
    setState(() {
      _ciudad = ubi.ciudad;
      _latitud = ubi.latitud;
      _longitud = ubi.longitud;
      _paisCodigo = ubi.paisCodigo;
    });
  }

  Future<void> _pickFotos() async {
    final picked = await elegirVariasFotosAnimal(context);
    if (picked.isEmpty) return;
    final pathsExistentes = _animales.map((a) => a.foto1.path).toSet();
    final nuevas = picked
        .where((f) => !pathsExistentes.contains(f.path))
        .toList();
    if (nuevas.isEmpty) return;
    setState(() {
      for (final f in nuevas) _animales.add(_AnimalDraft(foto1: f));
    });
  }

  Future<void> _pickSegundaFoto(int index) async {
    // Antes esto era una copia a mano del picker: forzaba galería (sin
    // ofrecer la cámara, a diferencia de publicar y editar), usaba calidad
    // 80 en vez de 90, y no atrapaba nada. Ver elegirFotoAnimal().
    final img = await elegirFotoAnimal(context);
    if (img != null && mounted) setState(() => _animales[index].foto2 = img);
  }

  Future<void> _publicar() async {
    // El spinner arranca ACÁ, antes de ir a buscar nombres ya publicados
    // (nombresExistentes trae TODOS tus animales bajo el rol albergue —
    // tarda más cuanto más historial tengas) — no recién antes de subir
    // fotos. Antes el botón se quedaba con su apariencia normal durante
    // todo ese chequeo, sin ningún aviso de que ya estaba trabajando.
    // Hallazgo real de Eliza: "también se está tardando" al cargar un
    // animalito para el albergue — mismo tramo silencioso que el alta
    // individual (ver el comentario igual en subir_rescate_screen.dart).
    setState(() => _publicando = true);
    // Se dispara ACÁ, antes del chequeo de duplicados (que puede esperar a
    // que la persona decida en un diálogo) y antes de procesar fotos — es
    // una lectura independiente de las dos cosas (el nombre/logo del
    // albergue no depende de qué decida en el diálogo ni de las fotos), así
    // que arranca temprano en vez de esperar su turno más abajo. Mismo
    // motivo que el mismo arreglo en subir_rescate_screen.dart. Hallazgo
    // real de Eliza: "guardar animalitos se estaba demorando muchísimo".
    final uidParaPerfil = contextoAlbergue().albergueId;
    final userDocFuture = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uidParaPerfil)
        .get();
    // Aviso, no bloqueo, y ANTES de arrancar el lote (no tiene sentido
    // interrumpir a mitad de un lote que ya está publicando). Chequea dos
    // cosas: nombres que ya existen en tus animales publicados como
    // albergue (el lote siempre publica con ese rol — mismo motivo que en
    // el alta individual, ver subir_rescate_screen.dart: no cruza con lo
    // que hayas publicado como rescatista, son dos "negocios" distintos
    // aunque el login sea el mismo), y nombres repetidos dentro del propio
    // lote (sin ir a la red, comparando entre sí). En los dos casos se
    // compara nombre + especie juntos — un "Richard" perro no debería
    // chocar con un "Richard" gato.
    final animalesConNombre = _animales
        .where((a) => a.nombreCtl.text.trim().isNotEmpty)
        .toList();
    // Fuera del if (no solo declarado adentro): publicarUno() más abajo lo
    // necesita para dejar el mismo rastro de auditoría que el alta
    // individual (ver _duplicadoDeId en subir_rescate_screen.dart) en cada
    // animal que se publicó pese al aviso de nombre repetido.
    final repetidos = <String>{};
    if (animalesConNombre.isNotEmpty) {
      final uidActual = uidParaPerfil;
      // Una sola consulta para todo el lote, no una por animal (mismo
      // filtro rescatistaId+creadoPor cada vez — hallazgo de auditoría).
      final existentes = await RescatesRepository().nombresExistentes(
        uid: uidActual,
        role: CreatorRole.albergue,
      );
      for (final a in animalesConNombre) {
        final nombreAnimal = a.nombreCtl.text.trim();
        final especieAnimal = a.especieOverride ?? _especie;
        final clave = '${nombreAnimal.toLowerCase()}_$especieAnimal';
        if (existentes.contains(clave)) {
          repetidos.add(nombreAnimal);
        }
      }
      final vistos = <String>{};
      for (final a in animalesConNombre) {
        final clave =
            '${a.nombreCtl.text.trim().toLowerCase()}_${a.especieOverride ?? _especie}';
        if (!vistos.add(clave)) repetidos.add(a.nombreCtl.text.trim());
      }
      if (repetidos.isNotEmpty) {
        if (!mounted) return;
        final continuar = await showDialog<bool>(
          context: context,
          builder: (dlgCtx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Nombres repetidos'),
            content: Text(
              'Ya tenés (o estás por subir más de una vez en este lote) '
              'un animal llamado: ${repetidos.join(", ")}. Si es a propósito, '
              'podés publicar igual.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, true),
                child: Text(
                  'Publicar igual',
                  style: TextStyle(color: context.sp.primaryStrong),
                ),
              ),
            ],
          ),
        );
        if (continuar != true) {
          if (mounted) setState(() => _publicando = false);
          return;
        }
      }
    }

    // Faltaba: si la persona sale de la pantalla mientras las consultas de
    // arriba todavía estaban en curso (conexión lenta, sin duplicados), el
    // setState() de acá abajo corría igual sobre una pantalla ya cerrada
    // (hallazgo de auditoría de código).
    if (!mounted) return;
    setState(() => _procesados = 0);
    // El umbral crece con la cantidad de animales — todos suben sus fotos
    // al mismo tiempo, así que un lote de 3 mueve más datos en total que
    // uno de 1, y tarda más de forma normal y esperable. Con el límite fijo
    // de 6s (pensado para 1 animal), el aviso de "esto está tardando" salía
    // seguido en lotes de 3+ animales aunque todo estuviera funcionando
    // bien — el bug real que reportó Eliza.
    iniciarTimerTardando(Duration(seconds: 6 + 5 * (_animales.length - 1)));
    final fallidos = <String>[];
    var publicados = 0;
    try {
      final uid = uidParaPerfil;
      var nombre =
          FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista';
      // userDocFuture ya viene corriendo desde el principio de _publicar()
      // — para cuando llegamos acá (después del chequeo de duplicados, que
      // puede haber esperado a un diálogo) este await casi nunca espera de
      // verdad.
      final userDoc = await userDocFuture;
      // UsuariosRepository.nombrePropioDesde — misma regla compartida que
      // el alta individual y los avisos automáticos. Esta pantalla solo la
      // alcanza un albergue (se abre desde albergue_home_screen), de ahí
      // el 'albergue' fijo.
      nombre = UsuariosRepository.nombrePropioDesde(
        datosUsuario: userDoc.data(),
        creadoPor: 'albergue',
        nombreDeLaCuenta: nombre,
      );
      // El logo del albergue ya no se copia adentro de cada animalito: eran
      // ~85 KB de base64 por documento. Lo resuelve AvatarUsuario leyendo
      // usuarios/{uid}. El original no se toca.

      // Cada animal se publica en paralelo, no uno atrás del otro — antes
      // el lote entero esperaba a que el animal 1 terminara (crear doc +
      // subir fotos + actualizar) para recién ahí arrancar el animal 2,
      // sumando los tiempos de cada uno en vez de que corrieran juntos.
      // Con 2 animales, eso duplicaba la espera sin necesidad (el bug real
      // que reportó Eliza: "la creación del lote tarda mucho, y eso que
      // solo cargué dos animalitos"). Cada animal sigue teniendo su propio
      // try/catch y su propio rollback — uno que falla no aborta a los
      // demás, sigan corriendo en paralelo o no.
      Future<void> publicarUno(_AnimalDraft a, int i) async {
        final nombreAnimal = a.nombreCtl.text.trim().isNotEmpty
            ? a.nombreCtl.text.trim()
            : 'Animal ${i + 1}';
        try {
          // normalizarFoto() corre en su propio isolate (compute()) — así
          // el procesamiento de fotos de ESTE animal corre en paralelo
          // real con el de los demás animales del lote, y con la foto 2 de
          // este mismo animal. Antes, aunque los animales se publicaban
          // "en paralelo" con Future.wait, esta parte (CPU, sincrónica, en
          // el isolate principal) igual se serializaba entre todos —
          // el paralelismo era ilusorio en la parte que más tiempo tomaba.
          final normalizadas = await Future.wait([
            normalizarFoto(a.foto1.path),
            if (a.foto2 != null) normalizarFoto(a.foto2!.path),
          ]);

          // "Crear doc sin fotos → subir en paralelo → vincular", con
          // rollback automático si algo falla, vive en
          // RescatesRepository.publicarConFotos — antes esa secuencia
          // estaba duplicada acá y en subir_rescate_screen.dart (hallazgo
          // de auditoría de código).
          await RescatesRepository().publicarConFotos(
            uid: uid,
            autor: contextoAlbergue().camposAutor,
            role: CreatorRole.albergue,
            datos: {
              'nombre': a.nombreCtl.text.trim(),
              'especie': a.especieOverride ?? _especie,
              'raza': 'Criolla',
              'estado': 'Sano',
              'urgencia': a.urgenciaOverride ?? _urgencia,
              'ubicacion': _ciudad,
              if (_latitud != null) 'latitud': _latitud,
              if (_longitud != null) 'longitud': _longitud,
              if (_paisCodigo.isNotEmpty) 'paisCodigo': _paisCodigo,
              'descripcion': a.descCtl.text.trim(),
              'estadoAdopcion': 'Rescatado',
              'rescatistaNombre': nombre,
              // Mismo rastro de auditoría que el alta individual: se avisó
              // un nombre repetido y se publicó igual a propósito — útil
              // para poder encontrar y limpiar duplicados reales después,
              // sin necesitar el id exacto del otro doc (acá puede haber
              // más de un candidato: contra lo ya publicado, o contra otro
              // animal del mismo lote).
              if (repetidos.contains(nombreAnimal))
                'duplicadoConfirmadoEn': FieldValue.serverTimestamp(),
              'edad': 'Adulto',
              'genero': 'No sé',
              'energia': 'Tranquilo',
              'tamano': 'Mediano',
              'okConNinos': true,
              'okConMascotas': true,
              'requiereExperiencia': false,
              // Por defecto, no asumido — igual que en el alta individual,
              // se puede corregir después editando cada animal cuando se
              // sepa de verdad (ej. tras la visita al veterinario).
              'vacunado': 'Aún no lo sé',
              'desparasitado': 'Aún no lo sé',
            },
            fotos: normalizadas,
          );
          FirebaseAnalytics.instance
              .logEvent(
                name: 'animal_publicado',
                parameters: {
                  'especie': a.especieOverride ?? _especie,
                  'creado_por': 'albergue',
                },
              )
              .catchError((_) {});
          publicados++;
        } catch (_) {
          // Este animal falló — no se aborta el lote entero (no tiene
          // sentido perder los N-1 que sí funcionaron). El rollback de
          // este animal ya lo hace publicarConFotos internamente; acá solo
          // queda anotarlo como pendiente y seguir con el resto.
          fallidos.add(nombreAnimal);
        }
        if (mounted) setState(() => _procesados++);
      }

      // Con un tope de 3 a la vez, no todos los animales de una: cada uno
      // normaliza y sube hasta 2 fotos en su propio isolate (ver el
      // comentario de publicarUno más arriba), así que un lote grande sin
      // límite podía disparar decenas de isolates y subidas simultáneas — de
      // sobra para quedarse sin memoria y crashear a mitad de una
      // publicación real (un albergue subiendo 15-20 animales de una, justo
      // el caso de uso de esta pantalla), perdiendo todo lo ya tipeado.
      //
      // Antes ese tope se aplicaba en TANDAS FIJAS: se esperaba a que
      // terminaran los 3 antes de empezar los 3 siguientes. El techo de
      // memoria era el mismo, pero si un animal traía una foto pesada los
      // otros dos lugares quedaban vacíos hasta que ese terminara, y con
      // fotos de tamaños distintos esos huecos se suman. Eliza subiendo
      // varios: "se demoró bastante, 1... 2... 3...".
      //
      // correrConLimite mantiene el mismo tope pero sin huecos: apenas uno
      // termina, entra el siguiente. Ver su doc y sus tests.
      await correrConLimite(
        cuantas: _animales.length,
        limite: 3,
        tarea: (i) => publicarUno(_animales[i], i),
      );

      if (!mounted) return;
      Navigator.pop(context);
      if (fallidos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$publicados animales publicados 🐾'),
            backgroundColor: context.sp.msgExito,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$publicados publicados. No se pudieron publicar: ${fallidos.join(", ")}.',
            ),
            backgroundColor: context.sp.msgAdvertencia,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (_) {
      // Rama poco común (algo falló ANTES/AFUERA del try/catch por animal
      // de más arriba, que ya cubre el caso normal de "se cayó la señal a
      // mitad de un animal puntual") — pero el mensaje y el volver a la
      // pantalla principal tienen que ser los mismos que el resto, no un
      // SnackBar rojo distinto dejando a la persona parada acá.
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No se pudo publicar el lote. Revisá tu conexión e intentá de nuevo.',
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
          _publicando = false;
          tardandoMucho = false;
        });
    }
  }

  @override
  void dispose() {
    for (final a in _animales) a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: SpPawBackground()),
          SafeArea(
            child: Column(
              children: [
                _appBar(),
                _progressBar(),
                Expanded(child: _body()),
                _bottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Volver apagado mientras se publica: sin esto, se podía volver al paso
  // de fotos (paso 0) y borrar/reemplazar la tarjeta de un animal que se
  // está publicando en ese mismo instante de fondo — publicarUno() vuelve a
  // leer nombreCtl/descCtl de ese draft DESPUÉS de un await, y si el
  // dispose() ya corrió en ese hueco, revienta con "used after being
  // disposed". Hallazgo de auditoría de código.
  Widget _appBar() => SpScreenHeader(
    title: 'Subir lote',
    subtitle: _paso == 0
        ? 'Paso 1 de 3 · Selecciona las fotos'
        : _paso == 1
        ? 'Paso 2 de 3 · Datos comunes para todos'
        : 'Paso 3 de 3 · Revisa cada animal',
    onBack: _publicando
        ? () {}
        : () {
            if (_paso > 0) {
              setState(() => _paso--);
            } else {
              Navigator.pop(context);
            }
          },
  );

  Widget _progressBar() {
    final c = context.sp;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: List.generate(
          3,
          (i) => Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 8,
              margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
              decoration: BoxDecoration(
                color: i <= _paso ? c.primary : c.surfaceSunken,
                borderRadius: BorderRadius.circular(SpRadius.full),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (_paso) {
    0 => _pasoFotos(),
    1 => _pasoComunes(),
    _ => _pasoIndividual(),
  };

  // ── Paso 0: Fotos ─────────────────────────────────────────────────────────

  Future<void> _pickFotosConConfirmacion() async {
    if (_animales.isEmpty) {
      await _pickFotos();
      return;
    }
    final c = context.sp;
    Widget opcion({
      required IconData icono,
      required String titulo,
      required String detalle,
      required bool peligro,
      required VoidCallback onTap,
    }) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: peligro ? c.dangerSoft : c.primarySoft,
          borderRadius: BorderRadius.circular(SpRadius.sm),
        ),
        child: Icon(icono, color: peligro ? c.danger : c.primaryStrong),
      ),
      title: Text(
        titulo,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: peligro ? c.danger : c.ink,
        ),
      ),
      subtitle: Text(detalle, style: TextStyle(color: c.inkMuted)),
      onTap: onTap,
    );
    final elegida = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '¿Qué quieres hacer?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 12),
            SpCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  opcion(
                    icono: Icons.add_photo_alternate_outlined,
                    titulo: 'Agregar más fotos',
                    detalle: 'Se suman a las que ya tienes',
                    peligro: false,
                    onTap: () => Navigator.pop(sheetCtx, 'agregar'),
                  ),
                  Divider(height: 1, color: c.line),
                  opcion(
                    icono: Icons.refresh_rounded,
                    titulo: 'Reemplazar todo',
                    detalle: 'Borra las fotos actuales y empieza de nuevo',
                    peligro: true,
                    onTap: () => Navigator.pop(sheetCtx, 'reemplazar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (elegida == null) return;
    if (elegida == 'reemplazar') {
      for (final a in _animales) {
        a.dispose();
      }
      _animales.clear();
    }
    await _pickFotos();
  }

  Widget _pasoFotos() {
    final c = context.sp;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_animales.isEmpty)
            GestureDetector(
              onTap: _pickFotos,
              child: CustomPaint(
                foregroundPainter: SpBordePunteado(c.mintDeep),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: SpDeco.primary(
                          c,
                          radius: 20,
                          gradient: true,
                        ),
                        child: Icon(
                          Icons.add_photo_alternate_rounded,
                          size: 30,
                          color: c.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Toca para seleccionar fotos',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Selecciona varias a la vez: 1 foto = 1 animal',
                        style: SpText.caption.copyWith(
                          color: c.inkMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_animales.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: SpSectionTitle(
                    '${_animales.length} ${_animales.length == 1 ? "animal" : "animales"}',
                  ),
                ),
                SpLink('Agregar más', onTap: _pickFotosConConfirmacion),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _animales.length,
              itemBuilder: (_, i) => Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.file(
                        File(_animales[i].foto1.path),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(SpRadius.full),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Tooltip(
                      message: 'Quitar',
                      child: GestureDetector(
                        // Ver el comentario de _appBar(): borrar un draft
                        // mientras se publica puede tirar abajo un
                        // publicarUno() en curso sobre ESE mismo índice.
                        onTap: _publicando
                            ? null
                            : () => setState(() {
                                _animales[i].dispose();
                                _animales.removeAt(i);
                              }),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: SpDeco.soft(c, radius: SpRadius.full),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: c.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Paso 1: Datos comunes ─────────────────────────────────────────────────

  Widget _pasoComunes() {
    final c = context.sp;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SpNotice(
            fondo: c.primarySoft,
            tinta: c.primaryStrong,
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Se aplican a los ${_animales.length} animales. Puedes editar cada uno después.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpSpace.s4),
          const SpSectionTitle('¿Qué animales son?'),
          const SizedBox(height: SpSpace.s3),
          SpSelectorEspecie(
            especies: const ['Perro', 'Gato', 'Otro'],
            seleccion: _especie,
            onSeleccionar: (v) => setState(() => _especie = v),
          ),
          const SizedBox(height: SpSpace.s6),
          const SpSectionTitle('Urgencia'),
          const SizedBox(height: SpSpace.s3),
          SpCard(
            child: _chips(
              const ['Alta', 'Media', 'Baja'],
              _urgencia,
              (v) => setState(() => _urgencia = v),
              spColorUrgencia(c, _urgencia),
            ),
          ),
        ],
      ),
    );
  }

  // ── Paso 2: Individual ────────────────────────────────────────────────────

  Widget _pasoIndividual() {
    final c = context.sp;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _animales.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        final a = _animales[i];
        final especie = a.especieOverride ?? _especie;
        final urgencia = a.urgenciaOverride ?? _urgencia;
        return Container(
          key: ObjectKey(a),
          padding: const EdgeInsets.all(12),
          decoration: SpDeco.card(c),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fotos (principal + 2da)
                  Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.file(
                          File(a.foto1.path),
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _pickSegundaFoto(i),
                        child: a.foto2 != null
                            ? Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: Image.file(
                                      File(a.foto2!.path),
                                      width: 84,
                                      height: 84,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () =>
                                          setState(() => a.foto2 = null),
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: SpDeco.soft(
                                          c,
                                          radius: SpRadius.full,
                                        ),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 14,
                                          color: c.ink,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : CustomPaint(
                                foregroundPainter: SpBordePunteado(c.mintDeep),
                                child: Container(
                                  width: 84,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: c.primarySoft,
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_a_photo_rounded,
                                        size: 16,
                                        color: c.primaryStrong,
                                      ),
                                      Text(
                                        '2da foto',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: c.primaryStrong,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Animal ${i + 1}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: c.ink,
                                ),
                              ),
                            ),
                            // Mismo motivo que el botón "atrás" de
                            // _appBar(): borrar un draft mientras se publica
                            // puede tirar abajo un publicarUno() en curso
                            // sobre ESE mismo índice.
                            SpMiniButton(
                              icon: Icons.delete_outline_rounded,
                              tooltip: 'Eliminar',
                              danger: true,
                              onTap: _publicando
                                  ? () {}
                                  : () => setState(() {
                                      _animales[i].dispose();
                                      _animales.removeAt(i);
                                    }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: a.nombreCtl,
                          maxLength: 30,
                          decoration: const InputDecoration(
                            hintText: 'Nombre (opcional)',
                          ),
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _selectableMiniChip(
                              valor: especie,
                              opciones: const ['Perro', 'Gato', 'Otro'],
                              tono: spEspecie(especie).$1,
                              onChanged: (v) =>
                                  setState(() => a.especieOverride = v),
                            ),
                            _selectableMiniChip(
                              valor: urgencia,
                              opciones: const ['Alta', 'Media', 'Baja'],
                              tono: switch (urgencia) {
                                'Alta' || 'Media' => SpTone.peach,
                                _ => SpTone.mint,
                              },
                              colorActivo: spColorUrgencia(c, urgencia),
                              onChanged: (v) =>
                                  setState(() => a.urgenciaOverride = v),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Descripción (opcional)',
                      style: SpText.label.copyWith(
                        color: c.inkMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SpButton(
                    label: 'Usar plantilla',
                    icon: Icons.auto_awesome_rounded,
                    suave: true,
                    compacto: true,
                    // Sin el nombre acá adentro — mismo motivo que
                    // subir_rescate_screen.dart: repetirlo como texto plano
                    // dejaba el nombre viejo pegado en la descripción para
                    // siempre después de renombrar. Pedido real de Eliza.
                    onTap: () {
                      const plantilla =
                          'Fue encontrado/a [contá cómo o dónde lo/la encontraste]. '
                          'Lo/la que lo/la hace único/a es [una costumbre, gesto o anécdota que lo/la describa]. '
                          'Ya pasó por mucho. Ahora solo le falta alguien que decida quedarse. '
                          '¿Serás vos?';
                      setState(() {
                        a.descCtl.value = TextEditingValue(
                          text: plantilla,
                          selection: TextSelection.collapsed(
                            offset: plantilla.length,
                          ),
                        );
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: a.descCtl,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  hintText:
                      'Estado del animal, dónde fue encontrado, necesidades especiales...',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────

  Widget _bottomBar() {
    final c = context.sp;
    if (_paso == 2) {
      final contenido = _publicando
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
                        color: c.onPrimary,
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Publicando $_procesados de ${_animales.length}...',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: c.onPrimary,
                      ),
                    ),
                  ],
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
                Icon(Icons.pets_rounded, size: 20, color: c.onPrimary),
                const SizedBox(width: 8),
                Text(
                  'Publicar ${_animales.length} animales',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.onPrimary,
                  ),
                ),
              ],
            );
      // Mientras publica no se puede tocar, pero se sigue viendo igual (mismo
      // verde), solo ocupado — ver el mismo comentario en
      // subir_rescate_screen.dart. Hallazgo real de Eliza, en modo avión.
      final caja = Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        alignment: Alignment.center,
        decoration: SpDeco.primary(c, radius: SpRadius.md),
        child: contenido,
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: _publicando ? caja : SpPressable(onTap: _publicar, child: caja),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: SpButton(
          label: _paso == 0
              ? 'Siguiente: datos comunes'
              : 'Siguiente: revisar animales',
          icon: Icons.arrow_forward_rounded,
          onTap: _animales.isNotEmpty ? () => setState(() => _paso++) : null,
        ),
      ),
    );
  }

  Widget _chips(
    List<String> opts,
    String sel,
    ValueChanged<String> fn, [
    Color? color,
  ]) => ChipsSeleccionables(
    opciones: opts,
    seleccion: sel,
    onSeleccionar: fn,
    colorActivo: color,
    paddingChip: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
  );

  /// Píldora pastel que, al tocarla, abre una hoja para cambiar ese dato
  /// solo para este animal.
  Widget _selectableMiniChip({
    required String valor,
    required List<String> opciones,
    required SpTone tono,
    required ValueChanged<String> onChanged,
    Color? colorActivo,
  }) {
    final c = context.sp;
    final k = SpToneColors.of(c, tono);
    return GestureDetector(
      onTap: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: c.bg,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          builder: (sheetCtx) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 18),
                ChipsSeleccionables(
                  opciones: opciones,
                  seleccion: valor,
                  colorActivo: colorActivo,
                  paddingChip: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  onSeleccionar: (o) => Navigator.pop(sheetCtx, o),
                ),
              ],
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: k.fill,
          borderRadius: BorderRadius.circular(SpRadius.full),
          boxShadow: [BoxShadow(color: k.deep, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              valor,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: k.ink,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.expand_more_rounded, size: 14, color: k.ink),
          ],
        ),
      ),
    );
  }
}
