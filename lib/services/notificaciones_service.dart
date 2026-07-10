import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class NotificacionesService {
  static final _messaging = FirebaseMessaging.instance;
  static StreamSubscription<RemoteMessage>? _foregroundSub;

  static Future<void> inicializar() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await guardarToken();

    // Refresca el token si cambia (ej. reinstalación)
    _messaging.onTokenRefresh.listen((_) => guardarToken());
  }

  static Future<void> guardarToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final token = await _messaging.getToken();
    if (token == null) return;
    // set+merge, no update(): un usuario nuevo (a mitad de onboarding, antes
    // de que exista usuarios/{uid}) o un refresh de token justo tras el
    // primer login puede llegar antes de que el doc exista — update()
    // fallaría con "not-found" en ese momento, que es al arrancar la app.
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .set({'fcmToken': token}, SetOptions(merge: true));
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
          backgroundColor: const Color(0xFF1F8A62),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    });
  }
}
