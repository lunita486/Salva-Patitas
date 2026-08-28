import 'dart:async';

/// Corre [cuantas] tareas dejando como mucho [limite] en curso a la vez, y
/// arrancando la siguiente apenas se libera un lugar.
///
/// **Por qué existe.** Subir un lote publicaba en tandas fijas: agarraba 3
/// animales, esperaba a que terminaran LOS TRES, y recién ahí agarraba los 3
/// siguientes. El límite de 3 está para no quedarse sin memoria (un lote de
/// 20 disparando 20 isolates y 40 subidas a la vez ya crasheó una vez), pero
/// esperar a la tanda completa suma un costo que no hace falta pagar: si un
/// animal trae una foto pesada, los otros dos lugares quedan VACÍOS hasta
/// que ese termine.
///
/// Con fotos de tamaños distintos —que es lo normal— esos huecos se acumulan
/// y el lote entero tarda bastante más. Eliza subiendo varios animalitos:
/// "se demoró bastante, 1... 2... 3...". Ese conteo de a 3 era literalmente
/// esto.
///
/// Acá el límite es el mismo, pero no hay huecos: apenas uno termina, entra
/// el siguiente. El techo de memoria no cambia; lo que cambia es que los 3
/// lugares están siempre ocupados mientras quede trabajo.
///
/// [tarea] recibe el índice. Si una lanza, se propaga y las demás terminan
/// lo que ya empezaron — igual que con `Future.wait`. Quien llama decide si
/// atrapa adentro (el lote lo hace: un animal que falla no debe tirar abajo
/// a los otros 19).
Future<void> correrConLimite({
  required int cuantas,
  required int limite,
  required Future<void> Function(int indice) tarea,
}) async {
  if (cuantas <= 0) return;
  final enParalelo = limite < 1 ? 1 : limite;
  var siguiente = 0;

  // Cada "trabajador" agarra el próximo índice libre y sigue hasta que no
  // quede ninguno. El `siguiente++` es seguro sin candado porque Dart no
  // interrumpe código sincrónico: entre leer y escribir no puede colarse
  // otro trabajador.
  Future<void> trabajador() async {
    while (true) {
      final indice = siguiente;
      if (indice >= cuantas) return;
      siguiente = indice + 1;
      await tarea(indice);
    }
  }

  await Future.wait([
    for (var i = 0; i < enParalelo && i < cuantas; i++) trabajador(),
  ]);
}
