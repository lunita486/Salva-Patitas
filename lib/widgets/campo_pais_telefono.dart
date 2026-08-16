import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import 'campos_perfil.dart';

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

/// Bandera del país a partir de su código ISO de 2 letras ('AR' → 🇦🇷), o
/// string vacío si el código no sirve.
///
/// Se calcula, no se busca en una tabla: cada letra se corre al símbolo
/// indicador regional que le corresponde, que es exactamente cómo se
/// componen las banderas en Unicode. Así funciona para CUALQUIER país sin
/// mantener una lista (paisesHispanohablantes de acá abajo es otra cosa:
/// son los indicativos telefónicos, y solo cubre los que la app ofrece).
///
/// Para qué: la tarjeta del feed mostraba solo el nombre de la ciudad, y
/// "Córdoba" puede ser la de Argentina o la de España. Con la bandera al
/// lado, una ciudad mal geocodificada se ve de una en vez de esconderse
/// detrás de una distancia rara. Pedido real de Eliza.
String banderaPais(String? isoPais) {
  final iso = (isoPais ?? '').trim().toUpperCase();
  if (iso.length != 2) return '';
  const primeraLetra = 0x41; // 'A'
  const primerIndicador = 0x1F1E6; // 🇦
  final unidades = <int>[];
  for (final letra in iso.codeUnits) {
    if (letra < primeraLetra || letra > primeraLetra + 25) return '';
    unidades.add(primerIndicador + (letra - primeraLetra));
  }
  return String.fromCharCodes(unidades);
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SelectorPais(pais: _pais, onChanged: _cambiarPais),
        const SizedBox(width: 8),
        Expanded(
          child: widget.decoracionLocal != null
              ? TextField(
                  controller: _localCtl,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 ()-]')),
                  ],
                  decoration: widget.decoracionLocal,
                )
              : perfilCampo(
                  _localCtl,
                  'ej. 300 123 4567',
                  tipo: TextInputType.phone,
                  autofocus: widget.autofocus,
                  formato: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 ()-]')),
                  ],
                ),
        ),
      ],
    );
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Pais>(
          value: pais,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          borderRadius: BorderRadius.circular(12),
          items: paisesHispanohablantes
              .map(
                (p) => DropdownMenuItem(
                  value: p,
                  child: Text(
                    '${p.bandera} ${p.nombre}  +${p.indicativo}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              )
              .toList(),
          selectedItemBuilder: (_) => paisesHispanohablantes
              .map(
                (p) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${p.bandera} +${p.indicativo}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
