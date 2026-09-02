import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:salva_patitas/services/notificaciones_service.dart';

// El caso real que esto prueba: un celular sin Google Play Services (Huawei
// sin GMS, algunos emuladores) hace que requestPermission()/getToken()
// LANCEN en vez de devolver un valor vacío. main.dart espera a
// NotificacionesService.inicializar() antes de runApp() — sin que este
// método atrape sus propios errores, esa excepción dejaba a la app entera
// sin arrancar nunca, ni siquiera hasta el login.
class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

void main() {
  late MockFirebaseMessaging messaging;

  setUp(() {
    messaging = MockFirebaseMessaging();
    NotificacionesService.debugMessagingParaTests = messaging;
  });

  group('NotificacionesService.inicializar()', () {
    test('NO lanza aunque requestPermission() falle (el caso real: celular '
        'sin Google Play Services)', () async {
      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenThrow(Exception('SERVICE_NOT_AVAILABLE'));
      when(
        () => messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        ),
      ).thenAnswer((_) async {});
      when(() => messaging.getToken()).thenAnswer((_) async => null);
      when(
        () => messaging.onTokenRefresh,
      ).thenAnswer((_) => const Stream.empty());

      await expectLater(NotificacionesService.inicializar(), completes);
    });

    test('NO lanza aunque getToken() falle', () async {
      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer(
        (_) async => const NotificationSettings(
          authorizationStatus: AuthorizationStatus.authorized,
          alert: AppleNotificationSetting.enabled,
          announcement: AppleNotificationSetting.notSupported,
          badge: AppleNotificationSetting.enabled,
          carPlay: AppleNotificationSetting.notSupported,
          lockScreen: AppleNotificationSetting.notSupported,
          notificationCenter: AppleNotificationSetting.notSupported,
          showPreviews: AppleShowPreviewSetting.always,
          timeSensitive: AppleNotificationSetting.notSupported,
          criticalAlert: AppleNotificationSetting.notSupported,
          sound: AppleNotificationSetting.enabled,
          providesAppNotificationSettings:
              AppleNotificationSetting.notSupported,
        ),
      );
      when(
        () => messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        ),
      ).thenAnswer((_) async {});
      when(
        () => messaging.getToken(),
      ).thenThrow(Exception('SERVICE_NOT_AVAILABLE'));
      when(
        () => messaging.onTokenRefresh,
      ).thenAnswer((_) => const Stream.empty());

      await expectLater(NotificacionesService.inicializar(), completes);
    });

    test('NO lanza aunque TODOS los pasos fallen a la vez — el peor caso '
        'real', () async {
      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenThrow(Exception('sin Play Services'));
      when(
        () => messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        ),
      ).thenThrow(Exception('sin Play Services'));
      when(
        () => messaging.getToken(),
      ).thenThrow(Exception('sin Play Services'));
      when(
        () => messaging.onTokenRefresh,
      ).thenThrow(Exception('sin Play Services'));

      await expectLater(NotificacionesService.inicializar(), completes);
    });
  });

  group('NotificacionesService.guardarToken()', () {
    // guardarToken() empieza con FirebaseAuth.instance, un singleton real
    // sin punto de inyección (mismo límite ya documentado en
    // auth_helper_test.dart) — en este entorno de test, sin Firebase
    // inicializado, ESO tira antes de llegar a getToken(). Sirve igual
    // como prueba: confirma que ni siquiera esa falla más temprana se
    // escapa hacia afuera, que es exactamente la garantía que importa acá
    // (3 pantallas llaman a este método sin esperar la respuesta — un
    // error sin atrapar quedaba como excepción async sin manejar cada vez
    // que alguien abría la app).
    test('NO lanza ni con FirebaseAuth sin inicializar ni con getToken() '
        'fallando', () async {
      when(
        () => messaging.getToken(),
      ).thenThrow(Exception('SERVICE_NOT_AVAILABLE'));

      await expectLater(NotificacionesService.guardarToken(), completes);
    });
  });

  // ── P1 de la auditoría del 2026-08-25 ────────────────────────────────
  //
  // El token de este teléfono se escribía en usuarios/{uid} en cada
  // arranque y NADA lo borraba nunca. En un teléfono prestado o vendido,
  // la cuenta A cerraba sesión, entraba B, y las notificaciones de A
  // seguían llegando a ese aparato — con el texto del mensaje privado
  // visible en la pantalla de bloqueo.
  group('olvidarToken()', () {
    test('saca el token del perfil de quien cierra sesión', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('usuarios').doc('ana').set({
        'nombre': 'Ana',
        'fcmToken': 'token-de-este-telefono',
      });
      NotificacionesService.debugFirestoreParaTests = db;

      await NotificacionesService.olvidarToken(uid: 'ana');

      final d = (await db.collection('usuarios').doc('ana').get()).data()!;
      expect(d.containsKey('fcmToken'), isFalse, reason: 'el campo se borra');
      expect(d['nombre'], 'Ana', reason: 'y no se lleva puesto el resto');
    });

    // Lo que NO debe pasar: que un fallo acá deje a alguien atrapado dentro
    // de la app. cerrarSesion() lo llama sin protección propia, así que si
    // esto relanzara, el signOut nunca correría.
    test('un perfil que no existe no lanza', () async {
      final db = FakeFirebaseFirestore();
      NotificacionesService.debugFirestoreParaTests = db;
      await expectLater(
        NotificacionesService.olvidarToken(uid: 'no_existe'),
        completes,
      );
    });

    test('sin uid y sin sesión, no hace nada y no lanza', () async {
      final db = FakeFirebaseFirestore();
      NotificacionesService.debugFirestoreParaTests = db;
      await expectLater(NotificacionesService.olvidarToken(), completes);
    });
  });

  // ── Quién llama a guardarToken(), y cuándo ───────────────────────────
  //
  // El token se borraba de forma confiable (olvidarToken en cada cierre de
  // sesión, y el servidor cuando FCM avisa que murió) y se escribía de
  // forma oportunista: inicializar(), que corre antes de runApp() y no hace
  // nada si Auth todavía no restauró la sesión, más un postFrameCallback en
  // 3 de las 4 pantallas de inicio. La del adoptante no lo llamaba.
  //
  // Medido en producción el 2026-09-02: 5 de 23 cuentas sin token, y las
  // activas más recientemente eran justo esas. Caso real: los avisos de
  // fallecimiento de Lucía quedaron bien escritos en Firestore y no le
  // llegó ninguna notificación.
  //
  // Se prueba leyendo el fuente porque el gancho vive en el State privado
  // de AuthWrapper y arranca desde FirebaseAuth.instance, que no tiene
  // costura (mismo límite ya documentado más arriba en este archivo y en
  // auth_helper_test.dart). Mismo patrón que las guardas de
  // solicitudes_repository_test.dart sobre cambiar_estado_sheet.dart.
  group(
    'el guardado del token está atado al comienzo de sesión (main.dart)',
    () {
      final fuente = File('lib/main.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      // El cuerpo del gancho que corre una vez por sesión con el uid ya
      // resuelto y el perfil ya existente.
      final gancho = fuente.substring(
        fuente.indexOf('void _sincronizarEfectosDeSesion('),
      );

      test('_sincronizarEfectosDeSesion guarda el token', () {
        expect(
          gancho,
          contains('NotificacionesService.guardarToken()'),
          reason:
              'volvió a no haber ningún punto de guardado atado al login: '
              'una cuenta que cierra sesión y vuelve a entrar sin reiniciar la '
              'app queda sin token, y sin push',
        );
      });

      test('una vez por sesión, no en cada snapshot del perfil', () {
        // Solo el cuerpo del `if` de la guarda: desde que se marca el uid
        // hasta el `}` que cierra ese bloque (4 espacios de sangría, el
        // primero que aparece). Una llamada puesta DESPUÉS de ese `}` corre
        // con cada snapshot, que es justo lo que hay que impedir.
        final desdeLaGuarda = gancho.substring(
          gancho.indexOf('_ultimaVezActivaMarcadaParaUid = user.uid;'),
        );
        final cuerpoDeLaGuarda = desdeLaGuarda.substring(
          0,
          desdeLaGuarda.indexOf('\n    }'),
        );
        expect(
          cuerpoDeLaGuarda,
          contains('NotificacionesService.guardarToken()'),
          reason:
              'quedó fuera de la guarda: este método corre con CADA '
              'snapshot del perfil, y guardarToken() hace un getToken() más '
              'una escritura',
        );
      });
    },
  );
}
