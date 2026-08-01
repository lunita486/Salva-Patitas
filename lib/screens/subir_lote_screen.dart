import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../theme.dart';
import '../data/creator_role.dart';
import '../data/rescates_repository.dart';
import '../data/foto_normalizador.dart';

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

class _SubirLoteScreenState extends State<SubirLoteScreen> with TardandoMuchoMixin {
  final _picker = ImagePicker();
  int _paso = 0;

  String _especie  = 'Perro';
  String _urgencia = 'Alta';
  String _ciudad   = '';
  bool   _cargandoCiudad = true;

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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final ciudad = (doc.data()?['ciudad'] as String?) ?? '';
    if (mounted) setState(() { _ciudad = ciudad; _cargandoCiudad = false; });
  }

  Future<void> _pickFotos() async {
    final picked = await _picker.pickMultiImage(imageQuality: 80, maxWidth: 1000, maxHeight: 1000);
    if (picked.isEmpty) return;
    final pathsExistentes = _animales.map((a) => a.foto1.path).toSet();
    final nuevas = picked.where((f) => !pathsExistentes.contains(f.path)).toList();
    if (nuevas.isEmpty) return;
    setState(() {
      for (final f in nuevas) _animales.add(_AnimalDraft(foto1: f));
    });
  }

  Future<void> _pickSegundaFoto(int index) async {
    final img = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1000, maxHeight: 1000);
    if (img != null && mounted) setState(() => _animales[index].foto2 = img);
  }

  Future<void> _publicar() async {
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
    final animalesConNombre = _animales.where((a) => a.nombreCtl.text.trim().isNotEmpty).toList();
    // Fuera del if (no solo declarado adentro): publicarUno() más abajo lo
    // necesita para dejar el mismo rastro de auditoría que el alta
    // individual (ver _duplicadoDeId en subir_rescate_screen.dart) en cada
    // animal que se publicó pese al aviso de nombre repetido.
    final repetidos = <String>{};
    if (animalesConNombre.isNotEmpty) {
      final uidActual = FirebaseAuth.instance.currentUser?.uid ?? '';
      // Una sola consulta para todo el lote, no una por animal (mismo
      // filtro rescatistaId+creadoPor cada vez — hallazgo de auditoría).
      final existentes = await RescatesRepository()
          .nombresExistentes(uid: uidActual, role: CreatorRole.albergue);
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
        final clave = '${a.nombreCtl.text.trim().toLowerCase()}_${a.especieOverride ?? _especie}';
        if (!vistos.add(clave)) repetidos.add(a.nombreCtl.text.trim());
      }
      if (repetidos.isNotEmpty) {
        if (!mounted) return;
        final continuar = await showDialog<bool>(
          context: context,
          builder: (dlgCtx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Nombres repetidos'),
            content: Text('Ya tenés (o estás por subir más de una vez en este lote) '
                'un animal llamado: ${repetidos.join(", ")}. Si es a propósito, '
                'podés publicar igual.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx, true),
                child: const Text('Publicar igual', style: TextStyle(color: appTeal)),
              ),
            ],
          ),
        );
        if (continuar != true) return;
      }
    }

    // Faltaba: si la persona sale de la pantalla mientras las consultas de
    // arriba todavía estaban en curso (conexión lenta, sin duplicados), el
    // setState() de acá abajo corría igual sobre una pantalla ya cerrada
    // (hallazgo de auditoría de código).
    if (!mounted) return;
    setState(() { _publicando = true; _procesados = 0; });
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
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      var nombre = FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista';
      final userDoc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      final albergueNombre = userDoc.data()?['albergueNombre'] as String?;
      if (albergueNombre != null && albergueNombre.isNotEmpty) nombre = albergueNombre;
      final fotoAlbergue = userDoc.data()?['fotoBase64'] as String?;

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
            ? a.nombreCtl.text.trim() : 'Animal ${i + 1}';
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
            role: CreatorRole.albergue,
            datos: {
              'nombre':              a.nombreCtl.text.trim(),
              'especie':             a.especieOverride ?? _especie,
              'raza':                'Criolla',
              'estado':              'Sano',
              'urgencia':            a.urgenciaOverride ?? _urgencia,
              'ubicacion':           _ciudad,
              'descripcion':         a.descCtl.text.trim(),
              'estadoAdopcion':      'Rescatado',
              'rescatistaNombre':    nombre,
              // Mismo rastro de auditoría que el alta individual: se avisó
              // un nombre repetido y se publicó igual a propósito — útil
              // para poder encontrar y limpiar duplicados reales después,
              // sin necesitar el id exacto del otro doc (acá puede haber
              // más de un candidato: contra lo ya publicado, o contra otro
              // animal del mismo lote).
              if (repetidos.contains(nombreAnimal)) 'duplicadoConfirmadoEn': FieldValue.serverTimestamp(),
              if (fotoAlbergue != null) 'rescatistaFotoBase64': fotoAlbergue,
              'edad':                'Adulto',
              'genero':              'No sé',
              'energia':             'Tranquilo',
              'tamano':              'Mediano',
              'okConNinos':          true,
              'okConMascotas':       true,
              'requiereExperiencia': false,
              // Por defecto, no asumido — igual que en el alta individual,
              // se puede corregir después editando cada animal cuando se
              // sepa de verdad (ej. tras la visita al veterinario).
              'vacunado':            'Aún no lo sé',
              'desparasitado':       'Aún no lo sé',
            },
            fotos: normalizadas,
          );
          FirebaseAnalytics.instance.logEvent(
            name: 'animal_publicado',
            parameters: {
              'especie': a.especieOverride ?? _especie,
              'creado_por': 'albergue',
            },
          ).catchError((_) {});
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

      // En tandas chicas, no todos los animales a la vez: cada uno normaliza
      // y sube hasta 2 fotos en su propio isolate (ver el comentario de
      // publicarUno más arriba), así que un lote grande sin límite podía
      // disparar decenas de isolates y subidas simultáneas — de sobra para
      // quedarse sin memoria y crashear a mitad de una publicación real
      // (un albergue subiendo 15-20 animales de una, justo el caso de uso
      // de esta pantalla), perdiendo todo lo ya tipeado. Hallazgo de
      // auditoría de código. Con tandas de 3 se conserva el paralelismo
      // real DENTRO de cada tanda (la mejora que ya existía) sin acumular
      // más de ~6 isolates/subidas a la vez en ningún momento, sin importar
      // cuán grande sea el lote entero.
      const tandaPublicacion = 3;
      for (var inicio = 0; inicio < _animales.length; inicio += tandaPublicacion) {
        final tanda = _animales.skip(inicio).take(tandaPublicacion).toList();
        await Future.wait([
          for (var j = 0; j < tanda.length; j++) publicarUno(tanda[j], inicio + j),
        ]);
      }

      if (!mounted) return;
      Navigator.pop(context);
      if (fallidos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$publicados animales publicados 🐾'),
          backgroundColor: msgExito,
          behavior: SnackBarBehavior.floating,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$publicados publicados. No se pudieron publicar: ${fallidos.join(", ")}.'),
          backgroundColor: msgAdvertencia,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ));
      }
    } catch (_) {
      // Rama poco común (algo falló ANTES/AFUERA del try/catch por animal
      // de más arriba, que ya cubre el caso normal de "se cayó la señal a
      // mitad de un animal puntual") — pero el mensaje y el volver a la
      // pantalla principal tienen que ser los mismos que el resto, no un
      // SnackBar rojo distinto dejando a la persona parada acá.
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('No se pudo publicar el lote. Revisá tu conexión e intentá de nuevo.'),
        backgroundColor: msgError,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ));
    } finally {
      cancelarTimerTardando();
      if (mounted) setState(() { _publicando = false; tardandoMucho = false; });
    }
  }

  @override
  void dispose() {
    for (final a in _animales) a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: SafeArea(
        child: Column(children: [
          _appBar(),
          _progressBar(),
          Expanded(child: _body()),
          _bottomBar(),
        ]),
      ),
    );
  }

  Widget _appBar() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
    child: Row(children: [
      IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                tooltip: 'Volver',
        // Apagado mientras se publica: sin esto, se podía volver al paso de
        // fotos (paso 0) y borrar/reemplazar la tarjeta de un animal que se
        // está publicando en ese mismo instante de fondo — publicarUno()
        // vuelve a leer nombreCtl/descCtl de ese draft DESPUÉS de un await
        // (la normalización de fotos), y si el dispose() ya corrió en ese
        // hueco, revienta con "used after being disposed". Hallazgo de
        // auditoría de código.
        onPressed: _publicando ? null : () {
          if (_paso > 0) setState(() => _paso--);
          else Navigator.pop(context);
        },
      ),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Subir lote',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: appInk)),
        Text(
          _paso == 0 ? 'Selecciona las fotos'
              : _paso == 1 ? 'Datos comunes para todos'
              : 'Revisa cada animal',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ])),
    ]),
  );

  Widget _progressBar() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
    child: Row(children: List.generate(3, (i) => Expanded(
      child: Container(
        height: 3,
        margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
        decoration: BoxDecoration(
          color: i <= _paso ? appTeal : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ))),
  );

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
    final opcion = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('¿Qué quieres hacer?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: appTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.add_photo_alternate_outlined, color: appTeal),
            ),
            title: const Text('Agregar más fotos',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Se suman a las que ya tienes'),
            onTap: () => Navigator.pop(sheetCtx, 'agregar'),
          ),
          const Divider(),
          ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.refresh, color: Colors.red.shade400),
            ),
            title: Text('Reemplazar todo',
                style: TextStyle(fontWeight: FontWeight.w600,
                    color: Colors.red.shade400)),
            subtitle: const Text('Borra las fotos actuales y empieza de nuevo'),
            onTap: () => Navigator.pop(sheetCtx, 'reemplazar'),
          ),
        ]),
      ),
    );
    if (opcion == null) return;
    if (opcion == 'reemplazar') {
      for (final a in _animales) a.dispose();
      _animales.clear();
    }
    await _pickFotos();
  }

  Widget _pasoFotos() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_animales.isEmpty)
        GestureDetector(
          onTap: _pickFotos,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: appTeal.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Column(children: [
              Icon(Icons.add_photo_alternate_outlined, size: 52, color: appTeal.withValues(alpha: 0.7)),
              const SizedBox(height: 12),
              const Text('Toca para seleccionar fotos',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: appTeal)),
              const SizedBox(height: 4),
              Text('Selecciona varias a la vez: 1 foto = 1 animal',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ]),
          ),
        ),
      if (_animales.isNotEmpty) ...[
        const SizedBox(height: 20),
        Row(children: [
          Text('${_animales.length} ${_animales.length == 1 ? "animal" : "animales"}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: appInk)),
          const Spacer(),
          GestureDetector(
            onTap: _pickFotosConConfirmacion,
            child: const Text('+ Agregar más',
                style: TextStyle(fontSize: 13, color: appTeal, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
          itemCount: _animales.length,
          itemBuilder: (_, i) => Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(File(_animales[i].foto1.path),
                  width: double.infinity, height: double.infinity, fit: BoxFit.cover),
            ),
            Positioned(
              top: 0, left: 0, right: 0, bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.3)]),
                ),
              ),
            ),
            Positioned(bottom: 4, left: 4,
              child: Text('${i + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.bold))),
            Positioned(top: 4, right: 4,
              child: GestureDetector(
                // Ver el comentario del botón "atrás" en _appBar(): borrar
                // un draft mientras se publica puede tirar abajo un
                // publicarUno() en curso sobre ESE mismo índice.
                onTap: _publicando
                    ? null
                    : () => setState(() { _animales[i].dispose(); _animales.removeAt(i); }),
                child: Container(
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(3),
                  child: const Icon(Icons.close, size: 13, color: Colors.white),
                ),
              )),
          ]),
        ),
      ],
    ]),
  );

  // ── Paso 1: Datos comunes ─────────────────────────────────────────────────

  Widget _pasoComunes() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: appTeal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: appTeal.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 16, color: appTeal),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Se aplican a los ${_animales.length} animales. Puedes editar cada uno después.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          )),
        ]),
      ),
      const SizedBox(height: 24),
      _label('ESPECIE'),
      const SizedBox(height: 10),
      _chips(['Perro', 'Gato', 'Otro'], _especie, (v) => setState(() => _especie = v), appTeal),
      const SizedBox(height: 24),
      _label('URGENCIA'),
      const SizedBox(height: 10),
      _chips(['Alta', 'Media', 'Baja'], _urgencia, (v) => setState(() => _urgencia = v),
          _urgencia == 'Alta' ? const Color(0xFFD32F2F)
              : _urgencia == 'Media' ? const Color(0xFFE65100) : appTeal),
      const SizedBox(height: 24),
      _label('CIUDAD'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          const Icon(Icons.location_on, size: 16, color: appTeal),
          const SizedBox(width: 8),
          Text(_cargandoCiudad ? 'Cargando...' : (_ciudad.isNotEmpty ? _ciudad : 'Sin ciudad'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const Spacer(),
          Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade400),
        ]),
      ),
      const SizedBox(height: 4),
      Text('Tomada del perfil del albergue',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
    ]),
  );

  // ── Paso 2: Individual ────────────────────────────────────────────────────

  Widget _pasoIndividual() => ListView.separated(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
    itemCount: _animales.length,
    separatorBuilder: (_, _) => const SizedBox(height: 12),
    itemBuilder: (_, i) {
      final a = _animales[i];
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Botón eliminar
          Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: 'Eliminar',
              child: GestureDetector(
                // Mismo motivo que el botón "atrás" de _appBar(): borrar
                // un draft mientras se publica puede tirar abajo un
                // publicarUno() en curso sobre ESE mismo índice.
                onTap: _publicando
                    ? null
                    : () => setState(() { _animales[i].dispose(); _animales.removeAt(i); }),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Icon(Icons.delete_outline, size: 15, color: Colors.red.shade400),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Fotos (principal + 2da)
          Column(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(File(a.foto1.path), width: 72, height: 72, fit: BoxFit.cover),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _pickSegundaFoto(i),
              child: a.foto2 != null
                ? Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(a.foto2!.path),
                          width: 72, height: 72, fit: BoxFit.cover),
                    ),
                    Positioned(top: 3, right: 3,
                      child: GestureDetector(
                        onTap: () => setState(() => a.foto2 = null),
                        child: Container(
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      )),
                  ])
                : Container(
                    width: 72, height: 40,
                    decoration: BoxDecoration(
                      color: appTeal.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: appTeal.withValues(alpha: 0.3), width: 1.2),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add_a_photo_outlined, size: 15,
                          color: appTeal.withValues(alpha: 0.7)),
                      const SizedBox(height: 2),
                      Text('+2da foto',
                          style: TextStyle(fontSize: 8, color: appTeal.withValues(alpha: 0.8))),
                    ]),
                  ),
            ),
          ]),
          const SizedBox(width: 12),
          // Nombre + resumen datos comunes
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Animal ${i + 1}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: a.nombreCtl,
              maxLength: 60,
              decoration: InputDecoration(
                hintText: 'Nombre (opcional)',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFF7F7F7),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _selectableMiniChip(
                valor: a.especieOverride ?? _especie,
                opciones: const ['Perro', 'Gato', 'Otro'],
                color: appTeal,
                onChanged: (v) => setState(() => a.especieOverride = v),
              ),
              _selectableMiniChip(
                valor: a.urgenciaOverride ?? _urgencia,
                opciones: const ['Alta', 'Media', 'Baja'],
                color: (a.urgenciaOverride ?? _urgencia) == 'Alta'
                    ? const Color(0xFFD32F2F)
                    : (a.urgenciaOverride ?? _urgencia) == 'Media'
                        ? const Color(0xFFE65100) : appTeal,
                onChanged: (v) => setState(() => a.urgenciaOverride = v),
              ),
              if (_ciudad.isNotEmpty) _miniChip(_ciudad, Colors.grey.shade700),
            ]),
          ])),
        ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Descripción (opcional)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
            GestureDetector(
              onTap: () {
                final nombre = a.nombreCtl.text.trim().isNotEmpty
                    ? a.nombreCtl.text.trim() : 'Animal ${i + 1}';
                final plantilla =
                    '$nombre fue encontrado/a [contá cómo o dónde lo/la encontraste]. '
                    'Lo/la que lo/la hace único/a es [una costumbre, gesto o anécdota que lo/la describa]. '
                    'Ya pasó por mucho. Ahora solo le falta alguien que decida quedarse. '
                    '¿Serás vos?';
                setState(() {
                  a.descCtl.value = TextEditingValue(
                    text: plantilla,
                    selection: TextSelection.collapsed(offset: plantilla.length),
                  );
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: appTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: appTeal.withValues(alpha: 0.3)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('✨', style: TextStyle(fontSize: 10)),
                  SizedBox(width: 3),
                  Text('Usar plantilla',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: appTeal)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: a.descCtl,
            maxLines: 3,
            maxLength: 1000,
            decoration: InputDecoration(
              hintText: 'Estado del animal, dónde fue encontrado, necesidades especiales...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFFF7F7F7),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          ]),
        );
    },
  );

  // ── Bottom bar ────────────────────────────────────────────────────────────

  Widget _bottomBar() {
    if (_paso == 2) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _publicando ? null : _publicar,
            style: ElevatedButton.styleFrom(
              backgroundColor: appDark, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: _publicando
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text('Publicando $_procesados de ${_animales.length}...',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                    ]),
                    if (tardandoMucho) ...[
                      const SizedBox(height: 6),
                      const Text('Esto está tardando más de lo normal. Revisá tu conexión',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: Colors.white70)),
                    ],
                  ])
                : Text('Publicar ${_animales.length} animales 🐾',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _animales.isNotEmpty ? () => setState(() => _paso++) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: appTeal, foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade200,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: Text(
            _paso == 0 ? 'Siguiente  →  Datos comunes' : 'Siguiente  →  Revisar animales',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          letterSpacing: 1.1, color: Colors.grey.shade700));

  Widget _chips(List<String> opts, String sel, ValueChanged<String> fn, Color color) =>
      Wrap(spacing: 8, runSpacing: 8, children: opts.map((o) {
        final active = o == sel;
        return GestureDetector(
          onTap: () => fn(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: active ? color : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: active ? color : Colors.grey.shade300),
            ),
            child: Text(o, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.grey.shade700)),
          ),
        );
      }).toList());

  Widget _miniChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
  );

  Widget _selectableMiniChip({
    required String valor,
    required List<String> opciones,
    required Color color,
    required ValueChanged<String> onChanged,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: opciones.map((o) {
                final active = o == valor;
                return GestureDetector(
                  onTap: () => Navigator.pop(context, o),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? color : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: active ? color : Colors.grey.shade300),
                    ),
                    child: Text(o, style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: active ? Colors.white : Colors.grey.shade700)),
                  ),
                );
              }).toList()),
            ]),
          ),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(valor, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(width: 3),
          Icon(Icons.expand_more, size: 11, color: color),
        ]),
      ),
    );
  }
}
