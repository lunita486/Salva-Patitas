import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/salva_patitas_theme.dart';

import '../data/contexto_albergue.dart';
import '../data/chats_repository.dart';
import '../data/rescates_repository.dart';
import '../data/solicitudes_repository.dart';
import '../data/usuarios_repository.dart';
import '../domain/reglas_negocio.dart';
import 'sp_widgets.dart';
import '../data/hogares_de_paso_repository.dart';
import 'pedir_hogar_de_paso.dart';
import 'pedir_motivo.dart';

// ─── Cambiar Estado Adopción Sheet ────────────────────────────────────────────

class CambiarEstadoSheet extends StatelessWidget {
  final String docId;
  final String estadoActual;
  final String nombre;
  final String? adoptanteIdEnProceso;

  /// Un albergue guarda al cuidador en su red de hogares de paso; un
  /// rescatista no tiene red. Ver pedirHogarDePaso().
  final bool esAlbergue;
  const CambiarEstadoSheet({
    super.key,
    required this.docId,
    required this.estadoActual,
    this.nombre = '',
    this.adoptanteIdEnProceso,
    this.esAlbergue = false,
  });

  /// ¿Hay alguien CON CUENTA cuidando a este animalito?
  ///
  /// Se pregunta en dos lugares con polaridad opuesta —para saber a quién
  /// avisar, y para saber si hace falta preguntar quién lo cuida— así que
  /// tiene nombre en vez de estar escrita dos veces. Un hogar de paso
  /// puesto a mano da `false`: esa persona existe, pero no en la app.
  bool get _hayCuidadorConCuenta => (adoptanteIdEnProceso ?? '').isNotEmpty;

  /// Suma al cuidador a la red de hogares de paso del albergue.
  ///
  /// Usa `sumarAyudaManual`, que busca por nombre + email: si esa persona
  /// ya estaba en la red le suma una ayuda en vez de crear una fila
  /// repetida. Por eso el email del diálogo se valida antes — uno mal
  /// escrito rompe esa búsqueda y la persona termina duplicada.
  ///
  /// Best-effort: si falla, el animalito igual quedó en hogar de paso con
  /// sus fechas, que es lo que importa. Perder la fila de la red es
  /// recuperable a mano; bloquear el cambio de estado por eso, no.
  Future<void> _sumarARed(DatosHogarDePaso datos) async {
    // La red es del albergue del panel (el de la responsable en modo equipo).
    final uid = uidDueno(esAlbergue: esAlbergue);
    if (uid.isEmpty) return;
    try {
      await HogaresDePasoRepository().sumarAyudaManual(
        albergueId: uid,
        nombre: datos.nombre,
        email: datos.contacto,
      );
    } catch (_) {}
  }

  /// Único punto de escritura del estado — pasa por
  /// [RescatesRepository.cambiarEstadoAdopcion] (ver ARCHITECTURE.md) y
  /// avisa si falla, en vez del `.update()` suelto y sin manejar de antes
  /// (si fallaba, el sheet ya se había cerrado como si hubiera funcionado,
  /// sin ningún aviso).
  Future<bool> _actualizarEstado(
    BuildContext context,
    String nuevoEstado, {
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      await RescatesRepository().cambiarEstadoAdopcion(
        docId,
        nuevoEstado,
        extra: extra,
      );
      return true;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.sp.msgError,
            content: Text('No se pudo actualizar el estado. Intentá de nuevo.'),
          ),
        );
      }
      return false;
    }
  }

  /// Avisa que el animal falleció — al adoptante EN PROCESO (solicitud ya
  /// aprobada) si hay uno, y a TODOS los que todavía tengan una solicitud
  /// PENDIENTE para este animal. Devuelve `false` si algún aviso no se
  /// pudo dejar (el cambio de estado en sí ya se guardó aparte y no se
  /// deshace por esto), para que quien lo llama pueda decirlo en pantalla
  /// en vez de que se pierda en silencio.
  ///
  /// **Antes solo avisaba al adoptante en proceso — hallazgo real de
  /// Eliza.** `adoptanteIdEnProceso` solo se completa cuando una solicitud
  /// se APRUEBA (ver `solicitudes_rescatista_screen.dart`); un animal
  /// marcado fallecido con solicitudes todavía pendientes (nunca
  /// aprobadas, el caso más común con un animal recién publicado) dejaba a
  /// esas personas sin ningún aviso — no porque algo fallara, sino porque
  /// nadie llegaba a estar registrado como destinatario.
  ///
  /// Todo el trabajo real (buscar el chat, crearlo si hace falta, escribir
  /// el mensaje) lo hace `ChatsRepository.avisarSobreAnimal` — única fuente
  /// para toda la app, ver su doc para el detalle completo de por qué
  /// también hacía falta poder CREAR el chat acá (antes esta función solo
  /// buscaba uno existente, y una solicitud recién mandada muchas veces
  /// todavía no tiene ningún chat abierto).
  Future<bool> _avisarAdoptanteFallecido(String nota) async {
    if (nombre.isEmpty) return true;
    final miUid = uidDueno(esAlbergue: esAlbergue);
    if (miUid.isEmpty) return true;

    // A quién avisar: el adoptante ya aprobado (si hay) + todos los que
    // todavía esperan respuesta. Un Map por adoptanteId, no una lista, para
    // no mandarle el aviso dos veces a la misma persona si por algún motivo
    // aparece en los dos grupos.
    final porAvisar = <String, String>{}; // adoptanteId -> su nombre
    if (_hayCuidadorConCuenta) {
      porAvisar[adoptanteIdEnProceso!] = 'Adoptante';
    }
    try {
      // Cierra las pendientes Y devuelve las que cerró, en UNA operación.
      //
      // UNA sola llamada, no dos. Esta función averigua a quién escribirle
      // a partir de las solicitudes pendientes: si se cerraran por un lado
      // y se consultaran por otro, cerrar primero dejaría esa consulta
      // vacía y nadie recibiría el aviso — el bug que Eliza ya reportó una
      // vez ("el usuario no se entera q falleció el animalito"). Con una
      // sola operación que hace las dos cosas, ese orden no se puede
      // equivocar, y como es una sola lista tampoco puede haber avisos
      // duplicados.
      //
      // Solo toca las `pendiente`: una solicitud ya aprobada o ya
      // rechazada queda como está.
      final pendientes = await SolicitudesRepository()
          .rechazarPendientesPorFallecimiento(
            rescateId: docId,
            rescatistaId: miUid,
          );
      for (final s in pendientes) {
        final id = s['adoptanteId'] as String? ?? '';
        if (id.isEmpty) continue;
        porAvisar.putIfAbsent(
          id,
          () => (s['nombre'] as String?)?.isNotEmpty == true
              ? s['nombre'] as String
              : 'Adoptante',
        );
      }
    } catch (_) {
      // Sin señal no se puede cerrar ni saber quién más está esperando — se
      // sigue igual con quien ya se tenía (el adoptante en proceso, si
      // hay), en vez de bloquear TODO el aviso por no poder completar la
      // lista. Las que no se hayan podido cerrar siguen protegidas por
      // aprobarSiDisponible, que rechaza con este mismo motivo si alguien
      // intenta aprobarlas.
    }
    if (porAvisar.isEmpty) return true;

    // `creadoPor` real del animal (rescatista/albergue) — sin esto, el
    // aviso de abajo caía al default 'rescatista' de
    // ChatsRepository.avisarSobreAnimal, aunque el animal fuera de un
    // albergue. Si la persona a avisar todavía no tenía chat abierto (el
    // caso más común: mandó la solicitud y nunca llegó a escribir), las
    // reglas de Firestore rechazaban la creación de ese chat nuevo porque
    // el `creadoPor` no coincidía con el del rescate — y el aviso de
    // fallecimiento se perdía en silencio. Mismo hallazgo, mismo motivo,
    // que el de solicitudes_rescatista_screen.dart:_aprobarSolicitudImpl.
    // Hallazgo real de Eliza: "el usuario no se entera q falleció el
    // animalito".
    //
    // De la MISMA lectura salen la foto y la especie del animalito. No es
    // un dato de más: el chat guarda su propia copia de los dos, y la
    // lista de conversaciones lee esa copia, nunca el animal. Sin ellos el
    // chat recién creado nacía sin foto (emoji en vez del animalito) y sin
    // especie, que cae al default 'Perro' y le pone 🐶 a un gato. El
    // relleno del cliente que tapaba el hueco busca por NOMBRE de animal,
    // así que con dos animalitos sin nombre le ponía a uno la foto del
    // otro. Verificado en producción el 2026-09-02: el chat de
    // BM0sxb68YL5KNo5b3mdj mostraba la foto de 2b6dVwmGLz5kj1k5uWM2.
    String? creadoPorReal;
    String? fotoUrlReal;
    String? especieReal;
    try {
      final rescateDoc = await RescatesRepository().obtener(docId);
      final datos = rescateDoc.data();
      creadoPorReal = datos?['creadoPor'] as String?;
      fotoUrlReal = datos?['fotoUrl'] as String?;
      especieReal = datos?['especie'] as String?;
    } catch (_) {}

    final texto =
        'Lamentamos informarte que $nombre falleció. '
        'Gracias por tu interés en darle un hogar. 🌈'
        '${nota.isNotEmpty ? '\n\n$nota' : ''}';
    // UsuariosRepository().nombrePropioParaAnimal() decide entre nombre y
    // albergueNombre mirando de qué animal es (creadoPorReal, ya resuelto
    // arriba) — antes acá vivía una copia a mano que ignoraba ese dato y
    // siempre prefería albergueNombre si existía, mismo bug (y mismo
    // arreglo) que enviarMensajeChat() en solicitudes_rescatista_screen.
    // dart, ver el doc de nombrePropioParaAnimal() para el hallazgo real.
    final miNombre = await UsuariosRepository().nombrePropioParaAnimal(
      uid: miUid,
      creadoPor: creadoPorReal,
    );

    var todoOk = true;
    for (final entry in porAvisar.entries) {
      final ok = await ChatsRepository().avisarSobreAnimal(
        adoptanteId: entry.key,
        adoptanteNombre: entry.value,
        rescatistaId: miUid,
        rescatista: miNombre,
        texto: texto,
        rescateId: docId,
        animalNombre: nombre,
        creadoPor: creadoPorReal,
        especie: especieReal,
        fotoUrl: fotoUrlReal,
      );
      if (!ok) todoOk = false;
    }
    return todoOk;
  }

  // El segundo dato era un emoji de color; ya no se muestra (cada estado se
  // pinta con su tono del tema, spToneEstado, y su ícono, spIconoEstado).
  static const _estados = [
    ('Rescatado', '', 'Disponible para adopción'),
    ('Hogar de paso', '', 'Temporalmente con un cuidador'),
    ('En proceso de adopción', '', 'Tiene una solicitud activa'),
    ('Adoptado', '', 'Ya encontró su hogar'),
    ('Regresado', '', 'Fue devuelto, disponible de nuevo'),
    ('Fallecido', '', 'Ya no está con nosotros'),
  ];

  /// Los estados que esta hoja ofrece de verdad.
  ///
  /// Lo único que se saca es 'Hogar de paso' mientras haya una adopción en
  /// curso: pasar directo desde ahí la dejaba a medias, con el
  /// `adoptanteIdEnProceso` del adoptante colgando de un hogar de paso que
  /// es de otra persona. La forma correcta de terminar esa adopción es
  /// RECHAZAR la solicitud, que devuelve el animalito a 'Rescatado'; desde
  /// ahí sí se puede. Pedido explícito de Eliza: no inventar una transición
  /// especial ni borrar el claim para que entre.
  ///
  /// **Solo ese estado.** Se evaluó reutilizar [sePuedeSerHogarDePaso], que
  /// responde que no para el mismo caso, y se descartó: esa es la pregunta
  /// del ADOPTANTE ("¿me puedo ofrecer yo?") y también dice que no para
  /// 'Adoptado', que del lado del dueño SÍ se podía elegir. Habría cambiado
  /// un comportamiento que nadie pidió. Ver el doc de [hayAdopcionEnCurso].
  ///
  /// El estado ACTUAL siempre se muestra: es el que aparece marcado, y
  /// esconderlo dejaría la hoja sin indicar en qué estado está el
  /// animalito.
  ///
  /// En modo equipo (fase 2) tampoco se ofrece 'Fallecido': cierra las
  /// solicitudes pendientes rechazándolas, y rechazar es solo de la
  /// responsable (las reglas no lo dejan). Lo marca ella.
  Iterable<(String, String, String)> get _estadosOfrecidos => _estados.where(
    (e) =>
        (e.$1 != 'Hogar de paso' ||
            e.$1 == estadoActual ||
            !hayAdopcionEnCurso(estadoActual)) &&
        (e.$1 != 'Fallecido' || e.$1 == estadoActual || !(esAlbergue && SesionEquipo.activa)),
  );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SpAgarradera(),
        const SizedBox(height: 14),
        const SpHojaTitulo(
          'Estado del animal',
          subtitulo: 'Toca para cambiar el estado',
        ),
        const SizedBox(height: 16),
        ..._estadosOfrecidos.map((e) {
          final sel = e.$1 == estadoActual;
          return GestureDetector(
            onTap: () async {
              // "Hogar de paso" puesto a mano: hay que preguntar quién y
              // hasta cuándo. Antes se escribía solo el estado, y eso
              // dejaba tres cosas rotas en silencio a la vez — el
              // recordatorio de vencimiento no se disparaba nunca, la
              // tarjeta no mostraba el período, y no había a quién
              // contactar. Ver pedirHogarDePaso() para el porqué de que
              // este camino exista y no se exija una solicitud.
              //
              // Si YA hay alguien con cuenta cuidándolo (vino de una
              // solicitud aprobada) no se pregunta nada: esos datos ya
              // están y volver a pedirlos los pisaría.
              // `estadoActual != 'Hogar de paso'`: este desplegable sirve
              // para CAMBIAR de estado, y elegir el estado en el que el
              // animalito ya está no es un cambio. Sin esa condición, un
              // hogar de paso cargado a mano volvía a mostrar el formulario
              // en blanco, y completarlo pisaba `hogarDePasoNombre` y las
              // dos fechas, reiniciaba los avisos de vencimiento y le sumaba
              // otra ayuda en la red al albergue. Peor todavía: el nombre se
              // pisa siempre pero el contacto solo si se escribe uno, así
              // que el animalito podía quedar con el nombre del cuidador
              // nuevo y el email del anterior. Hallazgo de Eliza: "1 animal
              // puede quedar en dos familias?".
              //
              // Uno que llegó por una solicitud aprobada ya no preguntaba,
              // porque tiene `adoptanteIdEnProceso`. Ahora los dos casos se
              // comportan igual, y igual para rescatista y albergue.
              //
              // Cambiar de cuidador no se resuelve acá: sería editar los
              // datos del hogar de paso, que es otra acción y no existe
              // todavía.
              if (e.$1 == 'Hogar de paso' &&
                  estadoActual != 'Hogar de paso' &&
                  !_hayCuidadorConCuenta) {
                final datos = await pedirHogarDePaso(
                  context,
                  pedirEmail: esAlbergue,
                );
                if (datos == null) return;
                if (!context.mounted) return;
                final ok = await _actualizarEstado(
                  context,
                  e.$1,
                  extra: {
                    'fechaInicioHogar': Timestamp.fromDate(datos.desde),
                    'fechaFinHogar': Timestamp.fromDate(datos.hasta),
                    'hogarDePasoNombre': datos.nombre,
                    if (datos.contacto.isNotEmpty)
                      'hogarDePasoContacto': datos.contacto,
                    // Mismo par que usa el camino de aprobar una
                    // solicitud, para que los dos no puedan divergir.
                    ...RescatesRepository.avisosHogarDePasoDesdeCero,
                  },
                );
                if (ok && esAlbergue) {
                  // Se suma sola a la red, con registrarAyuda: si esa
                  // persona ya estaba (mismo email) le suma una ayuda en
                  // vez de duplicarla.
                  await _sumarARed(datos);
                }
                if (ok && context.mounted) Navigator.pop(context);
                return;
              }
              if (e.$1 != 'Regresado' && e.$1 != 'Fallecido') {
                final ok = await _actualizarEstado(
                  context,
                  e.$1,
                  extra: {
                    if (e.$1 == 'Adoptado')
                      'fechaAdopcion': FieldValue.serverTimestamp(),
                  },
                );
                if (ok && context.mounted) Navigator.pop(context);
                return;
              }
              final esFallecido = e.$1 == 'Fallecido';
              final sheetCtx = context;
              // El diálogo es dueño de su propio TextEditingController (ver
              // _MotivoDialog) y devuelve el texto ya escrito. Antes el
              // controller se creaba acá y se liberaba con
              // `.then((_) => ctrl.dispose())` sobre el showDialog — y ese
              // Future se completa apenas se llama Navigator.pop, NO cuando
              // el diálogo termina de cerrarse. O sea que el controller se
              // destruía mientras el TextField todavía estaba en pantalla
              // animándose hacia afuera; al desmontarse, ese TextField
              // intentaba soltar su listener sobre un controller ya
              // destruido y Flutter lanzaba "A TextEditingController was
              // used after being disposed", pintando su pantalla roja de
              // error por lo que durara la animación de cierre. Hallazgo
              // real de Eliza cambiando un animal a 'Regresado': "salió un
              // mensaje rojo feo con letras amarillas así súper rápido y
              // luego cambió el estado".
              //
              // Con el controller adentro de un State, Flutter lo libera
              // exactamente cuando corresponde (al desmontarse el widget que
              // lo usa), sin que nadie tenga que adivinar el momento.
              final motivo = await pedirMotivo(
                context,
                titulo: esFallecido
                    ? 'Lo sentimos mucho 🌈'
                    : '¿Por qué fue regresado?',
                hint: esFallecido
                    ? 'Puedes dejar una nota sobre este angelito...'
                    : 'Ej: Incompatibilidad con otros animales, mudanza...',
                etiquetaConfirmar: 'Guardar',
                colorConfirmar: esFallecido
                    ? context.sp.inkMuted
                    : context.sp.danger,
                confirmarRelleno: true,
                autofocus: true,
              );
              // null = cerró con Cancelar (o tocando afuera): no se cambia
              // nada. Un texto vacío SÍ es una respuesta válida — el motivo
              // nunca fue obligatorio.
              if (motivo == null) return;
              final ok = await _actualizarEstado(
                sheetCtx,
                e.$1,
                extra: {
                  if (esFallecido && motivo.isNotEmpty)
                    'notaFallecido': motivo
                  else if (!esFallecido)
                    'motivoRegreso': motivo,
                },
              );
              // await, no fire-and-forget: antes esta llamada salía sin
              // await y sin catch, así que si el aviso fallaba (sin señal, o
              // el chat no existía) la excepción quedaba suelta y nadie se
              // enteraba de que el adoptante nunca recibió la noticia.
              // Hallazgo de auditoría de código.
              var avisoOk = true;
              if (esFallecido && ok) {
                avisoOk = await _avisarAdoptanteFallecido(motivo);
              }
              if (!avisoOk && sheetCtx.mounted) {
                ScaffoldMessenger.of(sheetCtx).showSnackBar(
                  SnackBar(
                    backgroundColor: context.sp.msgAdvertencia,
                    content: Text(
                      'El estado se guardó, pero no pudimos avisarle '
                      'al adoptante. Escribile por el chat.',
                    ),
                  ),
                );
              }
              if (ok && sheetCtx.mounted) Navigator.pop(sheetCtx);
            },
            // El toque lo maneja el GestureDetector de afuera.
            child: SpOpcionHoja(
              titulo: e.$1,
              detalle: e.$3,
              icono: spIconoEstado(e.$1),
              tono: spToneEstado(e.$1),
              elegida: sel,
            ),
          );
        }),
      ],
    ),
  );
}
