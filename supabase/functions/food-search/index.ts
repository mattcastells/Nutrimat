// food-search — alimentos genéricos, vía USDA FoodData Central.
//
// Existe por la misma razón que `analyze-meal-photo`: la clave de USDA no
// puede vivir en el APK. Una clave dentro de un APK es una clave regalada.
//
// Qué tapa. Open Food Facts es un catálogo de **productos envasados con código
// de barras**: sirve para un yogur de una marca, y es ciego a "pechuga de
// pollo", "arroz cocido" o "manzana". USDA cubre justamente eso.
//
// Y qué NO hace: los alimentos argentinos no se buscan acá. La tabla de
// ARGENFOODS viaja dentro del APK, así que se resuelve sin red y al instante.
// Esta función es para lo genérico que esa tabla no tiene.

const USDA_BASE = 'https://api.nal.usda.gov/fdc/v1/foods/search';

/** Más que esto es una espera que la app no debería sostener. */
const TIMEOUT_MS = 12_000;

/**
 * Números de nutriente de USDA (tagnames INFOODS, estables desde SR Legacy).
 *
 * Se busca por `nutrientNumber` y no por nombre: los nombres cambian de
 * capitalización y de idioma entre datasets, los números no. El 208 es la
 * energía en kcal; el 268 es la misma energía en kJ y no se usa.
 */
const NUTRIENTES = {
  kcal: '208',
  protein: '203',
  fat: '204',
  carbs: '205',
};

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
};

function fail(code: string, message: string, status = 400): Response {
  return new Response(
    JSON.stringify({ error: { code, message } }),
    { status, headers: { ...CORS, 'Content-Type': 'application/json' } },
  );
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  // Se exige sesión aunque el dato sea público: sin esto la función es un
  // proxy abierto contra nuestra cuota de USDA.
  if (!req.headers.get('Authorization')) {
    return fail('ERR_UNAUTHENTICATED', 'Falta la sesión.', 401);
  }

  const apiKey = Deno.env.get('USDA_API_KEY');
  if (!apiKey) {
    return fail(
      'ERR_PROVIDER_UNAVAILABLE',
      'La búsqueda de alimentos genéricos no está configurada en el servidor.',
      503,
    );
  }

  let query: string;
  let limit: number;
  try {
    const body = await req.json();
    query = String(body.query ?? '').trim();
    limit = Math.min(Math.max(Number(body.limit ?? 20), 1), 50);
  } catch {
    return fail('ERR_VALIDATION', 'Falta qué buscar.');
  }
  if (query.length < 2) return fail('ERR_VALIDATION', 'Escribí al menos dos letras.');

  const url = new URL(USDA_BASE);
  url.searchParams.set('api_key', apiKey);
  url.searchParams.set('query', query);
  url.searchParams.set('pageSize', String(limit));
  // Foundation y SR Legacy son los alimentos genéricos y crudos, que es lo que
  // acá falta. `Branded` queda afuera a propósito: eso ya lo cubre Open Food
  // Facts, y con productos de góndola argentinos en vez de estadounidenses.
  url.searchParams.append('dataType', 'Foundation');
  url.searchParams.append('dataType', 'SR Legacy');

  let payload: unknown;
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
    const response = await fetch(url, { signal: controller.signal });
    clearTimeout(timer);

    if (response.status === 429) {
      return fail(
        'ERR_RATE_LIMITED',
        'El catálogo está al límite de consultas por ahora. Probá en un rato.',
        429,
      );
    }
    if (!response.ok) {
      const detail = await response.text().catch(() => '');
      return fail(
        'ERR_UPSTREAM_FAILED',
        `El catálogo respondió ${response.status}. ${detail.slice(0, 120)}`,
        502,
      );
    }
    payload = await response.json();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return fail('ERR_UPSTREAM_FAILED', `No pudimos consultar el catálogo (${message}).`, 502);
  }

  const foods = (payload as { foods?: unknown[] })?.foods ?? [];
  const out = [];

  for (const raw of foods) {
    const food = raw as Record<string, unknown>;
    const nutrients = (food.foodNutrients as Record<string, unknown>[]) ?? [];

    const valor = (numero: string): number | null => {
      for (const n of nutrients) {
        if (String(n.nutrientNumber ?? '') === numero) {
          const v = Number(n.value);
          return Number.isFinite(v) ? v : null;
        }
      }
      return null;
    };

    const kcal = valor(NUTRIENTES.kcal);
    const proteinG = valor(NUTRIENTES.protein);
    const carbsG = valor(NUTRIENTES.carbs);
    const fatG = valor(NUTRIENTES.fat);

    // Sin energía no sirve para registrar una comida: se descarta en vez de
    // mandarle a la app un alimento de 0 kcal que arruinaría el total del día.
    if (kcal === null || kcal < 0 || kcal > 900) continue;

    const description = String(food.description ?? '').trim();
    if (!description) continue;

    out.push({
      id: `usda:${food.fdcId}`,
      name: description.toLowerCase(),
      source: 'usda',
      // USDA publica todo por 100 g de alimento.
      servingSize: 100,
      servingUnit: 'g',
      kcal: Math.round(kcal),
      proteinG: proteinG ?? 0,
      carbsG: carbsG ?? 0,
      fatG: fatG ?? 0,
      portions: [{ label: '100 g', grams: 100 }],
    });
  }

  return new Response(
    JSON.stringify({ foods: out }),
    { headers: { ...CORS, 'Content-Type': 'application/json' } },
  );
});
