import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../theme.dart';
import '../data/creator_role.dart';
import '../data/solicitudes_repository.dart';

class SolicitudAdopcionScreen extends StatefulWidget {
  final Map<String, dynamic> animal;
  const SolicitudAdopcionScreen({super.key, required this.animal});
  @override
  State<SolicitudAdopcionScreen> createState() => _SolicitudAdopcionScreenState();
}

class _SolicitudAdopcionScreenState extends State<SolicitudAdopcionScreen> {
  final _solicitudesRepo = SolicitudesRepository();
  int _step = 0;

  String _vivienda          = '';
  String _ninos             = '';
  String _mascotas          = '';
  String _experienciaPrevia = '';
  final  _integrantesCtl = TextEditingController();
  final  _horasCtl       = TextEditingController();
  final  _motivacionCtl  = TextEditingController();
  late String _tipoSolicitud;
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  bool   _enviando        = false;
  bool   _verificando     = true;
  bool   _yaAplico        = false;
  String _estadoExistente = '';

  @override
  void initState() {
    super.initState();
    _tipoSolicitud = (widget.animal['tipoSolicitud'] as String?) == 'hogar_de_paso'
        ? 'hogar_de_paso'
        : 'adopcion';
    _verificarDuplicado();
  }

  Future<void> _verificarDuplicado() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _verificando = false);
      return;
    }
    final estado = await _solicitudesRepo.estadoExistente(
      uid: uid,
      animalNombre: widget.animal['nombre'] as String,
    );
    if (mounted) {
      setState(() {
        _yaAplico        = estado != null;
        _estadoExistente = estado ?? '';
        _verificando     = false;
      });
    }
  }

  static const _viviendaOpts   = ['Casa con jardín', 'Apartamento con balcón', 'Apartamento sin área exterior'];
  static const _ninosOpts      = ['Sí', 'No'];
  static const _mascotasOpts   = ['Sí', 'No'];
  static const _experienciaOpts = ['Sí', 'No, sería mi primera mascota'];

  bool get _completo =>
      _integrantesCtl.text.trim().isNotEmpty &&
      _horasCtl.text.trim().isNotEmpty &&
      _vivienda.isNotEmpty && _ninos.isNotEmpty && _mascotas.isNotEmpty &&
      _experienciaPrevia.isNotEmpty &&
      _motivacionCtl.text.trim().isNotEmpty &&
      (_tipoSolicitud != 'hogar_de_paso' || (_fechaInicio != null && _fechaFin != null));

  String _fmt(DateTime d) {
    const m = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    final user = FirebaseAuth.instance.currentUser;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios').doc(user?.uid).get();
      final nombreAdoptante = (userDoc.data()?['nombre'] as String?)?.isNotEmpty == true
          ? userDoc.data()!['nombre'] as String
          : user?.displayName ?? user?.email ?? 'Adoptante';
      await _solicitudesRepo.crear(
        adoptanteUid: user?.uid ?? '',
        rescatistaId: widget.animal['rescatistaId'] as String? ?? '',
        creadoPor: creatorRoleFromFirestore(widget.animal['creadoPor'] as String?),
        datos: {
          'animalNombre':  widget.animal['nombre'],
          'rescateId':     widget.animal['rescateId']    ?? '',
          'nombre':            nombreAdoptante,
          'email':             user?.email ?? '',
          'integrantes':       _integrantesCtl.text.trim(),
          'horasFuera':        _horasCtl.text.trim(),
          'vivienda':          _vivienda,
          'tieneNinos':        _ninos == 'Sí',
          'tieneMascotas':     _mascotas == 'Sí',
          'experienciaPrevia': _experienciaPrevia == 'Sí',
          'motivacion':        _motivacionCtl.text.trim(),
          'tipoSolicitud':     _tipoSolicitud,
          if (_tipoSolicitud == 'hogar_de_paso' && _fechaInicio != null)
            'fechaInicioHogar': Timestamp.fromDate(_fechaInicio!),
          if (_tipoSolicitud == 'hogar_de_paso' && _fechaFin != null)
            'fechaFinHogar': Timestamp.fromDate(_fechaFin!),
          'fotoBase64':        widget.animal['fotoBase64'],
          // etiquetas del animal para calcular compatibilidad
          'animalEnergia':          widget.animal['energia'],
          'animalTamano':           widget.animal['tamano'],
          'animalOkConNinos':       widget.animal['okConNinos'],
          'animalOkConMascotas':    widget.animal['okConMascotas'],
          'animalRequiereExp':      widget.animal['requiereExperiencia'],
        },
      );
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
    if (_verificando) {
      return const Scaffold(
        backgroundColor: appBg,
        body: Center(child: CircularProgressIndicator(color: appTeal)),
      );
    }
    if (_yaAplico) {
      final aprobada = _estadoExistente == 'aprobada';
      return Scaffold(
        backgroundColor: appBg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    color: (aprobada ? appTeal : appOrange).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(aprobada ? Icons.favorite : Icons.access_time,
                      color: aprobada ? appTeal : appOrange, size: 44),
                ),
                const SizedBox(height: 24),
                Text(
                  aprobada ? '¡Solicitud aprobada!' : 'Ya enviaste una solicitud',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  aprobada
                      ? 'Tu solicitud para ${widget.animal['nombre']} fue aprobada. Revisa el chat para coordinar el encuentro.'
                      : 'Tu solicitud para ${widget.animal['nombre']} está pendiente de revisión. Te avisaremos por el chat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.6),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appDark, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                    child: const Text('Volver', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: appBg,
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
                  valueColor: const AlwaysStoppedAnimation<Color>(appTeal),
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
          decoration: BoxDecoration(color: appDark, borderRadius: BorderRadius.circular(20)),
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
              'Un animal no es un juguete ni decoración.\nTe amará sin condiciones, en los buenos momentos y en los difíciles.\n\nAdoptar es una promesa de por vida.\n\n¿Estás listo?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFFB8D8C8), height: 1.7),
            ),
          ]),
        ),
        const SizedBox(height: 28),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tipoSolicitud = 'adopcion'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _tipoSolicitud == 'adopcion' ? appOrange : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _tipoSolicitud == 'adopcion' ? appOrange : Colors.grey.shade300,
                    width: 2,
                  ),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🏠', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 4),
                  Text('Adoptar',
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold,
                        color: _tipoSolicitud == 'adopcion' ? Colors.white : const Color(0xFF1A1A1A),
                      )),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tipoSolicitud = 'hogar_de_paso'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _tipoSolicitud == 'hogar_de_paso' ? appTeal : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _tipoSolicitud == 'hogar_de_paso' ? appTeal : Colors.grey.shade300,
                    width: 2,
                  ),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🏡', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 4),
                  Text('Hogar de paso',
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold,
                        color: _tipoSolicitud == 'hogar_de_paso' ? Colors.white : const Color(0xFF1A1A1A),
                      )),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => setState(() => _step = 1),
            style: ElevatedButton.styleFrom(
              backgroundColor: _tipoSolicitud == 'adopcion' ? appOrange : appTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              elevation: 0,
            ),
            child: Text(
              _tipoSolicitud == 'adopcion' ? 'Quiero adoptar 🏠' : 'Quiero dar hogar de paso 🏡',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
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
            color: appTeal.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: appTeal.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.person_rounded, color: appTeal, size: 20),
            const SizedBox(width: 10),
            Text(
              FirebaseAuth.instance.currentUser?.displayName ?? 'Tu nombre de Google',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: appTeal),
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
        if (_tipoSolicitud == 'hogar_de_paso') ...[
          const SizedBox(height: 24),
          RichText(text: const TextSpan(
            text: 'Período del hogar de paso',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
            children: [TextSpan(text: ' *', style: TextStyle(color: appTeal))],
          )),
          const SizedBox(height: 6),
          Text('📅  ¿Cuándo puedes recibirlo y hasta cuándo?',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _selectorFecha(
              label: 'Desde',
              fecha: _fechaInicio,
              onPick: (d) => setState(() {
                _fechaInicio = d;
                if (_fechaFin != null && _fechaFin!.isBefore(d)) _fechaFin = null;
              }),
              firstDate: DateTime.now(),
            )),
            const SizedBox(width: 12),
            Expanded(child: _selectorFecha(
              label: 'Hasta',
              fecha: _fechaFin,
              onPick: (d) => setState(() => _fechaFin = d),
              firstDate: _fechaInicio ?? DateTime.now(),
            )),
          ]),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _completo && !_enviando ? _enviar : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: appOrange, foregroundColor: Colors.white,
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
          TextSpan(text: ' *', style: TextStyle(color: appOrange, fontSize: 15)),
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
              color: sel ? appTeal : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: sel ? appTeal : Colors.grey.shade300),
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

  Widget _selectorFecha({
    required String label,
    required DateTime? fecha,
    required ValueChanged<DateTime> onPick,
    required DateTime firstDate,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: fecha ?? firstDate,
          firstDate: firstDate,
          lastDate: DateTime.now().add(const Duration(days: 365)),
          builder: (_, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(primary: appTeal),
            ),
            child: child!,
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: fecha != null ? appTeal : Colors.grey.shade300,
            width: fecha != null ? 1.5 : 1,
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.calendar_today, size: 14, color: fecha != null ? appTeal : Colors.grey.shade400),
            const SizedBox(width: 6),
            Text(
              fecha != null ? _fmt(fecha) : 'Seleccionar',
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: fecha != null ? const Color(0xFF1A1A1A) : Colors.grey.shade400,
              ),
            ),
          ]),
        ]),
      ),
    );
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
                color: appTeal.withOpacity(0.12), shape: BoxShape.circle),
            child: const Icon(Icons.favorite, color: appTeal, size: 50),
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
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              style: ElevatedButton.styleFrom(
                backgroundColor: appDark, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 0,
              ),
              child: const Text('Ver más animales',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }
}
