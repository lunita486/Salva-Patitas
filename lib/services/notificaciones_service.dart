import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme.dart' show appTeal;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class NotificacionesService {
  static FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Para tests únicamente — reemplaza la instancia real por un mock antes
  /// de llamar a [inicializar]/[guardarToken]. No hay otra forma de
  /// inyectarla: esta clase se usa entera como namespace estático desde 4
  /// lugares de la app (main.dart y las 3 pantallas de inicio), convertirla
  /// a instancia habría significado tocar los 4 sin necesidad.
  @visibleForTesting
  static set debugMessagingParaTests(FirebaseMessaging messaging) =>
      _messaging = messaging;

  static FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Misma costura que [debugMessagingParaTests], por el mismo motivo, para
  /// poder probar [olvidarToken] con `fake_cloud_firestore`.
  @visibleForTesting
  static set debugFirestoreParaTests(FirebaseFirestore db) => _db = db;

  static StreamSubscription<RemoteMessage>? _foregroundSub;

  /// Nada acá adentro puede lanzar hacia afuera — ni un solo paso. main.dart
  /// espera este método ANTES de llamar a runApp(), así que una excepción
  /// sin atrapar acá no rompe "las notificaciones": deja a la persona
  /// mirando una pantalla en blanco para siempre, sin haber llegado siquiera
  /// a construir la UI (ni el login). Pasa de verdad en celulares sin
  /// Google Play Services (Huawei sin GMS, algunos emuladores) — ahí
  /// requestPermission()/getToken() tiran, no devuelven un valor vacío.
  ///
  /// Por eso cada paso atrapa su propio error y sigue con el siguiente en
  /// vez de un solo try/catch envolviendo todo: un celular sin permiso de
  /// notificaciones pero CON Play Services igual debería poder guardar su
  /// token (por si el permiso se concede después), no perder también eso
  /// porque el paso anterior falló.
  static Future<void> inicializar() async {
    try {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    } catch (e) {
      debugPrint(
        'NotificacionesService: no se pudo registrar el handler de fondo ($e)',
      );
    }

    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint(
        'NotificacionesService: no se pudo pedir permiso de notificaciones ($e)',
      );
    }

    try {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint(
        'NotificacionesService: no se pudo configurar notificaciones en primer plano ($e)',
      );
    }

    await guardarToken();

    // Refresca el token si cambia (ej. reinstalación)
    try {
      _messaging.onTokenRefresh.listen(
        (_) => guardarToken(),
        onError: (Object e) => debugPrint(
          'NotificacionesService: falló el refresh del token ($e)',
        ),
      );
    } catch (e) {
      debugPrint(
        'NotificacionesService: no se pudo escuchar el refresh del token ($e)',
      );
    }
  }

  /// Best-effort, a propósito no relanza nada: sin token guardado, esa
  /// cuenta simplemente no recibe notificaciones push (degradado, no
  /// roto) — pero esto lo llaman también, sin esperar la respuesta,
  /// 3 pantallas de inicio (albergue/aliado/adoptante), así que un error
  /// sin atrapar acá quedaba como excepción async sin manejar cada vez
  /// que alguien abría la app, además de ser el mismo riesgo de bloquear
  /// el arranque cuando lo llama inicializar() más arriba.
  static Future<void> guardarToken() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final token = await _messaging.getToken();
      if (token == null) return;
      // set+merge, no update(): un usuario nuevo (a mitad de onboarding,
      // antes de que exista usuarios/{uid}) o un refresh de token justo
      // tras el primer login puede llegar antes de que el doc exista —
      // update() fallaría con "not-found" en ese momento, que es al
      // arrancar la app.
      await _db.collection('usuarios').doc(uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('NotificacionesService: no se pudo guardar el token ($e)');
    }
  }

  /// Saca el token de este teléfono del perfil de la cuenta que está por
  /// cerrar sesión.
  ///
  /// Sin esto, el token quedaba en `usuarios/{uid}` PARA SIEMPRE: no había
  /// ninguna ruta de código que lo borrara (`guardarToken` lo escribe en
  /// cada arranque, y nada lo sacaba). El resultado, en un teléfono
  /// prestado o vendido: la cuenta A cierra sesión, entra la cuenta B, y
  /// las notificaciones de A —con el texto del mensaje privado adentro—
  /// siguen llegando a ese teléfono y se leen en la pantalla de bloqueo.
  /// Peor todavía, el mismo token queda escrito en los DOS perfiles, así
  /// que las dos cuentas empujan al mismo aparato.
  ///
  /// Se borra el campo en vez de escribir null: `notificar()` (functions/
  /// index.js) corta con `if (!token) return`, y un null lo satisface
  /// igual, pero dejar el campo con basura adentro invita a que alguien lo
  /// lea mal más adelante. Es además lo mismo que ya hace esa función
  /// cuando FCM le dice que el token murió.
  ///
  /// Best-effort igual que [guardarToken]: si falla, se sigue cerrando la
  /// sesión. Dejar a alguien atrapado adentro de la app por no poder
  /// escribir en Firestore sería peor que el problema que esto resuelve.
  ///
  /// [uid] se puede pasar explícito (los tests lo necesitan, porque
  /// `FirebaseAuth.instance` no tiene costura); en la app real se toma de
  /// la sesión que todavía está abierta.
  static Future<void> olvidarToken({String? uid}) async {
    try {
      final quien = uid ?? FirebaseAuth.instance.currentUser?.uid;
      if (quien == null) return;
      await _db
          .collection('usuarios')
          .doc(quien)
          .update({'fcmToken': FieldValue.delete()})
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('NotificacionesService: no se pudo olvidar el token ($e)');
    }
  }

  // Muestra un banner dentro del app cuando llega una notificación en primer plano.
  // Cancela la suscripción anterior para evitar listeners duplicados.
  //
  // NO se captura el ScaffoldMessenger acá arriba, de una sola vez: este
  // listener puede seguir vivo mucho después de que se registró (la
  // suscripción solo se cancela/renueva la próxima vez que alguien llame a
  // este método, típicamente al entrar a la home de otro rol) — si en el
  // medio la persona cierra sesión, la pantalla que lo registró se destruye
  // y una referencia guardada de antemano queda apuntando a un
  // ScaffoldMessengerState ya desmontado. Un push que llegue justo en esa
  // ventana (cerrar sesión → antes de que la pantalla de login o la próxima
  // home vuelvan a suscribirse) tiraba una excepción sin atrapar al intentar
  // mostrar el snackbar ahí. Por eso `context` se revisa y se resuelve DE
  // NUEVO cada vez que llega un mensaje, nunca por adelantado — hallazgo de
  // auditoría de código previa a subir a Play Store.
  static void escucharEnPrimerPlano(BuildContext context) {
    _foregroundSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen((
      RemoteMessage message,
    ) {
      if (!context.mounted) return;
      final notif = message.notification;
      if (notif == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notif.title ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if ((notif.body ?? '').isNotEmpty)
                Text(
                  notif.body ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
            ],
          ),
          backgroundColor: appTeal,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    });
  }
}
