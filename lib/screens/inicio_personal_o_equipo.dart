import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/contexto_albergue.dart';
import '../data/equipo_repository.dart';
import '../theme/salva_patitas_theme.dart';
import 'albergue_home_screen.dart';
import 'home_screen.dart';

/// Inicio de una cuenta personal (adoptante y/o rescatista): su HomeScreen
/// de siempre o, si es miembro de un equipo y eligió "Albergue" en el
/// selector de rol (`usuarios.ultimoRolActivo == 'equipo'`), el panel del
/// albergue de su responsable (PLAN-EQUIPO-ALBERGUE.md, "Fase 2").
///
/// Es el único lugar que pone y saca [SesionEquipo.actual]. Si la membresía
/// deja de estar activa (la quitaron o salió desde otro teléfono) mientras
/// está en modo Albergue, vuelve sola a su inicio personal con un aviso, y
/// se borra la elección para que no vuelva a intentarlo al reabrir la app.
class InicioPersonalOEquipo extends StatefulWidget {
  const InicioPersonalOEquipo({super.key, required this.uid, required this.perfil, this.repo});
  final String uid;
  final Map<String, dynamic> perfil;
  final EquipoRepository? repo;

  @override
  State<InicioPersonalOEquipo> createState() => _InicioPersonalOEquipoState();
}

class _InicioPersonalOEquipoState extends State<InicioPersonalOEquipo> {
  late final Stream<Membresia?> _membresia = (widget.repo ?? EquipoRepository()).miMembresia(widget.uid);
  bool _avisoMostrado = false;
  String? _albergueDelStream;
  Stream<String>? _streamNombre;

  /// El mismo stream mientras no cambie el albergue: si se pidiera uno
  /// nuevo en cada build, el StreamBuilder se resuscribiría todo el tiempo.
  Stream<String> _nombreAlbergue(String albergueId) {
    if (_albergueDelStream != albergueId || _streamNombre == null) {
      _albergueDelStream = albergueId;
      _streamNombre = (widget.repo ?? EquipoRepository()).nombreDeAlbergue(albergueId);
    }
    return _streamNombre!;
  }

  @override
  void dispose() {
    SesionEquipo.actual.value = null;
    super.dispose();
  }

  String get _nombre {
    final delPerfil = (widget.perfil['nombre'] as String?)?.trim() ?? '';
    if (delPerfil.isNotEmpty) return delPerfil;
    final deGoogle = FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
    return deGoogle.isNotEmpty ? deGoogle : 'Alguien del equipo';
  }

  /// Vuelve al rol personal: rescatista si lo tiene, si no adoptante.
  Future<void> _salirDelModoEquipo() async {
    final roles = List<String>.from(widget.perfil['roles'] as List? ?? const []);
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(widget.uid).set(
        {'ultimoRolActivo': roles.contains('rescatista') ? 'rescatista' : 'adoptante'},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final quiereEquipo = widget.perfil['ultimoRolActivo'] == 'equipo';
    return StreamBuilder<Membresia?>(
      stream: _membresia,
      builder: (context, snap) {
        final m = snap.data;
        if (quiereEquipo && m != null && m.activa) {
          return StreamBuilder<String>(
            stream: _nombreAlbergue(m.albergueId),
            builder: (context, sn) {
              SesionEquipo.actual.value = ContextoAlbergue.equipo(
                albergueId: m.albergueId,
                autorUid: widget.uid,
                autorNombre: _nombre,
                albergueNombre: sn.data ?? '',
              );
              return AlbergueHomeScreen(key: ValueKey('equipo-${m.albergueId}'));
            },
          );
        }
        SesionEquipo.actual.value = null;
        if (quiereEquipo && snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: context.sp.bg,
            body: Center(child: CircularProgressIndicator(color: context.sp.primary)),
          );
        }
        if (quiereEquipo && !_avisoMostrado) {
          _avisoMostrado = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('Ya no sos parte del equipo del albergue. Volviste a tu cuenta.')),
            );
            _salirDelModoEquipo();
          });
        }
        return const HomeScreen();
      },
    );
  }
}
