# Panel de seguimiento

La web que usa un profesional —una nutricionista— para ver el día a día de
quien le dio acceso desde la app.

## Lo que hay que entender antes de tocarlo

**No hay service-role key en este proyecto, y no puede haberla.** Esa clave
saltea RLS por completo: en un frontend, o en una variable de entorno de Vercel
que cualquiera con acceso al proyecto puede leer, es una llave maestra a los
datos de todos. El panel entra con la **publishable key** y la sesión de quien
mira, y lo que puede ver lo decide Postgres a partir de `care_grants`.

Eso significa que **este código no es lo que protege los datos**. Si mañana una
consulta de acá pide de más, la base devuelve vacío. Las garantías viven en
`supabase/migrations/20260803000100_care_access.sql` y están probadas en
`supabase/tests/care_access_test.sql`, que corre en CI contra una base limpia.

El panel es de **solo lectura**. No hay una sola política de escritura para el
profesional, así que no es una convención de la interfaz: es que la base no
tiene por dónde.

## Cómo se conceden los accesos

1. La profesional entra al panel y ve su código (`NT-XXXXXX`) arriba de todo.
   Lo crea `ensure_care_code` la primera vez y después devuelve siempre el
   mismo.
2. El paciente lo carga en la app, en **Perfil → Mi nutricionista**, y elige qué
   categorías prende: comidas, fotos, peso y medidas, actividad/agua/sueño.
3. El paciente puede cambiar qué ve o cortar el acceso cuando quiera, desde la
   misma pantalla.

Una categoría apagada no es lo mismo que un día sin registros, y el panel lo
dice: donde no hay permiso muestra "no está compartido" y no un vacío.

## Correrlo

```bash
cd backoffice
npm install
npm run dev
```

Y abrís **http://localhost:3000**.

### La primera vez: el `.env.local`

Hacen falta dos variables. Son **las mismas dos que ya usa la app** en
`env/local.json`, así que en vez de copiarlas a mano conviene generarlas desde
ahí — un valor tipeado mal da un error de login que no dice que el problema es
la clave:

```bash
# desde backoffice/
URL=$(node -p "require('../env/local.json').SUPABASE_URL")
KEY=$(node -p "require('../env/local.json').SUPABASE_PUBLISHABLE_KEY")
printf 'NEXT_PUBLIC_SUPABASE_URL=%s\nNEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=%s\n' "$URL" "$KEY" > .env.local
```

Si no tenés `env/local.json`, salen del dashboard → Settings → API Keys:

| Variable | Qué va |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | La Project URL |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | La publishable key (`sb_publishable_…`) |

Las dos son públicas por diseño: viajan al navegador igual que en la app.
`.env.local` está en `.gitignore`.

### Antes de subir un cambio

```bash
npm run typecheck
npm run build
```

⚠️ **No corras `npm run build` con `npm run dev` levantado.** Los dos escriben en
`.next/`, y el build de producción le pisa los chunks al de desarrollo. El
síntoma no dice nada de eso: la página muere con un
`Runtime TypeError: a[d] is not a function` adentro del runtime de webpack, que
parece un bug del código y no lo es. Si pasa:

```bash
rm -rf .next && npm run dev
```

y recargá el navegador **forzado** (`Ctrl+Shift+R`): la pestaña se queda con el
bundle roto en memoria aunque el servidor ya esté sano.

### Si entrás y no ves ningún paciente

Es lo esperado hasta que alguien te dé acceso. El circuito completo es:

1. Entrás al panel → arriba aparece tu código `NT-XXXXXX`
2. El paciente lo carga en la app: **Perfil → Mi nutricionista → Dar acceso con
   un código**
3. Recargás el panel

Si la cuenta es nueva y **no puede entrar**, fijate que esté confirmada:
Authentication → Users. Una cuenta creada desde el dashboard nace confirmada;
una creada por la API queda esperando el mail de verificación.

## Desplegarlo en Vercel

El plan gratuito alcanza. Al importar el repo hay que apuntar **Root Directory**
a `backoffice/`, porque el repositorio es el de la app y este proyecto vive en
una subcarpeta. Las dos variables de arriba se cargan en Project Settings →
Environment Variables.

Después del primer deploy, agregá la URL de Vercel en Supabase → Authentication
→ URL Configuration → Redirect URLs. Sin eso el login entra pero la sesión no
vuelve a la app.

## El look and feel

Los tokens están copiados de `docs/handoff/design-tokens.json` a variables CSS
en `app/globals.css`. Se copian y no se importan porque el JSON vive en el repo
de la app y una build de Vercel con Root Directory en `backoffice/` no lo ve. Si
los tokens cambian, se actualizan ahí.

**Una cosa sobre los gráficos.** La paleta de Nutrimat es pastel y toda en una
banda de luminosidad estrecha: los tres colores de macros (`#9184d9`, `#7fa8d9`,
`#d9b46a`) no se distinguen lo suficiente entre sí ni siquiera con visión de
color normal —ΔE 9.6 entre proteínas y carbohidratos, cuando el piso es 15—.
Por eso acá **no hay ningún gráfico que dependa de distinguir tres colores de
marca**: los de peso y calorías son de una serie sola, y los macros van como
columnas con su nombre. Es lo que permite mantener la identidad sin publicar un
gráfico que no se puede leer.
