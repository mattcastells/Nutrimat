# 18 — Implementation Roadmap

15 fases. Cada una declara **dependencias, entregables, riesgos y definición de terminado
(DoD)**. La estimación es de referencia para un equipo de 2 personas (1 móvil + 1
full-stack); ajustar según el equipo real.

DoD transversal (aplica a todas las fases, además de lo específico): código revisado,
tests de la fase en verde, cobertura por encima del umbral, sin literales de color ni
strings hardcodeados, documentación actualizada si cambió una decisión.

---

## Fase 1 — Fundación  · ~1 semana

**Dependencias:** ninguna.

**Entregables**
- Repositorio, ramas (`main` protegida, `feat/*`), convención de commits, plantilla de PR.
- Proyecto Flutter (o RN) con la estructura de `19-project-structure.md`.
- Pipeline de tokens: `design-tokens.json` → `tokens.dart` / `tokens.ts`; test de sincronía.
- Tema claro y oscuro completos; lint que prohíbe hex fuera de `theme/`.
- i18n con `es` y el andamiaje para agregar idiomas; lint contra strings hardcodeados.
- CI: analyze, lint, test, cobertura.
- Sentry integrado con `sendDefaultPii = false`.

**Riesgos:** sobre-ingeniería del generador de tokens. *Mitigación:* un script simple, no
Style Dictionary completo, hasta que haga falta.

**DoD:** la app arranca en ambos temas con una pantalla de prueba que muestra el 100 % de
los tokens; el CI corre en < 6 min.

---

## Fase 2 — Diseño y navegación  · ~1,5 semanas

**Dependencias:** 1.

**Entregables**
- Router con todas las rutas de `02-information-architecture.md` §2, con parámetros tipados.
- Shell autenticado: `BottomTabBar` + FAB, stacks independientes por tab.
- Todas las pantallas creadas como esqueletos navegables con datos falsos en memoria.
- Componentes de sistema de `05-component-library.md` §4 implementados y con golden tests.
- `sheet.add` y `sheet.activity_add` funcionando, con la regla de reemplazo de contenido.

**Riesgos:** el back de Android en stacks anidados. *Mitigación:* test de integración
específico del comportamiento descrito en IA §4.

**DoD:** se puede recorrer toda la app sin backend; ningún callejón sin salida; todos los
estados vacíos presentes.

---

## Fase 3 — Autenticación  · ~1 semana

**Dependencias:** 1, 2.

**Entregables**
- Supabase Auth: registro, login, recuperación, confirmación por correo, deep link de callback.
- Almacenamiento seguro de sesión, refresh automático, expulsión limpia al fallar el refresh.
- Modo demo local (D-15) y su migración a cuenta real.
- Migraciones `profiles` + trigger de alta; RLS de `profiles`.

**Riesgos:** deep link de confirmación mal configurado. *Mitigación:* probar en dispositivo
real antes de cerrar la fase.

**DoD:** F-01 completo en iOS y Android; los tests D-01…D-03 de auth en verde.

---

## Fase 4 — Perfil y objetivos  · ~1 semana

**Dependencias:** 3.

**Entregables**
- Onboarding de 6 pasos (F-02).
- `domain/calculations`: BMR, TDEE, objetivo, macros, IMC — **con los tests T-01…T-05 y
  T-14, T-20 pasando** antes de conectar la UI.
- Migraciones `goals` con la restricción de exclusión; `GoalService.setGoal`.
- `/settings/exercise-credit` con el copy exacto y el efecto de F-13.
- Pantalla de perfil corporal.

**Riesgos:** el clamp de RN-12 aplicado en el lugar equivocado. *Mitigación:* el clamp vive
en la función de dominio, no en la UI; test T-05.

**DoD:** AC-01 y AC-04 (parte de configuración) verificados.

---

## Fase 5 — Registro de comidas  · ~2 semanas

**Dependencias:** 4.

**Entregables**
- Migraciones `foods`, `meals`, `meal_items`, triggers de totales y de recientes.
- `/meal/new`, `/food/new`, `/food/:id`, `sheet.portion`.
- Inicio con `DailySummaryCard` real (sin actividad todavía) y secciones de comidas.
- RPC `create_meal_with_items` idempotente; `get_daily_summary`.
- Favoritos y recientes de alimentos.

**Riesgos:** desnormalización de totales fuera de sincronía. *Mitigación:* el trigger es la
única vía de escritura de los totales; test I-02.

**DoD:** F-03 y F-07 completos; AC-05 (transparencia) parcialmente verificable.

---

## Fase 6 — Integración nutricional  · ~1 semana

**Dependencias:** 5.

**Entregables**
- Edge Functions `food-search`, `food-detail`, `barcode-lookup`.
- `foods_cache` + política de TTL; fusión y deduplicación de resultados.
- `/food/search` con pestañas, debounce, estados `degraded` y offline.
- Mocks de USDA y OFF para desarrollo y tests.

**Riesgos:** rate limit de USDA en desarrollo. *Mitigación:* mocks por defecto en `dev`;
clave real solo en `staging`.

**DoD:** F-04 completo, incluidos los cuatro estados de error.

---

## Fase 7 — Análisis mediante IA  · ~1,5 semanas

**Dependencias:** 5, 6.

**Entregables**
- Bucket `meal-photos` con políticas; captura, compresión y subida.
- Edge Function `analyze-meal-photo` con prompt versionado, `responseSchema`, validación,
  cuota y cache por hash.
- `/meal/photo/capture`, `/analyzing`, `/review` con todos sus estados.
- `ai_analyses` con `corrections`; evento `ai_result_corrected`.
- Set de 40 fotos de referencia y script de evaluación del error medio de kcal.

**Riesgos:** costo y variabilidad del modelo (R-01). *Mitigación:* cuota, compresión, cache,
y el set de referencia como control de regresión al cambiar de prompt o modelo.

**DoD:** F-05 y F-06 completos; AC-10 verificado; error medio de kcal del set de referencia
documentado como línea de base.

---

## Fase 8 — Registro de actividad  ★ · ~2 semanas

**Dependencias:** 4, 5.

**Entregables**
- Migraciones `activity_types` (+ seed desde `met-catalog.json`), `activities`,
  `exercise_templates`, `rest_days`; trigger `recalc_applied_calories`.
- `ExerciseCalculationService` completo con **T-06 a T-12 y T-15 en verde antes de la UI**.
- `/activity/new` en sus 5 modos, `/activity/search`, `/activity/:id`, plantillas,
  favoritos, duplicar, `dialog.override_calories`.
- `ActivitySummaryCard` y `ActivityListItem` integrados en Inicio.
- Ajuste por ejercicio aplicado en `get_daily_summary` y en `sheet.daily_breakdown`.

**Riesgos:** el porcentaje de crédito aplicado en momentos inconsistentes. *Mitigación:* se
congela en la fila y se recalcula solo hoy en adelante (D-05); test I-05.

**DoD:** AC-02, AC-03, AC-04, AC-06 y AC-07 verificados.

---

## Fase 9 — Historial  · ~1 semana

**Dependencias:** 5, 8.

**Entregables**
- RPC `get_history` con filtros y paginación; `/history` y `/history/:date`.
- `sheet.filters`; persistencia local de los filtros elegidos.
- Edición de registros desde el detalle del día.

**Riesgos:** rendimiento con 2 años de datos. *Mitigación:* índices de `07-data-model.md` §3
y el test de carga de `16-test-plan.md` §12.

**DoD:** F-12 completo; AC-11 verificado.

---

## Fase 10 — Progreso  · ~1,5 semanas

**Dependencias:** 8, 9.

**Entregables**
- RPC `get_progress`; `/progress`, `/progress/activity`, `/progress/measurements`,
  `/progress/goals`.
- Gráficos de peso, calorías, actividad por día y por categoría, con marcadores
  diferenciados y alternativa en tabla.
- `activity_goals` + `ActivityGoalCard`; mensajes de consistencia neutrales.
- Registro de peso y de medidas.

**Riesgos:** gráficos inaccesibles. *Mitigación:* la alternativa textual y la tabla son
parte del entregable, no un extra.

**DoD:** AC-12, AC-13, AC-14 verificados; `insufficient_data` funcionando.

---

## Fase 11 — Integraciones de salud  · ~2 semanas

**Dependencias:** 8.

**Entregables**
- Migraciones `health_integrations`, `sync_records`, `duplicate_resolutions`.
- Adaptadores nativos de Health Connect con el mapeo de tipos documentado.
- `HealthSyncService` incremental con ancla/cursor; Edge Function `sync-health`.
- `DuplicateDetectionService` con el algoritmo de `11-calculation-rules.md` §12.
- `/settings/integrations`, `HealthIntegrationCard`, `DuplicateActivityDialog`,
  `dialog.permission_rationale`.

**Riesgos:** comportamiento distinto entre dispositivos y versiones de SO (R-02).
*Mitigación:* probar en 2 iPhones y 2 Android reales; `FakeHealthProvider` para CI.

**DoD:** F-09 completo; AC-08 y AC-09 verificados; los tests P-01…P-07 y U-01…U-08 en verde.

---

## Fase 12 — Offline  · ~1,5 semanas

**Dependencias:** 5, 8 (se diseña desde la fase 1, se completa acá).

**Entregables**
- Base local completa (Drift/WatermelonDB) con el esquema espejo.
- `SyncQueueService` con orden, backoff, tope e idempotencia.
- Escrituras optimistas con la política de reversión de `13-state-management.md` §7.
- `OfflineBanner`, `SyncStatusBadge`, pantalla "Registros sin sincronizar", `conflict_log`.
- Borradores persistidos de comida, revisión de IA y actividad.

**Riesgos:** duplicados al reintentar. *Mitigación:* uuid en cliente + idempotencia en todos
los endpoints de escritura; tests O-01…O-08.

**DoD:** AC-15 verificado; el escenario E-05 pasa en dispositivo real.

---

## Fase 13 — Seguridad y privacidad  · ~1 semana

**Dependencias:** 3–12.

**Entregables**
- RLS de **todas** las tablas + suite pgTAP R-01…R-10.
- Políticas de Storage por prefijo de usuario; URLs firmadas.
- `export-user-data` y `delete-account` con el período de gracia y los jobs de cron.
- Toggle de analítica y revisión del catálogo de eventos contra la lista prohibida.
- Revisión de secretos: nada sensible en el bundle del cliente.

**Riesgos:** una tabla sin RLS. *Mitigación:* test que enumera `pg_tables` y falla si alguna
tabla de usuario no tiene RLS activada.

**DoD:** AC-17 verificado; D-01…D-08 en verde; auditoría de secretos documentada.

---

## Fase 14 — Testing y accesibilidad  · ~1,5 semanas

**Dependencias:** 1–13.

**Entregables**
- Cobertura al umbral; 48 goldens; suite e2e nightly.
- Auditoría completa de `15-accessibility.md` con los 14 flujos recorridos con VoiceOver y
  TalkBack, y la lista de defectos cerrada.
- Pruebas de rendimiento (cold start, frames, carga de base).
- Pruebas con 2 años de datos sembrados.

**Riesgos:** defectos de accesibilidad estructurales descubiertos tarde. *Mitigación:* los
tests de semántica corren desde la fase 2, no acá.

**DoD:** AC-18 verificado; ningún defecto de accesibilidad bloqueante abierto.

---

## Fase 15 — Publicación  · ~1,5 semanas

**Dependencias:** todas.

**Entregables**
- Fichas de App Store y Play Store, capturas, textos, clasificación por edad.
- Declaraciones obligatorias: *App Privacy* (iOS) y *Data safety* (Play), incluida la
  declaración de uso de datos de salud y del procesamiento de fotos con IA.
- Cumplimiento de la política de Health Connect (política de privacidad accesible desde el
  diálogo de permisos).
- Consentimiento de analítica para la UE.
- Universal Links / App Links con dominio verificado.
- Beta con TestFlight y pista interna de Play; canal de feedback.
- Monitoreo: alertas de crash rate, de errores de Edge Function y de cuota de Gemini.
- Runbook de incidentes y prueba de restauración de backup.

**Riesgos:** rechazo de la tienda por la declaración de datos de salud o por el uso de IA.
*Mitigación:* preparar las declaraciones en la fase 13, no en la 15; textos revisados.

**DoD:** build en beta cerrada instalada por 10 personas, con al menos 3 días de uso real y
los criterios de éxito del PRD instrumentados y visibles en el panel.

---

## Ruta crítica y paralelización

```
1 → 2 → 3 → 4 → 5 → 8 → 11 → 13 → 14 → 15      (ruta crítica)
              ├→ 6 → 7                          (nutrición e IA, en paralelo a 8)
              └→ 9 → 10                         (historial y progreso)
        12 se desarrolla junto a 5 y 8, se cierra después de 8
```

Duración estimada en serie: ~20 semanas. Con las dos ramas en paralelo y 2 personas:
**~14–15 semanas** hasta la beta.

## Hitos demostrables

| Hito | Al terminar | Qué se puede mostrar |
| --- | --- | --- |
| H1 | Fase 2 | La app entera navegable, sin datos |
| H2 | Fase 5 | Registrar comida real y ver el resumen del día |
| H3 | Fase 8 | El producto completo en su idea central: comida + ejercicio + balance transparente |
| H4 | Fase 11 | Importación de salud con resolución de duplicados |
| H5 | Fase 15 | Beta pública |
