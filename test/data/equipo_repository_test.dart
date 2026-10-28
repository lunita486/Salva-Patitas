import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/equipo_repository.dart';

void main() {
  final ahora = DateTime.utc(2026, 10, 23, 12);
  DateTime reloj() => ahora;
  Timestamp en(Duration d) => Timestamp.fromDate(ahora.add(d));

  late FakeFirebaseFirestore db;
  late List<(String, Map<String, dynamic>)> llamadas;
  Object? respuesta;
  Object? error;
  late EquipoRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    llamadas = [];
    respuesta = null;
    error = null;
    repo = EquipoRepository(
      db: db,
      llamar: (nombre, datos) async {
        llamadas.add((nombre, datos));
        if (error != null) throw error!;
        return respuesta;
      },
    );
  });

  group('lecturas (mismos filtros que firestore.rules)', () {
    test('miMembresia: null si nunca fue de un equipo; después, la suya', () async {
      expect(await repo.miMembresia('ana').first, isNull);
      await db.collection('membresias').doc('ana').set({
        'albergueId': 'perla', 'estado': 'activa', 'nombre': 'Ana', 'email': 'ana@mail.com',
        'desde': Timestamp.fromDate(ahora),
      });
      final m = await repo.miMembresia('ana').first;
      expect(m!.activa, isTrue);
      expect(m.albergueId, 'perla');
      expect(m.desde!.isAtSameMomentAs(ahora), isTrue);
    });

    test('una membresía revocada o sin albergue no cuenta como activa', () {
      expect(Membresia.desde('a', {'albergueId': 'p', 'estado': 'revocada'}).activa, isFalse);
      expect(Membresia.desde('a', {'estado': 'activa'}).activa, isFalse);
      expect(Membresia.desde('a', {'email': 'a@mail.com'}).nombreVisible, 'a@mail.com');
    });

    test('miembrosDe: solo las activas de ese albergue, ordenadas por nombre', () async {
      final col = db.collection('membresias');
      await col.doc('b').set({'albergueId': 'perla', 'estado': 'activa', 'nombre': 'Bea'});
      await col.doc('a').set({'albergueId': 'perla', 'estado': 'activa', 'nombre': 'ana'});
      await col.doc('c').set({'albergueId': 'perla', 'estado': 'revocada', 'nombre': 'Caro'});
      await col.doc('d').set({'albergueId': 'otro', 'estado': 'activa', 'nombre': 'Dani'});
      final lista = await repo.miembrosDe('perla').first;
      expect(lista.map((m) => m.uid), ['a', 'b']);
    });

    test('invitacionesDe: pendientes y vigentes de ese albergue', () async {
      final col = db.collection('invitaciones');
      await col.doc('i1').set({'albergueId': 'perla', 'estado': 'pendiente', 'emailDestino': 'a@mail.com', 'expiraEn': en(const Duration(days: 3))});
      await col.doc('i2').set({'albergueId': 'perla', 'estado': 'pendiente', 'emailDestino': 'b@mail.com', 'expiraEn': en(const Duration(days: -1))});
      await col.doc('i3').set({'albergueId': 'perla', 'estado': 'cancelada', 'emailDestino': 'c@mail.com', 'expiraEn': en(const Duration(days: 3))});
      await col.doc('i4').set({'albergueId': 'otro', 'estado': 'pendiente', 'emailDestino': 'd@mail.com', 'expiraEn': en(const Duration(days: 3))});
      final lista = await repo.invitacionesDe('perla', ahora: reloj).first;
      expect(lista.map((i) => i.id), ['i1']);
    });

    test('invitacionesPara: el correo se compara en minúsculas; vencidas y ajenas no', () async {
      final col = db.collection('invitaciones');
      await col.doc('i1').set({'albergueId': 'perla', 'albergueNombre': 'La Perla', 'estado': 'pendiente', 'emailDestino': 'ana@mail.com', 'expiraEn': en(const Duration(days: 6))});
      await col.doc('i2').set({'albergueId': 'otro', 'estado': 'pendiente', 'emailDestino': 'ana@mail.com', 'expiraEn': en(const Duration(hours: -2))});
      await col.doc('i3').set({'albergueId': 'perla', 'estado': 'pendiente', 'emailDestino': 'bea@mail.com', 'expiraEn': en(const Duration(days: 6))});
      final lista = await repo.invitacionesPara('  Ana@Mail.com ', ahora: reloj).first;
      expect(lista.single.id, 'i1');
      expect(lista.single.albergueNombre, 'La Perla');
      expect(await repo.invitacionesPara('', ahora: reloj).first, isEmpty);
    });

    test('vence: hoy, 1 día, varios días; sin fecha no es vigente', () {
      InvitacionEquipo inv(Duration d) => InvitacionEquipo(
        id: 'x', albergueId: 'p', emailDestino: 'a', estado: 'pendiente', expiraEn: ahora.add(d));
      expect(inv(const Duration(hours: 5)).venceEnTexto(ahora), 'Vence hoy');
      expect(inv(const Duration(hours: 30)).venceEnTexto(ahora), 'Vence en 1 día');
      expect(inv(const Duration(days: 6, hours: 1)).venceEnTexto(ahora), 'Vence en 6 días');
      expect(inv(const Duration(days: 6, hours: 23)).venceEnTexto(ahora), 'Vence en 7 días',
          reason: 'recién creada no puede decir 6 si dura 7');
      expect(inv(const Duration(days: 6, hours: 23)).plazoParaResponder(ahora), 'Tenés 7 días para responder');
      expect(inv(const Duration(hours: 30)).plazoParaResponder(ahora), 'Tenés 1 día para responder');
      expect(inv(const Duration(hours: 5)).plazoParaResponder(ahora), 'Respondé hoy: después vence');
      expect(const InvitacionEquipo(id: 'x', albergueId: 'p', emailDestino: 'a', estado: 'pendiente').vigente(ahora), isFalse);
    });
  });

  group('acciones: cada una llama a su Function con solo lo necesario', () {
    test('nombres y datos exactos', () async {
      respuesta = {'albergueId': 'perla'};
      await repo.invitar('  Ana@Mail.com ');
      expect(await repo.aceptar('inv1'), 'perla');
      await repo.rechazar('inv2');
      await repo.cancelar('inv3');
      await repo.revocar('uid_m');
      await repo.salir();
      expect(llamadas.map((l) => l.$1).toList(), [
        'invitarMiembro', 'aceptarInvitacion', 'rechazarInvitacion', 'cancelarInvitacion',
        'revocarMiembro', 'salirDelEquipo',
      ]);
      expect(llamadas.map((l) => l.$2).toList(), [
        {'email': 'ana@mail.com'},
        {'invitacionId': 'inv1'},
        {'invitacionId': 'inv2'},
        {'invitacionId': 'inv3'},
        {'miembroUid': 'uid_m'},
        <String, dynamic>{},
      ]);
    });

    test('las acciones no escriben nada en Firestore desde la app', () async {
      await repo.invitar('a@mail.com');
      await repo.revocar('x');
      for (final col in ['membresias', 'invitaciones', 'equipos', 'hogaresDePaso']) {
        expect((await db.collection(col).get()).docs, isEmpty, reason: col);
      }
    });
  });

  group('errores', () {
    Future<EquipoError> errorDe(Object e) async {
      error = e;
      try {
        await repo.invitar('a@mail.com');
      } on EquipoError catch (x) {
        return x;
      }
      fail('se esperaba un EquipoError');
    }

    test('mensaje de negocio del servidor: se muestra tal cual', () async {
      final e = await errorDe(FirebaseFunctionsException(
        code: 'already-exists', message: 'Ya hay una invitación pendiente para ese correo.'));
      expect(e.mensaje, 'Ya hay una invitación pendiente para ese correo.');
    });

    test('errores técnicos: texto genérico, sin detalles del servidor', () async {
      final interno = await errorDe(FirebaseFunctionsException(code: 'internal', message: 'stack trace secreto'));
      expect(interno.mensaje, isNot(contains('secreto')));
      final sinRed = await errorDe(FirebaseFunctionsException(code: 'unavailable', message: 'x'));
      expect(sinRed.mensaje, contains('conexión'));
      final lento = await errorDe(TimeoutException('t'));
      expect(lento.mensaje, contains('tardando'));
      expect(EquipoError.mensajeDe(StateError('x')), contains('Probá de nuevo'));
    });
  });
}
