import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/auth_helper.dart';
import '../theme.dart';

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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              backgroundColor: msgError,
              content: Text('Esperá unos segundos e intentá de nuevo.')));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: msgError,
            content: Text('No se pudo iniciar sesión con Google en este dispositivo. '
                'Probá con otra cuenta o revisá que Google Play Services esté actualizado.')));
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: msgError,
            content: Text('Esto está tardando demasiado. Revisá tu conexión e intentá de nuevo.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: msgError,
            content: Text('No se pudo iniciar sesión. Revisá tu conexión e intentá de nuevo.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: Stack(fit: StackFit.expand, children: [
        const LeafOverlay(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Container(
                  width: 80, height: 80,
                  decoration: const BoxDecoration(color: appTeal, shape: BoxShape.circle),
                  child: const Icon(Icons.pets, color: Colors.white, size: 44),
                ),
                const SizedBox(height: 24),
                const Text('Salva Patitas',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold,
                        color: appInk)),
                const SizedBox(height: 8),
                Text('Conectamos animales con familias',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade700)),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _cargando ? null : _loginGoogle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: appInk,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _cargando
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: appTeal))
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Image.network(
                              'https://www.google.com/favicon.ico',
                              width: 20, height: 20,
                              errorBuilder: (_, __, ___) => const Icon(Icons.login, size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Text('Continuar con Google',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ]),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => launchUrl(
                    Uri.parse('https://lunita486.github.io/Salva-Patitas/privacidad.html'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      children: const [
                        TextSpan(text: 'Al continuar aceptás nuestra '),
                        TextSpan(
                          text: 'Política de Privacidad',
                          style: TextStyle(
                            color: appTeal,
                            decoration: TextDecoration.underline,
                            decorationColor: appTeal,
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
      ]),
    );
  }
}
