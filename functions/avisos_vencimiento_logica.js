// Lógica pura de "¿toca avisar hoy que un hogar de paso vence mañana o ya
// venció?" — sin ninguna llamada a Firestore acá adentro, a propósito
// (mismo criterio que eliminar_cuenta_logica.js): permite testear con
// `node --test` simple, sin depender del emulador.
//
// Mismo criterio EXACTO que verificarVencimientos() del lado del cliente
// (lib/screens/solicitudes_rescatista_screen.dart) — dos flags separados
// (avisoPrevioAvisado/vencimientoAvisado) para que el aviso de "vence
// mañana" y el de "ya venció" no se pisen entre sí, cada uno se manda una
// sola vez.

function textoVenceManana(nombre) {
  return `📋 El período de hogar de paso de ${nombre} vence mañana. `
    + 'Coordiná con tiempo la devolución o el proceso de adopción definitivo. 🐾';
}

function textoVencido(nombre) {
  return `📋 El período de hogar de paso de ${nombre} ha vencido. `
    + 'Por favor coordina la devolución o el proceso de adopción definitivo. 🐾';
}

function sinHora(fecha) {
  return new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate());
}

// null si no toca avisar nada (todavía falta más de un día, o ya se avisó
// lo que correspondía) — si no, { tipo, flag, mensaje } con el flag que hay
// que marcar en `rescates/{id}` para no volver a mandar este mismo aviso.
function decidirAviso({ fechaFin, ahora, avisoPrevioAvisado, vencimientoAvisado, nombre }) {
  if (fechaFin > ahora) {
    const diasRestantes = Math.round((sinHora(fechaFin) - sinHora(ahora)) / 86400000);
    if (diasRestantes === 1 && avisoPrevioAvisado !== true) {
      return { tipo: 'previo', flag: 'avisoPrevioAvisado', mensaje: textoVenceManana(nombre) };
    }
    return null;
  }
  if (vencimientoAvisado === true) return null;
  return { tipo: 'vencido', flag: 'vencimientoAvisado', mensaje: textoVencido(nombre) };
}

module.exports = { decidirAviso, textoVenceManana, textoVencido };
