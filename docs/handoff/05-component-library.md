# 05 — Component Library

Convenciones:

- Nombres en `PascalCase`; en Flutter son widgets, en React Native componentes funcionales.
- Todo componente es **stateless respecto de datos de red**: recibe datos por props y emite
  eventos hacia arriba. La única excepción son los inputs, que manejan estado de edición local.
- Todo componente declara: props, estados, eventos, variantes, validaciones, dependencias,
  reglas de accesibilidad, ejemplo de uso, y comportamiento en carga / error / sin datos.
- Los tokens usados son los de `06-design-tokens.md`. Ningún componente hardcodea un color,
  una tipografía ni un espaciado.

---

## 1. Componentes de actividad

### `ActivitySummaryCard`

Resumen de la actividad del día para la pantalla de Inicio.

| Prop | Tipo | Req. | Default | Descripción |
| --- | --- | --- | --- | --- |
| `totalMinutes` | `int` | sí | — | Minutos de actividad del día |
| `estimatedCalories` | `int` | sí | — | kcal estimadas totales |
| `appliedCalories` | `int` | sí | — | kcal efectivamente aplicadas al objetivo |
| `creditPercentage` | `int` | sí | — | 0–100 |
| `sessionCount` | `int` | sí | — | Cantidad de actividades |
| `steps` | `int?` | no | `null` | Pasos del día, si hay fuente |
| `isRestDay` | `bool` | no | `false` | Día de descanso planificado |
| `onTap` | `VoidCallback?` | no | — | Abre la sección de actividad |
| `onAdd` | `VoidCallback` | sí | — | Abre `sheet.activity_add` |

- **Estados:** `default`, `empty` (0 sesiones → CTA de una línea), `restDay`
  ("Descanso planificado"), `loading` (skeleton), `error` (no aplica: siempre recibe datos locales).
- **Eventos:** `onTap`, `onAdd`.
- **Variantes:** `compact` (Inicio) · `expanded` (Progreso, agrega promedio y comparación).
- **Validaciones:** `creditPercentage ∈ [0,100]`; si es 0, no se renderiza la fila "aplicadas".
- **Dependencias:** `CalorieValue`, `Tag`, `Button(ghost)`.
- **Accesibilidad:** etiqueta compuesta "Actividad de hoy: 45 minutos, aproximadamente 240
  calorías estimadas, 2 sesiones". Toque mínimo 48×48. El CTA es un botón, no la tarjeta entera.
- **Ejemplo:** `ActivitySummaryCard(totalMinutes: 45, estimatedCalories: 240, appliedCalories: 120, creditPercentage: 50, sessionCount: 2, onAdd: openActivitySheet)`

### `ActivityListItem`

Fila de una actividad en Inicio, Historial o detalle del día.

| Prop | Tipo | Req. | Descripción |
| --- | --- | --- | --- |
| `activity` | `Activity` | sí | Entidad completa |
| `showDate` | `bool` | no | Mostrar la fecha (Historial) |
| `onTap` / `onEdit` / `onDuplicate` / `onDelete` / `onToggleFavorite` | callbacks | no | Acciones |

- **Muestra:** ícono del tipo, nombre (o `custom_name`), hora, duración, intensidad,
  `≈ kcal`, `DataOriginBadge`, `SyncStatusBadge`, estrella si es favorita.
- **Estados:** `default`, `pending` (sync), `error` (sync fallida, con reintento),
  `needsReview` (posible duplicado, badge ámbar "Revisar"), `deleting` (opacidad 0,4 durante
  la ventana de deshacer).
- **Variantes:** `default` · `dense` (Historial) · `readOnly`.
- **Interacción:** swipe izquierda → Eliminar; swipe derecha → Duplicar; long-press → menú.
  En Android el swipe requiere confirmación por snackbar con deshacer (8 s).
- **Accesibilidad:** las acciones de swipe se exponen también en el menú contextual
  (`Semantics.customActions`), porque el swipe no es accesible por lector de pantalla.

### `ActivityTypeSelector`

| Prop | Tipo | Descripción |
| --- | --- | --- |
| `types` | `List<ActivityType>` | Catálogo disponible |
| `recentTypeIds` | `List<String>` | Para los chips iniciales (máx. 4) |
| `value` | `String?` | `activity_type_id` seleccionado |
| `onChanged` | `(String) -> void` | — |
| `onBrowseAll` | `VoidCallback` | Abre `/activity/search` |

- **Estados:** `unselected` (guarda deshabilitado aguas arriba), `selected`, `loading` (catálogo).
- **Accesibilidad:** grupo de radio (`role: radiogroup`), cada chip anuncia su estado.

### `ActivityIntensitySelector`

Segmentado de 3 opciones: Suave · Moderada · Intensa. Default `moderate`.
Props: `value`, `onChanged`, `metByIntensity` (para mostrar el MET bajo cada opción cuando
el tipo lo define). Si el tipo no tiene MET por intensidad, se usa `default_met` para las
tres y se muestra una nota "Este tipo usa el mismo valor para todas las intensidades".

### `DurationInput`

Props: `valueMinutes`, `onChanged`, `presets` (default `[15, 30, 45, 60, 90, 120]`),
`min` (1), `max` (1440), `sliderMax` (240).
- Tres formas de entrada, siempre visibles: chips de preset, deslizador de `min` a
  `sliderMax` con paso de 5, y **campo libre `hh:mm`** que llega hasta el `max` real de
  1440 min (D-22). El deslizador se satura en `sliderMax`; el campo libre no.
- Por encima de 240 minutos muestra una nota neutral "¿Cuatro horas o más? Confirmá la
  duración", sin bloquear el guardado.
- **Validación:** entero dentro del rango; fuera de rango muestra el error de F-08 debajo.
- **Accesibilidad:** el campo acepta teclado numérico; los presets son botones, no chips
  decorativos.

### `DistanceInput`

Props: `valueMeters`, `unit` (`km`|`mi`, del perfil), `onChanged`, `max` (500000).
Convierte a metros para almacenar. Muestra 2 decimales en km, 2 en mi.

### `ExerciseCaloriesEstimate`  ★

La pieza que hace visible la honestidad del producto.

| Prop | Tipo | Descripción |
| --- | --- | --- |
| `calories` | `int` | Valor a mostrar |
| `method` | `EstimationMethod` | `met`, `provider`, `user_override`, `met_recalculated` |
| `metValue` | `double?` | Para el texto explicativo |
| `weightKg` | `double?` | idem |
| `durationMinutes` | `int?` | idem |
| `originalCalories` | `int?` | Si hubo override |
| `sourceLabel` | `String?` | "Health Connect", "Health Connect" |
| `onOverride` | `VoidCallback?` | Abre `dialog.override_calories` |
| `onRestore` | `VoidCallback?` | Restaura el valor calculado |

- **Reglas de render (obligatorias, RN-03):**
  - Siempre prefijo `≈`.
  - Siempre una segunda línea con el método: "Estimado con MET 3,5 · 100 kg · 30 min" /
    "Informado por Health Connect" / "Corregido por vos (cálculo original: 184 kcal)".
  - Nunca la palabra "quemaste"; se usa "gasto estimado".
- **Estados:** `calculated`, `overridden`, `provider`, `recalculated`, `unavailable`
  (falta peso → "Necesitamos tu peso para estimar" + CTA).
- **Accesibilidad:** se lee "aproximadamente 184 calorías, estimado con MET 3,5".

### `ExerciseCreditSelector`

Props: `value` (0–100), `onChanged`, `disabled` (bool), `onToggleDisabled`,
`previewEstimatedCalories` (para el ejemplo en vivo).
- Radios 0/50/75/100 + "Personalizado" con slider.
- Copy fijo del sistema (ver S-28), no parametrizable — es una decisión de producto.
- **Accesibilidad:** el slider anuncia el porcentaje y su efecto ("50 por ciento, sumaría
  120 calorías hoy").

### `ActivityHistoryChart`

Props: `points` (`List<{date, minutes, calories, sessions}>`), `range`, `comparePrevious`
(bool), `onSelectPoint`.
- Barras de minutos + línea de kcal, eje X por día/semana según rango.
- **Sin datos:** placeholder con ejes vacíos y texto "Sin actividad en este período".
- **Accesibilidad:** `Semantics` con resumen + tabla de datos desplegable.

### `ActivityCategoryChart`

Props: `slices` (`List<{category, minutes, color}>`), `totalMinutes`.
Barras horizontales apiladas + leyenda con minutos y porcentaje. No usar torta.

### `ActivityGoalCard`

Props: `goal` (`ActivityGoal`), `currentValue`, `onEdit`, `onToggle`.
- Muestra tipo, progreso `12 / 150 min`, barra, período y estado.
- **Nunca** muestra estados de fracaso; si el período terminó sin cumplirse, dice
  "Cerraste la semana con 120 de 150 minutos" (RN-14).

### `HealthIntegrationCard`

Props: `provider`, `status`, `lastSyncAt`, `permissions`, `importedCount`, `lastError`,
callbacks `onConnect`, `onSync`, `onDisconnect`, `onDeleteImported`, `onViewPermissions`.
- **Estados:** los 7 de S-29. En `syncing` el botón muestra progreso indeterminado y el
  resto de acciones se deshabilita.

### `SyncStatusBadge`

Props: `status` (`synced`|`pending`|`syncing`|`error`|`needs_review`), `compact`.
Iconografía Phosphor + texto. Nunca solo color. En `error` es tappable → reintentar.

### `DataOriginBadge`

Props: `sourceType` (`manual`|`imported`|`ai`), `sourceLabel`.
Ej.: "Manual" · "Importado · Health Connect" · "Estimado por IA". Usa `.tag-neutral` /
`.tag-outline` del sistema.

### `DuplicateActivityDialog`

Props: `candidateA`, `candidateB`, `matchScore`, `onKeepA`, `onKeepB`, `onKeepBoth`,
`onDecideLater`.
Ver S-14. **Validación:** nunca se autoresuelve; sin acción del usuario, el estado queda
`needs_review`.

### `ExerciseTemplateCard`

Props: `template`, `onUse`, `onEdit`, `onDelete`.
Muestra nombre, tipo, duración e intensidad por defecto y las kcal que estimaría con el
peso actual.

### `ActiveMinutesCard` / `StepsSummaryCard`

Props: `value`, `goalValue?`, `deltaVsPrevious`, `range`, `onTap`.
Tarjetas de una métrica con comparación neutral ("25 min más que la semana anterior").
`StepsSummaryCard` se **oculta por completo** si no hay ninguna fuente de pasos —no muestra 0.

---

## 2. Componentes de alimentación

| Componente | Props principales | Notas |
| --- | --- | --- |
| `DailySummaryCard` | `summary: DailySummary`, `onBreakdown`, `creditPercentage` | La tarjeta ★ de Inicio; muestra las 6 filas del desglose por separado (RN-01) |
| `CalorieRing` | `consumed`, `target`, `adjustedTarget`, `remaining` | El arco excedente se dibuja en `--color-accent-700`, no en rojo (RN-14) |
| `MacroBar` | `protein/carbs/fat` `{current, target}` | 3 barras con etiqueta y gramos |
| `MealSection` | `slot`, `items`, `totalKcal`, `onAdd` | Agrupa por slot |
| `MealListItem` | `meal`, callbacks | Igual patrón de swipe que `ActivityListItem` |
| `MealItemRow` | `item`, `onEditPortion`, `onRemove` | Dentro de `/meal/new` |
| `MealTotalsBar` | `kcal`, `macros` | Barra fija inferior en `/meal/new` |
| `FoodResultRow` | `food`, `source`, `onTap` | Fila de búsqueda con badge de origen |
| `PortionSelector` | `portions`, `value`, `quantity`, `onChanged` | Unidades del alimento |
| `AiEstimateBanner` | `confidenceAvg` | Banner ámbar obligatorio en S-20 |
| `AiItemRow` | `item`, `confidence`, callbacks | Campo de cantidad resaltado si confianza < 0,5 |
| `ConfidenceBadge` | `value` | `alta`/`media`/`baja` con texto, no solo color |
| `NutritionTable` | `nutrients`, `per` | Por 100 g y por porción |

## 3. Componentes de cuerpo y progreso

| Componente | Props principales | Notas |
| --- | --- | --- |
| `WeightRow` | `latest`, `delta`, `onLog` | Fila compacta en Inicio |
| `WeightChart` | `points`, `movingAverage`, `range` | Puntos + media móvil de 7 días |
| `CaloriesChart` | `days`, `targetLine`, `range` | Barras + línea de objetivo |
| `MeasurementChart` | `points`, `metric` | Una medida por vez |
| `StatCard` | `label`, `value`, `caption`, `trend` | Tarjeta de métrica genérica |
| `ConsistencyNote` | `text` | Mensajes neutrales de S-24 |

## 4. Componentes de sistema

| Componente | Props principales | Notas |
| --- | --- | --- |
| `Button` | `variant: primary\|secondary\|ghost\|icon`, `block`, `loading`, `disabled`, `icon` | El primario es **contorneado**, nunca relleno (Nocturne) |
| `TextField` / `NumberField` / `PasswordField` | `label`, `value`, `error`, `hint`, `suffix`, `keyboardType` | Error debajo del campo, `liveRegion` |
| `SegmentedControl` | `options`, `value`, `onChanged` | `.seg` del sistema |
| `RadioGroup` / `Switch` / `Slider` / `Checkbox` | estándar | Estados temáticos, nunca defaults del SO |
| `Tag` | `variant: accent\|accent-2\|neutral\|outline` | — |
| `Card` | `elevation: sm\|md\|lg` | `.card` + `.elev-*` |
| `ActionSheet` / `ActionRow` | `items`, `onSelect` | Foco atrapado, Escape cierra |
| `Dialog` | `title`, `body`, `actions`, `dismissible` | `.dialog` |
| `Snackbar` | `message`, `actionLabel`, `onAction`, `duration` | 8 s cuando hay "Deshacer" |
| `EmptyState` | `icon`, `title`, `body`, `primaryAction`, `secondaryAction` | Nunca una lista vacía sin explicación |
| `ErrorState` | `code`, `message`, `onRetry` | Muestra el código en modo debug |
| `OfflineBanner` | `pendingCount` | Fijo bajo la cabecera |
| `SkeletonBlock` / `SkeletonList` | `lines`, `height` | Sustituye a los spinners |
| `StepIndicator` | `current`, `total` | Onboarding |
| `BottomTabBar` | `items`, `current`, `onSelect` | 4 destinos + hueco central para el FAB |
| `Fab` | `onPressed` | 56×56, elevado, ícono `Plus` |
| `InfoNote` | `text`, `tone: neutral\|caution` | Notas explicativas (estimaciones, límites) |
| `FormulaRow` | `expression`, `values` | Desglose diario |

## 5. Reglas transversales de componente

**Carga.** Ningún componente muestra un spinner de pantalla completa. Se usa
`SkeletonBlock` con la forma del contenido final. Un contenido que tarda < 200 ms no
muestra estado de carga (evita el parpadeo).

**Error.** Todo componente que puede fallar acepta `error` y `onRetry`. El mensaje es
específico (nunca "Ocurrió un error"): incluye qué falló y qué puede hacer el usuario. El
código técnico se muestra solo en builds de debug o detrás de "Ver detalle".

**Sin datos.** Todo listado acepta un `EmptyState` con al menos una acción. Un cero
legítimo (0 kcal consumidas hoy) **no** es un estado vacío: se muestra el cero.

**Responsive.** Breakpoints en `06-design-tokens.md` §6. Regla práctica: hasta 600 px una
columna; 600–900 px las tarjetas de Progreso pasan a 2 columnas; > 900 px (tablet) el
layout usa `NavigationRail` en lugar de `BottomTabBar` y Inicio se parte en dos columnas
(resumen a la izquierda, registros a la derecha). El ancho de contenido se limita a 720 px.

**Accesibilidad (aplica a todos).** Área táctil mínima 48×48 dp. Contraste de texto ≥ 4,5:1
(≥ 3:1 para texto ≥ 24 px y para iconografía). Todo componente interactivo tiene etiqueta
semántica y estado; el foco visible usa el anillo de acento de 2 px del sistema. El color
nunca es el único portador de información. Soporte de escalado de texto hasta 200 % sin
pérdida de contenido: ningún contenedor tiene altura fija en dp para texto.

**Tematización.** Todos los componentes leen del tema (claro/oscuro) y no del sistema
operativo directamente. Ningún valor de color se pasa por prop salvo en gráficos, y allí
proviene de la paleta de datos definida en tokens §5.
