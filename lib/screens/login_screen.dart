import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _cargando = false;

  Future<void> _loginDebug(String email, String password, Map<String, dynamic> userData) async {
    setState(() => _cargando = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email, password: password);
      final docRef = FirebaseFirestore.instance
          .collection('usuarios').doc(cred.user!.uid);
      if (!(await docRef.get()).exists) {
        await docRef.set({
          ...userData,
          'email': email,
          'creadoEn': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

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
      if (mounted) setState(() => _cargando = false);
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
                Text('Al continuar aceptas nuestros términos de uso',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    textAlign: TextAlign.center),
                if (kDebugMode) ...[
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _cargando ? null : () => _loginDebug(
                          'albergue@test.com', 'test1234', {
                            'nombre':        'La Perla',
                            'roles':         ['albergue'],
                            'ciudad':        'Medellín',
                            'albergueNombre':'La Perla',
                            'albergueTipo':  'Centro municipal',
                            'capacidadTotal': 100,
                          }),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.purple.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('🛠 Albergue',
                            style: TextStyle(fontSize: 13, color: Colors.purple.shade700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _cargando ? null : () => _loginDebug(
                          'adoptante@test.com', 'test1234', {
                            'nombre': 'Adoptante Test',
                            'roles':  ['adoptante'],
                            'ciudad': 'Medellín',
                          }),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.purple.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('🛠 Adoptante',
                            style: TextStyle(fontSize: 13, color: Colors.purple.shade700)),
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
