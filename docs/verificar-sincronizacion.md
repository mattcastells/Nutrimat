# Queries para verificar la sincronización

## 1. Antes de la migración: confirmar el alcance

```sql
select 'profiles'          as tabla, count(*) from public.profiles
union all select 'goals',            count(*) from public.goals
union all select 'weight_logs',      count(*) from public.weight_logs
union all select 'body_measurements',count(*) from public.body_measurements
union all select 'water_logs',       count(*) from public.water_logs
union all select 'sleep_logs',       count(*) from public.sleep_logs
union all select 'activity_goals',   count(*) from public.activity_goals
union all select 'foods',            count(*) from public.foods
union all select 'meals',            count(*) from public.meals
union all select 'meal_items',       count(*) from public.meal_items
union all select 'activities',       count(*) from public.activities;
```

Están en el mismo orden en que las sube `RelationalSyncClient.push`. La primera
que dé 0 es donde se cortaba; todo lo de abajo tiene que dar 0 también.

## 2. Después de la migración: que la base acepte lo que antes rechazaba

```sql
begin;
insert into public.body_measurements (id, user_id, metric, value, unit, local_date)
select gen_random_uuid(), id, 'triceps_fold', 12.5, 'mm', current_date
from public.profiles limit 1;
rollback;
```

Sin error = la restricción quedó bien. El `rollback` deja todo como estaba.

## 3. Después de que alguien registre algo desde la app

Los mismos conteos del punto 1. Tienen que dejar de dar 0.
