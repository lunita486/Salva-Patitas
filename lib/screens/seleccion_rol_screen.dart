import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/sp_widgets.dart';
import '../data/usuarios_repository.dart';
import '../services/ubicacion_service.dart';

class SeleccionRolScreen extends StatefulWidget {
  final User user;
  const SeleccionRolScreen({super.key, required this.user});
  @override
  State<SeleccionRolScreen> createState() => _SeleccionRolScreenState();
}

class _SeleccionRolScreenState extends State<SeleccionRolScreen> {
  final Set<String> _roles = {'adoptante'};
  bool _guardando = false;
  bool _perfilExiste = false;

  @override
  void initState() {
    super.initState();
    _cargarRolesExistentes();
  }

  /// Esta pantalla puede aparecer para una cuenta que YA tiene perfil (la
  /// caché de Firestore puede decir "no existe" por un instante en un
  /// arranque en frío). Si el perfil existe, precargamos sus roles y en
  /// _continuar() solo actualizamos roles — nunca se pisa el perfil entero.
  Future<void> _cargarRolesExistentes() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(widget.user.uid)
          .get();
      final roles =
          (doc.data()?['roles'] as List?)
              ?.cast<String>()
              .where(UsuariosRepository.rolesValidos.contains)
              .toSet() ??
          {};
      if (!mounted || !doc.exists) return;
      setState(() {
        // NO alcanza con "el doc existe": asegurarPerfilBase() (ver
        // auth_helper.dart) ahora crea usuarios/{uid} desde el primer
        // login, SIN roles, antes de que la persona llegue a esta
        // pantalla. Si _perfilExiste se basara solo en doc.exists, una
        // cuenta genuinamente nueva tomaría el camino de actualizarRoles()
        // en vez de crearPerfil() — perdiendo ciudad/creadoEn para
        // siempre y sin disparar el evento de registro_completado. El
        // dato real de "ya completó el onboarding alguna vez" es que
        // tenga roles guardados, no que el doc exista.
        _perfilExiste = roles.isNotEmpty;
        if (roles.isNotEmpty) {
          _roles
            ..clear()
            ..addAll(roles);
        }
      });
    } catch (_) {
      // Sin conexión no podemos saberlo — _continuar() usa crearPerfil()
      // con merge, así que aun en el peor caso no se pisa nada.
    }
  }

  /// La ciudad es un dato opcional del alta de perfil: si no se puede
  /// detectar se guarda vacía y listo, nunca traba el registro (ver
  /// _continuar, que además le pone su propio límite de 5s).
  ///
  /// Antes esta copia pedía la posición SIN chequear primero si el servicio
  /// de ubicación estaba prendido — justo lo que dispara el diálogo nativo
  /// de Android "Precisión de la ubicación", y acá encima en la primerísima
  /// pantalla que ve alguien que se registra. Tampoco le ponía `timeLimit`
  /// al pedido, así que el GPS seguía corriendo de fondo aunque el timeout
  /// del llamador ya se hubiera rendido. Las dos cosas las resuelve
  /// UbicacionService para todas las pantallas a la vez.
  Future<String> _detectarCiudad() async =>
      (await UbicacionService.actual(conCiudad: true)).ciudad;

  Future<void> _continuar() async {
    setState(() => _guardando = true);
    try {
      if (_perfilExiste) {
        // Perfil ya creado: solo se tocan los roles (nada de ciudad, nombre,
        // creadoEn... — eso ya lo tiene y no es asunto de esta pantalla).
        await UsuariosRepository().actualizarRoles(
          widget.user.uid,
          _roles.toList(),
        );
      } else {
        final ciudad = await _detectarCiudad().timeout(
          const Duration(seconds: 5),
          onTimeout: () => '',
        );
        await UsuariosRepository().crearPerfil(
          uid: widget.user.uid,
          nombre: widget.user.displayName ?? 'Usuario',
          email: widget.user.email,
          foto: widget.user.photoURL,
          roles: _roles.toList(),
          ciudad: ciudad,
        );
        // Solo se dispara acá (perfil NUEVO), no cuando alguien vuelve a
        // esta pantalla a sumar/quitar roles después — eso pisaría el dato
        // de "cuántos se registran de verdad" con cada cambio de rol
        // posterior. Best-effort: si falla, no debe tumbar el registro real.
        FirebaseAnalytics.instance
            .logEvent(
              name: 'registro_completado',
              parameters: {'roles': _roles.join(',')},
            )
            .catchError((_) {});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.sp.msgError,
          content: const Text(
            'No se pudo crear tu perfil. Revisá tu conexión e intentá de nuevo.',
          ),
        ),
      );
    }
  }

  static const _rolesExclusivos = {'albergue', 'aliado'};

  void _toggleRol(String rol) {
    setState(() {
      if (_roles.contains(rol)) {
        if (_roles.length > 1) _roles.remove(rol);
      } else if (_rolesExclusivos.contains(rol)) {
        // Albergue y Aliado son exclusivos — limpian todo lo demás
        _roles
          ..clear()
          ..add(rol);
      } else {
        // Adoptante/Rescatista no pueden combinarse con roles exclusivos
        _roles.removeWhere((r) => _rolesExclusivos.contains(r));
        _roles.add(rol);
      }
    });
  }

  /// Tarjeta de un rol: blanca 3D; elegida, con borde y canto verdes y el
  /// check. La baldosa pastel de la izquierda lleva el animalito o ícono del
  /// rol.
  Widget _rolCard({
    required String rol,
    required SpTone tono,
    required Widget arte,
    required String nombre,
    required String descripcion,
    String? badgeLabel,
    SpTone? badgeTono,
  }) {
    final c = context.sp;
    final sel = _roles.contains(rol);
    final badge = badgeTono == null ? null : SpToneColors.of(c, badgeTono);
    return GestureDetector(
      onTap: () => _toggleRol(rol),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(SpSpace.s3),
        decoration: sel
            ? BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(SpRadius.lg),
                border: Border.all(color: c.primary, width: 2.5),
                boxShadow: [
                  BoxShadow(color: c.primaryEdge, offset: const Offset(0, 4)),
                  BoxShadow(
                    color: c.primary.withValues(alpha: .3),
                    offset: const Offset(0, 12),
                    blurRadius: 22,
                    spreadRadius: -10,
                  ),
                ],
              )
            : SpDeco.card(c, radius: SpRadius.lg),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: SpDeco.tone(c, tono, radius: SpRadius.md),
              child: arte,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        nombre,
                        style: SpText.headline.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (badgeLabel != null && badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: badge.fill,
                            borderRadius: BorderRadius.circular(SpRadius.full),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: badge.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    descripcion,
                    style: SpText.label.copyWith(
                      color: c.inkMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Elegido: check verde; sin elegir: círculo vacío (se puede
            // marcar más de uno, como casillas).
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: sel ? c.primary : c.surfaceSunken,
                shape: BoxShape.circle,
                border: sel ? null : Border.all(color: c.edge, width: 2),
              ),
              child: sel
                  ? Icon(Icons.check_rounded, size: 18, color: c.onPrimary)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final nombre = widget.user.displayName?.split(' ').first ?? 'Usuario';
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const SpPawBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Hola, $nombre',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SpText.screen.copyWith(color: c.ink),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const SpPaw(size: 22, angle: -12),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '¿Cómo vas a entrar? Puedes elegir más de uno.',
                    style: SpText.body.copyWith(color: c.inkMuted),
                  ),
                  const SizedBox(height: SpSpace.s6),
                  // Las 4 tarjetas + el Spacer de antes eran un Column fijo sin
                  // scroll: en una pantalla lo bastante baja (teléfono chico,
                  // o con letra grande de accesibilidad), el conjunto no
                  // entraba y el botón "Continuar" — el último elemento, empujado
                  // por el Spacer — quedaba directamente afuera de la pantalla,
                  // invisible, sin ningún aviso (el bug real que reportó una
                  // tester: "no le muestra el botón continuar"). Envolviendo
                  // las tarjetas en Expanded+scroll, el botón queda SIEMPRE
                  // pegado justo debajo, visible sin importar el tamaño de
                  // pantalla — si las tarjetas no entran, se puede deslizar
                  // para verlas todas antes de tocar Continuar.
                  Expanded(
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        children: [
                          _rolCard(
                            rol: 'adoptante',
                            tono: SpTone.peach,
                            arte: const SpAnimal(SpAnimalKind.perro, size: 46),
                            nombre: 'Adoptante',
                            descripcion: 'Quiero adoptar un animal',
                          ),
                          const SizedBox(height: SpSpace.s3),
                          _rolCard(
                            rol: 'rescatista',
                            tono: SpTone.mint,
                            arte: const SpAnimal(SpAnimalKind.huella, size: 42),
                            nombre: 'Rescatista',
                            descripcion: 'Rescato animales por mi cuenta',
                          ),
                          const SizedBox(height: SpSpace.s3),
                          _rolCard(
                            rol: 'albergue',
                            tono: SpTone.butter,
                            arte: const SpAnimal(SpAnimalKind.casa, size: 44),
                            nombre: 'Albergue',
                            descripcion: 'Represento un albergue oficial',
                            badgeLabel: 'Verificación oficial',
                            badgeTono: SpTone.mint,
                          ),
                          const SizedBox(height: SpSpace.s3),
                          _rolCard(
                            rol: 'aliado',
                            tono: SpTone.lilac,
                            arte: Icon(
                              Icons.storefront_rounded,
                              size: 28,
                              color: c.lilacInk,
                            ),
                            nombre: 'Aliado',
                            descripcion: 'Soy veterinario, tienda o servicio',
                            badgeLabel: 'Negocio aliado',
                            badgeTono: SpTone.lilac,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _botonContinuar(c),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Botón verde 3D. Mientras guarda dice "Creando tu perfil..." con un
  /// spinner y no se puede tocar de nuevo.
  Widget _botonContinuar(SpColors c) {
    final caja = Container(
      width: double.infinity,
      height: 54,
      decoration: SpDeco.primary(c, radius: SpRadius.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_guardando) ...[
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: c.onPrimary,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            _guardando ? 'Creando tu perfil...' : 'Continuar',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: c.onPrimary,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: !_guardando,
      child: _guardando ? caja : SpPressable(onTap: _continuar, child: caja),
    );
  }
}
