// Barra de abajo del adoptante: Adoptar · Favoritos · Solicitudes · Chats ·
// Negocios · Perfil. Es UNA sola, la misma en el inicio y en cada sección que
// se abre desde él, para que la persona siempre vea dónde está (pedido de
// Eliza, igual que la del albergue).
//
// Cómo se navega (igual que AlbergueTabBar): el inicio abre cada sección con
// un push. Dentro de una sección, tocar otra pestaña NO apila otra pantalla:
// cierra la actual devolviendo la pestaña elegida
// ([AdoptanteTabBar.volverAlInicio]) y el inicio abre esa. Así la pila
// siempre es inicio + una sección, y "volver" lleva siempre al inicio.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/chats_repository.dart';
import '../routing/pagina_pestana.dart';
import 'sp_widgets.dart';

enum AdoptanteTab { adoptar, favoritos, solicitudes, chats, negocios, perfil }

class AdoptanteTabBar extends StatefulWidget {
  const AdoptanteTabBar({super.key, required this.actual, required this.onTap});

  /// Pestaña resaltada.
  final AdoptanteTab actual;
  final ValueChanged<AdoptanteTab> onTap;

  /// Para las secciones abiertas desde el inicio: cerrar esta pantalla y
  /// avisarle al inicio qué pestaña abrir. Tocar la pestaña actual no hace
  /// nada.
  static ValueChanged<AdoptanteTab> volverAlInicio(
    BuildContext context,
    AdoptanteTab actual,
  ) => (t) {
    if (t == actual) return;
    // Cambio de pestaña: sin animación de salida ni de entrada (ver
    // PaginaPestana).
    SaltoDePestana.marcar();
    context.pop(t);
  };

  @override
  State<AdoptanteTabBar> createState() => _AdoptanteTabBarState();
}

class _AdoptanteTabBarState extends State<AdoptanteTabBar> {
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Cada barra pide su propio stream (mismo motivo que en AlbergueTabBar:
  // quien se suscribe tarde a un stream broadcast no recibe la última foto).
  late final _chats = ChatsRepository().mios(uid: _uid, esRescatista: false);

  @override
  Widget build(BuildContext context) {
    SpTabItem item(
      AdoptanteTab t,
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
        item(AdoptanteTab.adoptar, Icons.pets_rounded, 'Adoptar'),
        item(
          AdoptanteTab.favoritos,
          Icons.favorite_border_rounded,
          'Favoritos',
        ),
        item(
          AdoptanteTab.solicitudes,
          Icons.assignment_outlined,
          'Solicitudes',
        ),
        StreamBuilder(
          stream: _chats,
          builder: (_, snap) {
            // ChatsRepository.perteneceALaLista es la misma función que
            // decide qué chats muestra AdoptanteChatsScreen, así la lista y
            // el número no pueden divergir.
            final unread = (snap.data?.docs ?? []).where((doc) {
              final d = doc.data();
              return ChatsRepository.perteneceALaLista(
                    d,
                    uid: _uid,
                    esRescatista: false,
                  ) &&
                  ChatsRepository.noLeidosPara(
                        d,
                        uid: _uid,
                        esRescatista: false,
                      ) >
                      0;
            }).length;
            return item(
              AdoptanteTab.chats,
              Icons.chat_bubble_outline_rounded,
              'Chats',
              badge: unread,
            );
          },
        ),
        item(AdoptanteTab.negocios, Icons.storefront_outlined, 'Negocios'),
        item(AdoptanteTab.perfil, Icons.person_outline_rounded, 'Perfil'),
      ],
    );
  }
}
