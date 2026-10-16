// Barra de abajo del rescatista: Mis rescates · Subir · Solicitudes · Chats ·
// Negocios · Perfil. La misma en el inicio y en cada sección que se abre
// desde él (pedido de Eliza, igual que la del adoptante).
//
// Mismo mecanismo que AdoptanteTabBar: dentro de una sección, tocar otra
// pestaña cierra la actual devolviendo la elegida y el inicio abre esa. La
// pila siempre es inicio + una sección.
//
// "Subir" es la excepción: el formulario NO lleva esta barra. Un toque sin
// querer en otra pestaña a mitad del formulario hacía perder todo lo escrito.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/chats_repository.dart';
import '../domain/reglas_negocio.dart';
import '../routing/pagina_pestana.dart';
import 'sp_widgets.dart';

enum RescatistaTab { misRescates, subir, solicitudes, chats, negocios, perfil }

class RescatistaTabBar extends StatefulWidget {
  const RescatistaTabBar({
    super.key,
    required this.actual,
    required this.onTap,
  });

  /// Pestaña resaltada.
  final RescatistaTab actual;
  final ValueChanged<RescatistaTab> onTap;

  /// Para las secciones abiertas desde el inicio: cerrar esta pantalla y
  /// avisarle al inicio qué pestaña abrir. Tocar la pestaña actual no hace
  /// nada.
  static ValueChanged<RescatistaTab> volverAlInicio(
    BuildContext context,
    RescatistaTab actual,
  ) => (t) {
    if (t == actual) return;
    // Cambio de pestaña: sin animación de salida ni de entrada (ver
    // PaginaPestana).
    SaltoDePestana.marcar();
    context.pop(t);
  };

  @override
  State<RescatistaTabBar> createState() => _RescatistaTabBarState();
}

class _RescatistaTabBarState extends State<RescatistaTabBar> {
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Cada barra pide sus propios streams (mismo motivo que en AlbergueTabBar:
  // quien se suscribe tarde a un stream broadcast no recibe la última foto).
  late final _chats = ChatsRepository();
  late final _recibidos = _chats.mios(uid: _uid, esRescatista: true);
  // Consultas que ESTA cuenta le mandó a un negocio aliado (ver
  // contarMensajesSinLeer en domain/reglas_negocio.dart).
  late final _consultas = _chats.consultasEnviadas(uid: _uid);

  @override
  Widget build(BuildContext context) {
    SpTabItem item(
      RescatistaTab t,
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
        item(RescatistaTab.misRescates, Icons.pets_rounded, 'Mis rescates'),
        item(RescatistaTab.subir, Icons.add_circle_outline, 'Subir'),
        item(
          RescatistaTab.solicitudes,
          Icons.notifications_outlined,
          'Solicitudes',
        ),
        // Mismo cálculo que el inicio del rescatista: así el número de la
        // barra y el de "Sin leer" no pueden divergir.
        StreamBuilder(
          stream: _recibidos,
          builder: (_, snap) => StreamBuilder(
            stream: _consultas,
            builder: (_, consultaSnap) => item(
              RescatistaTab.chats,
              Icons.chat_bubble_outline_rounded,
              'Chats',
              badge: contarMensajesSinLeer(
                recibidos: snap.data?.docs,
                consultasEnviadas: consultaSnap.data?.docs,
                esAlbergue: false,
                uid: _uid,
              ),
            ),
          ),
        ),
        item(RescatistaTab.negocios, Icons.storefront_outlined, 'Negocios'),
        item(RescatistaTab.perfil, Icons.person_outline_rounded, 'Perfil'),
      ],
    );
  }
}
