# 11 — Calculation Rules

Todas las fórmulas se implementan como **funciones puras, independientes y testeables**
en `domain/calculations/` (Flutter) o `src/domain/calculations/` (RN). Ninguna vive dentro
de un widget o componente.

Reglas transversales:

- **Redondeo:** `round_half_up` al entero para kcal y minutos; 1 decimal para kg; 2 para MET
  y para porcentajes derivados. Nunca se acumula error: se redondea **una sola vez**, al
  final del cálculo mostrado, salvo `applied_calories`, que se redondea y se persiste.
- **Unidades:** kg, cm, minutos, metros, kcal. Cualquier entrada en otra unidad se convierte
  antes de entrar a la fórmula.
- **Casos inválidos:** toda función valida sus entradas y lanza `CalculationError` con el
  campo ofensor. Ninguna devuelve `NaN`, `Infinity` ni negativos donde no corresponde.
- **Cero es un valor válido**, `null` no: si falta un insumo, la función no se llama y la
  UI muestra el estado "no podemos estimar" con el CTA para completarlo.

---

## 1. BMR — Mifflin-St Jeor

```
bmr(male)   = 10 × pesoKg + 6,25 × alturaCm − 5 × edadAños + 5
bmr(female) = 10 × pesoKg + 6,25 × alturaCm − 5 × edadAños − 161
bmr(unspecified) = promedio de ambas
```

| Variable | Unidad | Rango válido |
| --- | --- | --- |
| `pesoKg` | kg | 25–400 |
| `alturaCm` | cm | 90–250 |
| `edadAños` | años enteros | 13–100 |
| `sexo` | enum | `male \| female \| unspecified` |

- **Redondeo:** entero.
- **Inválido:** fuera de rango → `CalculationError('bmr', campo)`.
- **Decisión D-03:** se elige Mifflin-St Jeor sobre Harris-Benedict por su menor error medio
  en población general y sobre Katch-McArdle porque no exigimos % de grasa corporal.
- **Ejemplo:** mujer, 30 años, 165 cm, 70 kg → `700 + 1031,25 − 150 − 161 = 1420,25 → 1420`.
- **Tests esperados:** los 4 ejemplos de la tabla de §14, más límites (25 kg, 400 kg, 13
  años, 100 años) y errores fuera de rango.

## 2. TDEE

```
tdee = bmr × factorNivelActividad
```

| Nivel | Factor | Descripción mostrada |
| --- | --- | --- |
| `sedentary` | 1,200 | Trabajo de oficina, poco movimiento |
| `light` | 1,375 | Camina bastante o entrena 1–2 veces por semana |
| `moderate` | 1,550 | Entrena 3–4 veces por semana |
| `high` | 1,725 | Entrena 5–6 veces por semana |
| `very_high` | 1,900 | Trabajo físico o entrenamiento diario intenso |

- **Redondeo:** entero.
- **Nota importante:** el factor **ya incluye** actividad habitual. Por eso el crédito de
  ejercicio por defecto es 0 % (D-02): sumar el ejercicio registrado sobre un TDEE que ya
  lo contempla es doble conteo.
- **Ejemplo:** BMR 1420 × 1,375 = 1952,5 → **1953**.

## 3. Objetivo calórico — déficit y superávit

```
kcalPorKgDeGrasa = 7700
ajusteDiario     = (ritmoKgPorSemana × 7700) ÷ 7
objetivoBase(lose)     = tdee − ajusteDiario
objetivoBase(gain)     = tdee + ajusteDiario × 0,5   ← superávit conservador (D-04)
objetivoBase(maintain) = tdee
```

| Ritmo | Ajuste diario (déficit) |
| --- | --- |
| 0,25 kg/sem | 275 kcal |
| 0,50 kg/sem | 550 kcal |
| 0,75 kg/sem | 825 kcal |
| 1,00 kg/sem | 1100 kcal |

- **Clamp (RN-12):** mínimo 1200 kcal (femenino) / 1500 kcal (masculino) / 1350
  (`unspecified`). Máximo 6000. Si el clamp actúa, la UI lo dice:
  "Ajustamos tu objetivo al mínimo saludable de 1200 kcal."
- **Máximo de ritmo (RN-13):** 1 kg/semana.
- **Ejemplo:** TDEE 1953, bajar 0,5 kg/sem → 1953 − 550 = **1403**.
- **Superávit al 50 %:** ganar peso a 0,25 kg/sem sobre TDEE 2600 → 2600 + 137,5 = **2738**.
  Se usa la mitad porque un superávit completo se traduce mayormente en grasa (D-04).

### 3.b. El ritmo se elige como fracción del gasto (RN-19)

Lo de arriba sigue siendo la fórmula, pero **ya no es así como se elige el
ritmo**. Un ajuste fijo en kilos por semana esconde dos esfuerzos que no se
parecen: 550 kcal son el 21 % del gasto de una persona de 2.600 y el 35 % del de
una de 1.550, y el piso de RN-12 no alcanza para notarlo — actúa recién en 1.200
kcal, cuando el desbalance ya pasó. Es lo que hacía que la app le diera muy poco
a los cuerpos más chicos.

Las pantallas ofrecen una fracción del TDEE (`GoalPace`) y los kilos por semana
salen como consecuencia:

```
ajusteDiario     = tdee × fraccion
ritmoKgPorSemana = redondear2(ajusteDiario × 7 ÷ 7700), topeado en 1 (RN-13)
ajusteDiario     = (ritmoKgPorSemana × 7700) ÷ 7      ← se rehace desde el ritmo ya redondeado
```

El ajuste se recalcula desde el ritmo redondeado porque es ese valor el que se
guarda (`goals.rate_kg_per_week` es `numeric(3,2)`): si el objetivo saliera de la
fracción sin redondear, el número mostrado y el guardado se separarían.

| Ritmo | lose | gain_muscle | gain |
| --- | --- | --- | --- |
| De a poco | 10 % | 5 % | 2,5 % |
| Sostenido *(por defecto)* | 15 % | 10 % | 5 % |
| Más firme | 20 % | 15 % | 7,5 % |
| Al máximo | 25 % | 20 % | 10 % |

- **Techo:** 30 % del gasto. Un ritmo guardado que lo supere —los hay, de antes
  de esta regla— se recorta al releerlo en vez de romper la pantalla.
- **D-04 sigue vivo, pero visible:** las fracciones de `gain` son la mitad de las
  de `gain_muscle`. El camino relativo **no** vuelve a multiplicar por 0,5; si lo
  hiciera, el superávit quedaría en un cuarto.
- **Ejemplo:** TDEE 2417, bajar, "Sostenido" → 2417 × 0,15 = 362,55 → ritmo 0,33
  kg/sem → ajuste 363 → **2054**.
- **Ejemplo del tope:** TDEE 6000, bajar, "Al máximo" → 0,25 daría 1,36 kg/sem,
  se topea en 1,00 → **4900**.

### 3.c. Objetivo propuesto por la IA (RN-20)

El alta guiada (S-05) ofrece que el objetivo lo proponga un modelo, al lado del
que da la fórmula. Se guarda con `target_method = 'ai'`: no es `calculated` —no
salió de Mifflin-St Jeor— ni `manual` —nadie lo escribió—.

La Edge Function `suggest-calorie-target` **recalcula el BMR y el TDEE con estas
mismas fórmulas** a partir de los datos crudos que recibe, y acota lo que
devuelve el modelo contra su propio número: nunca más de un 30 % de déficit ni de
un 25 % de superávit, nunca fuera de 800–6000, y el mínimo de RN-12 lo sube y lo
dice. Fuera de esa banda la respuesta se descarta entera en vez de recortarse: un
número tan lejos del gasto significa que el modelo no entendió el pedido, y su
explicación —que es la mitad del valor de esto— hablaría de otro número.

No se le pasa un TDEE ya calculado a propósito. Si el techo de la validación
viniera de quien llama, la validación no estaría validando nada.

## 4. Calorías por gramos de macronutriente

```
kcalPorMacros = proteínaG × 4 + carbohidratoG × 4 + grasaG × 9
                (+ fibraG × 2 y alcoholG × 7 cuando estén presentes)
```

- **Redondeo:** entero.
- **Uso:** validación cruzada al crear un alimento y cálculo de un ítem cuando el catálogo
  no trae kcal.
- **Ejemplo:** 46,5 P · 0 C · 5,4 G → 186 + 0 + 48,6 = 234,6 → **235**.

## 5. Consistencia macros ↔ calorías

```
delta = |kcalDeclaradas − kcalPorMacros|
inconsistente = delta > 30  AND  delta > kcalDeclaradas × 0,20
```

No bloquea el guardado; muestra la advertencia de F-03. Se marca el alimento con
`nutrient_warning = true` para poder auditar la calidad del catálogo.

## 6. Total de una comida

```
comida.kcal      = Σ ítem.kcal
comida.proteínaG = Σ ítem.proteínaG        (idem carbos y grasas)
ítem.kcal        = round(alimento.kcalPorPorción × cantidad ÷ porciónReferencia)
```

Los totales se recalculan por trigger en la base y en el cliente al editar. Se redondea
**por ítem** (es lo que ve el usuario en cada fila) y luego se suman los redondeados, para
que la suma visible coincida con el total visible.

## 7. Calorías consumidas del día

```
consumidas = Σ comida.kcal de las comidas con local_date = D y deleted_at is null
```

## 8. MET — estimación de gasto por actividad  ★

```
caloriasPorMinuto = MET × 3,5 × pesoKg ÷ 200
caloriasActividad = caloriasPorMinuto × duracionMinutos
```

Forma equivalente, la que se implementa:

```
caloriasActividad = MET × 3,5 × pesoKg ÷ 200 × duracionMinutos
```

| Variable | Unidad | Rango |
| --- | --- | --- |
| `MET` | — | 0,9–23,0 |
| `pesoKg` | kg | 25–400 |
| `duracionMinutos` | min | 1–1440 |

- **Peso usado:** el último `weight_logs` (S-07 del PRD); si no hay ninguno, el del perfil.
  Se persiste en `activities.weight_kg_used` para poder auditar el cálculo después.
- **Redondeo:** `round_half_up` al entero, **una sola vez**, al final.
- **Inválido:** falta el peso → no se calcula; la UI muestra "Necesitamos tu peso para
  estimar" con CTA a registrar peso. MET fuera de rango → `CalculationError`.
- **Ejemplo canónico (el del brief):** peso 100 kg, caminata moderada MET 3,5, 30 min
  → `3,5 × 3,5 × 100 ÷ 200 = 6,125 kcal/min` → `6,125 × 30 = 183,75` → **184 kcal**.
- **Tests esperados:** el ejemplo canónico; 60 kg / MET 9,8 / 45 min = 463 kcal;
  duración 1 min; MET mínimo; error por peso 0.

**Los valores MET no se hardcodean en la UI** (D-06): salen de `activity_types`, que es un
catálogo editable desde la base sin publicar una versión de la app.

## 9. Intensidad → MET

```
met = tipo[intensidad + '_met'] ?? tipo.default_met
```

Cada actividad define su MET por intensidad (`light_met`, `moderate_met`, `vigorous_met`).
Si no los define, se usa `default_met` para las tres y la UI lo aclara.

Ejemplo del catálogo: `{ "activity": "walking", "intensity": "moderate", "met": 3.5 }`.

## 10. Gasto informado por un proveedor

```
si activeCalories es válido → estimatedCalories = activeCalories
                              estimationMethod  = 'provider'
si no                       → recalcular por MET
                              estimationMethod  = 'met_recalculated'
```

`activeCalories` es **inválido** si es nulo, ≤ 0, o si su tasa supera 1500 kcal/hora
(`activeCalories ÷ duracionMinutos × 60 > 1500`) — un valor así casi siempre es un error de
unidad del proveedor. Ver RN-05.

## 11. Estimación por ritmo (caminata y carrera)

Cuando hay distancia y duración pero el tipo no da un MET confiable:

```
velocidadKmh = (distanciaMetros ÷ 1000) ÷ (duracionMinutos ÷ 60)
```

| Velocidad | MET caminata | MET carrera |
| --- | --- | --- |
| < 4,0 km/h | 2,8 | — |
| 4,0–5,5 | 3,5 | — |
| 5,5–6,5 | 4,3 | — |
| 6,5–8,0 | 5,0 | 6,0 |
| 8,0–9,7 | — | 8,3 |
| 9,7–11,3 | — | 9,8 |
| 11,3–12,9 | — | 11,0 |
| > 12,9 | — | 12,8 |

Los tramos son semiabiertos `[inferior, superior)` y cada uno lleva el MET de su **borde
inferior**, que es el punto del [Compendium of Physical Activities][compendium] que lo ancla:
6,4 km/h (4 mph) → 6,0 · 8,0 (5 mph) → 8,3 · 9,7 (6 mph) → 9,8 · 11,3 (7 mph) → 11,0. El
tramo abierto superior usa 14,5 km/h (9 mph) → 12,8 como valor representativo.

[compendium]: https://pacompendium.com/running/

`estimationMethod = 'pace'`. Si la velocidad resultante es > 45 km/h se descarta el cálculo
por ritmo (dato incoherente) y se vuelve al MET del tipo.

## 12. Detección de duplicados  ★

Puntaje 0–1; se comparan solo actividades del **mismo usuario** con
`|started_at(A) − started_at(B)| ≤ 4 h`.

```
si A.external_source == B.external_source y A.external_id == B.external_id
   → score = 1,0 (duplicado exacto, se resuelve automáticamente por update)

en otro caso:
   solape       = duraciónDelSolape ÷ min(duraciónA, duraciónB)          → 0–1
   mismoTipo    = A.activity_type_id == B.activity_type_id               → 1 ó 0
   simDuración  = 1 − |durA − durB| ÷ max(durA, durB)                    → 0–1
   simCalorías  = 1 − |kcalA − kcalB| ÷ max(kcalA, kcalB)                → 0–1
   simDistancia = 1 − |distA − distB| ÷ max(distA, distB)  (si ambas)    → 0–1

   score = 0,45 × solape
         + 0,20 × mismoTipo
         + 0,15 × simDuración
         + 0,12 × simCalorías
         + 0,08 × simDistancia        (si no hay distancia, su peso se reparte
                                        proporcionalmente entre los demás)
```

| Score | Acción |
| --- | --- |
| ≥ 0,85 | Duplicado probable → `sync_status = 'needs_review'` + `DuplicateActivityDialog` |
| 0,60–0,85 | Sospecha → se guarda y se marca "Revisar", sin diálogo interruptivo |
| < 0,60 | Se consideran distintas |

**Nunca** se borra automáticamente. El umbral se ajusta con los datos de
`duplicate_resolutions`.

Casos cubiertos: manual + importada · Dos apps escribiendo en Health Connect · entrenamiento
importado + pasos asociados (los pasos no crean actividad, solo alimentan
`activityTotals.steps`) · dos sincronizaciones del mismo proveedor (índice único) ·
actividad editada que vuelve a importarse (RN-06).

## 13. Ajuste por ejercicio y balance diario  ★

```
factorRecuperacionEjercicio = porcentaje configurado por el usuario ÷ 100
caloriasEjercicioEstimadas  = Σ actividad.estimated_calories del día
caloriasEjercicioAplicadas  = round(caloriasEjercicioEstimadas × factorRecuperacionEjercicio)
objetivoAjustado            = objetivoBase + caloriasEjercicioAplicadas
caloriasRestantes           = objetivoAjustado − caloriasConsumidas
caloriasNetas               = caloriasConsumidas − caloriasEjercicioAplicadas
```

- Si `exercise_credit_enabled = false` → `caloriasEjercicioAplicadas = 0` y la fila "Ajuste"
  no se muestra.
- `caloriasRestantes` **puede ser negativo**; se muestra como "Te pasaste por 120 kcal", en
  `accent-700`, nunca en rojo (RN-14).
- `caloriasNetas` se muestra solo donde autoriza RN-11.
- **Ejemplo del brief:** objetivo base 2100, consumidas 1640, actividad 240, crédito 50 %
  → aplicadas `round(240 × 0,5) = 120` → ajustado `2220` → restantes `2220 − 1640 = 580`.
  Con crédito 100 %: aplicadas 240, ajustado 2340, restantes **700** — el ejemplo
  "700 kcal restantes con ajuste de actividad" del brief corresponde al 100 %.
- **Congelado:** `activities.exercise_credit_percentage` guarda el porcentaje vigente al
  crear el registro; al cambiar la configuración se recalculan **solo** el día en curso y
  los futuros (D-05).

## 14. IMC

```
imc = pesoKg ÷ (alturaCm ÷ 100)²
```

Redondeo a 1 decimal. Se muestra **sin categorías moralizantes**: se da el número y una
referencia neutral de rangos de la OMS en un enlace "Qué significa", nunca un juicio en la
pantalla principal (RN-14).

## 15. Promedios móviles y tendencia

```
mediaMovil(n)[i] = promedio de los valores en la ventana [i−n+1 … i]
                   (ventana incompleta → se calcula con los que haya, mínimo 2)
```

- Peso: ventana **7 días**, es la serie que se grafica como línea sobre los puntos diarios.
- Tendencia semanal: regresión lineal por mínimos cuadrados sobre los últimos 14 días de la
  media móvil; `trendKgPerWeek = pendienteDiaria × 7`, 2 decimales.
- Con menos de 3 puntos no se calcula tendencia: la UI muestra
  "Necesitamos unos días más de registro para mostrar una tendencia".

## 16. Adherencia

```
diaAdherente = |consumidas − objetivo| ≤ objetivo × 0,10   (tolerancia ±10 %)
adherencia%  = round(diasAdherentes ÷ diasConRegistro × 100)
```

Los días sin ningún registro **no cuentan** ni a favor ni en contra — no se penaliza no
registrar (RN-14). Si `diasConRegistro < 3`, no se muestra el porcentaje.

## 17. Métricas de actividad del período

```
minutosActivos     = Σ duration_minutes
sesiones           = count(actividades)
duracionPromedio   = round(minutosActivos ÷ sesiones)
kcalEstimadas      = Σ estimated_calories
diasConActividad   = count(distinct local_date)
promedioSemanal    = round(minutosActivos ÷ (díasDelRango ÷ 7))
deltaSemanaAnterior= minutosSemanaActual − minutosSemanaAnterior
promedioPasos      = round(Σ pasos ÷ díasConDatoDePasos)   (null si no hay ninguno)
```

Los días marcados como descanso planificado **no** bajan `diasConActividad` a efectos de
los mensajes de consistencia (RN-15): el texto dice "4 de los últimos 7 días (1 de
descanso planificado)".

## 18. Progreso de un objetivo de actividad

```
período     = semana ISO (lunes–domingo) o día, según goal.period
valorActual = Σ métrica del período según goal_type
progreso%   = min(100, round(valorActual ÷ target_value × 100))
```

El progreso **nunca** altera el objetivo calórico (RN-09).

## 19. Objetivos de macronutrientes por defecto

```
proteínaG = round(1,6 × pesoKg)                          (2,0 si goalType = 'lose')
grasaG    = round(objetivoKcal × 0,25 ÷ 9)
carbosG   = round((objetivoKcal − proteínaG×4 − grasaG×9) ÷ 4)
```

Si `carbosG` resulta < 50 g, se baja la proteína a 1,6 g/kg y se recalcula; si aún así es
< 50 g, se fija en 50 y se reduce la grasa. Nunca se devuelve un macro negativo.

## 20. Tabla de tests esperados (fixtures)

| # | Función | Entrada | Salida esperada |
| --- | --- | --- | --- |
| T-01 | `bmrMifflinStJeor` | F, 30 a, 165 cm, 70 kg | 1420 |
| T-02 | `bmrMifflinStJeor` | M, 40 a, 180 cm, 90 kg | 1830 |
| T-03 | `tdee` | 1420, `light` | 1953 |
| T-04 | `calorieTarget` | tdee 1953, lose, 0,5 | 1403 |
| T-05 | `calorieTarget` (clamp) | tdee 1400, lose, 1,0, F | 1200 + flag `clamped` |
| T-06 | `calculateCaloriesFromMet` | MET 3,5 · 100 kg · 30 min | **184** |
| T-07 | `calculateCaloriesFromMet` | MET 9,8 · 60 kg · 45 min | 463 |
| T-08 | `calculateAppliedExerciseCalories` | 240 · 50 % | 120 |
| T-09 | `calculateAppliedExerciseCalories` | 240 · 0 % | 0 |
| T-10 | `calculateAdjustedCalorieTarget` | 2100 + 120 | 2220 |
| T-11 | `calculateRemainingCalories` | 2220 − 1640 | 580 |
| T-12 | `calculateNetCalories` | 1640 − 120 | 1520 |
| T-13 | `kcalPorMacros` | 46,5 / 0 / 5,4 | 235 |
| T-14 | `bmi` | 70 kg · 165 cm | 25,7 |
| T-15 | `estimateMetFromPace` | 5000 m · 30 min · running (10 km/h) | 9,8 |
| T-16 | `duplicateScore` | mismo tipo, solape 100 %, kcal 176 vs 184 | ≥ 0,85 |
| T-17 | `duplicateScore` | distinto tipo, sin solape | < 0,60 |
| T-18 | `movingAverage` | 7 puntos, ventana 7 | media exacta |
| T-19 | `adherencePct` | 10 días, 7 dentro de ±10 % | 70 |
| T-20 | `macroTargets` | 1403 kcal, 70 kg, lose | P 140 · G 39 · C 123 |
