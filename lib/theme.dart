import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter, FilteringTextInputFormatter;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'data/chats_repository.dart';
import 'data/rescates_repository.dart';

// ─── Aviso de "esto está tardando" ────────────────────────────────────────────
// El trío bool + Timer + cancelar-en-dispose se copiaba en 3 pantallas de
// publicar/editar (hallazgo de auditoría de código) — cada una sigue
// dibujando su propio aviso (se ven distinto a propósito, según dónde
// aparece), este mixin solo centraliza CUÁNDO mostrarlo.
mixin TardandoMuchoMixin<T extends StatefulWidget> on State<T> {
  bool tardandoMucho = false;
  Timer? _tardandoTimer;

  void iniciarTimerTardando(Duration umbral) {
    _tardandoTimer?.cancel();
    tardandoMucho = false;
    _tardandoTimer = Timer(umbral, () {
      if (mounted) setState(() => tardandoMucho = true);
    });
  }

  void cancelarTimerTardando() => _tardandoTimer?.cancel();

  @override
  void dispose() {
    _tardandoTimer?.cancel();
    super.dispose();
  }
}

// ─── Fecha ────────────────────────────────────────────────────────────────────
// El mismo arreglo de meses abreviados en español se copiaba, con leves
// variaciones, en 6 pantallas distintas (hallazgo de auditoría de código) —
// se centraliza acá para que un cambio de formato (o de idioma, algún día)
// se aplique en un solo lugar.
const _mesesAbreviados = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

/// "15 jul" o "15 jul 2026" según [conAnio]. Pantallas con lógica propia de
/// fecha relativa (ej. chat_screen.dart, que también muestra "Hoy"/"Ayer" y
/// solo agrega el año si difiere del actual) siguen resolviendo esa parte
/// ellas mismas y llaman a esta función solo para el "día mes [año]" final.
String formatearFecha(DateTime d, {bool conAnio = true}) =>
    '${d.day} ${_mesesAbreviados[d.month - 1]}${conAnio ? ' ${d.year}' : ''}';

// ─── WhatsApp ─────────────────────────────────────────────────────────────────
// Compartido entre albergue_publico_screen.dart y aliado_publico_screen.dart
// (los dos muestran el mismo botón "Escribir por WhatsApp" si el perfil
// cargó un teléfono).
//
/// Arma el link de WhatsApp a partir de lo que la persona haya escrito en
/// "Teléfono/WhatsApp". Los números guardados con [CampoTelefono] ya vienen
/// con su indicativo real adelante ("+52 55 1234 5678", por ejemplo) y se
/// usan tal cual.
///
/// Para números viejos, guardados en el formato libre de antes de que
/// existiera el selector de país, se asume Colombia si quedan 10 dígitos
/// al limpiar todo lo que no sea número — eso cubre tanto un celular
/// (empieza en 3) como un fijo con el prefijo "60" que el plan de
/// numeración de Colombia le agregó a todos los fijos del país (ej. un fijo
/// de Medellín: "604 444 4444"). Antes solo se cubría el caso celular, así
/// que un fijo escrito tal como lo sugiere el propio campo (sin +57
/// delante) armaba un link roto — bug real reportado por Eliza.
String? whatsappUrl(String telefono) {
  final digitos = telefono.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.isEmpty) return null;
  final conIndicativo = digitos.length == 10 ? '57$digitos' : digitos;
  return 'https://wa.me/$conIndicativo';
}

// ─── Selector de país + teléfono ────────────────────────────────────────────
// La app conecta animales rescatados con adoptantes en toda Hispanoamérica,
// no solo en Colombia (pedido real de Eliza) — así que adivinar el país por
// la forma del número (como hacía whatsappUrl() antes) nunca iba a ser
// confiable para siempre. Esta caja reemplaza la adivinanza por una
// elección explícita de la persona: el indicativo elegido queda
// EMBEBIDO en el mismo texto de siempre ("+57 300 123 4567"), así que
// whatsappUrl() no tiene que volver a adivinar nada para lo que se guarde
// desde acá en adelante — el campo de Firestore no cambia de nombre ni de
// forma, solo de contenido.

class Pais {
  final String nombre;
  final String bandera;
  final String indicativo;
  const Pais(this.nombre, this.bandera, this.indicativo);
}

const paisesHispanohablantes = <Pais>[
  Pais('Colombia', '🇨🇴', '57'),
  Pais('México', '🇲🇽', '52'),
  Pais('Argentina', '🇦🇷', '54'),
  Pais('Chile', '🇨🇱', '56'),
  Pais('Perú', '🇵🇪', '51'),
  Pais('Ecuador', '🇪🇨', '593'),
  Pais('Venezuela', '🇻🇪', '58'),
  Pais('Bolivia', '🇧🇴', '591'),
  Pais('Paraguay', '🇵🇾', '595'),
  Pais('Uruguay', '🇺🇾', '598'),
  Pais('España', '🇪🇸', '34'),
  Pais('Costa Rica', '🇨🇷', '506'),
  Pais('Panamá', '🇵🇦', '507'),
  Pais('Guatemala', '🇬🇹', '502'),
  Pais('Honduras', '🇭🇳', '504'),
  Pais('El Salvador', '🇸🇻', '503'),
  Pais('Nicaragua', '🇳🇮', '505'),
  Pais('República Dominicana', '🇩🇴', '1'),
  Pais('Puerto Rico', '🇵🇷', '1'),
  Pais('Cuba', '🇨🇺', '53'),
  Pais('Guinea Ecuatorial', '🇬🇶', '240'),
];

/// Separa lo que ya haya en [texto] entre el país que corresponde y el
/// número local que se muestra en la caja de texto — para que abrir un
/// perfil que ya tenía teléfono guardado no lo borre ni lo desordene.
/// Si no reconoce ningún indicativo adelante (número viejo, formato
/// libre, o campo recién vacío) asume Colombia y deja el texto tal cual,
/// igual que se comportaba el campo antes de que existiera este selector.
({Pais pais, String local}) partirTelefono(String texto) {
  final t = texto.trim();
  if (t.startsWith('+')) {
    final digitos = t.replaceAll(RegExp(r'[^0-9]'), '');
    for (final p in paisesHispanohablantes) {
      if (digitos.startsWith(p.indicativo)) {
        return (pais: p, local: digitos.substring(p.indicativo.length).trim());
      }
    }
  }
  return (pais: paisesHispanohablantes.first, local: t);
}

class CampoTelefono extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration? decoracionLocal;
  final bool autofocus;
  const CampoTelefono({
    super.key,
    required this.controller,
    this.decoracionLocal,
    this.autofocus = false,
  });
  @override
  State<CampoTelefono> createState() => _CampoTelefonoState();
}

class _CampoTelefonoState extends State<CampoTelefono> {
  late Pais _pais;
  final _localCtl = TextEditingController();
  String _ultimoValorPropio = '';

  @override
  void initState() {
    super.initState();
    // El controlador de afuera casi siempre llega vacío en este primer
    // instante — las pantallas de perfil lo llenan con un setState()
    // async DESPUÉS de leer Firestore. _externoCambio() es lo que atrapa
    // ese llenado tardío; sin él, un teléfono ya guardado se ve vacío al
    // abrir la pantalla hasta que la persona lo escribe de nuevo a mano
    // (mismo tipo de bug ya encontrado esta sesión con `late` que solo se
    // evalúa una vez por vida del State).
    _cargarDesdeControladorExterno();
    widget.controller.addListener(_externoCambio);
    _localCtl.addListener(_sincronizar);
  }

  void _cargarDesdeControladorExterno() {
    final partido = partirTelefono(widget.controller.text);
    _pais = partido.pais;
    _localCtl.text = partido.local;
    _ultimoValorPropio = widget.controller.text;
  }

  void _externoCambio() {
    // Si el cambio de afuera es justo el que nosotros mismos acabamos de
    // escribir en _sincronizar(), no hay nada que releer — evita un loop
    // infinito entre este listener y el de _localCtl.
    if (widget.controller.text == _ultimoValorPropio) return;
    setState(_cargarDesdeControladorExterno);
  }

  void _sincronizar() {
    final local = _localCtl.text.trim();
    _ultimoValorPropio = local.isEmpty ? '' : '+${_pais.indicativo} $local';
    widget.controller.text = _ultimoValorPropio;
  }

  void _cambiarPais(Pais? p) {
    if (p == null) return;
    setState(() => _pais = p);
    _sincronizar();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_externoCambio);
    _localCtl.removeListener(_sincronizar);
    _localCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SelectorPais(pais: _pais, onChanged: _cambiarPais),
      const SizedBox(width: 8),
      Expanded(
        child: widget.decoracionLocal != null
            ? TextField(
                controller: _localCtl,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ()-]'))],
                decoration: widget.decoracionLocal,
              )
            : perfilCampo(_localCtl, 'ej. 300 123 4567',
                tipo: TextInputType.phone,
                autofocus: widget.autofocus,
                formato: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ()-]'))]),
      ),
    ]);
  }
}

class _SelectorPais extends StatelessWidget {
  final Pais pais;
  final void Function(Pais?) onChanged;
  const _SelectorPais({required this.pais, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Pais>(
          value: pais,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          borderRadius: BorderRadius.circular(12),
          items: paisesHispanohablantes.map((p) => DropdownMenuItem(
                value: p,
                child: Text('${p.bandera} ${p.nombre}  +${p.indicativo}',
                    style: const TextStyle(fontSize: 13)),
              )).toList(),
          selectedItemBuilder: (_) => paisesHispanohablantes
              .map((p) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${p.bandera} +${p.indicativo}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Normaliza lo que la persona haya escrito en "Página web" (con o sin
/// "http(s)://", con o sin "www.") a una URL abrible — si no escribió nada
/// con esquema, se le antepone "https://" antes de abrirla.
String sitioWebUrl(String sitioWeb) {
  final limpio = sitioWeb.trim();
  return limpio.startsWith('http://') || limpio.startsWith('https://')
      ? limpio
      : 'https://$limpio';
}

// ─── Constantes de color ──────────────────────────────────────────────────────

const appBg     = Color(0xFFDFFBEC);
const appDark   = Color(0xFF162416);
const appTeal   = Color(0xFF1F8A62);
const appOrange = Color(0xFFD84E18);
// El negro casi puro que en la práctica se usa para casi todo el texto de
// la app (0xFF1A1A1A) — antes escrito a mano en decenas de lugares, sin
// ningún token que lo agrupara (a diferencia de appDark, que existía pero
// casi no se usaba). Mismo valor exacto, solo con nombre — no cambia
// ningún color en pantalla, unifica cómo se referencia.
const appInk    = Color(0xFF1A1A1A);

// ─── Colores semánticos para SnackBars ───────────────────────────────────────
// Antes, de 72 SnackBars en toda la app, solo 6 tenían un color puesto a
// propósito (appTeal para éxito, naranja suelto para "pasó pero a medias")
// — el resto caía en el gris casi negro por default de Flutter, sin ningún
// criterio: un error de conexión, un campo faltante y "publicación
// eliminada" se veían todos igual (lo que notó Eliza probando: "sale el
// mensaje negro ese feo"). Estos 3 nombres son el criterio único de acá en
// más — msgError para lo que bloqueó la acción, msgAdvertencia para lo que
// pasó pero quedó a medias, msgExito para confirmaciones. Reusan colores
// que la app ya tenía (el rojo de Eliminar/urgente, el naranja de marca, y
// el verde de siempre) — no son colores nuevos.
const msgError       = Color(0xFFD32F2F);
const msgAdvertencia = appOrange;
const msgExito       = appTeal;

// ─── Ícono/color por tipo de negocio aliado ──────────────────────────────────
// Un solo mapeo, reutilizado en la grilla de "Negocios aliados"
// (adoptante_feed_screen.dart) y en el encabezado del perfil público del
// aliado — así el mismo tipo (ej. "Veterinaria") se ve siempre con el mismo
// ícono en toda la app, en vez de repetir un switch en cada pantalla.
// Colores pastel (no los saturados de un mockup de referencia) para que
// combinen con el resto de la paleta de la app en vez de competir con ella.
IconData aliadoTipoIcono(String tipo) => switch (tipo) {
  'Veterinaria'        => Icons.medical_services_outlined,
  'Tienda de mascotas' => Icons.shopping_bag_outlined,
  'Spa canino'         => Icons.self_improvement,
  'Peluquería canina'  => Icons.content_cut,
  _                    => Icons.pets,
};

Color aliadoTipoColorPastel(String tipo) => switch (tipo) {
  'Veterinaria'        => const Color(0xFFD8ECE6),
  'Tienda de mascotas' => const Color(0xFFFBE3D3),
  'Spa canino'         => const Color(0xFFE6DFF4),
  'Peluquería canina'  => const Color(0xFFFAE0E7),
  _                    => const Color(0xFFE7EFEA),
};

Color aliadoTipoColorTexto(String tipo) => switch (tipo) {
  'Veterinaria'        => appTeal,
  'Tienda de mascotas' => const Color(0xFFB0501C),
  'Spa canino'         => const Color(0xFF6C4FA0),
  'Peluquería canina'  => const Color(0xFFC2447A),
  _                    => const Color(0xFF5F6F68),
};

// ─── Umbral de "animal estancado" ────────────────────────────────────────────
// Cuántos días sin encontrar hogar antes de mostrar el aviso naranja en
// mis_rescates_screen.dart. Configurable por cada rescatista/albergue desde
// su perfil (pedido explícito de Eliza — antes eran 30 días fijos para
// todos) y guardado en `usuarios/{uid}.umbralEstancadoDias`. El umbral
// "urgente" (rojo) no es una segunda configuración: se deriva como el
// doble del elegido, misma proporción 30/60 que tenía el valor fijo.
const umbralEstancadoDefault = 30;
const umbralEstancadoOpciones = [
  (15,  '15 días'),
  (30,  '30 días'),
  (60,  '2 meses'),
  (90,  '3 meses'),
  (180, '6 meses'),
  (365, '1 año y más'),
];

int umbralEstancadoDe(Map<String, dynamic>? datosUsuario) =>
    (datosUsuario?['umbralEstancadoDias'] as int?) ?? umbralEstancadoDefault;

// ─── Chip de especie (Todos/Perros/Gatos/Otros) ──────────────────────────────
// Un solo widget y una sola lista de opciones, reutilizados en el feed
// (adoptante_feed_screen.dart) y en el perfil (tipo_animal_screen.dart) para
// la misma preferencia (`prefEspecie`) — antes el perfil tenía su propio
// estilo (pastillas negro/blanco, sin íconos) y su propio orden distinto al
// del feed, dos versiones visualmente distintas de lo mismo (lo que notó
// Eliza: "lindos en un lado, feos en el perfil").
//
// El valor real (lo que se guarda y se compara) va primero en cada tupla;
// el label (con su emoji) es solo lo que se muestra — así "Ambos" se sigue
// guardando igual que siempre aunque en pantalla diga "Todos".
const especieOpciones = [
  ('Ambos', 'Todos'),
  ('Perro', '🐕 Perros'),
  ('Gato',  '🐈 Gatos'),
  ('Otro',  '🐾 Otros'),
];

// Espacio entre chips — un solo número compartido por el feed y el perfil,
// junto con el padding/letra de acá abajo, para que los 4 (Todos/Perros/
// Gatos/Otros) entren sin deslizar en la mayoría de los teléfonos (antes
// con padding 14/letra 12.5 el cuarto chip quedaba cortado y había que
// deslizar — sugerencia real de Eliza).
const especieChipGap = 6.0;

Widget especieChip({required String label, required bool active, required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? appTeal : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? appTeal : Colors.grey.shade300),
      ),
      child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
          color: active ? Colors.white : appInk)),
    ),
  );
}

// ─── Campos de las pantallas "Configura tu albergue"/"Configura tu negocio" ──
// Antes cada pantalla tenía su propia versión: albergue con label gris
// arriba del campo, aliado con ícono + label flotante adentro. Un solo
// estilo para las dos (Eliza las comparó una al lado de la otra y pidió
// que se vean igual) — texto oscuro en vez del gris apagado que tenía
// albergue, que es lo que a ella más le gustó de las dos.
Widget perfilLabel(String texto) => Text(texto,
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
        letterSpacing: 1.1, color: appDark));

Widget perfilCampo(
  TextEditingController ctl,
  String hint, {
  TextInputType tipo = TextInputType.text,
  List<TextInputFormatter> formato = const [],
  bool autofocus = false,
  void Function(String)? onChanged,
}) =>
    TextField(
      controller: ctl,
      keyboardType: tipo,
      inputFormatters: formato,
      autofocus: autofocus,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: appTeal, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );

// ─── Paw print painter ───────────────────────────────────────────────────────

class _PawPrintPainter extends CustomPainter {
  final Color color;
  const _PawPrintPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..style = PaintingStyle.fill;
    double x(double v) => v * size.width  / 100;
    double y(double v) => v * size.height / 100;

    // Main pad — large rounded oval at the bottom
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x(50), y(72)), width: x(54), height: y(46)),
      p,
    );
    // Four toe pads arranged in an arc above the main pad
    canvas.drawOval(Rect.fromCenter(center: Offset(x(16), y(42)), width: x(22), height: y(26)), p);
    canvas.drawOval(Rect.fromCenter(center: Offset(x(37), y(26)), width: x(25), height: y(29)), p);
    canvas.drawOval(Rect.fromCenter(center: Offset(x(63), y(26)), width: x(25), height: y(29)), p);
    canvas.drawOval(Rect.fromCenter(center: Offset(x(84), y(42)), width: x(22), height: y(26)), p);
  }

  @override
  bool shouldRepaint(covariant _PawPrintPainter old) => old.color != color;
}

// ─── Fondo con patitas ────────────────────────────────────────────────────────

Widget _hoja(double w, double op, {bool fx = false, bool fy = false}) =>
  Transform(
    alignment: Alignment.center,
    transform: Matrix4.diagonal3Values(fx ? -1.0 : 1.0, fy ? -1.0 : 1.0, 1.0),
    child: CustomPaint(
      size: Size(w, w),
      painter: _PawPrintPainter(appTeal.withValues(alpha: op * 0.38)),
    ),
  );

class LeafOverlay extends StatelessWidget {
  const LeafOverlay({super.key});
  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned(top: -28, left: -28,  child: _hoja(170, 0.82)),
    Positioned(top: -28, right: -28, child: _hoja(170, 0.82, fx: true)),
    Positioned(bottom: -28, left: -28,  child: _hoja(140, 0.60, fy: true)),
    Positioned(bottom: -28, right: -28, child: _hoja(140, 0.60, fx: true, fy: true)),
  ]);
}

Widget leafBackground({required Widget child}) => Stack(
  children: [
    Positioned.fill(child: Container(color: appBg)),
    Positioned(top: -28, left: -28,  child: _hoja(170, 0.82)),
    Positioned(top: -28, right: -28, child: _hoja(170, 0.82, fx: true)),
    Positioned(bottom: -28, left: -28,  child: _hoja(140, 0.60, fy: true)),
    Positioned(bottom: -28, right: -28, child: _hoja(140, 0.60, fx: true, fy: true)),
    child,
  ],
);

// ─── Helpers globales ─────────────────────────────────────────────────────────

/// Para cuando un StreamBuilder falla (sin conexión, permiso denegado, etc.)
/// — sin esto, `snap.data?.docs ?? []` hace que la pantalla se vea igual que
/// "no hay nada todavía", confundiendo un error real con una lista vacía.
Widget errorFeedState({String mensaje = 'No se pudo cargar. Revisá tu conexión e intentá de nuevo.'}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(mensaje, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4)),
      ]),
    ),
  );
}

/// Decodifica un string base64 de forma segura — devuelve `null` en vez de
/// tirar una excepción si el string está corrupto o incompleto (ej. una
/// subida de foto que se cortó a la mitad). Usar antes de armar un
/// `MemoryImage`/`DecorationImage` a mano, para poder caer al fallback
/// (inicial/emoji) en vez de crashear.
Uint8List? bytesFotoSegura(String? base64) {
  if (base64 == null || base64.isEmpty) return null;
  try {
    return base64Decode(base64);
  } catch (_) {
    return null;
  }
}

/// Muestra una foto guardada en base64 de forma segura: si el string está
/// corrupto, o los bytes no son una imagen válida, muestra [fallback] en vez
/// de crashear la pantalla que la contiene. Antes cada pantalla decodificaba
/// `base64Decode(...)` a mano sin ninguna protección — un solo dato corrupto
/// (una subida interrumpida, por ejemplo) tumbaba toda la pantalla.
class FotoSegura extends StatelessWidget {
  final String base64;
  final Widget fallback;
  final double? width;
  final double? height;
  final BoxFit fit;
  const FotoSegura({
    super.key,
    required this.base64,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = bytesFotoSegura(base64);
    if (bytes == null) return fallback;
    return Image.memory(
      bytes,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// Muestra una foto alojada en Firebase Storage (`url`) de forma segura:
/// mientras carga, un indicador liviano; si la red falla o la URL ya no es
/// válida, [fallback] en vez de crashear. Mismo contrato que [FotoSegura]
/// (base64) para minimizar el diff en cada pantalla — se usa para fotos de
/// animales (`rescates`), que viven en Storage y no embebidas en Firestore.
class FotoUrl extends StatelessWidget {
  final String url;
  final Widget fallback;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  const FotoUrl({
    super.key,
    required this.url,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: width,
          height: height,
          child: const Center(
            child: SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: appTeal),
            ),
          ),
        );
      },
    );
  }
}

/// Foto de animal a prueba de CUALQUIER encuadre: muestra la foto COMPLETA
/// (BoxFit.contain, nunca recorta) y rellena las franjas sobrantes con la
/// misma foto ampliada y desenfocada de fondo — la técnica estándar de las
/// apps de fotos para encajar cualquier proporción en cualquier recuadro.
///
/// Existe porque ningún recorte fijo funciona para todas las fotos: el
/// ancla arriba (Alignment.topCenter) salva a la mayoría (la cara suele
/// estar cerca del borde superior) pero rompe fotos con el animal abajo —
/// el bug real de "Tobyiii": un retrato vertical con el gato al fondo del
/// mueble se veía como un mueble vacío en el feed, el detalle y favoritos.
/// Con esta técnica el animal se ve entero SIEMPRE, sin elegir recorte,
/// sin datos nuevos por foto y sin migrar las fotos existentes. Cuando la
/// proporción de la foto ya calza con la del recuadro, el fondo borroso
/// queda tapado por completo — se ve igual que antes.
///
/// Para miniaturas chicas (avatares de 64px en listas) conviene seguir
/// usando [FotoUrl] con recorte: a ese tamaño el desenfoque se vuelve
/// ruido y el recorte no molesta.
class FotoAnimal extends StatelessWidget {
  final String url;
  final Widget fallback;
  final double? width;
  final double? height;
  const FotoAnimal({
    super.key,
    required this.url,
    required this.fallback,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      // ClipRect: el fondo cover se desborda del recuadro a propósito
      // (para que el blur no muestre bordes transparentes) — sin el clip,
      // pintaría encima de lo que rodee al widget.
      child: ClipRect(
        child: Stack(fit: StackFit.expand, children: [
          // Fondo: misma foto, estirada a cubrir y desenfocada. Una sola
          // descarga real: Image.network con la misma URL comparte el
          // caché de imágenes de Flutter entre las dos capas.
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: TileMode.clamp),
            child: FotoUrl(url: url, fit: BoxFit.cover, fallback: fallback),
          ),
          // Velo suave para que el fondo no compita con la foto nítida.
          Container(color: Colors.black.withValues(alpha: 0.12)),
          // La foto de verdad, entera. Sin fallback propio: si la carga
          // falla, ya lo muestra la capa de fondo — dos fallbacks apilados
          // se verían duplicados.
          FotoUrl(url: url, fit: BoxFit.contain, fallback: const SizedBox.shrink()),
        ]),
      ),
    );
  }
}

/// Avatar de una persona (foto de perfil en base64 o URL). Si la foto falla
/// al cargar, cae a la inicial en vez de romper con una excepción sin
/// manejar o quedar en blanco. Antes esta lógica vivía duplicada como
/// `_AvatarPublicador` solo en el feed del adoptante — el mismo problema
/// (foto que no carga = pantalla rota) aplica a cualquier avatar de foto
/// real, así que se promovió acá para reutilizarla (ej. en el chat).
class AvatarPersona extends StatefulWidget {
  final String? fotoBase64;
  final String? fotoUrl;
  final String inicial;
  final double radius;
  final Color backgroundColor;
  final Color textColor;
  const AvatarPersona({
    super.key,
    this.fotoBase64,
    this.fotoUrl,
    required this.inicial,
    this.radius = 20,
    this.backgroundColor = appTeal,
    this.textColor = Colors.white,
  });

  @override
  State<AvatarPersona> createState() => _AvatarPersonaState();
}

class _AvatarPersonaState extends State<AvatarPersona> {
  bool _falloCarga = false;

  @override
  Widget build(BuildContext context) {
    final fotoBytes = bytesFotoSegura(widget.fotoBase64);
    final ImageProvider? foto = fotoBytes != null
        ? MemoryImage(fotoBytes)
        : widget.fotoUrl != null
            ? NetworkImage(widget.fotoUrl!)
            : null;
    final mostrarFoto = foto != null && !_falloCarga;
    return CircleAvatar(
      backgroundColor: widget.backgroundColor,
      radius: widget.radius,
      backgroundImage: mostrarFoto ? foto : null,
      onBackgroundImageError: mostrarFoto
          ? (_, _) {
              if (mounted) setState(() => _falloCarga = true);
            }
          : null,
      child: !mostrarFoto
          ? Text(widget.inicial,
              style: TextStyle(color: widget.textColor, fontSize: widget.radius * 0.65, fontWeight: FontWeight.bold))
          : null,
    );
  }
}

/// Avatar de OTRO usuario de la app, identificado por su uid — busca su foto
/// en usuarios/{userId}.foto (Google Auth photoURL, sincronizado en
/// main.dart). Si [campoLogoNegocio] no es null, prioriza ese campo (el logo
/// que un albergue/aliado sube a propósito desde su perfil) sobre esa foto
/// personal.
///
/// [campoLogoNegocio] es el NOMBRE del campo a leer, no un booleano, porque
/// cada rol de negocio guarda su logo en un campo propio dentro del MISMO
/// doc usuarios/{uid}: 'fotoBase64' es el logo de albergue,
/// 'aliadoFotoBase64' el de aliado — una cuenta puede tener varios roles de
/// negocio a la vez (ver ARCHITECTURE.md), así que "mostrar el logo" no
/// alcanza, hay que decir CUÁL. Pasar el campo equivocado (o forzar siempre
/// 'fotoBase64') es cómo un chat de consulta a un aliado terminaba
/// mostrando la foto personal de la cuenta en vez del logo del negocio: ese
/// logo vivía en 'aliadoFotoBase64' y nadie lo estaba pidiendo. null =
/// mostrar siempre la foto personal.
///
/// Antes cada pantalla que necesitaba mostrar la foto de una contraparte
/// (encabezado del chat, tarjeta de solicitud, fila de la lista de
/// conversaciones) usaba la foto de la cuenta ACTUALMENTE logueada por
/// error — se centraliza acá para no repetir el mismo bug en cada pantalla
/// nueva.
class AvatarUsuario extends StatefulWidget {
  final String? userId;
  final String inicial;
  final double radius;
  final Color backgroundColor;
  final Color textColor;
  final String? campoLogoNegocio;
  const AvatarUsuario({
    super.key,
    required this.userId,
    required this.inicial,
    this.radius = 20,
    this.backgroundColor = appTeal,
    this.textColor = Colors.white,
    this.campoLogoNegocio,
  });

  @override
  State<AvatarUsuario> createState() => _AvatarUsuarioState();
}

class _AvatarUsuarioState extends State<AvatarUsuario> {
  late final Future<(String?, String?)> _foto = _cargar();

  Future<(String?, String?)> _cargar() async {
    final id = widget.userId;
    if (id == null || id.isEmpty) return (null, null);
    try {
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(id).get();
      final data = doc.data();
      final campo = widget.campoLogoNegocio;
      final fotoBase64 = campo != null ? (data?[campo] as String?) : null;
      return (fotoBase64, data?['foto'] as String?);
    } catch (_) {
      return (null, null);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<(String?, String?)>(
    future: _foto,
    builder: (context, snap) => AvatarPersona(
      fotoBase64: snap.data?.$1,
      fotoUrl: snap.data?.$2,
      inicial: widget.inicial,
      radius: widget.radius,
      backgroundColor: widget.backgroundColor,
      textColor: widget.textColor,
    ),
  );
}

Color cicloColor(String s) => switch (s) {
  'En cuidado'             => appTeal,
  'Rescatado'              => appTeal,
  'Hogar de paso'          => const Color(0xFF7C6FCD),
  'En proceso de adopción' => const Color(0xFFE65100),
  'Adoptado'               => const Color(0xFF2196F3),
  'Regresado'              => const Color(0xFFD32F2F),
  'Fallecido'              => const Color(0xFF78909C),
  'Estancados'             => appOrange,
  _                        => Colors.grey,
};

// ─── Cambiar Estado Adopción Sheet ────────────────────────────────────────────

class CambiarEstadoSheet extends StatelessWidget {
  final String docId;
  final String estadoActual;
  final String nombre;
  final String? adoptanteIdEnProceso;
  const CambiarEstadoSheet({
    super.key,
    required this.docId,
    required this.estadoActual,
    this.nombre = '',
    this.adoptanteIdEnProceso,
  });

  /// Único punto de escritura del estado — pasa por
  /// [RescatesRepository.cambiarEstadoAdopcion] (ver ARCHITECTURE.md) y
  /// avisa si falla, en vez del `.update()` suelto y sin manejar de antes
  /// (si fallaba, el sheet ya se había cerrado como si hubiera funcionado,
  /// sin ningún aviso).
  Future<bool> _actualizarEstado(BuildContext context, String nuevoEstado, {
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      await RescatesRepository().cambiarEstadoAdopcion(docId, nuevoEstado, extra: extra);
      return true;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: msgError,
            content: Text('No se pudo actualizar el estado. Intentá de nuevo.')));
      }
      return false;
    }
  }

  Future<void> _avisarAdoptanteFallecido(String nota) async {
    final adoptanteId = adoptanteIdEnProceso;
    if (adoptanteId == null || adoptanteId.isEmpty || nombre.isEmpty) return;
    // docId es el id único del rescate (el mismo animal), así que el chat se
    // ubica directo por id en vez de buscarlo por nombre (que puede repetirse).
    final chatDoc = await FirebaseFirestore.instance.collection('chats')
        .doc(ChatsRepository().idAnimal(rescateId: docId, adoptanteId: adoptanteId)).get();
    String? chatId = chatDoc.exists ? chatDoc.id : null;
    if (chatId == null) {
      final chats = await FirebaseFirestore.instance.collection('chats')
          .where('adoptanteId', isEqualTo: adoptanteId)
          .where('animalNombre', isEqualTo: nombre)
          .limit(1).get();
      if (chats.docs.isEmpty) return;
      chatId = chats.docs.first.id;
    }
    final n = DateTime.now();
    final hora = '${n.hour}:${n.minute.toString().padLeft(2, '0')}';
    final texto = 'Lamentamos informarte que $nombre falleció. '
        'Gracias por tu interés en darle un hogar. 🌈'
        '${nota.isNotEmpty ? '\n\n$nota' : ''}';
    await FirebaseFirestore.instance.collection('chats').doc(chatId)
        .collection('mensajes').add({
      'texto': texto, 'emisor': 'rescatista', 'hora': hora,
      'creadoEn': FieldValue.serverTimestamp(),
    });
    await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
      'ultimoMensaje': texto, 'ultimaHora': hora,
      'ultimoMensajeEn': FieldValue.serverTimestamp(),
      'noLeidosAdoptante': FieldValue.increment(1),
    });
  }

  static const _estados = [
    ('Rescatado',              '🟢', 'Disponible para adopción'),
    ('Hogar de paso',          '🟣', 'Temporalmente con un cuidador'),
    ('En proceso de adopción', '🟠', 'Tiene una solicitud activa'),
    ('Adoptado',               '🔵', 'Ya encontró su hogar'),
    ('Regresado',              '🔴', 'Fue devuelto, disponible de nuevo'),
    ('Fallecido',              '🌈', 'Ya no está con nosotros'),
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Container(width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 16),
      const Text('Estado del animal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text('Toca para cambiar el estado', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      const SizedBox(height: 16),
      ..._estados.map((e) {
        final sel = e.$1 == estadoActual;
        return GestureDetector(
          onTap: () async {
            if (e.$1 != 'Regresado' && e.$1 != 'Fallecido') {
              final ok = await _actualizarEstado(context, e.$1, extra: {
                if (e.$1 == 'Adoptado') 'fechaAdopcion': FieldValue.serverTimestamp(),
              });
              if (ok && context.mounted) Navigator.pop(context);
              return;
            }
            final esFallecido = e.$1 == 'Fallecido';
            final ctrl = TextEditingController();
            final sheetCtx = context;
            // .then() en vez de un dispose() suelto después de showDialog:
            // este showDialog no se espera (el onTap sigue corriendo, no es
            // async void bloqueado acá), así que un dispose() puesto justo
            // debajo se ejecutaría ANTES de que la persona llegue a escribir
            // nada. .then() sí espera a que el diálogo se cierre de verdad
            // (Cancelar o Guardar, los dos hacen Navigator.pop), sea cual
            // sea el camino — recién ahí libera el controller.
            showDialog(
              context: context,
              builder: (dlgCtx) => AlertDialog(
                title: Text(esFallecido ? 'Lo sentimos mucho 🌈' : '¿Por qué fue regresado?'),
                content: TextField(
                  controller: ctrl,
                  maxLines: 3,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: esFallecido
                        ? 'Puedes dejar una nota sobre este angelito...'
                        : 'Ej: Incompatibilidad con otros animales, mudanza...',
                    border: const OutlineInputBorder(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dlgCtx),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: esFallecido
                            ? const Color(0xFF78909C)
                            : const Color(0xFFD32F2F)),
                    onPressed: () async {
                      final motivo = ctrl.text.trim();
                      Navigator.pop(dlgCtx);
                      final ok = await _actualizarEstado(sheetCtx, e.$1, extra: {
                        if (esFallecido && motivo.isNotEmpty)
                          'notaFallecido': motivo
                        else if (!esFallecido)
                          'motivoRegreso': motivo,
                      });
                      if (esFallecido && ok) _avisarAdoptanteFallecido(motivo);
                      if (ok && sheetCtx.mounted) Navigator.pop(sheetCtx);
                    },
                    child: const Text('Guardar', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ).then((_) => ctrl.dispose());
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: sel ? cicloColor(e.$1).withValues(alpha: 0.1) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? cicloColor(e.$1) : Colors.grey.shade200, width: sel ? 2 : 1),
            ),
            child: Row(children: [
              Text(e.$2, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.$1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: sel ? cicloColor(e.$1) : appInk)),
                Text(e.$3, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ])),
              if (sel) Icon(Icons.check_circle, color: cicloColor(e.$1), size: 20),
            ]),
          ),
        );
      }),
    ]),
  );
}
