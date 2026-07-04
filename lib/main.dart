import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/seleccion_rol_screen.dart';
import 'screens/albergue_perfil_screen.dart';
import 'screens/albergue_home_screen.dart';
import 'screens/aliado_perfil_screen.dart';
import 'screens/aliado_home_screen.dart';
import 'screens/home_screen.dart';
import 'services/notificaciones_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificacionesService.inicializar();
  runApp(const PatitasApp());
}

class PatitasApp extends StatelessWidget {
  const PatitasApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salva Patitas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: appBg,
            body: Center(child: CircularProgressIndicator(color: appTeal)),
          );
        }
        if (snap.data == null) return const LoginScreen();
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('usuarios').doc(snap.data!.uid).snapshots(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: appBg,
                body: Center(child: CircularProgressIndicator(color: appTeal)),
              );
            }
            if (!userSnap.hasData || !userSnap.data!.exists) {
              return SeleccionRolScreen(user: snap.data!);
            }
            final data  = userSnap.data!.data() as Map<String, dynamic>;
            final roles = List<String>.from(data['roles'] as List? ?? []);
            final esAlbergue = roles.contains('albergue');
            final esAliado   = roles.contains('aliado');

            if (esAlbergue) {
              final perfilCompleto = (data['albergueNombre'] as String?)?.isNotEmpty == true;
              if (!perfilCompleto) return const AlberguePerfilScreen();
              return const AlbergueHomeScreen();
            }
            if (esAliado) {
              final perfilCompleto = (data['aliadoNombre'] as String?)?.isNotEmpty == true;
              if (!perfilCompleto) return const AliadoPerfilScreen();
              return const AliadoHomeScreen();
            }
            return const HomeScreen();
          },
        );
      },
    );
  }
}
