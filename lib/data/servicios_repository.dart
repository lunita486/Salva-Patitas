import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/reglas_negocio.dart';

/// Única puerta de entrada a la colección `servicios` (el catálogo de cada
/// negocio aliado). Ver ARCHITECTURE.md.
///
/// Existe porque esta colección se consultaba a mano desde 4 pantallas, y
/// eso dejó entrar CUATRO respuestas distintas a la misma pregunta —
/// "¿este servicio está activo?":
///
///   perfil público del aliado   → `activo == true`     (ausente = NO)
///   contador "Servicios activos"→ `activo == true`     (ausente = NO)
///   lista propia con su switch  → `activo ?? true`     (ausente = SÍ)
///   aviso al eliminar la cuenta → `.where('activo', isEqualTo: true)`
///                                 filtrado en la CONSULTA (ausente = NO)
///
/// Las dos primeras y la última decían que un servicio sin ese campo está
/// apagado; la tercera, que está encendido. Consecuencias reales: un
/// servicio así se le mostraba a su dueño con el interruptor en ON pero era
/// invisible para los clientes, y —lo más delicado— al borrar la cuenta la
/// app le decía que no tenía servicios activos y lo dejaba seguir.
///
/// La cuarta era la peor de arreglar sin este archivo: al filtrar dentro de
/// la consulta, Firestore descarta los documentos sin el campo ANTES de que
/// el código los vea, así que ninguna función compartida podía corregirlo
/// desde afuera. Por eso acá se trae por `aliadoId` y se filtra en memoria
/// con [servicioEstaActivo], la única fuente de esa regla.
class ServiciosRepository {
  ServiciosRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('servicios');

  /// Todos los servicios de [aliadoId], activos o no — para la lista propia
  /// del negocio, donde ver los apagados es justamente el punto (ahí están
  /// para poder volver a encenderlos).
  Stream<QuerySnapshot<Map<String, dynamic>>> deAliado(String aliadoId) =>
      _col.where('aliadoId', isEqualTo: aliadoId).snapshots();

  /// Solo los ACTIVOS de [aliadoId] — lo que ve un cliente en el perfil
  /// público. El filtro se aplica en memoria a propósito (ver el doc de la
  /// clase): filtrarlo en la consulta escondería los servicios sin el campo
  /// `activo`, que según [servicioEstaActivo] sí están activos.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> activosDeAliado(
    String aliadoId,
  ) => deAliado(
    aliadoId,
  ).map((s) => s.docs.where((d) => servicioEstaActivo(d.data())).toList());

  /// ¿[aliadoId] tiene al menos un servicio activo? Se usa para avisarle
  /// antes de borrar su cuenta.
  ///
  /// Sin `.limit(1)`: el filtro de "activo" ya no lo hace Firestore sino
  /// el código (ver el doc de la clase), así que cortar en 1 documento
  /// podría traer justo uno apagado y contestar "no tenés ninguno activo"
  /// teniendo otros encendidos.
  Future<bool> tieneServiciosActivos(String aliadoId) async {
    final snap = await _col.where('aliadoId', isEqualTo: aliadoId).get();
    return snap.docs.any((d) => servicioEstaActivo(d.data()));
  }

  /// Publica un servicio nuevo. `activo: true` se escribe acá y no en la
  /// pantalla: es parte de qué significa "crear un servicio", no una
  /// decisión de quién lo crea.
  Future<DocumentReference<Map<String, dynamic>>> crear({
    required String aliadoId,
    required Map<String, dynamic> datos,
  }) => _col.add({
    ...datos,
    'aliadoId': aliadoId,
    'activo': true,
    'creadoEn': FieldValue.serverTimestamp(),
  });

  Future<void> actualizar(String servicioId, Map<String, dynamic> datos) =>
      _col.doc(servicioId).update(datos);

  /// Enciende o apaga un servicio. Recibe el estado ACTUAL y lo invierte,
  /// en vez de recibir el nuevo valor: así quien llama no puede equivocarse
  /// calculando la negación por su cuenta.
  Future<void> alternarActivo({
    required String servicioId,
    required bool activoAhora,
  }) => _col.doc(servicioId).update({'activo': !activoAhora});

  Future<void> eliminar(String servicioId) => _col.doc(servicioId).delete();
}
