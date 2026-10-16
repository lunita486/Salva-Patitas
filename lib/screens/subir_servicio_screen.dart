import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/sp_widgets.dart';
import '../data/servicios_repository.dart';
import '../widgets/resultado_guardado_snackbar.dart';
import '../data/firestore_resiliencia.dart';

class SubirServicioScreen extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? data;
  const SubirServicioScreen({super.key, this.docId, this.data});
  @override
  State<SubirServicioScreen> createState() => _SubirServicioScreenState();
}

class _SubirServicioScreenState extends State<SubirServicioScreen> {
  final _nombreCtl = TextEditingController();
  final _precioCtl = TextEditingController();
  final _descripcionCtl = TextEditingController();
  bool _guardando = false;

  bool get _esEdicion => widget.docId != null;

  static const _categorias = [
    ('Baño y peluquería', '🛁'),
    ('Veterinaria', '🩺'),
    ('Tienda', '🛍️'),
    ('Adiestramiento', '🎓'),
    ('Transporte', '🚗'),
    ('Otro', '🐾'),
  ];

  String _categoriaSeleccionada = 'Baño y peluquería';

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _nombreCtl.text = widget.data!['nombre'] as String? ?? '';
      _precioCtl.text = '${widget.data!['precio'] as int? ?? 0}';
      _descripcionCtl.text = widget.data!['descripcion'] as String? ?? '';
      _categoriaSeleccionada =
          widget.data!['categoria'] as String? ?? 'Baño y peluquería';
    }
  }

  // "0" pasaba antes esta validación (solo se pedía que el campo no
  // estuviera vacío) y se guardaba tal cual, publicando un servicio con
  // precio $0 sin ningún aviso. Hallazgo de auditoría de código.
  bool get _completo =>
      _nombreCtl.text.trim().isNotEmpty &&
      (int.tryParse(_precioCtl.text.trim()) ?? 0) > 0;

  Future<void> _guardar() async {
    if (!_completo) return;
    setState(() => _guardando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // Sin uid no se puede publicar: antes esto seguía igual y creaba el
    // servicio con `aliadoId: null` — un documento huérfano que no
    // aparecía en la lista de NINGÚN negocio (todas filtran por aliadoId)
    // y que nadie podía borrar desde la app. Lo destapó el repositorio, que
    // exige el id del dueño en vez de aceptar cualquier cosa.
    if (uid == null || uid.isEmpty) {
      setState(() => _guardando = false);
      return;
    }
    final payload = {
      'nombre': _nombreCtl.text.trim(),
      // Sin .replaceAll('.', '') acá a propósito — era código muerto: el
      // campo tiene inputFormatters: [FilteringTextInputFormatter.digitsOnly]
      // (ver más abajo), así que un "." nunca se puede llegar a escribir.
      'precio': int.tryParse(_precioCtl.text.trim()) ?? 0,
      'descripcion': _descripcionCtl.text.trim(),
      'categoria': _categoriaSeleccionada,
    };
    // guardarConAviso, no un await directo: sin esto, sin conexión o con
    // el token de sesión vencido, el botón de guardar se quedaba pegado
    // para siempre sin ningún aviso — mismo bug ya arreglado una vez en
    // editar_rescate_screen.dart, que nunca se replicó acá (hallazgo de
    // auditoría de código). De yapa, esta pantalla ni siquiera avisaba
    // "listo" al guardar bien.
    final resultado = await guardarConAviso(
      // `activo: true` y `creadoEn` ya NO se escriben acá: son parte de qué
      // significa "crear un servicio", no una decisión de esta pantalla —
      // ver ServiciosRepository.crear().
      () => _esEdicion
          ? ServiciosRepository().actualizar(widget.docId!, payload)
          : ServiciosRepository().crear(aliadoId: uid, datos: payload),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    mostrarResultadoGuardado(
      context,
      resultado,
      exito: _esEdicion ? 'Servicio actualizado' : 'Servicio publicado',
    );
    if (resultado != ResultadoGuardado.fallo) Navigator.pop(context);
  }

  @override
  void dispose() {
    _nombreCtl.dispose();
    _precioCtl.dispose();
    _descripcionCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    final k = SpToneColors.of(
      c,
      spToneCategoriaServicio(_categoriaSeleccionada),
    );
    final habilitado = _completo && !_guardando;

    // Mismo esqueleto que "Subir uno" (subir_rescate_screen.dart):
    // encabezado, secciones con huellita, tarjetas blancas y el botón verde
    // abajo.
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: SpPawBackground()),
          SafeArea(
            child: Column(
              children: [
                SpScreenHeader(
                  title: _esEdicion ? 'Editar servicio' : 'Nuevo servicio',
                  subtitle: _categoriaSeleccionada,
                  subtitleColor: k.ink,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Categoría ────────────────────────────────────
                        const SpSectionTitle('Categoría'),
                        const SizedBox(height: SpSpace.s3),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          clipBehavior: Clip.none,
                          crossAxisCount: 3,
                          mainAxisSpacing: SpSpace.s3,
                          crossAxisSpacing: SpSpace.s3,
                          childAspectRatio: 1.05,
                          children: _categorias
                              .map((cat) => _baldosaCategoria(c, cat))
                              .toList(),
                        ),

                        // ── Sobre el servicio ────────────────────────────
                        const SizedBox(height: SpSpace.s6),
                        const SpSectionTitle('Sobre el servicio'),
                        const SizedBox(height: SpSpace.s3),
                        SpCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('Nombre del servicio *'),
                              const SizedBox(height: 8),
                              _campo(
                                _nombreCtl,
                                'ej. Baño completo con secado',
                                Icons.spa_outlined,
                              ),
                              const SizedBox(height: 10),
                              _label('Precio *'),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _precioCtl,
                                onChanged: (_) => setState(() {}),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                // Mismo bug y mismo arreglo que la capacidad
                                // del perfil de albergue
                                // (albergue_perfil_screen.dart): sin tope de
                                // dígitos, un número gigante desborda
                                // int.tryParse() en _completo (más abajo),
                                // que lo lee como "precio 0" y deja el botón
                                // de publicar deshabilitado para siempre sin
                                // ningún aviso. 9 dígitos (hasta 999.999.999)
                                // alcanza de sobra para cualquier precio
                                // real, en cualquier moneda de la app.
                                maxLength: 9,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: c.ink,
                                ),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  prefixText: '\$ ',
                                  prefixStyle: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: k.ink,
                                  ),
                                ),
                              ),
                              // Por qué "Publicar servicio" está apagado,
                              // dicho en el lugar donde se puede arreglar.
                              // _completo ya exigía precio > 0 (un servicio a
                              // $0 se publicaba tal cual antes), pero eso no
                              // se explicaba en ningún lado: el botón
                              // simplemente no se encendía. Mismo agregado, y
                              // por el mismo motivo, que el aviso de
                              // capacidad en albergue_perfil_screen.dart.
                              // Pedido de Eliza.
                              if (_precioCtl.text.trim().isNotEmpty &&
                                  (int.tryParse(_precioCtl.text.trim()) ?? 0) <=
                                      0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    'El precio tiene que ser mayor que 0 para poder publicar.',
                                    style: SpText.caption.copyWith(
                                      color: c.danger,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 10),
                              _label('Descripción (opcional)'),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _descripcionCtl,
                                maxLines: 3,
                                // 300, no los 1000 de la descripción de un
                                // animal (ver subir_rescate_screen.dart) — esa
                                // cuenta una historia para generar empatía,
                                // esta es "qué incluye el servicio": un par de
                                // oraciones alcanzan de sobra. Pedido real de
                                // Eliza.
                                maxLength: 300,
                                decoration: const InputDecoration(
                                  hintText: 'Contá qué incluye el servicio...',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: SpSpace.s6),
                        _botonGuardar(c, habilitado),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Baldosa pastel 3D de una categoría; la elegida con borde verde y ✓
  /// (igual que el selector de especie de Subir uno).
  Widget _baldosaCategoria(SpColors c, (String, String) cat) {
    final sel = _categoriaSeleccionada == cat.$1;
    final tono = spToneCategoriaServicio(cat.$1);
    final k = SpToneColors.of(c, tono);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: SpToneBox(
            tone: tono,
            radius: 20,
            padding: const EdgeInsets.all(6),
            onTap: () => setState(() => _categoriaSeleccionada = cat.$1),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(cat.$2, style: const TextStyle(fontSize: 28)),
                const SizedBox(height: 4),
                Text(
                  cat.$1,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: k.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (sel)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.primary, width: 3),
                ),
              ),
            ),
          ),
        if (sel)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 22,
              height: 22,
              decoration: SpDeco.primary(c, radius: SpRadius.full),
              child: Icon(Icons.check_rounded, size: 14, color: c.onPrimary),
            ),
          ),
      ],
    );
  }

  /// Botón verde 3D. Apagado (medio transparente) mientras falte nombre o
  /// precio; con spinner mientras guarda.
  Widget _botonGuardar(SpColors c, bool habilitado) {
    final caja = Container(
      width: double.infinity,
      height: 56,
      alignment: Alignment.center,
      decoration: SpDeco.primary(c, radius: SpRadius.md),
      child: _guardando
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.onPrimary,
              ),
            )
          : Text(
              _esEdicion ? 'Guardar cambios' : 'Publicar servicio',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: c.onPrimary,
              ),
            ),
    );
    return Semantics(
      button: true,
      enabled: habilitado,
      child: habilitado
          ? SpPressable(onTap: _guardar, child: caja)
          : Opacity(opacity: _guardando ? 1 : .5, child: caja),
    );
  }

  /// Etiqueta de un campo dentro de una tarjeta, como en Subir uno.
  Widget _label(String text) => Text(
    text,
    style: SpText.label.copyWith(
      color: context.sp.inkMuted,
      fontWeight: FontWeight.w700,
    ),
  );

  // El estilo del campo viene del tema (inputDecorationTheme).
  Widget _campo(TextEditingController ctl, String hint, IconData icon) =>
      TextFormField(
        controller: ctl,
        onChanged: (_) => setState(() {}),
        // Sin tope antes: un pegado gigante en el nombre se guardaba
        // entero. Hallazgo de auditoría de código.
        maxLength: 60,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 20),
        ),
      );
}
