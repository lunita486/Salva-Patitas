import 'package:cloud_firestore/cloud_firestore.dart';
// Barra de abajo del albergue: Panel · Jauría · Solicitudes · Chats ·
// Negocios · Perfil. Es UNA sola, la misma en el Panel y en cada sección que
// se abre desde él, para que la persona siempre vea dónde está (pedido de
// Eliza, igual que el prototipo).
//
// Cómo se navega: el Panel abre cada sección con un push (y al volver
// refresca sus números). Dentro de una sección, tocar otra pestaña NO apila
// otra pantalla: cierra la actual devolviendo la pestaña elegida
// ([AlbergueTabBar.volverAlPanel]) y el Panel abre esa. Así la pila siempre
// es Panel + una sección, y "volver" lleva siempre al Panel.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/contexto_albergue.dart';
import '../data/chats_repository.dart';
import '../data/creator_role.dart';
import '../data/solicitudes_repository.dart';
import '../domain/reglas_negocio.dart';
import '../routing/pagina_pestana.dart';
import 'sp_widgets.dart';

enum AlbergueTab { panel, jauria, solicitudes, chats, negocios, perfil }

class AlbergueTabBar extends StatefulWidget {
  const AlbergueTabBar({super.key, required this.actual, required this.onTap});

  /// Pestaña resaltada.
  final AlbergueTab actual;
  final ValueChanged<AlbergueTab> onTap;

  /// Para las secciones abiertas desde el Panel: cerrar esta pantalla y
  /// avisarle al Panel qué pestaña abrir. Tocar la pestaña actual no hace
  /// nada.
  static ValueChanged<AlbergueTab> volverAlPanel(
    BuildContext context,
    AlbergueTab actual,
  ) => (t) {
    if (t == actual) return;
    // Cambio de pestaña: sin animación de salida ni de entrada (ver
    // PaginaPestana).
    SaltoDePestana.marcar();
    context.pop(t);
  };

  @override
  State<AlbergueTabBar> createState() => _AlbergueTabBarState();
}

class _AlbergueTabBarState extends State<AlbergueTabBar> {
  // El albergue del panel: el propio, o el de la responsable en modo equipo.
  final _ctx = contextoAlbergue();
  late final _uid = _ctx.albergueId;

  // Cada barra pide sus propios streams (y no recibe los del Panel): un
  // stream de Firestore es broadcast, y quien se suscribe tarde no recibe la
  // última foto. Pedirlos acá garantiza el primer valor en cada pantalla.
  late final _pendientes = SolicitudesRepository().paraOwner(
    uid: _uid,
    role: CreatorRole.albergue,
    estado: 'pendiente',
  );
  late final _chats = ChatsRepository();
  // En modo equipo, solo los chats que las reglas le dejan leer al equipo.
  late final _recibidos = _ctx.esEquipo
      ? _chats.delEquipo(_uid).snapshots()
      : _chats.mios(uid: _uid, esRescatista: true);
  // Consultas que ESTA cuenta le mandó a un negocio aliado — sin esto el
  // badge nunca contaba una respuesta a una consulta propia (ver
  // contarMensajesSinLeer en domain/reglas_negocio.dart).
  // En modo equipo no hay: las consultas a negocios aliados no se comparten.
  late final Stream<QuerySnapshot<Map<String, dynamic>>?> _consultas = _ctx.esEquipo
      ? Stream.value(null)
      : _chats.consultasEnviadas(uid: _uid);

  @override
  Widget build(BuildContext context) {
    SpTabItem item(
      AlbergueTab t,
      IconData icon,
      String label, {
      int badge = 0,
    }) => SpTabItem(
      icon: icon,
      label: label,
      active: widget.actual == t,
      badge: badge,
      onTap: () => widget.onTap(t),
    );

    return SpTabBar(
      children: [
        item(AlbergueTab.panel, Icons.dashboard_rounded, 'Panel'),
        item(AlbergueTab.jauria, Icons.pets_rounded, 'Jauría'),
        StreamBuilder(
          stream: _pendientes,
          builder: (_, snap) => item(
            AlbergueTab.solicitudes,
            Icons.assignment_outlined,
            'Solicitudes',
            badge: snap.data?.docs.length ?? 0,
          ),
        ),
        StreamBuilder(
          stream: _recibidos,
          builder: (_, snap) => StreamBuilder(
            stream: _consultas,
            builder: (_, consultaSnap) => item(
              AlbergueTab.chats,
              Icons.chat_bubble_outline_rounded,
              'Chats',
              badge: contarMensajesSinLeer(
                recibidos: snap.data?.docs,
                consultasEnviadas: consultaSnap.data?.docs,
                esAlbergue: true,
                uid: _uid,
              ),
            ),
          ),
        ),
        // Las consultas a negocios aliados son de la responsable, no del equipo.
        if (!_ctx.esEquipo) item(AlbergueTab.negocios, Icons.storefront_outlined, 'Negocios'),
        item(AlbergueTab.perfil, Icons.person_outline_rounded, 'Perfil'),
      ],
    );
  }
}
