-- 39 · Guardar lo que el proveedor ya nos decía y tirábamos.
--
-- El 13 de agosto la app rebotó contra el límite de Gemini toda la tarde, y
-- reconstruir por qué costó sumar pedidos a mano en una planilla. La tabla
-- tenía la hora y `ERR_AI_RATE_LIMITED`, y con eso no alcanzaba para separar
-- dos cosas que son distintas.
--
-- **429 y 503 no son lo mismo y se guardaban igual.** El 429 es la cuota
-- agotada: no hay nada que hacer hasta que se libere. El 503 es el modelo
-- saturado un momento — el de las 16:47 se arregló solo, diez segundos
-- después. Leídos como una sola falla mandaban a buscar el problema al lugar
-- equivocado. Desde ahora el segundo tiene su propio código,
-- `ERR_AI_OVERLOADED`, y por eso `error_code` no lleva `check`: los códigos
-- los inventa el proveedor y no vamos a salir a migrar cada vez que aparezca
-- uno nuevo.
--
-- **Y faltaba por qué el modelo cortó.** Ese mismo día, cuatro de los veinte
-- pedidos se fueron en respuestas ilegibles; cada una cuesta doble porque
-- dispara un segundo intento. Sin `finish_reason` no hay forma de saber si el
-- JSON llegó truncado, si lo frenó un filtro, o si el modelo se quedó sin
-- presupuesto de salida razonando — que además es la mitad cara de la factura,
-- porque los tokens de razonamiento se cobran como salida. Con
-- `tokens_thinking` eso se contesta mirando, no suponiendo.
--
-- Las cuatro columnas las llenan solas las Edge Functions, en la fila que ya
-- escriben. No hay dato nuevo que pedirle a nadie: es dejar de descartar el
-- que el proveedor manda en cada respuesta.

alter table public.ai_analyses
  add column if not exists finish_reason   text,
  add column if not exists tokens_in       integer,
  add column if not exists tokens_out      integer,
  add column if not exists tokens_thinking integer;

comment on column public.ai_analyses.finish_reason is
  'finishReason del proveedor: STOP, MAX_TOKENS, SAFETY, RECITATION…';
comment on column public.ai_analyses.tokens_in is
  'Tokens de entrada: el prompt más la foto.';
comment on column public.ai_analyses.tokens_out is
  'Tokens de salida facturables, razonamiento incluido.';
comment on column public.ai_analyses.tokens_thinking is
  'De los de salida, cuántos se fueron en razonar. Se facturan igual.';

-- down
-- alter table public.ai_analyses
--   drop column if exists finish_reason,
--   drop column if exists tokens_in,
--   drop column if exists tokens_out,
--   drop column if exists tokens_thinking;
