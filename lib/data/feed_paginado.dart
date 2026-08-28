import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'rescates_repository.dart';

/// Las páginas del feed de adopción, cada una en vivo, juntadas en una sola
/// lista.
///
/// **Por qué existe.** El feed paginaba agrandando el `limit`: 50, después
/// 100, después 150. Cada página volvía a traer todo lo anterior, así que la
/// página 10 eran 500 documentos otra vez. Eso da por supuesto que la
/// colección es chica.
///
/// Ahora cada página es su propia consulta con cursor
/// (`startAfterDocument`) y cuesta 50 documentos, sin importar cuán adentro
/// del feed esté la persona.
///
/// **Por qué streams y no lecturas de una vez.** Porque el feed se actualiza
/// solo, y eso es una decisión de producto que ya estaba: un animalito que
/// se adopta cambia de estado en la tarjeta sin recargar la pantalla, en vez
/// de desaparecer de golpe. Con `.get()` por página eso se perdía. Es la
/// diferencia con `RescatesRepository.paginaDeMisRescates`, que sí es de una
/// sola lectura: por eso las dos NO comparten implementación. Forzarlas a
/// una sola abstracción sería juntar dos cosas que se parecen en la forma y
/// no en lo que hacen.
///
/// **Esto no decide qué animalitos se ven.** El orden es el de la consulta
/// (`creadoEn` ascendente) y los filtros siguen viviendo en la pantalla, tal
/// como estaban. Acá solo se juntan páginas.
class FeedPaginado {
  FeedPaginado({RescatesRepository? repo, this.porPagina = RescatesRepository.feedPageSize})
    : _repo = repo ?? RescatesRepository();

  final RescatesRepository _repo;
  final int porPagina;

  /// Lo que trajo cada página, en orden. Se reemplaza entero cada vez que
  /// esa página emite: es una foto en vivo de esa ventana.
  final _paginas = <List<QueryDocumentSnapshot<Map<String, dynamic>>>>[];

  /// Un listener por página abierta.
  final _subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

  final _salida =
      StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.broadcast();

  /// Los animalitos de todas las páginas abiertas, en orden y sin repetidos.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> get animales =>
      _salida.stream;

  /// Lo último que se emitió, o `null` si todavía no llegó nada.
  ///
  /// Va como `initialData` del StreamBuilder de la pantalla. **No es un
  /// lujo:** los streams de Firestore le entregan el estado actual a cada
  /// nuevo suscriptor, y esta pantalla se reconstruye seguido (hace
  /// `setState` cada vez que se pasa una tarjeta). Sin esto, un
  /// StreamBuilder que se vuelve a suscribir mostraría el spinner de carga
  /// —o "no quedan animalitos"— hasta que algo cambiara en la base.
  ///
  /// Se expone como valor y no metiéndolo dentro del stream a propósito: un
  /// `async*` que primero emite lo guardado y después se engancha al
  /// controlador deja una ventana en el medio donde se pierden eventos.
  /// Lo encontró un test de esta misma tanda.
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? get ultimo => _ultimo;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _ultimo;

  /// Cuántas páginas hay escuchando ahora mismo. Existe para que los tests
  /// puedan comprobar que no quedan listeners de más ni huérfanos.
  int get paginasAbiertas => _subs.length;

  /// `true` mientras la última página haya venido llena: una página con
  /// menos de [porPagina] es la señal de que no queda nada más.
  ///
  /// Antes esta pregunta se contestaba en la pantalla comparando el total
  /// acumulado contra el `limit` pedido. Con páginas independientes, la que
  /// manda es la última.
  bool get puedeHaberMas =>
      _paginas.isEmpty || _paginas.last.length >= porPagina;

  bool _pidiendo = false;

  /// Abre la página siguiente. No hace nada si ya no queda nada por traer, o
  /// si hay una página abriéndose: sin esa guarda, la pantalla puede pedir
  /// dos veces la misma antes de que llegue el primer snapshot.
  void pedirOtraPagina() {
    if (_pidiendo || !puedeHaberMas) return;
    _pidiendo = true;
    final indice = _paginas.length;
    // El cursor es el ÚLTIMO documento de la página anterior, y se captura
    // UNA sola vez, acá. `startAfterDocument` usa los valores que el
    // documento tenía en este momento, así que el cursor sigue sirviendo
    // aunque después ese animalito se borre. Recalcularlo en cada emisión
    // movería la ventana de esta página sola cada vez que cambia algo más
    // arriba. La primera página no lleva cursor.
    final anterior = _paginas.isEmpty ? null : _paginas.last;
    final cursor = (anterior == null || anterior.isEmpty)
        ? null
        : anterior.last;
    _paginas.add(const []);
    _subs.add(
      _repo
          .feedPublico(limite: porPagina, despuesDe: cursor)
          .listen(
            (snap) {
              // La página puede haber sido descartada por un reiniciar()
              // mientras su primer snapshot venía en camino.
              if (indice >= _paginas.length) return;
              _paginas[indice] = snap.docs;
              _pidiendo = false;
              _emitir();
            },
            onError: (Object e) {
              _pidiendo = false;
              if (!_salida.isClosed) _salida.addError(e);
            },
          ),
    );
  }

  /// Vuelve a empezar desde la primera página, cerrando todo lo anterior.
  void reiniciar() {
    _cerrarSubs();
    _paginas.clear();
    _ultimo = null;
    _pidiendo = false;
    pedirOtraPagina();
  }

  void dispose() {
    _cerrarSubs();
    _paginas.clear();
    _ultimo = null;
    _salida.close();
  }

  void _cerrarSubs() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _emitir() {
    if (_salida.isClosed) return;
    // Sin repetidos, y gana la página más temprana.
    //
    // Hace falta de verdad: la consulta de cada página es "los 50 que siguen
    // a este cursor". Si se BORRA un animalito de una página, esa consulta
    // se vuelve a evaluar sola y suma uno más del final para completar sus
    // 50 — y ese que suma es justo el primero de la página siguiente. Sin
    // deduplicar, la misma tarjeta aparecería dos veces.
    final vistos = <String>{};
    final todos = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final pagina in _paginas) {
      for (final doc in pagina) {
        if (vistos.add(doc.id)) todos.add(doc);
      }
    }
    _ultimo = todos;
    _salida.add(todos);
  }
}
