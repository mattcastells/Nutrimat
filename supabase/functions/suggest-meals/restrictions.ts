// Lo que esta persona no puede comer, y qué hacer con eso.
//
// Dos capas, y las dos hacen falta:
//
// 1. **El prompt.** Se le dice al modelo qué no puede usar, con la misma
//    dureza con la que se le dice el presupuesto.
// 2. **El filtro.** Se revisa lo que devolvió y se descarta la opción entera si
//    aparece un ingrediente prohibido. Es la misma decisión que ya se tomó con
//    las calorías: la regla que importa no se le delega al modelo, porque un
//    modelo que casi siempre acierta igual se equivoca, y acá equivocarse es
//    ofrecerle queso a alguien con alergia a la leche.
//
// El filtro es por palabra y por eso es tosco: no entiende de recetas, entiende
// de nombres. Un falso positivo cuesta una opción menos —hay tres— y un falso
// negativo cuesta que alguien coma algo que no puede. La asimetría manda: ante
// la duda, se descarta.

/** Los `wire` de `DietaryFlag` (lib/domain/enums/enums.dart). */
export type RestrictionId =
  | 'vegetarian'
  | 'vegan'
  | 'gluten_free'
  | 'lactose_free'
  | 'nut_free'
  | 'seafood_free'
  | 'diabetes'
  | 'hypertension';

interface Restriction {
  /** Lo que se le pide al modelo, en una línea. */
  readonly rule: string;
  /**
   * Palabras que descartan una opción si aparecen en el nombre de un
   * ingrediente. Vacío cuando la restricción no se puede comprobar así.
   *
   * Van sin tilde y en minúscula: el texto a comparar se normaliza antes.
   */
  readonly banned: readonly string[];
}

const RESTRICTIONS: Record<RestrictionId, Restriction> = {
  vegetarian: {
    rule:
      'No uses carne de ningún animal: ni vaca, ni cerdo, ni pollo, ni ' +
      'pescado, ni fiambres. Huevo y lácteos sí.',
    banned: [
      'carne', 'vacuno', 'ternera', 'bife', 'asado', 'milanesa de carne',
      'pollo', 'pechuga', 'pavita', 'cerdo', 'panceta', 'bondiola', 'chorizo',
      'jamon', 'salame', 'mortadela', 'salchicha', 'hamburguesa de carne',
      'pescado', 'merluza', 'atun', 'salmon', 'marisco', 'camaron', 'langostino',
      'anchoa', 'higado', 'cordero', 'conejo', 'gelatina',
    ],
  },
  vegan: {
    rule:
      'No uses nada de origen animal: ni carnes, ni pescado, ni huevo, ni ' +
      'leche, ni queso, ni yogur, ni manteca, ni miel.',
    banned: [
      'carne', 'vacuno', 'ternera', 'bife', 'asado', 'pollo', 'pechuga',
      'cerdo', 'panceta', 'bondiola', 'chorizo', 'jamon', 'salame',
      'mortadela', 'salchicha', 'pescado', 'merluza', 'atun', 'salmon',
      'marisco', 'camaron', 'langostino', 'anchoa', 'higado', 'cordero',
      'huevo', 'clara de huevo', 'yema', 'leche', 'queso', 'muzzarella',
      'mozzarella', 'ricota', 'yogur', 'manteca', 'crema', 'dulce de leche',
      'miel', 'gelatina',
    ],
  },
  gluten_free: {
    rule:
      'Sin gluten: ni trigo, ni avena, ni cebada, ni centeno. Nada de harina ' +
      'común, pan, pastas, rebozados, galletitas ni cerveza. Usá arroz, papa, ' +
      'maíz o legumbres.',
    banned: [
      'trigo', 'harina de trigo', 'harina 000', 'harina 0000', 'pan',
      'pan rallado', 'rebozado', 'empanizado', 'fideos', 'pasta', 'ñoquis',
      'noquis', 'ravioles', 'tallarines', 'tapa de empanada', 'tarta',
      'galletita', 'bizcochuelo', 'avena', 'cebada', 'centeno', 'cerveza',
      'semola', 'cuscus', 'salvado de trigo', 'masa', 'prepizza', 'tostada',
    ],
  },
  lactose_free: {
    rule:
      'Sin lactosa: ni leche, ni queso, ni yogur, ni crema, ni manteca, ni ' +
      'dulce de leche.',
    banned: [
      'leche', 'queso', 'muzzarella', 'mozzarella', 'ricota', 'yogur',
      'crema', 'manteca', 'dulce de leche', 'helado', 'flan',
    ],
  },
  nut_free: {
    rule:
      'Sin frutos secos ni maní: tampoco sus aceites, mantecas ni harinas.',
    banned: [
      'mani', 'nuez', 'nueces', 'almendra', 'avellana', 'castaña', 'castana',
      'pistacho', 'anacardo', 'caju', 'pecan', 'praline', 'nutella',
      'mantequilla de mani', 'manteca de mani',
    ],
  },
  seafood_free: {
    rule: 'Sin pescado ni mariscos, ni sus derivados.',
    banned: [
      'pescado', 'merluza', 'atun', 'salmon', 'sardina', 'anchoa', 'caballa',
      'marisco', 'camaron', 'langostino', 'mejillon', 'calamar', 'pulpo',
      'almeja', 'cangrejo', 'surimi', 'salsa de pescado',
    ],
  },
  diabetes: {
    rule:
      'Cuidá los azúcares: nada de azúcar agregada, dulces, gaseosas comunes ' +
      'ni jugos azucarados. Preferí integrales y sumá fibra y proteína en ' +
      'cada plato.',
    banned: [
      'azucar', 'dulce de leche', 'mermelada', 'miel', 'gaseosa', 'jugo azucarado',
      'jarabe', 'caramelo', 'chocolate con leche', 'galletita dulce', 'factura',
      'medialuna', 'helado', 'torta',
    ],
  },
  hypertension: {
    rule:
      'Bajo en sodio: nada de fiambres, embutidos, snacks salados, caldos en ' +
      'cubo ni conservas saladas. Condimentá con hierbas en vez de sal.',
    banned: [
      'fiambre', 'jamon', 'salame', 'mortadela', 'panceta', 'chorizo',
      'salchicha', 'caldo en cubo', 'cubito de caldo', 'sopa instantanea',
      'papas fritas de paquete', 'snack salado', 'aceituna', 'anchoa',
      'sal fina', 'sal gruesa', 'salsa de soja',
    ],
  },
};

/**
 * Sin tildes y en minúscula: "Salmón" y "salmon" son la misma palabra.
 *
 * El rango de marcas de acento va con escapes y no con los caracteres
 * combinantes literales: en el archivo se verían como espacios raros y el
 * próximo que lo edite los borra sin saber qué eran.
 */
function normalize(value: string): string {
  return value
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
}

/** Lee lo que mandó la app y descarta lo que no reconoce. */
export function parseRestrictions(raw: unknown): RestrictionId[] {
  if (!Array.isArray(raw)) return [];
  const out: RestrictionId[] = [];
  for (const entry of raw.slice(0, 16)) {
    if (typeof entry !== 'string') continue;
    if (entry in RESTRICTIONS && !out.includes(entry as RestrictionId)) {
      out.push(entry as RestrictionId);
    }
  }
  return out;
}

/** Lo que se le agrega al prompt. Cadena vacía si no hay nada que restringir. */
export function restrictionsPrompt(
  ids: RestrictionId[],
  note: string,
): string {
  if (ids.length === 0 && !note) return '';

  const reglas = ids.map((id) => `- ${RESTRICTIONS[id].rule}`);
  if (note) {
    reglas.push(
      `- Además, la persona aclara: "${note}". Respetalo como si fuera una ` +
        'de las reglas de arriba.',
    );
  }

  return `
RESTRICCIONES ALIMENTARIAS — MANDAN SOBRE TODO LO DEMÁS

Esta persona no puede o no quiere comer ciertas cosas. Ninguna de las tres
opciones puede incluirlas, ni como ingrediente principal ni como acompañamiento
ni "a gusto":

${reglas.join('\n')}

Si con estas restricciones y ese presupuesto no te salen tres opciones,
devolvé las que sí cierren. Es mejor una opción que la persona puede comer que
tres que no. No sustituyas en silencio: si una receta clásica no se puede
hacer, proponé otra.
`;
}

/**
 * Si una opción viola alguna restricción.
 *
 * Se mira el nombre del plato, el de cada ingrediente y los pasos: una receta
 * que dice "espolvorear con queso" tiene queso aunque no esté en la lista de
 * ingredientes.
 */
export function violatesRestrictions(
  option: { name: string; items: { name: string }[]; steps: string[] },
  ids: RestrictionId[],
): boolean {
  if (ids.length === 0) return false;

  const texto = normalize(
    [option.name, ...option.items.map((i) => i.name), ...option.steps].join(' · '),
  );

  for (const id of ids) {
    for (const palabra of RESTRICTIONS[id].banned) {
      // Tres cosas pasan en esta expresión y las tres hacen falta:
      //
      // 1. La palabra vetada se normaliza igual que el texto. En la lista hay
      //    "ñoquis" y "castaña", y comparar sin normalizar las dos puntas hace
      //    que esas dos entradas no peguen nunca.
      // 2. Límites de palabra. Sin eso "sal" pega dentro de "salmón" y
      //    "ensalada", y quien tiene hipertensión se queda sin ninguna opción.
      // 3. El plural, con `(es|s)?`. Una receta dice "almendras" y
      //    "langostinos", no "almendra" y "langostino": sin esta parte, la
      //    lista entera dejaba pasar justo la forma en que se escriben los
      //    ingredientes. Solo el plural y no cualquier continuación, porque
      //    con prefijo suelto "pan" se llevaría puesta a la "panceta".
      const patron = new RegExp(
        `(^|[^a-z0-9])${escapeRegExp(normalize(palabra))}(es|s)?([^a-z0-9]|$)`,
      );
      if (patron.test(texto)) return true;
    }
  }
  return false;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
