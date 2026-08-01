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
  bool _solicitudes = true;
  bool _loading  = true;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // Dos arreglos acá: (1) el `mounted` solo protegía la rama de "sí
  // existe" — si el doc no existía todavía, el `else` hacía setState()
  // sin revisar `mounted`, lo que revienta si la persona ya cerró la
  // pantalla (abrir y salir rápido). (2) no había ningún `.catchError` —
  // si la consulta fallaba (sin señal al abrir esta pantalla), la
  // excepción quedaba sin atrapar y `_loading` se quedaba en `true` para
  // siempre: la pantalla entera es solo un spinner mientras `_loading`
  // sea `true`, sin ningún botón de reintentar. Hallazgo de auditoría de
  // código.
  @override
  void initState() {
    super.initState();
    _preferenciasRepo.stream(_uid).first.then((doc) {
      if (!mounted) return;
      if (doc.exists) {
        final d = doc.data()!;
        setState(() {
          _mensajes    = d['notif_mensajes']    ?? true;
          _solicitudes = d['notif_solicitudes'] ?? true;
          _loading     = false;
        });
      } else {
        setState(() => _loading = false);
      }
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  // functions/index.js lee este mismo campo antes de mandar cada push
  // (notificar(), parámetro tipoPreferencia) — antes se guardaba acá y
  // nadie del otro lado lo leía nunca, así que apagar un interruptor no
  // hacía nada de verdad (hallazgo de auditoría de código).
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
