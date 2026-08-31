// Qué contadores existen, cuándo hay que recalcularlos y de quién. Sin
// Firestore ni firebase-admin adentro, para que se pueda probar entero con
// `node --test` — mismo criterio que propagar_copias_logica.js.
//
// Por qué existen estos contadores
// --------------------------------
// Dos pantallas muestran números sobre la colección de animalitos:
//
//   Perfil del rescatista        "Animales rescatados" / "Adopciones aprobadas"
//   Perfil público del albergue  "En cuidado" (Disponibles) / "Adoptados"
//
// Hasta el APK96 salían de un stream de la consulta completa: instantáneos,
// porque un stream de Firestore entrega primero lo que hay en el caché
// local del teléfono, pero al precio de descargar TODOS los documentos para
// pintar dos números.
//
// El APK97 los pasó a `count()`, que no descarga ni un documento. Lo que no
// se vio en ese momento: `count()` es una agregación y su única fuente
// posible es el servidor (`AggregateSource` tiene un solo valor, `server`).
// O sea que dejó de descargar de más, pero pasó a pagar un viaje de red
// COMPLETO en cada apertura, sin caché posible.
//
// La prueba más limpia de eso la trajo Eliza sin buscarla: en el perfil del
// albergue, la CAPACIDAD aparece al instante y los otros dos números
// tardan. Misma pantalla, mismo momento. La capacidad sale de
// `usuarios/{uid}`, que es un documento y se sirve del caché; los otros dos
// salían de una agregación, que no.
//
// Guardando los números en `usuarios/{uid}` se consiguen las dos cosas: la
// pantalla lee UN documento —el mismo que ya leía para la capacidad, sin
// una consulta nueva— y nadie descarga la colección de animalitos.
//
// Por qué se RECUENTA y no se incrementa
// --------------------------------------
// Eventarc entrega "al menos una vez": el mismo evento puede volver a
// disparar el trigger tras una falla transitoria o un redespliegue. Con
// `FieldValue.increment(1)` ese reintento suma dos veces y el número queda
// mal PARA SIEMPRE, porque nada lo vuelve a mirar. Es exactamente el bug
// que ya tuvimos con "11 adopciones aprobadas" y 1 animal adoptado.
//
// Recontar con `count()` del lado del servidor es idempotente por
// construcción: dos entregas del mismo evento escriben el mismo número. Y
// además se autocorrige, porque cualquier desvío que llegara a colarse
// queda arreglado en la siguiente alta, baja o cambio de estado.
//
// El costo lo paga el servidor y es una agregación, no una descarga: el
// teléfono no baja ningún documento.

/// Qué se guarda para cada rol.
///
/// **Una sola tabla para los dos roles, no un módulo por rol.** Lo único
/// que cambia entre un albergue y un rescatista es el valor de `creadoPor`
/// y qué estados cuentan para el primer número; todo lo demás (cuándo
/// recontar, cómo contar, dónde escribir, el backfill) es idéntico. Con dos
/// implementaciones paralelas habría dos lugares donde arreglar el mismo
/// bug, y la app ya pagó eso varias veces.
///
/// `estados: null` quiere decir "todos los estados, sin filtrar".
///
/// **Las definiciones son las que ya tenían las pantallas, sin cambios.**
/// Ojo con que NO son simétricas: el primer número del rescatista son
/// todos sus animalitos en cualquier estado, mientras que el del albergue
/// son solo los que están en cuidado. Por eso uno se llama `Total` y el
/// otro `EnCuidado`; llamarlos igual invitaría a suponer que cuentan lo
/// mismo.
const DEFINICIONES = [
  {
    rol: 'rescatista',
    campos: [
      // "Animales rescatados": todos, incluidos los adoptados y los
      // fallecidos. Es la definición que ya tenía perfil_rescatista_screen.
      { campo: 'contadorRescatistaTotal', estados: null },
      // "Adopciones aprobadas": animalitos cuyo estadoAdopcion ACTUAL es
      // 'Adoptado'. NO las solicitudes con estado 'aprobada', que suman los
      // hogares de paso y nunca restan.
      { campo: 'contadorRescatistaAdoptados', estados: ['Adoptado'] },
    ],
  },
  {
    rol: 'albergue',
    campos: [
      // "En cuidado" / "Disponibles": la misma lista `estadosEnCuidado` que
      // usa la grilla de albergue_publico_screen, para que el número y la
      // cantidad de tarjetas no puedan discrepar. NO incluye 'Hogar de
      // paso': esos animalitos siguen siendo adoptables en el resto de la
      // app, solo no se listan en ese perfil.
      { campo: 'contadorAlbergueEnCuidado', estados: ['Rescatado', 'Regresado'] },
      { campo: 'contadorAlbergueAdoptados', estados: ['Adoptado'] },
    ],
  },
];

/** Todos los nombres de campo que mantiene este módulo. */
const CAMPOS = DEFINICIONES.flatMap((d) => d.campos.map((c) => c.campo));

/** La definición de [rol], o `undefined` si ese rol no lleva contadores. */
function definicionDe(rol) {
  return DEFINICIONES.find((d) => d.rol === rol);
}

/** Un animalito entra en algún contador solo si tiene rol y dueño. */
function cuentaParaAlgunContador(datos) {
  return !!datos &&
    !!definicionDe(datos.creadoPor) &&
    typeof datos.rescatistaId === 'string' &&
    datos.rescatistaId !== '';
}

/** A qué contador pertenece este animalito. */
function claveDe(datos) {
  return { uid: datos.rescatistaId, rol: datos.creadoPor };
}

/**
 * Los contadores que hay que recalcular después de esta escritura, como
 * pares `{ uid, rol }`. Vacío si no hay nada que hacer.
 *
 * **El guard es lo que hace esto barato.** `onPerfilActualizado` reescribe
 * EN MASA todos los animalitos de una cuenta cada vez que esa persona
 * cambia su nombre o su foto. Sin este filtro, cambiar una foto dispararía
 * dos agregaciones por cada animalito. Con él, esas escrituras no tocan
 * `estadoAdopcion` y salen de acá con las manos vacías.
 *
 * Devuelve una lista y no un par suelto por un caso que hoy no puede pasar
 * pero que no quiero que dependa de eso: si un animalito cambiara de dueño
 * o de rol, hay DOS contadores que quedan mal. Las reglas prohíben mover
 * `rescatistaId` y `creadoPor` después de creado (firestore.rules), así que
 * solo llegaría por una escritura de admin; igual queda cubierto.
 */
function aRecontar({ antes, despues }) {
  const contabaAntes = cuentaParaAlgunContador(antes);
  const cuentaAhora = cuentaParaAlgunContador(despues);

  // Ni antes ni ahora entra en un contador: no hay nada que mover.
  if (!contabaAntes && !cuentaAhora) return [];

  // Alta (o algo que recién ahora pasa a contar).
  if (!contabaAntes) return [claveDe(despues)];

  // Baja (o algo que dejó de contar).
  if (!cuentaAhora) return [claveDe(antes)];

  const antesClave = claveDe(antes);
  const ahoraClave = claveDe(despues);

  // Cambió de dueño o de rol: quedan dos contadores desactualizados.
  if (antesClave.uid !== ahoraClave.uid || antesClave.rol !== ahoraClave.rol) {
    return [antesClave, ahoraClave];
  }

  // El único cambio que mueve un número es el estado. Todo lo demás
  // (nombre, foto, ubicación, descripción) deja los contadores igual.
  if (antes.estadoAdopcion !== despues.estadoAdopcion) return [ahoraClave];

  return [];
}

/**
 * true si el perfil `actual` no tiene ya exactamente los números `nuevos`.
 * Lo usa el backfill para no reescribir cuentas que ya están bien, y para
 * poder mostrar en el simulacro qué cambiaría.
 *
 * Un campo ausente cuenta como desactualizado: es el caso de las cuentas
 * viejas, que son justamente las que el backfill viene a sembrar.
 */
function contadoresDesactualizados(actual, nuevos) {
  const hoy = actual || {};
  return Object.keys(nuevos).some((campo) => hoy[campo] !== nuevos[campo]);
}

module.exports = {
  DEFINICIONES,
  CAMPOS,
  definicionDe,
  cuentaParaAlgunContador,
  aRecontar,
  contadoresDesactualizados,
};
