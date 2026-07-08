import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../data/preferencias_repository.dart';
import 'configuracion_screens.dart';

class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({super.key});
  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  final _preferenciasRepo = PreferenciasRepository();
  bool _mensajes = true;
  bool _matches  = true;
  bool _solicitudes = true;
  bool _loading  = true;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _preferenciasRepo.stream(_uid).first.then((doc) {
      if (doc.exists && mounted) {
        final d = doc.data()!;
        setState(() {
          _mensajes    = d['notif_mensajes']    ?? true;
          _matches     = d['notif_matches']     ?? true;
          _solicitudes = d['notif_solicitudes'] ?? true;
          _loading     = false;
        });
      } else {
        setState(() => _loading = false);
      }
    });
  }

  void _save(String key, bool val) {
    _preferenciasRepo.actualizar(_uid, {key: val});
  }

  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
    title: 'Notificaciones',
    child: _loading
        ? const Center(child: CircularProgressIndicator(color: appTeal))
        : Column(children: [
            SettingsSwitchTile(
              icon: Icons.chat_bubble_outline,
              label: 'Nuevos mensajes',
              subtitle: 'Cuando un rescatista te responde en el chat',
              value: _mensajes,
              onChanged: (v) { setState(() => _mensajes = v); _save('notif_mensajes', v); },
            ),
            SettingsSwitchTile(
              icon: Icons.favorite_outline,
              label: 'Animales que encajan contigo',
              subtitle: 'Cuando llega un animal según tus preferencias',
              value: _matches,
              onChanged: (v) { setState(() => _matches = v); _save('notif_matches', v); },
            ),
            SettingsSwitchTile(
              icon: Icons.assignment_outlined,
              label: 'Actualizaciones de solicitudes',
              subtitle: 'Estado de tus solicitudes de adopción',
              value: _solicitudes,
              last: true,
              onChanged: (v) { setState(() => _solicitudes = v); _save('notif_solicitudes', v); },
            ),
          ]),
  );
}
