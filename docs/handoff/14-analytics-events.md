# 14 — Analytics Events

Proveedor: PostHog (self-host o cloud UE). Wrapper: `AnalyticsService`
(`10-types-and-interfaces.ts`). Ningún componente llama al SDK directamente.

Convenciones: nombre `snake_case`, verbo en pasado; propiedades `snake_case`; sin PII;
todo evento lleva las propiedades comunes.

**Propiedades comunes (adjuntas automáticamente):**
`app_version`, `platform` (`ios|android`), `os_version`, `locale`, `theme_mode`,
`is_offline`, `session_id`, `user_id` (uuid), `days_since_signup`.

---

## 1. Eventos obligatorios

### `onboarding_started`
- **Cuándo:** al montarse `/onboarding/goal` por primera vez para el usuario.
- **Propiedades:** `entry_point` (`signup|demo`).
- **Finalidad:** denominador del embudo de onboarding.

### `onboarding_completed`
- **Cuándo:** al confirmar el paso 6 y persistir el perfil.
- **Propiedades:** `goal_type`, `target_kcal`, `target_method` (`calculated|manual`),
  `rate_kg_per_week`, `activity_level`, `credit_pct`, `duration_seconds`, `steps_skipped`.
- **Finalidad:** tasa de completitud (criterio de éxito ≥ 70 %) y distribución de
  configuraciones iniciales.

### `meal_created`
- **Cuándo:** cuando la comida se persiste local (no al sincronizar) — así se mide el acto
  del usuario aunque esté offline.
- **Propiedades:** `method` (`manual|ai_photo|barcode|duplicate|favorite`), `slot`,
  `item_count`, `total_kcal_bucket` (`0-300|300-600|600-900|900+`),
  `duration_seconds` (desde que abrió el flujo), `was_offline`.
- **Nunca:** el nombre de los alimentos ni el total exacto de kcal.

### `meal_photo_analyzed`
- **Cuándo:** al recibir una respuesta exitosa de `analyze-meal-photo`.
- **Propiedades:** `duration_ms`, `item_count`, `confidence_avg_bucket`
  (`low|medium|high`), `model`, `prompt_version`, `photo_source` (`camera|gallery`),
  `quota_remaining`.
- **Finalidad:** calidad y costo del análisis; denominador de `ai_result_corrected`.

### `ai_result_corrected`
- **Cuándo:** al guardar desde `/meal/photo/review` **si** hubo algún cambio respecto de la
  propuesta.
- **Propiedades:** `items_total`, `items_edited`, `items_removed`, `items_added`,
  `kcal_delta_pct`, `confidence_avg_bucket`, `prompt_version`.
- **Finalidad:** criterio de éxito ≤ 40 %; insumo directo para iterar el prompt.

### `food_searched`
- **Cuándo:** al recibir resultados (una vez por búsqueda estabilizada, no por tecla).
- **Propiedades:** `query_length`, `result_count`, `sources` (csv), `degraded`,
  `latency_ms`, `selected_position` (−1 si no eligió nada), `selected_source`.
- **Nunca:** el texto de la búsqueda.

### `activity_created`
- **Cuándo:** al persistir local la actividad.
- **Propiedades:** `activity_type_slug`, `mode` (`duration|distance|walk_run|strength|custom|template|duplicate`),
  `intensity`, `duration_minutes_bucket` (`<15|15-30|30-60|60+`), `estimation_method`,
  `was_overridden`, `has_distance`, `has_heart_rate`, `duration_seconds`, `was_offline`.
- **Finalidad:** criterio de éxito de tiempo de registro; uso relativo de cada modo.

### `activity_imported`
- **Cuándo:** por cada actividad efectivamente insertada durante una sincronización
  (agregado: se emite un evento por actividad, con `batch_id` compartido).
- **Propiedades:** `provider`, `activity_type_slug`, `had_calories`, `estimation_method`,
  `device_name_present`, `batch_id`.

### `activity_calories_edited`
- **Cuándo:** al guardar un override de calorías.
- **Propiedades:** `from_kcal`, `to_kcal`, `delta_pct`, `reason`
  (`watch|too_much|too_little|other|none`), `previous_method`, `source_type`.
- **Finalidad:** medir cuánto desconfía la gente de la estimación por MET.

### `weight_logged`
- **Cuándo:** al persistir el peso.
- **Propiedades:** `delta_kg_bucket` (`<-1|-1..0|0..1|>1|first`), `days_since_last`,
  `source` (`manual|imported`), `has_photo`.
- **Nunca:** el peso absoluto.

### `goal_updated`
- **Cuándo:** al persistir un objetivo nuevo.
- **Propiedades:** `goal_type`, `previous_target_kcal`, `new_target_kcal`,
  `target_method`, `rate_kg_per_week`, `was_clamped`.

### `integration_connected`
- **Cuándo:** cuando el proveedor devuelve al menos un permiso concedido.
- **Propiedades:** `provider`, `permissions_granted_count`, `permissions_denied_count`,
  `first_sync_imported`.

### `integration_sync_failed`
- **Cuándo:** cuando una sincronización termina en error.
- **Propiedades:** `provider`, `error_code`, `attempt`, `partial_imported`,
  `minutes_since_last_success`.

---

## 2. Eventos complementarios

| Evento | Cuándo | Propiedades clave |
| --- | --- | --- |
| `app_opened` | Arranque en frío | `cold_start_ms`, `pending_sync_count` |
| `sign_up_succeeded` / `sign_in_succeeded` | Auth OK | `method` |
| `auth_failed` | Auth con error | `reason` |
| `home_viewed` | Inicio visible | `date_offset`, `has_meals`, `has_activities` |
| `daily_breakdown_opened` | Sheet de desglose | `credit_pct` |
| `add_menu_action` | Acción del menú Agregar | `action` |
| `exercise_credit_changed` | Cambio de crédito | `from`, `to`, `disabled`, `entry_point` |
| `duplicate_dialog_shown` | Diálogo de duplicado | `match_score_bucket`, `provider` |
| `duplicate_resolved` | Resolución | `resolution`, `match_score_bucket` |
| `rest_day_marked` | Descanso planificado | `is_rest` |
| `history_filtered` | Filtros aplicados | `filters` |
| `progress_viewed` | Progreso | `range`, `has_enough_data` |
| `activity_goal_created` | Objetivo de actividad | `goal_type`, `target_value`, `period` |
| `offline_write_queued` | Escritura sin conexión | `entity`, `queue_size` |
| `sync_completed` | Pasada de sync OK | `pushed`, `pulled`, `duration_ms` |
| `error_shown` | Error visible al usuario | `code`, `screen`, `retryable` |
| `export_requested` | Exportación de datos | — |
| `account_deletion_requested` | Solicitud de borrado | `days_since_signup` |

---

## 3. Embudos definidos

1. **Activación:** `app_opened` → `onboarding_started` → `onboarding_completed` →
   primer `meal_created` o `activity_created`.
2. **Registro por foto:** `add_menu_action{action:'photo'}` → `meal_photo_analyzed` →
   (`ai_result_corrected`) → `meal_created{method:'ai_photo'}`.
3. **Registro de ejercicio:** `add_menu_action{action:'exercise'}` → `activity_created`.
4. **Integración:** `integration_connected` → `activity_imported` →
   (`duplicate_dialog_shown` → `duplicate_resolved`).

---

## 4. Datos que NUNCA se envían

Lista cerrada. Cualquier propiedad nueva que caiga en alguna de estas categorías se rechaza
en revisión de código (y el wrapper tiene un `assert` con la lista de claves prohibidas):

- Email, nombre, avatar, teléfono, cualquier identificador personal.
- **Peso absoluto, altura, edad exacta, sexo biológico, IMC.** (Se permiten *buckets* de
  variación, nunca el valor.)
- **Nombres de alimentos, contenido de comidas, notas, títulos de entrenamiento.**
- **Calorías totales exactas del día**, objetivo exacto — solo buckets.
  (Excepción acotada: `goal_updated` sí envía los objetivos porque son configuración del
  producto, no una medición corporal; y `activity_calories_edited` envía kcal de una
  actividad porque es la señal central para evaluar la fórmula.)
- Fotos, rutas de fotos, hashes de fotos.
- Frecuencia cardíaca, pasos absolutos, datos crudos de Health Connect.
- Ubicación, IP precisa (se trunca en el proveedor), identificadores publicitarios.
- Tokens, claves, cabeceras de autorización.

## 5. Consentimiento y control

- Al primer arranque, la analítica está **activa solo para eventos de producto** y sin
  cookies de terceros; no se hace tracking publicitario.
- `/settings/privacy` incluye un toggle "Compartir estadísticas de uso anónimas" que, al
  desactivarse, llama a `AnalyticsService.reset()` y deja de emitir. Los eventos ya enviados
  se eliminan a pedido vía el flujo de exportación/borrado.
- En la UE se muestra un diálogo de consentimiento previo (fase 15 del roadmap).
- `AnalyticsService.reset()` se llama en cada cierre de sesión.

## 6. Implementación

```dart
// Un único punto de emisión. El assert impide filtrar datos prohibidos.
class PostHogAnalyticsService implements AnalyticsService {
  static const _forbidden = {
    'email','name','weight_kg','height_cm','age','bmi','food_name','meal_name',
    'notes','photo_path','heart_rate','steps','latitude','longitude','token',
  };

  @override
  void track(String event, [Map<String, Object?>? properties]) {
    assert(properties == null ||
        properties.keys.every((k) => !_forbidden.contains(k)),
        'Propiedad prohibida en $event');
    if (!_consentGiven) return;
    _client.capture(eventName: event, properties: {..._common(), ...?properties});
  }
}
```

Test obligatorio (`analytics_privacy_test`): recorre el catálogo de eventos emitidos en los
tests de integración y falla si aparece cualquier clave de la lista prohibida.
