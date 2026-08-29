import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../domain/reglas_negocio.dart';
import 'creator_role.dart';
import 'solicitudes_repository.dart';
import 'favoritos_repository.dart';
import 'firestore_resiliencia.dart';
import 'rescate_fotos_repository.dart';

/// Una página de [RescatesRepository.paginaDeMisRescates]: los documentos,
/// si queda algo más abajo, y el cursor para pedir la página siguiente.
typedef PaginaDeRescates = ({
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  bool hayMas,
  DocumentSnapshot<Map<String, dynamic>>? ultimo,
});

/// Única puerta de entrada a la colección `rescates`. Las pantallas no
/// deben llamar `FirebaseFirestore.instance.collection('rescates')`
/// directamente — ver ARCHITECTURE.md.
class RescatesRepository {
  // ── Vocabulario del dominio ───────────────────────────────────────────
  // Los valores VÁLIDOS de cada campo de un rescate. Única fuente para
  // toda la app: las pantallas de publicar y de editar los leen de acá en
  // vez de declarar su propia lista.
  //
  // No es prolijidad — estaban declarados por separado en
  // subir_rescate_screen.dart y editar_rescate_screen.dart, y YA se habían
  // desincronizado sin que nadie lo notara (hallazgo de auditoría):
  //
  //   publicar: ['Sano', 'Herido', 'En tratamiento', 'Crítico']
  //   editar:   ['Sano', 'En tratamiento', 'Recuperado']
  //
  // Con eso, un animal publicado como 'Herido' o 'Crítico' se abría en
  // Editar SIN ningún chip marcado (su valor real no estaba en la lista de
  // esa pantalla): parecía que el dato se había perdido, y tocar cualquier
  // otra opción lo pisaba de verdad. Al revés, 'Recuperado' solo se podía
  // poner editando, nunca al publicar. Dos listas para el mismo campo no
  // pueden mantenerse iguales a mano; una sola no puede divergir.
  //
  // `estados` incluye la unión de las dos listas: sacar un valor dejaría a
  // los animales que YA lo tienen guardado sin poder mostrarlo (el mismo
  // bug, al revés). Antes de quitar alguno hay que migrar los documentos
  // que lo usen.
  static const especies = ['Perro', 'Gato', 'Otro'];
  static const estados = [
    'Sano',
    'Herido',
    'En tratamiento',
    'Recuperado',
    'Crítico',
  ];
  static const urgencias = ['Alta', 'Media', 'Baja'];
  static const energias = ['Tranquilo', 'Activo', 'Muy activo'];
  static const tamanos = ['Pequeño', 'Mediano', 'Grande'];
  static const edades = ['Cachorro', 'Adulto', 'Senior'];
  static const generos = ['Macho', 'Hembra', 'No sé'];
  static const siNo = ['Sí', 'No'];

  /// Salud (vacunado/desparasitado): 'Aún no lo sé' es un valor de primera
  /// clase, no un "sin dato" — un animal recién rescatado de la calle no
  /// pasó por veterinario todavía, y forzar Sí/No hacía que se adivinara
  /// (sugerencia real de un tester que rescató un gato de la calle).
  static const salud = ['Sí', 'No', 'Aún no lo sé'];
  static const tiposRaza = ['Criolla', 'Raza definida'];

  /// Nombre de un rescate, con el mismo criterio en toda la app para cuando
  /// no tiene uno cargado.
  ///
  /// `datos['nombre'] as String? ?? 'valor por defecto'` es un error fácil
  /// de cometer acá: un animal sin nombre NO tiene el campo en `null`,
  /// publicarlo lo deja en `''` (vacío) — así que ese `??` nunca entra en
  /// acción. Estaba mal en dos lugares (los avisos automáticos de
  /// vencimiento y de seguimiento post-adopción en
  /// solicitudes_rescatista_screen.dart, hallazgo real de Eliza: el mensaje
  /// salía "Venció el hogar de paso de " sin nada después) mientras que
  /// adoptante_feed_screen.dart sí comparaba contra vacío. Tres copias de la
  /// misma decisión — nombreDe es la única, para que no puedan volver a
  /// divergir entre sí.
  /// Las banderas de "ya avisé" del período de hogar de paso, puestas de
  /// vuelta en cero.
  ///
  /// Hay que limpiar LAS DOS al empezar un período nuevo. Si no, un
  /// animalito que ya tuvo un hogar de paso que venció no vuelve a avisar
  /// nunca: la bandera vieja lo silencia para siempre.
  ///
  /// Existe acá, y no escrita en cada lugar, porque hay DOS caminos que
  /// empiezan un período —aprobar una solicitud de hogar de paso, y
  /// ponerlo a mano desde el desplegable de estado— y ya se habían
  /// desincronizado: el de aprobar limpiaba solo `vencimientoAvisado` y se
  /// olvidaba de `avisoPrevioAvisado`, así que el aviso de "vence mañana"
  /// no se disparaba en el segundo período.
  static const avisosHogarDePasoDesdeCero = <String, Object?>{
    'avisoPrevioAvisado': false,
    'vencimientoAvisado': false,
  };

  /// Atajo para leer el nombre desde el MAPA del animal. La decisión de
  /// qué mostrar cuando no hay nombre NO vive acá: vive en
  /// `nombreDeAnimal` (domain/reglas_negocio.dart), que es la única. Esta
  /// función solo sabe de dónde sacar el campo.
  ///
  /// Antes tenía su propia copia de esa decisión, con su propio default.
  /// Eran dos funciones respondiendo lo mismo, más siete copias sueltas
  /// escritas a mano en las pantallas: diez lugares donde cambiar el mismo
  /// texto. Por eso el bug de "Para Sin nombre" se arregló una vez y
  /// siguió vivo en las otras nueve.
  static String nombreDe(Map<String, dynamic> datos, {bool enFrase = false}) =>
      nombreDeAnimal(datos['nombre'] as String?, enFrase: enFrase);

  RescatesRepository({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    RescateFotosRepository? fotosRepo,
  }) : _db = db ?? FirebaseFirestore.instance,
       _authOverride = auth,
       _fotosRepoOverride = fotosRepo;
  final FirebaseFirestore _db;
  // FirebaseAuth.instance recién se evalúa cuando hace falta de verdad
  // (dentro de eliminar(), y solo en la rama de permission-denied) — no en
  // el constructor. Evaluarlo ahí de entrada rompía CUALQUIER test de este
  // repositorio que no pasara un `auth:` mockeado (incluidos los que ni
  // tocan eliminar()), porque FirebaseAuth.instance exige un
  // Firebase.initializeApp() que `flutter test` no corre.
  final FirebaseAuth? _authOverride;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  // Mismo motivo que _authOverride, pero para Storage: publicarConFotos()
  // creaba su propio RescateFotosRepository() fijo por dentro, sin forma
  // de reemplazarlo — probar su lógica de deshacer (la parte "más grande
  // y delicada" agregada en esta sesión, según la propia auditoría de
  // código) necesita poder simular que una subida de foto falla, y sin
  // este punto de inyección eso es imposible desde afuera.
  final RescateFotosRepository? _fotosRepoOverride;
  RescateFotosRepository get _fotosRepo =>
      _fotosRepoOverride ?? RescateFotosRepository();

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('rescates');

  /// Animales publicados por [uid] bajo el rol [role]. `role` es
  /// obligatorio a propósito: una cuenta puede ser rescatista Y albergue
  /// a la vez, y sin este filtro se mezclan (bug real, arreglado hoy).
  Stream<QuerySnapshot<Map<String, dynamic>>> misRescates({
    required String uid,
    required CreatorRole role,
    String? estadoAdopcion,
  }) {
    Query<Map<String, dynamic>> q = _col
        .where('rescatistaId', isEqualTo: uid)
        .where('creadoPor', isEqualTo: role.firestoreValue);
    if (estadoAdopcion != null) {
      q = q.where('estadoAdopcion', isEqualTo: estadoAdopcion);
    }
    return q.snapshots();
  }

  /// Cuántos animales tiene [uid] bajo [role], SIN descargar ninguno.
  ///
  /// **Por qué existe.** Tres pantallas mostraban un número calculado con
  /// `snapshot.docs.length` sobre [misRescates], que es la colección
  /// completa: `home_screen` ("Animales rescatados"),
  /// `perfil_rescatista_screen` (total y adoptados) y `albergue_home_screen`
  /// (en cuidado, en adopción, adoptados, y el porcentaje de capacidad).
  ///
  /// O sea que abrir el inicio descargaba TODOS los documentos de la cuenta
  /// para pintar un número. Con 1.000 animales son 1.000 lecturas y ~2,5 MB;
  /// con 100.000, cien veces eso. El costo de mostrar un contador no puede
  /// depender de cuántos animales haya.
  ///
  /// `count()` lo resuelve del lado del servidor: Firestore lo cobra como
  /// 1 lectura por cada 1.000 documentos contados y no manda ni un
  /// documento. Un contador sobre 100.000 animales son 100 lecturas y unos
  /// bytes.
  ///
  /// **Lo que se pierde, y por qué se acepta.** Esto devuelve un número una
  /// vez, no un stream: el contador ya no se actualiza solo si otra persona
  /// publica algo mientras la pantalla está abierta. Se refresca al abrir la
  /// pantalla y al volver de publicar/editar/eliminar, que es cuando de
  /// verdad cambia para quien lo está mirando.
  ///
  /// **Cuándo dejaría de alcanzar** (dejado anotado a propósito, sin
  /// resolverlo ahora): si estos contadores se vuelven muy frecuentes —por
  /// ejemplo si se refrescaran en cada scroll, o si el inicio se recargara
  /// solo cada pocos segundos— el paso siguiente es guardar el número ya
  /// calculado en el documento de `usuarios` y mantenerlo con un trigger de
  /// Cloud Functions al crear/borrar/cambiar de estado un rescate. Eso lo
  /// deja en 0 lecturas extra (esas pantallas YA escuchan ese documento),
  /// a cambio de que un contador pueda quedar desincronizado si un trigger
  /// falla. Hoy no hace falta: son 4 contadores que se piden al abrir.
  ///
  /// [estados] filtra por `estadoAdopcion`. Ojo: un documento SIN ese campo
  /// no entra en ningún filtro (Firestore no puede consultar campos
  /// ausentes). `crear()` siempre lo escribe, así que solo afecta a
  /// documentos cargados a mano por fuera de la app.
  Future<int> contar({
    required String uid,
    required CreatorRole role,
    List<String>? estados,
  }) async {
    Query<Map<String, dynamic>> q = _col
        .where('rescatistaId', isEqualTo: uid)
        .where('creadoPor', isEqualTo: role.firestoreValue);
    if (estados != null && estados.isNotEmpty) {
      q = estados.length == 1
          ? q.where('estadoAdopcion', isEqualTo: estados.single)
          : q.where('estadoAdopcion', whereIn: estados);
    }
    return (await q.count().get()).count ?? 0;
  }

  /// Una página de los animales de [uid] bajo [role], con cursor.
  ///
  /// **Por qué existe.** [misRescates] devuelve un stream de la consulta
  /// COMPLETA, sin `limit`. Con 1.000 animales eso es 1.000 documentos cada
  /// vez que se abre la lista; con 100.000, cien veces eso. La regla que
  /// esto respeta es que la cantidad total de animales de la cuenta no
  /// determine cuánto trabajo hace el teléfono para mostrar una pantalla.
  ///
  /// **Cursor, no `offset` ni un `limit` que crece.** Firestore no tiene
  /// `offset` barato: saltear N documentos los COBRA igual. Y agrandar el
  /// `limit` de a poco (lo que hace hoy `feedPublico`) vuelve a traer todo
  /// lo anterior en cada página: la página 10 son 500 documentos otra vez.
  /// `startAfterDocument` arranca donde terminó la anterior y cobra solo lo
  /// nuevo, sin importar cuán adentro de la colección se esté.
  ///
  /// Se piden [porPagina] + 1 documentos a propósito: el sobrante no se
  /// devuelve, solo sirve para saber si [hayMas] sin pagar una consulta
  /// aparte.
  ///
  /// Los filtros van en la CONSULTA, no en Dart. Filtrar del lado del
  /// cliente sobre una página da resultados mal: si la primera página no
  /// tiene ningún gato, "Gatos" se vería vacío aunque haya 300 más abajo.
  ///
  /// Ordena por `creadoEn` descendente. Un documento sin ese campo queda
  /// afuera (Firestore excluye los que no tienen el campo del `orderBy`) —
  /// `crear()` siempre lo escribe; el riesgo es solo para documentos
  /// cargados a mano, el mismo que ya documenta [feedPublico].
  Future<PaginaDeRescates> paginaDeMisRescates({
    required String uid,
    required CreatorRole role,
    List<String>? estados,
    String? especie,
    /// Solo animales publicados ANTES de esta fecha. Existe para el filtro
    /// "Estancados", que no es un estado guardado sino un cálculo: lleva
    /// más de N días esperando y todavía se puede adoptar (ver esEstancado
    /// en domain/reglas_negocio.dart). Antes ese filtro se resolvía en Dart
    /// sobre la colección entera; como el corte es sobre `creadoEn`, que ya
    /// es el campo por el que se ordena, Firestore lo puede resolver sin
    /// traer nada de más.
    DateTime? creadoAntesDe,
    DocumentSnapshot<Map<String, dynamic>>? despuesDe,
    int porPagina = paginaRescatesSize,
  }) async {
    Query<Map<String, dynamic>> q = _col
        .where('rescatistaId', isEqualTo: uid)
        .where('creadoPor', isEqualTo: role.firestoreValue);
    if (estados != null && estados.isNotEmpty) {
      q = estados.length == 1
          ? q.where('estadoAdopcion', isEqualTo: estados.single)
          : q.where('estadoAdopcion', whereIn: estados);
    }
    if (especie != null) q = q.where('especie', isEqualTo: especie);
    if (creadoAntesDe != null) {
      q = q.where(
        'creadoEn',
        isLessThanOrEqualTo: Timestamp.fromDate(creadoAntesDe),
      );
    }
    q = q.orderBy('creadoEn', descending: true);
    if (despuesDe != null) q = q.startAfterDocument(despuesDe);

    final snap = await q.limit(porPagina + 1).get();
    final hayMas = snap.docs.length > porPagina;
    final docs = hayMas ? snap.docs.take(porPagina).toList() : snap.docs;
    return (docs: docs, hayMas: hayMas, ultimo: docs.isEmpty ? null : docs.last);
  }

  /// La misma página que [paginaDeMisRescates], pero EN VIVO.
  ///
  /// **Por qué existe además de la otra.** La versión de una sola lectura
  /// hacía que la pantalla esperara el viaje al servidor en cada apertura:
  /// `Query.get()` usa `Source.serverAndCache`, que va al servidor y solo cae
  /// a la caché si no hay conexión. Antes esta lista era `snapshots()`, que
  /// entrega la caché local AL INSTANTE y después actualiza con el servidor,
  /// así que aparecía sin esperar nada. Se notaba como una demora al abrir
  /// "Gestionar la jauría" — hallazgo real de Eliza, y una regresión que
  /// introdujo la paginación.
  ///
  /// Devolver un stream recupera las dos cosas: el pintado inmediato desde
  /// caché y que la lista se actualice sola (editar un animalito y ver el
  /// cambio al volver, sin recargar).
  ///
  /// [despuesDe] es el cursor, igual que en [paginaDeMisRescates] y en
  /// [feedPublico]. Pide [porPagina] + 1 por el mismo motivo: saber si hay
  /// más sin pagar otra consulta. Quien recorta ese sobrante es la pantalla.
  Stream<QuerySnapshot<Map<String, dynamic>>> misRescatesEnVivo({
    required String uid,
    required CreatorRole role,
    List<String>? estados,
    String? especie,
    DateTime? creadoAntesDe,
    DocumentSnapshot<Map<String, dynamic>>? despuesDe,
    int porPagina = paginaRescatesSize,
  }) {
    Query<Map<String, dynamic>> q = _col
        .where('rescatistaId', isEqualTo: uid)
        .where('creadoPor', isEqualTo: role.firestoreValue);
    if (estados != null && estados.isNotEmpty) {
      q = estados.length == 1
          ? q.where('estadoAdopcion', isEqualTo: estados.single)
          : q.where('estadoAdopcion', whereIn: estados);
    }
    if (especie != null) q = q.where('especie', isEqualTo: especie);
    if (creadoAntesDe != null) {
      q = q.where(
        'creadoEn',
        isLessThanOrEqualTo: Timestamp.fromDate(creadoAntesDe),
      );
    }
    q = q.orderBy('creadoEn', descending: true);
    if (despuesDe != null) q = q.startAfterDocument(despuesDe);
    return q.limit(porPagina + 1).snapshots();
  }

  /// Cuántos animales trae cada página de la lista. 20 llena de sobra una
  /// pantalla de teléfono sin traer de más.
  static const paginaRescatesSize = 20;

  /// True si [uid] ya tiene publicado otro animal con el mismo [nombre], la
  /// misma [especie] (sin importar mayúsculas/espacios en el nombre) Y bajo
  /// el mismo [role]. Se filtra por CreatorRole a propósito — una cuenta
  /// puede tener rol de rescatista Y de albergue a la vez, pero en la
  /// práctica eso representa a la misma persona operando dos "negocios"
  /// distintos (decisión de producto: no es realista en producción que la
  /// mayoría de las cuentas tengan doble rol, y cuando pasa, publicar el
  /// mismo nombre en cada uno por separado no es necesariamente un error).
  /// Antes no se filtraba por role y cruzaba rescatista con albergue de la
  /// misma cuenta — molestaba con avisos falsos exactamente en ese caso.
  ///
  /// Comparar también la especie evita falsos positivos con nombres
  /// populares que se repiten en animales realmente distintos — un
  /// "Richard" perro no debería chocar con un "Richard" gato del mismo rol.
  /// Comparar la foto en sí (para acercarse aún más a "duplicado real")
  /// queda pendiente — compararla a este nivel implicaría hashear el
  /// contenido de la imagen, no solo leer un campo de Firestore.
  ///
  /// El primer rescate de [uid] bajo [role] con el mismo [nombre] (y, si se
  /// pasa, la misma [especie]) — para el aviso de "posible duplicado" antes
  /// de publicar. Devuelve el documento (no solo un bool) para que la
  /// pantalla pueda ofrecer "Ver ficha existente" en vez de solo
  /// cancelar/continuar a ciegas sobre cuál es el otro animal.
  ///
  /// Un nombre vacío nunca cuenta como duplicado — el nombre es opcional y
  /// comparar vacíos contra vacíos daría falsos positivos entre animales
  /// sin nombre que no tienen nada que ver.
  ///
  /// Tolerante a fallas de red a propósito: este chequeo es un AVISO de
  /// cortesía, no una barrera de datos — su respuesta jamás debe impedir
  /// publicar. Justo después de recuperar señal (modo avión), la consulta
  /// al servidor puede fallar aunque ya haya internet (el canal tarda hasta
  /// ~1 minuto en reconectar); en ese caso se consulta la copia LOCAL, y si
  /// hasta eso falla se devuelve null (sin duplicado): mejor publicar sin
  /// el aviso que un botón "Publicar" muerto sin mensaje (las pantallas lo
  /// llaman ANTES de su manejo de errores — mismo bug de raíz que el
  /// "no pudimos verificar si se puede eliminar" de tienePendientesPara en
  /// SolicitudesRepository, ver ese comentario).
  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> buscarDuplicado({
    required String uid,
    required String nombre,
    required CreatorRole role,
    String? especie,
    String? excluyendoId,
  }) async {
    final buscado = nombre.trim().toLowerCase();
    if (buscado.isEmpty) return null;
    // Filtra por `nombreBusqueda` (nombre normalizado, ver crear()/actualizar())
    // en vez de traer TODOS los animales del rol y comparar acá — antes esto
    // escalaba con la cantidad total de animales publicados en la cuenta, sin
    // límite, así que una cuenta con mucho historial (ej. de tanto probar)
    // notaba cada vez más demora al publicar, con buena señal y todo. Hallazgo
    // real de Eliza. Solo 3 filtros de igualdad (sin orderBy ni rango), así
    // que no hace falta un índice compuesto nuevo.
    // Cuentas con animales publicados ANTES de este cambio, sin `nombreBusqueda`
    // todavía, no van a matchear acá hasta que ese animal se vuelva a guardar
    // una vez — el aviso de duplicado es una cortesía, no una barrera de
    // datos, así que ese costo se acepta a cambio de no escanear todo cada vez.
    final consulta = _col
        .where('rescatistaId', isEqualTo: uid)
        .where('creadoPor', isEqualTo: role.firestoreValue)
        .where('nombreBusqueda', isEqualTo: buscado);
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await consulta.get();
    } catch (_) {
      try {
        snap = await consulta.get(const GetOptions(source: Source.cache));
      } catch (_) {
        return null;
      }
    }
    for (final d in snap.docs) {
      if (d.id == excluyendoId) continue;
      final data = d.data();
      if (especie != null && especie.isNotEmpty && data['especie'] != especie)
        continue;
      return d;
    }
    // Ningún match por el camino rápido. Todavía puede haber un duplicado
    // REAL que la consulta de arriba no puede ver, y esa es la diferencia
    // entre "no hay duplicado" y "no lo encontré".
    return _duplicadoEntreLosViejos(
      uid: uid,
      role: role,
      buscado: buscado,
      especie: especie,
      excluyendoId: excluyendoId,
    );
  }

  /// uid+rol cuyos animales ya se comprobó que están todos migrados, para no
  /// repetir el rastreo caro en cada publicación de la misma sesión.
  static final _yaMigrados = <String>{};

  /// Solo para los tests, que necesitan cada caso desde cero.
  @visibleForTesting
  static void olvidarQuienEstaMigrado() => _yaMigrados.clear();

  /// El rastreo de respaldo para animales que la consulta rápida no puede
  /// ver.
  ///
  /// **Por qué hace falta.** [buscarDuplicado] filtra por `nombreBusqueda` y
  /// por `creadoPor`, dos campos que se agregaron después de que la app ya
  /// estaba en uso. Un animal cargado antes no tiene ninguno de los dos, así
  /// que era **invisible** para el aviso: se podía publicar un segundo
  /// "Michi" gato y no pasaba nada. Reporte real de Eliza — la rescatista
  /// Lucía Jiménez cargó dos gatos con el mismo nombre y el segundo no avisó.
  ///
  /// Esto ya estaba anotado en el código como un costo aceptado ("no van a
  /// matchear hasta que ese animal se vuelva a guardar una vez"). La cuenta
  /// estaba mal: no es un puñado de casos raros, es todo lo cargado antes de
  /// esa fecha, que para una cuenta de verdad es casi todo. Una función que
  /// avisa solo a veces, sin decir cuándo, es peor que no tenerla.
  ///
  /// **Por qué no reemplaza a la consulta rápida.** Traer todos los animales
  /// de la cuenta en cada publicación es justamente la demora que Eliza
  /// reportó antes ("se demora mucho en almacenarlo"). Así que el camino
  /// rápido se queda, esto corre solo cuando aquel no encontró nada, y en
  /// cuanto se comprueba que la cuenta está entera migrada no se vuelve a
  /// correr en toda la sesión.
  ///
  /// **El límite que tiene el memo.** Una vez que se comprobó que la cuenta
  /// está entera migrada no se vuelve a rastrear en toda la sesión, así que
  /// un documento sin `nombreBusqueda` que apareciera DESPUÉS quedaría
  /// invisible hasta reabrir la app. En la práctica no puede pasar: el único
  /// que escribe animales sin ese campo es una versión vieja de la app
  /// corriendo en otro teléfono al mismo tiempo. Se acepta a cambio de no
  /// pagar el rastreo en cada publicación, que es la demora que Eliza ya
  /// había reportado. La marca solo se pone si se recorrió la cuenta entera
  /// sin encontrar ni uno sin migrar, que es lo que un test custodia.
  ///
  /// La cura definitiva es rellenar `nombreBusqueda` de una vez en los
  /// documentos viejos; el día que no quede ninguno sin migrar, esta función
  /// y su memo se pueden borrar enteros.
  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _duplicadoEntreLosViejos({
    required String uid,
    required CreatorRole role,
    required String buscado,
    String? especie,
    String? excluyendoId,
  }) async {
    final memo = '$uid/${role.firestoreValue}';
    if (_yaMigrados.contains(memo)) return null;
    // Se filtra SOLO por rescatistaId: agregar `creadoPor` acá volvería a
    // dejar afuera a los documentos viejos, que es lo que vinimos a
    // arreglar. El rol se decide en Dart con creatorRoleFromFirestore(),
    // que ya sabe que un `creadoPor` ausente significa 'rescatista'.
    final consulta = _col.where('rescatistaId', isEqualTo: uid);
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await consulta.get();
    } catch (_) {
      try {
        snap = await consulta.get(const GetOptions(source: Source.cache));
      } catch (_) {
        return null;
      }
    }
    var todosMigrados = true;
    QueryDocumentSnapshot<Map<String, dynamic>>? encontrado;
    for (final d in snap.docs) {
      final data = d.data();
      if (((data['nombreBusqueda'] as String?) ?? '').isEmpty) {
        todosMigrados = false;
      }
      if (creatorRoleFromFirestore(data['creadoPor'] as String?) != role) {
        continue;
      }
      if (encontrado != null || d.id == excluyendoId) continue;
      if (claveDuplicado(data['nombre'] as String?, data['especie'] as String?) !=
          claveDuplicado(buscado, especie)) {
        continue;
      }
      encontrado = d;
    }
    // Solo se marca como migrada si se recorrió TODA la cuenta sin
    // encontrar un solo documento sin `nombreBusqueda`.
    if (todosMigrados) _yaMigrados.add(memo);
    return encontrado;
  }

  /// La única definición de "estos dos animales cuentan como el mismo" para
  /// el aviso de duplicado: nombre normalizado + especie.
  ///
  /// Existe como función y no escrita a mano en cada lado porque había DOS
  /// reglas: la de [buscarDuplicado] (publicar de a uno) y la de
  /// [nombresExistentes] (subir un lote). Dos definiciones de lo mismo es
  /// exactamente cómo una queda arreglada y la otra no.
  ///
  /// Una especie vacía compara solo por nombre, a propósito: es lo que pide
  /// un llamador que todavía no sabe la especie.
  @visibleForTesting
  static String claveDuplicado(String? nombre, String? especie) =>
      '${(nombre ?? '').trim().toLowerCase()}_${especie ?? ''}';

  /// Conveniencia sobre [buscarDuplicado] para los llamadores (ej. el lote,
  /// que solo necesita saber si avisar) a los que no les hace falta el
  /// documento completo.
  Future<bool> existeNombre({
    required String uid,
    required String nombre,
    required CreatorRole role,
    String? especie,
  }) async =>
      (await buscarDuplicado(
        uid: uid,
        nombre: nombre,
        role: role,
        especie: especie,
      )) !=
      null;

  /// Todos los "nombre_especie" (nombre en minúscula) ya publicados por
  /// [uid] bajo [role], en UNA sola consulta — para chequear varios
  /// animales a la vez (el lote) sin repetir la misma consulta a
  /// [buscarDuplicado]/[existeNombre] una vez por animal (mismo filtro
  /// rescatistaId+creadoPor cada vez, hallazgo de auditoría de código:
  /// un lote de N animales hacía N viajes de red idénticos antes de
  /// arrancar a publicar).
  Future<Set<String>> nombresExistentes({
    required String uid,
    required CreatorRole role,
  }) async {
    // Sin filtrar por `creadoPor` en la consulta, por el mismo motivo que
    // _duplicadoEntreLosViejos: los animales cargados antes de que ese campo
    // existiera no lo tienen y quedaban invisibles para el aviso del lote,
    // igual que quedaban para el de publicar de a uno. El rol se decide en
    // Dart, donde creatorRoleFromFirestore() sabe qué hacer con un campo
    // ausente.
    final consulta = _col.where('rescatistaId', isEqualTo: uid);
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await consulta.get();
    } catch (_) {
      try {
        snap = await consulta.get(const GetOptions(source: Source.cache));
      } catch (_) {
        return {};
      }
    }
    return snap.docs
        .where(
          (d) =>
              creatorRoleFromFirestore(d.data()['creadoPor'] as String?) == role,
        )
        // La MISMA clave que usa buscarDuplicado. Antes esta línea tenía su
        // propia copia de la regla.
        .map(
          (d) => claveDuplicado(
            d.data()['nombre'] as String?,
            d.data()['especie'] as String?,
          ),
        )
        .toSet();
  }

  /// Tamaño de cada tanda del feed público paginado — ver [feedPublico].
  /// Hallazgo de auditoría de código: antes `feedPublico()` no tenía
  /// ningún límite, así que abrir el feed bajaba TODA la colección de
  /// `rescates` de una sola vez, sin importar cuántos animales hubiera.
  /// Con pocos animales no se nota; es un problema de costo (Firestore
  /// cobra por lectura) y performance que crece sin techo junto con el
  /// catálogo.
  static const feedPageSize = 50;

  /// [despuesDe] es el cursor de la página siguiente: mismo nombre y misma
  /// forma que en [paginaDeMisRescates], para que las dos se lean igual.
  ///
  /// **Por qué acá el cursor y no un `limit` que crece.** Antes el feed
  /// pedía 50, después 100, después 150: cada página volvía a traer TODO lo
  /// anterior, así que la página 10 eran 500 documentos otra vez. Con el
  /// cursor, cada página cuesta 50 sin importar cuán adentro del feed se
  /// esté.
  ///
  /// Sigue devolviendo un STREAM, no una lectura de una vez, y eso es a
  /// propósito: el feed se actualiza solo (un animal que se adopta cambia
  /// de estado en la tarjeta sin recargar). Esa es la diferencia con
  /// [paginaDeMisRescates], y es la razón por la que las dos no comparten
  /// implementación: una es en vivo y la otra no. Quien junta las páginas
  /// en vivo es FeedPaginado (data/feed_paginado.dart).
  ///
  /// Feed público de adopción — sin scope por diseño, cualquiera lo ve.
  /// Paginado: trae como mucho [limite] animales (por defecto
  /// [feedPageSize]), ordenados por fecha de publicación, los más viejos
  /// primero. `adoptante_feed_screen.dart` va agrandando [limite] de a
  /// [feedPageSize] a medida que la persona se acerca al final de lo ya
  /// cargado — un catálogo enorme nunca se descarga entero de golpe, y
  /// como sigue siendo el MISMO stream en vivo (no una serie de páginas
  /// sueltas), un animal publicado por otra cuenta mientras alguien ya
  /// está mirando el feed va a aparecer solo, apenas el límite crezca lo
  /// suficiente para alcanzarlo — sin que nadie tenga que cerrar y volver
  /// a abrir la pantalla.
  ///
  /// CAMBIO DE DISEÑO — antes esto NO ordenaba por `creadoEn` a propósito
  /// (ver el test viejo que este comentario reemplaza en
  /// rescates_repository_test.dart): Firestore excluye de un `orderBy`
  /// cualquier documento que no tenga ese campo, y antes existían rescates
  /// legados sin él. Ordenar es necesario para que la paginación tenga
  /// sentido (sin orden, "los primeros N" serían un subconjunto arbitrario
  /// que no crece hacia ningún lado predecible). Confirmado con Eliza
  /// (2026-08-02) que hoy TODOS los rescates reales tienen `creadoEn`
  /// (crear() lo pone siempre) — el riesgo que sigue abierto es a futuro:
  /// un rescate cargado por fuera de este repositorio (a mano en Firebase
  /// Console, o un script) que se olvide de ese campo quedaría invisible
  /// en el feed, sin ningún aviso.
  Stream<QuerySnapshot<Map<String, dynamic>>> feedPublico({
    int limite = feedPageSize,
    DocumentSnapshot<Map<String, dynamic>>? despuesDe,
  }) {
    Query<Map<String, dynamic>> q = _col.orderBy('creadoEn');
    if (despuesDe != null) q = q.startAfterDocument(despuesDe);
    return q.limit(limite).snapshots();
  }

  /// Stream de UN rescate por id — para pantallas que necesitan reaccionar
  /// en vivo a cambios de estado (ej. chat_screen.dart, que muestra "✅
  /// Adoptado"/"🌈 Falleció" apenas cambian, sin recargar la pantalla).
  Stream<DocumentSnapshot<Map<String, dynamic>>> porId(String rescateId) =>
      _col.doc(rescateId).snapshots();

  /// Stream por nombre+dueño — fallback para chats/solicitudes viejos
  /// guardados sin `rescateId` (ver actualizarPorNombre, mismo criterio:
  /// dato legado, puede confundirse si hay 2 animales con el mismo nombre
  /// bajo la misma cuenta en distinto rol, pero es el mejor esfuerzo
  /// posible sin ese id).
  Stream<QuerySnapshot<Map<String, dynamic>>> porNombreYDueno({
    required String rescatistaId,
    required String nombre,
  }) => _col
      .where('rescatistaId', isEqualTo: rescatistaId)
      .where('nombre', isEqualTo: nombre)
      .limit(1)
      .snapshots();

  /// Lectura puntual de UN rescate por id — usada para chequear su estado
  /// actual justo antes de eliminarlo (ver editar_rescate_screen.dart y
  /// mis_rescates_screen.dart). No alcanza con el estado que la pantalla
  /// cargó al abrir: puede haber cambiado desde entonces (ej. se aprobó un
  /// hogar de paso mientras la pantalla de edición seguía abierta).
  Future<DocumentSnapshot<Map<String, dynamic>>> obtener(String rescateId) =>
      _col.doc(rescateId).get();

  /// Lectura puntual (no stream) de "mis animales en tal estado" — para
  /// chequeos únicos como avisos de vencimiento de hogar de paso.
  Future<QuerySnapshot<Map<String, dynamic>>> misRescatesPorEstado({
    required String uid,
    required CreatorRole role,
    required String estadoAdopcion,
  }) => _col
      .where('rescatistaId', isEqualTo: uid)
      .where('creadoPor', isEqualTo: role.firestoreValue)
      .where('estadoAdopcion', isEqualTo: estadoAdopcion)
      .get();

  /// Genera un id de rescate sin tocar la red (`.doc()` sin argumentos es
  /// puramente local) — para poder conocer el id ANTES de intentar el
  /// `set()` de [crear]. Necesario para hacer rollback de forma confiable:
  /// `Future.timeout()` no cancela la operación original, solo deja de
  /// esperarla. Si `crear()` usara `.add()` y el timeout se disparara antes
  /// de que la escritura realmente terminara, el llamador nunca se entera
  /// del id — pero el `.add()` original sigue corriendo en segundo plano y,
  /// si la conexión vuelve más tarde, puede terminar creando el documento
  /// igual, sin que nadie sepa que existe para poder borrarlo (bug real:
  /// publicar 2 veces sin señal dejó 2 rescates fantasma sin foto, visibles
  /// para el adoptante, porque el rollback nunca tuvo un id que borrar).
  DocumentReference<Map<String, dynamic>> nuevoRef() => _col.doc();

  Future<DocumentReference<Map<String, dynamic>>> crear({
    required String uid,
    required CreatorRole role,
    required Map<String, dynamic> datos,
    DocumentReference<Map<String, dynamic>>? ref,
  }) async {
    final destino = ref ?? _col.doc();
    final nombre = datos['nombre'] as String?;
    await destino.set({
      ...datos,
      'rescatistaId': uid,
      'creadoPor': role.firestoreValue,
      'creadoEn': FieldValue.serverTimestamp(),
      // Nombre normalizado para que buscarDuplicado() pueda filtrar del lado
      // del servidor en vez de traer todos los animales del rol — se escribe
      // acá, no en cada pantalla, para que ningún llamador nuevo se olvide.
      if (nombre != null && nombre.isNotEmpty)
        'nombreBusqueda': nombre.trim().toLowerCase(),
    });
    return destino;
  }

  /// Las copias del nombre/foto de este animal que viven en `solicitudes`
  /// y `chats` NO se tocan desde acá: las mantiene al día el trigger
  /// `onRescateActualizado` (functions/propagar_copias.js). Antes esto
  /// disparaba dos sincronizaciones "best-effort" en segundo plano que
  /// fallaban en silencio de cuatro formas distintas — ver el comentario
  /// largo en functions/propagar_copias_logica.js para el porqué de la
  /// mudanza al servidor.
  Future<void> actualizar(String rescateId, Map<String, dynamic> cambios) async {
    final nombre = cambios['nombre'] as String?;
    await _col.doc(rescateId).update({
      ...cambios,
      // Mismo motivo que en crear(): si esta actualización toca el nombre,
      // mantiene nombreBusqueda sincronizado — sin esto, editar el nombre de
      // un animal ya publicado lo dejaría invisible para buscarDuplicado().
      if (nombre != null) 'nombreBusqueda': nombre.trim().toLowerCase(),
    });
  }

  /// Cambia `estadoAdopcion` desde el picker de estado (`CambiarEstadoSheet`).
  /// [extra] son campos propios de ese estado (ej. `fechaAdopcion`,
  /// `motivoRegreso`, `notaFallecido`).
  ///
  /// Al volver a 'Rescatado'/'Regresado'/'Fallecido' limpia
  /// `adoptanteIdEnProceso` a propósito: ese campo lo escribe
  /// `SolicitudesRepository.aprobarSiDisponible` para saber a quién le
  /// pertenece el proceso activo, y si queda pegado después de que el
  /// animal vuelve a estar disponible, la próxima solicitud que se intente
  /// aprobar se autorrechaza para siempre (la transacción cree que YA hay
  /// un adoptante con el proceso activo, aunque ese adoptante ya no tenga
  /// nada que ver). Bug real: un animal "Regresado" y republicado como
  /// disponible no dejaba aprobar ninguna solicitud nueva.
  Future<void> cambiarEstadoAdopcion(
    String rescateId,
    String nuevoEstado, {
    Map<String, dynamic> extra = const {},
  }) {
    final limpiaClaim =
        nuevoEstado == 'Rescatado' ||
        nuevoEstado == 'Regresado' ||
        nuevoEstado == 'Fallecido';
    return _col.doc(rescateId).update({
      'estadoAdopcion': nuevoEstado,
      if (limpiaClaim) 'adoptanteIdEnProceso': FieldValue.delete(),
      ...extra,
    });
  }

  /// Fallback para solicitudes viejas guardadas sin `rescateId`: busca el
  /// rescate por nombre+dueño y lo actualiza si lo encuentra. Si hay más de
  /// un animal con el mismo nombre bajo la misma cuenta, actualiza el
  /// primero que encuentre — mismo comportamiento legado que reemplaza.
  Future<void> actualizarPorNombre({
    required String nombre,
    required String rescatistaId,
    required Map<String, dynamic> cambios,
  }) async {
    final q = await _col
        .where('nombre', isEqualTo: nombre)
        .where('rescatistaId', isEqualTo: rescatistaId)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) {
      await q.docs.first.reference.update(cambios);
    }
  }

  /// Un `permission-denied` acá casi siempre NO es un problema real de
  /// permisos — la regla de `rescates` solo compara `rescatistaId` contra
  /// el uid actual, y si la pantalla te muestra el botón de eliminar es
  /// porque ya sabe que sos el dueño. Lo que sí pasa: después de rato
  /// alternando entre modo avión y señal real (justo el patrón de una
  /// sesión larga de pruebas offline), el token de sesión puede quedar
  /// vencido sin que el refresco automático llegue a tiempo — el pedido
  /// sale con un token viejo y el servidor lo rechaza. Antes esto se
  /// mostraba tal cual, como texto técnico en inglés ("Error:
  /// [cloud_firestore/permission-denied] The caller does not have
  /// permission..."), dejando a la usuaria sin ninguna acción clara. Se
  /// fuerza un refresh del token y se reintenta UNA vez antes de
  /// rendirse — si era eso, la persona ni se entera de que pasó algo.
  Future<void> eliminar(String rescateId) async {
    // El refresh-token-y-reintentar vive en firestore_resiliencia.dart
    // (conReintentoSiTokenVencido), compartido con UsuariosRepository —
    // ver el porqué completo en el doc-comment de arriba.
    await conReintentoSiTokenVencido(
      () => _auth,
      () => _col.doc(rescateId).delete(),
    );
    // Sin esperar (fire-and-forget) a propósito: esto YA es best-effort
    // (ver doc de _borrarFavoritos), así que no tiene sentido que la
    // persona que está borrando su animal espere por una limpieza que ni
    // siquiera es su acción. Antes estaba con `await` acá, y sumaba sus
    // propios timeouts (hasta 10s) DENTRO del `eliminar()` que las
    // pantallas envuelven en su propio `.timeout(12s)` — el guard
    // `_eliminando` de mis_rescates_screen.dart/editar_rescate_screen.dart
    // se soltaba recién cuando ESTO también terminaba, no cuando el
    // borrado real (lo único que la persona ve y espera) ya había
    // pasado. El bug real que reportó Eliza: "borro un animalito bien, y
    // al borrar el siguiente dice que hay una eliminación en curso" — la
    // tarjeta ya había desaparecido, pero el guard seguía trabado
    // esperando esta limpieza silenciosa de fondo.
    _borrarFavoritos(rescateId);
  }

  /// Los `favoritos` que apuntan a este rescate no se borran solos: sin
  /// esto, un animal eliminado seguía viéndose en la pantalla de
  /// Favoritos del adoptante como si siguiera disponible para adoptar,
  /// con un botón "Adoptar" apuntando a un rescate que ya no existe (el
  /// bug real que reportó Eliza). Solo se tocan los favoritos de ESTE
  /// rescatista/albergue (regla de seguridad: `rescatistaId == uid()`,
  /// además de `adoptanteId == uid()` que ya tenían) — el dueño del
  /// favorito nunca ve este borrado como una acción suya, así que es
  /// best-effort: si falla (sin señal, error transitorio), no bloquea el
  /// borrado real que la persona pidió, y ni siquiera se espera (ver
  /// comentario en `eliminar`). La pantalla de Favoritos se defiende del
  /// lado del adoptante por si esto no llega a correr, y el Cloud
  /// Function `onRescateEliminado` (functions/index.js) lo garantiza de
  /// todas formas del lado del servidor, incluso si el borrado pasó sin
  /// señal y esto ni llegó a intentarse.
  Future<void> _borrarFavoritos(String rescateId) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      // Timeouts propios, más cortos que los de las pantallas (10-12s
      // sobre eliminar() completo): sin límite acá, una consulta lenta de
      // favoritos podía estirar eliminar() hasta el timeout del llamador
      // y convertir un borrado que YA salió bien en el mensaje de "está
      // tardando" — un error fantasma por culpa de la limpieza secundaria.
      final favoritos = await FavoritosRepository(db: _db)
          .deRescate(rescateId: rescateId, rescatistaId: uid)
          .timeout(const Duration(seconds: 5));
      if (favoritos.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in favoritos.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// Traduce lo que puede salir mal en [eliminar] (si el reintento con
  /// token renovado TAMBIÉN falla) a un mensaje que una persona sin
  /// conocimientos técnicos pueda entender y accionar — usado por las dos
  /// pantallas que llaman a [eliminar] (mis_rescates_screen.dart,
  /// editar_rescate_screen.dart) en vez de mostrar el texto crudo de la
  /// excepción tal cual llega.
  ///
  /// Un TimeoutException NUNCA llega acá a propósito: timeout ≠ error (el
  /// borrado queda encolado, Firestore lo aplica solo al reconectar y la
  /// Cloud Function onRescateEliminado limpia fotos/favoritos en el
  /// servidor), así que las dos pantallas lo atrapan ANTES con su propio
  /// `on TimeoutException` y muestran el mismo "Publicación eliminada"
  /// del camino feliz. Hubo dos intentos de mensaje especial para ese
  /// caso ("estamos sin señal", después "está tardando") y ambos
  /// confundieron en las pruebas reales: la tarjeta ya había
  /// desaparecido, y un aviso naranja sobre un borrado visiblemente
  /// exitoso se lee como que algo falló.
  static String mensajeErrorEliminar(Object error) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'No pudimos eliminar. Puede que tu sesión necesite renovarse. '
          'Cerrá sesión y volvé a entrar, o intentá de nuevo en un momento.';
    }
    return 'No se pudo eliminar. Revisá tu conexión e intentá de nuevo.';
  }

  /// Título y mensaje del diálogo que bloquea el borrado cuando el animal no
  /// está en "Rescatado". Antes vivía duplicado byte a byte en
  /// mis_rescates_screen.dart y editar_rescate_screen.dart (hallazgo de
  /// auditoría de código) — un cambio de texto necesitaba dos ediciones.
  /// "Hogar de paso"/"En proceso de adopción"/"Regresado" son reversibles
  /// (cambiando el estado a "Rescatado" se puede eliminar después);
  /// "Adoptado"/"Fallecido" son registros permanentes (pedido explícito de
  /// Eliza) sin ningún camino para desbloquearlos.
  static (String, String) mensajeBloqueoEliminar(String estado, String nombre) {
    switch (estado) {
      case 'Hogar de paso':
        return (
          'No se puede eliminar todavía',
          '${nombreDeAnimal(nombre, enFrase: true)} está en hogar de paso ahora mismo. Cambiá su estado a "Rescatado" primero, y después podés eliminar la publicación.',
        );
      case 'En proceso de adopción':
        return (
          'No se puede eliminar todavía',
          '${nombreDeAnimal(nombre, enFrase: true)} tiene un proceso de adopción en curso. Cambiá su estado primero, y después podés eliminar la publicación.',
        );
      case 'Regresado':
        return (
          'No se puede eliminar todavía',
          '$nombre está marcado como "Regresado". Cambiá su estado a "Rescatado" primero, y después podés eliminar la publicación.',
        );
      case 'Adoptado':
        return (
          'No se puede eliminar',
          '$nombre ya fue adoptado. Queda como registro permanente, no se puede eliminar.',
        );
      case 'Fallecido':
        return (
          'No se puede eliminar',
          '$nombre fue marcado como "Fallecido". Queda como registro permanente, no se puede eliminar.',
        );
      default:
        return (
          'No se puede eliminar',
          '$nombre no se puede eliminar en su estado actual.',
        );
    }
  }

  /// (título, mensaje) del bloqueo si [rescateId] todavía no se puede
  /// eliminar, o `null` si sí se puede — junta en un solo lugar los 3
  /// chequeos que antes vivían duplicados en mis_rescates_screen.dart y
  /// editar_rescate_screen.dart (hallazgo de auditoría de código).
  ///
  /// Los 3 chequeos corren en paralelo, no uno atrás del otro: en el caso
  /// más común (nada bloquea, se puede eliminar) los tres hacen falta
  /// igual, así que separarlos solo sumaba tiempo de espera sin necesidad
  /// (otro hallazgo de la misma auditoría). El costo es leer de más en el
  /// caso menos común donde el primer chequeo ya bloquea — un descarte
  /// barato frente a la demora de 3 viajes de red seguidos en el camino
  /// feliz.
  ///
  /// Tira una excepción si no se pudo verificar por conexión — el llamador
  /// la distingue con su propio try/catch, igual que el resto de los
  /// chequeos de esta clase (no se traga el error acá para no esconder
  /// una falla real de red detrás de un "sí se puede eliminar" falso).
  /// [rescatistaId] es el uid de quien está borrando (siempre el dueño: es
  /// el único a quien las pantallas le ofrecen el botón, y lo único que las
  /// reglas dejan borrar). No es opcional porque las consultas de
  /// solicitudes lo necesitan para que el servidor las acepte — ver
  /// SolicitudesRepository._hayAlguna.
  Future<(String, String)?> bloqueoParaEliminar({
    required String rescateId,
    required String nombre,
    required String rescatistaId,
  }) async {
    // Mismo _db que este repositorio (no FirebaseFirestore.instance a
    // secas) — así un test que inyecta un Firestore fake en
    // RescatesRepository ve ese mismo fake acá adentro, en vez de que
    // este chequeo se escape a la instancia real por su cuenta.
    // Futures con tipo propio (en vez de Future.wait + cast posicional):
    // las tres arrancan en paralelo igual, pero un futuro cast por índice
    // ('resultados[1] as ...') no avisa en tiempo de compilación si alguien
    // reordena o agrega un elemento a la lista — esto sí.
    final solicitudesRepo = SolicitudesRepository(db: _db);
    final futuroPendientes = solicitudesRepo.tienePendientesPara(
      rescateId,
      rescatistaId: rescatistaId,
    );
    final futuroDatos = obtener(rescateId).then((d) => d.data());
    final futuroAprobada = solicitudesRepo.tuvoSolicitudAprobada(
      rescateId,
      rescatistaId: rescatistaId,
    );

    final tienePendientes = await futuroPendientes;
    final datosActuales = await futuroDatos;
    final tuvoAprobada = await futuroAprobada;

    if (tienePendientes) {
      return (
        'No se puede eliminar todavía',
        '$nombre tiene una solicitud esperando respuesta. Aprobala o rechazala primero, y después podés eliminar la publicación.',
      );
    }
    final estadoActual =
        datosActuales?['estadoAdopcion'] as String? ?? 'Rescatado';
    if (estadoActual != 'Rescatado') {
      return mensajeBloqueoEliminar(estadoActual, nombre);
    }
    if (tuvoAprobada) {
      return (
        'No se puede eliminar',
        '$nombre tuvo una adopción o un hogar de paso aprobado alguna vez. '
            'Queda como registro permanente, marcalo como "Adoptado", "Regresado" o "Fallecido" en vez de eliminarlo.',
      );
    }
    return null;
  }

  /// Stream de varios rescates a la vez por su id — para pantallas como
  /// Favoritos, que necesitan el estado de N animales guardados sin abrir
  /// un listener por cada uno. Antes favoritos_screen.dart armaba esta
  /// consulta directo contra Firestore en vez de pasar por acá (hallazgo
  /// de auditoría de código — ver ARCHITECTURE.md).
  ///
  /// [ids] ya tiene que venir recortado a como mucho 30 (límite de
  /// Firestore para `whereIn`) — el recorte queda del lado del llamador
  /// porque suele necesitar saber CUÁLES ids terminaron consultados de
  /// verdad, para no confundir "no vino en la respuesta" con "nunca se
  /// preguntó por él" (ej. para detectar favoritos huérfanos).
  ///
  /// Con más de 30 ids, usar [porIdsSinTope] en vez de recortar acá: ese
  /// recorte silencioso es justo el bug real que tenía Favoritos (ver su
  /// doc).
  Stream<QuerySnapshot<Map<String, dynamic>>> porIds(List<String> ids) {
    if (ids.isEmpty) return const Stream.empty();
    return _col.where(FieldPath.documentId, whereIn: ids).snapshots();
  }

  /// Lo mismo que [porIds], pero sin el tope de 30 de `whereIn` — parte
  /// [ids] en tandas de 30 y combina sus streams en una sola lista que se
  /// actualiza cuando CUALQUIER tanda tiene novedades.
  ///
  /// Existe porque recortar a los primeros 30 (lo que hacía Favoritos, del
  /// lado del llamador) no es "mostrar de menos": el resto queda pegado
  /// para siempre en la copia vieja que el favorito guardó al crearse, sin
  /// ninguna forma de enterarse de un cambio de nombre/foto/ciudad más
  /// tarde — ni siquiera recargando la pantalla. Hallazgo real de Eliza:
  /// con 62 favoritos, uno de los que quedaba fuera de los primeros 30
  /// nunca reflejó un cambio de nombre, aunque el mismo cambio SÍ se veía
  /// en el feed y en "Mis animales".
  ///
  /// Devuelve la lista de documentos directamente (no un `QuerySnapshot`,
  /// que es intrínseco de UNA consulta) — con varias tandas combinadas ya
  /// no hay un único `QuerySnapshot` que las represente a todas.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> porIdsSinTope(
    List<String> ids,
  ) {
    if (ids.isEmpty) return Stream.value(const []);
    final tandas = <List<String>>[
      for (var i = 0; i < ids.length; i += 30)
        ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30),
    ];
    if (tandas.length == 1) {
      return _col
          .where(FieldPath.documentId, whereIn: tandas.single)
          .snapshots()
          .map((s) => s.docs);
    }
    // Combine-latest a mano: cada tanda es su propio listener en vivo: la
    // lista combinada se vuelve a emitir cada vez que CUALQUIERA de las
    // tandas tiene una novedad, con el último valor conocido de las demás
    // (no hace falta esperar a que las N respondan de nuevo a la vez).
    final ultimaPorTanda =
        List<List<QueryDocumentSnapshot<Map<String, dynamic>>>?>.filled(
          tandas.length,
          null,
        );
    final subs = <StreamSubscription<dynamic>>[];
    late final StreamController<
      List<QueryDocumentSnapshot<Map<String, dynamic>>>
    >
    controller;
    controller = StreamController.broadcast(
      onListen: () {
        for (var i = 0; i < tandas.length; i++) {
          final idx = i;
          subs.add(
            _col
                .where(FieldPath.documentId, whereIn: tandas[idx])
                .snapshots()
                .listen(
                  (snap) {
                    ultimaPorTanda[idx] = snap.docs;
                    if (ultimaPorTanda.every((t) => t != null)) {
                      controller.add(
                        ultimaPorTanda.expand((t) => t!).toList(),
                      );
                    }
                  },
                  onError: controller.addError,
                ),
          );
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }

  /// Crea un rescate y sube su(s) foto(s): "doc sin fotos → subir en
  /// paralelo → vincular" — antes duplicado (~80 líneas) entre
  /// subir_rescate_screen.dart y subir_lote_screen.dart (hallazgo de
  /// auditoría de código).
  ///
  /// [datos] son los campos propios del formulario (nombre, especie,
  /// etc. — SIN fotoUrl/fotoUrl2, eso lo agrega este método). [fotos] es
  /// la foto 1 (obligatoria) y, si hay, la 2 (opcional), ya normalizadas.
  /// [onProgreso] es opcional — el alta individual lo usa para su barra de
  /// progreso; el lote no pasa nada y no pierde nada por no pasarlo.
  ///
  /// Si algo falla ANTES de terminar (el doc, la foto obligatoria, o el
  /// paso de vincular), hace rollback completo (borra las fotos que
  /// llegaron a subir + el doc) y RELANZA la excepción tal cual — este
  /// método no decide qué mensaje mostrar ni si abortar del todo o seguir
  /// con el resto de un lote, eso lo resuelve cada pantalla llamadora con
  /// su propio try/catch, igual que antes.
  ///
  /// Si falla solo la foto 2 (opcional), no hay rollback: la publicación
  /// se completa igual y `foto2Fallo` queda en `true` para que el
  /// llamador pueda avisar "se publicó, pero la segunda foto no subió".
  Future<({String rescateId, bool foto2Fallo})> publicarConFotos({
    required String uid,
    required CreatorRole role,
    required Map<String, dynamic> datos,
    required List<Uint8List> fotos,
    void Function(double progreso)? onProgreso,
  }) async {
    final fotosRepo = _fotosRepo;
    String? rescateId;
    try {
      // El id se genera ACÁ (local, sin red) y se asigna a rescateId ANTES
      // del await de crear() — Future.timeout() no cancela la escritura
      // original, así que si el timeout se dispara primero, el create
      // puede terminar solo en segundo plano y crear el documento igual
      // cuando vuelva la señal. Con el id ya conocido, el rollback de
      // abajo sabe qué borrar aunque eso pase; si no, quedaba un rescate
      // fantasma sin foto (bug real reportado por Eliza).
      final nuevaRef = nuevoRef();
      rescateId = nuevaRef.id;
      await crear(ref: nuevaRef, uid: uid, role: role, datos: datos).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('No hay conexión a internet.'),
      );

      double progreso1 = 0, progreso2 = 0;
      var foto2Fallo = false;
      void actualizarProgreso() {
        onProgreso?.call(
          fotos.length > 1 ? (progreso1 + progreso2) / 2 : progreso1,
        );
      }

      // El timeout de cada subida vive DENTRO de fotosRepo.subir() (y
      // cancela la tarea nativa de verdad al vencer) — envolverlo acá
      // TAMBIÉN con su propio `.timeout()` no suma nada y puede abandonar
      // la espera antes de que la cancelación interna llegue a correr,
      // reabriendo el mismo hueco que esto arregla (ver el doc de subir()).
      final idRescate = rescateId;
      Future<String?> subirFoto2(Uint8List bytes) async {
        try {
          return await fotosRepo.subir(
            rescateId: idRescate,
            slot: 2,
            bytes: bytes,
            onProgreso: (p) {
              progreso2 = p;
              actualizarProgreso();
            },
          );
        } catch (_) {
          foto2Fallo = true;
          return null;
        }
      }

      final resultados = await Future.wait([
        fotosRepo.subir(
          rescateId: idRescate,
          slot: 1,
          bytes: fotos[0],
          onProgreso: (p) {
            progreso1 = p;
            actualizarProgreso();
          },
        ),
        if (fotos.length > 1) subirFoto2(fotos[1]),
      ]);
      final fotoUrl = resultados[0]!;
      final fotoUrl2 = resultados.length > 1 ? resultados[1] : null;

      await actualizar(rescateId, {
        'fotoUrl': fotoUrl,
        if (fotoUrl2 != null) 'fotoUrl2': fotoUrl2,
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('No hay conexión a internet.'),
      );

      return (rescateId: rescateId, foto2Fallo: foto2Fallo);
    } catch (_) {
      // Orden importa: storage.rules valida dueño de una foto leyendo
      // rescates/{id}.rescatistaId — si el doc de Firestore se borra
      // PRIMERO, esa lectura falla (documento inexistente) y la limpieza
      // de Storage queda con permission-denied, dejando fotos huérfanas.
      if (rescateId != null) {
        final id = rescateId;
        try {
          await fotosRepo
              .eliminarTodas(id)
              .timeout(const Duration(seconds: 10));
        } catch (_) {}
        try {
          await eliminar(id).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Resuelve los dos slots de fotos al EDITAR un rescate y devuelve las
  /// URLs que hay que guardar en el documento (`null` = ese slot queda
  /// vacío). Sube las nuevas, conserva las que no cambiaron, promociona la
  /// foto 2 al lugar de la 1 cuando hizo falta, y borra los archivos que
  /// dejaron de estar referenciados.
  ///
  /// Vivía inline en `editar_rescate_screen.dart` — la contraparte de
  /// [publicarConFotos], que ya estaba acá. Esa asimetría dejaba la parte
  /// más delicada del manejo de Storage (la única que BORRA y MUEVE
  /// archivos, no solo sube) sin ningún test posible, validada nada más
  /// que leyéndola.
  ///
  /// [nuevaFoto1]/[nuevaFoto2] son los bytes YA normalizados (igual que en
  /// [publicarConFotos]: normalizar corre en su propio isolate y es
  /// responsabilidad de la pantalla). `null` significa "no se eligió una
  /// foto nueva para ese slot". [urlExistente1]/[urlExistente2] son las
  /// URLs que la pantalla tiene en pantalla AHORA — ojo: después de quitar
  /// la foto 1 teniendo dos, `urlExistente1` apunta al archivo `foto2.jpg`,
  /// y eso es justamente lo que dispara la promoción.
  ///
  /// **Las tres reglas que no se ven leyendo una sola rama:**
  ///
  /// 1. **La promoción mueve el ARCHIVO, no la URL.** Los campos
  ///    `fotoUrl`/`fotoUrl2` prometen apuntar a `foto1.jpg`/`foto2.jpg`, y
  ///    el borrado por slot cuenta con eso. Copiando solo la URL, el mismo
  ///    guardado borraba `foto2.jpg` como "slot 2 ahora vacío" y la ficha
  ///    quedaba apuntando a un archivo borrado — el feed mostraba el emoji
  ///    de repuesto (bug real: "rarito 2").
  /// 2. **Nunca borrar un archivo que el otro campo todavía referencia.**
  ///    Red de seguridad independiente de la detección de promoción: para
  ///    que una foto se rompa tendrían que fallar las dos a la vez.
  /// 3. **Con promoción, los slots se resuelven en SERIE.** `moverFoto` lee
  ///    y borra `foto2.jpg`, y el slot 2 puede estar subiendo una foto
  ///    nueva a ese mismo path (quitar la 1 y agregar otra segunda foto en
  ///    la misma edición) — en paralelo se pisan. Sin promoción sí van en
  ///    paralelo: son independientes.
  Future<({String? fotoUrl, String? fotoUrl2})> resolverFotosAlEditar({
    required String rescateId,
    required Uint8List? nuevaFoto1,
    required Uint8List? nuevaFoto2,
    required String? urlExistente1,
    required String? urlExistente2,
    Duration timeoutBorrado = const Duration(seconds: 10),
  }) async {
    final fotosRepo = _fotosRepo;

    Future<String?> resolverSlot(int slot) async {
      final nueva = slot == 1 ? nuevaFoto1 : nuevaFoto2;
      final existente = slot == 1 ? urlExistente1 : urlExistente2;
      if (nueva != null) {
        // El timeout vive DENTRO de subir() (cancela la subida real al
        // vencer) — no se vuelve a envolver acá, ver el doc de ese método.
        return fotosRepo.subir(rescateId: rescateId, slot: slot, bytes: nueva);
      }
      if (existente != null) return existente;
      // Regla 2 (ver arriba). Si el otro slot tiene una foto NUEVA, su
      // campo va a quedar apuntando a su propio archivo recién subido —
      // este queda sin referencias y sí se puede borrar.
      final urlDelOtroSlot = slot == 1 ? urlExistente2 : urlExistente1;
      final nuevaDelOtroSlot = slot == 1 ? nuevaFoto2 : nuevaFoto1;
      final referenciadoPorOtroSlot =
          nuevaDelOtroSlot == null &&
          RescateFotosRepository.urlApuntaASlot(urlDelOtroSlot, slot);
      if (!referenciadoPorOtroSlot) {
        // Timeout acá sí (a diferencia de subir/moverFoto, que lo manejan
        // por dentro): Storage no encola los borrados sin señal, se quedan
        // esperando para siempre.
        await fotosRepo
            .eliminar(rescateId: rescateId, slot: slot)
            .timeout(timeoutBorrado);
      }
      return null;
    }

    // La detección es por PATH del archivo (no comparando contra la URL
    // inicial): así también repara documentos que ya quedaron cruzados por
    // este bug antes de que existiera el arreglo.
    final promocionPendiente =
        nuevaFoto1 == null &&
        RescateFotosRepository.urlApuntaASlot(urlExistente1, 2);

    if (promocionPendiente) {
      // Sin `.timeout()` acá afuera a propósito: moverFoto() ya está
      // acotado por dentro. Envolverlo TAMBIÉN podía darse por vencido
      // antes de que la cancelación interna llegara a correr — dos relojes
      // para lo mismo, y el de afuera no cancela nada real.
      final fotoMovida = await fotosRepo.moverFoto(
        rescateId: rescateId,
        deSlot: 2,
        aSlot: 1,
      );
      // null acá NO significa "sin foto": significa "no hubo nada que
      // mover" (el archivo de origen ya no estaba). En ese caso el campo
      // ya tenía una URL válida — por eso se detectó la promoción — así
      // que se conserva en vez de borrarla: perder la referencia sería
      // peor que dejarla como estaba.
      final fotoUrl = fotoMovida ?? urlExistente1;
      final fotoUrl2 = await resolverSlot(2); // Regla 3: en serie.
      return (fotoUrl: fotoUrl, fotoUrl2: fotoUrl2);
    }

    final resultados = await Future.wait([resolverSlot(1), resolverSlot(2)]);
    return (fotoUrl: resultados[0], fotoUrl2: resultados[1]);
  }
}
