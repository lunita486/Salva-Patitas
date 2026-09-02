import 'package:flutter/material.dart';

import '../domain/reglas_negocio.dart';
import '../theme.dart';

/// Los datos de un hogar de paso puesto a mano desde el desplegable de
/// estado.
typedef DatosHogarDePaso = ({
  DateTime desde,
  DateTime hasta,
  String nombre,
  String contacto,
});

/// Pide quién se lleva al animalito y hasta cuándo.
///
/// **Por qué existe.** Marcar "Hogar de paso" desde el desplegable escribía
/// solamente el estado, sin fechas ni cuidador. Eso dejaba tres cosas rotas
/// a la vez, en silencio: el recordatorio de vencimiento nunca se disparaba
/// (avisos_vencimiento.js saltea lo que no tiene fecha), la tarjeta no
/// mostraba el período, y no había a quién contactar. El estado quedaba
/// como una etiqueta suelta.
///
/// **Por qué a mano y no solo desde una solicitud.** Porque así funciona un
/// refugio de verdad: la mayoría de los hogares de paso son personas que
/// ayudan y que nunca van a instalar la app. Obligar a que cada uno tenga
/// cuenta habría roto el caso más común. Es el mismo criterio que usan los
/// sistemas de gestión de refugios: el cuidador es un contacto, no un
/// usuario.
///
/// Devuelve `null` si se canceló.
///
/// El diálogo es dueño de sus propios controllers, igual que
/// [pedirMotivo] y por el mismo motivo: crearlos afuera y liberarlos con
/// `.then()` sobre el `showDialog` los destruía mientras el campo todavía
/// estaba en pantalla animándose hacia afuera, y Flutter pintaba su
/// pantalla roja de error por lo que durara la animación.
Future<DatosHogarDePaso?> pedirHogarDePaso(
  BuildContext context, {
  required bool pedirEmail,
}) => showDialog<DatosHogarDePaso>(
  context: context,
  builder: (_) => _DialogoHogarDePaso(pedirEmail: pedirEmail),
);

class _DialogoHogarDePaso extends StatefulWidget {
  const _DialogoHogarDePaso({required this.pedirEmail});

  /// Un albergue guarda al cuidador en su red de hogares de paso, y esa red
  /// une a la misma persona entre animalitos por el email. Un rescatista no
  /// tiene red, así que le alcanza con un teléfono o un email sueltos.
  final bool pedirEmail;

  @override
  State<_DialogoHogarDePaso> createState() => _DialogoHogarDePasoState();
}

class _DialogoHogarDePasoState extends State<_DialogoHogarDePaso> {
  final _nombreCtl = TextEditingController();
  final _contactoCtl = TextEditingController();
  DateTime? _desde;
  DateTime? _hasta;
  String? _avisoContacto;

  @override
  void dispose() {
    _nombreCtl.dispose();
    _contactoCtl.dispose();
    super.dispose();
  }

  /// El nombre y las dos fechas son lo mínimo: sin fechas no hay
  /// recordatorio, que es justo lo que veníamos a arreglar.
  ///
  /// El contacto es obligatorio **solo cuando se pide el email**, o sea del
  /// lado del albergue. Ahí ese dato no es un extra: es la identidad de la
  /// persona en la red de hogares. Sin él, [buscarDuplicado] no tiene con
  /// qué comparar y crea una fila nueva cada vez que la misma persona
  /// cuida a otro animalito. Medido en producción el 2026-09-02: 5 de 13
  /// filas de la red sin email. Y el formulario de "Agregar" de
  /// hogares_de_paso_screen.dart ya lo exigía, así que las dos puertas a
  /// la MISMA red pedían cosas distintas.
  ///
  /// Del lado del rescatista sigue opcional: su campo es "Teléfono o
  /// email", no alimenta ninguna red, y solo se muestra en la tarjeta.
  bool get _completo =>
      _nombreCtl.text.trim().isNotEmpty &&
      _desde != null &&
      _hasta != null &&
      (!widget.pedirEmail || _contactoCtl.text.trim().isNotEmpty);

  Future<void> _elegirFecha({required bool esDesde}) async {
    final hoy = DateTime.now();
    final base = esDesde ? (_desde ?? hoy) : (_hasta ?? _desde ?? hoy);
    // El "hasta" nunca puede ser anterior al "desde": si lo fuera, el
    // animalito nacería con el hogar de paso ya vencido.
    final minimo = esDesde ? hoy : (_desde ?? hoy);
    final elegida = await showDatePicker(
      context: context,
      initialDate: base.isBefore(minimo) ? minimo : base,
      firstDate: minimo,
      lastDate: hoy.add(const Duration(days: 365 * 2)),
    );
    if (elegida == null) return;
    setState(() {
      if (esDesde) {
        _desde = elegida;
        if (_hasta != null && _hasta!.isBefore(elegida)) _hasta = null;
      } else {
        _hasta = elegida;
      }
    });
  }

  void _confirmar() {
    final contacto = _contactoCtl.text.trim();
    // Si escribió algo, tiene que tener forma de email cuando es lo que se
    // le pidió: un email mal escrito en la red del albergue rompe la
    // fusión por email de registrarAyuda(), y esa persona termina
    // duplicada.
    if (widget.pedirEmail && contacto.isNotEmpty && !esEmailValido(contacto)) {
      setState(() => _avisoContacto = avisoEmailInvalido);
      return;
    }
    Navigator.pop(context, (
      desde: _desde!,
      hasta: _hasta!,
      nombre: _nombreCtl.text.trim(),
      contacto: contacto,
    ));
  }

  Widget _campoFecha({required bool esDesde}) {
    final valor = esDesde ? _desde : _hasta;
    return Expanded(
      child: InkWell(
        onTap: () => _elegirFecha(esDesde: esDesde),
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: esDesde ? 'Desde' : 'Hasta',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          child: Text(
            valor == null ? 'Seleccionar' : formatearFecha(valor),
            style: TextStyle(
              color: valor == null ? Colors.grey.shade600 : appInk,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('¿Quién lo va a cuidar?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nombreCtl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              onChanged: (_) => setState(() {}),
              // Sin `isDense`. Con OutlineInputBorder la etiqueta flotante se
              // dibuja ENCIMA del borde, en un hueco que Flutter le recorta;
              // `isDense` achica el relleno del campo y, con la letra del
              // sistema agrandada, la etiqueta ya no entra en ese hueco y se
              // ve cortada por arriba. Hallazgo de Eliza: "Nombre de la
              // persona" aparecia con la mitad de arriba comida.
              //
              // Se nota solo cuando la etiqueta FLOTA (campo con foco o con
              // texto): vacio y sin foco va adentro del campo y entra bien.
              // Por eso el de al lado se veia entero en la misma captura.
              decoration: const InputDecoration(
                labelText: 'Nombre de la persona',
                hintText: 'Ej: María González',
                border: OutlineInputBorder(),
              ),
            ),
            TextField(
              controller: _contactoCtl,
              maxLength: 80,
              keyboardType: widget.pedirEmail
                  ? TextInputType.emailAddress
                  : TextInputType.text,
              onChanged: (_) => setState(() => _avisoContacto = null),
              decoration: InputDecoration(
                labelText: widget.pedirEmail
                    ? 'Email'
                    : 'Teléfono o email (opcional)',
                // Mas corto, mismo significado: entraba en dos renglones y
                // el contador de maxLength (abajo a la derecha, que es donde
                // Material lo pone) quedaba amontonado contra el.
                helperText: widget.pedirEmail
                    ? 'Este email se agrega a la red de hogares.'
                    : null,
                helperMaxLines: 2,
                errorText: _avisoContacto,
                // Sin `isDense`, mismo motivo que el campo de arriba.
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _campoFecha(esDesde: true),
                const SizedBox(width: 10),
                _campoFecha(esDesde: false),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Con las fechas te avisamos cuando esté por vencer.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _completo ? _confirmar : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
