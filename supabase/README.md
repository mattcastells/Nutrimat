# Backend Supabase

Proyecto `ifincvqdsotorvmwzpos`, región **sa-east-1** (la que prescribe
`decisions.md` §4 paso 2). Postgres 17.6.

## Estado

| Qué | Resultado |
| --- | --- |
| Migraciones aplicadas | 18 de 18 |
| Tablas | 24 |
| Tablas con RLS activo | **24 de 24** (ninguna sin RLS) |
| Políticas | 78 |
| Buckets de Storage | 3, privados, con política por prefijo `{user_id}/` |
| `activity_types` sembrados | 15 (D-06) |
| RPC | `create_meal_with_items`, `get_daily_summary` |
| pg_cron | habilitado, con los 4 jobs de `08-supabase-plan.md` §7 |
| Suite pgTAP | **31 casos en verde** (22 de RLS + 9 de Storage), en local y contra el proyecto |

## Cómo trabajar

```bash
supabase start          # stack local en Docker (Studio en :54323)
supabase db reset       # reaplica todas las migraciones en local
supabase test db        # corre supabase/tests/*.sql con pgTAP
supabase stop           # apaga el stack local
```

Las credenciales van en `supabase/.env.local` (fuera del repo). Se crea
copiando `.env.local.example`.

## Aplicar migraciones al proyecto remoto

`supabase db push` **no funciona desde esta máquina**: el host directo
(`db.<ref>.supabase.co`) es IPv6 puro y acá no hay IPv6, y el CLI no logra
conectar por el pooler. El camino que sí anda es psql contra el *session
pooler*, que es IPv4:

```bash
set -a; . ./supabase/.env.local; set +a
C=supabase_db_Nutrimat__especificaciones_completas   # contenedor local, trae psql
H=aws-0-sa-east-1.pooler.supabase.com
U=postgres.ifincvqdsotorvmwzpos

docker exec -i -e PGPASSWORD="$SUPABASE_DB_PASSWORD" $C \
  psql -h $H -p 5432 -U $U -d postgres -v ON_ERROR_STOP=1 -f - < supabase/migrations/XXXX.sql
```

Cada migración aplicada se registra en `supabase_migrations.schema_migrations`,
igual que haría `db push`, así que el CLI queda en sincronía.

> Si en el futuro hay IPv6 disponible, o se agrega un *personal access token*
> con `supabase login`, `supabase db push` vuelve a ser el camino corto.

## Lo que hay que saber del esquema

- **RLS no alcanza sola.** Las políticas filtran filas, pero antes hace falta
  `GRANT` sobre la tabla: sin eso `authenticated` recibe *permission denied* y
  las políticas ni se evalúan. Los grants están en la migración 14, junto con
  las políticas, porque son la misma capa.
- **El borrado físico está prohibido** en las tablas de contenido: policy
  `for delete using (false)` + trigger `guard_hard_delete`. La app borra con
  `deleted_at` y el job diario purga lo de más de 30 días.
- **La base tiene la última palabra en el cálculo**: `applied_calories` lo
  recalcula un trigger a partir de `estimated_calories` y del porcentaje
  congelado (RN-02, D-05), y los totales de la comida los mantiene
  `recalc_meal_totals` (D-11). Si el cliente manda otro número, la base lo
  corrige.
- **`pgtap` quedó instalado** en el proyecto por la suite de tests. Es solo el
  framework de aserciones; si molesta, `drop extension pgtap`.

## Lo que falta

1. La `anon key` en `.env.local` para conectar la app.
2. Buckets de Storage (`08-supabase-plan.md` §3) y sus políticas por prefijo.
3. Edge Functions (§4) y sus secretos (§5).
4. Proyectos `staging` y `prod` con las mismas migraciones.
