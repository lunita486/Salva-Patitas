// Lógica pura de "¿qué copias hay que refrescar cuando cambia un animal o
// el perfil de un albergue?" — sin ninguna llamada a Firestore acá
// adentro, a propósito (mismo criterio que avisos_vencimiento_logica.js y
// eliminar_cuenta_logica.js): permite testear con `node --test` simple,
// sin depender del emulador.
//
// ── Por qué esto vive en el servidor ──────────────────────────────────
// Varios datos del animal y del albergue se COPIAN dentro de otros
// documentos al crearlos (una solicitud guarda `animalNombre`/`fotoUrl`;
// un chat guarda `animalNombre`/`fotoUrl`/`rescatista`/`fotoBase64`; cada
// animal de un albergue guarda `ubicacion`/`rescatistaNombre`/...). Se
// copian para no tener que leer 3 documentos por fila en el feed y en las
// bandejas, y esa decisión se mantiene.
//
// Lo que cambió es QUIÉN mantiene esas copias al día. Antes lo hacía solo
// la app, "best-effort" y en segundo plano, y ese camino falló de todas
// las formas posibles, cada una en silencio:
//   - la consulta no estaba acotada al dueño y las reglas la rechazaban
//     entera (permission-denied, tapado por un catchError vacío);
//   - la regla de update no contemplaba esos campos;
//   - la sincronización solo corría cuando el dato CAMBIABA, así que una
//     copia que ya había quedado vieja no tenía forma de repararse;
//   - y si la persona cerraba la app o se quedaba sin señal justo ahí, se
//     perdía sin dejar rastro.
// Eliza reportó el mismo síntoma más de 20 veces por estos caminos.
//
// Un trigger de Firestore no tiene ninguno de esos problemas: corre con
// permisos de admin (las reglas no aplican), corre aunque la app esté
// cerrada, reintenta solo si falla, y vale para TODAS las versiones de la
// app instaladas, sin necesidad de que nadie actualice nada. La app sigue
// haciendo su copia local para que la pantalla se sienta instantánea,
// pero ya no es de quien depende que el dato quede bien.

// Campos del animal (`rescates/{id}`) que otras colecciones copian, con el
// nombre que tiene cada uno en el documento destino. Único lugar donde
// vive esta correspondencia.
//
// Un CHAT solo necesita saber de qué animal se habla: su nombre y su foto.
const CAMPOS_ANIMAL_A_CHAT = {
  // en rescates  ->  en chats
  nombre: 'animalNombre',
  fotoUrl: 'fotoUrl',
};

// Una SOLICITUD necesita lo mismo MÁS las etiquetas con las que se calcula
// el puntaje de compatibilidad que ve quien decide aprobarla o rechazarla.
//
// Esas 5 etiquetas se copiaban UNA vez, al crear la solicitud
// (solicitud_adopcion_screen.dart), y después nada las volvía a tocar —
// mientras los valores reales del animal sí cambian cada vez que se edita
// su ficha. Resultado: el rescatista descubre que el perro no es apto con
// niños, lo corrige, y la solicitud que tiene en la bandeja le sigue
// mostrando "✓ Hay niños y el animal los acepta bien — Perfil ideal
// (100%)". Aprueba mirando información que ya no es cierta. Del lado del
// adoptante, el feed calcula ese MISMO puntaje con los datos en vivo, así
// que los dos ven números distintos del mismo par.
const CAMPOS_ANIMAL_A_SOLICITUD = {
  ...CAMPOS_ANIMAL_A_CHAT,
  energia: 'animalEnergia',
  tamano: 'animalTamano',
  okConNinos: 'animalOkConNinos',
  okConMascotas: 'animalOkConMascotas',
  requiereExperiencia: 'animalRequiereExp',
};

// Campos del perfil (`usuarios/{uid}`) que cada animal del albergue copia.
const CAMPOS_PERFIL_A_ANIMAL = {
  ciudad: 'ubicacion',
  latitud: 'latitud',
  longitud: 'longitud',
  paisCodigo: 'paisCodigo',
  albergueNombre: 'rescatistaNombre',
  fotoBase64: 'rescatistaFotoBase64',
};

// Campo del perfil que cada chat de ANIMAL del albergue copia: solo el
// nombre, con el que queda firmado el chat — NUNCA `fotoBase64`, aunque
// `usuarios/{uid}` tenga ese mismo campo. Esa foto (el logo del albergue)
// no le sirve de nada al chat de un animal: la foto grande de esa fila es
// la del ANIMAL (`fotoUrl`, la sincroniza aparte onRescateActualizado), y
// la foto del albergue se muestra en una insignia chica que YA la lee en
// vivo de `usuarios/{uid}` (ver ChatsRepository.campoLogoRescatista/
// campoLogoAdoptante) — sin ninguna copia de por medio, nunca desactualizada
// por diseño. Escribir `fotoBase64` acá corrompía ESE campo en un chat de
// animal, donde la pantalla de Chats nunca debió tener nada — y como esa
// pantalla mira `fotoBase64` ANTES que `fotoUrl` para decidir la foto
// grande (piensa que un `fotoBase64` presente es un chat de negocio), la
// foto del animal quedaba tapada por la del albergue: la insignia chica
// (correcta, en vivo) y la foto grande (mal, desde esta copia) mostraban
// la MISMA foto del albergue en vez de albergue + animal. Hallazgo real
// de Eliza: "se ven mal las fotos, se tienen dos circulitos donde debería
// mostrar la foto del animalito y la foto del albergue".
const CAMPOS_PERFIL_A_CHAT = {
  albergueNombre: 'rescatista',
};

// Lo que copia un animal publicado como RESCATISTA (no como albergue).
//
// Es un mapa aparte y NO una variante del de albergue, a proposito: un
// animal de rescatista no hereda nada de la ficha del refugio. Ni la
// direccion (el animal esta donde lo encontraron, no donde queda el
// albergue) ni el logo ni el nombre del refugio. Solo la persona.
//
// `foto` es la copia que main.dart mantiene al dia contra el photoURL de
// Google. Existe justamente para esto: FirebaseAuth solo expone al usuario
// propio, asi que un trigger (y cualquier pantalla que quiera mostrar a la
// CONTRAPARTE) tiene que leerla de `usuarios/{uid}`.
//
// Antes esta copia no se refrescaba nunca: quien cambiaba su foto de
// Google, o se corregia el nombre en la app, seguia apareciendo con los
// viejos en cada animal que ya habia publicado.
const CAMPOS_PERFIL_A_ANIMAL_RESCATISTA = {
  nombre: 'rescatistaNombre',
  foto: 'rescatistaFotoUrl',
};

// El lado del ADOPTANTE, que hasta ahora no se refrescaba nunca.
//
// `solicitudes.nombre` y `chats.adoptanteNombre` son copias del nombre de
// quien pidió, hechas en el momento de pedir. Es exactamente el mismo
// patrón que ya nos mordió tres veces del lado del rescatista: el dato se
// copia y nada lo vuelve a mirar. Alguien que se registró con el nombre
// que le puso Google y después lo corrigió en su perfil seguía apareciendo
// con el viejo en cada solicitud que ya había mandado — y ese es
// justamente el nombre que lee el rescatista para decidir a quién le
// entrega un animal.
//
// `email` NO se propaga a propósito: es el de la cuenta de Auth, no un
// campo del perfil, así que no cambia acá y no hay nada que refrescar.
const CAMPOS_PERFIL_A_SOLICITUD = {
  nombre: 'nombre',
};

const CAMPOS_PERFIL_A_CHAT_ADOPTANTE = {
  nombre: 'adoptanteNombre',
};

/**
 * Campos que NO deben existir en un chat de animal, y hay que BORRAR si
 * están — no alcanza con dejar de escribirlos.
 *
 * `fotoBase64` es exclusivo de las consultas a negocios (ahí guarda el logo
 * del aliado). Una versión anterior de este trigger lo escribía también en
 * los chats de animal (ver el comentario de CAMPOS_PERFIL_A_CHAT), y esa
 * escritura dejó datos corruptos que NO se limpian solos: dejar de
 * escribirlo evita empeorar, pero el valor viejo sigue ahí. Y molesta de
 * verdad, porque la lista de chats mira `fotoBase64` ANTES que `fotoUrl`
 * (un fotoBase64 presente significa "esto es un chat de negocio"): con el
 * logo viejo del albergue pegado ahí, la fila muestra ESE logo en vez de
 * la foto del animalito, mientras que al abrir el chat se ve bien —
 * porque el encabezado lee el perfil en vivo, sin pasar por esta copia.
 * Hallazgo real de Eliza: cambió la foto del albergue y en la lista de
 * chats del adoptante seguía viendo la vieja, pero al entrar al chat veía
 * la nueva.
 */
const CAMPOS_A_BORRAR_EN_CHAT_DE_ANIMAL = ['fotoBase64'];

/**
 * `creadoPor` está SOBRECARGADO entre las dos formas de chat, y significa
 * cosas distintas en cada una: en un chat de ANIMAL dice con qué rol se
 * publicó el animal; en una CONSULTA A UN ALIADO dice con qué rol contactó
 * quien escribió — dos preguntas completamente distintas que comparten el
 * mismo nombre de campo. Filtrar CAMPOS_PERFIL_A_CHAT (pensado solo para
 * chats de ANIMAL) por `creadoPor == 'albergue'` sin este chequeo también
 * agarraba chats de consulta_aliado donde esa cuenta figura como
 * rescatistaId (una cuenta que es albergue Y aliado a la vez, o cualquier
 * consulta donde ella es la aliada consultada) — pisándoles
 * `fotoBase64`/`rescatista` con la identidad de ALBERGUE en vez de la de
 * ALIADO que corresponde ahí. `tipoSolicitud == 'consulta_aliado'` nunca
 * aparece en un chat de animal, así que excluirlo es inambiguo. Hallazgo
 * real de Eliza: abrió el chat con "VetPet la 30" (un negocio) y vio el
 * nombre/foto del ALBERGUE en su lugar — con apenas 2 albergues y 2
 * negocios de prueba en todo el sistema.
 */
function esChatDeAnimal(datosChat) {
  return datosChat.tipoSolicitud !== 'consulta_aliado';
}

// Lo mismo para un negocio aliado. Los campos DESTINO son los mismos que
// los del albergue (un chat es un chat), pero los de ORIGEN son otros:
// una misma cuenta puede tener rol de albergue Y de aliado a la vez, así
// que cada rol guarda su nombre y su logo por separado en el perfil
// (`albergueNombre`/`fotoBase64` vs `aliadoNombre`/`aliadoFotoBase64`).
// Mezclarlos fue un bug real: llenar el contacto del albergue se veía en
// el perfil de aliado de la misma cuenta.
// `animalNombre` no es un error de copiar/pegar: al crear una consulta,
// asegurarChatNegocio guarda el nombre del negocio en DOS campos a la vez
// (`rescatista` y `animalNombre`), porque la colección `chats` tiene
// esquema mixto y cada pantalla lee uno distinto — el encabezado del chat
// usa `rescatista`, y la tarjeta "Conversando con ..." (más el fallback de
// la inicial) usa `animalNombre`, el mismo campo que en un chat de animal
// lleva el nombre del animalito. Reparar solo uno deja al otro con el
// nombre viejo: hallazgo real de Eliza, el encabezado decía "VetPet la 30"
// (ya reparado) y justo abajo "Conversando con Veterinario la 30" (el
// nombre anterior del mismo negocio).
const CAMPOS_PERFIL_ALIADO_A_CHAT = {
  aliadoNombre: ['rescatista', 'animalNombre'],
  aliadoFotoBase64: 'fotoBase64',
};

/**
 * Qué escribir en los documentos destino, dado el antes y el después de un
 * documento fuente y el mapa de campos que corresponda.
 *
 * Devuelve `null` si no cambió ninguno de los campos que se copian — el
 * caso abrumadoramente más común (marcar un animal como adoptado, tocar su
 * descripción, cambiar la capacidad del albergue...). Devolver null ahí es
 * lo que evita reescribir cientos de documentos en cada guardado.
 *
 * Solo incluye los campos que REALMENTE cambiaron: si se cambió la foto
 * pero no el nombre, el destino recibe únicamente la foto. Así dos cambios
 * distintos nunca se pisan entre sí, y una copia que alguien corrigió a
 * mano no se sobreescribe sin motivo.
 *
 * Un valor que se borra (queda `undefined`) se ignora en vez de escribir
 * `undefined` — Firestore lo rechazaría, y "el animal ya no tiene segunda
 * foto" no es algo que las copias necesiten saber.
 */
/**
 * TODOS los valores que el destino debería tener ahora mismo, mire lo que
 * mire el "antes" — a diferencia de [cambiosAPropagar], que solo devuelve
 * lo que cambió en ESTE guardado.
 *
 * Hace falta para REPARAR, no solo para mantener al día. Una copia que
 * quedó mal por un bug anterior no se arregla con "propagá lo que cambió":
 * si el nombre del negocio no cambió en este guardado, ese campo no viaja,
 * y la copia corrupta sobrevive intacta para siempre. Hallazgo real de
 * Eliza: le cambió la FOTO a su negocio aliado y la foto del chat se
 * reparó sola (prueba de que la propagación funciona), pero el NOMBRE
 * siguió mostrando el del albergue — porque el nombre no había cambiado y
 * por lo tanto nunca se propagó.
 *
 * Se usa junto con [desactualizado] para que esto no se convierta en
 * "reescribir todo en cada guardado": se piden los valores deseados, se
 * comparan contra lo que cada documento tiene HOY, y solo se escriben los
 * que de verdad difieren. Self-healing sin escrituras de más.
 */
/**
 * El destino de un campo puede ser uno solo ('rescatista') o varios
 * (['rescatista', 'animalNombre']) — ver CAMPOS_PERFIL_ALIADO_A_CHAT para
 * el caso real donde el mismo dato de origen tiene que viajar a dos campos
 * distintos del MISMO documento.
 */
function destinosDe(campoDestino) {
  return Array.isArray(campoDestino) ? campoDestino : [campoDestino];
}

function valoresDeseados({ despues, campos }) {
  const deseados = {};
  for (const [campoOrigen, campoDestino] of Object.entries(campos)) {
    const valor = despues?.[campoOrigen];
    if (valor === undefined) continue;
    for (const destino of destinosDe(campoDestino)) deseados[destino] = valor;
  }
  return Object.keys(deseados).length === 0 ? null : deseados;
}

/**
 * ¿Este documento destino tiene algún campo distinto de lo que debería?
 * Es el filtro que evita escribir en documentos que ya están bien.
 */
function desactualizado(datosDestino, deseados, aBorrar = []) {
  const algunValorMal = Object.entries(deseados).some(
      ([campo, valor]) => datosDestino?.[campo] !== valor,
  );
  // Un campo que sobra también cuenta como "desactualizado" — si no, un
  // documento con SOLO basura para borrar (todo lo demás correcto) nunca
  // entraría al batch y quedaría corrupto para siempre.
  const sobraAlguno = aBorrar.some(
      (campo) => datosDestino?.[campo] !== undefined,
  );
  return algunValorMal || sobraAlguno;
}

function cambiosAPropagar({ antes, despues, campos }) {
  const cambios = {};
  for (const [campoOrigen, campoDestino] of Object.entries(campos)) {
    const valorNuevo = despues?.[campoOrigen];
    if (valorNuevo === undefined) continue;
    if (antes?.[campoOrigen] === valorNuevo) continue;
    for (const destino of destinosDe(campoDestino)) cambios[destino] = valorNuevo;
  }
  return Object.keys(cambios).length === 0 ? null : cambios;
}

/**
 * Un WriteBatch tiene un tope duro de 500 operaciones. Un albergue con más
 * de 500 animales, o un animal con más de 500 solicitudes, haría que
 * `commit()` tirara y —con un catch -por-arriba— NINGUNA copia se
 * actualizaría, ni siquiera las primeras 500. Mismo criterio y mismo tope
 * que onRescateEliminado con los favoritos.
 */
function enTandas(items, tamano = 500) {
  const tandas = [];
  for (let i = 0; i < items.length; i += tamano) {
    tandas.push(items.slice(i, i + tamano));
  }
  return tandas;
}

module.exports = {
  CAMPOS_ANIMAL_A_CHAT,
  CAMPOS_ANIMAL_A_SOLICITUD,
  CAMPOS_PERFIL_A_ANIMAL,
  CAMPOS_PERFIL_A_ANIMAL_RESCATISTA,
  CAMPOS_PERFIL_A_CHAT,
  CAMPOS_PERFIL_A_SOLICITUD,
  CAMPOS_PERFIL_A_CHAT_ADOPTANTE,
  CAMPOS_A_BORRAR_EN_CHAT_DE_ANIMAL,
  CAMPOS_PERFIL_ALIADO_A_CHAT,
  cambiosAPropagar,
  valoresDeseados,
  desactualizado,
  enTandas,
  esChatDeAnimal,
};
