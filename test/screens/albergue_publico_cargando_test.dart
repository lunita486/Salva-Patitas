import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/data/creator_role.dart';
import 'package:salva_patitas/data/rescates_repository.dart';
import 'package:salva_patitas/domain/reglas_negocio.dart';

/// El perfil público del albergue no puede decir "0" mientras no sabe.
///
/// **El problema.** Los dos contadores mostraban `0` antes de que llegara la
/// consulta, y el grid decía "No hay animales disponibles por ahora". Los
/// tres son afirmaciones falsas: el dato todavía no había llegado. Eliza:
/// "el 0 inicial es especialmente molesto porque no significa que haya 0
/// animales: significa que todavía no terminó de cargar el dato".
///
/// Se comprueba leyendo el código porque montar esta pantalla necesita
/// Firebase, y lo que hay que custodiar es que nadie vuelva a poner un
/// `?? 0` en un contador que puede estar cargando.
void main() {
  final fuente = File(
    'lib/screens/albergue_publico_screen.dart',
  ).readAsStringSync();

  test('los contadores distinguen "cargando" de "cero"', () {
    expect(
      fuente,
      contains('final cargando = !rSnap.hasData;'),
      reason: 'sin esta distinción no se puede saber si el 0 es real',
    );
  });

  test('el contador de disponibles no cae a 0 mientras carga', () {
    expect(fuente, contains("s.hasData ? '\${s.data}' : _cargandoValor"));
  });

  // El defecto que Eliza comprobó con un albergue de 55: el numero salia de
  // contar los documentos de UNA pagina, que pide 30.
  test('el contador de disponibles NO sale del tamaño de la página', () {
    expect(
      fuente,
      isNot(contains("'\${disponibles.length}'")),
      reason:
          'volvió a contar la página: con más de 30 disponibles muestra 30',
    );
    expect(
      fuente,
      contains('_totalDisponibles'),
      reason: 'tiene que salir de un conteo total, como adoptados',
    );
  });

  test('la lista de abajo sigue paginada, no se trajo entera', () {
    expect(
      fuente,
      contains('porPagina: 30'),
      reason: 'el arreglo del contador no debe tocar la paginación',
    );
  });

  test('el de adoptados tampoco', () {
    expect(fuente, contains("s.hasData ? '\${s.data}' : _cargandoValor"));
    expect(
      fuente,
      isNot(contains("'\${s.data ?? 0}'")),
      reason: 'volvió el ?? 0: muestra un cero que no es un dato',
    );
  });

  test('mientras carga no se afirma que no hay animales', () {
    // El "No hay animales" tiene que estar detrás del else de `cargando`,
    // no colgado solo de que la lista esté vacía.
    final iCargando = fuente.indexOf('if (cargando)');
    final iVacio = fuente.indexOf('else if (disponibles.isEmpty)');
    expect(iCargando, isNot(-1), reason: 'no hay estado de carga en el grid');
    expect(
      iVacio,
      greaterThan(iCargando),
      reason: 'el mensaje de vacío no está protegido por el estado de carga',
    );
  });

  test('el marcador de carga no es un número', () {
    final m = RegExp(r"static const _cargandoValor = '(.*)';").firstMatch(fuente);
    expect(m, isNotNull, reason: 'no existe el marcador de carga');
    expect(
      int.tryParse(m!.group(1)!),
      isNull,
      reason: 'el marcador se lee como un dato real si es un número',
    );
  });

  // ── El número real, contra el repositorio ──────────────────────────────
  //
  // Los de arriba miran el código; este mide el comportamiento: con 55
  // disponibles tiene que decir 55, no 30.
  group('un albergue con más de una página de disponibles', () {
    late FakeFirebaseFirestore db;
    late RescatesRepository repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = RescatesRepository(db: db);
    });

    Future<void> sembrar(int cuantos, String estado) async {
      for (var i = 0; i < cuantos; i++) {
        await db.collection('rescates').add({
          'nombre': 'Animal $estado $i',
          'especie': 'Perro',
          'estadoAdopcion': estado,
          'rescatistaId': 'refugio',
          'creadoPor': 'albergue',
          'creadoEn': Timestamp.fromDate(
            DateTime(2026, 1, 1).add(Duration(seconds: i)),
          ),
        });
      }
    }

    test('55 disponibles se cuentan como 55, no como 30', () async {
      await sembrar(55, 'Rescatado');
      final total = await repo.contar(
        uid: 'refugio',
        role: CreatorRole.albergue,
        estados: estadosDisponibles,
      );
      expect(total, 55, reason: 'el contador se quedó en el tamaño de página');

      // Y la página que alimenta la lista sigue trayendo 30, que es lo
      // correcto: son dos cosas distintas y el arreglo no las mezcla.
      final pagina = await repo.paginaDeMisRescates(
        uid: 'refugio',
        role: CreatorRole.albergue,
        estados: estadosDisponibles,
        porPagina: 30,
      );
      expect(pagina.docs.length, 30);
      expect(pagina.hayMas, isTrue);
    });

    test('cuenta los tres estados disponibles, igual que la lista', () async {
      await sembrar(20, 'Rescatado');
      await sembrar(15, 'Regresado');
      await sembrar(12, 'Hogar de paso');
      await sembrar(40, 'Adoptado');
      final total = await repo.contar(
        uid: 'refugio',
        role: CreatorRole.albergue,
        estados: estadosDisponibles,
      );
      expect(total, 47, reason: 'el número y la lista tienen que coincidir');
    });

    test('si de verdad no hay ninguno, el número es 0', () async {
      await sembrar(5, 'Adoptado');
      expect(
        await repo.contar(
          uid: 'refugio',
          role: CreatorRole.albergue,
          estados: estadosDisponibles,
        ),
        0,
      );
    });
  });
}