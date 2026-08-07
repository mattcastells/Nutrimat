-- `goals.target_method` acepta `ai`: el objetivo que propuso el modelo y la
-- persona aceptó en el alta guiada (S-05).
--
-- Es un tercer valor y no un alias de los dos que había, a propósito. No es
-- `calculated` —no salió de Mifflin-St Jeor sino de un modelo— ni es `manual`
-- —nadie lo escribió—, y de dónde viene un número es parte del número (RN-03).
-- Sin este valor, el único registro de que un objetivo no coincide con su
-- fórmula sería ninguno.
--
-- Sin esta migración el síntoma no se parece a la causa: `push` sube cada tabla
-- con un solo `upsert`, así que la fila rechazada se lleva puesto el lote de
-- `goals` entero y todas las tablas que van después. Es exactamente lo que pasó
-- con `gain_muscle` (ver 20260801002600). `test/data/enum_constraints_test.dart`
-- compara este `check` contra el enum de Dart y falla si vuelven a separarse.

alter table public.goals drop constraint if exists goals_method;
alter table public.goals add constraint goals_method
  check (target_method in ('calculated', 'manual', 'ai'));
