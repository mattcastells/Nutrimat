# 16 — Test Plan

Pirámide objetivo: **70 % unitarios · 20 % de componente/integración · 10 % end-to-end**.
Cobertura mínima de líneas: **85 % global**, **100 % en `domain/calculations/`** (las
fórmulas no admiten huecos).

Herramientas — Flutter: `flutter_test`, `mocktail`, `golden_toolkit`, `integration_test`,
`patrol` (permisos nativos). React Native: Jest, Testing Library, Detox, MSW.
Base de datos: `pgTAP` para RLS y constraints. CI: GitHub Actions.

---

## 1. Tests unitarios

**Dominio y cálculos** — la tabla T-01…T-20 de `11-calculation-rules.md` es el set mínimo.
Además, por cada función:

- Caso feliz con el ejemplo documentado.
- Límites inferior y superior de cada parámetro.
- Un caso fuera de rango por parámetro → espera `CalculationError` con el campo correcto.
- Redondeo: valores en `.5` exactos (`round_half_up`), y verificación de que no hay
  acumulación de error en sumas de 30 ítems.
- Idempotencia: llamar dos veces con la misma entrada da el mismo resultado.

**Otros unitarios:**

| Módulo | Qué se prueba |
| --- | --- |
| `DateResolver` | `local_date` con cambios de zona horaria y horario de verano; medianoche exacta |
| `Mappers` | Row ↔ modelo ↔ DTO, ida y vuelta sin pérdida, incluyendo nulos |
| `ErrorMapper` | Cada código Postgres/HTTP → el `ApiErrorCode` correcto |
| `Validators` | Cada regla de F-01…F-14 con caso válido, límite e inválido |
| `SyncQueue` | Orden, backoff, tope de intentos, deduplicación de operaciones |
| `DuplicateDetection` | Los 5 escenarios de duplicado de RN-07 + los umbrales 0,60 y 0,85 |
| `UnitConverter` | kg↔lb, cm↔ft/in, km↔mi, ida y vuelta con tolerancia |

## 2. Tests de componentes / widgets

Por cada componente de `05-component-library.md`, cuatro tests mínimos: render por defecto,
estado de carga, estado de error, estado sin datos. Más los específicos:

| Componente | Test específico |
| --- | --- |
| `DailySummaryCard` | Con crédito 0 % **no** muestra la fila "Ajuste"; con 50 % la muestra con el valor correcto; con restantes negativas muestra "Te pasaste por N" y **no** usa `color.danger` |
| `ExerciseCaloriesEstimate` | Siempre muestra "≈"; muestra el método; con override muestra el valor original y el botón restaurar |
| `ActivityListItem` | Las acciones de swipe existen también como acciones semánticas |
| `ExerciseCreditSelector` | El toggle de desactivado fuerza 0 y deshabilita el slider |
| `ConfidenceBadge` | Incluye texto además del color |
| `AiEstimateBanner` | Es imposible llegar a "Guardar" sin que el banner se haya renderizado |
| `DuplicateActivityDialog` | No se cierra por tap fuera; sin elección queda `needs_review` |
| `EmptyState` | Cada lista de la app tiene uno registrado (test parametrizado) |
| `StepsSummaryCard` | No se renderiza cuando no hay fuente de pasos (no muestra 0) |

**Golden tests:** las 8 pantallas principales × 2 temas × 3 escalas de texto
(1,0 / 1,3 / 2,0) = 48 goldens. Se regeneran solo con aprobación explícita en el PR.

## 3. Tests de integración (app + base local + backend mockeado)

| # | Escenario |
| --- | --- |
| I-01 | Onboarding completo → perfil y objetivo persistidos → Inicio muestra el objetivo calculado |
| I-02 | Crear comida manual con 3 ítems → totales correctos → aparece en el slot correcto |
| I-03 | Analizar foto (mock) → corregir 2 ítems → guardar → `ai_result_corrected` emitido con el diff correcto |
| I-04 | Registrar actividad → recalculo al cambiar duración e intensidad → guardar → Inicio actualizado |
| I-05 | Cambiar crédito de 0 a 50 % → el día en curso recalcula `applied_calories`; un día pasado **no** cambia |
| I-06 | Override de calorías → `original_calories` conservado → restaurar devuelve el valor calculado |
| I-07 | Sincronizar salud (mock) con 6 sesiones, 1 duplicada → 5 importadas, 1 en `needs_review` |
| I-08 | Resolver duplicado quedándose con la manual → la importada queda `deleted_at` con `deletion_reason='duplicate_merge'` |
| I-09 | Registrar peso dos veces el mismo día → upsert, no dos filas |
| I-10 | Cambiar objetivo → el día de hoy usa el nuevo, los días previos conservan el viejo |
| I-11 | Historial con filtro "solo ejercicio" → no aparecen comidas |
| I-12 | Progreso con 2 puntos de peso → muestra `insufficient_data` |
| I-13 | Marcar día de descanso → los objetivos de actividad de ese día no cuentan como incumplidos |
| I-14 | Eliminar actividad → deshacer dentro de 8 s → el registro vuelve intacto |

## 4. Tests end-to-end

Sobre un proyecto Supabase `staging` real, con datos sembrados y limpiados por test.

| # | Recorrido |
| --- | --- |
| E-01 | Crear cuenta → confirmar correo (mailbox de prueba) → onboarding → primera comida |
| E-02 | Registro de comida por foto de punta a punta, con Gemini real y una foto de fixture |
| E-03 | Registro de ejercicio rápido → verificar el ajuste en Inicio y en Historial |
| E-04 | Conectar Health Connect (emulador con datos sembrados) → importar → resolver duplicado |
| E-05 | Modo avión: crear 3 registros → volver a conectar → los 3 sincronizados, sin duplicados |
| E-06 | Exportar datos → recibir el correo → el ZIP contiene todas las tablas |
| E-07 | Eliminar cuenta → login muestra el aviso de gracia → cancelar → la cuenta sigue viva |
| E-08 | Eliminar cuenta → esperar el job (forzado) → los datos ya no existen |

## 5. Tests de fórmulas (dedicado)

Archivo `test/domain/calculations_golden_test` con una **tabla de casos en JSON**
(`test/fixtures/calculation_cases.json`) que incluye los 20 casos documentados más 60
generados. El mismo JSON se usa en Flutter y en React Native, de modo que ambas
implementaciones sean verificablemente equivalentes.

Property-based testing (con `fast_check` / `glados`) para:
`0 ≤ appliedCalories ≤ estimatedCalories` para cualquier crédito en [0,100];
`adjustedTarget ≥ baseTarget`; `caloriesFromMet` monótona creciente en peso, MET y duración.

## 6. Tests offline

| # | Caso |
| --- | --- |
| O-01 | Crear comida, actividad y peso sin red → los 3 visibles con badge `pending` |
| O-02 | Reconexión → los 3 sincronizan en orden, la UI pasa a `synced` |
| O-03 | Matar la app con la cola llena → al reabrir la cola persiste y se procesa |
| O-04 | Crear el mismo registro dos veces por reintento → idempotencia, una sola fila |
| O-05 | Error 422 al sincronizar → se revierte y se avisa; error 500 → **no** se revierte |
| O-06 | Búsqueda de alimentos sin red → solo locales + banner |
| O-07 | Foto sin red → encolada, se analiza al reconectar |
| O-08 | Borrador de comida sobrevive al cierre de la app |

## 7. Tests de sincronización

| # | Caso |
| --- | --- |
| S-01 | Sync incremental: solo trae lo posterior al cursor |
| S-02 | Reenvío del mismo lote → 0 nuevas filas |
| S-03 | Registro modificado en el proveedor (`sync_hash` distinto) → se actualiza |
| S-04 | Registro editado por el usuario (`user_edited`) → se omite con `skipped_reason` |
| S-05 | Sync parcial interrumpida → el cursor avanza solo hasta lo confirmado |
| S-06 | Dos dispositivos editan la misma actividad → LWW por `updated_at`, salvo `user_edited` |
| S-07 | `TotalCaloriesBurnedRecord` presente pero sin `ActiveCalories` → se recalcula por MET |
| S-08 | Sesión de 30 s → descartada por duración mínima |

## 8. Tests de permisos

Con `patrol` (Flutter) o Detox + UI Automator / XCUITest.

| # | Caso |
| --- | --- |
| P-01 | Cámara denegada → pantalla explicativa + "Abrir configuración" + alternativa galería |
| P-02 | Cámara concedida después → el flujo continúa sin reiniciar la app |
| P-03 | Health denegado → integración en `permission_denied`, el resto de la app funciona |
| P-04 | Health parcialmente concedido → se importa lo permitido y se avisa qué falta |
| P-05 | Health Connect no instalada → `ERR_PROVIDER_UNAVAILABLE` + enlace a la tienda |
| P-06 | Permiso revocado desde Ajustes con la app abierta → estado actualizado sin crash |
| P-07 | El diálogo de justificación se muestra **antes** del diálogo del sistema, siempre |

## 9. Tests de RLS (pgTAP)

`supabase/tests/rls_test.sql` — por **cada** tabla con datos de usuario:

| # | Caso |
| --- | --- |
| R-01 | Usuario A no puede `SELECT` filas de B (0 filas, no error) |
| R-02 | Usuario A no puede `INSERT` con `user_id` de B (error 42501) |
| R-03 | Usuario A no puede `UPDATE` filas de B |
| R-04 | Nadie puede `DELETE` físico desde el cliente |
| R-05 | `meal_items` hereda la protección de `meals` |
| R-06 | `foods_cache` es legible por cualquier autenticado y no escribible |
| R-07 | `activity_types` del sistema legibles por todos; los propios solo por su dueño |
| R-08 | Sin JWT (rol `anon`) no se lee absolutamente nada de las tablas de usuario |
| R-09 | Storage: A no puede leer objetos del prefijo de B |
| R-10 | `audit_log` es de solo lectura para el dueño |

## 10. Tests de eliminación de cuenta

| # | Caso |
| --- | --- |
| D-01 | Sin reautenticación reciente → `ERR_REAUTH_REQUIRED` |
| D-02 | Confirmación textual incorrecta → no se envía |
| D-03 | Solicitud → sesiones revocadas en todos los dispositivos |
| D-04 | Login durante la gracia → aviso y opción de cancelar |
| D-05 | Cancelar → `deletion_requested_at` a null, todo intacto |
| D-06 | Job ejecutado → 0 filas en las 18 tablas y 0 objetos en los 5 buckets |
| D-07 | Queda solo el registro anonimizado en `deletion_audit` |
| D-08 | Sin conexión → no se encola, se informa |

## 11. Tests de duplicados

| # | Caso | Esperado |
| --- | --- | --- |
| U-01 | Manual 30 min caminata 11:00 + importada 32 min caminata 11:00 | score ≥ 0,85 → diálogo |
| U-02 | Mismo `(provider, external_id)` reimportado | update, no insert (índice único) |
| U-03 | Dos apps escribiendo en Health Connect con la misma sesión | score ≥ 0,85 → diálogo |
| U-04 | Entrenamiento importado + registro de pasos del mismo rato | no duplica: los pasos no crean actividad |
| U-05 | Dos sesiones distintas del mismo tipo con 3 h de diferencia | score < 0,60 → ambas |
| U-06 | Actividad editada que vuelve a importarse | omitida por RN-06 |
| U-07 | Solape parcial del 50 % | score entre 0,60 y 0,85 → marcada "Revisar", sin diálogo |
| U-08 | El usuario elige "Son distintas" | ambas quedan, se registra en `duplicate_resolutions` |

## 12. Otros

- **Rendimiento:** cold start < 1,2 s hasta el primer frame útil (medido en un Pixel 6a y un
  iPhone 12); Inicio con 20 comidas y 10 actividades renderiza en < 16 ms por frame.
- **Carga de la base:** 2 años de datos (≈ 2.200 comidas, 700 actividades) → Historial y
  Progreso responden en < 300 ms desde SQLite.
- **Accesibilidad:** ver `15-accessibility.md` §11.
- **Analítica:** `analytics_privacy_test` verifica que ningún evento emita claves prohibidas.
- **Localización:** test que falla si hay un string hardcodeado fuera de los archivos de i18n.
- **Tokens:** `tokens_in_sync_test` falla si el tema difiere de `design-tokens.json`.

## 13. Pipeline de CI

```
PR  → analyze + lint + unit + widget + golden + pgTAP     (~6 min, bloqueante)
merge a main → + integración con backend mockeado          (~12 min)
nightly      → + e2e en staging + performance + a11y suite (~35 min)
release      → + checklist manual de lector de pantalla y permisos, en 2 dispositivos reales
```

Un PR no se puede mergear con cobertura por debajo del umbral, con un golden sin aprobar ni
con un test de RLS en rojo.
