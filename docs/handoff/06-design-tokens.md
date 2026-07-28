# 06 — Design Tokens

Los tokens derivan del sistema de diseño **Nocturne** (tema oscuro canónico). Se entregan
en tres formatos que deben mantenerse en sincronía:

- `design-tokens.json` — fuente de verdad, consumible por Style Dictionary.
- `design-tokens.ts` — objeto tipado para React Native.
- Este documento — la explicación de cuándo usar cada uno.

> Regla de oro: **ningún componente escribe un hex, un nombre de fuente ni un número de
> píxel que ya exista como token.**

## 1. Color

### 1.1 Roles

| Token | Oscuro (canónico) | Claro | Uso |
| --- | --- | --- | --- |
| `color.bg` | `#161826` | `#f7f7fb` | Fondo de la app |
| `color.surface` | `#232532` | `#ffffff` | Tarjetas, hojas, campos |
| `color.surfaceRaised` | `#2b2e3d` | `#f0f0f6` | Superficie sobre superficie |
| `color.text` | `#e9e9ed` | `#1b1c26` | Texto principal |
| `color.textMuted` | `rgba(233,233,237,.55)` | `rgba(27,28,38,.58)` | Texto secundario |
| `color.accent` | `#9184d9` | `#796cbf` (accent-600) | Acento único |
| `color.divider` | `rgba(233,233,237,.16)` | `rgba(27,28,38,.12)` | Separadores |
| `color.section` | `#262a60` | `#262a60` | Fondo de presencia (poco uso en app) |

El tema claro invierte la rampa neutral y baja el acento un paso (`accent-600`) para
conservar ≥ 4,5:1 sobre `#ffffff`. **El acento base no se usa para texto de párrafo en
oscuro** (contrast ≈ 3,4:1): para eso está `color.accent-300`.

### 1.2 Rampas (100 → 900, escala perceptual compartida en OKLCH)

```
neutral   100 #f3f5fe  200 #e4e7f5  300 #cfd3e5  400 #b2b6ca  500 #9397ab
          600 #75798c  700 #595d6c  800 #3f424d  900 #292b31
accent    100 #f5f4ff  200 #e7e5fe  300 #d2cefd  400 #b5abfc  500 #968ae0
          600 #796cbf  700 #5d5294  800 #423a6a  900 #2b2741
accent-2  100 #f5f4ff  200 #e7e5fe  300 #d2cefd  400 #b5afe8  500 #9690c9
          600 #7972a9  700 #5c5783  800 #423e5d  900 #2b293a
```

Uso sobre fondo oscuro: 700–900 para rellenos tintados, hovers y bordes sutiles; 500 como
base del rol; 100–300 para texto sobre esos rellenos y para estados presionados.
**No usar `color-mix()` ad hoc cuando existe un paso de rampa.**

### 1.3 Colores semánticos

| Token | Oscuro | Claro | Uso |
| --- | --- | --- | --- |
| `color.success` | `#6fbf9a` | `#2f8f6a` | Confirmaciones, sincronizado |
| `color.caution` | `#d9b46a` | `#9a7420` | Estimaciones de IA, revisar duplicado, advertencias no bloqueantes |
| `color.danger` | `#d97b7b` | `#b04141` | Errores, borrado destructivo |
| `color.info` | `#7fa8d9` | `#3c6ea8` | Notas informativas |

`caution` es el color de **todo lo estimado o incierto** (banner de IA, badge de revisión).
`danger` **no** se usa para "te pasaste de calorías" (RN-14): el exceso se dibuja con
`accent-700`.

### 1.4 Paleta de datos (gráficos)

Orden fijo, para que la misma categoría tenga el mismo color en todos los gráficos:

| Serie | Token | Oscuro |
| --- | --- | --- |
| Caminata | `chart.1` | `#9184d9` |
| Carrera | `chart.2` | `#7fa8d9` |
| Fuerza | `chart.3` | `#b5abfc` |
| Ciclismo | `chart.4` | `#6fbf9a` |
| Deportes | `chart.5` | `#d9b46a` |
| Otras | `chart.6` | `#9397ab` |
| Consumido | `chart.intake` | `#968ae0` |
| Objetivo (línea) | `chart.target` | `#cfd3e5` |
| Peso | `chart.weight` | `#b5abfc` |
| Media móvil | `chart.trend` | `#e9e9ed` |

Cada serie lleva además un patrón o forma de marcador distinto, para no depender del color
(`15-accessibility.md` §8).

## 2. Tipografía

Familia única: **Inter** (`font.heading` y `font.body`). Peso de títulos **500** — no
subir a 600/700; la jerarquía es tamaño y espacio.

| Token | Tamaño | Line-height | Peso | Uso |
| --- | --- | --- | --- | --- |
| `type.display` | 42 | 1,12 | 500 | Número grande del anillo de calorías |
| `type.h1` | 32 | 1,12 | 500 | Título de pantalla |
| `type.h2` | 25 | 1,15 | 500 | Título de sección |
| `type.h3` | 20 | 1,2 | 500 | Título de tarjeta |
| `type.h4` | 16 | 1,3 | 500 | Subtítulo |
| `type.body` | 15 | 1,55 | 400 | Cuerpo |
| `type.bodySm` | 14 | 1,5 | 400 | Cuerpo denso, inputs, botones |
| `type.caption` | 13 | 1,45 | 400 | Metadatos |
| `type.micro` | 11 | 1,4 | 400 | Badges, notas al pie |
| `type.overline` | 10 | 1,4 | 500 | Kickers, `letter-spacing: .1em`, mayúsculas |

Tracking: `-0.015em` en títulos, `0` en cuerpo. Números tabulares
(`font-feature-settings: 'tnum'`) obligatorios en todas las cifras de calorías, peso y
duración para que no bailen al actualizarse.

## 3. Espaciado

Escala de densidad 0,70× de Nocturne. En móvil se redondea a enteros:

| Token | px | Uso |
| --- | --- | --- |
| `space.1` | 3 | Separación mínima intra-componente |
| `space.2` | 6 | Gap de chips, icono-texto |
| `space.3` | 8 | Padding interno de tarjeta compacta |
| `space.4` | 11 | Padding de tarjeta |
| `space.5` | 14 | — |
| `space.6` | 17 | Separación entre bloques |
| `space.8` | 22 | Separación entre secciones |
| `space.10` | 28 | Margen superior de pantalla |
| `space.12` | 34 | Separación mayor |

Márgenes de pantalla: 16 px laterales en móvil, 24 px ≥ 600 px.
Altura del `BottomTabBar`: 56 + safe area. FAB: 56×56, `-20 px` de solape.

## 4. Radios, sombras, iconos

| Token | Valor |
| --- | --- |
| `radius.sm` | 4 |
| `radius.md` | 8 (default de tarjetas, campos y botones) |
| `radius.lg` | 14 (hojas y diálogos) |
| `radius.full` | 999 (chips, badges, FAB) |

| Token | Valor (oscuro) | Uso |
| --- | --- | --- |
| `shadow.sm` | `0 0 0 1px #3f424d` | Borde-elevación de tarjeta |
| `shadow.md` | `0 0 0 1px #595d6c, 0 6px 18px rgba(0,0,0,.55)` | Hojas, FAB |
| `shadow.lg` | `0 0 0 1px #9397ab, 0 16px 40px rgba(0,0,0,.65)` | Diálogos |

En tema claro las sombras pasan a tinta suave sin borde:
`sm: 0 1px 2px rgba(27,28,38,.08)`, `md: 0 4px 14px rgba(27,28,38,.10)`,
`lg: 0 16px 40px rgba(27,28,38,.16)`.

**Iconos:** Phosphor (peso `regular`; `fill` solo para el estado activo del tab bar).
Tamaños: `icon.sm` 16 · `icon.md` 20 · `icon.lg` 24 · `icon.xl` 32.
Los iconos heredan `currentColor`; nunca llevan color propio.

## 5. Duraciones y curvas

| Token | Valor | Uso |
| --- | --- | --- |
| `motion.instant` | 90 ms | Cambio de estado de un control |
| `motion.fast` | 160 ms | Hover, ripple, badge |
| `motion.base` | 240 ms | Transición de pantalla, apertura de sheet |
| `motion.slow` | 380 ms | Anillo de calorías, barras de macros, contadores |
| `motion.chart` | 520 ms | Entrada de series de un gráfico |
| `motion.ease` | `cubic-bezier(.2,.8,.2,1)` | Entradas |
| `motion.easeOut` | `cubic-bezier(.4,0,1,1)` | Salidas |

Con `reduce motion` activo: todas las duraciones pasan a 0 ms salvo los *fades*, que se
reducen a 90 ms. Ninguna animación es portadora de información. El comportamiento completo
(qué se anima, estados de carga, spinners, entrada de gráficos) está en
`21-motion-and-loading.md`.

## 6. Breakpoints y elevación lógica

| Token | Ancho | Layout |
| --- | --- | --- |
| `bp.compact` | < 600 | 1 columna, `BottomTabBar` |
| `bp.medium` | 600–904 | tarjetas en 2 columnas |
| `bp.expanded` | ≥ 905 | `NavigationRail`, Inicio en 2 columnas, contenido máx. 720 px |

Elevaciones lógicas (z-index): contenido 0 · barra fija 10 · FAB 20 · bottom sheet 30 ·
diálogo 40 · snackbar 50 · banner de sistema 60.

## 7. Estados de interacción

| Estado | Regla |
| --- | --- |
| `hover` (puntero/tablet) | Tinte del acento al 12 % o `--color-text` al 7 % en secundarios |
| `pressed` | Tinte al 22 % / 14 %; en fondo oscuro se usa `accent-400` |
| `focus-visible` | `outline: 2px solid color.accent; outline-offset: 2px` — **nunca** el anillo por defecto del SO |
| `selected` | `box-shadow: inset 0 0 0 1px color.accent` + texto en acento |
| `disabled` | opacidad 0,45, sin cambios de color |
| `error` | borde `color.danger` + mensaje debajo, nunca solo borde |
| `loading` | skeleton, no spinner |

## 8. Sincronización de tokens

`design-tokens.json` es la fuente. El pipeline (fase 1 del roadmap) genera:

- Flutter: `lib/core/theme/tokens.dart` (clase `NmTokens` con `ColorScheme` y `TextTheme`).
- React Native: `src/theme/tokens.ts`.

Un test de CI (`tokens_in_sync_test`) falla si algún archivo generado difiere del JSON, y
un lint prohíbe literales de color hexadecimal fuera de `theme/`.
