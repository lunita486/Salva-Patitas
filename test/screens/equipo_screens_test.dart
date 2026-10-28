import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/equipo_repository.dart';
import 'package:salva_patitas/screens/equipo_albergue_screen.dart';
import 'package:salva_patitas/screens/mi_equipo_screen.dart';
import 'package:salva_patitas/theme/salva_patitas_theme.dart';
import 'package:salva_patitas/widgets/fila_mi_equipo.dart';

/// Pantallas del equipo del albergue, montadas de verdad contra
/// fake_cloud_firestore y con las Cloud Functions reemplazadas por un
/// registro de llamadas. Lo que importa: qué se muestra con cada estado y
/// que cada botón llame a la Function correcta con solo lo necesario.
void main() {
  late FakeFirebaseFirestore db;
  late List<(String, Map<String, dynamic>)> llamadas;
  Object? errorAlLlamar;
  late EquipoRepository repo;
  final venceLuego = Timestamp.fromDate(DateTime.now().add(const Duration(days: 5)));

  setUp(() {
    db = FakeFirebaseFirestore();
    llamadas = [];
    errorAlLlamar = null;
    repo = EquipoRepository(
      db: db,
      llamar: (nombre, datos) async {
        llamadas.add((nombre, datos));
        if (errorAlLlamar != null) throw errorAlLlamar!;
        return {'albergueId': 'perla'};
      },
    );
  });

  Widget app(Widget w) => MaterialApp(theme: SpTheme.light(), home: w);

  Future<void> miembro(String uid, String nombre, {String albergue = 'perla', String estado = 'activa'}) =>
      db.collection('membresias').doc(uid).set({
        'albergueId': albergue, 'estado': estado, 'nombre': nombre, 'email': '$uid@mail.com',
        'desde': Timestamp.fromDate(DateTime(2026, 10, 1)),
      });

  Future<void> invitacion(String id, String email, {String albergue = 'perla', String nombre = 'La Perla'}) =>
      db.collection('invitaciones').doc(id).set({
        'albergueId': albergue, 'albergueNombre': nombre, 'emailDestino': email,
        'estado': 'pendiente', 'expiraEn': venceLuego,
      });

  Future<void> confirmar(WidgetTester tester, String boton) async {
    await tester.tap(find.widgetWithText(TextButton, boton));
    await tester.pumpAndSettle();
  }

  group('Equipo del albergue (responsable)', () {
    testWidgets('muestra miembros activos e invitaciones pendientes', (tester) async {
      await miembro('m1', 'Bea');
      await miembro('m2', 'Revocada', estado: 'revocada');
      await miembro('m3', 'De otro', albergue: 'otro');
      await invitacion('i1', 'caro@mail.com');
      await tester.pumpWidget(app(EquipoAlbergueScreen(repo: repo, uid: 'perla')));
      await tester.pumpAndSettle();
      expect(find.text('Bea'), findsOneWidget);
      expect(find.text('Revocada'), findsNothing);
      expect(find.text('De otro'), findsNothing);
      expect(find.text('caro@mail.com'), findsOneWidget);
      expect(find.text('Invitaciones pendientes (1)'), findsOneWidget);
      expect(find.textContaining('lugares'), findsNothing, reason: 'sin tope, no hay cupo que mostrar');
      expect(find.text('Qué puede hacer tu equipo'), findsOneWidget);
      expect(find.textContaining('aprobar o rechazar solicitudes', findRichText: true), findsOneWidget);
      expect(find.text('Miembros (1)'), findsOneWidget);
    });

    testWidgets('quitar pide confirmación y llama a revocarMiembro con ese uid', (tester) async {
      await miembro('m1', 'Bea');
      await tester.pumpWidget(app(EquipoAlbergueScreen(repo: repo, uid: 'perla')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Quitar del equipo'));
      await tester.pumpAndSettle();
      await confirmar(tester, 'Cancelar');
      expect(llamadas, isEmpty, reason: 'cancelar el diálogo no hace nada');
      await tester.tap(find.byTooltip('Quitar del equipo'));
      await tester.pumpAndSettle();
      await confirmar(tester, 'Quitar');
      expect(llamadas.single.$1, 'revocarMiembro');
      expect(llamadas.single.$2, {'miembroUid': 'm1'});
    });

    testWidgets('cancelar una invitación llama a cancelarInvitacion', (tester) async {
      await invitacion('i1', 'caro@mail.com');
      await tester.pumpWidget(app(EquipoAlbergueScreen(repo: repo, uid: 'perla')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Cancelar invitación'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancelar invitación'));
      await tester.pumpAndSettle();
      await confirmar(tester, 'Cancelar invitación');
      expect(llamadas.single.$1, 'cancelarInvitacion');
      expect(llamadas.single.$2, {'invitacionId': 'i1'});
    });

    testWidgets('invitar: sin un correo válido no se puede; con uno, llama a invitarMiembro', (tester) async {
      await tester.pumpWidget(app(EquipoAlbergueScreen(repo: repo, uid: 'perla')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invitar a alguien'));
      await tester.pumpAndSettle();
      expect(find.text('Usá el correo con el que esa persona entra a Salva Patitas.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ana@mail');
      await tester.pump();
      await tester.tap(find.text('Enviar invitación'));
      await tester.pump();
      expect(llamadas, isEmpty);
      await tester.enterText(find.byType(TextField), '  Ana@Mail.com ');
      await tester.pump();
      await tester.tap(find.text('Enviar invitación'));
      await tester.pumpAndSettle();
      expect(llamadas.single.$1, 'invitarMiembro');
      expect(llamadas.single.$2, {'email': 'ana@mail.com'});
      expect(find.textContaining('Invitación enviada a ana@mail.com'), findsOneWidget);
    });

    testWidgets('un error del servidor se muestra en la hoja, sin el viejo atajo a revisar hogares', (tester) async {
      errorAlLlamar = FirebaseFunctionsException(
        code: 'already-exists',
        message: 'Ya hay una invitación pendiente para ese correo.',
      );
      await tester.pumpWidget(app(EquipoAlbergueScreen(repo: repo, uid: 'perla')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invitar a alguien'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ana@mail.com');
      await tester.pump();
      await tester.tap(find.text('Enviar invitación'));
      await tester.pumpAndSettle();
      expect(find.text('Ya hay una invitación pendiente para ese correo.'), findsOneWidget);
      expect(find.text('Revisar mis hogares de paso'), findsNothing);
    });

    testWidgets('sin tope: con 12 miembros y 3 invitaciones se puede seguir invitando', (tester) async {
      for (var i = 0; i < 12; i++) {
        await miembro('m${i.toString().padLeft(2, '0')}', 'Persona $i');
      }
      for (var i = 0; i < 3; i++) {
        await invitacion('i$i', 'p$i@mail.com');
      }
      await tester.pumpWidget(app(EquipoAlbergueScreen(repo: repo, uid: 'perla')));
      await tester.pumpAndSettle();
      expect(find.text('Miembros (12)'), findsOneWidget);
      expect(find.text('Equipo completo'), findsNothing);
      await tester.tap(find.text('Invitar a alguien'));
      await tester.pumpAndSettle();
      expect(find.text('Invitar al equipo'), findsOneWidget);
    });
  });

  group('Mi equipo de albergue (persona invitada o miembro)', () {
    testWidgets('sin invitaciones ni equipo: estado vacío', (tester) async {
      await tester.pumpWidget(app(MiEquipoScreen(repo: repo, uid: 'ana', email: 'ana@mail.com')));
      await tester.pumpAndSettle();
      expect(find.text('No tenés invitaciones'), findsOneWidget);
    });

    testWidgets('aceptar una invitación pide confirmación y llama a aceptarInvitacion', (tester) async {
      await invitacion('i1', 'ana@mail.com');
      await invitacion('i2', 'otra@mail.com');
      await tester.pumpWidget(app(MiEquipoScreen(repo: repo, uid: 'ana', email: 'Ana@Mail.com')));
      await tester.pumpAndSettle();
      expect(find.text('La Perla te invitó a su equipo'), findsOneWidget);
      expect(find.text('Tenés 5 días para responder'), findsOneWidget);
      expect(find.text('Invitaciones (1)'), findsOneWidget, reason: 'la de otro correo no aparece');
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(find.text('¿Sumarte al equipo de La Perla?'), findsOneWidget);
      expect(find.textContaining('los animales que publicás por tu cuenta', findRichText: true), findsOneWidget);
      expect(find.text('•  Cargar y editar animalitos'), findsOneWidget);
      expect(find.text('Aprobar adopciones sigue siendo de la responsable.'), findsOneWidget);
      await confirmar(tester, 'Sí, sumarme');
      expect(llamadas.single.$1, 'aceptarInvitacion');
      expect(llamadas.single.$2, {'invitacionId': 'i1'});
    });

    testWidgets('rechazar llama a rechazarInvitacion', (tester) async {
      await invitacion('i1', 'ana@mail.com');
      await tester.pumpWidget(app(MiEquipoScreen(repo: repo, uid: 'ana', email: 'ana@mail.com')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rechazar'));
      await tester.pumpAndSettle();
      await confirmar(tester, 'Rechazar');
      expect(llamadas.single.$1, 'rechazarInvitacion');
      expect(llamadas.single.$2, {'invitacionId': 'i1'});
    });

    testWidgets('miembro: ve su albergue y desde cuándo, sin accesos de solo lectura, y puede salir', (tester) async {
      await db.collection('usuarios').doc('perla').set({'albergueNombre': 'La Perla', 'roles': ['albergue']});
      await miembro('ana', 'Ana');
      await tester.pumpWidget(app(MiEquipoScreen(repo: repo, uid: 'ana', email: 'ana@mail.com')));
      await tester.pumpAndSettle();
      expect(find.text('La Perla'), findsOneWidget);
      expect(find.textContaining('Sos parte del equipo desde el'), findsOneWidget);
      expect(find.text('Chats del albergue'), findsNothing);
      expect(find.text('Hogares de paso compartidos'), findsNothing);
      await tester.ensureVisible(find.text('Salir del equipo'));
      await tester.tap(find.text('Salir del equipo'));
      await tester.pumpAndSettle();
      await confirmar(tester, 'Salir');
      expect(llamadas.single.$1, 'salirDelEquipo');
      expect(llamadas.single.$2, isEmpty);
    });

    testWidgets('miembro con otra invitación: no puede aceptarla sin salir antes', (tester) async {
      await miembro('ana', 'Ana');
      await invitacion('i9', 'ana@mail.com', albergue: 'otro', nombre: 'Huellitas');
      await tester.pumpWidget(app(MiEquipoScreen(repo: repo, uid: 'ana', email: 'ana@mail.com')));
      await tester.pumpAndSettle();
      expect(find.textContaining('primero salí de tu equipo actual'), findsOneWidget);
      await tester.ensureVisible(find.text('Aceptar'));
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(llamadas, isEmpty);
    });

    testWidgets('una membresía revocada no muestra el albergue', (tester) async {
      await miembro('ana', 'Ana', estado: 'revocada');
      await tester.pumpWidget(app(MiEquipoScreen(repo: repo, uid: 'ana', email: 'ana@mail.com')));
      await tester.pumpAndSettle();
      expect(find.text('Salir del equipo'), findsNothing);
      expect(find.text('No tenés invitaciones'), findsOneWidget);
    });
  });

  group('Fila "Mi equipo de albergue" del perfil', () {
    Widget fila() => app(Scaffold(body: Column(children: [FilaMiEquipo(repo: repo, uid: 'ana', email: 'ana@mail.com')])));

    testWidgets('sin equipo ni invitaciones no aparece', (tester) async {
      await tester.pumpWidget(fila());
      await tester.pumpAndSettle();
      expect(find.text('Mi equipo de albergue'), findsNothing);
    });

    testWidgets('con una invitación aparece y dice cuántas', (tester) async {
      await invitacion('i1', 'ana@mail.com');
      await tester.pumpWidget(fila());
      await tester.pumpAndSettle();
      expect(find.text('Mi equipo de albergue'), findsOneWidget);
      expect(find.text('1 invitación pendiente'), findsOneWidget);
    });

    testWidgets('siendo miembro aparece', (tester) async {
      await miembro('ana', 'Ana');
      await tester.pumpWidget(fila());
      await tester.pumpAndSettle();
      expect(find.text('Sos parte de un equipo'), findsOneWidget);
    });
  });
}
