import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un centinela, no una prueba de comportamiento.
///
/// **Qué vigila.** Que nadie agregue un deep link sin poner antes las
/// guardas de sesión en las rutas.
///
/// **Por qué hace falta.** La app tiene 24 rutas y ninguna comprueba, al
/// entrar, si hay una sesión abierta. Hoy eso no importa: la única forma de
/// llegar a cualquiera de ellas es tocando botones adentro de la app, y para
/// estar adentro hay que haber pasado por el login. Hay una sola puerta.
/// Incluso el botón de compartir manda a Play Store, no a la ficha del
/// animalito (ver compartir_animal.dart).
///
/// El día que eso cambie —un link que abra la app directo en un animalito,
/// que además es una mejora que vale la pena— aparecen 24 puertas de golpe y
/// ninguna mira quién pasa. Una pantalla que da por hecho que hay sesión
/// puede terminar en blanco o cerrándose sola.
///
/// **Por qué un test y no una nota.** Porque una nota depende de que alguien
/// se acuerde dentro de seis meses. Esto falla solo, en el momento exacto, y
/// le explica a quien lo rompió qué tiene que hacer antes de seguir.
///
/// Si estás leyendo esto porque el test falló: no borres el test. Poné la
/// guarda de sesión en `lib/routing/app_router.dart` (un `redirect` que
/// mande a `/` cuando no hay `FirebaseAuth.instance.currentUser`, excluyendo
/// la propia `/` para no hacer un bucle) y después agregá acá el deep link
/// que estás sumando, como esperado.
void main() {
  test('no hay deep links sin guardas de sesión en las rutas', () {
    final manifiesto = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    // Solo interesa lo que está dentro de <application>: el bloque
    // <queries> de más abajo también menciona VIEW y https, pero eso es
    // para PREGUNTAR qué apps pueden abrir un link, no para recibirlos.
    final app = manifiesto.substring(
      manifiesto.indexOf('<application'),
      manifiesto.indexOf('</application>'),
    );

    final filtros = RegExp(
      r'<intent-filter[\s\S]*?</intent-filter>',
    ).allMatches(app).map((m) => m.group(0)!);

    final conDeepLink = filtros
        .where((f) => f.contains('android.intent.action.VIEW'))
        .toList();

    expect(
      conDeepLink,
      isEmpty,
      reason:
          'Alguien agregó un deep link al AndroidManifest. A partir de '
          'ahora las 24 rutas de la app son alcanzables desde afuera, y '
          'ninguna comprueba si hay sesión abierta. Poné la guarda de '
          'sesión en lib/routing/app_router.dart ANTES de seguir, y recién '
          'después actualizá este test. Ver el comentario de arriba.',
    );
  });

  // La contraprueba: si el test no sabe encontrar un deep link, no vigila
  // nada y pasaría para siempre sin que nadie lo note.
  test('y el centinela sabe reconocer uno cuando lo hay', () {
    const conDeepLink = '''
<application android:label="Salva Patitas">
  <activity android:name=".MainActivity">
    <intent-filter>
      <action android:name="android.intent.action.MAIN"/>
      <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter>
    <intent-filter android:autoVerify="true">
      <action android:name="android.intent.action.VIEW"/>
      <category android:name="android.intent.category.BROWSABLE"/>
      <data android:scheme="https" android:host="salvapatitas.app"/>
    </intent-filter>
  </activity>
</application>
''';
    final filtros = RegExp(
      r'<intent-filter[\s\S]*?</intent-filter>',
    ).allMatches(conDeepLink).map((m) => m.group(0)!);
    expect(
      filtros.where((f) => f.contains('android.intent.action.VIEW')),
      hasLength(1),
      reason: 'si esto falla, el test de arriba no está mirando nada',
    );
  });
}
