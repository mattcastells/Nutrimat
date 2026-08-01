// Lo que comparten `analyze-meal-photo` y `analyze-meal-text`.
//
// Las dos estiman la misma cosa —los ítems de una comida— y difieren solo en
// qué le mandan a Gemini: una imagen o una descripción. Todo lo demás (el
// contrato de salida, la validación, la llamada, el manejo de límites) tiene
// que ser idéntico, y la única forma de que siga siéndolo dentro de seis meses
// es que sea el mismo código.
//
// Duplicar la validación sería peor que duplicar cualquier otra cosa: es la
// que impide que un "9000 kcal" entre al historial de alguien.

export const GEMINI_MODEL = Deno.env.get('GEMINI_MODEL') ?? 'gemini-3.6-flash';
export const PROMPT_VERSION = Deno.env.get('GEMINI_PROMPT_VERSION') ?? 'v3';

/** Cuota diaria por usuario (D-18). */
export const DAILY_QUOTA = 20;

/** El proveedor puede tardar; más de esto es una app colgada. */
export const GEMINI_TIMEOUT_MS = 25_000;

export const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
};

export function fail(code: string, message: string, status = 400): Response {
  return new Response(
    JSON.stringify({ error: { code, message } }),
    { status, headers: { ...CORS, 'Content-Type': 'application/json' } },
  );
}

export function ok(payload: unknown): Response {
  return new Response(
    JSON.stringify(payload),
    { headers: { ...CORS, 'Content-Type': 'application/json' } },
  );
}

/**
 * Mismo contrato que `docs/handoff/gemini-output-schema.json`, en el dialecto
 * que entiende Gemini. Se pasa como `responseSchema` para que el modelo no
 * pueda devolver otra forma, y **igual** se valida después: que el proveedor
 * prometa un formato no es garantía de que lo cumpla.
 */
export const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  required: ['items', 'overallConfidence'],
  properties: {
    items: {
      type: 'ARRAY',
      maxItems: 12,
      items: {
        type: 'OBJECT',
        required: [
          'name', 'quantity', 'unit', 'kcal',
          'proteinG', 'carbsG', 'fatG', 'confidence',
        ],
        properties: {
          name: { type: 'STRING' },
          quantity: { type: 'NUMBER' },
          unit: {
            type: 'STRING',
            enum: ['g', 'ml', 'unidad', 'taza', 'cucharada', 'rebanada', 'porcion'],
          },
          kcal: { type: 'INTEGER' },
          proteinG: { type: 'NUMBER' },
          carbsG: { type: 'NUMBER' },
          fatG: { type: 'NUMBER' },
          confidence: { type: 'NUMBER' },
          preparation: { type: 'STRING' },
          visualReference: { type: 'STRING' },
        },
      },
    },
    overallConfidence: { type: 'NUMBER' },
  },
};

export interface AnalysisItem {
  name: string;
  quantity: number;
  unit: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  confidence: number;
  preparation?: string;
  visualReference?: string;
}

const UNITS = ['g', 'ml', 'unidad', 'taza', 'cucharada', 'rebanada', 'porcion'];

/**
 * Valida la respuesta contra el contrato y descarta los ítems que no cumplen.
 *
 * Devuelve `null` solo si la respuesta entera es inservible. Un ítem con un
 * número imposible se tira y los demás siguen: perder un alimento es mejor que
 * perder el análisis completo, y **muchísimo** mejor que meterle a alguien un
 * "9000 kcal" al historial.
 */
export function validate(raw: unknown): AnalysisItem[] | null {
  if (!raw || typeof raw !== 'object') return null;
  const rawItems = (raw as { items?: unknown }).items;
  if (!Array.isArray(rawItems)) return null;

  const clean: AnalysisItem[] = [];
  for (const entry of rawItems.slice(0, 12)) {
    if (!entry || typeof entry !== 'object') continue;
    const i = entry as Record<string, unknown>;

    const name = typeof i.name === 'string' ? i.name.trim() : '';
    if (!name || name.length > 120) continue;

    const quantity = Number(i.quantity);
    const kcal = Number(i.kcal);
    const proteinG = Number(i.proteinG);
    const carbsG = Number(i.carbsG);
    const fatG = Number(i.fatG);
    const confidence = Number(i.confidence);
    const unit = typeof i.unit === 'string' ? i.unit : '';

    const inRange = (v: number, min: number, max: number) =>
      Number.isFinite(v) && v >= min && v <= max;

    if (!inRange(quantity, 0.1, 5000)) continue;
    if (!inRange(kcal, 0, 3000)) continue;
    if (!inRange(proteinG, 0, 500)) continue;
    if (!inRange(carbsG, 0, 500)) continue;
    if (!inRange(fatG, 0, 500)) continue;
    if (!inRange(confidence, 0, 1)) continue;
    if (!UNITS.includes(unit)) continue;

    clean.push({
      name,
      quantity,
      unit,
      kcal: Math.round(kcal),
      proteinG,
      carbsG,
      fatG,
      confidence,
      preparation: typeof i.preparation === 'string'
        ? i.preparation.slice(0, 60)
        : undefined,
      visualReference: typeof i.visualReference === 'string'
        ? i.visualReference.slice(0, 120)
        : undefined,
    });
  }

  // El array vacío es una respuesta válida — significa "no hay comida" — y por
  // eso se distingue de `null`, que es "la respuesta no se pudo leer".
  return clean;
}

export interface GeminiOutcome {
  parsed: unknown;
  lastError: string;
  rateLimited: boolean;
  latencyMs: number;
}

/**
 * Le manda las partes a Gemini y devuelve el JSON ya parseado.
 *
 * Reintenta una vez: si el JSON vino inválido, el segundo intento va con
 * `temperature: 0` y es determinista, así que insistir más no aportaría nada.
 * Un 429 (pasaste el límite del plan) o un 503 (modelo saturado) se reintentan
 * con una espera corta, porque el límite por minuto se libera solo — y se
 * marcan aparte, porque no son "la comida está mal descripta" y decirlo así
 * manda a corregir el lugar equivocado.
 */
export async function callGemini(
  apiKey: string,
  parts: unknown[],
  // Por omisión el contrato de estimación, que es el que usan las dos
  // funciones que estiman una comida. `suggest-meals` devuelve otra forma
  // —tres opciones, cada una con sus ingredientes y su receta— y pasa la suya.
  schema: unknown = RESPONSE_SCHEMA,
): Promise<GeminiOutcome> {
  const startedAt = Date.now();
  let parsed: unknown = null;
  let lastError = '';
  let rateLimited = false;

  for (const temperature of [0.2, 0]) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), GEMINI_TIMEOUT_MS);

      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
        {
          method: 'POST',
          signal: controller.signal,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: JSON.stringify({
            contents: [{ parts }],
            generationConfig: {
              temperature,
              responseMimeType: 'application/json',
              responseSchema: schema,
            },
          }),
        },
      );
      clearTimeout(timer);

      if (!response.ok) {
        // El cuerpo dice *por qué*; sin él, un 404 puede ser el modelo, la
        // clave o la URL y no hay forma de distinguirlos.
        const detail = await response.text().catch(() => '');
        lastError = `Gemini ${response.status}: ${detail.slice(0, 300)}`;
        if (response.status === 429 || response.status === 503) {
          rateLimited = true;
          await new Promise((r) => setTimeout(r, 2000));
        }
        continue;
      }
      rateLimited = false;

      const payload = await response.json();
      const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!text) {
        lastError = 'Gemini no devolvió contenido';
        continue;
      }

      parsed = JSON.parse(text);
      break;
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
  }

  return { parsed, lastError, rateLimited, latencyMs: Date.now() - startedAt };
}

/** El 429 del proveedor, con su propio código y su propio texto. */
export function rateLimitedResponse(): Response {
  return fail(
    'ERR_AI_RATE_LIMITED',
    // Ojo con el `+`: TypeScript **no** concatena literales adyacentes como
    // Dart. Sin él esto no es un string partido en dos líneas, es un error de
    // sintaxis, y el deploy de la función falla entero.
    'El servicio de análisis está al límite por ahora. Esperá un minuto y ' +
      'probá de nuevo, o cargá la comida a mano.',
    429,
  );
}
