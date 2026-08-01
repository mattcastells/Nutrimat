# Backend Supabase

Proyecto `ifincvqdsotorvmwzpos`, región **sa-east-1** (la que prescribe
`decisions.md` §4 paso 2). Postgres 17.6.

## Estado

| Qué | Resultado |
| --- | --- |
| Migraciones aplicadas | 32 de 32 |
| Tablas | 26 |
| Tablas con RLS activo | **26 de 26** (ninguna sin RLS) |
| Políticas | 83, más 5 de Storage |
| Buckets de Storage | 4 (3 de fotos + `backups`), privados, con política por prefijo |
| `activity_types` sembrados | 15 (D-06) |
| RPC | `request_pal` y `check_rate_limit` (los únicos que se llaman); `create_meal_with_items` y `get_daily_summary` existen y no los usa nadie |
| pg_cron | habilitado, con los 4 jobs de `08-supabase-plan.md` §7 (ejecutables solo por `pg_cron`, no por `authenticated`) |
| Pals | vínculo por código; `shared_days` es la superficie compartida, con fotos/agua/sueño/detalle de ejercicio opcionales por perfil |
| Suite pgTAP | **85 casos en verde** (22 RLS + 9 Storage + 19 Pals + 8 hardening + 8 privacidad de Pals + 10 consentimiento de Pals + 7 contrato de sync), en local y contra el proyecto |

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

`supabase db push --linked` **no funciona desde esta máquina**: resuelve el host
directo (`db.<ref>.supabase.co`), que es IPv6 puro, y acá no hay IPv6. Pero
pasándole el *session pooler* a mano con `--db-url` anda perfecto, sin Docker y
sin `supabase login`. El pooler es IPv4:

```bash
set -a; . ./supabase/.env.local; set +a
# La contraseña va dentro de una URL: hay que escaparla.
PWENC=$(node -e 'process.stdout.write(encodeURIComponent(String(process.env.SUPABASE_DB_PASSWORD)))')
DBURL="postgresql://postgres.ifincvqdsotorvmwzpos:${PWENC}@aws-0-sa-east-1.pooler.supabase.com:5432/postgres"

supabase db push --db-url "$DBURL" --dry-run   # qué se aplicaría
supabase db push --db-url "$DBURL"             # aplicarlo
supabase migration list --db-url "$DBURL"      # verificar
```

Solo se aplican las migraciones pendientes, y cada una queda registrada en
`supabase_migrations.schema_migrations`, así que el CLI queda en sincronía.

> Sin Docker corriendo, `db push` tira varios *warnings* de
> `failed to connect to the docker API`. Son del caché opcional del catálogo
> (`pg-delta`), no de la migración: si el resumen final dice
> `"migrations":[...]` sin error, se aplicó. Confirmalo con `migration list`.

> La ruta larga —`docker exec` contra el contenedor local para usar su `psql`—
> sigue sirviendo si hace falta correr SQL suelto, pero para migraciones no
> hace falta.

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

## Desplegar una Edge Function

⚠️ **Ni el release de la app ni `db push` tocan las funciones.** Cambiar
`supabase/functions/**` y publicar una versión de la app deja el código nuevo
en el repositorio y el viejo corriendo en el servidor. Hay que desplegarlo
aparte:

```bash
supabase functions deploy analyze-meal-photo --project-ref ifincvqdsotorvmwzpos
supabase functions deploy analyze-meal-text  --project-ref ifincvqdsotorvmwzpos
supabase functions deploy suggest-meals      --project-ref ifincvqdsotorvmwzpos
supabase functions deploy food-search        --project-ref ifincvqdsotorvmwzpos
```

Las cuatro funciones:

| Función | Qué hace | Secreto que necesita |
| --- | --- | --- |
| `analyze-meal-photo` | Estima los ítems de una foto | `GEMINI_API_KEY` |
| `analyze-meal-text` | Lo mismo desde una descripción escrita | `GEMINI_API_KEY` |
| `suggest-meals` | Tres platos que entran en las calorías que quedan | `GEMINI_API_KEY` |
| `food-search` | Alimentos genéricos de USDA | `USDA_API_KEY` |

Las **tres** de Gemini comparten `_shared/estimation.ts`: la llamada al modelo,
el manejo de errores y la cuota diaria de 20, que es una sola para las tres — las
tres gastan lo mismo del proveedor y darle cupo propio a cada una sería
triplicarlo por la ventana. Si tocás el módulo compartido, **desplegá las tres**:
el bundler copia el módulo dentro de cada función, así que las que no subas
quedan con la versión vieja.

`suggest-meals` no comparte la validación, porque su contrato de salida es otro
—tres opciones, cada una con ingredientes y receta— y porque tiene una regla
propia: **ninguna opción puede pasarse del presupuesto**. Eso se comprueba
sumando de este lado, no se le cree al modelo. Tampoco escribe en `ai_analyses`:
esa tabla registra estimaciones de lo que alguien *comió*.

La clave de USDA se saca gratis en <https://api.data.gov/signup> (el dato es de
dominio público, CC0). El límite es de 1.000 consultas por hora por IP.

A diferencia de las migraciones, esto **sí** necesita autenticarse con la
plataforma: `supabase login` (abre el navegador) o un *personal access token*
en `SUPABASE_ACCESS_TOKEN`. Hoy esta máquina no tiene ninguno de los dos, así
que el despliegue es manual.

Los secretos de la función van por separado y tampoco viajan con el código:

```bash
supabase secrets set GEMINI_API_KEY=... --project-ref ifincvqdsotorvmwzpos
supabase secrets set USDA_API_KEY=...   --project-ref ifincvqdsotorvmwzpos
```

Sin `USDA_API_KEY` la función contesta 503 y la búsqueda sigue andando con Open
Food Facts y con la tabla argentina: se pierde lo genérico, no la pantalla.

## Lo que falta

1. La `anon key` en `.env.local` para conectar la app.
2. Buckets de Storage (`08-supabase-plan.md` §3) y sus políticas por prefijo.
3. Edge Functions (§4) y sus secretos (§5).
4. Proyectos `staging` y `prod` con las mismas migraciones.
