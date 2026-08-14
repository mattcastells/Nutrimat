# 21 — Motion, carga y micro-interacciones

Este documento es normativo: define **qué se anima, cuánto dura, con qué curva y qué se
muestra mientras se espera**. Si una pantalla no aparece acá, aplica el comportamiento por
defecto de §2.

Principio: la animación explica un cambio de estado, nunca decora. Si al quitar una
animación el usuario pierde información, esa información está mal comunicada —
arreglar el texto, no la animación.

---

## 1. Tokens de movimiento

Los mismos de `06-design-tokens.md` §5, repetidos acá con su uso obligatorio:

| Token | ms | Curva | Se usa en |
| --- | --- | --- | --- |
| `motion.instant` | 90 | `ease` | Cambio de estado de un control (chip, radio, switch, checkbox) |
| `motion.fast` | 160 | `ease` | Hover, ripple, aparición de badge, cambio de tab |
| `motion.base` | 240 | `ease` | Transición de pantalla, apertura y cierre de sheet, diálogo |
| `motion.slow` | 380 | `ease` | Anillo de calorías, barras de macros, contadores numéricos |
| `motion.chart` | 520 | `ease` | Entrada de series de un gráfico |
| `motion.ease` | — | `cubic-bezier(.2,.8,.2,1)` | Entradas y cambios de valor |
| `motion.easeOut` | — | `cubic-bezier(.4,0,1,1)` | Salidas y descartes |

Escalonado (*stagger*) estándar: **40 ms** entre elementos hermanos, con un techo de
**8 elementos** (a partir del noveno todos entran juntos, para que una lista larga no tarde
medio segundo en aparecer).

Regla de oro: nada dura más de 520 ms. Si algo necesita más tiempo, es una carga, no una
transición — mostrar un estado de carga (§4).

## 2. Comportamiento por defecto

| Evento | Animación |
| --- | --- |
| Entrada de pantalla (push) | Deslizamiento 12 px desde la derecha + fundido, `base`, `ease` |
| Salida de pantalla (pop) | Inverso, `base`, `easeOut` |
| Cambio de tab | Solo fundido, `fast` — sin desplazamiento lateral (los tabs son hermanos, no una jerarquía) |
| Apertura de bottom sheet | Deslizamiento desde abajo 100 % → 0, `base`, `ease`; backdrop hace fundido `fast` |
| Cierre de sheet | Inverso, `base`, `easeOut`; el gesto de arrastre lo controla el dedo y suelta con inercia |
| Apertura de diálogo | Escala 0,96 → 1 + fundido, `base`, `ease` |
| Aparición de snackbar | Deslizamiento 14 px desde abajo + fundido, `base` |
| Elemento nuevo en una lista | Fundido + 8 px hacia arriba, `base`, con el stagger de §1 |
| Elemento eliminado | Colapso de altura + fundido, `base`, `easeOut` |
| Reordenamiento | Desplazamiento de posición, `base` |

## 3. Animaciones con significado (obligatorias)

### 3.1 Anillo de calorías · `CalorieRing`

- Al montar: el arco crece de 0 al valor actual en `motion.chart` (520 ms) con `ease`, y el
  número del centro hace **count-up** desde 0 en la misma duración.
- Al cambiar el valor (se guarda una comida, se agrega actividad, cambia el crédito): el
  arco **transiciona** al nuevo valor en `motion.slow` (380 ms) y el número hace count-up
  desde el valor anterior al nuevo. Nunca salta.
- Implementación: animar `stroke-dashoffset` (propiedad CSS animable), no `stroke-dasharray`
  reasignada. En Flutter, `TweenAnimationBuilder<double>` sobre el ángulo + `CustomPainter`.
- Si el resultado queda negativo (se pasó del objetivo), el arco completa la vuelta y el
  excedente se dibuja encima en `accent-700` — con la misma duración, sin rebote ni
  vibración (RN-14: nada de castigo cinético).

### 3.2 Contadores numéricos

Todo número grande que cambia como consecuencia de una acción del usuario hace count-up /
count-down en `motion.slow`, con `ease` y **redondeo por frame** (no se muestran decimales
intermedios). Aplica a: calorías restantes, objetivo ajustado, gasto estimado de la
actividad en edición, total de la comida en `/meal/new` y en la revisión de IA.

No aplica a: valores que el usuario está tipeando (el campo manda), ni a listas.

### 3.3 Estimación de ejercicio · `ExerciseCaloriesEstimate`

Al recalcular (cambio de tipo, duración, intensidad o peso) el número hace count-up en
`motion.slow` y la línea de método hace un *crossfade* de `fast`. El recálculo tiene un
debounce de 120 ms: mientras el usuario arrastra el deslizador de duración se actualiza en
vivo, sin animación de count-up (sería un arrastre visual), y la animación solo corre
cuando el gesto termina.

### 3.4 Barras de macros

`width` con transición de `motion.slow`. Al montar la pantalla entran de 0 a su valor con
un stagger de 40 ms entre las tres.

### 3.5 Gráficos

| Gráfico | Entrada |
| --- | --- |
| `ActivityHistoryChart` (barras) | `scaleY` de 0 a 1 con `transform-origin: bottom`, `motion.chart`, stagger de 40 ms por barra, izquierda a derecha |
| Línea de kcal sobre las barras | Trazado progresivo (`stroke-dasharray` de 0 al largo total), `motion.chart`, con 120 ms de retraso respecto de las barras |
| `WeightChart` | Igual trazado progresivo; los puntos aparecen con fundido y escala 0,6 → 1, stagger 24 ms |
| `CaloriesChart` | Barras como arriba; la línea de objetivo entra al final con un fundido de `fast` |
| `ActivityCategoryChart` | `width` de 0 al valor, `motion.chart`, stagger 40 ms |
| Cambio de rango (7d → 30d) | No se reanima desde cero: los valores **transicionan** a su nuevo alto/ancho en `motion.slow`. Reanimar desde cero en cada cambio de rango marea. |

Un gráfico solo se anima **la primera vez que entra en pantalla** en esa sesión de
navegación. Volver a un gráfico ya visto (por ejemplo con el botón atrás) lo muestra en su
estado final, sin reanimación.

### 3.6 Progreso de objetivos de actividad

`ActivityGoalCard`: la barra crece en `motion.chart` al entrar. Al completar un objetivo,
un destello suave del acento (`opacity` 0 → 0,25 → 0, 520 ms) recorre la barra una vez.
**Sin confeti, sin rebote, sin sonido** — el tono del producto es neutral.

## 4. Estados de carga

Regla general: **skeleton, no spinner**. El spinner solo aparece dentro de un control que el
usuario acaba de accionar, o cuando no se puede anticipar la forma del contenido.

### 4.1 Umbrales

| Duración esperada | Qué se muestra |
| --- | --- |
| < 200 ms | Nada. No se muestra estado de carga (evita el parpadeo) |
| 200 ms – 10 s | Skeleton con la forma del contenido, o spinner en el control accionado |
| > 10 s | Skeleton + texto de progreso que cambia de fase (§4.4) + acción de cancelar |

Además, todo estado de carga tiene una **duración mínima visible de 400 ms** una vez que
apareció: si la respuesta llega a los 250 ms, el skeleton se mantiene hasta los 400 ms y
recién ahí hace crossfade al contenido. Sin esto, la pantalla parpadea.

### 4.2 Skeleton

- Bloques con `radius.md`, color `neutral-800` sobre `surface`.
- Brillo: gradiente que recorre de izquierda a derecha, **1200 ms**, `linear`, en bucle.
- La forma imita el contenido real: en Inicio, un bloque de tarjeta con un círculo (el
  anillo) y cuatro líneas; en listas, N filas con avatar cuadrado y dos líneas de distinto
  ancho (100 % y 60 %).
- Cantidad de filas fantasma por pantalla: Inicio 2 · Historial 10 · Buscador de alimentos 6
  · Progreso 2 tarjetas de gráfico.
- Transición skeleton → contenido: crossfade de `fast`, sin desplazamiento (los tamaños
  deben coincidir, por eso el skeleton imita la forma).

### 4.3 Spinner

- Anillo de 2 px, `accent`, arco de 270°, rotación de **900 ms** `linear` en bucle.
- Tamaños: 16 px dentro de un botón, 20 px en una fila, 24 px suelto.
- Dentro de un botón: el texto se reemplaza por el spinner y el botón **conserva su ancho**
  (nada de saltos de layout), queda deshabilitado y anuncia "Guardando" al lector de pantalla.
- Se usa en: guardar comida, guardar actividad, conectar integración, sincronizar ahora,
  exportar datos, confirmar eliminación de cuenta.
- Nunca a pantalla completa.

### 4.4 Pantalla "Analizando" (foto con IA)

Es la única espera larga del producto (2–25 s) y necesita tratamiento propio:

1. La foto se muestra al 45 % de opacidad, con un barrido de acento vertical de 1600 ms en
   bucle (sugiere lectura de la imagen, no progreso falso).
2. Debajo, tres filas skeleton con el shimmer estándar — la forma exacta de los ítems que
   van a aparecer.
3. Texto de fase, con crossfade de `fast` entre frases y un cambio cada 3,2 s. Primero
   las cinco que describen el trabajo real ("Buscando alimentos en la foto…" →
   "Reconociendo las preparaciones…" → …), que cubren la espera típica; después, **un
   pozo de frases livianas que rota sin fin** mientras no llegue la respuesta.
   **Ninguna frase habla del reloj.** Nada de "Terminando", nada de "Está tardando más
   de lo normal": los dos prometían algo sobre un tiempo que no controlamos —"Terminando"
   a los 14 s era falso la mitad de las veces— y el aviso de demora convertía una espera
   normal en un problema que la persona no puede resolver. La señal de que el análisis
   sigue vivo es que la frase cambia, no que anuncie el final.
4. **Prohibido** mostrar una barra de progreso determinada: no conocemos el progreso real.
   Lo que sí se muestra es una barra que avanza por pasos reales (preparar · subir ·
   analizar) y que dentro del último **estima contra la mediana medida y se frena en
   92 %**, con el "≈" delante del porcentaje. El 100 % solo llega con la respuesta.
5. Al llegar la respuesta: los skeletons hacen crossfade a los ítems reales con stagger de
   40 ms.

### 4.5 Refresco y paginación

- Pull-to-refresh: indicador nativo de la plataforma, con el color de acento.
- Scroll infinito en Historial: tres filas skeleton al pie mientras carga la página
  siguiente. Nunca un spinner centrado que empuje el contenido.

## 5. Micro-interacciones

| Interacción | Comportamiento |
| --- | --- |
| Tap en un botón | Tinte de acento al 22 % que entra en `instant` y sale en `fast`; en Android, ripple nativo con el color de acento |
| Tap en una fila de lista | Tinte neutral al 7 %, `instant` |
| Chip seleccionado | Borde y color cambian en `instant`; **sin** cambio de tamaño (mover el layout al seleccionar es desorientador) |
| Switch | Perilla se desplaza en `fast` con `ease`; el fondo hace crossfade en la misma duración |
| Campo con foco | Borde a acento en `fast`; el anillo de `:focus-visible` aparece sin animación (accesibilidad) |
| Error de validación | El mensaje entra con fundido + 4 px hacia abajo en `fast`. **Sin sacudida** — la sacudida lee como reproche |
| Swipe de una fila | Sigue al dedo 1:1; al soltar, completa o vuelve con `base` y curva de resorte suave (sin sobrepaso visible) |
| Eliminar con deshacer | La fila colapsa en `base`; si el usuario toca "Deshacer", se expande con la misma duración y un fundido del contenido |
| FAB | Al abrir el sheet, el ícono `+` rota 45° hasta la `×` en `base`; al cerrar, vuelve |
| Badge de sincronización | Al pasar de `pending` a `synced`, crossfade de `fast` + un pulso de escala 1 → 1,08 → 1 en 240 ms |
| Cambio de día en Inicio | El contenido hace un desplazamiento horizontal de 16 px en la dirección del gesto + fundido, `base` |
| Toast | Entra en `base`, permanece 3,6 s (8 s si hay "Deshacer", 20 s con lector de pantalla activo), sale en `fast` |

## 6. Reducción de movimiento

Con "Reducir movimiento" activo en el sistema:

- Todas las duraciones de desplazamiento y escala pasan a **0 ms**; se conservan los
  fundidos, reducidos a 90 ms.
- Los gráficos se dibujan en su estado final, sin crecimiento.
- Los contadores muestran el valor final sin count-up.
- El shimmer del skeleton se detiene: queda un bloque estático (el skeleton sigue existiendo,
  porque comunica "esto está cargando").
- El barrido de la pantalla "Analizando" se reemplaza por el texto de fase, que sigue
  cambiando.
- El spinner **se mantiene girando**: es el único indicador de actividad y desactivarlo
  dejaría al usuario sin señal. Es una excepción consciente y documentada.
- Ninguna animación es portadora exclusiva de información (`15-accessibility.md` §7).

## 7. Rendimiento

- Solo se animan `transform` y `opacity` cuando es posible. `width`, `height` y
  `stroke-dashoffset` se permiten en los casos listados en §3 (son pocos y acotados).
- Objetivo: 60 fps. Ninguna animación puede provocar un *layout pass* de la lista completa.
- Los gráficos animan como una sola capa compuesta, no elemento por elemento con setState
  por frame.
- Las animaciones se pausan cuando la pantalla no está visible y al pasar a segundo plano.
- Presupuesto: como máximo **dos** animaciones simultáneas en pantalla; si coinciden más
  (guardar una actividad recalcula anillo + barras + lista), se escalonan con el stagger de
  §1 en lugar de dispararse todas juntas.

## 8. Implementación

**Flutter**

| Necesidad | API |
| --- | --- |
| Transición de pantalla | `PageRouteBuilder` con `SlideTransition` + `FadeTransition` |
| Valor que cambia | `TweenAnimationBuilder<double>` (anillo, barras, contadores) |
| Entrada de listas | `AnimatedList` o `flutter_animate` con `.fadeIn().slideY()` y `delay` por índice |
| Skeleton | `Shimmer` propio con `AnimatedBuilder` + `LinearGradient` (no una dependencia externa) |
| Spinner | `CircularProgressIndicator(strokeWidth: 2)` con el color de acento |
| Colapso al eliminar | `SizeTransition` |
| Gráficos | `CustomPainter` con un `AnimationController` por gráfico |
| Reducción de movimiento | `MediaQuery.of(context).disableAnimations` → un `MotionScale` en el tema que multiplica todas las duraciones por 0 |

Todas las duraciones salen de `NmTokens.motion`; un lint prohíbe `Duration(milliseconds:)`
literal fuera de `core/theme/`.

**React Native**

`react-native-reanimated` v3 para todo lo de §3 y §5 (`withTiming` + `Easing.bezier(.2,.8,.2,1)`),
`react-native-svg` con `useAnimatedProps` para los gráficos, `LayoutAnimation` /
`entering`/`exiting` de Reanimated para listas, y `AccessibilityInfo.isReduceMotionEnabled()`
para el modo reducido, expuesto por un hook `useMotion()` que devuelve las duraciones ya
escaladas.

## 9. Qué se prueba

| Test | Verifica |
| --- | --- |
| `motion_tokens_test` | Ninguna duración literal fuera del tema |
| `reduced_motion_test` | Con `disableAnimations = true`, todos los widgets llegan a su estado final en un frame y el spinner sigue animando |
| `loading_min_duration_test` | Una respuesta de 250 ms mantiene el skeleton hasta los 400 ms |
| `no_layout_jump_test` | El botón con spinner conserva su ancho; skeleton y contenido real tienen la misma altura |
| `chart_replay_test` | Volver a un gráfico ya visto no lo reanima |
| Goldens de carga | Cada pantalla con estado `loading` tiene su golden |
