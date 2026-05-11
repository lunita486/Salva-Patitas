import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:geolocator/geolocator.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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

// ─── Auth Wrapper ─────────────────────────────────────────────────────────────

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: _bg,
            body: Center(child: CircularProgressIndicator(color: _teal)),
          );
        }
        if (snap.data == null) return const LoginScreen();
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('usuarios').doc(snap.data!.uid).snapshots(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: _bg,
                body: Center(child: CircularProgressIndicator(color: _teal)),
              );
            }
            if (!userSnap.hasData || !userSnap.data!.exists) {
              return SeleccionRolScreen(user: snap.data!);
            }
            return const HomeScreen();
          },
        );
      },
    );
  }
}

// ─── Login Screen ─────────────────────────────────────────────────────────────

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
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: LeafPainter()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Container(
                  width: 80, height: 80,
                  decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle),
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
                            child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
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
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Selección de Rol Screen ──────────────────────────────────────────────────

class SeleccionRolScreen extends StatefulWidget {
  final User user;
  const SeleccionRolScreen({super.key, required this.user});
  @override
  State<SeleccionRolScreen> createState() => _SeleccionRolScreenState();
}

class _SeleccionRolScreenState extends State<SeleccionRolScreen> {
  final Set<String> _roles = {'adoptante'};
  bool _guardando = false;

  Future<void> _continuar() async {
    setState(() => _guardando = true);
    await FirebaseFirestore.instance
        .collection('usuarios').doc(widget.user.uid).set({
      'nombre':   widget.user.displayName ?? 'Usuario',
      'email':    widget.user.email,
      'foto':     widget.user.photoURL,
      'roles':    _roles.toList(),
      'ciudad':   'Medellín',
      'creadoEn': FieldValue.serverTimestamp(),
    });
  }

  Widget _rolCard(String rol, String emoji, String descripcion) {
    final sel = _roles.contains(rol);
    return GestureDetector(
      onTap: () => setState(() {
        if (sel && _roles.length > 1) _roles.remove(rol);
        else _roles.add(rol);
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF1A1A1A) : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: sel ? const Color(0xFF1A1A1A) : Colors.grey.shade300, width: 2),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rol[0].toUpperCase() + rol.substring(1),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                    color: sel ? Colors.white : const Color(0xFF1A1A1A))),
            const SizedBox(height: 4),
            Text(descripcion, style: TextStyle(fontSize: 13,
                color: sel ? Colors.white70 : Colors.grey.shade600)),
          ])),
          if (sel) const Icon(Icons.check_circle, color: _teal, size: 24),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.user.displayName?.split(' ').first ?? 'Usuario';
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: LeafPainter()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 40),
              Text('Hola, $nombre 👋',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A))),
              const SizedBox(height: 8),
              Text('¿Cómo quieres usar Salva Patitas?',
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Text('Puedes elegir los dos',
                  style: TextStyle(fontSize: 13, color: _teal, fontWeight: FontWeight.w600)),
              const SizedBox(height: 32),
              _rolCard('adoptante',  '🏠', 'Encuentra tu compañero perfecto y solicita adopciones'),
              const SizedBox(height: 12),
              _rolCard('rescatista', '🦺', 'Publica animales rescatados y gestiona solicitudes'),
              const SizedBox(height: 12),
              _rolCard('institucion','🏛️', 'Refugios, fundaciones y perreras con muchos animales'),
              const SizedBox(height: 12),
              _rolCard('padrino',    '💛', 'Financia gastos de animales sin necesidad de adoptarlos'),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _guardando ? null : _continuar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _guardando
                      ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('Creando tu perfil...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ])
                      : const Text('Continuar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ]),
    );
  }
}

const _bg     = Color(0xFFDFFBEC);
const _dark   = Color(0xFF162416);
const _teal   = Color(0xFF1F8A62);
const _orange = Color(0xFFD84E18);

// ─── Monstera Leaf Painter ────────────────────────────────────────────────────

class LeafPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const c1 = Color(0xFF2E7D32);
    const c2 = Color(0xFF1B5E20);

    // Esquina superior-izquierda
    _leaf(canvas, x: 155, y: 168, s: 210, a:  pi*.75, c: c1, op: 0.94);
    _leaf(canvas, x:  68, y: 108, s: 148, a:  pi*.60, c: c2, op: 0.73);
    // Esquina superior-derecha
    _leaf(canvas, x: w-155, y: 168, s: 210, a: -pi*.75, c: c1, op: 0.94);
    _leaf(canvas, x: w- 68, y: 108, s: 148, a: -pi*.60, c: c2, op: 0.73);
    // Esquina inferior-izquierda
    _leaf(canvas, x: 155, y: h-168, s: 210, a:  pi*.25, c: c1, op: 0.94);
    _leaf(canvas, x:  68, y: h-108, s: 148, a:  pi*.40, c: c2, op: 0.73);
    // Esquina inferior-derecha
    _leaf(canvas, x: w-155, y: h-168, s: 210, a: -pi*.25, c: c1, op: 0.94);
    _leaf(canvas, x: w- 68, y: h-108, s: 148, a: -pi*.40, c: c2, op: 0.73);
  }

  void _leaf(Canvas canvas, {
    required double x, required double y,
    required double s, required double a,
    required Color c, double op = 1.0,
  }) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(a);

    // Relleno
    canvas.drawPath(_monsteraPath(s),
        Paint()..color = c.withOpacity(op)..style = PaintingStyle.fill);

    // Huecos (fenestrations) – un óvalo por lóbulo, ambos lados
    final hp = Paint()..color = _bg..style = PaintingStyle.fill;
    for (final xs in [-1.0, 1.0]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(xs*s*.34,  s*.18), width: s*.22, height: s*.12), hp);
      canvas.drawOval(Rect.fromCenter(center: Offset(xs*s*.33, -s*.12), width: s*.21, height: s*.11), hp);
      canvas.drawOval(Rect.fromCenter(center: Offset(xs*s*.26, -s*.40), width: s*.16, height: s*.09), hp);
      canvas.drawOval(Rect.fromCenter(center: Offset(xs*s*.15, -s*.66), width: s*.11, height: s*.07), hp);
    }

    // Nervio central
    canvas.drawPath(
      Path()..moveTo(0, s*.52)..cubicTo(s*.02, s*.20, 0, -s*.50, 0, -s*.90),
      Paint()..color = Colors.white.withOpacity(0.30)..strokeWidth = 2.8..style = PaintingStyle.stroke,
    );

    // Nervios laterales (uno por lóbulo)
    final vp = Paint()..color = Colors.white.withOpacity(0.22)
        ..strokeWidth = 1.6..style = PaintingStyle.stroke;
    for (final yF in [s*.18, -s*.12, -s*.40, -s*.66]) {
      canvas.drawPath(Path()..moveTo(0, yF)
          ..cubicTo( s*.20, yF+s*.02,  s*.50, yF-s*.06,  s*.62, yF), vp);
      canvas.drawPath(Path()..moveTo(0, yF)
          ..cubicTo(-s*.20, yF+s*.02, -s*.50, yF-s*.06, -s*.62, yF), vp);
    }

    canvas.restore();
  }

  // Monstera deliciosa: 4 lóbulos por lado, cortes muy profundos, hoja ancha.
  Path _monsteraPath(double s) {
    final p = Path();
    p.moveTo(0, s * .52);

    // ── LADO DERECHO ─────────────────────────────────────────────────────
    p.cubicTo( s*.04,  s*.52,  s*.70,  s*.42,  s*.70,  s*.26); // → lóbulo 1
    p.cubicTo( s*.70,  s*.12,  s*.08,  s*.10,  s*.06,  s*.02); // corte 1
    p.cubicTo( s*.04, -s*.06,  s*.68, -s*.08,  s*.66, -s*.22); // → lóbulo 2
    p.cubicTo( s*.64, -s*.34,  s*.08, -s*.32,  s*.06, -s*.40); // corte 2
    p.cubicTo( s*.04, -s*.48,  s*.54, -s*.50,  s*.50, -s*.60); // → lóbulo 3
    p.cubicTo( s*.46, -s*.70,  s*.08, -s*.68,  s*.06, -s*.74); // corte 3
    p.cubicTo( s*.04, -s*.80,  s*.30, -s*.82,  s*.24, -s*.90); // → lóbulo 4
    p.cubicTo( s*.14, -s*.96,  s*.02, -s*.96,  0,     -s*.94); // punta

    // ── LADO IZQUIERDO (espejo) ────────────────────────────────────────
    p.cubicTo(-s*.02, -s*.96, -s*.14, -s*.96, -s*.24, -s*.90);
    p.cubicTo(-s*.30, -s*.82, -s*.04, -s*.80, -s*.06, -s*.74);
    p.cubicTo(-s*.08, -s*.68, -s*.46, -s*.70, -s*.50, -s*.60);
    p.cubicTo(-s*.54, -s*.50, -s*.04, -s*.48, -s*.06, -s*.40);
    p.cubicTo(-s*.08, -s*.32, -s*.64, -s*.34, -s*.66, -s*.22);
    p.cubicTo(-s*.68, -s*.08, -s*.04, -s*.06, -s*.06,  s*.02);
    p.cubicTo(-s*.08,  s*.10, -s*.70,  s*.12, -s*.70,  s*.26);
    p.cubicTo(-s*.70,  s*.42, -s*.04,  s*.52,  0,       s*.52);

    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget leafBackground({required Widget child}) {
  return Stack(
    children: [
      Positioned.fill(child: Container(color: _bg)),
      Positioned.fill(child: CustomPaint(painter: LeafPainter())),
      child,
    ],
  );
}

// ─── Home Screen ─────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? _isRescatista;
  List<String> _roles = [];
  int  _selectedNav  = 0;

  static const _rolLabel = {
    'rescatista': 'Rescatista',
    'adoptante':  'Adoptante',
    'institucion':'Institución',
    'padrino':    'Padrino',
  };

  @override
  void initState() {
    super.initState();
    _cargarRol();
  }

  Future<void> _cargarRol() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    if (!mounted) return;
    final roles = List<String>.from((doc.data()?['roles'] as List?) ?? []);
    setState(() {
      _roles = roles;
      _isRescatista = roles.contains('rescatista');
    });
  }

  Widget _rolToggle() {
    if (_roles.length <= 1) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.80),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _roles.map((rol) {
          final activo = (_isRescatista == true && rol == 'rescatista') ||
                         (_isRescatista == false && rol != 'rescatista');
          final label  = _rolLabel[rol] ?? rol;
          return GestureDetector(
            onTap: () => setState(() {
              _isRescatista = rol == 'rescatista';
              _selectedNav  = 0;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: activo ? const Color(0xFF1A1A1A) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: activo ? Colors.white : Colors.grey.shade500)),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isRescatista == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _teal)),
      );
    }
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: _bg),
          CustomPaint(painter: LeafPainter()),
          SafeArea(
            child: _isRescatista!
                ? _rescatistaView(context)
                : _adoptanteView(context),
          ),
        ],
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  // ── Vista Rescatista ──────────────────────────────────────────────────────

  Widget _rescatistaView(BuildContext ctx) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [_rolToggle(), _avatar('A', _orange)]),
        const SizedBox(height: 24),
        Text('Hola,', style: const TextStyle(fontSize: 18, color: Color(0xFF444444))),
        const SizedBox(height: 2),
        Row(children: [
          Text('${FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ?? 'Rescatista'} ',
              style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
          const Text('🌿', style: TextStyle(fontSize: 28)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.location_on, size: 14, color: _teal),
          const SizedBox(width: 2),
          Text('Medellín', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        ]),
        const SizedBox(height: 20),
        _label('ESTA SEMANA'),
        const SizedBox(height: 10),
        _statsRowDynamic(),
        const SizedBox(height: 16),
        _ctaCard(ctx),
        const SizedBox(height: 28),
        _sectionHeader('ESPERAN RESPUESTA', 'Solicitudes de adopción', 'Ver todas',
            onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SolicitudesRescatistaScreen()))),
        const SizedBox(height: 12),
        _solicitudesFirestore(),
        const SizedBox(height: 28),
        _sectionHeader('MIS ANIMALES', 'Tus rescates activos', 'Gestionar',
            onAction: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TodosLosRescatesScreen()))),
        const SizedBox(height: 12),
        _misRescatesCarousel(),
        const SizedBox(height: 90),
      ]),
    );
  }

  Widget _sectionHeader(String label, String title, String action, {VoidCallback? onAction}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _label(label),
        GestureDetector(
          onTap: onAction,
          child: Text(action, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _teal)),
        ),
      ]),
      const SizedBox(height: 6),
      Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
    ],
  );

  Widget _solicitudDetalle(String ini, Color col, String nombre, String detalle,
      String tiempo, String animal, {String? docId, Map<String, dynamic>? data}) {
    final score      = data != null ? calcularCompatibilidad(data) : -1;
    final scoreColor = score >= 80 ? const Color(0xFF1F8A62) : score >= 60 ? const Color(0xFFE65100) : const Color(0xFFB71C1C);

    return Builder(builder: (ctx) => GestureDetector(
        onTap: docId == null ? null : () => showModalBottomSheet(
          context: ctx,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.92,
            minChildSize: 0.4,
            builder: (_, scrollCtl) => SingleChildScrollView(
              controller: scrollCtl,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(children: [
                _avatar(ini, col, radius: 22, fontSize: 18),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nombre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  Text('Para $animal', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ])),
              ]),
              const SizedBox(height: 16),
              if (score >= 0) Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: scoreColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scoreColor.withOpacity(0.35))),
                child: Row(children: [
                  Text(score >= 80 ? '✅' : score >= 60 ? '⚠️' : '❌', style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Text(score >= 80 ? 'Perfil ideal ($score%)' : score >= 60 ? 'Perfil aceptable ($score%)' : 'No recomendado ($score%)',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scoreColor)),
                ]),
              ),
              const SizedBox(height: 20),
              Text('Perfil del adoptante', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade500)),
              const SizedBox(height: 10),
              _infoFila('🏠', 'Vivienda', data?['vivienda'] ?? '-'),
              _infoFila('⏰', 'Horas fuera al día', data?['horasFuera'] ?? '-'),
              _infoFila('👥', 'Personas en casa', data?['integrantes'] ?? '-'),
              _infoFila('👶', 'Niños menores de 8 años', (data?['tieneNinos'] as bool? ?? false) ? 'Sí' : 'No'),
              _infoFila('🐾', 'Otras mascotas', (data?['tieneMascotas'] as bool? ?? false) ? 'Sí' : 'No'),
              _infoFila('📚', 'Experiencia previa', (data?['experienciaPrevia'] as bool? ?? false) ? 'Sí' : 'No, primera mascota'),
              if (data?['motivacion'] != null) ...[
                const SizedBox(height: 16),
                Text('Motivación', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade500)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Text('"${data!['motivacion']}"', style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.5)),
                ),
              ],
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () { Navigator.pop(ctx);
                      FirebaseFirestore.instance.collection('solicitudes').doc(docId).update({'estado': 'aprobada'}); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(12)),
                      child: const Text('Aprobar', textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final motivoCtl = TextEditingController();
                      showDialog(context: ctx, builder: (dlg) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('¿Por qué rechazas?'),
                        content: TextField(
                          controller: motivoCtl,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'ej. El espacio no es suficiente para este animal...',
                            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dlg), child: const Text('Cancelar')),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(dlg);
                              Navigator.pop(ctx);
                              FirebaseFirestore.instance.collection('solicitudes').doc(docId).update({
                                'estado': 'rechazada',
                                'motivoRechazo': motivoCtl.text.trim().isEmpty
                                    ? 'Sin motivo especificado'
                                    : motivoCtl.text.trim(),
                              });
                            },
                            child: const Text('Confirmar', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(border: Border.all(color: Colors.red.shade300), borderRadius: BorderRadius.circular(12)),
                      child: Text('Rechazar', textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ),
              ]),
            ]),
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _avatar(ini, col, radius: 20, fontSize: 16),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(detalle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ])),
              Text(tiempo, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFD8F0E4), borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.brown.shade300, borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.pets, size: 18, color: Colors.white)),
                const SizedBox(width: 8),
                Text('Para $animal', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            ),
            if (docId != null) ...[
              const SizedBox(height: 12),
              const Text('Revisar →', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _teal)),
            ],
          ]),
        ),
      ));
  }

  Widget _infoFila(String emoji, String label, String valor) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 15)),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
      Text(valor, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
    ]),
  );

  Widget _misRescatesCarousel() {
    return SizedBox(
      height: 210,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rescates')
            .where('rescatistaId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _teal));
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}', style: const TextStyle(fontSize: 12)));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Text('Aún no tienes rescates publicados.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            );
          }
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final nombre         = (data['nombre'] as String?)?.isNotEmpty == true ? data['nombre'] : 'Sin nombre';
              final especie        = data['especie']        ?? '';
              final estadoAdopcion = data['estadoAdopcion'] ?? 'Rescatado';
              final fotoBase64     = data['fotoBase64']     as String?;
              final docId          = docs[i].id;
              return _animalCard(
                nombre, especie,
                estado: estadoAdopcion,
                emoji: especie == 'Gato' ? '🐱' : '🐶',
                fotoBase64: fotoBase64,
                onCambiarEstado: () => showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => _CambiarEstadoSheet(docId: docId, estadoActual: estadoAdopcion),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _animalCard(String nombre, String especie,
      {String emoji = '🐾', String estado = 'En adopción', String? fotoBase64, VoidCallback? onCambiarEstado}) {
    final color = _cicloColor(estado);
    return Container(
      width: 150,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: fotoBase64 != null
            ? Image.memory(base64Decode(fotoBase64),
                height: 100, width: double.infinity, fit: BoxFit.cover)
            : Container(
                height: 100, width: double.infinity,
                color: const Color(0xFFD8F0E4),
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 40))),
              ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis),
            Text(especie, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onCambiarEstado,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(child: Text(estado,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
                    overflow: TextOverflow.ellipsis)),
                  if (onCambiarEstado != null) ...[
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more, size: 12, color: color),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Vista Adoptante ───────────────────────────────────────────────────────

  Widget _adoptanteView(BuildContext ctx) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_rolToggle(), _avatar('A', _orange)]),
        ),
        const Expanded(child: _AdoptanteCardStack()),
      ],
    );
  }



  Widget _label(String t) => Text(t, style: TextStyle(
      fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: Colors.grey.shade600));

  Widget _statsRowDynamic() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('solicitudes')
          .where('rescatistaId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
          .where('estado', isEqualTo: 'pendiente')
          .snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('chats')
              .where('rescatistaId', isEqualTo: uid).snapshots(),
          builder: (context, chatSnap) {
            final noLeidos = (chatSnap.data?.docs ?? []).where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return ((d['noLeidosRescatista'] as int?) ?? 0) > 0;
            }).length;
            return Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SolicitudesRescatistaScreen())),
                child: _stat('$count', 'Nuevas\nsolicitudes', const Color(0xFFF9DDD5), const Color(0xFFCC4422)))),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdoptanteChatsScreen(esRescatista: true))),
                child: _stat('$noLeidos', 'Mensajes\nsin leer', const Color(0xFFD8EEFA), const Color(0xFF2070B0)))),
              const SizedBox(width: 10),
              Expanded(child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('rescates')
                    .where('rescatistaId', isEqualTo: uid).snapshots(),
                builder: (context, rescSnap) {
                  final total = rescSnap.data?.docs.length ?? 0;
                  return _stat('$total', 'Animales\nrescatados', Colors.white, const Color(0xFF1A1A1A));
                },
              )),
            ]);
          },
        );
      },
    );
  }

  Widget _solicitudesFirestore() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('solicitudes')
          .where('rescatistaId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
          .where('estado', isEqualTo: 'pendiente')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _teal));
        }
        final docs = [...(snap.data?.docs ?? [])]
          ..sort((a, b) {
            final ta = (a.data() as Map)['creadoEn'] as Timestamp?;
            final tb = (b.data() as Map)['creadoEn'] as Timestamp?;
            if (ta == null || tb == null) return 0;
            return tb.compareTo(ta);
          });
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Center(child: Text('No hay solicitudes por ahora.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500))),
          );
        }
        final limited = docs.take(3).toList();
        return Column(
          children: List.generate(limited.length, (i) {
            final d = limited[i].data() as Map<String, dynamic>;
            final animal      = d['animalNombre'] as String? ?? 'Animal';
            final nombre      = d['nombre']      as String? ?? '';
            final apellido    = d['apellido']    as String? ?? '';
            final integrantes = d['integrantes'] as String? ?? '';
            final vivienda    = d['vivienda']    as String? ?? '';
            final mascotas    = (d['tieneMascotas'] as bool? ?? false) ? 'con mascotas' : 'sin mascotas';
            final ninos       = (d['tieneNinos']    as bool? ?? false) ? 'con niños' : 'sin niños';
            final nombreCompleto = nombre.isNotEmpty ? '$nombre $apellido' : 'Adoptante ${i + 1}';
            final detalle     = '$vivienda · $integrantes personas · $ninos · $mascotas';
            final ts          = d['creadoEn'] as Timestamp?;
            final tiempo      = ts != null ? _tiempoRelativo(ts.toDate()) : '';
            final ini         = nombreCompleto[0].toUpperCase();
            final col         = i.isEven ? _teal : _orange;
            return Padding(
              padding: EdgeInsets.only(bottom: i < limited.length - 1 ? 10 : 0),
              child: _solicitudDetalle(ini, col, nombreCompleto, detalle, tiempo, animal,
                  docId: limited[i].id, data: d),
            );
          }),
        );
      },
    );
  }

  String _tiempoRelativo(DateTime fecha) {
    final diff = DateTime.now().difference(fecha);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    if (diff.inHours < 24)   return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }

  Widget _stat(String n, String lbl, Color bg, Color nc) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(n, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: nc)),
      const SizedBox(height: 4),
      Text(lbl, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3)),
    ]),
  );

  Widget _ctaCard(BuildContext ctx) => GestureDetector(
    onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const SubirRescateScreen())),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _dark, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Container(width: 44, height: 44,
          decoration: const BoxDecoration(color: _orange, shape: BoxShape.circle),
          child: const Icon(Icons.add, color: Colors.white, size: 24)),
        const SizedBox(width: 16),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Subir un rescate', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          SizedBox(height: 2),
          Text('Publica un animal en minutos', style: TextStyle(color: Color(0xFF7FAF7F), fontSize: 13)),
        ])),
        const Icon(Icons.chevron_right, color: Color(0xFF7FAF7F), size: 22),
      ]),
    ),
  );


  Widget _bottomNav() => Container(
    decoration: BoxDecoration(color: Colors.white,
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, -2))]),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          if (_isRescatista == true) ...[
            _navItem(Icons.pets,                    'Mis rescates', 0),
            _navTap(Icons.add_circle_outline, 'Subir', 1,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubirRescateScreen()))),
            _navTap(Icons.notifications_outlined, 'Solicitudes', 2,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SolicitudesRescatistaScreen()))),
            _navTap(Icons.chat_bubble_outline, 'Chats', 3,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdoptanteChatsScreen(esRescatista: true)))),
            _navTap(Icons.person_outline, 'Perfil', 4,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PerfilRescatistaScreen()))),
          ] else ...[
            _navItem(Icons.pets,                 'Adoptar',   0),
            _navTap(Icons.favorite_outline, 'Favoritos', 1,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritosScreen()))),
            _navTap(Icons.chat_bubble_outline, 'Chats', 2,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdoptanteChatsScreen()))),
            _navTap(Icons.person_outline, 'Perfil', 3,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PerfilAdoptanteScreen()))),
          ],
        ]),
      ),
    ),
  );

  Widget _navItem(IconData icon, String label, int idx) {
    final active = _selectedNav == idx;
    final color  = active ? _teal : Colors.grey.shade400;
    return GestureDetector(
      onTap: () => setState(() => _selectedNav = idx),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ]),
    );
  }

  Widget _navTap(IconData icon, String label, int idx, {required VoidCallback onTap}) {
    final color = Colors.grey.shade400;
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ]),
    );
  }

}

Widget _avatar(String letter, Color color, {double radius = 22, double fontSize = 20}) {
  final user = FirebaseAuth.instance.currentUser;
  final foto = user?.photoURL;
  if (foto != null) {
    return CircleAvatar(backgroundImage: NetworkImage(foto), radius: radius);
  }
  final inicial = user?.displayName?.isNotEmpty == true
      ? user!.displayName![0].toUpperCase() : letter;
  return CircleAvatar(backgroundColor: color, radius: radius,
      child: Text(inicial, style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.bold)));
}

// ─── Cambiar Estado Adopción Sheet ────────────────────────────────────────────

class _CambiarEstadoSheet extends StatelessWidget {
  final String docId;
  final String estadoActual;
  const _CambiarEstadoSheet({required this.docId, required this.estadoActual});

  static const _estados = [
    ('Rescatado',              '🟢', 'Disponible para adopción'),
    ('Hogar de paso',          '🟣', 'Temporalmente con un cuidador'),
    ('En proceso de adopción', '🟠', 'Tiene una solicitud activa'),
    ('Adoptado',               '🔵', 'Ya encontró su hogar'),
    ('Regresado',              '🔴', 'Fue devuelto, disponible de nuevo'),
  ];

  Color _color(String s) => switch (s) {
    'Rescatado'              => _teal,
    'Hogar de paso'          => const Color(0xFF7C6FCD),
    'En proceso de adopción' => const Color(0xFFE65100),
    'Adoptado'               => const Color(0xFF2196F3),
    'Regresado'              => const Color(0xFFD32F2F),
    _                        => Colors.grey,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Container(width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 16),
      const Text('Estado del animal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text('Toca para cambiar el estado', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      const SizedBox(height: 16),
      ..._estados.map((e) {
        final sel = e.$1 == estadoActual;
        return GestureDetector(
          onTap: () {
            FirebaseFirestore.instance.collection('rescates').doc(docId)
                .update({'estadoAdopcion': e.$1});
            Navigator.pop(context);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: sel ? _color(e.$1).withOpacity(0.1) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? _color(e.$1) : Colors.grey.shade200, width: sel ? 2 : 1),
            ),
            child: Row(children: [
              Text(e.$2, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.$1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: sel ? _color(e.$1) : const Color(0xFF1A1A1A))),
                Text(e.$3, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ])),
              if (sel) Icon(Icons.check_circle, color: _color(e.$1), size: 20),
            ]),
          ),
        );
      }),
    ]),
  );
}

// ─── Subir Rescate Screen ─────────────────────────────────────────────────────

class SubirRescateScreen extends StatefulWidget {
  const SubirRescateScreen({super.key});
  @override
  State<SubirRescateScreen> createState() => _SubirRescateScreenState();
}

class _SubirRescateScreenState extends State<SubirRescateScreen> {
  final _picker    = ImagePicker();
  final _nombreCtl = TextEditingController();
  final _lugarCtl  = TextEditingController();
  final _descCtl   = TextEditingController();

  final _razaCtl = TextEditingController();
  final List<XFile> _fotos = [];
  String _especie      = 'Perro';
  String _estado       = 'Herido';
  String _urgencia     = 'Alta';
  String _energia      = 'Tranquilo';
  String _tamano       = 'Mediano';
  String _edad         = 'Cachorro';
  String _genero       = 'No sé';
  String _okNinos      = 'Sí';
  String _okMascotas   = 'Sí';
  String _requiereExp  = 'No';
  String _tipoRaza     = 'Criolla';

  static const _especies      = ['Perro', 'Gato', 'Otro'];
  static const _estados       = ['Sano', 'Herido', 'En tratamiento', 'Crítico'];
  static const _urgencias     = ['Alta', 'Media', 'Baja'];
  static const _energias      = ['Tranquilo', 'Activo', 'Muy activo'];
  static const _tamanos       = ['Pequeño', 'Mediano', 'Grande'];
  static const _edades        = ['Cachorro', 'Adulto', 'Senior'];
  static const _generos       = ['Macho', 'Hembra', 'No sé'];
  static const _siNoOpts      = ['Sí', 'No'];
  static const _tipoRazaOpts  = ['Criolla', 'Raza definida'];

  Color _urgenciaColor(String u) => switch (u) {
    'Alta'  => const Color(0xFFD32F2F),
    'Media' => const Color(0xFFE65100),
    _       => const Color(0xFF1F8A62),
  };

  Future<void> _pickFoto() async {
    if (_fotos.length >= 2) return;
    final img = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 40, maxWidth: 400, maxHeight: 400);
    if (img != null) setState(() => _fotos.add(img));
  }

  Future<void> _tomarFoto() async {
    if (_fotos.length >= 2) return;
    final img = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 40, maxWidth: 400, maxHeight: 400);
    if (img != null) setState(() => _fotos.add(img));
  }

  bool _publicando = false;
  double? _latitud;
  double? _longitud;

  Future<void> _obtenerUbicacionGPS() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activa el GPS en tu dispositivo')));
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permiso de ubicación bloqueado. Habilítalo en Ajustes.')));
      return;
    }
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
    setState(() {
      _latitud  = pos.latitude;
      _longitud = pos.longitude;
      _lugarCtl.text = 'Medellín';
    });
  }

  Future<void> _publicar() async {
    if (_fotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes agregar al menos una foto del animal')));
      return;
    }
    if (_latitud == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor detecta tu ubicación GPS')));
      return;
    }
    setState(() => _publicando = true);
    try {
      String? fotoBase64;
      if (_fotos.isNotEmpty) {
        final bytes = await File(_fotos[0].path).readAsBytes();
        fotoBase64 = base64Encode(bytes);
      }

      await FirebaseFirestore.instance.collection('rescates').add({
        'nombre':           _nombreCtl.text.trim(),
        'especie':          _especie,
        'raza':             _tipoRaza == 'Criolla' ? 'Criolla' : _razaCtl.text.trim().isEmpty ? 'Raza definida' : _razaCtl.text.trim(),
        'estado':           _estado,
        'urgencia':         _urgencia,
        'ubicacion':        _lugarCtl.text.trim(),
        'descripcion':      _descCtl.text.trim(),
        'estadoAdopcion':   'Rescatado',
        'cantidadFotos':    _fotos.length,
        if (fotoBase64 != null) 'fotoBase64': fotoBase64,
        'rescatistaId':        FirebaseAuth.instance.currentUser?.uid ?? '',
        'rescatistaNombre':    FirebaseAuth.instance.currentUser?.displayName ?? 'Rescatista',
        if (_latitud  != null) 'latitud':  _latitud,
        if (_longitud != null) 'longitud': _longitud,
        // etiquetas de compatibilidad
        'edad':             _edad,
        'genero':           _genero,
        'energia':          _energia,
        'tamano':           _tamano,
        'okConNinos':       _okNinos == 'Sí',
        'okConMascotas':    _okMascotas == 'Sí',
        'requiereExperiencia': _requiereExp == 'Sí',
        'creadoEn':         FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('¡Rescate publicado! 🐾'),
          content: Text('${_nombreCtl.text.isEmpty ? "El animal" : _nombreCtl.text} '
              'fue publicado con urgencia $_urgencia en ${_lugarCtl.text}.'),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(context); Navigator.pop(context); },
              child: const Text('Ver rescates', style: TextStyle(color: _teal)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al publicar: $e')));
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  @override
  void dispose() {
    _nombreCtl.dispose();
    _lugarCtl.dispose();
    _descCtl.dispose();
    _razaCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
          child: Column(children: [
            _appBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 8),
                  _section('Fotos del animal'),
                  const SizedBox(height: 10),
                  _fotoGrid(),
                  const SizedBox(height: 20),
                  _field('Nombre del animal (opcional)', _nombreCtl, hint: 'ej. Luna, sin nombre...'),
                  const SizedBox(height: 16),
                  _section('Raza'),
                  const SizedBox(height: 8),
                  _chips(_tipoRazaOpts, _tipoRaza,
                      (v) => setState(() { _tipoRaza = v; _razaCtl.clear(); }), _teal),
                  if (_tipoRaza == 'Raza definida') ...[
                    const SizedBox(height: 10),
                    _field('¿Cuál raza?', _razaCtl, hint: 'ej. Golden Retriever, Siamés...'),
                  ],
                  const SizedBox(height: 16),
                  _section('Especie'),
                  const SizedBox(height: 8),
                  _chips(_especies, _especie, (v) => setState(() => _especie = v), _teal),
                  const SizedBox(height: 20),
                  _section('Edad aproximada'),
                  const SizedBox(height: 8),
                  _chips(_edades, _edad, (v) => setState(() => _edad = v), _teal),
                  const SizedBox(height: 20),
                  _section('Género'),
                  const SizedBox(height: 8),
                  _chips(_generos, _genero, (v) => setState(() => _genero = v), _teal),
                  const SizedBox(height: 20),
                  _section('Estado de salud'),
                  const SizedBox(height: 8),
                  _chips(_estados, _estado, (v) => setState(() => _estado = v), _teal),
                  const SizedBox(height: 20),
                  _section('Urgencia'),
                  const SizedBox(height: 8),
                  _chips(_urgencias, _urgencia,
                    (v) => setState(() => _urgencia = v), _urgenciaColor(_urgencia)),
                  const SizedBox(height: 28),
                  _sectionLabel('Compatibilidad para adopción'),
                  const SizedBox(height: 4),
                  Text('Estas etiquetas ayudan a encontrar el hogar ideal',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  const SizedBox(height: 16),
                  _section('Nivel de energía'),
                  const SizedBox(height: 8),
                  _chips(_energias, _energia,
                      (v) => setState(() => _energia = v), const Color(0xFF7C4DFF)),
                  const SizedBox(height: 20),
                  _section('Tamaño'),
                  const SizedBox(height: 8),
                  _chips(_tamanos, _tamano,
                      (v) => setState(() => _tamano = v), _teal),
                  const SizedBox(height: 20),
                  _section('¿Es bueno con niños?'),
                  const SizedBox(height: 8),
                  _chips(_siNoOpts, _okNinos,
                      (v) => setState(() => _okNinos = v), _teal),
                  const SizedBox(height: 20),
                  _section('¿Es bueno con otras mascotas?'),
                  const SizedBox(height: 8),
                  _chips(_siNoOpts, _okMascotas,
                      (v) => setState(() => _okMascotas = v), _teal),
                  const SizedBox(height: 20),
                  _section('¿Requiere adoptante con experiencia?'),
                  const SizedBox(height: 8),
                  _chips(_siNoOpts, _requiereExp,
                      (v) => setState(() => _requiereExp = v), _orange),
                  const SizedBox(height: 28),
                  _section('Ubicación'),
                  const SizedBox(height: 8),
                  _locationField(),
                  const SizedBox(height: 20),
                  _field('Descripción adicional', _descCtl,
                      hint: 'Estado del animal, dónde fue encontrado, necesidades especiales...',
                      maxLines: 4),
                  const SizedBox(height: 28),
                  _publishBtn(),
                  const SizedBox(height: 40),
                ]),
              ),
            ),
          ]),
      ),
    );
  }

  Widget _appBar(BuildContext ctx) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
    child: Row(children: [
      IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        onPressed: () => Navigator.pop(ctx),
      ),
      const Expanded(
        child: Text('Subir un rescate',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
      ),
    ]),
  );

  Widget _section(String t) => Text(t,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF222222)));

  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF7C4DFF)));

  Widget _fotoGrid() {
    final items = List<Widget>.from(_fotos.map((f) => _fotoThumb(f)));
    if (_fotos.length < 2) {
      items.add(_fotoAddBtn());
    }
    return Wrap(spacing: 10, runSpacing: 10, children: items);
  }

  Widget _fotoThumb(XFile f) => Stack(children: [
    ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(File(f.path), width: 90, height: 90, fit: BoxFit.cover),
    ),
    Positioned(top: 4, right: 4,
      child: GestureDetector(
        onTap: () => setState(() => _fotos.remove(f)),
        child: Container(
          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
          padding: const EdgeInsets.all(3),
          child: const Icon(Icons.close, size: 14, color: Colors.white),
        ),
      )),
  ]);

  Widget _fotoAddBtn() => GestureDetector(
    onTap: _mostrarOpcionesFoto,
    child: Container(
      width: 90, height: 90,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _teal.withOpacity(0.4), width: 1.5),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.add_a_photo_outlined, color: _teal, size: 28),
        const SizedBox(height: 4),
        Text('${_fotos.length}/2', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ]),
    ),
  );

  void _mostrarOpcionesFoto() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(leading: const Icon(Icons.camera_alt, color: _teal), title: const Text('Tomar foto'),
            onTap: () { Navigator.pop(context); _tomarFoto(); }),
          ListTile(leading: const Icon(Icons.photo_library, color: _teal), title: const Text('Elegir de la galería'),
            onTap: () { Navigator.pop(context); _pickFoto(); }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _chips(List<String> options, String selected, ValueChanged<String> onSelect, Color activeColor) =>
      Wrap(spacing: 8, runSpacing: 8, children: options.map((o) {
        final sel = o == selected;
        return GestureDetector(
          onTap: () => onSelect(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? activeColor : Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? activeColor : Colors.grey.shade300),
            ),
            child: Text(o, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: sel ? Colors.white : Colors.grey.shade700)),
          ),
        );
      }).toList());

  Widget _field(String label, TextEditingController ctl, {String hint = '', int maxLines = 1}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _section(label),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.88), borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
          child: TextField(
            controller: ctl, maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ]);

  Widget _locationField() {
    final obtenida = _latitud != null;
    return GestureDetector(
      onTap: _obtenerUbicacionGPS,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: obtenida ? _teal.withOpacity(0.08) : Colors.white.withOpacity(0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: obtenida ? _teal : Colors.grey.shade300),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Row(children: [
          Icon(obtenida ? Icons.check_circle : Icons.my_location,
              color: obtenida ? _teal : Colors.grey.shade500, size: 22),
          const SizedBox(width: 12),
          Text(
            obtenida ? 'Ubicación detectada ✓' : 'Toca para detectar tu ubicación',
            style: TextStyle(
              fontSize: 14,
              color: obtenida ? _teal : Colors.grey.shade500,
              fontWeight: obtenida ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _publishBtn() => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: _publicando ? null : _publicar,
      style: ElevatedButton.styleFrom(
        backgroundColor: _dark, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      child: _publicando
          ? const SizedBox(height: 20, width: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Text('Publicar rescate 🐾', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    ),
  );
}

// ─── Todos los Rescates ───────────────────────────────────────────────────────

class TodosLosRescatesScreen extends StatefulWidget {
  const TodosLosRescatesScreen({super.key});
  @override
  State<TodosLosRescatesScreen> createState() => _TodosLosRescatesScreenState();
}

class _TodosLosRescatesScreenState extends State<TodosLosRescatesScreen> {
  String? _filtroEstado; // null = Todos

  static const _estadosFiltro = [
    'Rescatado',
    'Hogar de paso',
    'En proceso de adopción',
    'Adoptado',
    'Regresado',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: _bg)),
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text('Mis rescates',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                  ),
                ]),
              ),
              // Chips de filtro
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _chip('Todos', null),
                    ..._estadosFiltro.map((e) => _chip(e, e)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('rescates')
                      .where('rescatistaId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: _teal));
                    }
                    var allDocs = [...(snap.data?.docs ?? [])]..sort((a, b) {
                      final ta = (a.data() as Map)['creadoEn'] as Timestamp?;
                      final tb = (b.data() as Map)['creadoEn'] as Timestamp?;
                      if (ta == null || tb == null) return 0;
                      return tb.compareTo(ta);
                    });
                    if (_filtroEstado != null) {
                      allDocs = allDocs.where((doc) {
                        final ea = (doc.data() as Map<String, dynamic>)['estadoAdopcion'] as String? ?? 'Rescatado';
                        return ea == _filtroEstado;
                      }).toList();
                    }
                    if (allDocs.isEmpty) {
                      return Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('🐾', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          Text(
                            _filtroEstado == null
                                ? 'Aún no has publicado rescates'
                                : 'No hay animales en estado "$_filtroEstado"',
                            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                        ]),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: allDocs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final d = allDocs[i].data() as Map<String, dynamic>;
                        final docId         = allDocs[i].id;
                        final nombre        = (d['nombre'] as String?)?.isNotEmpty == true ? d['nombre'] : 'Sin nombre';
                        final especie       = d['especie']       ?? '';
                        final estado        = d['estado']        ?? '';
                        final urgencia      = d['urgencia']      ?? '';
                        final ubicacion     = d['ubicacion']     ?? '';
                        final fotoBase64    = d['fotoBase64']    as String?;
                        final estadoAdopcion= d['estadoAdopcion'] as String? ?? 'Rescatado';
                        final emoji = especie == 'Gato' ? '🐱' : '🐶';
                        final urgColor = urgencia == 'Alta'
                            ? const Color(0xFFD32F2F)
                            : urgencia == 'Media' ? const Color(0xFFE65100) : _teal;

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: fotoBase64 != null
                                  ? Image.memory(base64Decode(fotoBase64),
                                      width: 64, height: 64, fit: BoxFit.cover)
                                  : Container(width: 64, height: 64,
                                      color: const Color(0xFFD8F0E4),
                                      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 32)))),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text('$especie · $estado', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                                const SizedBox(height: 4),
                                Row(children: [
                                  const Icon(Icons.location_on, size: 13, color: _teal),
                                  const SizedBox(width: 2),
                                  Text(ubicacion, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                ]),
                              ])),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: urgColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                                child: Text(urgencia, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: urgColor)),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            Row(children: [
                              GestureDetector(
                                onTap: () => showModalBottomSheet(
                                  context: context,
                                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                  builder: (_) => _CambiarEstadoSheet(docId: docId, estadoActual: estadoAdopcion),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _cicloColor(estadoAdopcion).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: _cicloColor(estadoAdopcion).withOpacity(0.3)),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(estadoAdopcion, style: TextStyle(fontSize: 12,
                                        fontWeight: FontWeight.w700, color: _cicloColor(estadoAdopcion))),
                                    const SizedBox(width: 4),
                                    Icon(Icons.expand_more, size: 14, color: _cicloColor(estadoAdopcion)),
                                  ]),
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => EditarRescateScreen(docId: docId, data: d))),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.edit_outlined, size: 13, color: Colors.grey.shade600),
                                    const SizedBox(width: 4),
                                    Text('Editar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                                  ]),
                                ),
                              ),
                            ]),
                          ]),
                        );
                      },
                    );
                  },
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String? valor) {
    final activo = _filtroEstado == valor;
    final color  = valor == null ? _teal : _cicloColor(valor);
    return GestureDetector(
      onTap: () => setState(() => _filtroEstado = valor),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: activo ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: activo ? color : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: activo ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}

// ─── Editar Rescate Screen ────────────────────────────────────────────────────

class EditarRescateScreen extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  const EditarRescateScreen({super.key, required this.docId, required this.data});
  @override
  State<EditarRescateScreen> createState() => _EditarRescateScreenState();
}

class _EditarRescateScreenState extends State<EditarRescateScreen> {
  late TextEditingController _nombreCtl;
  late TextEditingController _descCtl;
  late TextEditingController _lugarCtl;
  late String _especie;
  late String _estado;
  late String _urgencia;
  late String _energia;
  late String _tamano;
  late String _edad;
  late String _genero;
  late String _okNinos;
  late String _okMascotas;
  late String _requiereExp;
  bool _guardando = false;
  String? _fotoBase64Existente;
  XFile? _nuevaFoto;
  final _picker = ImagePicker();

  static const _especies  = ['Perro', 'Gato', 'Otro'];
  static const _estados   = ['Sano', 'En tratamiento', 'Recuperado'];
  static const _urgencias = ['Alta', 'Media', 'Baja'];
  static const _energias  = ['Tranquilo', 'Activo', 'Muy activo'];
  static const _tamanos   = ['Pequeño', 'Mediano', 'Grande'];
  static const _edades    = ['Cachorro', 'Adulto', 'Senior'];
  static const _generos   = ['Macho', 'Hembra', 'No sé'];
  static const _siNo      = ['Sí', 'No'];

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _nombreCtl = TextEditingController(text: d['nombre'] ?? '');
    _descCtl   = TextEditingController(text: d['descripcion'] ?? '');
    _lugarCtl  = TextEditingController(text: d['ubicacion'] ?? '');
    _especie   = d['especie']   ?? 'Perro';
    _estado    = d['estado']    ?? 'Sano';
    _urgencia  = d['urgencia']  ?? 'Media';
    _energia   = d['energia']   ?? 'Tranquilo';
    _tamano    = d['tamano']    ?? 'Mediano';
    _edad      = d['edad']      ?? 'Cachorro';
    _genero    = d['genero']    ?? 'No sé';
    _okNinos   = (d['okConNinos']    as bool? ?? false) ? 'Sí' : 'No';
    _okMascotas= (d['okConMascotas'] as bool? ?? false) ? 'Sí' : 'No';
    _requiereExp=(d['requiereExperiencia'] as bool? ?? false) ? 'Sí' : 'No';
    _fotoBase64Existente = d['fotoBase64'] as String?;
  }

  @override
  void dispose() {
    _nombreCtl.dispose(); _descCtl.dispose(); _lugarCtl.dispose();
    super.dispose();
  }

  Future<void> _pickFoto(ImageSource src) async {
    final img = await _picker.pickImage(source: src, imageQuality: 40, maxWidth: 400, maxHeight: 400);
    if (img != null) setState(() => _nuevaFoto = img);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    String? fotoBase64;
    if (_nuevaFoto != null) {
      final bytes = await File(_nuevaFoto!.path).readAsBytes();
      fotoBase64 = base64Encode(bytes);
    }
    await FirebaseFirestore.instance.collection('rescates').doc(widget.docId).update({
      'nombre':      _nombreCtl.text.trim(),
      'descripcion': _descCtl.text.trim(),
      'ubicacion':   _lugarCtl.text.trim(),
      'especie':     _especie,
      'estado':      _estado,
      'urgencia':    _urgencia,
      'energia':     _energia,
      'tamano':      _tamano,
      'edad':        _edad,
      'genero':      _genero,
      'okConNinos':        _okNinos    == 'Sí',
      'okConMascotas':     _okMascotas == 'Sí',
      'requiereExperiencia': _requiereExp == 'Sí',
      if (fotoBase64 != null) 'fotoBase64': fotoBase64,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('¡Cambios guardados!'), backgroundColor: _teal));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 20, 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(child: Text('Editar animal',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)))),
              if (_guardando)
                const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: _teal, strokeWidth: 2))
              else
                TextButton(
                  onPressed: _guardar,
                  child: const Text('Guardar', style: TextStyle(color: _teal, fontWeight: FontWeight.w700, fontSize: 15)),
                ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _seccion('FOTO'),
                const SizedBox(height: 10),
                _fotoSection(),
                const SizedBox(height: 20),
                _campo('Nombre', _nombreCtl, 'ej. Luna'),
                const SizedBox(height: 16),
                _campo('Ubicación', _lugarCtl, 'ej. Laureles'),
                const SizedBox(height: 16),
                _campo('Descripción', _descCtl, 'Cuéntanos sobre el animal...', maxLines: 3),
                const SizedBox(height: 20),
                _seccion('INFORMACIÓN'),
                const SizedBox(height: 12),
                _selector('Especie', _especie, _especies, (v) => setState(() => _especie = v)),
                const SizedBox(height: 12),
                _selector('Estado de salud', _estado, _estados, (v) => setState(() => _estado = v)),
                const SizedBox(height: 12),
                _selector('Urgencia', _urgencia, _urgencias, (v) => setState(() => _urgencia = v)),
                const SizedBox(height: 20),
                _seccion('COMPATIBILIDAD'),
                const SizedBox(height: 12),
                _selector('Energía', _energia, _energias, (v) => setState(() => _energia = v)),
                const SizedBox(height: 12),
                _selector('Tamaño', _tamano, _tamanos, (v) => setState(() => _tamano = v)),
                const SizedBox(height: 12),
                _selector('Edad', _edad, _edades, (v) => setState(() => _edad = v)),
                const SizedBox(height: 12),
                _selector('Género', _genero, _generos, (v) => setState(() => _genero = v)),
                const SizedBox(height: 12),
                _selector('¿Ok con niños?', _okNinos, _siNo, (v) => setState(() => _okNinos = v)),
                const SizedBox(height: 12),
                _selector('¿Ok con otras mascotas?', _okMascotas, _siNo, (v) => setState(() => _okMascotas = v)),
                const SizedBox(height: 12),
                _selector('¿Requiere experiencia?', _requiereExp, _siNo, (v) => setState(() => _requiereExp = v)),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _seccion(String t) => Text(t,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.grey.shade500));

  Widget _fotoSection() {
    final bool tieneNueva = _nuevaFoto != null;
    final bool tieneExistente = _fotoBase64Existente != null && !tieneNueva;
    final bool tieneFoto = tieneNueva || tieneExistente;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Vista previa grande
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: double.infinity, height: 180,
          child: tieneFoto
            ? Stack(fit: StackFit.expand, children: [
                tieneNueva
                  ? Image.file(File(_nuevaFoto!.path), fit: BoxFit.cover)
                  : Image.memory(base64Decode(_fotoBase64Existente!), fit: BoxFit.cover),
                Positioned(bottom: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Foto actual',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  )),
              ])
            : GestureDetector(
                onTap: () => _pickFoto(ImageSource.gallery),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8F0E4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _teal.withOpacity(0.4), width: 2,
                        style: BorderStyle.solid),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_a_photo_outlined, size: 44, color: _teal),
                    const SizedBox(height: 8),
                    const Text('Toca para agregar foto',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _teal)),
                    const SizedBox(height: 4),
                    Text('Requerida para publicar',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ]),
                ),
              ),
        ),
      ),
      const SizedBox(height: 10),
      // Botones cambiar foto
      Row(children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _pickFoto(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 16),
            label: const Text('Galería'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _pickFoto(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined, size: 16),
            label: const Text('Cámara'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: _teal,
              side: const BorderSide(color: _teal),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _campo(String label, TextEditingController ctl, String hint, {int maxLines = 1}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 6),
      TextField(
        controller: ctl,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    ]);

  Widget _selector(String label, String valor, List<String> opts, ValueChanged<String> onChanged) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: opts.map((o) {
        final sel = o == valor;
        return GestureDetector(
          onTap: () => onChanged(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? _teal : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? _teal : Colors.grey.shade300),
            ),
            child: Text(o, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: sel ? Colors.white : Colors.grey.shade600)),
          ),
        );
      }).toList()),
    ]);
}

// ─── Helpers globales ─────────────────────────────────────────────────────────

Color _cicloColor(String s) => switch (s) {
  'Rescatado'              => _teal,
  'Hogar de paso'          => const Color(0xFF7C6FCD),
  'En proceso de adopción' => const Color(0xFFE65100),
  'Adoptado'               => const Color(0xFF2196F3),
  'Regresado'              => const Color(0xFFD32F2F),
  _                        => Colors.grey,
};

int calcularCompatibilidad(Map<String, dynamic> solicitud) {
  int score = 0;

  final energia    = solicitud['animalEnergia']  as String? ?? 'Tranquilo';
  final horas      = int.tryParse(solicitud['horasFuera']?.toString() ?? '0') ?? 0;
  final vivienda   = solicitud['vivienda']       as String? ?? '';
  final tienePatio = vivienda == 'Casa con jardín';

  if (energia == 'Tranquilo') {
    score += 20;
  } else if (energia == 'Activo') {
    score += horas <= 8 ? 20 : 10;
  } else {
    if (tienePatio && horas <= 6) score += 20;
    else if (tienePatio || horas <= 6) score += 10;
  }

  final tamano = solicitud['animalTamano'] as String? ?? 'Mediano';
  if (tamano == 'Pequeño') {
    score += 20;
  } else if (tamano == 'Mediano') {
    score += vivienda != 'Apartamento sin área exterior' ? 20 : 10;
  } else {
    score += tienePatio ? 20 : (vivienda == 'Apartamento con balcón' ? 10 : 0);
  }

  final okNinos    = solicitud['animalOkConNinos']   as bool? ?? true;
  final tieneNinos = solicitud['tieneNinos']         as bool? ?? false;
  score += (!tieneNinos || okNinos) ? 20 : 0;

  final okMascotas    = solicitud['animalOkConMascotas'] as bool? ?? true;
  final tieneMascotas = solicitud['tieneMascotas']       as bool? ?? false;
  score += (!tieneMascotas || okMascotas) ? 20 : 0;

  final requiereExp = solicitud['animalRequiereExp']   as bool? ?? false;
  final tieneExp    = solicitud['experienciaPrevia']   as bool? ?? false;
  score += (!requiereExp || tieneExp) ? 20 : 0;

  return score;
}

// ─── Solicitudes Rescatista Screen ───────────────────────────────────────────

class SolicitudesRescatistaScreen extends StatefulWidget {
  const SolicitudesRescatistaScreen({super.key});
  @override
  State<SolicitudesRescatistaScreen> createState() => _SolicitudesRescatistaScreenState();
}

class _SolicitudesRescatistaScreenState extends State<SolicitudesRescatistaScreen> {
  String _filtro = 'pendiente';

  static const _filtros = [
    ('pendiente',  'Pendientes'),
    ('aprobada',   'Aprobadas'),
    ('rechazada',  'Rechazadas'),
  ];

  String _tiempoRelativo(DateTime fecha) {
    final diff = DateTime.now().difference(fecha);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    if (diff.inHours < 24)   return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 20, 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(child: Text('Solicitudes de adopción',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)))),
            ]),
          ),
          // Filtros
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: _filtros.map((f) {
              final activo = _filtro == f.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _filtro = f.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: activo ? _teal : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: activo ? _teal : Colors.grey.shade300),
                    ),
                    child: Text(f.$2, style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: activo ? Colors.white : Colors.grey.shade600,
                    )),
                  ),
                ),
              );
            }).toList()),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('solicitudes')
                  .where('rescatistaId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                  .where('estado', isEqualTo: _filtro)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: _teal));
                }
                final docs = [...(snap.data?.docs ?? [])]..sort((a, b) {
                    final ta = (a.data() as Map)['creadoEn'] as Timestamp?;
                    final tb = (b.data() as Map)['creadoEn'] as Timestamp?;
                    if (ta == null || tb == null) return 0;
                    return tb.compareTo(ta);
                  });
                if (docs.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No hay solicitudes ${_filtro == 'pendiente' ? 'pendientes' : _filtro == 'aprobada' ? 'aprobadas' : 'rechazadas'}',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 15, fontWeight: FontWeight.w600)),
                    ]),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final d           = docs[i].data() as Map<String, dynamic>;
                    final animal      = d['animalNombre'] as String? ?? 'Animal';
                    final nombre      = d['nombre']      as String? ?? 'Adoptante';
                    final integrantes = d['integrantes'] as String? ?? '';
                    final vivienda    = d['vivienda']    as String? ?? '';
                    final mascotas    = (d['tieneMascotas'] as bool? ?? false) ? 'con mascotas' : 'sin mascotas';
                    final ninos       = (d['tieneNinos']    as bool? ?? false) ? 'con niños' : 'sin niños';
                    final exp         = (d['experienciaPrevia'] as bool? ?? false) ? 'con experiencia' : 'sin experiencia';
                    final horas       = d['horasFuera'] as String? ?? '';
                    final ts          = d['creadoEn'] as Timestamp?;
                    final tiempo      = ts != null ? _tiempoRelativo(ts.toDate()) : '';
                    final ini         = nombre.isNotEmpty ? nombre[0].toUpperCase() : 'A';
                    final col         = i.isEven ? _teal : _orange;
                    final score       = calcularCompatibilidad(d);
                    final scoreColor  = score >= 80 ? const Color(0xFF1F8A62) : score >= 60 ? const Color(0xFFE65100) : const Color(0xFFB71C1C);
                    final detalle     = [
                      vivienda, if (integrantes.isNotEmpty) '$integrantes personas',
                      ninos, mascotas, exp,
                      if (horas.isNotEmpty) '$horas h fuera/día',
                    ].join(' · ');

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          CircleAvatar(backgroundColor: col, radius: 20,
                              child: Text(ini, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(detalle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), maxLines: 2),
                          ])),
                          Text(tiempo, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                        ]),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: const Color(0xFFD8F0E4), borderRadius: BorderRadius.circular(12)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 32, height: 32,
                              decoration: BoxDecoration(color: Colors.brown.shade300, borderRadius: BorderRadius.circular(6)),
                              child: const Icon(Icons.pets, size: 18, color: Colors.white)),
                            const SizedBox(width: 8),
                            Text('Para $animal', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: scoreColor.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scoreColor.withOpacity(0.35)),
                          ),
                          child: Row(children: [
                            Text(score >= 80 ? '✅' : score >= 60 ? '⚠️' : '❌',
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                score >= 80 ? 'Perfil ideal ($score%)'
                                    : score >= 60 ? 'Perfil aceptable ($score%)'
                                    : 'No recomendado ($score%)',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scoreColor),
                              ),
                            ])),
                          ]),
                        ),
                        if (_filtro == 'rechazada' && d['motivoRechazo'] != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Motivo del rechazo',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red.shade400)),
                              const SizedBox(height: 4),
                              Text(d['motivoRechazo'], style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                            ]),
                          ),
                        ],
                        if (_filtro == 'pendiente') ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => FirebaseFirestore.instance
                                    .collection('solicitudes').doc(docs[i].id)
                                    .update({'estado': 'aprobada'}),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(10)),
                                  child: const Text('Aprobar', textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  final motivoCtl = TextEditingController();
                                  showDialog(context: context, builder: (dlg) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Text('¿Por qué rechazas?'),
                                    content: TextField(
                                      controller: motivoCtl,
                                      maxLines: 3,
                                      decoration: InputDecoration(
                                        hintText: 'ej. El espacio no es suficiente...',
                                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(dlg), child: const Text('Cancelar')),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(dlg);
                                          FirebaseFirestore.instance.collection('solicitudes').doc(docs[i].id).update({
                                            'estado': 'rechazada',
                                            'motivoRechazo': motivoCtl.text.trim().isEmpty
                                                ? 'Sin motivo especificado'
                                                : motivoCtl.text.trim(),
                                          });
                                        },
                                        child: const Text('Confirmar', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ));
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.red.shade300),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('Rechazar', textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                            ),
                          ]),
                        ],
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Perfil Rescatista Screen ─────────────────────────────────────────────────

class PerfilRescatistaScreen extends StatelessWidget {
  const PerfilRescatistaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final nombre = user?.displayName ?? 'Rescatista';
    final foto   = user?.photoURL;
    final email  = user?.email ?? '';

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: LeafPainter()),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
              ]),
              const SizedBox(height: 8),
              foto != null
                ? CircleAvatar(backgroundImage: NetworkImage(foto), radius: 44)
                : CircleAvatar(backgroundColor: _teal, radius: 44,
                    child: Text(nombre[0].toUpperCase(),
                        style: const TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.bold))),
              const SizedBox(height: 14),
              Text(nombre, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
              const SizedBox(height: 4),
              Text(email, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: const Text('Rescatista 🦺', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _teal)),
              ),
              const SizedBox(height: 32),
              // Stats
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('rescates')
                    .where('rescatistaId', isEqualTo: user?.uid ?? '').snapshots(),
                builder: (context, snap) {
                  final total = snap.data?.docs.length ?? 0;
                  return Row(children: [
                    _statTile('$total', 'Animales\nrescatados', _teal),
                    const SizedBox(width: 12),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('solicitudes')
                          .where('rescatistaId', isEqualTo: user?.uid ?? '')
                          .where('estado', isEqualTo: 'aprobada').snapshots(),
                      builder: (context, snap2) {
                        final aprobadas = snap2.data?.docs.length ?? 0;
                        return _statTile('$aprobadas', 'Adopciones\naprobadas', _orange);
                      },
                    ),
                  ]);
                },
              ),
              const SizedBox(height: 32),
              // Cerrar sesión
              GestureDetector(
                onTap: () => showDialog(context: context, builder: (dlgCtx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Cerrar sesión'),
                  content: const Text('¿Seguro que quieres cerrar sesión?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancelar')),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(dlgCtx);
                        await GoogleSignIn().signOut();
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        }
                      },
                      child: const Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                )),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.logout, color: Colors.red.shade400, size: 18),
                    const SizedBox(width: 8),
                    Text('Cerrar sesión', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _statTile(String n, String lbl, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
      child: Column(children: [
        Text(n, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(lbl, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.3), textAlign: TextAlign.center),
      ]),
    ),
  );
}

// ─── Adoptante Card Stack ─────────────────────────────────────────────────────

class _AdoptanteCardStack extends StatefulWidget {
  const _AdoptanteCardStack();
  @override
  State<_AdoptanteCardStack> createState() => _AdoptanteCardStackState();
}

class _AdoptanteCardStackState extends State<_AdoptanteCardStack> {
  int _idx = 0;
  Position? _userPosition;
  Map<String, dynamic>? _perfilAdopcion;

  @override
  void initState() {
    super.initState();
    _obtenerPosicion();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    if (doc.exists && mounted) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['perfilAdopcion'] != null) {
        setState(() => _perfilAdopcion = Map<String, dynamic>.from(data['perfilAdopcion']));
      }
    }
  }

  int _calcularScore(Map<String, dynamic> animal) {
    if (_perfilAdopcion == null) return -1;
    return calcularCompatibilidad({
      ...animal,
      'animalEnergia':       animal['energia'],
      'animalTamano':        animal['tamano'],
      'animalOkConNinos':    animal['okConNinos'],
      'animalOkConMascotas': animal['okConMascotas'],
      'animalRequiereExp':   animal['requiereExperiencia'],
      ..._perfilAdopcion!,
    });
  }

  Future<void> _obtenerPosicion() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      if (!serviceEnabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return;
      }
      if (perm == LocationPermission.deniedForever) return;
      // Intenta posición conocida primero (más rápido)
      Position? pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        setState(() => _userPosition = pos);
      }
      // Luego actualiza con posición actual
      pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 10),
          ));
      if (mounted) setState(() => _userPosition = pos);
    } catch (_) {}
  }

  String _distancia(Map<String, dynamic> animal) {
    final lat = animal['latitud']  as double?;
    final lng = animal['longitud'] as double?;
    if (lat == null || lng == null || _userPosition == null) return '';
    final metros = Geolocator.distanceBetween(
        _userPosition!.latitude, _userPosition!.longitude, lat, lng);
    if (metros < 1000) return '${metros.round()} m';
    return '${(metros / 1000).toStringAsFixed(1)} km';
  }


  Future<void> _guardarFavorito(Map<String, dynamic> animal) async {
    final uid    = FirebaseAuth.instance.currentUser?.uid ?? '';
    final nombre = (animal['nombre'] as String).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final docId  = '${uid}_$nombre';
    await FirebaseFirestore.instance.collection('favoritos').doc(docId).set({
      'adoptanteId':  uid,
      'animalNombre': animal['nombre'],
      'especie':      animal['especie'],
      'edad':         animal['edad'],
      'ubicacion':    animal['ubicacion'],
      'descripcion':  animal['descripcion'],
      'tags':         animal['tags'],
      'rescatista':   animal['rescatista'],
      'rescatistaId': animal['rescatistaId'] ?? '',
      'genero':       animal['genero'] ?? '',
      'fotoBase64':   animal['fotoBase64'],
      'verificado':   animal['verificado'] ?? false,
      'creadoEn':     FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rescates')
          .orderBy('creadoEn', descending: true)
          .snapshots(),
      builder: (context, snap) {
        final firestoreDocs = (snap.data?.docs ?? []).where((doc) {
          final estado = (doc.data() as Map<String, dynamic>)['estadoAdopcion'] as String?;
          return estado == null || estado == 'Rescatado' || estado == 'Regresado';
        }).toList();
        final animals = <Map<String, dynamic>>[
          ...firestoreDocs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return {
              'nombre':              (d['nombre'] as String?)?.isNotEmpty == true ? d['nombre'] : 'Sin nombre',
              'edad':                d['edad']       ?? '',
              'genero':              d['genero']     ?? '',
              'especie':             d['especie']    ?? 'Perro',
              'raza':                d['raza']       ?? 'Criolla',
              'tamano':              d['tamano']     ?? 'Mediano',
              'ubicacion':           d['ubicacion']  ?? 'Medellín',
              'distancia':           '~',
              'descripcion':         d['descripcion'] ?? '',
              'tags':                <String>[d['estado'] ?? '', d['urgencia'] ?? '']
                                      .where((s) => s.isNotEmpty).toList(),
              'rescatista':          d['rescatistaNombre'] ?? 'Rescatista',
              'rescatistaId':        d['rescatistaId'] ?? '',
              'fotoBase64':          d['fotoBase64'],
              'latitud':             d['latitud'],
              'longitud':            d['longitud'],
              'energia':             d['energia'],
              'okConNinos':          d['okConNinos'],
              'okConMascotas':       d['okConMascotas'],
              'requiereExperiencia': d['requiereExperiencia'],
            };
          }),
        ];

        if (_idx >= animals.length) return _emptyState();

        final animal = animals[_idx];

        final distancia = _distancia(animal);
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: SizedBox(
              width: double.infinity,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    distancia.isNotEmpty
                        ? '${(animal['ubicacion'] as String).toUpperCase()} · ${distancia.toUpperCase()}'
                        : (animal['ubicacion'] as String).toUpperCase(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        letterSpacing: 1.2, color: _teal)),
                const Text('Cerca de ti',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A))),
              ]),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.topCenter,
                child: _buildCard(animal, distancia, _calcularScore(animal)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _actionBtn(Icons.close, Colors.grey.shade200, Colors.grey.shade600, 52,
                  () => setState(() => _idx++)),
              const SizedBox(width: 18),
              _actionBtn(Icons.pets, Colors.white, const Color(0xFF1A1A1A), 46, () {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AnimalDetalleScreen(animal: animal)));
              }),
              const SizedBox(width: 18),
              _actionBtn(Icons.favorite, _orange, Colors.white, 62, () async {
                await _guardarFavorito(animal);
                setState(() => _idx++);
              }),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _emptyState() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: SizedBox(
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MEDELLÍN', style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w600, letterSpacing: 1.2, color: _teal)),
            const Text('Cerca de ti',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
          ]),
        ),
      ),
      Expanded(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              color: _orange.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.pets, size: 44, color: _orange),
          ),
          const SizedBox(height: 24),
          const Text('Eso es todo por hoy',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 10),
          Text('Vuelve mañana — nuevos amigos\nllegan cada día.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5)),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => setState(() => _idx = 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
              decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(30)),
              child: const Text('Ver de nuevo',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildCard(Map<String, dynamic> a, String distancia, int score) {
    final fotoBase64  = a['fotoBase64'] as String?;
    final nombre      = a['nombre']     as String;
    final edad        = a['edad']       as String;
    final raza        = a['raza']       as String;
    final tamano      = a['tamano']     as String;
    final descripcion = a['descripcion'] as String;
    final tags        = (a['tags'] as List).cast<String>();
    final rescatista  = a['rescatista'] as String;
    final ubicacion   = a['ubicacion']  as String;
    final verificado  = a['verificado'] as bool? ?? false;
    final emoji       = a['especie'] == 'Gato' ? '🐱' : '🐶';

    Color scoreColor(int s) {
      if (s >= 80) return const Color(0xFF1F8A62);
      if (s >= 60) return const Color(0xFFE65100);
      return const Color(0xFFB71C1C);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.09), blurRadius: 18, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 245,
            child: Stack(fit: StackFit.expand, children: [
              fotoBase64 != null
                ? Image.memory(base64Decode(fotoBase64), fit: BoxFit.cover)
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFF3D7A52), Color(0xFF1F4A30)],
                      ),
                    ),
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 90))),
                  ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.68)],
                      stops: const [0.45, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(top: 12, left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.location_on, size: 12, color: _teal),
                    const SizedBox(width: 3),
                    Text(distancia.isNotEmpty ? '$ubicacion · $distancia' : ubicacion,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                )),
              Positioned(top: 12, right: 12,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (score >= 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: scoreColor(score), borderRadius: BorderRadius.circular(20)),
                      child: Text('$score% compatible',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  if (verificado) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(20)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.verified, size: 12, color: Colors.white),
                        SizedBox(width: 3),
                        Text('Verificado',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                      ]),
                    ),
                  ],
                ])),
              Positioned(bottom: 14, left: 16,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  RichText(text: TextSpan(
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                    children: [
                      TextSpan(text: '$nombre, '),
                      TextSpan(text: edad,
                          style: const TextStyle(color: Color(0xFFB8F0CC), fontWeight: FontWeight.w400)),
                    ],
                  )),
                  Text('$raza · $tamano',
                      style: const TextStyle(fontSize: 13, color: Colors.white70)),
                ])),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (descripcion.isNotEmpty) ...[
                Text('"$descripcion"',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
              ],
              if (tags.isNotEmpty) ...[
                Wrap(spacing: 8, runSpacing: 6, children: tags.map((t) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: _teal.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(20),
                    color: _teal.withOpacity(0.07),
                  ),
                  child: Text(t, style: const TextStyle(fontSize: 12, color: _teal, fontWeight: FontWeight.w500)),
                )).toList()),
                const SizedBox(height: 14),
              ],
              Row(children: [
                _avatar('A', _orange, radius: 16, fontSize: 13),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('A cargo de',
                      style: TextStyle(fontSize: 10, color: Color(0xFFAAAAAA))),
                  Text(rescatista,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _teal)),
                ]),
                const Spacer(),
                const Text('★★★★★', style: TextStyle(fontSize: 14, color: Color(0xFFFFB800))),
              ]),
            ]),
          ),
        ]),
    );
  }

  Widget _actionBtn(IconData icon, Color bg, Color iconColor, double size, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 3))]),
        child: Icon(icon, color: iconColor, size: size * 0.40),
      ),
    );
}

// ─── Animal Detalle Screen ────────────────────────────────────────────────────

class AnimalDetalleScreen extends StatelessWidget {
  final Map<String, dynamic> animal;
  const AnimalDetalleScreen({super.key, required this.animal});

  @override
  Widget build(BuildContext context) {
    final fotoBase64  = animal['fotoBase64'] as String?;
    final nombre      = animal['nombre']      as String;
    final edad        = (animal['edad']   as String?) ?? '';
    final genero      = (animal['genero'] as String?) ?? '';
    final raza        = animal['raza']        as String;
    final ubicacion   = animal['ubicacion']   as String;
    final descripcion = animal['descripcion'] as String;
    final tags        = (animal['tags'] as List).cast<String>();
    final emoji       = animal['especie'] == 'Gato' ? '🐱' : '🐶';

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              _circleBtn(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
              Expanded(child: Text(nombre,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)))),
              _circleBtn(Icons.favorite_border, () {}),
            ]),
          ),
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Photo
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: fotoBase64 != null
                    ? Image.memory(base64Decode(fotoBase64),
                        height: 260, width: double.infinity, fit: BoxFit.cover)
                    : Container(
                        height: 260, width: double.infinity,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF3D7A52), Color(0xFF1F4A30)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 90))),
                      ),
                ),
                const SizedBox(height: 12),
                // Badges
                Row(children: [
                  _pill(Icons.location_on, ubicacion),
                  if (edad.isNotEmpty) ...[const SizedBox(width: 8), _pill(null, edad)],
                ]),
                const SizedBox(height: 16),
                // Name
                Text(nombre,
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF1B3A1F))),
                const SizedBox(height: 4),
                Text([raza, if (genero.isNotEmpty && genero != 'No sé') genero, if (edad.isNotEmpty) edad].join(' · '),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                // Chips
                if (tags.isNotEmpty) Wrap(spacing: 8, runSpacing: 6,
                  children: tags.map((t) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF9DDD5), borderRadius: BorderRadius.circular(20)),
                    child: Text(t,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8B3A1F), fontWeight: FontWeight.w500)),
                  )).toList()),
                const SizedBox(height: 22),
                // Historia
                if (descripcion.isNotEmpty) ...[
                  const Text('MI HISTORIA',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: _teal)),
                  const SizedBox(height: 10),
                  Text('"$descripcion"',
                      style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic,
                          color: Color(0xFF2A2A2A), height: 1.65, fontWeight: FontWeight.w500)),
                ],
                const SizedBox(height: 100),
              ]),
            ),
          ),
          // Bottom buttons
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            color: _bg,
            child: Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ChatScreen(animal: animal))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.grey.shade200)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.chat_bubble_outline, size: 18),
                      SizedBox(width: 8),
                      Text('Mensaje', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => SolicitudAdopcionScreen(animal: animal))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(30)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.favorite, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Solicitar adopción',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 6)]),
      child: Icon(icon, size: 16, color: const Color(0xFF444444)),
    ),
  );

  Widget _pill(IconData? icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 12, color: _teal), const SizedBox(width: 4)],
      Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );
}

// ─── Solicitud Rescatista Screen ──────────────────────────────────────────────

class SolicitudRescatistaScreen extends StatefulWidget {
  const SolicitudRescatistaScreen({super.key});
  @override
  State<SolicitudRescatistaScreen> createState() => _SolicitudRescatistaScreenState();
}

class _SolicitudRescatistaScreenState extends State<SolicitudRescatistaScreen> {
  final _nombreCtl  = TextEditingController();
  final _barrioCtl  = TextEditingController();
  bool? _experiencia;
  int   _paso       = 1;
  bool  _enviando   = false;

  @override
  void dispose() {
    _nombreCtl.dispose();
    _barrioCtl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_nombreCtl.text.trim().isEmpty || _barrioCtl.text.trim().isEmpty || _experiencia == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor completa todos los campos')));
      return;
    }
    setState(() => _enviando = true);
    await FirebaseFirestore.instance.collection('solicitudes_rescatista').add({
      'nombre':      _nombreCtl.text.trim(),
      'barrio':      _barrioCtl.text.trim(),
      'experiencia': _experiencia,
      'estado':      'pendiente',
      'creadoEn':    FieldValue.serverTimestamp(),
    });
    if (mounted) setState(() { _enviando = false; _paso = 2; });
  }

  Widget _campo(String label, TextEditingController ctl, String hint) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RichText(text: TextSpan(
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
        children: [TextSpan(text: label), const TextSpan(text: ' *', style: TextStyle(color: _teal))],
      )),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.88),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
        child: TextField(
          controller: ctl,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: LeafPainter()),
        SafeArea(
          child: _paso == 1 ? _paso1() : _paso2(),
        ),
      ]),
    );
  }

  Widget _paso1() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF1A1A1A)),
      ),
      const SizedBox(height: 24),
      Text('ÚNETE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          letterSpacing: 1.2, color: _teal)),
      const SizedBox(height: 6),
      const Text('Vuélvete rescatista\nverificado', style: TextStyle(fontSize: 28,
          fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 8),
      Text('Completa estos datos y revisaremos tu solicitud en 24-48 horas.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
      const SizedBox(height: 28),
      _campo('Nombre completo', _nombreCtl, 'ej. Ana Restrepo'),
      const SizedBox(height: 20),
      _campo('Barrio en Medellín', _barrioCtl, 'ej. Laureles'),
      const SizedBox(height: 20),
      RichText(text: const TextSpan(
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
        children: [TextSpan(text: '¿Ya tienes experiencia rescatando?'),
          TextSpan(text: ' *', style: TextStyle(color: _teal))],
      )),
      const SizedBox(height: 10),
      Row(children: [
        _chip('Sí', _experiencia == true, () => setState(() => _experiencia = true)),
        const SizedBox(width: 10),
        _chip('No', _experiencia == false, () => setState(() => _experiencia = false)),
      ]),
      const SizedBox(height: 36),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _enviando ? null : _enviar,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A1A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _enviando
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Enviar solicitud', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    ]),
  );

  Widget _chip(String label, bool sel, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: sel ? const Color(0xFF1A1A1A) : Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sel ? const Color(0xFF1A1A1A) : Colors.grey.shade300),
      ),
      child: Text(label, style: TextStyle(
          color: sel ? Colors.white : Colors.grey.shade700,
          fontWeight: FontWeight.w600)),
    ),
  );

  Widget _paso2() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle),
          child: const Icon(Icons.check, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 24),
        const Text('¡Solicitud enviada!', style: TextStyle(fontSize: 24,
            fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 12),
        Text('El equipo de Salva Patitas revisará tu solicitud en 24-48 horas. '
            'Te notificaremos cuando sea aprobada.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            textAlign: TextAlign.center),
        const SizedBox(height: 36),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A1A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Entendido', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    ),
  );
}

// ─── Pantallas de Configuración ───────────────────────────────────────────────

final _prefDoc = FirebaseFirestore.instance.collection('preferencias').doc('adoptante');

class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({super.key});
  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  bool _mensajes = true;
  bool _matches  = true;
  bool _solicitudes = true;
  bool _loading  = true;

  @override
  void initState() {
    super.initState();
    _prefDoc.get().then((doc) {
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
    _prefDoc.set({key: val}, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) => _SettingsPageScaffold(
    title: 'Notificaciones',
    child: _loading
        ? const Center(child: CircularProgressIndicator(color: _teal))
        : Column(children: [
            _SwitchTile(
              icon: Icons.chat_bubble_outline,
              label: 'Nuevos mensajes',
              subtitle: 'Cuando un rescatista te responde en el chat',
              value: _mensajes,
              onChanged: (v) { setState(() => _mensajes = v); _save('notif_mensajes', v); },
            ),
            _SwitchTile(
              icon: Icons.favorite_outline,
              label: 'Animales que encajan contigo',
              subtitle: 'Cuando llega un animal según tus preferencias',
              value: _matches,
              onChanged: (v) { setState(() => _matches = v); _save('notif_matches', v); },
            ),
            _SwitchTile(
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

class UbicacionAlcanceScreen extends StatefulWidget {
  const UbicacionAlcanceScreen({super.key});
  @override
  State<UbicacionAlcanceScreen> createState() => _UbicacionAlcanceScreenState();
}

class _UbicacionAlcanceScreenState extends State<UbicacionAlcanceScreen> {
  String _radio = '10 km';
  final _radios = ['2 km', '5 km', '10 km', '20 km', 'Toda Medellín'];

  @override
  void initState() {
    super.initState();
    _prefDoc.get().then((doc) {
      if (doc.exists && mounted) {
        setState(() => _radio = doc.data()!['radio'] ?? '10 km');
      }
    });
  }

  @override
  Widget build(BuildContext context) => _SettingsPageScaffold(
    title: 'Ubicación y alcance',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Text('Muéstrame animales a menos de:',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: _radios.asMap().entries.map((e) {
            final last = e.key == _radios.length - 1;
            final sel  = e.value == _radio;
            return GestureDetector(
              onTap: () {
                setState(() => _radio = e.value);
                _prefDoc.set({'radio': e.value}, SetOptions(merge: true));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                decoration: BoxDecoration(
                  border: last ? null : Border(bottom: BorderSide(color: Colors.grey.shade100)),
                ),
                child: Row(children: [
                  Expanded(child: Text(e.value,
                      style: TextStyle(fontSize: 15,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                          color: sel ? _teal : const Color(0xFF1A1A1A)))),
                  if (sel) const Icon(Icons.check, color: _teal, size: 20),
                ]),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text('Los animales fuera de este radio no aparecerán en tu feed.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ),
    ]),
  );
}

class TipoAnimalScreen extends StatefulWidget {
  const TipoAnimalScreen({super.key});
  @override
  State<TipoAnimalScreen> createState() => _TipoAnimalScreenState();
}

class _TipoAnimalScreenState extends State<TipoAnimalScreen> {
  String _especie = 'Ambos';
  String _tamano  = 'Cualquiera';
  String _edad    = 'Cualquiera';

  @override
  void initState() {
    super.initState();
    _prefDoc.get().then((doc) {
      if (doc.exists && mounted) {
        final d = doc.data()!;
        setState(() {
          _especie = d['especie'] ?? 'Ambos';
          _tamano  = d['tamano']  ?? 'Cualquiera';
          _edad    = d['edad']    ?? 'Cualquiera';
        });
      }
    });
  }

  void _guardar() {
    _prefDoc.set({'especie': _especie, 'tamano': _tamano, 'edad': _edad}, SetOptions(merge: true));
  }

  Widget _grupo(String label, List<String> opciones, String sel, ValueChanged<String> onChange) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            letterSpacing: 1.1, color: Colors.grey.shade500)),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: opciones.map((o) {
          final active = o == sel;
          return GestureDetector(
            onTap: () { onChange(o); _guardar(); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF1A1A1A) : Colors.white.withOpacity(0.88),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? const Color(0xFF1A1A1A) : Colors.grey.shade300),
              ),
              child: Text(o, style: TextStyle(
                  color: active ? Colors.white : Colors.grey.shade700,
                  fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          );
        }).toList()),
      ),
    ]);

  @override
  Widget build(BuildContext context) => _SettingsPageScaffold(
    title: 'Tipo de animal preferido',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 4),
      _grupo('ESPECIE', ['Perro', 'Gato', 'Ambos'], _especie, (v) => setState(() => _especie = v)),
      const SizedBox(height: 20),
      _grupo('TAMAÑO', ['Pequeño', 'Mediano', 'Grande', 'Cualquiera'], _tamano, (v) => setState(() => _tamano = v)),
      const SizedBox(height: 20),
      _grupo('EDAD', ['Cachorro', 'Adulto', 'Senior', 'Cualquiera'], _edad, (v) => setState(() => _edad = v)),
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text('Te notificaremos cuando llegue un animal que encaje con estas preferencias.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ),
    ]),
  );
}

// Scaffold compartido para pantallas de configuración
class _SettingsPageScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  const _SettingsPageScaffold({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    body: Stack(fit: StackFit.expand, children: [
      CustomPaint(painter: LeafPainter()),
      SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
          ]),
        ),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: child,
        )),
      ])),
    ]),
  );
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final bool last;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({required this.icon, required this.label, required this.subtitle,
      required this.value, required this.onChanged, this.last = false});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.8),
      borderRadius: BorderRadius.only(
        topLeft:     Radius.circular(last ? 0 : 16),
        topRight:    Radius.circular(last ? 0 : 16),
        bottomLeft:  Radius.circular(last ? 16 : 0),
        bottomRight: Radius.circular(last ? 16 : 0),
      ),
      border: last ? null : Border(bottom: BorderSide(color: Colors.grey.shade100)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Icon(icon, size: 22, color: Colors.grey.shade600),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ])),
      Switch(value: value, onChanged: onChanged, activeColor: _teal),
    ]),
  );
}

// ─── Mis Solicitudes Screen ───────────────────────────────────────────────────

class MisSolicitudesScreen extends StatelessWidget {
  const MisSolicitudesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 20, 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(child: Text('Mis solicitudes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)))),
            ]),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('solicitudes')
                  .where('adoptanteId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: _teal));
                }
                final docs = [...(snap.data?.docs ?? [])]..sort((a, b) {
                    final ta = (a.data() as Map)['creadoEn'] as Timestamp?;
                    final tb = (b.data() as Map)['creadoEn'] as Timestamp?;
                    if (ta == null || tb == null) return 0;
                    return tb.compareTo(ta);
                  });
                if (docs.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.pets_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('Aún no has enviado solicitudes',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                      const SizedBox(height: 8),
                      Text('Cuando te interese un animal, toca\n"Quiero adoptarlo"',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                    ]),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final d       = docs[i].data() as Map<String, dynamic>;
                    final animal  = d['animalNombre'] as String? ?? 'Animal';
                    final estado  = d['estado']       as String? ?? 'pendiente';
                    final motivo  = d['motivoRechazo'] as String?;
                    final ts      = d['creadoEn'] as Timestamp?;
                    final tiempo  = ts != null ? _formatFecha(ts.toDate()) : '';

                    final estadoColor = estado == 'aprobada'
                        ? const Color(0xFF1F8A62)
                        : estado == 'rechazada'
                            ? const Color(0xFFB71C1C)
                            : const Color(0xFFE65100);
                    final estadoLabel = estado == 'aprobada' ? '✅ Aprobada'
                        : estado == 'rechazada' ? '❌ Rechazada'
                        : '⏳ Pendiente';

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(width: 40, height: 40,
                            decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.pets, color: _teal, size: 22)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Para $animal',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            Text(tiempo, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: estadoColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: estadoColor.withOpacity(0.4)),
                            ),
                            child: Text(estadoLabel,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: estadoColor)),
                          ),
                        ]),
                        if (estado == 'rechazada' && motivo != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Motivo del rechazo',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red.shade400)),
                              const SizedBox(height: 4),
                              Text(motivo, style: TextStyle(fontSize: 13, color: Colors.red.shade700, height: 1.4)),
                            ]),
                          ),
                        ],
                        if (estado == 'aprobada') ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD8F0E4),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('¡El rescatista aprobó tu solicitud! Escríbele por el chat para coordinar.',
                                style: TextStyle(fontSize: 13, color: Colors.green.shade800, height: 1.4)),
                          ),
                        ],
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  String _formatFecha(DateTime fecha) {
    final diff = DateTime.now().difference(fecha);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
    if (diff.inHours < 24)   return 'hace ${diff.inHours}h';
    return 'hace ${diff.inDays}d';
  }
}

// ─── Perfil Adoptante Screen ──────────────────────────────────────────────────

class PerfilAdoptanteScreen extends StatelessWidget {
  const PerfilAdoptanteScreen({super.key});

  Widget _settingsCard(List<Widget> items) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.75),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
    ),
    child: Column(children: items),
  );

  Widget _settingsRow(String label, IconData icon, {Color? color, VoidCallback? onTap, bool last = false}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: Colors.grey.shade100)),
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: color ?? Colors.grey.shade600),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: color ?? const Color(0xFF1A1A1A)))),
          Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
        ]),
      ),
    );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: LeafPainter()),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header
              Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(width: 12),
                Text('PERFIL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    letterSpacing: 1.2, color: _teal)),
              ]),
              const SizedBox(height: 16),
              // Avatar + nombre + stats
              Builder(builder: (context) {
                final user = FirebaseAuth.instance.currentUser;
                final nombre = user?.displayName ?? 'Tú';
                final foto   = user?.photoURL;
                final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : 'T';
                return Row(children: [
                  foto != null
                      ? CircleAvatar(backgroundImage: NetworkImage(foto), radius: 32)
                      : CircleAvatar(backgroundColor: _orange, radius: 32,
                          child: Text(inicial, style: const TextStyle(color: Colors.white,
                              fontSize: 24, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 16),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(nombre, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 4),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('favoritos').snapshots(),
                    builder: (_, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return Row(children: [
                        Icon(Icons.location_on, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 2),
                        Text('Medellín · $count favorito${count == 1 ? "" : "s"}',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ]);
                    },
                  ),
                  ]),
                ]);
              }),
              const SizedBox(height: 24),
              // CTA rescatista
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('¿RESCATAS ANIMALES?', style: TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 1.2, color: _teal)),
                  const SizedBox(height: 6),
                  const Text('Vuélvete rescatista verificado',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 6),
                  Text('Publica animales, gestiona solicitudes y construye tu historial público.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const SolicitudRescatistaScreen())),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A1A1A),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Empezar solicitud', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              // Configuración
              Text('CONFIGURACIÓN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  letterSpacing: 1.2, color: _teal)),
              const SizedBox(height: 8),
              const Text('Preferencias', style: TextStyle(fontSize: 24,
                  fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
              const SizedBox(height: 16),
              _settingsCard([
                _settingsRow('Mis solicitudes', Icons.pets,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const MisSolicitudesScreen()))),
                _settingsRow('Notificaciones', Icons.notifications_outlined,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const NotificacionesScreen()))),
                _settingsRow('Ubicación y alcance', Icons.location_on_outlined,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const UbicacionAlcanceScreen()))),
                _settingsRow('Tipo de animal preferido', Icons.pets, last: true,
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const TipoAnimalScreen()))),
              ]),
              const SizedBox(height: 12),
              _settingsCard([
                _settingsRow('Cerrar sesión', Icons.logout,
                    color: Colors.red.shade400, last: true,
                    onTap: () => showDialog(context: context, builder: (_) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text('Cerrar sesión'),
                      content: const Text('¿Seguro que quieres cerrar sesión?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context),
                            child: const Text('Cancelar')),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await GoogleSignIn().signOut();
                            await FirebaseAuth.instance.signOut();
                            if (context.mounted) {
                              Navigator.of(context).popUntil((route) => route.isFirst);
                            }
                          },
                          child: const Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ))),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─── Adoptante Chats Screen ───────────────────────────────────────────────────

class AdoptanteChatsScreen extends StatelessWidget {
  final bool esRescatista;
  const AdoptanteChatsScreen({super.key, this.esRescatista = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(fit: StackFit.expand, children: [
        CustomPaint(painter: LeafPainter()),
        SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios_new, size: 20, color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(width: 12),
                const Text('Conversaciones', style: TextStyle(fontSize: 20,
                    fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
              ]),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('chats')
                    .where(esRescatista ? 'rescatistaId' : 'adoptanteId',
                           isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: _teal));
                  }
                  final docs = [...(snap.data?.docs ?? [])]..sort((a, b) {
                      final ta = (a.data() as Map)['ultimoMensajeEn'] as Timestamp?;
                      final tb = (b.data() as Map)['ultimoMensajeEn'] as Timestamp?;
                      if (ta == null && tb == null) return 0;
                      if (ta == null) return 1;
                      if (tb == null) return -1;
                      return tb.compareTo(ta);
                    });
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('Aún no tienes conversaciones',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            esRescatista
                                ? 'Cuando un adoptante inicie un chat sobre uno de tus animales, aparecerá aquí'
                                : 'Cuando te interese un animal, toca "Chatear" para iniciar una conversación',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ]),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final d             = docs[i].data() as Map<String, dynamic>;
                      final animalNombre  = d['animalNombre']  as String? ?? 'Animal';
                      final rescatista    = d['rescatista']    as String? ?? 'Rescatista';
                      final ultimoMensaje = d['ultimoMensaje'] as String? ?? '';
                      final ultimaHora    = d['ultimaHora']    as String? ?? '';
                      final especie       = d['especie']       as String? ?? 'Perro';
                      final fotoBase64    = d['fotoBase64']    as String?;
                      final campoBadge    = esRescatista ? 'noLeidosRescatista' : 'noLeidosAdoptante';
                      final noLeidos      = (d[campoBadge]    as int?) ?? 0;
                      final emoji         = especie == 'Gato' ? '🐱' : '🐶';
                      final inicial       = rescatista.isNotEmpty ? rescatista[0].toUpperCase() : 'R';
                      final avatarColors  = [_orange, _teal, const Color(0xFF7C6FCD), const Color(0xFF4CAF50)];
                      final avatarColor   = avatarColors[rescatista.length % avatarColors.length];

                      Widget animalAvatar = fotoBase64 != null
                          ? CircleAvatar(backgroundImage: MemoryImage(base64Decode(fotoBase64)), radius: 28)
                          : CircleAvatar(backgroundColor: _teal.withOpacity(0.15), radius: 28,
                              child: Text(emoji, style: const TextStyle(fontSize: 26)));

                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            esRescatista: esRescatista,
                            animal: {
                              'nombre':      animalNombre,
                              'rescatista':  rescatista,
                              'especie':     especie,
                              'ubicacion':   '',
                              'descripcion': '',
                              'tags':        <String>[],
                              'edad':        '',
                              'fotoBase64':  fotoBase64,
                            }),
                        )),
                        child: Container(
                          color: Colors.white.withOpacity(noLeidos > 0 ? 0.7 : 0.4),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          child: Row(children: [
                            Stack(clipBehavior: Clip.none, children: [
                              animalAvatar,
                              Positioned(
                                bottom: -2, left: -4,
                                child: CircleAvatar(
                                  radius: 12, backgroundColor: avatarColor,
                                  child: Text(inicial, style: const TextStyle(fontSize: 10,
                                      color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ]),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(rescatista, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(width: 6),
                                Container(width: 8, height: 8,
                                    decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle)),
                                const Spacer(),
                                Text(ultimaHora, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                              ]),
                              const SizedBox(height: 2),
                              Row(children: [
                                Text('Sobre ', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                                Text(animalNombre, style: TextStyle(fontSize: 13,
                                    fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                              ]),
                              const SizedBox(height: 3),
                              Row(children: [
                                Expanded(
                                  child: Text(ultimoMensaje.isNotEmpty ? ultimoMensaje : 'Inicia la conversación',
                                      style: TextStyle(fontSize: 13,
                                          color: noLeidos > 0 ? const Color(0xFF1A1A1A) : Colors.grey.shade500,
                                          fontWeight: noLeidos > 0 ? FontWeight.w600 : FontWeight.normal),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                                if (noLeidos > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 20, height: 20,
                                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                    alignment: Alignment.center,
                                    child: Text('$noLeidos', style: const TextStyle(
                                        fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ]),
                            ])),
                          ]),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Chat Screen ──────────────────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> animal;
  final bool esRescatista;
  const ChatScreen({super.key, required this.animal, this.esRescatista = false});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtl    = TextEditingController();
  final _scrollCtl = ScrollController();
  late final String _chatId;
  late final CollectionReference _mensajesRef;

  @override
  void initState() {
    super.initState();
    final nombre     = (widget.animal['nombre'] as String)
        .toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final rescatista = ((widget.animal['rescatista'] as String?) ?? 'ana_restrepo')
        .toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    _chatId = '${nombre}_$rescatista';
    _mensajesRef = FirebaseFirestore.instance
        .collection('chats').doc(_chatId).collection('mensajes');
    // Solo el adoptante crea/actualiza el doc del chat.
    // El rescatista NO sobreescribe los IDs — eso rompía el filtro de la lista.
    if (!widget.esRescatista) {
      FirebaseFirestore.instance.collection('chats').doc(_chatId).set({
        'animalNombre':  widget.animal['nombre'],
        'rescatista':    widget.animal['rescatista'] ?? 'Rescatista',
        'rescatistaId':  widget.animal['rescatistaId'] ?? '',
        'adoptanteId':   FirebaseAuth.instance.currentUser?.uid ?? '',
        'especie':       widget.animal['especie'] ?? 'Perro',
        'fotoBase64':    widget.animal['fotoBase64'],
        'ultimoMensaje': '',
        'creadoEn':      FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    // Resetea los no leídos del rol que abre el chat
    final campo = widget.esRescatista ? 'noLeidosRescatista' : 'noLeidosAdoptante';
    FirebaseFirestore.instance.collection('chats').doc(_chatId)
        .update({campo: 0}).catchError((_) {});
  }

  String _nowTime() {
    final n = DateTime.now();
    return '${n.hour}:${n.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _msgCtl.clear();
    await _mensajesRef.add({
      'texto':    trimmed,
      'emisor':   widget.esRescatista ? 'rescatista' : 'adoptante',
      'hora':     _nowTime(),
      'creadoEn': FieldValue.serverTimestamp(),
    });
    final campoDestinatario = widget.esRescatista ? 'noLeidosAdoptante' : 'noLeidosRescatista';
    await FirebaseFirestore.instance.collection('chats').doc(_chatId).update({
      'ultimoMensaje':    trimmed,
      'ultimaHora':       _nowTime(),
      'ultimoMensajeEn':  FieldValue.serverTimestamp(),
      campoDestinatario:  FieldValue.increment(1),
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtl.hasClients) {
        _scrollCtl.animateTo(_scrollCtl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _msgCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nombre      = widget.animal['nombre']     as String;
    final edad        = (widget.animal['edad'] as String?) ?? '';
    final fotoBase64  = widget.animal['fotoBase64'] as String?;
    final rescatista  = (widget.animal['rescatista'] as String?) ?? 'Rescatista';
    final emoji       = widget.animal['especie'] == 'Gato' ? '🐱' : '🐶';

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ─────────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              CircleAvatar(
                radius: 20, backgroundColor: _orange,
                child: Text(rescatista[0],
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(rescatista,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                  const SizedBox(width: 6),
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF34C759), shape: BoxShape.circle),
                  ),
                ]),
                const SizedBox(height: 1),
                Text('Rescatista · normalmente responde en 1h',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ])),
              const SizedBox(width: 36),
            ]),
          ),

          // ── Context card ────────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: fotoBase64 != null
                  ? Image.memory(base64Decode(fotoBase64), width: 48, height: 48, fit: BoxFit.cover)
                  : Container(
                      width: 48, height: 48, color: const Color(0xFFD8F0E4),
                      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26)))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'Conversando sobre $nombre${edad.isNotEmpty ? " · $edad" : ""}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF9DDD5), borderRadius: BorderRadius.circular(20)),
                  child: const Text('En adopción',
                      style: TextStyle(fontSize: 11, color: Color(0xFF8B3A1F), fontWeight: FontWeight.w600)),
                ),
              ])),
              const Icon(Icons.chevron_right, color: Color(0xFFCCCCCC), size: 20),
            ]),
          ),

          // ── Date separator ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              const SizedBox(width: 16),
              Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('Hoy', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
              const SizedBox(width: 16),
            ]),
          ),

          // ── Messages ────────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _mensajesRef.orderBy('creadoEn').snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: _teal));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text('Sé el primero en escribir 🐾',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollCtl.hasClients) {
                    _scrollCtl.jumpTo(_scrollCtl.position.maxScrollExtent);
                  }
                });
                return ListView.builder(
                  controller: _scrollCtl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d      = docs[i].data() as Map<String, dynamic>;
                    final isMine = widget.esRescatista
                        ? d['emisor'] == 'rescatista'
                        : d['emisor'] == 'adoptante';
                    final text   = d['texto'] as String? ?? '';
                    final time   = d['hora']  as String? ?? '';
                    return Align(
                      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMine ? _orange : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft:     const Radius.circular(18),
                            topRight:    const Radius.circular(18),
                            bottomLeft:  Radius.circular(isMine ? 18 : 4),
                            bottomRight: Radius.circular(isMine ? 4  : 18),
                          ),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))],
                        ),
                        child: Column(
                          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Text(text,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: isMine ? Colors.white : const Color(0xFF1A1A1A),
                                    height: 1.4)),
                            const SizedBox(height: 4),
                            Text(time,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: isMine ? Colors.white.withOpacity(0.7) : Colors.grey.shade400)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // ── Template chips ──────────────────────────────────────────────────
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _templateChip('Plantilla: preguntar por encuentro',
                    '¿Podríamos coordinar un encuentro con $nombre esta semana?'),
                const SizedBox(width: 8),
                _templateChip('Plantilla: mi casa y familia',
                    'Vivo en Laureles, tenemos jardín y somos 2 adultos. $nombre estaría muy bien aquí 🌿'),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Input bar ───────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
            child: Row(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F4),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _msgCtl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _send(_msgCtl.text),
                child: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(color: _orange, shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _templateChip(String label, String text) => GestureDetector(
    onTap: () => setState(() => _msgCtl.text = text),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)],
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF444444), fontWeight: FontWeight.w500)),
    ),
  );
}

// ─── Solicitud Adopción Screen ────────────────────────────────────────────────

class SolicitudAdopcionScreen extends StatefulWidget {
  final Map<String, dynamic> animal;
  const SolicitudAdopcionScreen({super.key, required this.animal});
  @override
  State<SolicitudAdopcionScreen> createState() => _SolicitudAdopcionScreenState();
}

class _SolicitudAdopcionScreenState extends State<SolicitudAdopcionScreen> {
  int _step = 0;

  String _vivienda          = '';
  String _ninos             = '';
  String _mascotas          = '';
  String _experienciaPrevia = '';
  final  _integrantesCtl = TextEditingController();
  final  _horasCtl       = TextEditingController();
  final  _motivacionCtl  = TextEditingController();
  bool   _enviando       = false;

  static const _viviendaOpts   = ['Casa con jardín', 'Apartamento con balcón', 'Apartamento sin área exterior'];
  static const _ninosOpts      = ['Sí', 'No'];
  static const _mascotasOpts   = ['Sí', 'No'];
  static const _experienciaOpts = ['Sí', 'No, sería mi primera mascota'];

  bool get _completo =>
      _integrantesCtl.text.trim().isNotEmpty &&
      _horasCtl.text.trim().isNotEmpty &&
      _vivienda.isNotEmpty && _ninos.isNotEmpty && _mascotas.isNotEmpty &&
      _experienciaPrevia.isNotEmpty &&
      _motivacionCtl.text.trim().isNotEmpty;

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    final user = FirebaseAuth.instance.currentUser;
    try {
      await FirebaseFirestore.instance.collection('solicitudes').add({
        'animalNombre':  widget.animal['nombre'],
        'rescatistaId':  widget.animal['rescatistaId'] ?? '',
        'adoptanteId':       user?.uid,
        'nombre':            user?.displayName ?? '',
        'email':             user?.email ?? '',
        'integrantes':       _integrantesCtl.text.trim(),
        'horasFuera':        _horasCtl.text.trim(),
        'vivienda':          _vivienda,
        'tieneNinos':        _ninos == 'Sí',
        'tieneMascotas':     _mascotas == 'Sí',
        'experienciaPrevia': _experienciaPrevia == 'Sí',
        'motivacion':        _motivacionCtl.text.trim(),
        'estado':            'pendiente',
        // etiquetas del animal para calcular compatibilidad
        'animalEnergia':          widget.animal['energia'],
        'animalTamano':           widget.animal['tamano'],
        'animalOkConNinos':       widget.animal['okConNinos'],
        'animalOkConMascotas':    widget.animal['okConMascotas'],
        'animalRequiereExp':      widget.animal['requiereExperiencia'],
        'creadoEn':      FieldValue.serverTimestamp(),
      });
      // Guarda el perfil para el score de compatibilidad en el feed
      await FirebaseFirestore.instance.collection('usuarios').doc(user?.uid).set({
        'perfilAdopcion': {
          'vivienda':          _vivienda,
          'horasFuera':        _horasCtl.text.trim(),
          'tieneNinos':        _ninos == 'Sí',
          'tieneMascotas':     _mascotas == 'Sí',
          'experienciaPrevia': _experienciaPrevia == 'Sí',
        }
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _step = 2);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar: $e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  void dispose() {
    _integrantesCtl.dispose();
    _horasCtl.dispose();
    _motivacionCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 20, 4),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () {
                  if (_step == 1) setState(() => _step = 0);
                  else Navigator.pop(context);
                },
              ),
              Expanded(child: Text(
                _step == 0 ? 'Antes de continuar' :
                _step == 1 ? 'Cuéntanos sobre ti' : '¡Solicitud enviada!',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
              )),
              if (_step < 2)
                Text('${_step + 1} / 2',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (_step < 2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _step == 0 ? 0.5 : 1.0,
                  minHeight: 4,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(_teal),
                ),
              ),
            ),
          Expanded(
            child: _step == 0 ? _stepConciencia() :
                   _step == 1 ? _stepCuestionario() :
                                _stepExito(),
          ),
        ]),
      ),
    );
  }

  Widget _stepConciencia() {
    final nombre     = widget.animal['nombre'] as String;
    final emoji      = widget.animal['especie'] == 'Gato' ? '🐱' : '🐶';
    final fotoBase64 = widget.animal['fotoBase64'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: fotoBase64 != null
            ? Image.memory(base64Decode(fotoBase64),
                height: 200, width: double.infinity, fit: BoxFit.cover)
            : Container(
                height: 200, width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF3D7A52), Color(0xFF1F4A30)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                ),
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 80)))),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: _dark, borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            const Text('🐾', style: TextStyle(fontSize: 32)),
            const SizedBox(height: 16),
            Text(
              '"$nombre te está esperando."',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                  color: Colors.white, height: 1.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'Un animal no es un juguete ni decoración.\nTe amará sin condiciones — en los buenos momentos y en los difíciles.\n\nAdoptar es una promesa de por vida.\n\n¿Estás listo?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFFB8D8C8), height: 1.7),
            ),
          ]),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => setState(() => _step = 1),
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              elevation: 0,
            ),
            child: const Text('Sí, estoy listo 🐾',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Text('Aún no estoy seguro/a',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500,
                  decoration: TextDecoration.underline)),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _stepCuestionario() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _teal.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _teal.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.person_rounded, color: _teal, size: 20),
            const SizedBox(width: 10),
            Text(
              FirebaseAuth.instance.currentUser?.displayName ?? 'Tu nombre de Google',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _teal),
            ),
            const Spacer(),
            const Text('via Gmail', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ),
        const SizedBox(height: 20),
        _campoTexto('¿Cuántas personas en casa?', _integrantesCtl, 'ej. 3',
            teclado: TextInputType.number),
        const SizedBox(height: 24),
        _campoTexto('¿Cuántas horas al día estás fuera de casa?', _horasCtl,
            'ej. 4 horas', teclado: TextInputType.number),
        const SizedBox(height: 24),
        _pregunta('¿Dónde vives?', '🏠', _viviendaOpts, _vivienda,
            (v) => setState(() => _vivienda = v)),
        const SizedBox(height: 24),
        _pregunta('¿Tienes niños menores de 8 años?', '👶', _ninosOpts, _ninos,
            (v) => setState(() => _ninos = v)),
        const SizedBox(height: 24),
        _pregunta('¿Tienes otras mascotas?', '🐕', _mascotasOpts, _mascotas,
            (v) => setState(() => _mascotas = v)),
        const SizedBox(height: 24),
        _pregunta('¿Has tenido mascotas antes?', '🐾', _experienciaOpts,
            _experienciaPrevia, (v) => setState(() => _experienciaPrevia = v)),
        const SizedBox(height: 24),
        _campoTexto('¿Por qué quieres adoptarlo?', _motivacionCtl,
            'ej. Siempre quise tener un perro, tengo espacio y mucho amor...',
            maxLines: 3),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _completo && !_enviando ? _enviar : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange, foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              elevation: 0,
            ),
            child: _enviando
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Enviar solicitud',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _campoTexto(String titulo, TextEditingController ctl,
      String hint, {TextInputType teclado = TextInputType.text, int maxLines = 1}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RichText(text: TextSpan(
        text: titulo,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
        children: const [
          TextSpan(text: ' *', style: TextStyle(color: _orange, fontSize: 15)),
        ],
      )),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: TextField(
          controller: ctl,
          keyboardType: teclado,
          maxLines: maxLines,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    ]);
  }

  Widget _pregunta(String titulo, String icono, List<String> opciones,
      String seleccion, ValueChanged<String> onSelect) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titulo,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
      const SizedBox(height: 4),
      Text('$icono  Elige una opción',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: opciones.map((o) {
        final sel = o == seleccion;
        return GestureDetector(
          onTap: () => onSelect(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? _teal : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: sel ? _teal : Colors.grey.shade300),
              boxShadow: sel ? [] :
                  [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)],
            ),
            child: Text(o, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: sel ? Colors.white : Colors.grey.shade700)),
          ),
        );
      }).toList()),
    ]);
  }

  Widget _stepExito() {
    final nombre = widget.animal['nombre'] as String;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
                color: _teal.withOpacity(0.12), shape: BoxShape.circle),
            child: const Icon(Icons.favorite, color: _teal, size: 50),
          ),
          const SizedBox(height: 28),
          const Text('¡Solicitud enviada!',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 12),
          Text(
            'Le avisamos a la rescatista.\nPronto sabrás si $nombre encontró su hogar contigo. 🌿',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.6),
          ),
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () { Navigator.pop(context); Navigator.pop(context); },
              style: ElevatedButton.styleFrom(
                backgroundColor: _dark, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 0,
              ),
              child: const Text('Volver al inicio',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ver más animales',
                style: TextStyle(color: _teal, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

// ─── Favoritos Screen ─────────────────────────────────────────────────────────

class FavoritosScreen extends StatelessWidget {
  const FavoritosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('favoritos')
              .where('adoptanteId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _teal));
            }
            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
            final allDocs = snap.data?.docs ?? [];
            final seen = <String>{};
            final docs = allDocs.where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final nombre = (d['animalNombre'] as String? ?? '').toLowerCase();
              return seen.add(nombre);
            }).toList();
            for (final doc in allDocs) {
              final d = doc.data() as Map<String, dynamic>;
              final nombre = (d['animalNombre'] as String? ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
              final expectedId = '${uid}_$nombre';
              if (doc.id != expectedId) doc.reference.delete();
            }

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          docs.isEmpty ? 'SIN GUARDADOS' : '${docs.length} GUARDADO${docs.length == 1 ? "" : "S"}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              letterSpacing: 1.2, color: Colors.grey.shade500),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text('Tus favoritos',
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                      ),
                    ]),
                  ),
                ),
                if (docs.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.favorite_border, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        const Text('Aún no tienes favoritos',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                        const SizedBox(height: 8),
                        Text('Toca ❤️ en las tarjetas para guardar\nanimalitos que te gusten.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.5)),
                      ]),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.72,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final d            = docs[i].data() as Map<String, dynamic>;
                          final nombre       = d['animalNombre'] as String? ?? 'Sin nombre';
                          final especie      = d['especie']      as String? ?? '';
                          final edad         = d['edad']         as String? ?? '';
                          final ubicacion    = d['ubicacion']    as String? ?? '';
                          final fotoBase64   = d['fotoBase64']   as String?;
                          final rescatista   = d['rescatista']   as String? ?? 'Rescatista';
                          final rescatistaId = d['rescatistaId'] as String? ?? '';
                          final emoji        = especie == 'Gato' ? '🐱' : '🐶';

                          final animalMap = {
                            'nombre': nombre,
                            'especie': especie,
                            'edad': edad,
                            'genero': d['genero'] ?? '',
                            'ubicacion': ubicacion,
                            'rescatista': rescatista,
                            'rescatistaId': rescatistaId,
                            'fotoBase64': fotoBase64,
                          };

                          return Stack(children: [
                            GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  animal: animalMap,
                                  esRescatista: false,
                                ),
                              )),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07),
                                      blurRadius: 10, offset: const Offset(0, 3))],
                                ),
                                clipBehavior: Clip.hardEdge,
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(
                                    child: fotoBase64 != null
                                      ? Image.memory(base64Decode(fotoBase64),
                                          width: double.infinity, fit: BoxFit.cover)
                                      : Container(
                                          width: double.infinity,
                                          color: const Color(0xFFD8F0E4),
                                          child: Center(child: Text(emoji,
                                              style: const TextStyle(fontSize: 52)))),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(nombre,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                                              color: Color(0xFF1A1A1A)),
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${edad.isNotEmpty ? "$edad · " : ""}$ubicacion',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                                            builder: (_) => ChatScreen(
                                              animal: animalMap,
                                              esRescatista: false,
                                            ),
                                          )),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _teal,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            elevation: 0,
                                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                          ),
                                          child: const Text('Adoptar'),
                                        ),
                                      ),
                                    ]),
                                  ),
                                ]),
                              ),
                            ),
                            // Botón quitar favorito
                            Positioned(
                              top: 8, right: 8,
                              child: GestureDetector(
                                onTap: () => docs[i].reference.delete(),
                                child: Container(
                                  width: 30, height: 30,
                                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                  child: const Icon(Icons.favorite, color: _orange, size: 17),
                                ),
                              ),
                            ),
                          ]);
                        },
                        childCount: docs.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
