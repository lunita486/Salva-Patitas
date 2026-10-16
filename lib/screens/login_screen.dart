import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/auth_helper.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/sp_widgets.dart';
import '../data/sandbox.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _cargando = false;

  // Toda la mecánica (Google → Firebase, timeouts, el candado contra
  // operaciones apiladas) vive en auth_helper.dart — esta pantalla solo
  // traduce el desenlace a UI. Si el login sale bien no hay que navegar
  // nada: AuthWrapper (main.dart) reacciona solo al cambio de sesión.
  /// Solo sandbox. Ver el bloque `if (enSandbox)` en build().
  Future<void> _entrarSandbox(String email, String nombre) async {
    setState(() => _cargando = true);
    try {
      await entrarEnSandbox(email: email, nombre: nombre);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sandbox: $e')));
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _loginGoogle() async {
    setState(() => _cargando = true);
    try {
      final resultado = await iniciarSesionGoogle();
      if (!mounted) return;
      switch (resultado) {
        case ResultadoLogin.ok:
          break;
        case ResultadoLogin.cancelado:
          setState(() => _cargando = false);
          break;
        case ResultadoLogin.ocupado:
          setState(() => _cargando = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: context.sp.msgError,
              content: const Text('Esperá unos segundos e intentá de nuevo.'),
            ),
          );
      }
    } on GoogleSignInException catch (_) {
      // Un GoogleSignInException que llega hasta acá (canceled/interrupted
      // ya los maneja auth_helper.dart como ResultadoLogin.cancelado) casi
      // siempre es un problema de configuración/entorno del dispositivo
      // (Google Play Services desactualizado, cuenta de Google con algún
      // problema), no de conexión — decirle "revisá tu conexión" a alguien
      // sin ese problema lo manda a buscar en el lugar equivocado.
      // Hallazgo de auditoría de código.
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.sp.msgError,
            content: const Text(
              'No se pudo iniciar sesión con Google en este dispositivo. '
              'Probá con otra cuenta o revisá que Google Play Services esté actualizado.',
            ),
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.sp.msgError,
            content: const Text(
              'Esto está tardando demasiado. Revisá tu conexión e intentá de nuevo.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.sp.msgError,
            content: const Text(
              'No se pudo iniciar sesión. Revisá tu conexión e intentá de nuevo.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const SpPawBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // Baldosa menta con los tres animalitos 3D, como el héroe
                  // del panel.
                  Container(
                    width: 210,
                    height: 170,
                    decoration: SpDeco.tone(c, SpTone.mint, radius: 44),
                    child: const Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 120,
                          top: 14,
                          child: SpAnimal(SpAnimalKind.conejo, size: 74),
                        ),
                        Positioned(
                          left: 14,
                          top: 52,
                          child: SpAnimal(SpAnimalKind.gato, size: 92),
                        ),
                        Positioned(
                          left: 72,
                          top: 60,
                          child: SpAnimal(SpAnimalKind.perro, size: 100),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Salva Patitas',
                        style: SpText.display.copyWith(
                          fontSize: 34,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const SpPaw(size: 24, angle: -12),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Conectamos animales con familias',
                    textAlign: TextAlign.center,
                    style: SpText.body.copyWith(color: c.inkMuted),
                  ),
                  const Spacer(),
                  _botonGoogle(c),
                  // Modo sandbox: cuatro cuentas de prueba, una por rol,
                  // contra el emulador de Auth. No existe en un build de
                  // release — `enSandbox` es una constante falsa ahí y todo
                  // este bloque se elimina del binario. Ver sandbox.dart.
                  if (enSandbox) ...[
                    const SizedBox(height: 12),
                    Text(
                      'SANDBOX (emuladores locales)',
                      style: TextStyle(fontSize: 11, color: c.inkFaint),
                    ),
                    Wrap(
                      spacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final cuenta in const [
                          ('ana@sandbox.test', 'Ana Adoptante'),
                          ('rita@sandbox.test', 'Rita Rescatista'),
                          ('perla@sandbox.test', 'Refugio La Perla'),
                          ('vet@sandbox.test', 'Veterinaria 30'),
                        ])
                          OutlinedButton(
                            onPressed: _cargando
                                ? null
                                : () => _entrarSandbox(cuenta.$1, cuenta.$2),
                            child: Text(
                              cuenta.$2.split(' ').first,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse(
                        'https://lunita486.github.io/Salva-Patitas/privacidad.html',
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: SpText.caption.copyWith(color: c.inkMuted),
                        children: [
                          const TextSpan(text: 'Al continuar aceptás nuestra '),
                          TextSpan(
                            text: 'Política de Privacidad',
                            style: TextStyle(
                              color: c.primaryStrong,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                              decorationColor: c.primaryStrong,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Botón blanco 3D de Google. Mientras entra muestra un spinner y no se
  /// puede tocar de nuevo.
  Widget _botonGoogle(SpColors c) {
    final caja = Container(
      width: double.infinity,
      height: 56,
      decoration: SpDeco.soft(c, radius: SpRadius.md),
      child: _cargando
          ? Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.primary,
                ),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.network(
                  'https://www.google.com/favicon.ico',
                  width: 20,
                  height: 20,
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.login_rounded, size: 20, color: c.ink),
                ),
                const SizedBox(width: 12),
                Text(
                  'Continuar con Google',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
              ],
            ),
    );
    return Semantics(
      button: true,
      enabled: !_cargando,
      child: _cargando ? caja : SpPressable(onTap: _loginGoogle, child: caja),
    );
  }
}
