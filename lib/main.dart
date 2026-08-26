import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'data/auth_helper.dart';
import 'domain/resolucion_perfil.dart';
import 'routing/app_router.dart';
import 'screens/login_screen.dart';
import 'screens/seleccion_rol_screen.dart';
import 'screens/albergue_perfil_screen.dart';
import 'screens/albergue_home_screen.dart';
import 'screens/aliado_perfil_screen.dart';
import 'screens/aliado_home_screen.dart';
import 'screens/home_screen.dart';
import 'services/notificaciones_service.dart';
import 'data/sandbox.dart';

// Instancia única compartida por toda la app — Fase 2 (eventos propios como
// "solicitud_enviada") la va a importar desde acá en vez de crear la suya.
final FirebaseAnalytics analytics = FirebaseAnalytics.instance;
final FirebaseAnalyticsObserver analyticsObserver = FirebaseAnalyticsObserver(
  analytics: analytics,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // targetSdk 36 (Android 15+) fuerza edge-to-edge a nivel de sistema
  // operativo sin importar lo que diga el theme nativo — sin este llamado,
  // el engine de Flutter y el OS pelean por quién dibuja la barra de
  // estado en cada frame. Hallazgo real de Eliza: en el Samsung Z Flip 6
  // (One UI, Android 15+) eso se vio como la barra de estado parpadeando
  // justo después del login y la app cerrándose sola — coincide con el
  // momento en que se abre el diálogo de permiso de ubicación en
  // AdoptanteFeedScreen, que agrega una transición de ventana más al
  // mismo instante.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Modo sandbox: redirige los SDK a los emuladores locales. Va ACÁ, pegado
  // a initializeApp y antes de cualquier lectura — los SDK no aceptan que se
  // les cambie el destino una vez que ya hablaron con el servidor. En un
  // build de release `enSandbox` es una constante falsa y todo esto se
  // elimina del binario (ver sandbox.dart).
  if (enSandbox) await conectarEmuladores();

  // Los dos manejadores de acá cubren errores DISTINTOS: FlutterError.
  // onError es lo que Flutter dispara para errores durante el build/layout/
  // paint de un widget (ej. un RenderBox roto); PlatformDispatcher.instance.
  // onError es la puerta de errores async fuera de ese ciclo (un Future que
  // rompe sin que nadie lo esperara — incluida la inicialización de abajo,
  // que ya no se espera). Sin los dos, la mitad de los crashes reales
  // seguiría sin llegar nunca a Crashlytics. Se instalan ANTES de runApp()
  // a propósito, aunque ya no dependen de setCrashlyticsCollectionEnabled()
  // (más abajo) para funcionar — el SDK encola los reportes igual mientras
  // esa llamada todavía está en vuelo.
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // App Check, Crashlytics y notificaciones YA NO bloquean el primer frame.
  // Antes los tres se esperaban acá, antes de runApp() — y el peor caso
  // (NotificacionesService pidiendo permiso de notificaciones) dejaba a la
  // persona mirando el splash nativo hasta que tocara "Permitir"/"No
  // permitir" en el diálogo del sistema, en la primerísima apertura de la
  // app. Ninguno de los tres hace falta para dibujar el login/feed —
  // corren en paralelo mientras la persona ya está viendo la app. Hallazgo
  // real de Eliza: "tarda un poco en entrar" al abrir por primera vez tras
  // instalar. Medido con el APK60 real (`adb shell am start -W`): 8.85s
  // hasta el diálogo de permiso en la instalación nueva, 4s en arranques
  // en frío posteriores — ambos por encima del umbral de 5s que Android
  // Vitals marca como mal comportamiento.
  unawaited(_inicializarEnSegundoPlano());

  runApp(const PatitasApp());
}

/// Ver el comentario en `main()`. Nada acá adentro puede demorar el primer
/// frame: no se espera este Future antes de `runApp()`. Un error acá cae en
/// `PlatformDispatcher.instance.onError` (ya instalado arriba) salvo
/// notificaciones, que además atrapa el suyo propio — nada de esto debería
/// poder impedir que la app arranque.
Future<void> _inicializarEnSegundoPlano() async {
  // Play Integrity solo existe para builds firmados/distribuidos de verdad
  // (Play Store o instalación directa de un APK release) — en debug (el
  // emulador, `flutter run`) no hay forma de que pase esa verificación, así
  // que se usa el proveedor `debug` en su lugar. Todavía NO hay ningún
  // servicio de Firebase exigiendo este token (Firestore/Storage/Functions
  // siguen aceptando pedidos sin él) — activar esto acá solo empieza a
  // generar los tokens; el día que se decida exigirlos desde la consola,
  // ya van a estar viajando en cada pedido de quien tenga esta versión o
  // una más nueva instalada.
  await FirebaseAppCheck.instance.activate(
    androidProvider: kDebugMode
        ? AndroidProvider.debug
        : AndroidProvider.playIntegrity,
  );

  // Apagado en debug: sin esto, cada excepción de una sesión de desarrollo
  // (la tuya, la mía probando en el emulador) ensucia el panel de
  // Crashlytics de producción mezclada con crashes reales de gente usando
  // la app de verdad — quedaría imposible distinguir una cosa de la otra.
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    !kDebugMode,
  );

  // Ya se protege sola por dentro (cada paso atrapa su propio error — ver
  // ese archivo); este try/catch es la segunda red, para que algo nuevo
  // que se agregue ahí en el futuro y se olvide de atrapar su error no
  // rompa esta cadena a mitad de camino.
  try {
    await NotificacionesService.inicializar();
  } catch (e) {
    debugPrint('No se pudo inicializar notificaciones: $e');
  }
}

class PatitasApp extends StatelessWidget {
  const PatitasApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Salva Patitas',
      debugShowCheckedModeBanner: false,
      // Sin esto, los widgets que trae Material con texto propio salen en
      // INGLÉS adentro de una app que está entera en español. El caso que
      // se veía: el selector de fechas del hogar de paso decía "Select
      // date", "August 2026" y los días "S M T W T F S". También afecta al
      // menú de copiar/pegar y al selector de hora.
      //
      // `localeResolutionCallback` fuerza español pase lo que pase: sin él,
      // un teléfono configurado en otro idioma seguiría viendo esos widgets
      // en el suyo, mientras que TODO el resto de la app (que está escrita
      // a mano en español) no cambiaría. Media app en un idioma y media en
      // otro es peor que toda en español.
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('es')],
      localeResolutionCallback: (_, __) => const Locale('es'),
      // El observer de Analytics ("screen_view" automático en cada cambio
      // de pantalla) ahora se pasa al GoRouter (ver lib/routing/
      // app_router.dart), no acá — MaterialApp.router no tiene
      // navigatorObservers propio, el Navigator vive adentro del router.
      // Antes ThemeData(useMaterial3: true) sin colorScheme ni textTheme —
      // cada pantalla pintaba sus propios colores a mano (257 Color(0xFF...)
      // hardcodeados, medido en la auditoría previa a subir a Play). Esto no
      // reemplaza esos estilos explícitos (siguen ganando ellos), solo le da
      // una base coherente con la marca a cualquier widget de Material que
      // NO tenga un color propio puesto (ej. Checkbox/Radio/Switch, que hoy
      // casi no se usan en la app — bajo riesgo de que algo se vea distinto).
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: appBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: appTeal,
          primary: appTeal,
          secondary: appOrange,
          surface: Colors.white,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: appInk,
          displayColor: appInk,
        ),
      ),
      routerConfig: appRouter,
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});
  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  // Cambiar la key recrea el StreamBuilder del perfil, forzando una
  // suscripción NUEVA a Firestore — es lo que hace el botón "Reintentar"
  // de _CargaConSalida cuando la primera se queda muda.
  int _intento = 0;

  // ── Efectos de sesión (sync de foto, sello de actividad) ─────────────
  // Viven en una suscripción propia, separada de los StreamBuilder que
  // arman la UI de abajo. Antes las dos escrituras pasaban DENTRO del
  // builder del StreamBuilder del perfil — funcionaban, pero dependían
  // enteramente de que build() se llamara solo por los motivos que este
  // código anticipaba. Flutter puede volver a llamar build() por
  // cualquier otro motivo (un rebuild del padre, un cambio de tema, un
  // InheritedWidget del que este árbol dependa) sin que eso signifique
  // "cambió la sesión" — y una escritura a Firestore metida ahí no tiene
  // forma de distinguir un motivo del otro. Acá SÍ: solo corren cuando
  // authStateChanges() emite de verdad, o cuando el doc de perfil de la
  // cuenta actual cambia de verdad.
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot>? _perfilSub;
  String? _perfilSubUid;

  // Guarda para QUÉ cuenta ya se escribió 'ultimaVezActiva' en este
  // proceso — String? con el uid, no un bool. Un bool simple ("¿ya
  // escribí ALGUNA vez?") tiene el problema que motivó este arreglo: la
  // app soporta cambiar de cuenta sin cerrar sesión (ver "Cerrar sesión y
  // volver a entrar" en _CargaConSalida), y _AuthWrapperState vive para
  // TODO el proceso de la app, no por sesión — con un bool, la cuenta B
  // nunca quedaba registrada si la cuenta A ya lo había hecho antes en el
  // mismo proceso. Guardar el uid y compararlo contra la cuenta ACTUAL
  // deja escribir de nuevo apenas cambia de quién se trata.
  String? _ultimaVezActivaMarcadaParaUid;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen(
      _onCambioDeSesion,
    );
  }

  void _onCambioDeSesion(User? user) {
    if (user == null) {
      // Lista para la próxima cuenta que inicie sesión en este mismo
      // proceso — incluso si es la MISMA cuenta de antes, cerrar sesión y
      // volver a entrar cuenta como una entrada nueva de verdad, no algo
      // ya registrado.
      _ultimaVezActivaMarcadaParaUid = null;
      _perfilSub?.cancel();
      _perfilSub = null;
      _perfilSubUid = null;
      return;
    }
    if (_perfilSubUid == user.uid)
      return; // ya hay efectos suscriptos a esta cuenta
    _perfilSub?.cancel();
    _perfilSubUid = user.uid;
    _perfilSub = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .snapshots()
        .listen((snap) => _sincronizarEfectosDeSesion(user, snap));
  }

  void _sincronizarEfectosDeSesion(User user, DocumentSnapshot snap) {
    if (!snap.exists) return;
    final data = snap.data() as Map<String, dynamic>;

    // `foto` solo se escribía una vez, al crear el perfil (ver
    // UsuariosRepository.crearPerfil) — si la cuenta se creó cuando el
    // photoURL de Google todavía no estaba disponible (o cambió después),
    // quedaba null para siempre. Otras pantallas del chat necesitan poder
    // mostrar la foto de la CONTRAPARTE leyendo este campo (no pueden usar
    // FirebaseAuth, que solo expone al usuario propio), así que acá se
    // mantiene sincronizado de forma oportunista cada vez que llega un
    // snapshot nuevo del perfil de la cuenta activa.
    final fotoAuth = user.photoURL;
    if (fotoAuth != null && fotoAuth != data['foto']) {
      FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .update({'foto': fotoAuth})
          .catchError((_) {});
    }

    // Sello de "última vez activa" — antes no había NINGÚN dato que dijera
    // qué días entró alguien a la app, solo el último login de Firebase
    // Auth (que ni se actualiza si la sesión ya estaba guardada). Una
    // escritura por sesión alcanza para reconstruir un historial real de
    // actividad día por día (pedido real de Eliza, mientras revisaba quién
    // venía probando la app).
    if (_ultimaVezActivaMarcadaParaUid != user.uid) {
      _ultimaVezActivaMarcadaParaUid = user.uid;
      FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .update({'ultimaVezActiva': FieldValue.serverTimestamp()})
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _perfilSub?.cancel();
    super.dispose();
  }

  Future<void> _reintentar() async {
    // Además de recrear la suscripción, se apaga y prende la red de
    // Firestore: después de un cambio de cuenta, el canal de escucha puede
    // quedar mudo (reintentando por dentro con un token viejo), y volver a
    // suscribirse sobre ese mismo canal muerto no cambia nada. El ciclo
    // fuerza canales nuevos con el token de la cuenta actual.
    try {
      await FirebaseFirestore.instance.disableNetwork().timeout(
        const Duration(seconds: 5),
      );
      await FirebaseFirestore.instance.enableNetwork().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {}
    if (mounted) setState(() => _intento++);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _CargaConSalida();
        }
        if (snap.data == null) {
          return const LoginScreen();
        }
        return StreamBuilder<DocumentSnapshot>(
          key: ValueKey('perfil-$_intento'),
          stream: FirebaseFirestore.instance
              .collection('usuarios')
              .doc(snap.data!.uid)
              .snapshots(),
          builder: (context, userSnap) {
            // Sin esto, un error del stream (regla denegada, red caída a
            // mitad de la suscripción) dejaba hasData=false para siempre →
            // caía al spinner de abajo y nunca salía de ahí.
            if (userSnap.hasError) {
              return _CargaConSalida(
                onReintentar: _reintentar,
                mensajeInmediato: true,
              );
            }
            if (userSnap.connectionState == ConnectionState.waiting) {
              return _CargaConSalida(onReintentar: _reintentar);
            }
            if (!userSnap.hasData || !userSnap.data!.exists) {
              // La caché puede decir "no existe" por un instante para una
              // cuenta que SÍ tiene perfil (arranque en frío / red lenta).
              // Solo se va al onboarding cuando el "no existe" viene del
              // servidor; mientras tanto, spinner. Si no, un usuario
              // existente podía caer en SeleccionRolScreen y pisarse el
              // perfil al tocar Continuar.
              //
              // PERO ese "mientras tanto" no puede ser infinito: para una
              // cuenta que de verdad no tiene perfil todavía, esta espera
              // depende 100% de que el servidor conteste — y si la red
              // parpadea justo acá, no contesta nunca. El bug real de
              // facturasmaxiloncheras: su login con Google salía BIEN
              // (confirmado en los registros del servidor), pero al ser la
              // única cuenta sin perfil creado caía siempre en esta espera
              // sin timeout, sin botón, sin salida — "la bendita cuenta
              // porquería se queda cargando y cargando". Las cuentas con
              // perfil pasaban al toque (la caché ya les alcanzaba), por
              // eso parecía que una sola cuenta estaba maldita.
              // _CargaConSalida ofrece reintentar/salir pasados unos
              // segundos.
              if (!userSnap.hasData || userSnap.data!.metadata.isFromCache) {
                return _CargaConSalida(onReintentar: _reintentar);
              }
              return SeleccionRolScreen(user: snap.data!);
            }
            final data = userSnap.data!.data() as Map<String, dynamic>;
            switch (resolverPantallaPerfil(data)) {
              // Documento que existe pero sin ningún rol = perfil a medio
              // crear (caso real: un login que se colgó a mitad del
              // onboarding dejó un doc con solo fcmToken y foto — los
              // servicios de fondo escriben esos campos apenas hay
              // sesión, antes de que la persona elija rol). Sin este
              // chequeo, esa cuenta salteaba la selección de rol para
              // siempre y caía a HomeScreen sin nombre ni rol. Se la
              // manda al onboarding, que completa el perfil con merge
              // (no pisa lo que ya haya).
              case PantallaPerfil.seleccionRol:
                // Mismo motivo que el chequeo de "!exists" de más arriba:
                // el PRIMER snapshot después de reinstalar la app (caché
                // local recién vaciada) puede llegar desde caché sin
                // `roles` todavía, un instante antes de que el snapshot
                // real del servidor lo corrija con el perfil completo —
                // sin este chequeo, una cuenta YA registrada (con rol)
                // veía un flash de la pantalla de selección de rol antes
                // de entrar a la app de verdad. Hallazgo real de Eliza:
                // pasaba solo la primera vez después de reinstalar.
                if (userSnap.data!.metadata.isFromCache) {
                  return _CargaConSalida(onReintentar: _reintentar);
                }
                return SeleccionRolScreen(user: snap.data!);
              case PantallaPerfil.alberguePerfil:
                return const AlberguePerfilScreen();
              case PantallaPerfil.albergueHome:
                return const AlbergueHomeScreen();
              case PantallaPerfil.aliadoPerfil:
                return const AliadoPerfilScreen();
              case PantallaPerfil.aliadoHome:
                return const AliadoHomeScreen();
              case PantallaPerfil.home:
                return const HomeScreen();
            }
          },
        );
      },
    );
  }
}

/// Pantalla de carga del arranque que NUNCA puede volverse una trampa: si
/// pasa más de unos segundos (red muda, servidor que no confirma), muestra
/// un aviso con "Reintentar" y "Cerrar sesión y volver a entrar" en vez de
/// dejar a la persona mirando el circulito para siempre.
///
/// Existe porque el spinner de AuthWrapper era el ÚNICO estado de la app
/// sin timeout ni escape — todos los reportes de "se queda cargando y no
/// puedo hacer nada, toca cerrar la app a la fuerza" terminaban acá, no en
/// el login (los registros del servidor mostraban logins exitosos). Con
/// [mensajeInmediato] (error ya confirmado, no vale la pena esperar) el
/// aviso aparece de una.
class _CargaConSalida extends StatefulWidget {
  final VoidCallback? onReintentar;
  final bool mensajeInmediato;
  const _CargaConSalida({this.onReintentar, this.mensajeInmediato = false});

  @override
  State<_CargaConSalida> createState() => _CargaConSalidaState();
}

class _CargaConSalidaState extends State<_CargaConSalida> {
  late bool _tardando = widget.mensajeInmediato;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!_tardando) _iniciarTimer();
  }

  void _iniciarTimer() {
    // 10 segundos: un arranque normal resuelve en menos de 2-3, así que
    // casi nadie ve este aviso — pero quien caía en la trampa lo va a
    // ver siempre, con salida.
    _timer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _tardando = true);
    });
  }

  // Sin esto, "inmediato" no era inmediato de verdad: en AuthWrapper este
  // widget nace PRIMERO en su forma "todavía esperando" (mensajeInmediato:
  // false, la única opción posible antes de que llegue cualquier evento
  // del stream) y recién después, si el stream confirma un error, vuelve a
  // construirse con mensajeInmediato: true. Flutter reutiliza el MISMO
  // State entre esos dos builds (misma posición en el árbol, sin key que
  // los distinga) — initState() no se vuelve a correr, así que
  // `late bool _tardando = widget.mensajeInmediato` había quedado fijado
  // en `false` desde el primer build y nunca se enteraba del cambio. Un
  // error ya confirmado esperaba los 10 segundos completos igual que una
  // carga normal — el mismo síntoma ("se queda cargando y no puedo hacer
  // nada") que este widget se construyó para eliminar (hallazgo de
  // auditoría de código).
  @override
  void didUpdateWidget(covariant _CargaConSalida oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mensajeInmediato && !oldWidget.mensajeInmediato && !_tardando) {
      _timer?.cancel();
      setState(() => _tardando = true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: appTeal),
              if (_tardando) ...[
                const SizedBox(height: 28),
                Text(
                  'Esto está tardando más de lo normal.\nRevisá tu conexión.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.onReintentar != null)
                  ElevatedButton(
                    onPressed: widget.onReintentar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appTeal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Reintentar'),
                  ),
                TextButton(
                  onPressed: cerrarSesion,
                  child: Text(
                    'Cerrar sesión y volver a entrar',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
