import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_resiliencia.dart';

/// Centraliza las escrituras del campo `roles` en `usuarios/{uid}`
/// (antes se escribía suelto desde ~7 pantallas de debug distintas, sin
/// validar qué valores eran válidos).
class UsuariosRepository {
  UsuariosRepository({FirebaseFirestore? db, FirebaseAuth? auth})
    : _db = db ?? FirebaseFirestore.instance,
      _authOverride = auth;
  final FirebaseFirestore _db;
  // Lazy, mismo motivo que en RescatesRepository: evaluar FirebaseAuth.instance
  // en el constructor rompe cualquier test que no pase un auth mockeado.
  final FirebaseAuth? _authOverride;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  static const rolesValidos = {'adoptante', 'rescatista', 'albergue', 'aliado'};

  /// Todos los negocios aliados (`aliadoNombre` cargado), UNA sola vez —
  /// no en vivo.
  ///
  /// Por qué no `.snapshots()`: un stream en vivo primero pinta lo que haya
  /// en la CACHÉ local del teléfono (a veces vacía, a veces con apenas uno
  /// de una sesión anterior) y recién después el snapshot real del
  /// servidor con la lista completa — el efecto es ver aparecer un negocio
  /// y "al ratito" el resto. La lista de negocios no necesita vivir
  /// actualizada en tiempo real mientras la persona la mira (no es un chat),
  /// así que no vale la pena pagar ese parpadeo por algo que no hace falta.
  ///
  /// Esta consulta estaba copiada en 2 pantallas (adoptante_feed_screen.dart
  /// y aliados_screen.dart) — una se arregló primero, y la otra se quedó
  /// con la versión en vivo hasta que Eliza encontró el mismo síntoma ahí
  /// también. Que sea UN método achica ese riesgo a "un lugar para revisar",
  /// no "acordarse de buscar todas las copias" cada vez.
  Future<QuerySnapshot<Map<String, dynamic>>> aliados() =>
      _db.collection('usuarios').where('aliadoNombre', isGreaterThan: '').get();

  /// Completa las coordenadas del perfil a partir de su ciudad ya guardada.
  ///
  /// Existe para reparar perfiles de albergue creados antes de que guardar
  /// la ciudad exigiera geocodificarla: tienen `ciudad` pero no
  /// `latitud`/`longitud`, y como los animales de un albergue copian esas
  /// coordenadas del perfil (no del GPS, porque se publican desde el
  /// albergue), NINGUNO de sus animales podía mostrar distancia. Hallazgo
  /// real de Eliza: "todos los cargados desde albergues no muestran la
  /// distancia".
  ///
  /// Se escribe con merge y solo estos dos campos: es una reparación de
  /// fondo, nunca debe pisar nada más de lo que la persona tenga guardado.
  Future<void> completarCoordenadas({
    required String uid,
    required double latitud,
    required double longitud,
  }) => _db.collection('usuarios').doc(uid).set({
    'latitud': latitud,
    'longitud': longitud,
  }, SetOptions(merge: true));

  Future<void> actualizarRoles(String uid, List<String> roles) {
    if (!roles.every(rolesValidos.contains)) {
      throw ArgumentError('rol inválido en $roles');
    }
    // Un permission-denied acá casi siempre es un token vencido, no falta
    // de permiso real (ver conReintentoSiTokenVencido en
    // firestore_resiliencia.dart) — mismo patrón que
    // RescatesRepository.eliminar(). El bug real: justo después de un
    // borrado masivo de cuentas de prueba, una cuenta que recién inicia
    // sesión puede traer un token viejo, y antes esto se mostraba como
    // "revisá tu conexión" dejando a la persona trabada sin poder elegir rol.
    return conReintentoSiTokenVencido(
      () => _auth,
      () => _db.collection('usuarios').doc(uid).update({'roles': roles}),
    );
  }

  /// Crea el perfil inicial de la cuenta (onboarding). `SetOptions(merge: true)`
  /// a propósito: si el doc ya existía — por ejemplo porque la pantalla de
  /// selección de rol se mostró por un falso "no existe" de la caché — NO
  /// pisa campos que no son suyos (fcmToken, fotoBase64, albergueNombre,
  /// perfilAdopcion...). Antes esto era un `set()` sin merge directo en la
  /// pantalla y borraba el perfil entero de un usuario existente.
  Future<void> crearPerfil({
    required String uid,
    required String nombre,
    String? email,
    String? foto,
    required List<String> roles,
    String ciudad = '',
  }) {
    if (!roles.every(rolesValidos.contains)) {
      throw ArgumentError('rol inválido en $roles');
    }
    return conReintentoSiTokenVencido(
      () => _auth,
      () => _db.collection('usuarios').doc(uid).set({
        'nombre': nombre,
        'email': email,
        'foto': foto,
        'roles': roles,
        'ciudad': ciudad,
        'creadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
    );
  }

  /// Asegura que el doc usuarios/{uid} EXISTA apenas la cuenta inicia
  /// sesión, con sus datos básicos pero SIN roles — se llama desde el flujo
  /// de login (auth_helper.dart), antes de que la persona elija rol.
  ///
  /// Por qué existe: AuthWrapper (main.dart) solo puede mandar a una cuenta
  /// al onboarding cuando el SERVIDOR le confirma "este perfil no existe" —
  /// confiar en la caché mandaría a usuarios existentes a pisarse el perfil.
  /// Pero esa confirmación depende de que el canal de escucha de Firestore
  /// esté sano justo en ese momento, y tras un cambio de cuenta puede
  /// quedar mudo un rato — el bug real: una cuenta nueva (sin perfil) se
  /// quedaba en el spinner de arranque para siempre, mientras las cuentas
  /// CON perfil entraban al toque porque a ellas la caché les alcanza. Toda
  /// persona nueva pasa por ese camino frágil en su primer ingreso.
  ///
  /// Con este write el camino frágil desaparece: la escritura queda en la
  /// caché local al instante (ni siquiera necesita señal), el stream de
  /// AuthWrapper emite "existe" de inmediato, y el guard de roles vacíos lo
  /// manda a elegir rol sin esperar ninguna confirmación del servidor.
  ///
  /// merge: true y sin tocar `roles`, a propósito — sobre una cuenta
  /// existente esto solo refresca nombre/email/foto y no pisa nada más.
  Future<void> asegurarPerfilBase({
    required String uid,
    String? nombre,
    String? email,
    String? foto,
  }) {
    return _db.collection('usuarios').doc(uid).set({
      if (nombre != null && nombre.isNotEmpty) 'nombre': nombre,
      if (email != null && email.isNotEmpty) 'email': email,
      if (foto != null && foto.isNotEmpty) 'foto': foto,
    }, SetOptions(merge: true));
  }
}
