import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../widgets/cambiar_rol_debug.dart';
import '../widgets/campo_ciudad.dart';
import '../widgets/campo_pais_telefono.dart';
import '../widgets/campos_perfil.dart';
import '../widgets/confirmar_ciudad_resuelta.dart';
import '../widgets/elegir_foto_perfil.dart';
import '../widgets/fondo_decorativo.dart';
import '../widgets/fotos.dart';
import '../data/firestore_resiliencia.dart';
import '../services/ubicacion_service.dart';

class AlberguePerfilScreen extends StatefulWidget {
  const AlberguePerfilScreen({super.key});
  @override
  State<AlberguePerfilScreen> createState() => _AlberguePerfilScreenState();
}

class _AlberguePerfilScreenState extends State<AlberguePerfilScreen> {
  final _nombreCtl = TextEditingController();
  final _ciudadCtl = TextEditingController();
  final _capacidadCtl = TextEditingController();
  final _telefonoCtl = TextEditingController();
  final _direccionCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _webCtl = TextEditingController();
  String? _tipo;
  String? _fotoBase64;
  bool _guardando = false;
  // Ciudad tal cual estaba guardada al abrir la pantalla — para geocodificar
  // solo cuando el texto realmente cambia (ver _guardar()), no en cada
  // guardado.
  String _ciudadOriginal = '';
  // ¿El perfil ya tiene coordenadas guardadas? Es la otra mitad de la
  // condición para geocodificar (ver _guardar): un perfil creado antes de
  // que existiera esa validación tiene ciudad pero NO coordenadas, y sin
  // esto nunca se le validaba porque el texto no cambiaba. Ese es el motivo
  // real de que NINGÚN animal de albergue mostrara distancia.
  bool _tieneCoordenadas = false;

  @override
  void initState() {
    super.initState();
    _cargarDatosExistentes();
  }

  Future<void> _cargarDatosExistentes() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    if (!doc.exists || !mounted) return;
    final data = doc.data() as Map<String, dynamic>;
    setState(() {
      _nombreCtl.text = data['albergueNombre'] as String? ?? '';
      _ciudadCtl.text = data['ciudad'] as String? ?? '';
      _ciudadOriginal = _ciudadCtl.text;
      _tieneCoordenadas = data['latitud'] != null && data['longitud'] != null;
      _capacidadCtl.text = (data['capacidadTotal'] as int?)?.toString() ?? '';
      _telefonoCtl.text = data['albergueTelefono'] as String? ?? '';
      _direccionCtl.text = data['albergueDireccion'] as String? ?? '';
      _emailCtl.text = data['albergueEmail'] as String? ?? '';
      _webCtl.text = data['albergueSitioWeb'] as String? ?? '';
      _tipo = data['albergueTipo'] as String?;
      _fotoBase64 = data['fotoBase64'] as String?;
    });
  }

  // El diálogo/escritura viven en mostrarCambiarRolDebug (widgets/cambiar_rol_debug.dart,
  // compartida entre 5 pantallas que antes cada una tenía su propia copia
  // — hallazgo de auditoría de código).
  Future<void> _cambiarRolDebug(BuildContext ctx) =>
      mostrarCambiarRolDebug(ctx);

  Future<void> _pickFoto() async {
    final b64 = await elegirFotoPerfil();
    if (b64 == null || !mounted) return;
    setState(() => _fotoBase64 = b64);
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
    final ciudad = _ciudadCtl.text.trim();
    // Geocodifica la ciudad escrita a mano a coordenadas — sin esto, un
    // albergue nunca tenía latitud/longitud en ningún lado (ni acá ni al
    // publicar un animal, que reusa este mismo campo de texto), así que
    // "a X km de ti" nunca podía calcularse para NINGÚN animal publicado
    // por un albergue. Hallazgo real de Eliza: notó que faltaba en todos
    // los albergues, no en uno solo. Solo geocodifica si el texto de
    // ciudad cambió — no tiene sentido volver a pedirle a la red algo que
    // ya se resolvió antes.
    //
    // UbicacionService.desdeTexto es la única fuente de "¿esto es una
    // ciudad real?" para toda la app — antes acá se trataba "no encontré
    // nada" exactamente igual que "no hay señal": en los dos casos se
    // guardaba la ciudad tal cual sin avisar nada, así que cualquier texto
    // ("verduras", lo que fuera) quedaba guardado como ciudad válida.
    // Ahora sí se distingue: sin señal se guarda igual (la ciudad en texto
    // nunca fue obligatoria para publicar, un problema de conexión no
    // debería empezar a bloquearlo), pero "no es un lugar real" bloquea el
    // guardado entero y avisa, en vez de guardar basura en silencio.
    double? lat;
    double? lng;
    // La regla ahora es un INVARIANTE, no una optimización: si hay ciudad
    // guardada, tiene que haber coordenadas. Por eso se geocodifica cuando
    // el texto cambió O cuando todavía no hay coordenadas — esa segunda
    // mitad es la que repara los perfiles viejos, creados antes de que esta
    // validación existiera, que nunca pasaban por acá porque el texto no
    // cambiaba y por eso dejaban a TODOS sus animales sin distancia.
    if (ciudad.isNotEmpty &&
        (ciudad != _ciudadOriginal || !_tieneCoordenadas)) {
      String? error;
      try {
        final resultado = await UbicacionService.desdeTexto(ciudad);
        if (resultado == null) {
          error =
              'No encontramos "$ciudad" como ciudad. Revisá cómo la escribiste.';
        } else {
          // Un texto mal escrito puede coincidir con OTRO lugar real del
          // mundo (no da null) — hallazgo real de Eliza escribiendo
          // "Nedellin" y quedando guardado a 9077km de Medellín. Se le
          // muestra qué se resolvió para que lo confirme ella misma.
          if (!mounted) return;
          final confirmo = await confirmarCiudadResuelta(
            context,
            escribiste: ciudad,
            resuelta: resultado.ciudadResuelta,
            paisCodigo: resultado.paisCodigo,
            region: resultado.regionResuelta,
          );
          if (!confirmo) {
            if (!mounted) return;
            setState(() => _guardando = false);
            return;
          }
          lat = resultado.lat;
          lng = resultado.lng;
        }
      } catch (_) {
        // Antes esto era un catch vacío que dejaba seguir: se guardaba la
        // ciudad sin coordenadas, en silencio, y ese animal (y todos los
        // que publicara ese albergue) quedaba sin distancia para siempre.
        // Un problema de red no puede dejar el dato a medias: se bloquea y
        // se avisa, con un texto que no confunde "no hay señal" con "eso no
        // es una ciudad".
        error =
            'No pudimos verificar esa ciudad. Revisá tu conexión e intentá de nuevo.';
      }
      if (error != null) {
        if (!mounted) return;
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: msgError),
        );
        return;
      }
    }
    // guardarConAviso, no un await directo: sin esto, sin conexión o con
    // el token de sesión vencido, el botón de guardar se quedaba pegado
    // para siempre sin ningún aviso — mismo bug ya arreglado una vez en
    // editar_rescate_screen.dart, que nunca se replicó acá (hallazgo de
    // auditoría de código).
    final resultado = await guardarConAviso(
      () => FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'albergueNombre': _nombreCtl.text.trim(),
        'albergueTipo': _tipo ?? '',
        'ciudad': ciudad,
        if (lat != null) 'latitud': lat,
        if (lng != null) 'longitud': lng,
        'capacidadTotal': int.tryParse(_capacidadCtl.text.trim()) ?? 0,
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
        'albergueTelefono': _telefonoCtl.text.trim(),
        'albergueDireccion': _direccionCtl.text.trim(),
        'albergueEmail': _emailCtl.text.trim(),
        'albergueSitioWeb': _webCtl.text.trim(),
        if (_fotoBase64 != null) 'fotoBase64': _fotoBase64,
      }),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    switch (resultado) {
      case ResultadoGuardado.confirmado:
        if (Navigator.canPop(context)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Perfil actualizado'),
              backgroundColor: msgExito,
            ),
          );
          Navigator.pop(context);
        }
      case ResultadoGuardado.siguePendiente:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Esto está tardando. Tu perfil se va a actualizar solo apenas vuelva la señal.',
            ),
            backgroundColor: msgAdvertencia,
          ),
        );
        if (Navigator.canPop(context)) Navigator.pop(context);
      case ResultadoGuardado.fallo:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo guardar. Revisá tu conexión e intentá de nuevo.',
            ),
            backgroundColor: msgError,
          ),
        );
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LeafOverlay(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Builder(
                    builder: (ctx) => Navigator.canPop(ctx)
                        ? IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios_new,
                              size: 20,
                            ),
                            tooltip: 'Volver',
                            onPressed: () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 16),

                  // Header
                  const Text(
                    'Configura tu albergue',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: appInk,
                      fontFamily: 'Baloo2',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Esta información aparecerá en tu perfil oficial.',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 32),

                  // Logo / foto del albergue
                  Center(
                    child: Builder(
                      builder: (_) {
                        final fotoBytes = bytesFotoSegura(_fotoBase64);
                        return GestureDetector(
                          onTap: _pickFoto,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(
                                    color: appTeal,
                                    width: 2.5,
                                  ),
                                  image: fotoBytes != null
                                      ? DecorationImage(
                                          image: MemoryImage(fotoBytes),
                                          fit: BoxFit.cover,
                                          onError: (_, _) {},
                                        )
                                      : null,
                                ),
                                child: fotoBytes == null
                                    ? const Icon(
                                        Icons.add_a_photo_outlined,
                                        color: appTeal,
                                        size: 32,
                                      )
                                    : null,
                              ),
                              if (fotoBytes != null)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: appTeal,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      _fotoBase64 == null
                          ? 'Agrega el logo de tu albergue (opcional)'
                          : 'Toca para cambiar',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Nombre
                  perfilLabel('NOMBRE DEL ALBERGUE *'),
                  const SizedBox(height: 8),
                  perfilCampo(
                    _nombreCtl,
                    'ej. Centro de Bienestar Animal La Perla',
                    autofocus: true,
                    maxLength: 50,
                  ),
                  const SizedBox(height: 24),

                  // Tipo
                  perfilLabel('TIPO DE ORGANIZACIÓN *'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _tipos.map((t) {
                      final sel = t == (_tipo ?? '');
                      return GestureDetector(
                        onTap: () => setState(() => _tipo = t),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: sel ? appInk : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sel ? appInk : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            t,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Capacidad
                  perfilLabel('CAPACIDAD TOTAL DE ANIMALES *'),
                  const SizedBox(height: 8),
                  perfilCampo(
                    _capacidadCtl,
                    'ej. 220',
                    tipo: TextInputType.number,
                    formato: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Cuántos animales puede albergar tu organización.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 24),

                  // Ciudad
                  perfilLabel('CIUDAD *'),
                  const SizedBox(height: 8),
                  CampoCiudad(
                    controller: _ciudadCtl,
                    hint: 'ej. Medellín, Bogotá, Santiago',
                    maxLength: 50,
                  ),
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
                  perfilCampo(
                    _direccionCtl,
                    'ej. Calle 10 #43-12, El Poblado',
                    maxLength: 100,
                  ),
                  const SizedBox(height: 24),

                  // Email (opcional)
                  perfilLabel('EMAIL (OPCIONAL)'),
                  const SizedBox(height: 8),
                  perfilCampo(
                    _emailCtl,
                    'ej. contacto@tuAlbergue.org',
                    tipo: TextInputType.emailAddress,
                    maxLength: 100,
                  ),
                  const SizedBox(height: 24),

                  // Página web (opcional)
                  perfilLabel('PÁGINA WEB (OPCIONAL)'),
                  const SizedBox(height: 8),
                  perfilCampo(
                    _webCtl,
                    'ej. www.tuAlbergue.org',
                    tipo: TextInputType.url,
                    maxLength: 150,
                  ),
                  const SizedBox(height: 24),

                  // "Aviso de animal sin adoptar" se sacó de este formulario —
                  // vive ahora en la pantalla de Perfil del albergue (no en
                  // "Editar perfil"), en el mismo lugar y con el mismo estilo
                  // que ya usa perfil_rescatista_screen.dart para lo mismo.
                  // Pedido real de Eliza: estandarizar dónde vive ese ajuste
                  // entre los dos roles.
                  const SizedBox(height: 12),

                  // Botón
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      _nombreCtl,
                      _ciudadCtl,
                      _capacidadCtl,
                    ]),
                    builder: (_, _) => SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_completo && !_guardando) ? _guardar : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appInk,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _guardando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                Navigator.canPop(context)
                                    ? 'Guardar cambios'
                                    : 'Crear perfil del albergue',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          if (kDebugMode)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: Builder(
                builder: (ctx) => Tooltip(
                  message: 'Cambiar rol (debug)',
                  child: GestureDetector(
                    onTap: () => _cambiarRolDebug(ctx),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.developer_mode,
                        color: Colors.purple.shade700,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
