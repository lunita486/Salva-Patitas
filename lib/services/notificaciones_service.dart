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
  static set debugMessagingParaTests(FirebaseMessaging messaging) => _messaging = messaging;

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
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('NotificacionesService: no se pudo registrar el handler de fondo ($e)');
    }

    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('NotificacionesService: no se pudo pedir permiso de notificaciones ($e)');
    }

    try {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('NotificacionesService: no se pudo configurar notificaciones en primer plano ($e)');
    }

    await guardarToken();

    // Refresca el token si cambia (ej. reinstalación)
    try {
      _messaging.onTokenRefresh.listen(
        (_) => guardarToken(),
        onError: (Object e) =>
            debugPrint('NotificacionesService: falló el refresh del token ($e)'),
      );
    } catch (e) {
      debugPrint('NotificacionesService: no se pudo escuchar el refresh del token ($e)');
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
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('NotificacionesService: no se pudo guardar el token ($e)');
    }
  }

  // Muestra un banner dentro del app cuando llega una notificación en primer plano.
  // Cancela la suscripción anterior para evitar listeners duplicados.
  static void escucharEnPrimerPlano(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context); // captura antes de async gap
    _foregroundSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notif = message.notification;
      if (notif == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notif.title ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              if ((notif.body ?? '').isNotEmpty)
                Text(notif.body ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          backgroundColor: appTeal,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    });
  }
}
