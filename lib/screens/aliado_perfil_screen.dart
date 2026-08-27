import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../widgets/boton_cambiar_rol.dart';
import '../widgets/campo_ciudad.dart';
import '../widgets/campo_pais_telefono.dart';
import '../widgets/campos_perfil.dart';
import '../widgets/confirmar_ciudad_resuelta.dart';
import '../widgets/elegir_foto_perfil.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/fondo_decorativo.dart';
import '../widgets/fotos.dart';
import '../widgets/resultado_guardado_snackbar.dart';
import '../data/firestore_resiliencia.dart';
import '../domain/reglas_negocio.dart';

class AliadoPerfilScreen extends StatefulWidget {
  const AliadoPerfilScreen({super.key});
  @override
  State<AliadoPerfilScreen> createState() => _AliadoPerfilScreenState();
}

class _AliadoPerfilScreenState extends State<AliadoPerfilScreen> {
  final _nombreCtl = TextEditingController();
  final _ciudadCtl = TextEditingController();
  final _telefonoCtl = TextEditingController();
  final _direccionCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _webCtl = TextEditingController();
  String? _tipo;
  String? _fotoBase64;
  bool _guardando = false;
  bool _cargando = true;
  bool _errorCarga = false;
  // Ciudad tal cual estaba guardada al abrir la pantalla — para validar
  // contra el servicio de geocoding solo cuando el texto realmente cambia
  // (ver _guardar()), no en cada guardado. Mismo criterio que
  // albergue_perfil_screen.dart.
  String _ciudadOriginal = '';
  // ¿La ciudad guardada pasó alguna vez por el geocodificador? Es la otra
  // mitad de la condición para validar (ver _guardar): sin esto, una
  // ciudad guardada antes de que existiera esta validación no se volvía a
  // revisar nunca, porque el texto no cambiaba. Equivale a
  // `_tieneCoordenadas`/`_tienePais` en albergue_perfil_screen.dart — este
  // perfil no guarda coordenadas (nada calcula distancia a un negocio),
  // así que necesita su propia marca.
  //
  // Arranca en `true` cuando el perfil ya la tiene marcada, y en `false`
  // para los perfiles viejos: esos se revalidan UNA vez, y al guardar
  // quedan marcados.
  bool _ciudadVerificada = false;

  static const _tipos = [
    'Veterinaria',
    'Tienda de mascotas',
    'Spa canino',
    'Peluquería canina',
    'Otro',
  ];

  bool get _completo =>
      _nombreCtl.text.trim().isNotEmpty &&
      _ciudadCtl.text.trim().isNotEmpty &&
      _tipo != null &&
      // Opcionales de verdad (un campo vacío no bloquea), pero si SE
      // ESCRIBE algo tiene que tener forma real — mismo criterio que la
      // ciudad geocodificada de esta misma pantalla. Hallazgo real de
      // Eliza: "sjejdj" se guardaba igual que un email/sitio real, sin
      // ningún aviso.
      (_emailCtl.text.trim().isEmpty ||
          esEmailValido(_emailCtl.text.trim())) &&
      (_webCtl.text.trim().isEmpty || esSitioWebValido(_webCtl.text.trim()));

  @override
  void initState() {
    super.initState();
    _cargarDatosExistentes();
  }

  // Antes esto no tenía ningún try/catch: si la carga inicial fallaba (o
  // tardaba y la persona no esperaba), los campos opcionales (teléfono,
  // dirección, email, web) quedaban vacíos en pantalla — y _guardar() los
  // escribía igual, sin ninguna protección, borrando de contrabando lo que
  // ya estaba guardado. Ahora la pantalla no muestra el formulario (ni el
  // botón de guardar) hasta confirmar que la carga terminó bien; si falla,
  // muestra un estado de reintento en vez de proceder con datos a medias.
  // Hallazgo de auditoría de código.
  Future<void> _cargarDatosExistentes() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      if (!mounted) return;
      if (!doc.exists) {
        setState(() => _cargando = false);
        return;
      }
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _nombreCtl.text = data['aliadoNombre'] as String? ?? '';
        // `?? data['ciudad']`: los perfiles de aliado creados ANTES de
        // separar este campo tienen su ciudad en `ciudad` (compartida con
        // el albergue) — se lee de ahí una última vez, y al guardar queda
        // migrada sola a `aliadoCiudad`. Sin este respaldo, todos los
        // negocios existentes aparecerían de golpe sin ciudad.
        _ciudadCtl.text =
            data['aliadoCiudad'] as String? ?? data['ciudad'] as String? ?? '';
        _ciudadVerificada = data['aliadoCiudadVerificada'] == true;
        _ciudadOriginal = _ciudadCtl.text;
        _telefonoCtl.text = data['aliadoTelefono'] as String? ?? '';
        _direccionCtl.text = data['aliadoDireccion'] as String? ?? '';
        _emailCtl.text = data['aliadoEmail'] as String? ?? '';
        _webCtl.text = data['aliadoSitioWeb'] as String? ?? '';
        _tipo = data['aliadoTipo'] as String?;
        _fotoBase64 = data['aliadoFotoBase64'] as String?;
        _cargando = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _cargando = false;
          _errorCarga = true;
        });
    }
  }

  Future<void> _reintentarCarga() async {
    setState(() {
      _cargando = true;
      _errorCarga = false;
    });
    await _cargarDatosExistentes();
  }

  Future<void> _pickFoto() async {
    // maxWidth:512 porque el resultado se guarda en base64 DENTRO del
    // documento de Firestore (no aparte en Storage, como las fotos de
    // rescates), que tiene un tope de 1MB total — el 1000px por defecto de
    // normalizarFoto() es para las fotos que sí van a Storage.
    final b64 = await elegirFotoPerfil(maxWidth: 512);
    if (b64 == null || !mounted) return;
    setState(() => _fotoBase64 = b64);
  }

  Future<void> _guardar() async {
    if (!_completo) return;
    setState(() => _guardando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    var ciudad = _ciudadCtl.text.trim();
    // Este perfil no guarda coordenadas (a diferencia del de albergue): hoy
    // nada en la app calcula distancia a un negocio aliado, así que no hay
    // ningún lugar que las use — solo se valida que el texto sea un lugar
    // real antes de guardarlo. Solo se valida si cambió, para no pedirle a
    // la red algo que ya se confirmó antes.
    //
    // Antes acá había un comentario diciendo que esta pantalla y la de
    // albergue "validan exactamente lo mismo y no pueden divergir". Era
    // falso: ya habían divergido (esta guardaba el texto crudo ante un
    // error de red, la otra bloqueaba), y el comentario ayudó a que nadie
    // lo mirara. Ahora sí es cierto, pero por construcción y no por
    // promesa: las 4 pantallas llaman a la MISMA resolverCiudadEscrita().
    // ¿Se resolvió una ciudad con el diálogo en ESTE guardado? Si sí, la
    // pantalla no se cierra al terminar — ver el comentario al final de
    // esta función. Mismo comportamiento que albergue_perfil_screen.dart.
    var huboCiudadResuelta = false;
    // `|| !_ciudadVerificada`: la segunda mitad repara las ciudades que
    // nunca pasaron por el geocodificador — las guardadas antes de que
    // esta validación existiera, o por el camino viejo que dejaba pasar
    // texto crudo ante un error de red. Sin esto, una ciudad sin verificar
    // se quedaba así PARA SIEMPRE: la condición de arriba solo dispara
    // cuando el texto CAMBIA, y volver a escribir la misma nunca cambia
    // nada. Mismo criterio, y mismo motivo, que `!_tieneCoordenadas ||
    // !_tienePais` en albergue_perfil_screen.dart — esta pantalla no
    // guardaba nada equivalente con qué saberlo.
    //
    // Hallazgo real de Eliza: a un aliado le salía el diálogo de confirmar
    // la ciudad y al otro no, escribiendo lo mismo. Eso en sí era correcto
    // (el segundo ya tenía esa ciudad guardada), pero destapó que su
    // ciudad no tenía forma de volver a validarse nunca.
    if (ciudad.isNotEmpty &&
        (ciudad != _ciudadOriginal || !_ciudadVerificada)) {
      // Misma función compartida que las otras 3 pantallas que piden una
      // ciudad — antes acá vivía una copia a mano de esa secuencia, y su
      // `catch` vacío dejaba pasar el texto crudo ante cualquier tropiezo
      // de red: era la única de las 4 que guardaba basura en silencio. Ver
      // el comentario de resolverCiudadEscrita().
      final elegida = await resolverCiudadEscrita(context, ciudad);
      // null = canceló ("No, corregir"), o no se pudo verificar
      // (resolverCiudadEscrita ya explicó por qué). Ninguno de los dos
      // debe dejar a la persona TRABADA sin forma de guardar nada — se
      // vuelve al texto que YA estaba guardado (no al que se tecleó, que
      // quedó sin confirmar) y se corta ACÁ, sin guardar ni salir de la
      // pantalla. Antes seguía derecho a guardar el resto de los campos y
      // cerraba la pantalla igual si podía volver — mismo bug que
      // editar_rescate_screen.dart/subir_rescate_screen.dart/albergue_
      // perfil_screen.dart: tocar "No, corregir" (que suena a "dejame
      // corregir eso") te sacaba igual del perfil, sin darte la chance de
      // reintentar la ciudad. Hallazgo real de Eliza en editar un rescate,
      // mismo camino compartido acá. Si de verdad no querés resolver la
      // ciudad, un segundo toque de "Guardar" sin volver a tocar ese campo
      // guarda el resto igual (el texto ya quedó revertido a uno válido,
      // así que la condición de arriba ya no dispara) — se sigue pudiendo
      // salir del paso sin quedar en bucle, solo que ya no de forma
      // silenciosa en el mismo toque.
      if (elegida == null) {
        ciudad = _ciudadOriginal;
        _ciudadCtl.text = ciudad;
        if (mounted) setState(() => _guardando = false);
        return;
      } else {
        // El nombre que resolvió el geocodificador, nunca el texto
        // tecleado — ver el invariante en confirmar_ciudad_resuelta.dart.
        // Este perfil no guarda coordenadas (ver el comentario de arriba),
        // así que acá el invariante se reduce a esta única línea.
        ciudad = elegida.ciudadResuelta;
        _ciudadCtl.text = ciudad;
        huboCiudadResuelta = true;
      }
    }
    // guardarConAviso, no un await directo: sin esto, sin conexión o con
    // el token de sesión vencido, el botón de guardar se quedaba pegado
    // para siempre sin ningún aviso — mismo bug ya arreglado una vez en
    // editar_rescate_screen.dart, que nunca se replicó acá (hallazgo de
    // auditoría de código).
    final resultado = await guardarConAviso(
      () => FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'aliadoNombre': _nombreCtl.text.trim(),
        'aliadoTipo': _tipo ?? '',
        // `aliadoCiudad`, NO `ciudad` a secas — prefijo por el mismo motivo
        // que aliadoTelefono/aliadoEmail/aliadoDireccion/aliadoSitioWeb:
        // una cuenta con doble rol (albergue + aliado) comparte el
        // documento usuarios/{uid}, y `ciudad` estaba siendo escrita por
        // LAS DOS pantallas de perfil.
        //
        // No era solo "se pisan": el perfil del albergue guarda `ciudad`
        // junto con `latitud`/`longitud`/`paisCodigo` como un conjunto que
        // describe UN SOLO lugar (hay un invariante cuidado explícitamente
        // para eso, ver confirmar_ciudad_resuelta.dart). Esta pantalla
        // escribía `ciudad` sin tocar las coordenadas — así que un negocio
        // que cambiaba su ciudad le dejaba al albergue de la misma cuenta
        // el nombre de una ciudad con las coordenadas y la bandera de
        // otra, y todos sus animales heredaban esa mezcla. Es el mismo bug
        // de "Córdoba 🇦🇷" de esta sesión, entrando por otra puerta.
        'aliadoCiudad': ciudad,
        // Queda marcada como verificada si la resolvió el geocodificador
        // en ESTE guardado, o si ya lo estaba de antes — ver
        // `_ciudadVerificada`.
        'aliadoCiudadVerificada': huboCiudadResuelta || _ciudadVerificada,
        // Opcionales a propósito, mismo criterio que albergue_perfil_screen.dart.
        // Prefijo "aliado" a propósito: ver el comentario largo en
        // albergue_perfil_screen.dart — una cuenta con doble rol (albergue +
        // aliado) compartía estos mismos campos genéricos entre los dos
        // perfiles, y "email" además pisaba el email de LOGIN de la cuenta.
        'aliadoTelefono': _telefonoCtl.text.trim(),
        'aliadoDireccion': _direccionCtl.text.trim(),
        'aliadoEmail': _emailCtl.text.trim(),
        'aliadoSitioWeb': _webCtl.text.trim(),
        if (_fotoBase64 != null) 'aliadoFotoBase64': _fotoBase64,
      }),
    );
    // El nombre y el logo de este negocio se copian dentro de cada chat
    // suyo; refrescar esas copias es trabajo del servidor (ver el trigger
    // onPerfilActualizado en functions/propagar_copias.js), no de acá.

    if (!mounted) return;
    setState(() {
      _guardando = false;
      // Lo recién guardado pasa a ser "lo original" — sin esto, ahora que
      // la pantalla se queda abierta, un segundo toque de Guardar volvería
      // a pedir confirmación de una ciudad ya resuelta y ya guardada.
      if (resultado != ResultadoGuardado.fallo) {
        _ciudadOriginal = ciudad;
        // Igual de importante que la línea de arriba: sin esto, un perfil
        // viejo que se acaba de verificar y guardar volvería a pedir
        // confirmación en el siguiente toque de Guardar (la condición de
        // `!_ciudadVerificada` seguiría siendo verdadera en memoria).
        _ciudadVerificada = huboCiudadResuelta || _ciudadVerificada;
      }
    });
    // canPop se evalúa UNA vez y se usa para las dos decisiones (qué
    // mostrar y si volver) — mismo criterio que ya tenía esta pantalla: si
    // no se puede volver (ej. esta pantalla no está en una pila normal de
    // navegación), el aviso de éxito no tiene sentido sin un lugar al que
    // volver, pero el de "esto está tardando" sí se muestra siempre.
    //
    // Tras resolver una ciudad con el diálogo NO se sale: la ciudad
    // guardada es la que eligió el geocodificador, no la que se tecleó, y
    // hay que poder verla en el campo antes de irse. Mismo cambio y mismo
    // motivo que en albergue_perfil_screen.dart — ver el comentario largo
    // ahí. Reportado por Eliza para el albergue, y esta pantalla se
    // comportaba igual.
    final puedeVolver = Navigator.canPop(context);
    mostrarResultadoGuardado(
      context,
      resultado,
      exito: huboCiudadResuelta
          ? 'Ciudad actualizada a $ciudad'
          : (puedeVolver ? 'Perfil actualizado' : null),
      pendiente:
          'Esto está tardando. Tu perfil se va a actualizar solo apenas vuelva la señal.',
    );
    if (resultado != ResultadoGuardado.fallo &&
        puedeVolver &&
        !huboCiudadResuelta) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _nombreCtl.dispose();
    _ciudadCtl.dispose();
    _telefonoCtl.dispose();
    _direccionCtl.dispose();
    _emailCtl.dispose();
    _webCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        backgroundColor: appBg,
        body: Center(child: CircularProgressIndicator(color: appTeal)),
      );
    }
    if (_errorCarga) {
      return Scaffold(
        backgroundColor: appBg,
        body: SafeArea(
          child: Column(
            children: [
              Builder(
                builder: (ctx) => Navigator.canPop(ctx)
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                          tooltip: 'Volver',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        errorFeedState(
                          mensaje:
                              'No pudimos cargar tu perfil. Revisá tu conexión e intentá de nuevo.',
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _reintentarCarga,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appTeal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Reintentar',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: appBg,
      floatingActionButton: botonCambiarRol(context, heroTag: 'debug_perfil'),
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
                  // Mismo patrón que albergue_perfil_screen.dart — acá no
                  // había ninguna forma de volver atrás salvo el gesto del
                  // sistema (o cerrar la app), a diferencia del resto de
                  // las pantallas de perfil. Hallazgo real de Eliza.
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

                  const Text(
                    'Configura tu negocio',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: appInk,
                      fontFamily: 'Baloo2',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Esta información aparecerá en tu perfil público',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 32),

                  // Foto
                  Center(
                    child: GestureDetector(
                      onTap: _pickFoto,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: appTeal, width: 2),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: _fotoBase64 != null
                            ? FotoSegura(
                                base64: _fotoBase64!,
                                fit: BoxFit.cover,
                                fallback: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.camera_alt_outlined,
                                      color: appTeal,
                                      size: 24,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Logo',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: appTeal,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt_outlined,
                                    color: appTeal,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Logo',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: appTeal,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Mismo estilo que "Configura tu albergue" (label arriba del
                  // campo, en vez del ícono + label flotante que tenía esta
                  // pantalla antes) — Eliza las comparó una al lado de la otra
                  // y pidió que las dos se vean con la misma tipografía.
                  perfilLabel('NOMBRE DEL NEGOCIO *'),
                  const SizedBox(height: 8),
                  perfilCampo(
                    _nombreCtl,
                    'ej. Veterinaria La 30',
                    autofocus: true,
                    maxLength: 50,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 24),

                  perfilLabel('CIUDAD *'),
                  const SizedBox(height: 8),
                  CampoCiudad(
                    controller: _ciudadCtl,
                    hint: 'ej. Medellín, Bogotá, Santiago',
                    maxLength: 50,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 24),

                  // Teléfono/WhatsApp y dirección, opcionales — no van en
                  // _completo a propósito, un negocio recién sumándose puede
                  // no tener todavía un número de atención separado.
                  perfilLabel('TELÉFONO / WHATSAPP (OPCIONAL)'),
                  const SizedBox(height: 8),
                  CampoTelefono(controller: _telefonoCtl),
                  const SizedBox(height: 24),

                  perfilLabel('DIRECCIÓN (OPCIONAL)'),
                  const SizedBox(height: 8),
                  perfilCampo(
                    _direccionCtl,
                    'ej. Calle 10 #43-12, El Poblado',
                    maxLength: 100,
                  ),
                  const SizedBox(height: 24),

                  perfilLabel('EMAIL (OPCIONAL)'),
                  const SizedBox(height: 8),
                  perfilCampo(
                    _emailCtl,
                    'ej. contacto@tunegocio.com',
                    tipo: TextInputType.emailAddress,
                    maxLength: 100,
                    onChanged: (_) => setState(() {}),
                  ),
                  // Opcional de verdad (vacío no bloquea), pero un texto sin
                  // forma de email sí — ver el comentario de _completo.
                  if (_emailCtl.text.trim().isNotEmpty &&
                      !esEmailValido(_emailCtl.text.trim()))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        avisoEmailInvalido,
                        style: TextStyle(fontSize: 12, color: msgError),
                      ),
                    ),
                  const SizedBox(height: 24),

                  perfilLabel('PÁGINA WEB (OPCIONAL)'),
                  const SizedBox(height: 8),
                  perfilCampo(
                    _webCtl,
                    'ej. www.tunegocio.com',
                    tipo: TextInputType.url,
                    maxLength: 150,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_webCtl.text.trim().isNotEmpty &&
                      !esSitioWebValido(_webCtl.text.trim()))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        avisoSitioWebInvalido,
                        style: TextStyle(fontSize: 12, color: msgError),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Tipo — mismo look que el resto de los campos (caja blanca
                  // sin ícono, radio 12): solo cambia que es un desplegable.
                  perfilLabel('TIPO DE NEGOCIO *'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _tipo,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    items: _tipos
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _tipo = v),
                  ),
                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_completo && !_guardando) ? _guardar : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: appTeal,
                        foregroundColor: Colors.white,
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
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Guardar y continuar',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
