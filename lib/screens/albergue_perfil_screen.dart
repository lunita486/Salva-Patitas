import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../domain/reglas_negocio.dart';
import '../data/firestore_resiliencia.dart';

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
  // Misma idea que _tieneCoordenadas, para el país: nunca se guardaba acá
  // (solo se usaba un instante para el cartel de confirmación y se
  // descartaba) — sin esto en la condición de abajo, un perfil que ya
  // tiene ciudad y coordenadas nunca vuelve a geocodificar, así que el país
  // faltante quedaría sin repararse para siempre. Motivo real de que NINGÚN
  // animal de albergue mostrara la bandera del país. Hallazgo real de
  // Eliza.
  bool _tienePais = false;
  // Las coordenadas y el país que YA tiene guardados el perfil. Hacen falta
  // para poder re-propagarlos a los animales en un guardado que NO
  // geocodificó nada (ver _guardar): sin esto solo se podían propagar los
  // valores recién geocodificados, y un animal que quedó con una ciudad
  // vieja no tenía ninguna forma de repararse — la sincronización solo
  // corría cuando la ciudad CAMBIABA, así que volver a guardar el perfil
  // con la ciudad correcta ya escrita no arreglaba nada. Hallazgo real de
  // Eliza, con evidencia: sus 16 animales tenían 5 ciudades distintas
  // (Medellin, Córdoba 🇦🇷, cordoba 🇪🇸, Montería, Nedellin) y ninguna era
  // la del perfil.
  double? _latPerfil;
  double? _lngPerfil;
  String _paisPerfil = '';
  bool _cargando = true;
  bool _errorCarga = false;

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
  // Mismo arreglo que ya tenía aliado_perfil_screen.dart — hallazgo de
  // auditoría de código: la misma pantalla de Albergue nunca lo recibió.
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
        _nombreCtl.text = data['albergueNombre'] as String? ?? '';
        _ciudadCtl.text = data['ciudad'] as String? ?? '';
        _ciudadOriginal = _ciudadCtl.text;
        _latPerfil = (data['latitud'] as num?)?.toDouble();
        _lngPerfil = (data['longitud'] as num?)?.toDouble();
        _paisPerfil = data['paisCodigo'] as String? ?? '';
        _tieneCoordenadas = _latPerfil != null && _lngPerfil != null;
        _tienePais = _paisPerfil.isNotEmpty;
        _capacidadCtl.text =
            (data['capacidadTotal'] as int?)?.toString() ?? '';
        _telefonoCtl.text = data['albergueTelefono'] as String? ?? '';
        _direccionCtl.text = data['albergueDireccion'] as String? ?? '';
        _emailCtl.text = data['albergueEmail'] as String? ?? '';
        _webCtl.text = data['albergueSitioWeb'] as String? ?? '';
        _tipo = data['albergueTipo'] as String?;
        _fotoBase64 = data['fotoBase64'] as String?;
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
      _tipo != null &&
      // Opcionales de verdad (un campo vacío no bloquea), pero si SE
      // ESCRIBE algo tiene que tener forma real — mismo criterio que la
      // ciudad geocodificada de esta misma pantalla, y la MISMA validación
      // que aliado_perfil_screen.dart, que ya la tenía desde que Eliza
      // reportó que "sjejdj" se guardaba como email sin ningún aviso. Esta
      // pantalla, con los mismos dos campos, nunca la recibió: Eliza pudo
      // guardar "lacasita" como email del albergue.
      (_emailCtl.text.trim().isEmpty ||
          esEmailValido(_emailCtl.text.trim())) &&
      (_webCtl.text.trim().isEmpty || esSitioWebValido(_webCtl.text.trim()));

  Future<void> _guardar() async {
    if (!_completo) return;
    setState(() => _guardando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    var ciudad = _ciudadCtl.text.trim();
    // Geocodifica la ciudad escrita a mano a coordenadas — sin esto, un
    // albergue nunca tenía latitud/longitud en ningún lado (ni acá ni al
    // publicar un animal, que reusa este mismo campo de texto), así que
    // "a X km de ti" nunca podía calcularse para NINGÚN animal publicado
    // por un albergue. Hallazgo real de Eliza: notó que faltaba en todos
    // los albergues, no en uno solo. Solo geocodifica si el texto de
    // ciudad cambió — no tiene sentido volver a pedirle a la red algo que
    // ya se resolvió antes.
    //
    // resolverCiudadEscrita (widgets/confirmar_ciudad_resuelta.dart) es la
    // única fuente de "¿esto es una ciudad real?" para toda la app — antes
    // acá se trataba "no encontré nada" exactamente igual que "no hay
    // señal": en los dos casos se guardaba la ciudad tal cual sin avisar
    // nada, así que cualquier texto ("verduras", lo que fuera) quedaba
    // guardado como ciudad válida. Ahora los dos casos avisan con mensajes
    // distintos y NINGUNO deja guardar: acá no se puede "guardar igual sin
    // verificar" porque el invariante de más abajo exige que una ciudad
    // guardada tenga siempre coordenadas y país, y sin verificar no hay de
    // dónde sacarlos.
    double? lat;
    double? lng;
    String? paisCodigo;
    // La regla ahora es un INVARIANTE, no una optimización: si hay ciudad
    // guardada, tiene que haber coordenadas Y país. Por eso se geocodifica
    // cuando el texto cambió O cuando todavía falta alguno de los dos —
    // esa segunda mitad es la que repara los perfiles viejos, creados antes
    // de que esta validación existiera (o antes de que paisCodigo se
    // empezara a guardar), que nunca pasaban por acá porque el texto no
    // cambiaba y por eso dejaban a TODOS sus animales sin distancia/bandera.
    if (ciudad.isNotEmpty &&
        (ciudad != _ciudadOriginal || !_tieneCoordenadas || !_tienePais)) {
      // Misma función compartida que las otras 3 pantallas que piden una
      // ciudad — ver el comentario de resolverCiudadEscrita(). Antes acá
      // vivía una copia a mano de esta secuencia.
      final elegida = await resolverCiudadEscrita(context, ciudad);
      // null = canceló ("No, corregir"), o no se pudo verificar
      // (resolverCiudadEscrita ya explicó por qué). Ninguno de los dos
      // debe dejar a la persona TRABADA sin forma de guardar nada — se
      // vuelve al texto que YA estaba guardado (no al que se tecleó, que
      // quedó sin confirmar) y se corta ACÁ, sin guardar ni salir de la
      // pantalla. Antes seguía derecho a guardar el resto de los campos y
      // cerraba la pantalla igual si podía volver — mismo bug que
      // editar_rescate_screen.dart/subir_rescate_screen.dart: tocar "No,
      // corregir" (que suena a "dejame corregir eso") te sacaba igual del
      // perfil, sin darte la chance de reintentar la ciudad. Hallazgo real
      // de Eliza en editar un rescate, mismo camino compartido acá.
      //
      // Acá la condición de arriba tiene una segunda pata que editar/subir
      // no tienen (`!_tieneCoordenadas || !_tienePais`, para reparar
      // perfiles viejos) — y esa pata NO se apaga sola con el texto vuelto
      // a lo de antes, porque no depende de si la ciudad cambió. Sin tocar
      // esas dos banderas acá, un segundo toque de "Guardar" volvería a
      // mostrar este mismo diálogo, reintroduciendo el bucle. Se marcan
      // como resueltas para lo que dure esta pantalla (no se reintenta más
      // hasta que se reabra el perfil) — no porque el perfil ya tenga
      // coordenadas de verdad, sino porque la persona ya vio la oferta de
      // repararlo y la rechazó por ahora.
      if (elegida == null) {
        ciudad = _ciudadOriginal;
        _ciudadCtl.text = ciudad;
        _tieneCoordenadas = true;
        _tienePais = true;
        if (mounted) setState(() => _guardando = false);
        return;
      } else {
        // Los tres datos del MISMO candidato, siempre — ver el invariante
        // en confirmar_ciudad_resuelta.dart. Acá pesa doble: los animales
        // de este albergue HEREDAN ciudad, coordenadas y país de este
        // perfil, así que una mezcla de dos lugares distintos se
        // replicaría en la tarjeta de cada uno de ellos en el feed.
        // Hallazgo real de Eliza: "medellin antioquia" y "cordoba
        // verduras 🇪🇸" guardados tal cual.
        lat = elegida.lat;
        lng = elegida.lng;
        paisCodigo = elegida.paisCodigo;
        ciudad = elegida.ciudadResuelta;
        _ciudadCtl.text = ciudad;
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
        if (paisCodigo != null) 'paisCodigo': paisCodigo,
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
    // Las copias de la ciudad/nombre/logo de este albergue (en sus animales
    // y en sus chats) las refresca el servidor — ver el trigger
    // onPerfilActualizado en functions/propagar_copias.js. Acá NO se hace
    // nada: cuando esto se intentaba desde el cliente fallaba en silencio
    // de cuatro formas distintas, y tener las dos versiones a la vez solo
    // agregaba una copia más que podía divergir de la otra.

    if (!mounted) return;
    setState(() {
      _guardando = false;
      // Lo recién guardado pasa a ser "lo original". Hace falta ahora que
      // esta pantalla se queda abierta tras resolver una ciudad (ver abajo):
      // sin esto, _ciudadOriginal seguiría siendo la ciudad vieja y un
      // segundo toque de Guardar volvería a abrir el diálogo de confirmación
      // para una ciudad que ya se resolvió y ya se guardó — el bucle que
      // esta pantalla evita con cuidado en el camino de "No, corregir".
      if (resultado != ResultadoGuardado.fallo) {
        _ciudadOriginal = ciudad;
        if (lat != null) _latPerfil = lat;
        if (lng != null) _lngPerfil = lng;
        if (paisCodigo != null) _paisPerfil = paisCodigo;
        _tieneCoordenadas = _latPerfil != null && _lngPerfil != null;
        _tienePais = _paisPerfil.isNotEmpty;
      }
    });
    // canPop se evalúa UNA vez y se usa para las dos decisiones (qué
    // mostrar y si volver) — mismo criterio que ya tenía esta pantalla: si
    // no se puede volver (ej. esta pantalla no está en una pila normal de
    // navegación), el aviso de éxito no tiene sentido sin un lugar al que
    // volver, pero el de "esto está tardando" sí se muestra siempre.
    final puedeVolver = Navigator.canPop(context);
    // `lat != null` = en ESTE guardado se resolvió una ciudad con el
    // diálogo de confirmación. En ese caso NO se sale de la pantalla: la
    // ciudad que quedó guardada es la que eligió el geocodificador, no la
    // que se tecleó ("medellin antioquia" puede resolver a un barrio), así
    // que hay que poder VERLA en el campo antes de irse. Salir de una
    // dejaba a la persona sin ninguna forma de confirmar qué se guardó
    // realmente — y como la ciudad del albergue se hereda a todos sus
    // animales, equivocarse ahí se replica en cada tarjeta del feed.
    // Reportado por Eliza ~20 veces: "busco la ciudad, la selecciono, y no
    // regresa a editar, se va derecho al perfil". El resto de los
    // guardados (sin diálogo de ciudad) sí siguen saliendo como siempre:
    // ahí no hay nada nuevo que revisar.
    final huboCiudadResuelta = lat != null;
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
    _capacidadCtl.dispose();
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
                    // Igual que la ciudad y el email/web de esta misma
                    // pantalla: sin esto, escribir en un campo OBLIGATORIO
                    // no vuelve a evaluar _completo, así que Guardar sigue
                    // deshabilitado hasta tocar por casualidad alguno de
                    // los campos que sí lo tienen.
                    onChanged: (_) => setState(() {}),
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
                    // Sin esto, un número gigante (los dígitos no tienen
                    // otro límite: el formato de arriba solo exige que
                    // SEAN dígitos) desborda el rango de int.tryParse(),
                    // que devuelve null y por _completo (más abajo) eso se
                    // lee como "capacidad 0" — Guardar se queda deshabilitado
                    // para siempre, sin ningún aviso de por qué. Hallazgo
                    // real de Eliza: escribió una fila larga de dígitos y
                    // el botón no se habilitaba nunca. 6 dígitos (hasta
                    // 999.999) alcanza de sobra para cualquier albergue real.
                    maxLength: 6,
                    // Mismo motivo que el nombre y la ciudad — es un campo
                    // obligatorio, y sin esto corregir la capacidad no
                    // vuelve a habilitar Guardar.
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  // Por qué Guardar está apagado, dicho en el lugar donde
                  // se puede arreglar. `_completo` exige capacidad > 0 (un
                  // albergue con capacidad 0 hace desaparecer el panel de
                  // capacidad entero de su propio dashboard, ver el
                  // comentario de _completo), pero eso antes no se
                  // explicaba en ningún lado: el botón simplemente no se
                  // encendía y no había forma de saber cuál de los cuatro
                  // campos obligatorios faltaba. Hallazgo real de Eliza:
                  // puso capacidad 0, después escribió en Dirección, y
                  // creyó que el problema era la dirección.
                  if (_capacidadCtl.text.trim().isNotEmpty &&
                      (int.tryParse(_capacidadCtl.text.trim()) ?? 0) <= 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'La capacidad tiene que ser mayor que 0 para poder guardar.',
                        style: TextStyle(fontSize: 12, color: msgError),
                      ),
                    ),
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
                    // Igual que aliado_perfil_screen.dart: sin esto, escribir
                    // la ciudad no vuelve a evaluar _completo, así que el
                    // botón Guardar seguía deshabilitado hasta tocar OTRO
                    // campo cualquiera.
                    onChanged: (_) => setState(() {}),
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

                  // Página web (opcional)
                  perfilLabel('PÁGINA WEB (OPCIONAL)'),
                  const SizedBox(height: 8),
                  perfilCampo(
                    _webCtl,
                    'ej. www.tuAlbergue.org',
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
          if (chipCambiarRol(context) case final boton?)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: boton,
            ),
        ],
      ),
    );
  }
}
