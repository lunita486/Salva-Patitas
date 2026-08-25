import 'package:go_router/go_router.dart';

import '../main.dart';
import '../screens/adoptante_chats_screen.dart';
import '../screens/albergue_perfil_screen.dart';
import '../screens/albergue_publico_screen.dart';
import '../screens/aliado_perfil_screen.dart';
import '../screens/aliado_publico_screen.dart';
import '../screens/aliados_screen.dart';
import '../screens/animal_detalle_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/editar_rescate_screen.dart';
import '../screens/favoritos_screen.dart';
import '../screens/hogares_de_paso_screen.dart';
import '../screens/mis_rescates_screen.dart';
import '../screens/mis_solicitudes_screen.dart';
import '../screens/notificaciones_screen.dart';
import '../screens/perfil_adoptante_screen.dart';
import '../screens/perfil_rescatista_screen.dart';
import '../screens/solicitud_adopcion_screen.dart';
import '../screens/solicitudes_rescatista_screen.dart';
import '../screens/subir_lote_screen.dart';
import '../screens/subir_rescate_screen.dart';
import '../screens/subir_servicio_screen.dart';
import '../screens/tipo_animal_screen.dart';
import '../screens/visor_foto_completa.dart';

// Tabla de rutas — antes cada pantalla llamaba a
// `Navigator.push(context, MaterialPageRoute(builder: (_) => Screen(...)))`
// a mano, en 62 lugares repartidos en 17 archivos: el grafo de qué pantalla
// lleva a cuál solo se podía reconstruir leyendo las 17 (auditoría de
// arquitectura, "Navegación", riesgo moderado). Ahora está en un solo
// lugar, con nombres en vez de tipear la clase de la pantalla en cada
// callsite.
//
// A propósito NO se migraron acá las pantallas raíz que decide
// `AuthWrapper` (`LoginScreen`, `SeleccionRolScreen`, `HomeScreen`,
// `AlbergueHomeScreen`, `AliadoHomeScreen`) — esas no se "navegan a" desde
// otra pantalla, son el resultado de una decisión de estado de sesión/rol
// (ver `lib/domain/resolucion_perfil.dart`), y siguen viviendo en
// `main.dart` exactamente igual que antes. `AuthWrapper` es el builder de
// la ruta raíz (`/`) — todo lo de acá cuelga como rutas hijas.
//
// Tampoco están `SolicitudesPreview` ni `AdoptanteFeedScreen`: son widgets
// EMBEBIDOS dentro de otra pantalla (una pestaña de HomeScreen, una
// sección de AlbergueHomeScreen), nunca se empujan con Navigator — no son
// "páginas" en el sentido de esta tabla.
//
// Los parámetros complejos (Map, List, User) viajan por `extra` como un
// record tipado — go_router no puede meterlos en la URL sin serializarlos,
// y estas pantallas ya reciben datos PRE-CARGADOS por quien las abre (no
// un id para volver a pedirlos), así que serializar habría sido cambiar
// comportamiento, no solo la forma de navegar. Las pantallas sin
// parámetros o con solo banderas booleanas también usan `extra` con
// record, por consistencia — un solo patrón para las 21, no dos.
class AppRoutes {
  AppRoutes._();

  static const adoptanteChats = '/adoptante-chats';
  static const alberguePerfil = '/albergue-perfil';
  static const alberguePublico = '/albergue-publico';
  static const aliadoPerfil = '/aliado-perfil';
  static const aliadoPublico = '/aliado-publico';
  static const aliados = '/aliados';
  static const animalDetalle = '/animal-detalle';
  static const chat = '/chat';
  static const editarRescate = '/editar-rescate';
  static const favoritos = '/favoritos';
  static const hogaresDePaso = '/hogares-de-paso';
  static const misRescates = '/mis-rescates';
  static const misSolicitudes = '/mis-solicitudes';
  static const notificaciones = '/notificaciones';
  static const perfilAdoptante = '/perfil-adoptante';
  static const perfilRescatista = '/perfil-rescatista';
  static const solicitudAdopcion = '/solicitud-adopcion';
  static const solicitudesRescatista = '/solicitudes-rescatista';
  static const subirLote = '/subir-lote';
  static const subirRescate = '/subir-rescate';
  static const subirServicio = '/subir-servicio';
  static const tipoAnimal = '/tipo-animal';
  static const visorFoto = '/visor-foto';
}

typedef AdoptanteChatsArgs =
    ({bool esRescatista, bool soloConsultas, bool esAlbergue});
typedef AliadoPublicoArgs =
    ({String aliadoId, bool esRescatista, bool esAlbergue});
typedef AliadosArgs = ({bool esRescatista, bool esAlbergue});
typedef ChatArgs =
    ({Map<String, dynamic> animal, bool esRescatista, String? chatId});
typedef EditarRescateArgs = ({String docId, Map<String, dynamic> data});
typedef MisRescatesArgs = ({String? filtroInicial, bool esAlbergue});
typedef SubirServicioArgs = ({String? docId, Map<String, dynamic>? data});
typedef VisorFotoArgs = ({List<String> fotos, int indiceInicial});

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  observers: [analyticsObserver],
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const AuthWrapper(),
    ),
    GoRoute(
      path: AppRoutes.adoptanteChats,
      builder: (context, state) {
        final a = state.extra as AdoptanteChatsArgs? ?? (
          esRescatista: false,
          soloConsultas: false,
          esAlbergue: false,
        );
        return AdoptanteChatsScreen(
          esRescatista: a.esRescatista,
          soloConsultas: a.soloConsultas,
          esAlbergue: a.esAlbergue,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.alberguePerfil,
      builder: (context, state) => const AlberguePerfilScreen(),
    ),
    GoRoute(
      path: AppRoutes.alberguePublico,
      builder: (context, state) =>
          AlberguePublicoScreen(rescatistaId: state.extra as String),
    ),
    GoRoute(
      path: AppRoutes.aliadoPerfil,
      builder: (context, state) => const AliadoPerfilScreen(),
    ),
    GoRoute(
      path: AppRoutes.aliadoPublico,
      builder: (context, state) {
        final a = state.extra as AliadoPublicoArgs;
        return AliadoPublicoScreen(
          aliadoId: a.aliadoId,
          esRescatista: a.esRescatista,
          esAlbergue: a.esAlbergue,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.aliados,
      builder: (context, state) {
        final a = state.extra as AliadosArgs? ?? (
          esRescatista: false,
          esAlbergue: false,
        );
        return AliadosScreen(esRescatista: a.esRescatista, esAlbergue: a.esAlbergue);
      },
    ),
    GoRoute(
      path: AppRoutes.animalDetalle,
      builder: (context, state) => AnimalDetalleScreen(
        animal: state.extra as Map<String, dynamic>,
      ),
    ),
    GoRoute(
      path: AppRoutes.chat,
      builder: (context, state) {
        final a = state.extra as ChatArgs;
        return ChatScreen(
          animal: a.animal,
          esRescatista: a.esRescatista,
          chatId: a.chatId,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.editarRescate,
      builder: (context, state) {
        final a = state.extra as EditarRescateArgs;
        return EditarRescateScreen(docId: a.docId, data: a.data);
      },
    ),
    GoRoute(
      path: AppRoutes.favoritos,
      builder: (context, state) => const FavoritosScreen(),
    ),
    GoRoute(
      path: AppRoutes.hogaresDePaso,
      builder: (context, state) => const HogaresDePasoScreen(),
    ),
    GoRoute(
      path: AppRoutes.misRescates,
      builder: (context, state) {
        final a = state.extra as MisRescatesArgs? ?? (
          filtroInicial: null,
          esAlbergue: false,
        );
        return TodosLosRescatesScreen(
          filtroInicial: a.filtroInicial,
          esAlbergue: a.esAlbergue,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.misSolicitudes,
      builder: (context, state) => const MisSolicitudesScreen(),
    ),
    GoRoute(
      path: AppRoutes.notificaciones,
      builder: (context, state) => const NotificacionesScreen(),
    ),
    GoRoute(
      path: AppRoutes.perfilAdoptante,
      builder: (context, state) =>
          PerfilAdoptanteScreen(ciudadConocida: state.extra as String?),
    ),
    GoRoute(
      path: AppRoutes.perfilRescatista,
      builder: (context, state) => const PerfilRescatistaScreen(),
    ),
    GoRoute(
      path: AppRoutes.solicitudAdopcion,
      builder: (context, state) => SolicitudAdopcionScreen(
        animal: state.extra as Map<String, dynamic>,
      ),
    ),
    GoRoute(
      path: AppRoutes.solicitudesRescatista,
      builder: (context, state) =>
          SolicitudesRescatistaScreen(esAlbergue: state.extra as bool? ?? false),
    ),
    GoRoute(
      path: AppRoutes.subirLote,
      builder: (context, state) => const SubirLoteScreen(),
    ),
    GoRoute(
      path: AppRoutes.subirRescate,
      builder: (context, state) =>
          SubirRescateScreen(esAlbergue: state.extra as bool? ?? false),
    ),
    GoRoute(
      path: AppRoutes.subirServicio,
      builder: (context, state) {
        final a = state.extra as SubirServicioArgs? ?? (docId: null, data: null);
        return SubirServicioScreen(docId: a.docId, data: a.data);
      },
    ),
    GoRoute(
      path: AppRoutes.tipoAnimal,
      builder: (context, state) => const TipoAnimalScreen(),
    ),
    GoRoute(
      path: AppRoutes.visorFoto,
      builder: (context, state) {
        final a = state.extra as VisorFotoArgs;
        return VisorFotoCompleta(fotos: a.fotos, indiceInicial: a.indiceInicial);
      },
    ),
  ],
);
