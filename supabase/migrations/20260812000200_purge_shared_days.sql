-- 36 · `shared_days` era la única tabla que no se limpiaba sola.
--
-- Es la proyección que ven los pals: una fila por persona y día. Se escribe una
-- por día de uso y **nunca se borraba ninguna**, así que crecía para siempre
-- guardando días que nadie puede mirar — la pantalla del día de un pal llega
-- hasta 7 días atrás (`palDayHistoryDays`) y las policies de agua, sueño y
-- fotos cortan en `current_date - 7`. Todo lo anterior es peso muerto: no lo
-- lee la app, no lo lee su dueño y no lo puede leer un pal.
--
-- No es una tabla grande —unas 2.500 filas por año con siete cuentas— y por eso
-- esto no es urgente. Es que no tiene por qué existir.
--
-- ## Por qué 30 días y no 7
--
-- Podría ser 8, que es exactamente lo que publica `PalPublisher`. Se deja un
-- mes de colchón por dos motivos que no dependen de nosotros: el día lo
-- calcula el **teléfono** con su zona horaria (D-09), y un reloj corrido o un
-- viaje pueden dejar una fila fechada un día más adelante de lo que este
-- servidor considera hoy. Borrar apenas pasada la ventana visible convierte
-- ese caso en un dato perdido; borrar al mes no le cuesta nada a nadie.
--
-- El resto de las purgas del proyecto usa el mismo criterio: lo borrado se va a
-- los 30 días, la auditoría a los 180.

create or replace function public.purge_shared_days()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.shared_days
   where local_date < current_date - interval '30 days';
end;
$$;

-- Va colgado del job que ya corre todas las noches a las 3, en vez de sumar
-- uno nuevo: hace lo mismo —tirar lo que ya no se puede ver— y un job más es
-- una entrada más de `cron.job` que alguien tiene que saber que existe.
create or replace function public.purge_soft_deleted()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.meals
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.activities
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.weight_logs
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.body_measurements
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.foods
   where deleted_at is not null and deleted_at < now() - interval '30 days';
  delete from public.exercise_templates
   where deleted_at is not null and deleted_at < now() - interval '30 days';

  -- La proyección de los pals no es un borrado suave: no tiene `deleted_at`
  -- ni lápida, porque no se borra un registro sino que se deja de publicar un
  -- día que ya nadie puede abrir.
  perform public.purge_shared_days();
end;
$$;

-- Se corre una vez ahora, para las filas que ya se venían acumulando. La
-- migración tiene que dejar la base en el estado que promete, no esperar a las
-- 3 de la mañana para empezar a cumplirlo.
select public.purge_shared_days();

-- down
-- create or replace function public.purge_soft_deleted() ... (sin el perform)
-- drop function if exists public.purge_shared_days();
