-- Poner al día las restricciones de valores fijos que se quedaron atrás de sus
-- enums.
--
-- Cuatro restricciones rechazaban valores que la app manda desde hace meses. No
-- se notó porque el síntoma no se parece a la causa: `RelationalSyncClient.push`
-- sube cada tabla con un solo `upsert`, así que **una fila mala tira el lote
-- entero**, y como las once tablas comparten un `try`, la excepción se lleva
-- puestas todas las que van después. El error termina en un `SyncFailed` que
-- ninguna pantalla mostraba.
--
-- El resultado: `public.meals` con cero filas mientras los teléfonos tenían
-- meses de comidas cargadas.
--
-- El orden del push es
--   profiles → goals → weight_logs → body_measurements → water_logs →
--   sleep_logs → activity_goals → foods → meals → meal_items → activities
-- así que `body_measurements` (cuarta) era la que más se llevaba puesto: a
-- quien cargó un pliegue cutáneo no le subió nada de ahí en adelante.
--
-- No se pierde nada: los datos están en los teléfonos y suben con el próximo
-- registro de cada persona.
--
-- `test/data/enum_constraints_test.dart` compara cada enum de Dart contra cada
-- `check` de estas migraciones y falla si vuelven a separarse. Es el arreglo de
-- verdad; esta migración es ponerse al día.

-- ── goals.goal_type ────────────────────────────────────────────────────────
-- Falta `gain_muscle`, el cuarto objetivo que ofrece la app desde que existen
-- los presets. Va segunda en el push: quien lo eligió no sincronizó **nada**
-- salvo su perfil.
alter table public.goals drop constraint if exists goals_type;
alter table public.goals add constraint goals_type
  check (goal_type in ('lose', 'maintain', 'gain', 'gain_muscle'));

-- ── meals.source ───────────────────────────────────────────────────────────
-- Falta `ai_text`: la estimación a partir de una descripción escrita. Se
-- distingue de `ai_photo` a propósito —no hay imagen que adjuntar— y esa
-- distinción es la que nunca llegó a la base.
alter table public.meals drop constraint if exists meals_source;
alter table public.meals add constraint meals_source
  check (source in ('manual', 'ai_photo', 'ai_text', 'barcode', 'duplicate'));

-- ── body_measurements ──────────────────────────────────────────────────────
-- La tabla aceptaba siete métricas en dos unidades; la app ofrece dieciocho en
-- cinco. Quedaron afuera los siete pliegues cutáneos, la bioimpedancia entera y
-- dos perímetros. Los rangos salen de `MeasurementMetric` (`min`/`max`), que es
-- de donde tienen que salir: la validación de la app y la de la base decían
-- cosas distintas sobre el mismo dato.
alter table public.body_measurements
  drop constraint if exists body_measurements_metric;
alter table public.body_measurements add constraint body_measurements_metric
  check (metric in (
    -- perímetros, en cm
    'arm', 'arm_flexed', 'chest', 'waist', 'hip', 'thigh', 'calf', 'neck',
    -- pliegues cutáneos, en mm
    'triceps_fold', 'subscapular_fold', 'biceps_fold', 'iliac_crest_fold',
    'supraspinale_fold', 'abdominal_fold', 'thigh_fold',
    -- composición corporal
    'body_fat_pct', 'muscle_pct', 'muscle_kg', 'visceral_fat'));

alter table public.body_measurements
  drop constraint if exists body_measurements_unit;
alter table public.body_measurements add constraint body_measurements_unit
  check (unit in ('cm', 'mm', 'pct', 'kg', 'index'));

-- El rango también asumía dos unidades: con `mm`, `kg` o `index` no matcheaba
-- ninguna rama y la fila se rechazaba aunque el valor fuera correcto.
alter table public.body_measurements
  drop constraint if exists body_measurements_range;
alter table public.body_measurements add constraint body_measurements_range
  check (
    (unit = 'cm'    and value between 10 and 300) or
    (unit = 'mm'    and value between  1 and  80) or
    (unit = 'pct'   and value between  3 and  70) or
    (unit = 'kg'    and value between  5 and 120) or
    (unit = 'index' and value between  1 and  60));
