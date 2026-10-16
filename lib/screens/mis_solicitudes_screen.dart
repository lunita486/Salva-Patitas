import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../theme/salva_patitas_theme.dart';
import '../widgets/adoptante_tab_bar.dart';
import '../widgets/sp_widgets.dart';
import '../widgets/solicitud_piezas.dart';
import '../domain/reglas_negocio.dart';
import '../routing/app_router.dart';
import '../widgets/estado_error_feed.dart';
import '../widgets/fotos.dart';
import '../data/chats_repository.dart';
import '../data/rescates_repository.dart';
import '../data/solicitudes_repository.dart';

class MisSolicitudesScreen extends StatefulWidget {
  const MisSolicitudesScreen({super.key});
  @override
  State<MisSolicitudesScreen> createState() => _MisSolicitudesScreenState();
}

class _MisSolicitudesScreenState extends State<MisSolicitudesScreen> {
  // `late final`, no una consulta armada dentro de build() — que es como
  // estaba, y es el mismo patrón que causó el parpadeo y los datos viejos
  // en el resto de las pantallas de esta sesión (mis_rescates, la vista
  // previa de solicitudes, el carrusel del panel, la insignia del chat).
  // Cada redibujado creaba una consulta NUEVA, el StreamBuilder se
  // desuscribía de la anterior y se resuscribía, y esa resuscripción puede
  // mostrar un instante de caché local vieja antes de que llegue el dato
  // fresco del servidor. El uid no cambia mientras esta pantalla está
  // abierta, así que se resuelve una sola vez.
  late final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _misSolicitudesStream =
      SolicitudesRepository().misSolicitudes(_uid);

  // "Registro del acuerdo de adopción", versión simple: sin firma dibujada
  // ni PDF — un texto genérico de compromiso que el adoptante lee y acepta,
  // guardado con la fecha del servidor dentro de la misma solicitud. Solo
  // para adopción definitiva (no hogar de paso, que ya tiene su propio
  // acuerdo de fechas de inicio/fin).
  Future<void> _mostrarAcuerdo(
    BuildContext context,
    String solicitudId,
    String animal,
  ) async {
    final aceptar = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Compromiso de adopción'),
        content: SingleChildScrollView(
          child: Text(
            'Al confirmar, te comprometés a:\n\n'
            '• No revenderlo, regalarlo ni cederlo a otra persona sin avisarle a quien te lo entregó.\n\n'
            '• Si en algún momento no podés seguir teniéndolo, devolverlo a quien te lo dio en adopción, nunca abandonarlo.\n\n'
            '• Darle buen trato, alimentación y atención veterinaria.\n\n'
            'Este es un compromiso de buena fe entre vos y quien te lo entregó, para que ${nombreDeAnimal(animal, enFrase: true)} tenga un hogar responsable.',
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cerrar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: Text(
              'Acepto estos compromisos',
              style: TextStyle(
                color: context.sp.primaryStrong,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (aceptar != true) return;
    try {
      await SolicitudesRepository().aceptarAcuerdo(solicitudId);
    } catch (_) {
      // Sin esto, si la escritura fallaba (sin señal, token vencido) la
      // persona no se enteraba: el botón "Ver compromiso de adopción"
      // seguía ahí como si nunca hubiera tocado "Acepto", sin ningún
      // aviso de que hay que reintentar (hallazgo de auditoría de código).
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.sp.msgError,
            content: Text(
              'No se pudo registrar tu aceptación. Revisá tu conexión e intentá de nuevo.',
            ),
          ),
        );
      }
    }
  }

  // Sugerencia real de una tester (Edith): adoptó por la app y no
  // encontraba forma de volver a ver las fotos/ficha del animal desde
  // "Mis solicitudes" — solo se veía la miniatura chiquita de la lista.
  // Funciona igual sin importar el estado (pendiente/aprobada/rechazada):
  // se busca el rescate por su id y se abre la misma ficha completa que
  // usa el resto de la app, no una versión reducida.
  Future<void> _verFicha(BuildContext context, String? rescateId) async {
    if (rescateId == null || rescateId.isEmpty) return;
    final doc = await RescatesRepository().obtener(rescateId);
    if (!context.mounted) return;
    if (!doc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.sp.msgError,
          content: Text(
            'Este animalito ya no está disponible en la plataforma.',
          ),
        ),
      );
      return;
    }
    final d = doc.data()!;
    final nombre = nombreDeAnimal(d['nombre'] as String?);
    final animalMap = {
      'nombre': nombre,
      'especie': d['especie'] ?? 'Perro',
      'edad': d['edad'] ?? '',
      'raza': d['raza'] ?? 'Criolla',
      'tamano': d['tamano'] ?? 'Mediano',
      'ubicacion': d['ubicacion'] ?? '',
      'descripcion': d['descripcion'] ?? '',
      'tags': <String>[
        if (d['okConNinos'] == true) 'Amigable con niños',
        if (d['okConMascotas'] == true) 'Es sociable',
        if ((d['energia'] as String?)?.isNotEmpty == true)
          d['energia'] as String,
      ],
      'rescatista': d['rescatistaNombre'] ?? '',
      'rescatistaId': d['rescatistaId'] ?? '',
      'rescateId': doc.id,
      'estadoAdopcion': d['estadoAdopcion'] ?? 'Rescatado',
      'fotoUrl': d['fotoUrl'],
      'fotoUrl2': d['fotoUrl2'],
      'latitud': d['latitud'],
      'longitud': d['longitud'],
      'energia': d['energia'],
      'okConNinos': d['okConNinos'],
      'okConMascotas': d['okConMascotas'],
      'requiereExperiencia': d['requiereExperiencia'],
      'vacunado': d['vacunado'],
      'desparasitado': d['desparasitado'],
      'urgencia': d['urgencia'] ?? '',
      'creadoPor': d['creadoPor'] ?? 'rescatista',
    };
    if (!context.mounted) return;
    context.push(AppRoutes.animalDetalle, extra: animalMap);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sp;
    return Scaffold(
      // Misma barra que el inicio del adoptante (ver AdoptanteTabBar).
      bottomNavigationBar: AdoptanteTabBar(
        actual: AdoptanteTab.solicitudes,
        onTap: AdoptanteTabBar.volverAlInicio(
          context,
          AdoptanteTab.solicitudes,
        ),
      ),
      backgroundColor: c.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: SpPawBackground()),
          SafeArea(
            child: Column(
              children: [
                const SpScreenHeader(
                  title: 'Mis solicitudes',
                  subtitle: 'Las que enviaste y su respuesta',
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    // SolicitudesRepository.misSolicitudes (no una consulta armada
                    // a mano acá) — regla del proyecto: `solicitudes` siempre pasa
                    // por lib/data/, ver ARCHITECTURE.md.
                    stream: _misSolicitudesStream,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(color: c.primary),
                        );
                      }
                      // Sin esto, un error real se veía igual que "todavía no
                      // enviaste solicitudes" — mismo patrón ya arreglado en
                      // favoritos_screen.dart y otras pantallas (errorFeedState,
                      // widgets/estado_error_feed.dart), acá (hallazgo de auditoría de código).
                      if (snap.hasError) return errorFeedState();
                      final docs = [...(snap.data?.docs ?? [])]
                        ..sort((a, b) {
                          final ta =
                              (a.data() as Map)['creadoEn'] as Timestamp?;
                          final tb =
                              (b.data() as Map)['creadoEn'] as Timestamp?;
                          if (ta == null || tb == null) return 0;
                          return tb.compareTo(ta);
                        });
                      if (docs.isEmpty) {
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: const [
                            SpEmpty(
                              title: 'Aún no has enviado solicitudes',
                              subtitle:
                                  'Cuando solicites adoptar un animal, aparecerá aquí con su estado.',
                              animal: SpAnimalKind.perro,
                            ),
                          ],
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        itemCount: docs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (_, i) {
                          final d = docs[i].data() as Map<String, dynamic>;
                          // Antes esta lista decía 'Animal' y el encabezado
                          // de la misma pantalla decía 'Sin nombre'.
                          final animal = nombreDeAnimal(
                            d['animalNombre'] as String?,
                          );
                          final estado = d['estado'] as String? ?? 'pendiente';
                          final motivo = d['motivoRechazo'] as String?;
                          final ts = d['creadoEn'] as Timestamp?;
                          final fecha = ts != null
                              ? formatearFecha(ts.toDate())
                              : '';
                          final fotoUrl = d['fotoUrl'] as String?;
                          final tipo =
                              d['tipoSolicitud'] as String? ?? 'adopcion';
                          final fechaFinTs = d['fechaFinHogar'] as Timestamp?;
                          final fechaInicioTs =
                              d['fechaInicioHogar'] as Timestamp?;
                          final fechaFin = fechaFinTs?.toDate();
                          final fechaInicio = fechaInicioTs?.toDate();
                          final hoy = DateTime.now();
                          // diasHastaVencimiento (domain/reglas_negocio.dart) —
                          // única fuente. El panel del rescatista contestaba
                          // esta MISMA pregunta con hora incluida, así que el
                          // día del vencimiento acá decía "vence hoy" y allá ya
                          // había mandado "ha vencido".
                          final diasRestantes = fechaFin != null
                              ? diasHastaVencimiento(
                                  fechaFin: fechaFin,
                                  ahora: hoy,
                                )
                              : null;

                          return Container(
                            key: ValueKey(docs[i].id),
                            padding: const EdgeInsets.all(14),
                            decoration: SpDeco.card(c),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () => _verFicha(
                                    context,
                                    d['rescateId'] as String?,
                                  ),
                                  // FotoAnimal en vez de recorte — mismo arreglo
                                  // que mis_rescates_screen.dart.
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: SizedBox(
                                      width: 64,
                                      height: 64,
                                      child: fotoUrl != null
                                          ? FotoAnimal(
                                              url: fotoUrl,
                                              width: 64,
                                              height: 64,
                                              // Miniatura de lista: sin fondo borroso, ver FotoAnimal.
                                              fondoBorroso: false,
                                              fallback: SpFotoVacia(
                                                especie:
                                                    d['especie'] as String?,
                                                size: 48,
                                              ),
                                            )
                                          : SpFotoVacia(
                                              especie: d['especie'] as String?,
                                              size: 48,
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        animal,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: c.ink,
                                        ),
                                      ),
                                      // El nombre del rescatista/albergue dueño
                                      // del animal nunca se guardó en el
                                      // documento de la solicitud (nadie lo
                                      // escribió al crearla, y el trigger del
                                      // servidor que sincroniza animalNombre/
                                      // fotoUrl tampoco lo cubre — no es un
                                      // campo de ESTA colección). Se lee en
                                      // vivo del animal en vez de agregar otra
                                      // copia más: justo el tipo de dato
                                      // denormalizado que se pasó buena parte
                                      // de esta sesión reparando. Hallazgo
                                      // real de Eliza: "en Solicitudes tampoco
                                      // se ve el nombre del albergue" —ni
                                      // antes ni después de renombrarlo,
                                      // porque nunca se mostraba nada ahí.
                                      if ((d['rescateId'] as String?)
                                              ?.isNotEmpty ==
                                          true)
                                        FutureBuilder<DocumentSnapshot>(
                                          future: RescatesRepository().obtener(
                                            d['rescateId'] as String,
                                          ),
                                          builder: (context, animalSnap) {
                                            final rd =
                                                animalSnap.data?.data()
                                                    as Map<String, dynamic>?;
                                            final rescatista =
                                                rd?['rescatistaNombre']
                                                    as String?;
                                            if (rescatista == null ||
                                                rescatista.isEmpty) {
                                              return const SizedBox.shrink();
                                            }
                                            return Text(
                                              rescatista,
                                              style: SpText.caption.copyWith(
                                                color: c.primaryStrong,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            );
                                          },
                                        ),

                                      if (fecha.isNotEmpty) ...[
                                        const SizedBox(height: 1),
                                        Text(
                                          'Enviada el $fecha',
                                          style: SpText.caption.copyWith(
                                            color: c.inkMuted,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          SolicitudTipoPill(
                                            esHogar: tipo == 'hogar_de_paso',
                                          ),
                                          SolicitudEstadoPill(estado: estado),
                                        ],
                                      ),
                                      if (estado == 'aprobada' &&
                                          tipo == 'adopcion') ...[
                                        const SizedBox(height: 10),
                                        (d['acuerdoAceptado'] == true)
                                            ? Builder(
                                                builder: (_) {
                                                  final ts =
                                                      d['acuerdoAceptadoEn']
                                                          as Timestamp?;
                                                  return Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .check_circle_rounded,
                                                        size: 15,
                                                        color: c.primaryStrong,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Expanded(
                                                        child: Text(
                                                          ts != null
                                                              ? 'Compromiso de adopción aceptado el ${formatearFecha(ts.toDate())}'
                                                              : 'Compromiso de adopción aceptado',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color:
                                                                c.primaryStrong,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              )
                                            : SizedBox(
                                                width: double.infinity,
                                                child: SpButton(
                                                  label:
                                                      'Ver compromiso de adopción',
                                                  icon:
                                                      Icons.assignment_outlined,
                                                  suave: true,
                                                  compacto: true,
                                                  onTap: () => _mostrarAcuerdo(
                                                    context,
                                                    docs[i].id,
                                                    animal,
                                                  ),
                                                ),
                                              ),
                                      ],
                                      if (estado == 'aprobada' &&
                                          tipo == 'hogar_de_paso' &&
                                          fechaFin != null) ...[
                                        const SizedBox(height: 10),
                                        SpNotice(
                                          fondo: c.butter,
                                          tinta: c.butterInk,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (fechaInicio != null)
                                                Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.event_outlined,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      '${formatearFecha(fechaInicio)} → ${formatearFecha(fechaFin)}',
                                                    ),
                                                  ],
                                                ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(
                                                    diasRestantes! <= 0
                                                        ? Icons
                                                              .warning_amber_rounded
                                                        : Icons
                                                              .schedule_rounded,
                                                    color: diasRestantes < 3
                                                        ? c.accentInk
                                                        : null,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    diasRestantes < 0
                                                        ? 'Período vencido hace ${diasRestantes.abs()} días'
                                                        : diasRestantes == 0
                                                        ? 'El período vence hoy'
                                                        : '$diasRestantes días restantes',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: diasRestantes < 3
                                                          ? c.accentInk
                                                          : null,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      if (estado == 'aprobada') ...[
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: SpButton(
                                            label: 'Ir al chat',
                                            icon: Icons
                                                .chat_bubble_outline_rounded,
                                            onTap: () async {
                                              final uid =
                                                  FirebaseAuth
                                                      .instance
                                                      .currentUser
                                                      ?.uid ??
                                                  '';
                                              final rescateIdChat =
                                                  d['rescateId'] as String? ??
                                                  '';
                                              // buscarDeAnimal ya elige solo entre el id
                                              // determinístico y el match por nombre (dato
                                              // legado), y traduce el permission-denied de
                                              // un chat inexistente a null — sin eso la
                                              // excepción mataba el onTap y el botón del
                                              // chat no hacía nada. Con chatId null,
                                              // ChatScreen crea el chat al abrirse.
                                              final chatId =
                                                  (await ChatsRepository()
                                                          .buscarDeAnimal(
                                                            rescateId:
                                                                rescateIdChat,
                                                            adoptanteId: uid,
                                                            animalNombre:
                                                                animal,
                                                          ))
                                                      ?.id;
                                              // `creadoPor`/rescatista de acá arriba
                                              // vienen de la SOLICITUD, congelados al
                                              // momento de mandarla — mismo problema
                                              // (y mismo arreglo) que
                                              // _aprobarSolicitudImpl/
                                              // _rechazarSolicitudImpl en
                                              // solicitudes_rescatista_screen.dart.
                                              // Sin esto, abrir el chat desde acá
                                              // podía volver a pisar con el valor
                                              // viejo un chat que ya tenía el dato
                                              // correcto: ChatScreen hace merge al
                                              // abrirse, así que este botón no solo
                                              // mostraba mal la etiqueta, la
                                              // corrompía de nuevo para todo el
                                              // mundo. Hallazgo real de Eliza: un
                                              // animal de albergue mostraba
                                              // "Rescatista" en el chat, reportado
                                              // hace meses y seguía pasando.
                                              var creadoPorVivo =
                                                  d['creadoPor'] as String?;
                                              var rescatistaVivo =
                                                  d['rescatistaNombre']
                                                      as String? ??
                                                  d['rescatista'] as String?;
                                              if (rescateIdChat.isNotEmpty) {
                                                try {
                                                  final rescateDoc =
                                                      await RescatesRepository()
                                                          .obtener(
                                                            rescateIdChat,
                                                          );
                                                  final rd = rescateDoc.data();
                                                  final creadoPorReal =
                                                      rd?['creadoPor']
                                                          as String?;
                                                  if (creadoPorReal != null &&
                                                      creadoPorReal
                                                          .isNotEmpty) {
                                                    creadoPorVivo =
                                                        creadoPorReal;
                                                  }
                                                  final rescatistaReal =
                                                      rd?['rescatistaNombre']
                                                          as String?;
                                                  if (rescatistaReal != null &&
                                                      rescatistaReal
                                                          .isNotEmpty) {
                                                    rescatistaVivo =
                                                        rescatistaReal;
                                                  }
                                                } catch (_) {}
                                              }
                                              if (!context.mounted) return;
                                              final animalMap = {
                                                'nombre': animal,
                                                'rescatista':
                                                    rescatistaVivo ??
                                                    'Rescatista',
                                                'rescatistaId':
                                                    d['rescatistaId']
                                                        as String? ??
                                                    '',
                                                'rescateId': rescateIdChat,
                                                // El ancla para las reglas cuando
                                                // el animal no trae rescateId
                                                // (solicitud vieja): la solicitud
                                                // misma prueba que estas dos
                                                // personas tienen relación. Ver
                                                // firestore.rules, chats.create.
                                                'solicitudId': docs[i].id,
                                                'especie':
                                                    d['especie'] as String? ??
                                                    'Perro',
                                                'fotoUrl': fotoUrl,
                                                'tipoSolicitud': tipo,
                                                'creadoPor': creadoPorVivo,
                                                'edad': '',
                                                'ubicacion': '',
                                                'descripcion': '',
                                                'tags': <String>[],
                                              };
                                              context.push(
                                                AppRoutes.chat,
                                                extra: (
                                                  animal: animalMap,
                                                  chatId: chatId,
                                                  esRescatista: false,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                      if (estado == 'rechazada') ...[
                                        const SizedBox(height: 10),
                                        Text(
                                          'Respuesta',
                                          style: SpText.caption.copyWith(
                                            color: c.inkMuted,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        // Burbuja con el mensaje que mandó quien
                                        // rechazó (`.bubble--them`).
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: c.surfaceSunken,
                                            borderRadius:
                                                const BorderRadius.only(
                                                  topLeft: Radius.circular(18),
                                                  topRight: Radius.circular(18),
                                                  bottomRight: Radius.circular(
                                                    18,
                                                  ),
                                                  bottomLeft: Radius.circular(
                                                    6,
                                                  ),
                                                ),
                                          ),
                                          child: Text(
                                            motivo != null && motivo.isNotEmpty
                                                ? motivo
                                                : mensajeRechazoBase(
                                                    nombreDeAnimal(
                                                      animal,
                                                      enFrase: true,
                                                    ),
                                                  ),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: c.ink,
                                              height: 1.45,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
