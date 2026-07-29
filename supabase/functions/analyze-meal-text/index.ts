// analyze-meal-text — estimar una comida a partir de una descripción escrita.
//
// "dos empanadas de carne y una coca". Es lo que Open Food Facts no puede
// contestar: su base son productos envasados con código de barras, y casi todo
// lo que se come acá —asado, milanesa, empanada, un plato de fideos— no tiene
// código de barras ni etiqueta.
//
// Comparte con `analyze-meal-photo` el contrato de salida, la validación, la
// cuota y el manejo de errores (`_shared/estimation.ts`). Lo único distinto es
// qué se le manda al modelo: acá texto, allá una imagen.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { PROMPT_TEXT_V1 } from './prompts/text_v1.ts';
import {
  CORS,
  DAILY_QUOTA,
  GEMINI_MODEL,
  PROMPT_VERSION,
  callGemini,
  fail,
  ok,
  rateLimitedResponse,
  validate,
} from '../_shared/estimation.ts';

/** Una descripción más larga que esto no es una comida, es un relato. */
const MAX_DESCRIPTION = 400;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return fail('ERR_UNAUTHENTICATED', 'Falta la sesión.', 401);

  const geminiKey = Deno.env.get('GEMINI_API_KEY');
  if (!geminiKey) {
    return fail(
      'ERR_PROVIDER_UNAVAILABLE',
      'La estimación por texto no está configurada en el servidor.',
      503,
    );
  }

  // Con el JWT de quien llama, no con la secret key: así RLS sigue aplicando.
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await supabase.auth.getUser();
  const user = userData?.user;
  if (userError || !user) return fail('ERR_UNAUTHENTICATED', 'Tu sesión venció.', 401);

  let description: string;
  try {
    const body = await req.json();
    description = String(body.description ?? '').trim();
  } catch {
    return fail('ERR_VALIDATION', 'Falta la descripción.');
  }
  if (description.length < 3) {
    return fail('ERR_VALIDATION', 'Contanos qué comiste, con un poco más de detalle.');
  }
  if (description.length > MAX_DESCRIPTION) {
    description = description.slice(0, MAX_DESCRIPTION);
  }

  // ── Cuota diaria ───────────────────────────────────────────────────────
  // Comparte el cupo con el análisis por foto: las dos gastan lo mismo del
  // proveedor, y separarlas daría 40 por día por la puerta de atrás.
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
      `Llegaste a las ${DAILY_QUOTA} estimaciones de hoy. Podés cargar la comida a mano.`,
      429,
    );
  }

  // ── Gemini ─────────────────────────────────────────────────────────────
  const { parsed, lastError, rateLimited, latencyMs } = await callGemini(
    geminiKey,
    [{ text: `${PROMPT_TEXT_V1}\n\nDescripción: ${description}` }],
  );

  const registrar = (status: string, errorCode?: string, extra?: object) =>
    supabase.from('ai_analyses').insert({
      id: crypto.randomUUID(),
      user_id: user.id,
      status,
      model: GEMINI_MODEL,
      prompt_version: PROMPT_VERSION,
      error_code: errorCode,
      latency_ms: latencyMs,
      ...extra,
    });

  if (parsed === null && rateLimited) {
    await registrar('failed', 'ERR_AI_RATE_LIMITED');
    return rateLimitedResponse();
  }

  const items = validate(parsed);
  if (items === null) {
    await registrar('failed', 'ERR_AI_INVALID_RESPONSE');
    return fail(
      'ERR_AI_INVALID_RESPONSE',
      `No pudimos interpretar la respuesta (${lastError}). Cargá la comida a mano.`,
      502,
    );
  }

  if (items.length === 0) {
    return fail(
      'ERR_AI_NO_FOOD',
      'No reconocimos ninguna comida en esa descripción. Probá nombrando los '
        'alimentos y las cantidades: "dos empanadas de carne, un vaso de coca".',
      422,
    );
  }

  const confidenceAvg =
    items.reduce((acc, i) => acc + i.confidence, 0) / items.length;

  const id = crypto.randomUUID();
  await supabase.from('ai_analyses').insert({
    id,
    user_id: user.id,
    status: 'completed',
    model: GEMINI_MODEL,
    prompt_version: PROMPT_VERSION,
    items,
    raw_response: parsed,
    confidence_avg: Number(confidenceAvg.toFixed(2)),
    latency_ms: latencyMs,
  });

  return ok({
    id,
    items,
    overallConfidence: Number(confidenceAvg.toFixed(2)),
    model: GEMINI_MODEL,
    promptVersion: PROMPT_VERSION,
    latencyMs,
  });
});
