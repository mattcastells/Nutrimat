// El filtro de restricciones, contra la lista de casos que ya fallaron.
//
// Existe porque acá equivocarse no es mostrar un número feo: es ofrecerle
// almendras a alguien alérgico a los frutos secos. Y ya pasó — la primera
// versión comparaba palabra exacta, así que "almendra" no pegaba contra
// "almendras" y la receta salía igual. Los plurales son **la forma en que se
// escriben los ingredientes**, no un caso raro.
//
// La otra mitad de la lista es el problema contrario: que el filtro no se pase
// de listo. "Ensalada" y "salmón" contienen "sal" y no son sal; si los
// descartara, alguien con hipertensión no vería nunca ninguna opción y la
// pantalla parecería rota.
//
// Corre en CI con node, después de bundlear con esbuild: el pipeline ya lo
// hace para comprobar que las funciones parsean.

import {
  parseRestrictions,
  restrictionsPrompt,
  RestrictionId,
  violatesRestrictions,
} from './restrictions.ts';

interface Caso {
  readonly descripcion: string;
  readonly plato: string;
  readonly ingredientes: string[];
  readonly pasos?: string[];
  readonly restricciones: RestrictionId[];
  readonly viola: boolean;
}

const CASOS: Caso[] = [
  // ── Lo que tiene que atajar ────────────────────────────────────────────
  {
    descripcion: 'vegano: el queso no pasa',
    plato: 'Tarta de verduras',
    ingredientes: ['Muzzarella', 'Acelga'],
    restricciones: ['vegan'],
    viola: true,
  },
  {
    descripcion: 'vegano: el huevo tampoco',
    plato: 'Tortilla de papas',
    ingredientes: ['Huevo', 'Papa'],
    restricciones: ['vegan'],
    viola: true,
  },
  {
    descripcion: 'celíaco: el pan rallado del rebozado',
    plato: 'Milanesa al horno',
    ingredientes: ['Nalga', 'Pan rallado'],
    restricciones: ['gluten_free'],
    viola: true,
  },
  {
    descripcion: 'celíaco: los ñoquis, con eñe y todo',
    plato: 'Ñoquis con salsa',
    ingredientes: ['Ñoquis', 'Tomate'],
    restricciones: ['gluten_free'],
    viola: true,
  },
  {
    descripcion: 'sin lactosa: el queso que aparece solo en los pasos',
    plato: 'Revuelto de espinaca',
    ingredientes: ['Huevo', 'Espinaca'],
    pasos: ['Espolvorear con queso rallado'],
    restricciones: ['lactose_free'],
    viola: true,
  },
  {
    descripcion: 'frutos secos: "almendras" en plural y con tilde',
    plato: 'Ensalada de rúcula',
    ingredientes: ['Almendras', 'Rúcula'],
    restricciones: ['nut_free'],
    viola: true,
  },
  {
    descripcion: 'mariscos: "langostinos" en plural',
    plato: 'Wok de verduras',
    ingredientes: ['Langostinos', 'Brócoli'],
    restricciones: ['seafood_free'],
    viola: true,
  },
  {
    descripcion: 'hipertensión: el fiambre sí',
    plato: 'Sándwich',
    ingredientes: ['Jamón cocido', 'Pan'],
    restricciones: ['hypertension'],
    viola: true,
  },

  // ── Lo que NO tiene que atajar ─────────────────────────────────────────
  {
    descripcion: 'hipertensión: "ensalada" no es sal',
    plato: 'Ensalada de atún',
    ingredientes: ['Atún al natural', 'Lechuga', 'Tomate'],
    restricciones: ['hypertension'],
    viola: false,
  },
  {
    descripcion: 'hipertensión: "salmón" tampoco',
    plato: 'Salmón al horno',
    ingredientes: ['Salmón', 'Limón'],
    restricciones: ['hypertension'],
    viola: false,
  },
  {
    descripcion: 'celíaco: la "panceta" no es "pan"',
    plato: 'Revuelto',
    ingredientes: ['Panceta', 'Huevo'],
    restricciones: ['gluten_free'],
    viola: false,
  },
  {
    descripcion: 'celíaco: el arroz pasa',
    plato: 'Pollo con arroz',
    ingredientes: ['Pechuga de pollo', 'Arroz'],
    restricciones: ['gluten_free'],
    viola: false,
  },
  {
    descripcion: 'vegetariano: el huevo sí se puede',
    plato: 'Tortilla de papas',
    ingredientes: ['Huevo', 'Papa'],
    restricciones: ['vegetarian'],
    viola: false,
  },
  {
    descripcion: 'vegano: las legumbres pasan',
    plato: 'Guiso de lentejas',
    ingredientes: ['Lentejas', 'Zanahoria', 'Cebolla'],
    restricciones: ['vegan'],
    viola: false,
  },
  {
    descripcion: 'sin restricciones no se filtra nada',
    plato: 'Milanesa con puré',
    ingredientes: ['Nalga', 'Pan rallado'],
    restricciones: [],
    viola: false,
  },
];

let fallos = 0;

function check(ok: boolean, mensaje: string) {
  if (ok) return;
  fallos++;
  console.error(`✗ ${mensaje}`);
}

for (const caso of CASOS) {
  const resultado = violatesRestrictions(
    {
      name: caso.plato,
      items: caso.ingredientes.map((name) => ({ name })),
      steps: caso.pasos ?? [],
    },
    caso.restricciones,
  );
  check(
    resultado === caso.viola,
    `${caso.descripcion}: devolvió ${resultado}, se esperaba ${caso.viola}`,
  );
}

// Una restricción que no existe no condiciona nada: se descarta en vez de
// llegar al prompt como una regla inventada.
check(
  JSON.stringify(parseRestrictions(['vegan', 'inventada', 42, 'vegan'])) ===
    '["vegan"]',
  'parseRestrictions no descartó lo desconocido ni los repetidos',
);
check(parseRestrictions('no es una lista').length === 0, 'parseRestrictions con basura');

// Sin restricciones el prompt no cambia en nada: la función tiene que seguir
// comportándose exactamente como antes para quien no cargó nada.
check(restrictionsPrompt([], '') === '', 'el prompt vacío no está vacío');
check(
  restrictionsPrompt([], 'alergia al kiwi').includes('alergia al kiwi'),
  'la nota libre no llegó al prompt',
);

if (fallos > 0) {
  console.error(`\n${fallos} caso(s) fallaron.`);
  throw new Error('restrictions.test.ts falló');
}
console.log(`✓ ${CASOS.length + 4} comprobaciones de restricciones`);
