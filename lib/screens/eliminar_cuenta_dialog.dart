import 'package:flutter/material.dart';
import '../theme.dart';
import '../data/auth_helper.dart';
import '../data/cuenta_repository.dart';

/// Punto de entrada único del flujo de "Eliminar mi cuenta" — mismo
/// criterio que `mostrarCambiarRolDebug` (theme.dart): una sola función
/// compartida por las 4 pantallas que tienen el botón, en vez de duplicar
/// un diálogo bastante más grande que el simple "Cerrar sesión" (acá hay
/// un paso extra de confirmación escrita, un estado de "procesando" y 3
/// desenlaces distintos) 4 veces.
///
/// Por qué un paso más que el "Cancelar/Cerrar sesión" de siempre: esto no
/// se puede deshacer y borra datos personales de verdad — el mismo criterio
/// que usan apps como GitHub para borrar un repositorio. Un solo toque es
/// poco para algo de esta escala.
Future<void> mostrarEliminarCuentaDialog(BuildContext context) async {
  final continuar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Eliminar mi cuenta'),
      content: const Text(
        'Esto borra tu perfil y tus datos de la app de forma permanente. '
        'No se puede deshacer.\n\n'
        'Si tenés una adopción o un hogar de paso ya aprobado, ese registro '
        'se conserva (sin tu nombre ni tus datos) porque el rescatista o '
        'albergue necesita mantener la prueba de que el animal encontró '
        'hogar.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continuar', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
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

  // No descartable — el borrado recorre 8 colecciones del lado del
  // servidor, puede tardar más que un guardado normal.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(children: const [
          SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(color: appTeal, strokeWidth: 2.5)),
          SizedBox(width: 20),
          Expanded(child: Text('Eliminando tu cuenta…')),
        ]),
      ),
    ),
  );

  try {
    await CuentaRepository().eliminarCuenta();
    if (!context.mounted) return;
    Navigator.pop(context); // cierra "Eliminando tu cuenta…"
    // El borrado ya pasó del lado del servidor (incluida la cuenta de
    // Firebase Auth) — cerrar sesión acá es solo para que el cliente lo
    // note: sin esto, AuthWrapper (main.dart) seguiría mostrando la sesión
    // vieja hasta el próximo reinicio de la app.
    await cerrarSesion();
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  } on CuentaBloqueada catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context); // cierra "Eliminando tu cuenta…"
    await showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('No se puede eliminar todavía'),
        content: Text(e.mensaje),
        actions: [TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Entendido'))],
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context); // cierra "Eliminando tu cuenta…"
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: msgError, content: Text(CuentaRepository.mensajeError(e))));
  }
}

class _ConfirmarEscribiendoDialog extends StatefulWidget {
  const _ConfirmarEscribiendoDialog();
  @override
  State<_ConfirmarEscribiendoDialog> createState() => _ConfirmarEscribiendoDialogState();
}

class _ConfirmarEscribiendoDialogState extends State<_ConfirmarEscribiendoDialog> {
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
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
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
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
      TextButton(
        onPressed: _habilitado ? () => Navigator.pop(context, true) : null,
        child: Text('Eliminar mi cuenta',
            style: TextStyle(
                color: _habilitado ? Colors.red : Colors.grey.shade400,
                fontWeight: FontWeight.w600)),
      ),
    ],
  );
}
