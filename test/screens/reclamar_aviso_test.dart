import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salva_patitas/screens/solicitudes_rescatista_screen.dart';

void main() {
  group(
    'reclamarAviso() — candado atómico para los 4 avisos automáticos '
    '(vencimiento de hogar de paso, seguimiento post-adopción). Hallazgo '
    'real de Eliza: el seguimiento de "Toby Papito" le llegó dos veces, '
    'idéntico, con el mismo minuto — el chequeo de antes ("leer el flag, '
    'si no está mandar el mensaje") no era atómico.',
    () {
      late FakeFirebaseFirestore firestore;

      setUp(() {
        firestore = FakeFirebaseFirestore();
      });

      test(
        'sin el flag todavía: reclama y lo deja en true',
        () async {
          final ref = await firestore.collection('rescates').add({
            'nombre': 'Toby',
          });
          final reclamado = await reclamarAviso(ref, 'seguimiento7Avisado');
          expect(reclamado, true);
          final doc = await ref.get();
          expect(doc['seguimiento7Avisado'], true);
        },
      );

      test(
        'el flag ya estaba en true: no reclama (otra llamada ya lo mandó)',
        () async {
          final ref = await firestore.collection('rescates').add({
            'nombre': 'Toby',
            'seguimiento7Avisado': true,
          });
          final reclamado = await reclamarAviso(ref, 'seguimiento7Avisado');
          expect(reclamado, false);
        },
      );

      // El caso real que reportó Eliza (dos llamadas casi simultáneas,
      // dos aperturas de la app o dos dispositivos con la misma cuenta,
      // verificando el MISMO animal) NO tiene una prueba acá que dispare
      // dos reclamarAviso() en paralelo con Future.wait: se probó, y
      // FakeFirebaseFirestore deja pasar a las dos — el fake no modela la
      // contención real entre transacciones concurrentes (dos llamadas
      // "a la vez" en el fake simplemente no chocan entre sí, lo que sea
      // que hagan cooperativamente en el mismo hilo de Dart no alcanza
      // para reproducir la carrera real contra el servidor). Un test así
      // pasaría siempre, incluso si reclamarAviso() no hiciera nada —
      // probaría que el fake no choca, no que el candado funciona. La
      // garantía real de fondo es la que documenta el propio SDK de
      // Firestore: dos transacciones que tocan el mismo documento se
      // serializan de verdad contra el servidor. Lo que SÍ se prueba acá
      // (arriba y abajo) es el contrato de la función en sí: reclama si
      // el flag no estaba, no reclama si ya estaba — la mitad que si
      // faltara, dejaría a reclamarAviso() inútil aunque el motor de
      // transacciones de Firestore hiciera bien su parte.

      test(
        'dos documentos DISTINTOS no se bloquean entre sí — cada rescate '
        'tiene su propio flag, no es un candado global',
        () async {
          final ref1 = await firestore.collection('rescates').add({
            'nombre': 'Toby',
          });
          final ref2 = await firestore.collection('rescates').add({
            'nombre': 'Luna',
          });
          final resultados = await Future.wait([
            reclamarAviso(ref1, 'seguimiento7Avisado'),
            reclamarAviso(ref2, 'seguimiento7Avisado'),
          ]);
          expect(
            resultados.every((r) => r),
            true,
            reason: 'las dos deberían poder reclamar, animales distintos',
          );
        },
      );

      test(
        'dos FLAGS distintos en el mismo documento no se pisan entre sí — '
        'avisoPrevioAvisado y vencimientoAvisado, por ejemplo, son '
        'independientes',
        () async {
          final ref = await firestore.collection('rescates').add({
            'nombre': 'Toby',
          });
          expect(await reclamarAviso(ref, 'avisoPrevioAvisado'), true);
          expect(await reclamarAviso(ref, 'vencimientoAvisado'), true);
          final doc = await ref.get();
          expect(doc['avisoPrevioAvisado'], true);
          expect(doc['vencimientoAvisado'], true);
        },
      );
    },
  );

  group(
    'revertirReclamoSiFallo() — contraparte de reclamarAviso() cuando el '
    'envío del mensaje falla de verdad. Sin esto se reintroduciría el bug '
    'de "Sarita": un tropiezo de red marcaría el aviso como mandado sin '
    'haberlo mandado.',
    () {
      test('deja el flag en false, como si nunca se hubiera reclamado', () async {
        final firestore = FakeFirebaseFirestore();
        final ref = await firestore.collection('rescates').add({
          'nombre': 'Sarita',
        });
        expect(await reclamarAviso(ref, 'vencimientoAvisado'), true);

        await revertirReclamoSiFallo(ref, 'vencimientoAvisado');

        final doc = await ref.get();
        expect(doc['vencimientoAvisado'], false);
        // Y con el flag repuesto, un reintento posterior puede reclamar
        // de nuevo — no queda trabado en false para siempre.
        expect(await reclamarAviso(ref, 'vencimientoAvisado'), true);
      });
    },
  );
}
