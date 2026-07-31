import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:patitas_medellin/services/notificaciones_service.dart';

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
      when(() => messaging.requestPermission(alert: true, badge: true, sound: true))
          .thenThrow(Exception('SERVICE_NOT_AVAILABLE'));
      when(() => messaging.setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true)).thenAnswer((_) async {});
      when(() => messaging.getToken()).thenAnswer((_) async => null);
      when(() => messaging.onTokenRefresh).thenAnswer((_) => const Stream.empty());

      await expectLater(NotificacionesService.inicializar(), completes);
    });

    test('NO lanza aunque getToken() falle', () async {
      when(() => messaging.requestPermission(alert: true, badge: true, sound: true))
          .thenAnswer((_) async => const NotificationSettings(
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
              providesAppNotificationSettings: AppleNotificationSetting.notSupported));
      when(() => messaging.setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true)).thenAnswer((_) async {});
      when(() => messaging.getToken()).thenThrow(Exception('SERVICE_NOT_AVAILABLE'));
      when(() => messaging.onTokenRefresh).thenAnswer((_) => const Stream.empty());

      await expectLater(NotificacionesService.inicializar(), completes);
    });

    test('NO lanza aunque TODOS los pasos fallen a la vez — el peor caso '
        'real', () async {
      when(() => messaging.requestPermission(alert: true, badge: true, sound: true))
          .thenThrow(Exception('sin Play Services'));
      when(() => messaging.setForegroundNotificationPresentationOptions(
              alert: true, badge: true, sound: true))
          .thenThrow(Exception('sin Play Services'));
      when(() => messaging.getToken()).thenThrow(Exception('sin Play Services'));
      when(() => messaging.onTokenRefresh)
          .thenThrow(Exception('sin Play Services'));

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
      when(() => messaging.getToken()).thenThrow(Exception('SERVICE_NOT_AVAILABLE'));

      await expectLater(NotificacionesService.guardarToken(), completes);
    });
  });
}
