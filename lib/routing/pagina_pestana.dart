// Página para las secciones que tienen la barra de abajo (Favoritos, Chats,
// Negocios...). Se ve y anima igual que una página normal, salvo cuando se
// cambia de pestaña desde esa barra: ahí la sección que se va y la que entra
// cambian al instante, sin animación.
//
// Por qué: cambiar de pestaña cierra la sección actual y el inicio abre la
// nueva (ver AdoptanteTabBar). Con animación, una pantalla salía deslizándose
// mientras la otra entraba, dejando ver el inicio en medio — se veía raro
// (hallazgo de Eliza probando en el emulador). Una barra de pestañas real
// cambia de una.
import 'package:flutter/material.dart';

/// Marca de "se está cambiando de pestaña". Es una marca de tiempo y no un
/// booleano porque la sección que entra se crea un frame después del toque:
/// vale durante un instante y después se apaga sola, así un "atrás" normal
/// más tarde anima como siempre.
class SaltoDePestana {
  static DateTime? _marca;

  static void marcar() => _marca = DateTime.now();

  static bool get activo =>
      _marca != null &&
      DateTime.now().difference(_marca!) < const Duration(milliseconds: 600);
}

class PaginaPestana<T> extends Page<T> {
  const PaginaPestana({required this.child, super.key, super.name});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _RutaPestana<T>(this);
}

class _RutaPestana<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _RutaPestana(PaginaPestana<T> page)
    : _entraSaltando = SaltoDePestana.activo,
      super(settings: page);

  /// Se decide al crearse: si se abrió por un cambio de pestaña, entra sin
  /// animación.
  final bool _entraSaltando;

  @override
  Widget buildContent(BuildContext context) =>
      (settings as PaginaPestana<T>).child;

  @override
  bool get maintainState => true;

  @override
  bool get fullscreenDialog => false;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final saltando = animation.status == AnimationStatus.reverse
        ? SaltoDePestana.activo
        : _entraSaltando;
    if (saltando) return child;
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
