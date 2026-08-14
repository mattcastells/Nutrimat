# 09 — API Contracts

Dos superficies:

- **PostgREST** (`/rest/v1/...`) para CRUD directo sobre las tablas, protegido por RLS.
- **Edge Functions** (`/functions/v1/...`) para todo lo que necesita un secreto, agrega
  varias fuentes o aplica lógica de servidor.

Base URL: `${SUPABASE_URL}`. Autenticación: `Authorization: Bearer <access_token>` y
`apikey: <SUPABASE_ANON_KEY>` en todas las llamadas.

Cabeceras comunes de request:
`X-Request-Id` (uuid, para trazar en Sentry), `X-Client-Version`, `X-Client-Platform`,
`Idempotency-Key` (en escrituras; por defecto el `id` del recurso).

---

## 1. Sobre de respuesta

Éxito (Edge Functions):

```json
{ "data": { }, "meta": { "requestId": "…", "durationMs": 812 } }
```

Error (todas las superficies, normalizado por el cliente):

```json
{
  "error": {
    "code": "ERR_QUOTA_EXCEEDED",
    "message": "Llegaste al límite diario de análisis por foto.",
    "details": { "limit": 20, "resetAt": "2026-07-28T03:00:00Z" },
    "requestId": "3f2b…"
  }
}
```

## 2. Catálogo de errores

| Código | HTTP | Reintentable | Mensaje al usuario |
| --- | --- | --- | --- |
| `ERR_UNAUTHENTICATED` | 401 | no (refresh y reintentar una vez) | "Tu sesión venció. Iniciá sesión de nuevo." |
| `ERR_FORBIDDEN` | 403 | no | "No tenés permiso para hacer eso." |
| `ERR_NOT_FOUND` | 404 | no | "Este registro ya no existe." |
| `ERR_VALIDATION` | 422 | no | Mensaje por campo, ver `details.fields` |
| `ERR_CONFLICT` | 409 | no | "Alguien más modificó este registro." |
| `ERR_RATE_LIMITED` | 429 | sí, tras `Retry-After` | "Demasiadas solicitudes. Probá en un momento." |
| `ERR_QUOTA_EXCEEDED` | 429 | no hasta el reset | "Llegaste al límite diario." |
| `ERR_UPSTREAM_TIMEOUT` | 504 | sí | "El servicio tardó demasiado. Reintentar." |
| `ERR_UPSTREAM_FAILED` | 502 | sí | "No pudimos consultar el catálogo. Reintentar." |
| `ERR_AI_INVALID_RESPONSE` | 502 | 1 reintento automático, salvo corte terminal | "No pudimos leer la foto." |
| `ERR_AI_RATE_LIMITED` | 429 | sí, recién pasado `error.retryAfter` | "El servicio de análisis está al límite por ahora. Esperá N segundos…" |
| `ERR_AI_OVERLOADED` | 503 | sí, en unos segundos | "El modelo está ocupado en este momento." |
| `ERR_AI_NO_FOOD` | 200 con `data.items = []` | no | "No encontramos comida en la foto." |
| `ERR_PERMISSION_DENIED` | — (cliente) | no | "Necesitamos tu permiso para…" |
| `ERR_PROVIDER_UNAVAILABLE` | — (cliente) | no | "Health Connect no está instalada." |
| `ERR_SYNC_FAILED` | 502 | sí | "No pudimos sincronizar." |
| `ERR_OFFLINE` | — (cliente) | sí al recuperar red | "Sin conexión." |
| `ERR_SERVER` | 500 | sí | "Algo salió mal de nuestro lado." |

Política de reintento del cliente: backoff exponencial con jitter — 1 s, 4 s, 15 s, 60 s,
luego cada 5 min, máximo 24 h. Solo para códigos reintentables y solo para escrituras
idempotentes.

Los dos códigos del proveedor de IA son la excepción y no se reintentan solos: los dispara
una persona mirando la pantalla, así que el reintento es un botón. Cuando el proveedor dice
cuánto falta, `ERR_AI_RATE_LIMITED` lo trae en `error.retryAfter` (segundos) y **el botón va
apagado hasta que pase**. Es la diferencia entre un límite del plan —que no se libera por
insistir, y donde cada toque le gasta el cupo al resto, porque la clave es una sola para
toda la app— y uno de saturación, que suele soltarse en segundos.

---

## 3. Buscar alimentos

**`GET /functions/v1/food-search`**

| Parámetro | Tipo | Req. | Notas |
| --- | --- | --- | --- |
| `q` | string | sí | ≥ 2 caracteres, ≤ 100 |
| `limit` | int | no | default 25, máx. 50 |
| `cursor` | string | no | Paginación por cursor opaco |
| `sources` | csv | no | `own,cache,usda,off` (default todas) |

- **Auth:** JWT. **Idempotencia:** N/A (GET). **Paginación:** cursor.
- **Errores:** `ERR_VALIDATION` (q corta), `ERR_RATE_LIMITED`, `ERR_UPSTREAM_TIMEOUT`
  (devuelve igual los resultados locales con `meta.degraded = true`).

```json
{
  "data": {
    "results": [
      {
        "id": "usda:1750340",
        "source": "usda",
        "name": "Yogur natural entero",
        "brand": null,
        "servingSize": 100,
        "servingUnit": "g",
        "kcal": 61,
        "proteinG": 3.5,
        "carbsG": 4.7,
        "fatG": 3.3,
        "isFavorite": false
      }
    ],
    "nextCursor": "eyJvIjoyNX0="
  },
  "meta": { "requestId": "…", "degraded": false, "sourceCounts": { "own": 2, "usda": 18, "off": 5 } }
}
```

## 4. Obtener detalle nutricional

**`GET /functions/v1/food-detail?source=usda&externalId=1750340`**

Respuesta: el objeto `Food` completo con `nutrients` (todos los micronutrientes
disponibles) y `portions` (lista de porciones con su factor a gramos).

Errores: `ERR_NOT_FOUND`, `ERR_UPSTREAM_FAILED`.

## 5. Analizar foto

**`POST /functions/v1/analyze-meal-photo`**

```json
{
  "analysisId": "b7c1…",
  "photoPath": "meal-photos/8f2a…/b7c1….jpg",
  "localDate": "2026-07-27",
  "hintSlot": "lunch"
}
```

- **Auth:** JWT. **Idempotencia:** por `analysisId` — repetir la llamada con el mismo id
  devuelve el análisis ya guardado sin volver a consumir cuota.
- **Timeout:** 25 s. **Cuota:** 20/día, 5/min.

```json
{
  "data": {
    "analysisId": "b7c1…",
    "status": "completed",
    "confidenceAvg": 0.71,
    "items": [
      {
        "name": "Pechuga de pollo a la plancha",
        "quantity": 150,
        "unit": "g",
        "kcal": 248,
        "proteinG": 46.5,
        "carbsG": 0,
        "fatG": 5.4,
        "confidence": 0.82,
        "matchedFood": { "source": "usda", "externalId": "171077" }
      },
      {
        "name": "Arroz blanco cocido",
        "quantity": 180, "unit": "g", "kcal": 234,
        "proteinG": 4.9, "carbsG": 51.3, "fatG": 0.5,
        "confidence": 0.44, "matchedFood": null
      }
    ],
    "notes": "Estimación visual. Las porciones pueden variar ±25 %."
  },
  "meta": { "requestId": "…", "durationMs": 4120, "model": "gemini-2.5-flash", "promptVersion": "v3" }
}
```

Errores: `ERR_QUOTA_EXCEEDED`, `ERR_AI_RATE_LIMITED`, `ERR_AI_OVERLOADED`,
`ERR_AI_INVALID_RESPONSE`, `ERR_AI_NO_FOOD`, `ERR_UPSTREAM_TIMEOUT`,
`ERR_VALIDATION` (foto inexistente o de otro usuario).

`ERR_QUOTA_EXCEEDED` es **nuestra** cuota (20 por persona por día) y
`ERR_AI_RATE_LIMITED` es la del proveedor, que la comparten todos los usuarios
de la app. Se parecen en el HTTP y no en nada más: la primera se resuelve
mañana para esa persona, la segunda depende del plan contratado.

## 6. Crear comida

**`POST /rest/v1/rpc/create_meal_with_items`** (transacción atómica)

```json
{
  "p_meal": {
    "id": "9d4e…",
    "slot": "lunch",
    "logged_at": "2026-07-27T15:10:00Z",
    "local_date": "2026-07-27",
    "source": "ai_photo",
    "ai_analysis_id": "b7c1…",
    "photo_path": "meal-photos/8f2a…/b7c1….jpg"
  },
  "p_items": [
    { "id": "1a…", "name": "Pechuga de pollo a la plancha", "quantity": 150, "unit": "g",
      "kcal": 248, "protein_g": 46.5, "carbs_g": 0, "fat_g": 5.4,
      "ai_confidence": 0.82, "was_ai_corrected": false, "position": 0 }
  ]
}
```

- **Idempotencia:** por `p_meal.id`. Si ya existe y no está borrada, devuelve la existente
  con `meta.idempotentHit = true`.
- **Validaciones de servidor:** `slot` válido; `logged_at ≤ now() + 24 h`; ≥ 1 ítem;
  `kcal` de cada ítem 0–2000; el trigger recalcula los totales.
- **Salida:** el objeto `Meal` con sus `items` y totales.
- **Errores:** `ERR_VALIDATION` (`details.fields`), `ERR_CONFLICT`, `ERR_UNAUTHENTICATED`.

## 7. Crear actividad

**`POST /rest/v1/activities`** (`Prefer: return=representation, resolution=merge-duplicates`)

```json
{
  "id": "4c8f…",
  "activity_type_id": "…walking…",
  "custom_name": null,
  "started_at": "2026-07-27T11:00:00Z",
  "ended_at": "2026-07-27T11:30:00Z",
  "local_date": "2026-07-27",
  "duration_minutes": 30,
  "intensity": "moderate",
  "distance_meters": 2600,
  "steps": 3400,
  "average_heart_rate": 108,
  "estimated_calories": 184,
  "original_calories": null,
  "applied_calories": 92,
  "exercise_credit_percentage": 50,
  "estimation_method": "met",
  "met_value": 3.5,
  "weight_kg_used": 100.0,
  "source_type": "manual",
  "user_edited": false,
  "notes": null
}
```

- **Idempotencia:** por `id` (PK generada en cliente) — el reintento offline no duplica.
- **Validaciones:** las CHECK de `07-data-model.md` §2.8 más la de solapamiento (se
  resuelve en cliente, el servidor solo advierte vía `meta.overlapCandidates`).
- **Salida:** la fila creada.
- **Errores:** `ERR_VALIDATION`, `ERR_CONFLICT` (choque con el índice único externo).

**`PATCH /rest/v1/activities?id=eq.<id>`** — actualización parcial. Al enviar
`estimated_calories` con `estimation_method = 'user_override'` el servidor exige que
`original_calories` no sea nulo (RN-04) o lo completa con el valor previo.

**Borrado:** `PATCH` con `{ "deleted_at": "…", "deletion_reason": "user" }`. El `DELETE`
físico está prohibido por policy.

## 8. Sincronizar Health Connect

**`POST /functions/v1/sync-health`**

El cliente lee del SDK nativo (solo el cliente tiene acceso), normaliza y envía el lote.

```json
{
  "provider": "health_connect",
  "since": "2026-07-20T00:00:00Z",
  "cursor": "eyJ0IjoxNzUzNjB9",
  "sessions": [
    {
      "externalId": "1F2E-…",
      "type": "walking",
      "startedAt": "2026-07-27T11:00:00Z",
      "endedAt": "2026-07-27T11:32:00Z",
      "activeCalories": 176,
      "distanceMeters": 2740,
      "steps": 3502,
      "averageHeartRate": 106,
      "maximumHeartRate": 128,
      "deviceName": "Pixel Watch 2",
      "sourceUpdatedAt": "2026-07-27T11:35:00Z"
    }
  ],
  "steps": [{ "localDate": "2026-07-27", "count": 8210 }],
  "weights": [{ "localDate": "2026-07-26", "weightKg": 99.4, "externalId": "W-…" }]
}
```

Respuesta:

```json
{
  "data": {
    "imported": 3,
    "updated": 1,
    "skipped": 2,
    "skippedReasons": { "user_edited": 1, "too_short": 1 },
    "duplicateCandidates": [
      {
        "incoming": { "externalId": "1F2E-…", "type": "walking", "startedAt": "…", "calories": 176 },
        "existing": { "id": "4c8f…", "sourceType": "manual", "startedAt": "…", "calories": 184 },
        "matchScore": 0.91
      }
    ],
    "nextCursor": "eyJ0IjoxNzUzOTB9",
    "lastSyncAt": "2026-07-27T18:02:11Z"
  }
}
```

- **Auth:** JWT. **Idempotencia:** por `(provider, externalId)`; reenviar el mismo lote no
  duplica (índice único + `sync_records.sync_hash`).
- **Paginación:** el cliente envía lotes de ≤ 200 sesiones y avanza con `nextCursor`.
- **Errores:** `ERR_VALIDATION` (provider desconocido), `ERR_SYNC_FAILED`, `ERR_RATE_LIMITED`.

**`POST /functions/v1/sync-health/resolve-duplicate`**

```json
{ "incomingExternalId": "1F2E-…", "existingActivityId": "4c8f…", "resolution": "keep_incoming" }
```
`resolution ∈ keep_incoming | keep_existing | keep_both | defer`.

## 9. Registrar peso

**`POST /rest/v1/weight_logs`** con `Prefer: resolution=merge-duplicates` (upsert por
`(user_id, local_date)`).

```json
{ "id": "…", "weight_kg": 99.2, "local_date": "2026-07-27",
  "logged_at": "2026-07-27T08:12:00Z", "source": "manual", "notes": null }
```

Validación: 25–400 kg. Errores: `ERR_VALIDATION`, `ERR_CONFLICT`.

## 10. Obtener resumen diario

**`GET /rest/v1/rpc/get_daily_summary?p_date=2026-07-27`**

Una sola llamada devuelve todo lo que Inicio necesita:

```json
{
  "data": {
    "date": "2026-07-27",
    "baseTarget": 2100,
    "consumedKcal": 1640,
    "exerciseEstimatedKcal": 240,
    "exerciseAppliedKcal": 120,
    "creditPercentage": 50,
    "creditEnabled": true,
    "adjustedTarget": 2220,
    "remainingKcal": 580,
    "netKcal": 1520,
    "macros": {
      "protein": { "current": 96, "target": 130 },
      "carbs":   { "current": 180, "target": 210 },
      "fat":     { "current": 54, "target": 70 }
    },
    "meals": [ { "id": "…", "slot": "lunch", "totalKcal": 640, "itemCount": 3, "source": "ai_photo" } ],
    "activities": [
      { "id": "4c8f…", "typeSlug": "walking", "displayName": "Caminata",
        "durationMinutes": 30, "estimatedCalories": 184, "appliedCalories": 92,
        "estimationMethod": "met", "sourceType": "manual", "syncStatus": "synced" }
    ],
    "activityTotals": { "minutes": 45, "sessions": 2, "steps": 8210 },
    "weight": { "weightKg": 99.2, "deltaKg": -0.4 },
    "isRestDay": false
  }
}
```

- **Auth:** JWT. **Errores:** `ERR_VALIDATION` (fecha inválida).
- **Cache:** el cliente cachea por `date` con invalidación en cualquier mutación del día.

## 11. Obtener progreso

**`GET /rest/v1/rpc/get_progress?p_from=2026-06-28&p_to=2026-07-27`**

```json
{
  "data": {
    "range": { "from": "2026-06-28", "to": "2026-07-27", "days": 30 },
    "weight": {
      "points": [{ "date": "2026-06-28", "kg": 101.2 }],
      "movingAverage7": [{ "date": "2026-07-04", "kg": 100.8 }],
      "deltaKg": -2.0,
      "trendKgPerWeek": -0.47
    },
    "calories": {
      "days": [{ "date": "2026-07-27", "consumed": 1640, "target": 2100, "exerciseApplied": 120 }],
      "averageConsumed": 1912,
      "adherencePct": 78
    },
    "activity": {
      "byDay": [{ "date": "2026-07-27", "minutes": 45, "calories": 240, "sessions": 2 }],
      "byCategory": [{ "category": "cardio", "minutes": 320 }],
      "totals": { "minutes": 520, "sessions": 14, "avgDurationMinutes": 37,
                  "estimatedCalories": 2840, "activeDays": 11,
                  "mostFrequentTypeSlug": "walking", "longestSessionMinutes": 75 },
      "weeklyAverageMinutes": 121,
      "previousWeekDeltaMinutes": 25,
      "stepsAverage": 7480
    },
    "goals": [{ "id": "…", "goalType": "active_minutes", "targetValue": 150,
                "currentValue": 130, "period": "week", "enabled": true }]
  }
}
```

Paginación: N/A (rango acotado a ≤ 366 días, `ERR_VALIDATION` si se excede).

## 12. Otros endpoints

| Operación | Método y ruta | Notas |
| --- | --- | --- |
| Perfil | `GET/PATCH /rest/v1/profiles?id=eq.<uid>` | — |
| Objetivo vigente | `GET /rest/v1/goals?user_id=eq.<uid>&ends_on=is.null` | — |
| Cambiar objetivo | `POST /rest/v1/rpc/set_goal` | Cierra el vigente e inserta el nuevo, transaccional |
| Catálogo de actividades | `GET /rest/v1/activity_types?or=(is_system.eq.true,user_id.eq.<uid>)` | Cacheado 24 h en el cliente |
| Historial | `GET /rest/v1/rpc/get_history?p_from&p_to&p_filters` | Paginado por 30 días |
| Plantillas | CRUD `/rest/v1/exercise_templates` | — |
| Objetivos de actividad | CRUD `/rest/v1/activity_goals` | — |
| Descanso | `POST/DELETE /rest/v1/rest_days` | — |
| Exportar datos | `POST /functions/v1/export-user-data` | 202 + correo |
| Eliminar cuenta | `POST /functions/v1/delete-account` | Requiere reautenticación < 5 min |

## 13. Idempotencia — resumen

| Operación | Clave | Comportamiento en repetición |
| --- | --- | --- |
| Crear comida | `meal.id` | Devuelve la existente |
| Crear actividad | `activity.id` | Devuelve la existente |
| Registrar peso | `(user_id, local_date)` | Upsert |
| Analizar foto | `analysisId` | Devuelve el análisis sin consumir cuota |
| Sincronizar salud | `(provider, externalId)` + `sync_hash` | Update solo si el hash cambió |
| Eliminar cuenta | `deletion_jobs` unique por usuario | No crea un segundo job |
