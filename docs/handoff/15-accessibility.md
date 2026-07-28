# 15 — Accessibility

Objetivo: **WCAG 2.2 nivel AA** en todo lo aplicable a una app móvil nativa, más las guías
de plataforma (Apple HIG Accessibility, Android Accessibility). Un defecto de accesibilidad
que rompa una de las reglas de este documento es **bloqueante para la publicación**.

## 1. Lector de pantalla

- Soporte completo de **VoiceOver** (iOS) y **TalkBack** (Android).
- Cada pantalla anuncia su título al abrirse; el foco se coloca en el encabezado, no en el
  primer control.
- Elementos decorativos (íconos junto a texto que ya lo dice, gradientes, ilustraciones)
  se marcan como ocultos al lector (`excludeSemantics` / `importantForAccessibility=no`).
- Elementos compuestos se agrupan en un solo nodo con etiqueta completa: la fila de una
  actividad se lee **"Caminata, 30 minutos, intensidad moderada, aproximadamente 184
  calorías estimadas, registro manual"**, no como 6 nodos sueltos.
- Los gestos de swipe tienen **siempre** un equivalente accesible
  (`Semantics.customActions` / `ACTION_*` de accesibilidad): Editar, Duplicar, Eliminar.
- Las hojas y diálogos atrapan el foco y lo devuelven al elemento que los abrió.
- Cambios asíncronos se anuncian con regiones vivas: "12 resultados", "Analizando la foto",
  "Comida guardada". Los errores se anuncian con prioridad `assertive`.

## 2. Etiquetas

| Elemento | Etiqueta |
| --- | --- |
| Anillo de calorías | "Te quedan 580 calorías de 2.220" |
| Fila del desglose | "Objetivo base, 2.100 calorías" |
| Calorías de actividad | "Aproximadamente 184 calorías, estimado con MET 3,5" |
| `SyncStatusBadge(pending)` | "Pendiente de sincronizar" |
| `DataOriginBadge(imported)` | "Importado desde Health Connect" |
| `ConfidenceBadge(low)` | "Confianza baja de la estimación" |
| FAB | "Agregar registro" |
| Botón "+" de un slot | "Agregar alimento al almuerzo" |
| Chip de tipo de actividad | "Caminata, seleccionado" / "no seleccionado" |
| Botón de eliminar | "Eliminar caminata de las 11:00" (nunca solo "Eliminar") |

Ninguna etiqueta contiene el nombre del ícono ni la palabra "botón" (la plataforma ya lo
anuncia por el rol).

## 3. Orden de foco

Sigue el orden visual y de lectura: cabecera → contenido principal → acciones secundarias →
navegación. En Inicio: selector de día → tarjeta de resumen → macros → comidas (por slot,
cada slot con sus ítems y luego su botón "+") → actividad → peso → FAB → tab bar.

En formularios, el orden es el de los campos; el botón de envío va al final. Al aparecer un
error, el foco se mueve al primer campo inválido y se anuncia el mensaje.

## 4. Contraste

| Contenido | Mínimo |
| --- | --- |
| Texto < 24 px | 4,5:1 |
| Texto ≥ 24 px o ≥ 19 px bold | 3:1 |
| Iconografía y bordes de controles | 3:1 |
| Estado de foco respecto del fondo | 3:1 |

Verificado en ambos temas. Consecuencias concretas ya aplicadas en tokens:
`--color-accent` (#9184d9) sobre `--color-bg` da ≈ 3,4:1 → **sirve para iconos, bordes y
texto grande, no para párrafos**; para texto de párrafo en acento se usa `accent-300`
(#d2cefd, ≈ 8,9:1). En tema claro el acento baja a `accent-600`.

`color.caution` y `color.danger` cumplen 4,5:1 sobre `surface` en ambos temas.

## 5. Texto escalable

- Soporte de **Dynamic Type / font scale hasta 200 %** sin pérdida de contenido ni de
  funcionalidad. Prohibido `MediaQuery.textScalerOf(context)` fijo o `allowFontScaling: false`.
- Ningún contenedor de texto tiene altura fija en dp: se usa altura mínima + `wrap`.
- A partir del 130 % de escala, los layouts de dos columnas de tarjetas pasan a una columna,
  y los chips de tipo de actividad pasan de fila horizontal a grilla envolvente.
- El número grande del anillo se limita a 1,6× de escala (sería ilegible por
  desbordamiento); el valor completo siempre está disponible en el desglose, que sí escala.
- Se prueba con las 5 escalas de sistema en los tests de golden.

## 6. Tamaños táctiles

- Mínimo **48×48 dp** para cualquier elemento accionable, aunque su parte visible sea menor
  (se expande el área de toque, no el gráfico).
- Separación mínima de 8 dp entre objetivos táctiles adyacentes.
- Los ítems de lista tienen 56 dp de alto mínimo.
- Las acciones destructivas no se colocan a menos de 16 dp de una acción frecuente.

## 7. Reducción de movimiento

Con `prefers-reduced-motion` / "Reducir movimiento" activo:

- Todas las transiciones de pantalla pasan a fundido de 90 ms.
- El anillo de calorías cambia sin animar el arco.
- Los skeletons dejan de tener brillo animado (quedan estáticos).
- El texto rotativo de la pantalla "Analizando" se reemplaza por un texto fijo.
- Ninguna animación es portadora de información: todo lo que una animación comunica está
  también en texto o en un cambio de estado estático.

Además: nada parpadea más de 3 veces por segundo (riesgo de fotosensibilidad).

## 8. Gráficos accesibles

Ningún gráfico depende del color. Cada serie tiene, además del color de la paleta de datos,
**una forma de marcador y un patrón de trazo distintos** (círculo lleno, cuadrado, línea
punteada, línea de trazos).

Cada gráfico expone:

1. Un **resumen semántico** que el lector de pantalla anuncia:
   "Gráfico de peso, últimos 30 días. De 101,2 a 99,2 kilos. Tendencia: baja 0,47 kilos por
   semana."
2. Un botón **"Ver como tabla"** que abre los datos en una tabla navegable con encabezados
   de fila y columna.
3. **Navegación por puntos:** con el lector activo, deslizar recorre punto por punto
   anunciando fecha y valor.

`ActivityCategoryChart` usa barras apiladas con etiqueta de texto por segmento (nunca una
torta con leyenda de solo color).

## 9. Mensajes de error

- Se anuncian con `liveRegion` `assertive` y mueven el foco al campo o al bloque afectado.
- Son específicos y accionables: "Ingresá una duración entre 1 y 1440 minutos", nunca
  "Valor inválido".
- El error se asocia al campo con la relación semántica adecuada
  (`Semantics(label:…, hint:…)` / `accessibilityLabelledBy`), no solo por proximidad visual.
- El color rojo del borde va acompañado de un ícono y del texto (nunca solo color).
- Los errores de formulario se resumen arriba del formulario cuando hay más de dos.

## 10. Otros requisitos

- **Sin dependencia del sensor:** ninguna acción requiere agitar, girar ni gestos multitáctiles.
- **Timeouts:** el snackbar con "Deshacer" dura 8 s; con lector de pantalla activo, 20 s.
  Nada crítico expira sin aviso.
- **Idioma:** `lang="es"` declarado; los números y fechas usan el formato local.
- **Modo oscuro/claro:** ambos cumplen los requisitos de contraste; el sistema respeta la
  preferencia del SO por defecto.
- **Teclado externo / navegación por teclado** (iPad, Android con teclado): todo alcanzable
  con Tab, con foco visible de 2 px de acento.
- **Orientación:** la app funciona en vertical y horizontal; no se bloquea la orientación.

## 11. Verificación

| Qué | Cómo | Cuándo |
| --- | --- | --- |
| Etiquetas y roles | `flutter test` con `SemanticsTester` en cada pantalla | CI, cada PR |
| Contraste | Script sobre los tokens + revisión manual de capturas | CI + revisión de diseño |
| Escalado de texto | Golden tests a 1,0× / 1,3× / 2,0× | CI |
| Tamaños táctiles | Lint personalizado sobre widgets accionables | CI |
| Recorrido con lector | Checklist manual de los 14 flujos con VoiceOver y TalkBack | Antes de cada release |
| Reducción de movimiento | Prueba manual con el ajuste activo | Antes de cada release |
