import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../data/usuarios_repository.dart';
import '../data/firestore_resiliencia.dart';

class AlberguePerfilScreen extends StatefulWidget {
  const AlberguePerfilScreen({super.key});
  @override
  State<AlberguePerfilScreen> createState() => _AlberguePerfilScreenState();
}

class _AlberguePerfilScreenState extends State<AlberguePerfilScreen> {
  final _nombreCtl    = TextEditingController();
  final _ciudadCtl    = TextEditingController();
  final _capacidadCtl = TextEditingController();
  final _telefonoCtl  = TextEditingController();
  final _direccionCtl = TextEditingController();
  final _emailCtl     = TextEditingController();
  final _webCtl       = TextEditingController();
  String? _tipo;
  String? _fotoBase64;
  int     _umbralEstancado = umbralEstancadoDefault;
  bool   _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatosExistentes();
  }

  Future<void> _cargarDatosExistentes() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    if (!doc.exists || !mounted) return;
    final data = doc.data() as Map<String, dynamic>;
    setState(() {
      _nombreCtl.text    = data['albergueNombre'] as String? ?? '';
      _ciudadCtl.text    = data['ciudad']         as String? ?? '';
      _capacidadCtl.text = (data['capacidadTotal'] as int?)?.toString() ?? '';
      _telefonoCtl.text  = data['albergueTelefono']  as String? ?? '';
      _direccionCtl.text = data['albergueDireccion'] as String? ?? '';
      _emailCtl.text     = data['albergueEmail']     as String? ?? '';
      _webCtl.text       = data['albergueSitioWeb']  as String? ?? '';
      _tipo              = data['albergueTipo']   as String?;
      _fotoBase64        = data['fotoBase64']     as String?;
      _umbralEstancado   = umbralEstancadoDe(data);
    });
  }

  Future<void> _cambiarRolDebug(BuildContext ctx) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final opciones = <String, List<String>>{
      'Solo Adoptante':         ['adoptante'],
      'Solo Rescatista':        ['rescatista'],
      'Adoptante + Rescatista': ['adoptante', 'rescatista'],
      'Albergue':               ['albergue'],
      'Aliado':                 ['aliado'],
    };
    final sel = await showDialog<List<String>>(
      context: ctx,
      builder: (ctx) => SimpleDialog(
        title: const Text('🛠 Cambiar rol (DEBUG)'),
        children: opciones.entries.map((e) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, e.value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(e.key),
          ),
        )).toList(),
      ),
    );
    if (sel == null || !mounted) return;
    try {
      await UsuariosRepository().actualizarRoles(uid, sel);
    } catch (_) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('No se pudo cambiar el rol. Revisá tu conexión e intentá de nuevo.'),
          backgroundColor: msgError));
    }
  }

  Future<void> _pickFoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _fotoBase64 = base64Encode(bytes));
  }

  static const _tipos = ['Centro municipal', 'Fundación', 'ONG', 'Privado'];

  // "0" pasaba antes esta validación (solo se pedía que el campo no
  // estuviera vacío) y se guardaba tal cual — pero el panel de capacidad
  // del dashboard (albergue_home_screen.dart) solo se muestra si
  // capacidadTotal es mayor a 0, así que esa función entera desaparecía
  // en silencio, sin ningún error que lo explicara. Hallazgo de auditoría
  // de código.
  bool get _completo =>
      _nombreCtl.text.trim().isNotEmpty &&
      _ciudadCtl.text.trim().isNotEmpty &&
      (int.tryParse(_capacidadCtl.text.trim()) ?? 0) > 0 &&
      _tipo != null;

  Future<void> _guardar() async {
    if (!_completo) return;
    setState(() => _guardando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // guardarConAviso, no un await directo: sin esto, sin conexión o con
    // el token de sesión vencido, el botón de guardar se quedaba pegado
    // para siempre sin ningún aviso — mismo bug ya arreglado una vez en
    // editar_rescate_screen.dart, que nunca se replicó acá (hallazgo de
    // auditoría de código).
    final resultado = await guardarConAviso(() =>
        FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
          'albergueNombre':    _nombreCtl.text.trim(),
          'albergueTipo':      _tipo ?? '',
          'ciudad':            _ciudadCtl.text.trim(),
          'capacidadTotal':    int.tryParse(_capacidadCtl.text.trim()) ?? 0,
          // Opcionales a propósito: un albergue chico recién arrancando puede
          // no tener todavía un número separado del personal o una dirección
          // fija — no debería trabarlo para poder crear su perfil.
          //
          // Prefijo "albergue" a propósito (no "telefono"/"email" genérico):
          // una misma cuenta puede tener rol de albergue Y de aliado a la vez, y
          // los dos guardaban antes en los mismos campos genéricos — llenar el
          // contacto del albergue pisaba (y se mostraba) en el perfil de aliado
          // también, y encima "email" genérico chocaba con el email de LOGIN de
          // la cuenta que ya escribía usuarios_repository.dart. Bug real
          // reportado por Eliza probando con una cuenta de doble rol.
          'albergueTelefono':  _telefonoCtl.text.trim(),
          'albergueDireccion': _direccionCtl.text.trim(),
          'albergueEmail':     _emailCtl.text.trim(),
          'albergueSitioWeb':  _webCtl.text.trim(),
          'umbralEstancadoDias': _umbralEstancado,
          if (_fotoBase64 != null) 'fotoBase64': _fotoBase64,
        }));
    if (!mounted) return;
    setState(() => _guardando = false);
    switch (resultado) {
      case ResultadoGuardado.confirmado:
        if (Navigator.canPop(context)) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Perfil actualizado'), backgroundColor: msgExito));
          Navigator.pop(context);
        }
      case ResultadoGuardado.siguePendiente:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Esto está tardando. Tu perfil se va a actualizar solo apenas vuelva la señal.'),
            backgroundColor: msgAdvertencia));
        if (Navigator.canPop(context)) Navigator.pop(context);
      case ResultadoGuardado.fallo:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo guardar. Revisá tu conexión e intentá de nuevo.'),
            backgroundColor: msgError));
    }
  }

  @override
  void dispose() {
    _nombreCtl.dispose();
    _ciudadCtl.dispose();
    _capacidadCtl.dispose();
    _telefonoCtl.dispose();
    _direccionCtl.dispose();
    _emailCtl.dispose();
    _webCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appBg,
      body: Stack(fit: StackFit.expand, children: [
        const LeafOverlay(),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 24),
              Builder(builder: (ctx) => Navigator.canPop(ctx)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                tooltip: 'Volver',
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )
                  : const SizedBox.shrink()),
              const SizedBox(height: 16),

              // Header
              const Text('Configura tu albergue',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                      color: appInk, fontFamily: 'Baloo2')),
              const SizedBox(height: 6),
              Text('Esta información aparecerá en tu perfil oficial.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
              const SizedBox(height: 32),

              // Logo / foto del albergue
              Center(
                child: Builder(builder: (_) {
                  final fotoBytes = bytesFotoSegura(_fotoBase64);
                  return GestureDetector(
                    onTap: _pickFoto,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Container(
                        width: 96, height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: appTeal, width: 2.5),
                          image: fotoBytes != null
                              ? DecorationImage(
                                  image: MemoryImage(fotoBytes),
                                  fit: BoxFit.cover,
                                  onError: (_, _) {})
                              : null,
                        ),
                        child: fotoBytes == null
                            ? const Icon(Icons.add_a_photo_outlined,
                                color: appTeal, size: 32)
                            : null,
                      ),
                      if (fotoBytes != null)
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            width: 30, height: 30,
                            decoration: BoxDecoration(
                              color: appTeal,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.edit, color: Colors.white, size: 14),
                          ),
                        ),
                    ]),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _fotoBase64 == null ? 'Agrega el logo de tu albergue (opcional)' : 'Toca para cambiar',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
              const SizedBox(height: 28),

              // Nombre
              perfilLabel('NOMBRE DEL ALBERGUE *'),
              const SizedBox(height: 8),
              perfilCampo(_nombreCtl, 'ej. Centro de Bienestar Animal La Perla', autofocus: true),
              const SizedBox(height: 24),

              // Tipo
              perfilLabel('TIPO DE ORGANIZACIÓN *'),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8,
                children: _tipos.map((t) {
                  final sel = t == (_tipo ?? '');
                  return GestureDetector(
                    onTap: () => setState(() => _tipo = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: sel ? appInk : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? appInk : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(t, style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.grey.shade700,
                      )),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Capacidad
              perfilLabel('CAPACIDAD TOTAL DE ANIMALES *'),
              const SizedBox(height: 8),
              perfilCampo(_capacidadCtl, 'ej. 220',
                  tipo: TextInputType.number,
                  formato: [FilteringTextInputFormatter.digitsOnly]),
              const SizedBox(height: 6),
              Text('Cuántos animales puede albergar tu organización.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 24),

              // Ciudad
              perfilLabel('CIUDAD *'),
              const SizedBox(height: 8),
              perfilCampo(_ciudadCtl, 'ej. Medellín, Bogotá, Santiago'),
              const SizedBox(height: 24),

              // Teléfono/WhatsApp (opcional) — se guarda tal cual lo
              // escriba la persona; al mostrarlo en el perfil público se
              // limpia y arma como link directo a WhatsApp (wa.me), no
              // solo un número para copiar a mano.
              perfilLabel('TELÉFONO / WHATSAPP (OPCIONAL)'),
              const SizedBox(height: 8),
              CampoTelefono(controller: _telefonoCtl),
              const SizedBox(height: 24),

              // Dirección (opcional)
              perfilLabel('DIRECCIÓN (OPCIONAL)'),
              const SizedBox(height: 8),
              perfilCampo(_direccionCtl, 'ej. Calle 10 #43-12, El Poblado'),
              const SizedBox(height: 24),

              // Email (opcional)
              perfilLabel('EMAIL (OPCIONAL)'),
              const SizedBox(height: 8),
              perfilCampo(_emailCtl, 'ej. contacto@tuAlbergue.org',
                  tipo: TextInputType.emailAddress),
              const SizedBox(height: 24),

              // Página web (opcional)
              perfilLabel('PÁGINA WEB (OPCIONAL)'),
              const SizedBox(height: 8),
              perfilCampo(_webCtl, 'ej. www.tuAlbergue.org',
                  tipo: TextInputType.url),
              const SizedBox(height: 24),

              // Umbral de "animal estancado" — a partir de cuánto tiempo
              // sin encontrar hogar se muestra el aviso en "Mis animales".
              // Antes eran 30 días fijos para todos; cada albergue conoce
              // mejor su propio ritmo de adopciones (pedido de Eliza).
              perfilLabel('AVISO DE ANIMAL SIN ADOPTAR, DESPUÉS DE...'),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8,
                children: umbralEstancadoOpciones.map((o) {
                  final sel = o.$1 == _umbralEstancado;
                  return GestureDetector(
                    onTap: () => setState(() => _umbralEstancado = o.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: sel ? appOrange : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel ? appOrange : Colors.grey.shade300),
                      ),
                      child: Text(o.$2, style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.grey.shade700,
                      )),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 36),

              // Botón
              ListenableBuilder(
                listenable: Listenable.merge([_nombreCtl, _ciudadCtl, _capacidadCtl]),
                builder: (_, _) => SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_completo && !_guardando) ? _guardar : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appInk,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _guardando
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(Navigator.canPop(context) ? 'Guardar cambios' : 'Crear perfil del albergue',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ),
        if (kDebugMode)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: Builder(builder: (ctx) => Tooltip(
              message: 'Cambiar rol (debug)',
              child: GestureDetector(
                onTap: () => _cambiarRolDebug(ctx),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade100,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: Icon(Icons.developer_mode,
                      color: Colors.purple.shade700, size: 18),
                ),
              ),
            )),
          ),
      ]),
    );
  }

}
