# Nutrimat

Aplicación móvil de registro de **alimentación, actividad física y peso corporal**, con una
idea central: mostrar el cálculo completo del día en vez de un único número mágico, y no
presentar nunca una estimación como si fuera una medición.

Este repositorio contiene **la especificación completa de producto, el prototipo
de alta fidelidad y la aplicación Flutter** construida a partir de esa
especificación.

## Contenido

| Ruta | Qué es |
| --- | --- |
| `lib/` · `android/` · `test/` | **La app.** Flutter para Android, en modo `mock`: corre entera contra la base local, sin backend. Ver [`docs/estado-de-la-app.md`](./docs/estado-de-la-app.md). |
| [`docs/handoff/`](./docs/handoff/00-index.md) | **El handoff de desarrollo.** 20 documentos + tipos, tokens y catálogos en formato código. Es la fuente de verdad funcional. |
| `Nutrimat.dc.html` | Prototipo navegable de alta fidelidad (abrir en el navegador). Fuente de verdad visual. |
| `_ds/nocturne-.../` | Sistema de diseño Nocturne: tokens y componentes CSS. |
| `Nutrimat Logo.dc.html` | Identidad: marca, ícono adaptativo de Android, monocromo, logotipo y reglas de uso. |
| `assets/brand/` | PNG exportados: `icon-512`, `adaptive-foreground`, `adaptive-background`, `monochrome`, `wordmark`. |
| `uploads/` | El brief original en PDF. |

## Correr la app

```bash
flutter pub get
flutter emulators --launch nutrimat   # o conectá el teléfono por USB
flutter run
flutter test                          # cálculos, widgets y sincronía de tokens
```

Arranca sin variables de entorno: siembra la base local con un día cargado y 30
días de historial. Lo que todavía está simulado y lo que falta conectar está en
[`docs/estado-de-la-app.md`](./docs/estado-de-la-app.md).

## Por dónde empezar

1. [`docs/handoff/00-index.md`](./docs/handoff/00-index.md) — índice y convenciones.
2. [`docs/handoff/01-product-requirements.md`](./docs/handoff/01-product-requirements.md) — qué es el producto y su alcance.
3. [`docs/handoff/21-motion-and-loading.md`](./docs/handoff/21-motion-and-loading.md) — movimiento, spinners y estados de carga.
4. [`docs/handoff/decisions.md`](./docs/handoff/decisions.md) — las 20 decisiones tomadas, qué está simulado y **los pasos exactos para empezar a desarrollar**.

## El prototipo

Abrí `Nutrimat.dc.html` en cualquier navegador. Las fórmulas MET, el crédito de ejercicio y
el balance diario están **implementados de verdad**: cambiar el tipo de actividad, la
duración, la intensidad o el porcentaje de crédito recalcula todo en vivo. Los atajos de
abajo saltan a cada pantalla.

Lo que simula (autenticación, persistencia, catálogos de alimentos, análisis de foto,
sincronización de salud) está listado en `docs/handoff/decisions.md` §2.

## Stack previsto

Flutter (implementación primaria) o React Native, sobre Supabase — Postgres con RLS, Auth,
Storage y Edge Functions. Gemini para el análisis de fotos, USDA FoodData Central y Open
Food Facts para el catálogo nutricional, HealthKit y Health Connect para importar actividad.
Ver `docs/handoff/12-external-integrations.md` y `19-project-structure.md`.

## Desarrollo

El handoff está escrito para que un equipo — o una IA desarrolladora — pueda implementar la
app sin acceso a la conversación original:

> Desarrollá la aplicación siguiendo exactamente el handoff que está en `docs/handoff/`.
> Empezá por `00-index.md`. Respetá las decisiones de `decisions.md` sin reinterpretarlas.
> Implementá primero `domain/calculations/` con sus tests (`11-calculation-rules.md` §20) y
> recién después la interfaz.

## Para publicarlo en GitHub

```bash
git init
git add .
git commit -m "Handoff completo + prototipo de alta fidelidad"
gh repo create nutrimat --private --source=. --push
```
