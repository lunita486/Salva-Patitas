import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../data/auth_helper.dart';
import '../data/cuenta_repository.dart';
import '../data/servicios_repository.dart';

/// Punto de entrada único del flujo de "Eliminar mi cuenta" — mismo
/// criterio que `mostrarCambiarRolDebug` (widgets/cambiar_rol_debug.dart): una sola función
/// compartida por las 4 pantallas que tienen el botón, en vez de duplicar
/// un diálogo bastante más grande que el simple "Cerrar sesión" (acá hay
/// un paso extra de confirmación escrita, un estado de "procesando" y 3
/// desenlaces distintos) 4 veces.
///
/// Por qué un paso más que el "Cancelar/Cerrar sesión" de siempre: esto no
/// se puede deshacer y borra datos personales de verdad — el mismo criterio
/// que usan apps como GitHub para borrar un repositorio. Un solo toque es
/// poco para algo de esta escala.
///
/// [mostrarParrafoAdopciones]: el párrafo de "si tenés una adopción o un
/// hogar de paso ya aprobado..." — cada pantalla que llama a esto decide si
/// le aplica a SU rol (`true` en adoptante/rescatista/albergue, `false` en
/// aliado). No se decide mirando los roles guardados de la cuenta: una
/// versión anterior sí lo hacía (para que una cuenta con doble rol, ej.
/// rescatista + aliado, siguiera viendo el párrafo aunque entrara desde el
/// lado del negocio), pero es más simple pensarlo por PANTALLA — este
/// diálogo habla de lo que se pierde EN ESE ROL, sin importar qué otros
/// roles tenga la cuenta. Pedido explícito de Eliza probando el perfil de
/// Aliado: "el mensaje para el aliado debería solo decir el tema del
/// aliado, no mencionar el tema de la adopción".
Future<void> mostrarEliminarCuentaDialog(
  BuildContext context, {
  bool mostrarParrafoAdopciones = true,
}) async {
  // Solo informa, no bloquea — pedido explícito de Eliza: no tiene sentido
  // obligar a borrar servicios a mano antes de poder irse, si de cualquier
  // forma se van a borrar solos como parte de eliminarCuenta (ver
  // functions/eliminar_cuenta.js, borra todo `servicios` con
  // aliadoId==uid). Esto es SOLO para que la persona sepa qué se pierde
  // antes de confirmar, mismo criterio que el párrafo de adopciones/hogares
  // de paso de acá abajo. best-effort: si esta consulta falla (sin señal),
  // se sigue sin el aviso extra en vez de trabar el diálogo entero por un
  // dato secundario.
  // Mismo criterio que mostrarParrafoAdopciones (ver doc de arriba): esto
  // habla de lo que se pierde EN ESE ROL, así que solo tiene sentido
  // consultarlo desde la pantalla de Aliado — y como mostrarParrafoAdopciones
  // ya es false únicamente para esa pantalla, se deriva de ahí en vez de
  // agregar un parámetro aparte. Antes se consultaba SIEMPRE, sin mirar
  // desde qué pantalla se abrió el diálogo: una cuenta con doble rol (ej.
  // adoptante + aliado, algo común probando la app) veía este párrafo de
  // "servicios activos" también al eliminar desde el lado de Adoptante,
  // donde no aplica para nada. Hallazgo real de Eliza.
  final esPantallaAliado = !mostrarParrafoAdopciones;
  var tieneServiciosActivos = false;
  if (esPantallaAliado) {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        // ServiciosRepository.tieneServiciosActivos — antes acá vivía un
        // `.where('activo', isEqualTo: true).limit(1)` armado a mano, que
        // era el criterio MÁS estricto de los cuatro que había en la app:
        // al filtrar dentro de la consulta, Firestore descarta los
        // servicios sin ese campo antes de que el código los vea. O sea
        // que a alguien con servicios encendidos en su propia lista, este
        // aviso le decía que no tenía ninguno activo y lo dejaba borrar la
        // cuenta igual. Ver el doc de ServiciosRepository.
        tieneServiciosActivos = await ServiciosRepository()
            .tieneServiciosActivos(uid);
      }
    } catch (_) {}
  }
  if (!context.mounted) return;

  final continuar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Eliminar mi cuenta'),
      content: Text(
        'Esto borra tu perfil y tus datos de la app de forma permanente. '
        'No se puede deshacer.'
        '${mostrarParrafoAdopciones ? '\n\nSi tenés una adopción o un hogar de paso ya aprobado, ese registro se conserva (sin tu nombre ni tus datos) porque el rescatista o albergue necesita mantener la prueba de que el animal encontró hogar.' : ''}'
        '${tieneServiciosActivos ? '\n\nTenés servicios activos publicados. Se van a eliminar junto con tu cuenta, y cualquier conversación abierta con quien te haya consultado va a quedar sin tu información.' : ''}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            'Continuar',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  if (continuar != true || !context.mounted) return;

  final confirmado = await showDialog<bool>(
    context: context,
    builder: (_) => const _ConfirmarEscribiendoDialog(),
  );
  if (confirmado != true || !context.mounted) return;

  // ── Por qué el spinner NO se cierra con `context` ──────────────────────
  //
  // El borrado del servidor incluye `usuarios/{uid}`, y esa baja le llega al
  // cliente por el stream que escucha AuthWrapper: la pantalla desde la que
  // se tocó "Eliminar mi cuenta" se desmonta SOLA mientras todavía estamos
  // esperando la respuesta. Con el contexto desmontado, cada rama de abajo
  // hacía `if (!context.mounted) return;` y se iba SIN cerrar el spinner.
  //
  // Y ese spinner no se puede descartar (barrierDismissible: false y
  // PopScope canPop: false), así que quedaba tapando la pantalla nueva para
  // siempre: la única salida era matar la app.
  //
  // Bug real de Eliza borrando un aliado: "sale eliminando tu cuenta y no
  // pasa nada, se queda ahí... y al fondo se ve Hola, Carmen, ¿cómo vas a
  // entrar?". Ese fondo ES la pantalla de elegir rol, y es la prueba: el
  // borrado había avanzado y quien esperaba la respuesta ya no existía.
  //
  // Le pasa a los 4 roles, no solo a Aliado: las 4 pantallas llaman a esta
  // misma función y todas escuchan ese documento. Que aparezca o no depende
  // de si la baja del documento llega antes que la respuesta, que es una
  // carrera.
  //
  // El navegador raíz sobrevive a ese cambio —AuthWrapper reemplaza lo que
  // cuelga de él, no a él— así que cerrar el spinner con esta referencia
  // funciona aunque el contexto de origen ya no esté.
  final navegador = Navigator.of(context, rootNavigator: true);
  final avisos = ScaffoldMessenger.of(context);

  // No descartable — el borrado recorre 8 colecciones del lado del
  // servidor, puede tardar más que un guardado normal.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: const [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: appTeal,
                strokeWidth: 2.5,
              ),
            ),
            SizedBox(width: 20),
            Expanded(child: Text('Eliminando tu cuenta…')),
          ],
        ),
      ),
    ),
  );

  // Se cierra UNA sola vez, pase lo que pase. Que cada rama lo hiciera por
  // su cuenta es lo que dejaba caminos sin cerrarlo.
  var spinnerAbierto = true;
  void cerrarSpinner() {
    if (!spinnerAbierto) return;
    spinnerAbierto = false;
    navegador.pop();
  }

  try {
    await CuentaRepository().eliminarCuenta();
    cerrarSpinner();
    // El borrado ya pasó del lado del servidor (incluida la cuenta de
    // Firebase Auth) — cerrar sesión acá es solo para que el cliente lo
    // note: sin esto, AuthWrapper (main.dart) seguiría mostrando la sesión
    // vieja hasta el próximo reinicio de la app.
    await cerrarSesion();
    // Si el contexto ya no está, AuthWrapper YA cambió de pantalla solo:
    // no hay nada que desapilar.
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  } on CuentaBloqueada catch (e) {
    cerrarSpinner();
    // navegador.context y no `context`: el de origen puede haberse
    // desmontado, y este aviso tiene que salir igual.
    await showDialog<void>(
      context: navegador.context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('No se puede eliminar todavía'),
        content: Text(e.mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  } on TimeoutException {
    // El timeout es del CLIENTE (30s) esperando la respuesta — no cancela
    // el borrado, que sigue corriendo del lado del servidor (tiene su
    // propio límite de 300s, y recorre 8 colecciones: para una cuenta con
    // muchos chats/mensajes puede tardar más). Mostrar el mensaje genérico
    // de "no pudimos eliminar, revisá tu conexión" acá sería mentirle a la
    // persona — lo más probable es que el borrado termine bien igual.
    cerrarSpinner();
    await showDialog<void>(
      context: navegador.context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Esto está tardando más de lo normal'),
        content: const Text(
          'Tu cuenta se sigue eliminando del lado del servidor — no hace '
          'falta que vuelvas a intentarlo. Cerrá la app y, en unos '
          'minutos, probá iniciar sesión de nuevo: si ya no podés entrar, '
          'es que terminó bien.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  } catch (e) {
    cerrarSpinner();
    avisos.showSnackBar(
      SnackBar(
        backgroundColor: msgError,
        content: Text(CuentaRepository.mensajeError(e)),
      ),
    );
  }
}

class _ConfirmarEscribiendoDialog extends StatefulWidget {
  const _ConfirmarEscribiendoDialog();
  @override
  State<_ConfirmarEscribiendoDialog> createState() =>
      _ConfirmarEscribiendoDialogState();
}

class _ConfirmarEscribiendoDialogState
    extends State<_ConfirmarEscribiendoDialog> {
  final _ctl = TextEditingController();
  bool _habilitado = false;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() {
      final habilitado = _ctl.text.trim().toUpperCase() == 'ELIMINAR';
      if (habilitado != _habilitado) setState(() => _habilitado = habilitado);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('¿Seguro que querés eliminar tu cuenta?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Escribí ELIMINAR para confirmar.'),
        const SizedBox(height: 12),
        TextField(
          controller: _ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancelar'),
      ),
      TextButton(
        onPressed: _habilitado ? () => Navigator.pop(context, true) : null,
        child: Text(
          'Eliminar mi cuenta',
          style: TextStyle(
            color: _habilitado ? Colors.red : Colors.grey.shade400,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}
