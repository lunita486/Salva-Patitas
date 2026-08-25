const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const {
  CAMPOS_ANIMAL_A_CHAT,
  CAMPOS_ANIMAL_A_SOLICITUD,
  CAMPOS_PERFIL_A_ANIMAL,
  CAMPOS_PERFIL_A_ANIMAL_RESCATISTA,
  CAMPOS_PERFIL_A_CHAT,
  CAMPOS_A_BORRAR_EN_CHAT_DE_ANIMAL,
  CAMPOS_PERFIL_ALIADO_A_CHAT,
  cambiosAPropagar,
  valoresDeseados,
  desactualizado,
  enTandas,
  esChatDeAnimal,
  CAMPOS_PERFIL_A_SOLICITUD,
  CAMPOS_PERFIL_A_CHAT_ADOPTANTE,
} = require('../propagar_copias_logica');

describe('cambiosAPropagar — qué copias hay que refrescar', () => {
  test('cambió el nombre del animal: se propaga con el nombre que tiene en el destino (animalNombre)', () => {
    assert.deepEqual(
      cambiosAPropagar({
        antes: { nombre: 'loquito', fotoUrl: 'https://a.jpg' },
        despues: { nombre: 'Pacolini', fotoUrl: 'https://a.jpg' },
        campos: CAMPOS_ANIMAL_A_CHAT,
      }),
      { animalNombre: 'Pacolini' },
    );
  });

  test('cambió la foto: se propaga solo la foto, el nombre no se toca', () => {
    assert.deepEqual(
      cambiosAPropagar({
        antes: { nombre: 'loquito', fotoUrl: 'https://vieja.jpg' },
        despues: { nombre: 'loquito', fotoUrl: 'https://nueva.jpg' },
        campos: CAMPOS_ANIMAL_A_CHAT,
      }),
      { fotoUrl: 'https://nueva.jpg' },
    );
  });

  test('cambiaron los dos: se propagan los dos', () => {
    assert.deepEqual(
      cambiosAPropagar({
        antes: { nombre: 'loquito', fotoUrl: 'https://vieja.jpg' },
        despues: { nombre: 'Pacolini', fotoUrl: 'https://nueva.jpg' },
        campos: CAMPOS_ANIMAL_A_CHAT,
      }),
      { animalNombre: 'Pacolini', fotoUrl: 'https://nueva.jpg' },
    );
  });

  // El caso más común de todos: marcar adoptado, tocar la descripción, la
  // urgencia... Devolver null acá es lo que evita reescribir cientos de
  // documentos en cada guardado.
  test('no cambió ninguno de los campos que se copian: null, no se toca nada', () => {
    assert.equal(
      cambiosAPropagar({
        antes: { nombre: 'loquito', fotoUrl: 'https://a.jpg', estadoAdopcion: 'Rescatado' },
        despues: { nombre: 'loquito', fotoUrl: 'https://a.jpg', estadoAdopcion: 'Adoptado' },
        campos: CAMPOS_ANIMAL_A_CHAT,
      }),
      null,
    );
  });

  // Firestore rechaza un update con `undefined`. Y "el animal ya no tiene
  // foto" no es algo que las copias necesiten saber.
  test('un campo que se borra se ignora, no se escribe undefined', () => {
    assert.equal(
      cambiosAPropagar({
        antes: { nombre: 'loquito', fotoUrl: 'https://a.jpg' },
        despues: { nombre: 'loquito' },
        campos: CAMPOS_ANIMAL_A_CHAT,
      }),
      null,
    );
  });

  test('documento recién creado sin "antes": propaga lo que tenga', () => {
    assert.deepEqual(
      cambiosAPropagar({
        antes: undefined,
        despues: { nombre: 'Pacolini' },
        campos: CAMPOS_ANIMAL_A_CHAT,
      }),
      { animalNombre: 'Pacolini' },
    );
  });

  test('perfil del albergue: la ciudad viaja al campo "ubicacion" de cada animal', () => {
    assert.deepEqual(
      cambiosAPropagar({
        antes: { ciudad: 'Montería', paisCodigo: 'CO', latitud: 8.75 },
        despues: {
          ciudad: 'Santiago de los Caballeros',
          paisCodigo: 'DO',
          latitud: 19.45,
        },
        campos: CAMPOS_PERFIL_A_ANIMAL,
      }),
      {
        ubicacion: 'Santiago de los Caballeros',
        paisCodigo: 'DO',
        latitud: 19.45,
      },
    );
  });

  test(
    'perfil del albergue: el nombre viaja a los chats de animal con OTRO '
    + 'nombre de campo — el logo NO viaja (ver el comentario largo en '
    + 'CAMPOS_PERFIL_A_CHAT, hallazgo real de Eliza: "dos circulitos donde '
    + 'debería mostrar la foto del animalito y la foto del albergue")',
    () => {
      assert.deepEqual(
        cambiosAPropagar({
          antes: { albergueNombre: 'Nombre viejo', fotoBase64: 'logoViejo' },
          despues: { albergueNombre: 'Casa hogar tu amigo fiel', fotoBase64: 'logoNuevo' },
          campos: CAMPOS_PERFIL_A_CHAT,
        }),
        { rescatista: 'Casa hogar tu amigo fiel' },
      );
    },
  );

  test('perfil del albergue: cambiar SOLO la foto no propaga nada a los chats de animal (el logo no es un campo que copien)', () => {
    assert.equal(
      cambiosAPropagar({
        antes: { albergueNombre: 'Casa hogar tu amigo fiel', fotoBase64: 'logoViejo' },
        despues: { albergueNombre: 'Casa hogar tu amigo fiel', fotoBase64: 'logoNuevo' },
        campos: CAMPOS_PERFIL_A_CHAT,
      }),
      null,
    );
  });

  // Guardar el perfil tocando solo el teléfono no debe reescribir ni los
  // animales ni los chats.
  test('perfil: cambiar un campo que nadie copia (teléfono) no propaga nada', () => {
    assert.equal(
      cambiosAPropagar({
        antes: { ciudad: 'Medellin', albergueTelefono: '111' },
        despues: { ciudad: 'Medellin', albergueTelefono: '222' },
        campos: CAMPOS_PERFIL_A_ANIMAL,
      }),
      null,
    );
  });
});

describe('enTandas — el tope de 500 operaciones por WriteBatch', () => {
  test('menos de 500 queda en una sola tanda', () => {
    const tandas = enTandas(new Array(3).fill('x'));
    assert.equal(tandas.length, 1);
    assert.equal(tandas[0].length, 3);
  });

  test('exactamente 500 sigue siendo una sola tanda', () => {
    const tandas = enTandas(new Array(500).fill('x'));
    assert.equal(tandas.length, 1);
  });

  // Sin partir, commit() tiraría y NINGUNA copia se actualizaría, ni
  // siquiera las primeras 500 — mismo bug que ya se arregló una vez en
  // onRescateEliminado con los favoritos.
  test('501 se parte en dos, sin perder el último', () => {
    const tandas = enTandas(new Array(501).fill('x'));
    assert.equal(tandas.length, 2);
    assert.equal(tandas[0].length, 500);
    assert.equal(tandas[1].length, 1);
  });

  test('lista vacía: ninguna tanda, no se abre un batch al pedo', () => {
    assert.deepEqual(enTandas([]), []);
  });
});

describe(
  'esChatDeAnimal — creadoPor está sobrecargado entre las dos formas de '
  + 'chat. Hallazgo real de Eliza: abrió el chat con "VetPet la 30" (un '
  + 'negocio) y vio el nombre/foto del ALBERGUE en su lugar.',
  () => {
    test('un chat de animal normal (adopción) es de animal', () => {
      assert.equal(
        esChatDeAnimal({ tipoSolicitud: 'adopcion', creadoPor: 'albergue' }),
        true,
      );
    });

    test('un chat de hogar de paso es de animal', () => {
      assert.equal(
        esChatDeAnimal({ tipoSolicitud: 'hogar_de_paso', creadoPor: 'albergue' }),
        true,
      );
    });

    test('un chat legado sin tipoSolicitud (dato viejo) se trata como de animal', () => {
      assert.equal(esChatDeAnimal({ creadoPor: 'albergue' }), true);
    });

    // El caso real: una cuenta que es albergue Y aliado a la vez (o
    // cualquier chat de consulta donde ella es la aliada consultada)
    // también tiene creadoPor=='albergue' en su chat de consulta_aliado
    // — pero ESE chat NO es sobre un animal, y no debe tocarse con los
    // campos de "chats de albergue" (fotoBase64/rescatista con la
    // identidad de ALBERGUE en vez de la de ALIADO).
    test('una consulta a un aliado, aunque tenga creadoPor=="albergue", NO es de animal', () => {
      assert.equal(
        esChatDeAnimal({
          tipoSolicitud: 'consulta_aliado',
          creadoPor: 'albergue',
        }),
        false,
      );
    });

    test('una consulta a un aliado contactada como rescatista tampoco es de animal', () => {
      assert.equal(
        esChatDeAnimal({
          tipoSolicitud: 'consulta_aliado',
          creadoPor: 'rescatista',
        }),
        false,
      );
    });
  },
);

describe(
  'valoresDeseados + desactualizado — el par que REPARA copias corruptas, '
  + 'no solo mantiene al día las sanas. Hallazgo real de Eliza: le cambió '
  + 'la FOTO a su negocio aliado y la foto del chat se reparó sola, pero '
  + 'el NOMBRE siguió mostrando el del albergue — porque el nombre no '
  + 'había cambiado y por lo tanto nunca se propagaba.',
  () => {
    test('valoresDeseados devuelve TODOS los campos, no solo los que cambiaron', () => {
      assert.deepEqual(
        valoresDeseados({
          despues: {
            aliadoNombre: 'VetPet la 30',
            aliadoFotoBase64: 'fotoNueva',
          },
          campos: CAMPOS_PERFIL_ALIADO_A_CHAT,
        }),
        {
          rescatista: 'VetPet la 30',
          // El nombre del negocio vive en DOS campos del chat — ver el
          // comentario de CAMPOS_PERFIL_ALIADO_A_CHAT.
          animalNombre: 'VetPet la 30',
          fotoBase64: 'fotoNueva',
        },
      );
    });

    test('un campo que no existe en el perfil se omite (no se escribe undefined)', () => {
      assert.deepEqual(
        valoresDeseados({
          despues: { aliadoNombre: 'VetPet la 30' },
          campos: CAMPOS_PERFIL_ALIADO_A_CHAT,
        }),
        { rescatista: 'VetPet la 30', animalNombre: 'VetPet la 30' },
      );
    });

    // El segundo caso real de Eliza: el encabezado ya decía "VetPet la 30"
    // (campo `rescatista`, reparado) y justo abajo "Conversando con
    // Veterinario la 30" (campo `animalNombre`, todavía con el nombre
    // anterior del mismo negocio).
    test('detecta el nombre viejo en animalNombre aunque rescatista ya esté bien', () => {
      assert.equal(
        desactualizado(
          {
            rescatista: 'VetPet la 30',
            animalNombre: 'Veterinario la 30',
            fotoBase64: 'fotoNueva',
          },
          {
            rescatista: 'VetPet la 30',
            animalNombre: 'VetPet la 30',
            fotoBase64: 'fotoNueva',
          },
        ),
        true,
      );
    });

    test('un perfil sin ninguno de los campos: null, no hay nada que propagar', () => {
      assert.equal(
        valoresDeseados({
          despues: { albergueNombre: 'Otro rol' },
          campos: CAMPOS_PERFIL_ALIADO_A_CHAT,
        }),
        null,
      );
    });

    // El caso EXACTO de Eliza: el chat tiene la foto ya reparada pero el
    // nombre todavía corrupto (con el del albergue). Tiene que detectarse
    // como desactualizado para que se repare.
    test('detecta el caso real: foto ya correcta pero nombre corrupto', () => {
      const deseados = {
        rescatista: 'VetPet la 30',
        fotoBase64: 'fotoNueva',
      };
      assert.equal(
        desactualizado(
          { rescatista: 'Oiga mire y vea.. venga axa', fotoBase64: 'fotoNueva' },
          deseados,
        ),
        true,
      );
    });

    // La otra mitad del par: sin esto, propagar "todo siempre" reescribiría
    // cada chat en cada guardado de perfil (incluido un refresco de token).
    test('un documento que ya está bien NO se marca para escribir', () => {
      assert.equal(
        desactualizado(
          { rescatista: 'VetPet la 30', fotoBase64: 'fotoNueva' },
          { rescatista: 'VetPet la 30', fotoBase64: 'fotoNueva' },
        ),
        false,
      );
    });

    test('un documento al que le falta el campo del todo se repara', () => {
      assert.equal(
        desactualizado({}, { rescatista: 'VetPet la 30' }),
        true,
      );
    });
  },
);

describe(
  'desactualizado con campos a BORRAR — un chat de animal no debe tener '
  + 'fotoBase64. Hallazgo real de Eliza: cambió la foto del albergue, en la '
  + 'lista de chats seguía la vieja pero al ENTRAR al chat se veía la nueva '
  + '(la lista mira fotoBase64 antes que fotoUrl; el encabezado lee el '
  + 'perfil en vivo).',
  () => {
    test('un chat con fotoBase64 de sobra se marca para reparar, aunque todo lo demás esté bien', () => {
      assert.equal(
        desactualizado(
          { rescatista: 'Mi Albergue', fotoBase64: 'logoViejoDelAlbergue' },
          { rescatista: 'Mi Albergue' },
          CAMPOS_A_BORRAR_EN_CHAT_DE_ANIMAL,
        ),
        true,
      );
    });

    test('un chat de animal limpio (sin fotoBase64) NO se toca', () => {
      assert.equal(
        desactualizado(
          { rescatista: 'Mi Albergue', fotoUrl: 'https://animal.jpg' },
          { rescatista: 'Mi Albergue' },
          CAMPOS_A_BORRAR_EN_CHAT_DE_ANIMAL,
        ),
        false,
      );
    });

    test('sin lista de borrado se comporta como antes (solo compara valores)', () => {
      assert.equal(
        desactualizado(
          { rescatista: 'Mi Albergue', fotoBase64: 'algo' },
          { rescatista: 'Mi Albergue' },
        ),
        false,
      );
    });
  },
);

describe(
  'CAMPOS_ANIMAL_A_SOLICITUD — las etiquetas con las que se calcula el '
  + 'puntaje de compatibilidad. Se copiaban UNA vez al crear la solicitud '
  + 'y nada las volvía a tocar: el rescatista corregía la ficha del animal '
  + 'y la solicitud seguía mostrando el puntaje viejo al aprobarla.',
  () => {
    // El caso real: descubrís que el perro NO es apto con niños y lo
    // corregís. Antes, la solicitud seguía diciendo "100% compatible".
    test('corregir okConNinos en el animal viaja a la solicitud', () => {
      assert.deepEqual(
        cambiosAPropagar({
          antes: { nombre: 'Toby', okConNinos: true },
          despues: { nombre: 'Toby', okConNinos: false },
          campos: CAMPOS_ANIMAL_A_SOLICITUD,
        }),
        { animalOkConNinos: false },
      );
    });

    test('las 5 etiquetas viajan con el nombre que tienen en la solicitud', () => {
      assert.deepEqual(
        cambiosAPropagar({
          antes: {},
          despues: {
            energia: 'Muy activo',
            tamano: 'Grande',
            okConNinos: false,
            okConMascotas: false,
            requiereExperiencia: true,
          },
          campos: CAMPOS_ANIMAL_A_SOLICITUD,
        }),
        {
          animalEnergia: 'Muy activo',
          animalTamano: 'Grande',
          animalOkConNinos: false,
          animalOkConMascotas: false,
          animalRequiereExp: true,
        },
      );
    });

    // Un CHAT no calcula compatibilidad: solo necesita saber de qué animal
    // se habla. Sin esta separación, cada corrección de la ficha escribiría
    // 5 campos inútiles en cada chat.
    test('esas etiquetas NO viajan a los chats', () => {
      assert.equal(
        cambiosAPropagar({
          antes: { nombre: 'Toby', okConNinos: true },
          despues: { nombre: 'Toby', okConNinos: false },
          campos: CAMPOS_ANIMAL_A_CHAT,
        }),
        null,
      );
    });

    test('el nombre y la foto sí viajan a los dos', () => {
      for (const campos of [CAMPOS_ANIMAL_A_CHAT, CAMPOS_ANIMAL_A_SOLICITUD]) {
        assert.deepEqual(
          cambiosAPropagar({
            antes: { nombre: 'Toby' },
            despues: { nombre: 'Tobías' },
            campos,
          }),
          { animalNombre: 'Tobías' },
        );
      }
    });
  },
);

describe(
  'CAMPOS_PERFIL_A_SOLICITUD / _A_CHAT_ADOPTANTE — el lado del adoptante, ' +
  'que no se refrescaba nunca. Mismo patrón que ya nos mordió tres veces ' +
  'del lado del rescatista: el nombre se copia al pedir y nada lo vuelve ' +
  'a mirar.',
  () => {
    test('corregir el nombre del perfil viaja a la solicitud', () => {
      assert.deepStrictEqual(
        cambiosAPropagar({
          antes: { nombre: 'eliza g' },
          despues: { nombre: 'Eliza García' },
          campos: CAMPOS_PERFIL_A_SOLICITUD,
        }),
        { nombre: 'Eliza García' },
      );
    });

    test('y al chat, con el nombre que ese campo tiene allá', () => {
      assert.deepStrictEqual(
        cambiosAPropagar({
          antes: { nombre: 'eliza g' },
          despues: { nombre: 'Eliza García' },
          campos: CAMPOS_PERFIL_A_CHAT_ADOPTANTE,
        }),
        { adoptanteNombre: 'Eliza García' },
      );
    });

    // Lo que NO debe pasar: una cuenta que es albergue Y adoptante a la vez
    // corre los dos juegos de destinos. Si `albergueNombre` se colara acá,
    // sus solicitudes como adoptante quedarían firmadas con el nombre del
    // refugio — el bug de roles cruzados de siempre.
    test('el nombre de ALBERGUE no viaja al lado de adoptante', () => {
      const cambios = cambiosAPropagar({
        antes: { nombre: 'Eliza', albergueNombre: 'La Perla' },
        despues: { nombre: 'Eliza', albergueNombre: 'La Perla Refugio' },
        campos: CAMPOS_PERFIL_A_SOLICITUD,
      });
      assert.strictEqual(cambios, null, 'solo cambió el nombre del refugio');
    });

    // Y el simétrico: el nombre personal no debe pisar la firma del
    // albergue en los chats que publicó con ese otro sombrero.
    test('el nombre personal no viaja al lado de albergue', () => {
      const cambios = cambiosAPropagar({
        antes: { nombre: 'eliza g', albergueNombre: 'La Perla' },
        despues: { nombre: 'Eliza García', albergueNombre: 'La Perla' },
        campos: CAMPOS_PERFIL_A_CHAT,
      });
      assert.strictEqual(cambios, null);
    });

    // El email viene de Auth, no del perfil: no cambia en `usuarios/{uid}`
    // y por eso no está en el mapa. Si alguien lo agrega sin darse cuenta,
    // este test lo frena.
    test('el email NO se propaga', () => {
      assert.ok(!('email' in CAMPOS_PERFIL_A_SOLICITUD));
      assert.deepStrictEqual(Object.keys(CAMPOS_PERFIL_A_SOLICITUD), ['nombre']);
    });
  },
);

describe(
  'CAMPOS_PERFIL_A_ANIMAL_RESCATISTA — los animales publicados con el ' +
  'sombrero de rescatista. Su copia del nombre y la foto de quien los ' +
  'publico no se refrescaba nunca.',
  () => {
    test('cambiar la foto de Google llega a los animales de rescatista', () => {
      assert.deepStrictEqual(
        cambiosAPropagar({
          antes: { foto: 'https://x/vieja.jpg' },
          despues: { foto: 'https://x/nueva.jpg' },
          campos: CAMPOS_PERFIL_A_ANIMAL_RESCATISTA,
        }),
        { rescatistaFotoUrl: 'https://x/nueva.jpg' },
      );
    });

    test('corregirse el nombre tambien', () => {
      assert.deepStrictEqual(
        cambiosAPropagar({
          antes: { nombre: 'eliza g' },
          despues: { nombre: 'Eliza García' },
          campos: CAMPOS_PERFIL_A_ANIMAL_RESCATISTA,
        }),
        { rescatistaNombre: 'Eliza García' },
      );
    });

    // Lo que NO debe pasar. Una cuenta que es rescatista Y albergue corre
    // los dos destinos; si el mapa de rescatista tomara datos del refugio,
    // sus animales propios quedarian firmados por el albergue. Es el bug
    // de roles cruzados de siempre.
    test('nada del ALBERGUE se cuela en los animales de rescatista', () => {
      const cambios = cambiosAPropagar({
        antes: { albergueNombre: 'La Perla', fotoBase64: 'AAA', ciudad: 'Santiago' },
        despues: { albergueNombre: 'La Perla 2', fotoBase64: 'BBB', ciudad: 'Cordoba' },
        campos: CAMPOS_PERFIL_A_ANIMAL_RESCATISTA,
      });
      assert.strictEqual(cambios, null);
    });

    // Y el simetrico: la direccion del refugio si viaja a SUS animales,
    // pero nunca a los de rescatista. Un animal de rescatista esta donde
    // lo encontraron.
    test('la ciudad del refugio NO viaja a los animales de rescatista', () => {
      assert.ok(!('ciudad' in CAMPOS_PERFIL_A_ANIMAL_RESCATISTA));
      assert.ok(!('latitud' in CAMPOS_PERFIL_A_ANIMAL_RESCATISTA));
      assert.strictEqual(CAMPOS_PERFIL_A_ANIMAL.ciudad, 'ubicacion');
    });
  },
);
