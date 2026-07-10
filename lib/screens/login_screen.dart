import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _cargando = false;

  Future<void> _loginGoogle() async {
    setState(() => _cargando = true);
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) { setState(() => _cargando = false); return; }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken:     googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
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
                        color: Color(0xFF1A1A1A))),
                const SizedBox(height: 8),
                Text('Conectamos animales con familias',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _cargando ? null : _loginGoogle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1A1A1A),
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
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
