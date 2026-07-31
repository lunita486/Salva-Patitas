import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'data/auth_helper.dart';
import 'screens/login_screen.dart';
import 'screens/seleccion_rol_screen.dart';
import 'screens/albergue_perfil_screen.dart';
import 'screens/albergue_home_screen.dart';
import 'screens/aliado_perfil_screen.dart';
import 'screens/aliado_home_screen.dart';
import 'screens/home_screen.dart';
import 'services/notificaciones_service.dart';

// Instancia única compartida por toda la app — Fase 2 (eventos propios como
// "solicitud_enviada") la va a importar desde acá en vez de crear la suya.
final FirebaseAnalytics analytics = FirebaseAnalytics.instance;
final FirebaseAnalyticsObserver analyticsObserver =
    FirebaseAnalyticsObserver(analytics: analytics);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // NotificacionesService.inicializar() ya se protege sola por dentro (cada
  // paso atrapa su propio error — ver ese archivo), pero runApp() de acá
  // abajo es lo único que de verdad importa: sin ESTE try/catch también,
  // cualquier cosa nueva que se agregue ahí en el futuro y se olvide de
  // atrapar su error deja a la persona en una pantalla en blanco para
  // siempre, sin haberse construido ni el login. Nada relacionado con
  // notificaciones debería poder impedir que la app arranque.
  try {
    await NotificacionesService.inicializar();
  } catch (e) {
    debugPrint('No se pudo inicializar notificaciones: $e');
  }
  runApp(const PatitasApp());
}

class PatitasApp extends StatelessWidget {
  const PatitasApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salva Patitas',
      debugShowCheckedModeBanner: false,
      // Registra automáticamente cada cambio de pantalla como evento
      // "screen_view" — la base gratis de Analytics (aperturas de la app,
      // navegación) sin necesidad de tocar ninguna pantalla todavía. Los
      // eventos propios del negocio (Fase 2: solicitud_enviada, etc.) se
      // agregan aparte, esto es solo lo automático.
      navigatorObservers: [analyticsObserver],
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
      home: const AuthWrapper(),
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
  // Guarda para QUÉ cuenta ya se escribió 'ultimaVezActiva' en esta sesión
  // — String? con el uid, no un bool. Sin este guard, escribirlo en cada
  // rebuild de este StreamBuilder (que reacciona en vivo al propio doc de
  // usuarios) dispararía un bucle infinito: escribir → llega un snapshot
  // nuevo → se vuelve a escribir. Pero un bool simple ("¿ya escribí ALGUNA
  // vez en este proceso?") tiene el problema que motivó este arreglo: la
  // app soporta cambiar de cuenta sin cerrarla (ver "Cerrar sesión y
  // volver a entrar" en _CargaConSalida), y _AuthWrapperState vive para
  // TODO el proceso de la app, no por sesión — con un bool, la cuenta B
  // nunca quedaba registrada si la cuenta A ya lo había hecho antes en el
  // mismo proceso (justo lo que estuvimos consultando hoy: quién entró).
  // Guardar el uid en vez de un bool, y compararlo contra la cuenta
  // ACTUAL, deja escribir de nuevo apenas cambia de quién se trata.
  String? _ultimaVezActivaMarcadaParaUid;

  Future<void> _reintentar() async {
    // Además de recrear la suscripción, se apaga y prende la red de
    // Firestore: después de un cambio de cuenta, el canal de escucha puede
    // quedar mudo (reintentando por dentro con un token viejo), y volver a
    // suscribirse sobre ese mismo canal muerto no cambia nada. El ciclo
    // fuerza canales nuevos con el token de la cuenta actual.
    try {
      await FirebaseFirestore.instance.disableNetwork()
          .timeout(const Duration(seconds: 5));
      await FirebaseFirestore.instance.enableNetwork()
          .timeout(const Duration(seconds: 5));
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
          // Lista para la próxima cuenta que inicie sesión en este mismo
          // proceso — incluso si es la MISMA cuenta de antes, cerrar
          // sesión y volver a entrar cuenta como una entrada nueva de
          // verdad, no algo ya registrado.
          _ultimaVezActivaMarcadaParaUid = null;
          return const LoginScreen();
        }
        return StreamBuilder<DocumentSnapshot>(
          key: ValueKey('perfil-$_intento'),
          stream: FirebaseFirestore.instance
              .collection('usuarios').doc(snap.data!.uid).snapshots(),
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
            final data  = userSnap.data!.data() as Map<String, dynamic>;
            // `foto` solo se escribía una vez, al crear el perfil (ver
            // UsuariosRepository.crearPerfil) — si la cuenta se creó cuando
            // el photoURL de Google todavía no estaba disponible (o cambió
            // después), quedaba null para siempre. Otras pantallas del chat
            // necesitan poder mostrar la foto de la CONTRAPARTE leyendo este
            // campo (no pueden usar FirebaseAuth, que solo expone al usuario
            // propio), así que acá se mantiene sincronizado de forma
            // oportunista cada vez que la cuenta pasa por este punto central.
            final fotoAuth = snap.data!.photoURL;
            if (fotoAuth != null && fotoAuth != data['foto']) {
              FirebaseFirestore.instance.collection('usuarios').doc(snap.data!.uid)
                  .update({'foto': fotoAuth}).catchError((_) {});
            }
            // Sello de "última vez activa" — antes no había NINGÚN dato que
            // dijera qué días entró alguien a la app, solo el último login
            // de Firebase Auth (que ni se actualiza si la sesión ya estaba
            // guardada). Una escritura por sesión alcanza para reconstruir
            // un historial real de actividad día por día (pedido real de
            // Eliza, mientras revisaba quién venía probando la app).
            if (_ultimaVezActivaMarcadaParaUid != snap.data!.uid) {
              _ultimaVezActivaMarcadaParaUid = snap.data!.uid;
              FirebaseFirestore.instance.collection('usuarios').doc(snap.data!.uid)
                  .update({'ultimaVezActiva': FieldValue.serverTimestamp()}).catchError((_) {});
            }
            final roles = List<String>.from(data['roles'] as List? ?? []);
            // Documento que existe pero sin ningún rol = perfil a medio
            // crear (caso real: un login que se colgó a mitad del
            // onboarding dejó un doc con solo fcmToken y foto — los
            // servicios de fondo escriben esos campos apenas hay sesión,
            // antes de que la persona elija rol). Sin este chequeo, esa
            // cuenta salteaba la selección de rol para siempre y caía a
            // HomeScreen sin nombre ni rol. Se la manda al onboarding, que
            // completa el perfil con merge (no pisa lo que ya haya).
            if (roles.isEmpty) return SeleccionRolScreen(user: snap.data!);
            final esAlbergue = roles.contains('albergue');
            final esAliado   = roles.contains('aliado');

            if (esAlbergue) {
              final perfilCompleto = (data['albergueNombre'] as String?)?.isNotEmpty == true;
              if (!perfilCompleto) return const AlberguePerfilScreen();
              return const AlbergueHomeScreen();
            }
            if (esAliado) {
              final perfilCompleto = (data['aliadoNombre'] as String?)?.isNotEmpty == true;
              if (!perfilCompleto) return const AliadoPerfilScreen();
              return const AliadoHomeScreen();
            }
            return const HomeScreen();
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
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CircularProgressIndicator(color: appTeal),
            if (_tardando) ...[
              const SizedBox(height: 28),
              Text(
                'Esto está tardando más de lo normal.\nRevisá tu conexión.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 16),
              if (widget.onReintentar != null)
                ElevatedButton(
                  onPressed: widget.onReintentar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appTeal, foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  ),
                  child: const Text('Reintentar'),
                ),
              TextButton(
                onPressed: cerrarSesion,
                child: Text('Cerrar sesión y volver a entrar',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
