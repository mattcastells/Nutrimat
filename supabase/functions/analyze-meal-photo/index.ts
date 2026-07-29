// analyze-meal-photo (08-supabase-plan.md §4, 12-external-integrations.md §1).
//
// Descarga la foto del bucket privado del usuario, se la manda a Gemini con el
// prompt versionado y el schema de salida, valida la respuesta y la persiste en
// `ai_analyses`.
//
// La clave de Gemini vive **solo acá**, en los secretos del proyecto. Ese es el
// motivo de que esta función exista en vez de que la app llame a Gemini
// directo: una clave dentro de un APK es una clave regalada.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { PROMPT_V3 } from './prompts/v3.ts';

// El 2.5-flash que fijaba el handoff quedó retirado para proyectos nuevos.
// Se fija una versión concreta y no `gemini-flash-latest`: un alias que cambia
// solo puede alterar las estimaciones sin que nadie toque el prompt.
const GEMINI_MODEL = Deno.env.get('GEMINI_MODEL') ?? 'gemini-3.6-flash';
const PROMPT_VERSION = Deno.env.get('GEMINI_PROMPT_VERSION') ?? 'v3';

/** Cuota diaria por usuario (D-18). */
const DAILY_QUOTA = 20;

/** El proveedor puede tardar; más de esto es una app colgada. */
const GEMINI_TIMEOUT_MS = 25_000;

const PROMPT = PROMPT_V3;

/**
 * Mismo contrato que `docs/handoff/gemini-output-schema.json`, en el dialecto
 * que entiende Gemini. Se pasa como `responseSchema` para que el modelo no
 * pueda devolver otra forma, y **igual** se valida después: que el proveedor
 * prometa un formato no es garantía de que lo cumpla.
 */
const RESPONSE_SCHEMA = {
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

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return fail('ERR_UNAUTHENTICATED', 'Falta la sesión.', 401);
  }

  const geminiKey = Deno.env.get('GEMINI_API_KEY');
  if (!geminiKey) {
    return fail(
      'ERR_PROVIDER_UNAVAILABLE',
      'El análisis por foto no está configurado en el servidor.',
      503,
    );
  }

  // El cliente se crea con el JWT de quien llama, no con la secret key: así
  // RLS sigue aplicando y la función no puede leer la foto de otra persona
  // aunque le pasen una ruta ajena.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await supabase.auth.getUser();
  const user = userData?.user;
  if (userError || !user) {
    return fail('ERR_UNAUTHENTICATED', 'Tu sesión venció.', 401);
  }

  let photoPath: string;
  try {
    const body = await req.json();
    photoPath = String(body.photoPath ?? '');
  } catch {
    return fail('ERR_VALIDATION', 'Falta indicar la foto.');
  }
  if (!photoPath) return fail('ERR_VALIDATION', 'Falta indicar la foto.');

  // Defensa en profundidad: RLS ya impide leer la carpeta de otro, pero se
  // rechaza acá también para que el error sea claro y no un 403 de Storage.
  if (!photoPath.startsWith(`${user.id}/`)) {
    return fail('ERR_FORBIDDEN', 'Esa foto no es tuya.', 403);
  }

  // ── Cuota diaria ───────────────────────────────────────────────────────
  const since = new Date();
  since.setUTCHours(0, 0, 0, 0);

  const { count } = await supabase
    .from('ai_analyses')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', user.id)
    .gte('created_at', since.toISOString());

  if ((count ?? 0) >= DAILY_QUOTA) {
    return fail(
      'ERR_QUOTA_EXCEEDED',
      `Llegaste a los ${DAILY_QUOTA} análisis de hoy. Podés cargar la comida a mano.`,
      429,
    );
  }

  // ── Foto ───────────────────────────────────────────────────────────────
  const { data: blob, error: downloadError } = await supabase
    .storage.from('meal-photos').download(photoPath);

  if (downloadError || !blob) {
    return fail('ERR_NOT_FOUND', 'No encontramos esa foto.', 404);
  }

  const bytes = new Uint8Array(await blob.arrayBuffer());
  const base64 = toBase64(bytes);

  // ── Gemini ─────────────────────────────────────────────────────────────
  const startedAt = Date.now();
  let parsed: unknown = null;
  let lastError = '';

  // Un JSON inválido se reintenta una vez con temperature 0; el segundo
  // intento es determinista, así que insistir más no aportaría nada.
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
            'x-goog-api-key': geminiKey,
          },
          body: JSON.stringify({
            contents: [{
              parts: [
                { text: PROMPT },
                { inlineData: { mimeType: 'image/jpeg', data: base64 } },
              ],
            }],
            generationConfig: {
              temperature,
              responseMimeType: 'application/json',
              responseSchema: RESPONSE_SCHEMA,
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
        continue;
      }

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

  const latencyMs = Date.now() - startedAt;

  const items = validate(parsed);
  if (items === null) {
    // Queda registrado el fallo: es lo que permite saber si el prompt empeoró
    // sin depender de que alguien lo reporte.
    await supabase.from('ai_analyses').insert({
      id: crypto.randomUUID(),
      user_id: user.id,
      photo_path: photoPath,
      status: 'failed',
      model: GEMINI_MODEL,
      prompt_version: PROMPT_VERSION,
      error_code: 'ERR_AI_INVALID_RESPONSE',
      latency_ms: latencyMs,
    });
    return fail(
      'ERR_AI_INVALID_RESPONSE',
      `No pudimos leer la foto (${lastError}). Cargá la comida a mano; la foto queda adjunta.`,
      502,
    );
  }

  if (items.length === 0) {
    return fail(
      'ERR_AI_NO_FOOD',
      'No vimos comida en la foto. Probá con otra o cargala a mano.',
      422,
    );
  }

  const confidenceAvg =
    items.reduce((acc, i) => acc + i.confidence, 0) / items.length;

  const id = crypto.randomUUID();
  await supabase.from('ai_analyses').insert({
    id,
    user_id: user.id,
    photo_path: photoPath,
    status: 'completed',
    model: GEMINI_MODEL,
    prompt_version: PROMPT_VERSION,
    items,
    raw_response: parsed,
    confidence_avg: Number(confidenceAvg.toFixed(2)),
    latency_ms: latencyMs,
  });

  return new Response(
    JSON.stringify({
      id,
      items,
      overallConfidence: Number(confidenceAvg.toFixed(2)),
      model: GEMINI_MODEL,
      promptVersion: PROMPT_VERSION,
      latencyMs,
    }),
    { headers: { ...CORS, 'Content-Type': 'application/json' } },
  );
});

/**
 * Base64 por bloques.
 *
 * `String.fromCharCode(...bytes)` parece lo obvio y es una bomba: pasa cada
 * byte como un argumento, y con una foto de 1024 px son ~200 000 argumentos —
 * bastante más de lo que aguanta la pila. Reventaba con **cualquier** foto
 * real, que es por qué el análisis se quedaba cargando para siempre.
 */
function toBase64(bytes: Uint8Array): string {
  const CHUNK = 0x8000;
  let binary = '';
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary);
}

interface AnalysisItem {
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
function validate(raw: unknown): AnalysisItem[] | null {
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
