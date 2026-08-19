# El contexto del día, y desde cuándo se cuenta

Tres decisiones que se tomaron juntas porque resuelven el mismo problema de
fondo: **un día vacío en la pantalla no siempre quiere decir lo mismo**, y hasta
ahora todos los vacíos se veían igual.

- No había registro porque todavía no existía la cuenta.
- No había registro porque la persona estaba enferma.
- No había entrenamiento porque el sábado se tomó tres cervezas y el domingo no
  se levantó.

Los tres se dibujaban como el mismo hueco gris.

---

## 1 · El período efectivo (`trackingSince`)

### El problema

Los períodos salen del calendario —"los últimos 30 días"— y los denominadores
salían de ahí también. Alguien que empezó el 18 de agosto aparecía, el 19, con:

> Días con comidas: **1 de 30** · 29 sin registrar

Ninguno de esos 29 días es un incumplimiento: son días en que la app no existía
para esa persona. El calendario de adherencia mostraba media pantalla en gris,
el porcentaje "entre semana" salía del 4 %, y el "hueco más largo" contaba
veintinueve días que nunca fueron un hueco.

### La regla

> Ninguna métrica cuenta como "sin registro" un día anterior al primero del que
> hay algo cargado.

El **período efectivo** de una ventana `[desde, hasta]` es
`[max(desde, trackingSince), hasta]`. Todos los denominadores, promedios,
rachas, huecos y porcentajes salen de ahí. Si no hay `trackingSince` —una cuenta
sin un solo registro— el período efectivo está vacío y las métricas muestran
`—`, no `0 de 30`.

### La definición, que es una sola para los dos lados

```
trackingSince = min(local_date) sobre comidas + actividades + pesos, sin borrados
```

Agua y sueño quedan afuera **a propósito**: se cargan hacia atrás con facilidad
y no marcan cuándo empezó nadie. El peso entra porque el alta guiada lo registra
antes que cualquier otra cosa.

No es una definición nueva: es la que ya usaba `LocalRepository.trackingSince`
para el informe en PDF. Lo que se hizo fue **subirla a un lugar compartido y
aplicarla en todos lados**, en vez de que la respetara un solo consumidor.

| Dónde | Qué es |
| --- | --- |
| Móvil | `lib/domain/calculations/tracking_window.dart` — `TrackingWindow` |
| Web | `backoffice/lib/tracking.ts` — `ventanaEfectiva()` |
| Servidor | `public.tracking_since(uuid)`, expuesta en `care_patients` |

El panel no puede calcularla sola: solo consulta el período elegido, así que si
la persona empezó antes de `desde` no hay forma de saberlo con esos datos. Por
eso viaja en la vista.

### Por qué centralizado y no en cada gráfico

Porque el error es invisible cuando está bien. Un gráfico que respeta el período
efectivo y otro que no se ven exactamente igual hasta que alguien empieza a
mitad de mes, y para entonces ya hay quince lugares donde revisar. La ventana se
calcula **una vez por pantalla** y todo lo demás deriva de ella.

---

## 2 · `day_markers`: enfermedad y descanso

### Lo que se evaluó

| Opción | Por qué no |
| --- | --- |
| Tabla `sick_days` | Ya existía `rest_days` con las mismas columnas. La tercera etiqueta —vacaciones, viaje— pedía una tercera tabla. |
| Columna en `profiles` | No tiene historia: lo que importa es qué días, no un estado actual. |
| `daily_events(kind, payload jsonb)` genérica | Se pierden los `check`. En este esquema **todas** las escalas están restringidas en SQL (`sleep_logs_quality_valid`, `body_measurements_range`); un `jsonb` sería la única que no, y los modelos de Dart pasarían a ser bolsas de `dynamic`. |
| Extender `activities` | Un día enfermo no es una actividad, y colgarlo de ahí lo haría desaparecer cuando `share_wellbeing` está apagado por otra razón. |

### Lo que se hizo

**Generalizar `rest_days` a `day_markers`**: la misma tabla, más un
discriminador `kind`.

```
day_markers(id, user_id, local_date, kind, severity, tags[], note,
            created_at, updated_at, deleted_at)
kind ∈ ('rest', 'sick')          único por (user_id, local_date, kind)
severity 1..3, solo para 'sick'  tags[] para síntomas futuros
```

Sumar una etiqueta es agregar un valor al `check`, no una tabla. Los síntomas
del futuro entran por `tags` sin tocar el esquema, y si alguna vez piden
estructura propia, esa es la conversación de ese momento y no una jaula de hoy.

### El bug que apareció en el camino

`rest_days` **nunca se sincronizó**. La app guarda los días de descanso en
`LocalStore.restDays`, un `Set<String>` del documento local, y el cliente
relacional no nombraba la tabla: estaba vacía en producción desde que se creó, y
un día de descanso marcado en un teléfono no existía en el siguiente. Ahora la
app la escribe y la trae como cualquier otra colección.

---

## 3 · `alcohol_logs`: por qué **no** es un `day_marker`

Porque tiene magnitud. Una marca contesta "sí o no"; un consumo contesta
"cuánto", y eso es lo único con lo que se puede correlacionar contra calorías,
peso o sueño.

**Una fila por consumo, no por día.** "Dos copas de vino y una cerveza" es un
sábado normal; un renglón por día obliga a elegir cuál de los dos tipos se
guarda. Agrupar por día después es una línea de código; separar lo que se guardó
junto no se puede.

La unidad transversal es la **UBE de 10 g de etanol** (Ministerio de Salud), no
los 14 g de EE.UU.:

```
std_drinks = volumen_ml × (abv% / 100) × 0,789 / 10
kcal       = gramos_de_etanol × 7,1  (+ los hidratos de la bebida)
```

Se calcula en el dominio —`lib/domain/calculations/alcohol.dart`, con su test— y
se **guarda** el resultado, igual que `activities.estimated_calories`. El volumen
y la graduación quedan en la fila: si mañana se corrige el preset de "chopp", el
sábado pasado sigue siendo lo que se tomó.

### Las calorías del alcohol no entran en `meals`

Van aparte y se muestran aparte. Sumarlas al total de comidas escondería de
dónde salieron, que es justamente el dato que la nutricionista está buscando
cuando mira una semana en la que el peso no bajó y las comidas estaban bien.

---

## 4 · `care_notes`: la primera escritura del panel

La migración 32 dice que el acceso profesional es solo lectura. Sigue siendo
cierto y hay que leerlo con precisión: **lo que no se puede escribir son los
datos del paciente**. Ninguna política nueva lo cambia.

Lo que se abre es una tabla donde la profesional escribe lo suyo. Sin eso, la
consulta se prepara en un cuaderno aparte y la pantalla que tiene los datos no
tiene la lectura de esos datos.

- **Las lee solo quien las escribió.** Una observación clínica que el paciente
  va a leer se escribe distinto —o no se escribe—. Es reversible en una línea y
  está anotado en la migración.
- **Revocar el acceso no las borra, pero corta la escritura.** El texto es de
  quien lo escribió; seguir anotando sobre alguien que cortó el acceso es lo que
  el corte tiene que impedir.
- `local_date` nullable: `null` es una nota del seguimiento en general, con
  fecha queda anclada a ese día.

---

---

## 5 · La limpieza que salió de auditar todo esto

Revisar qué toca cada cliente contra qué hay en el esquema dejó a la vista un
puñado de cosas que no lee nadie, y dos que sí valían y no estaban conectadas.
Las migraciones 43 y 44 resuelven las dos mitades.

**Lo que se fue** (migración 43). En todos los casos el dato era derivable de lo
que ya está guardado, o era del dispositivo y no de la cuenta:

| Qué | Por qué |
| --- | --- |
| `get_daily_summary`, `create_meal_with_items` | Dos RPC del plan original que nunca llamó nadie. La primera duplicaba en SQL una regla que vive en Dart: dos implementaciones de la misma cuenta, una sin ejecutar, es la forma más segura de que un día dejen de coincidir sin que nadie se entere. |
| `recent_foods`, `recent_activities` y sus triggers | Se llenaban en **cada insert** de ítem y de actividad, y no los leía nadie: la app calcula sus recientes con lo que tiene local. Un año de historial son miles de triggers `security definer` para producir algo derivable con un `group by`. |
| `foods_cache` y `expire_food_cache` | Un espejo por cuenta de un catálogo público. El cache sirve en el teléfono, que es donde permite buscar sin conexión. |
| `meal_items.food_id`, `meal_items.cache_food_id` | Siempre null: el cliente no las manda, y los ids de su catálogo (`usda:…`) ni siquiera son uuid. Además contradecían el diseño — el ítem es un snapshot, y un snapshot con puntero al original no es un snapshot. |
| `health_integrations`, `sync_records`, `duplicate_resolutions` | Todo lo de Health Connect es del aparato: el permiso, el cursor de importación. Una copia en la cuenta no estaría sin usar por olvido, estaría equivocada. Lo que sí es de la cuenta —los pesos y las actividades importadas— viaja por las tablas de siempre. |

**Lo que se conectó** (migración 44):

- **`meals.logged_at` → `eaten_at`.** El nombre mentía: la app arma ese valor
  con la fecha y la hora que elige la persona ("Cambiar hora" en el formulario),
  no con `now()`, y editar una comida lo conserva. Con el nombre viejo, la hora
  de la comida parecía un dato de auditoría y por eso no la usó nunca ninguna
  pantalla de análisis. El resto de las tablas se quedan con `logged_at` y hacen
  bien: ahí sí es cuándo se registró.
- **`reminders`** existía desde la migración 22 y el cliente nunca la escribió.
  No alcanzaba con nombrarla: la tabla tenía un solo horario por tipo y el
  recordatorio de agua son tres. El esquema se puso al día (`times`, en minutos
  desde medianoche) y ahora sube.
- **`exercise_templates`**, igual: existían desde la 09 y se quedaban en el
  teléfono.

Los tres agujeros —este, el de `rest_days` y el de las plantillas— tienen la
misma forma: la tabla estaba, el modelo tenía el dato, y faltaba el renglón que
los une. No se ve mirando ninguna de las dos puntas por separado, así que ahora
lo fija `supabase/tests/sync_contract_test.sql`.

### El puente que faltó, y el orden correcto (migración 45)

Renombrar `logged_at` estuvo bien. **El orden estuvo mal**: es una columna que
escribe un cliente ya desplegado, y la migración salió antes que la versión de
la app que usa el nombre nuevo. Con eso, cada teléfono que no actualizara
mandaba una columna inexistente.

Lo que hace daño no es el fallo, es que **no se ve**:

- al subir, solo el upsert de `meals` falla (42501/42703) y el resto de las
  tablas sigue viajando, así que la app se ve sana;
- al bajar, las comidas vuelven sin la columna, el parseo de cada una falla y se
  saltea sola;
- la reconciliación conserva lo local, así que **no se pierde nada** — pero nada
  nuevo llega;
- y `SyncFailed` solo aparece entrando a Ajustes → Respaldo en la nube.

Es el mismo modo de falla que ya vació esta base una vez, y está escrito en
`auth_providers.dart`: *"la app se veía perfecta mientras la base quedaba
vacía"*. La respuesta a eso no puede ser pedirle a la gente que actualice antes
de comer.

Así que `logged_at` volvió como **espejo de compatibilidad**, mantenido por un
trigger, con fecha de vencimiento escrita en el `comment` de la columna. El
nombre bueno sigue siendo `eaten_at` y es el único que usa código nuevo.

**La regla, para la próxima vez que haya que renombrar algo que el cliente
escribe:**

1. La migración deja **las dos** columnas y un trigger que las concilia.
2. Sale la versión de la app que usa el nombre nuevo.
3. Cuando no queden teléfonos con la versión vieja, una migración saca el
   espejo.

Nunca al revés, y nunca los pasos 1 y 3 juntos.

⚠️ Y el trigger no se puede guiar por "¿vino null?". El push es un upsert y
PostgREST arma el `do update set` **solo con las columnas que mandó el
cliente**, así que en un `update` la columna que el cliente no manda llega con
su valor anterior y nunca es null. El primer intento de la 45 se guiaba por eso
y **descartaba en silencio una corrección de hora hecha desde la app vieja**. Lo
que distingue quién habla es cuál de las dos se movió (`is distinct from old`).
Las cuatro combinaciones están en `sync_contract_test.sql`.

---

## Qué mirar si algo de esto se rompe

- **Aparece "0 de 30" en una cuenta nueva** → alguien calculó un denominador con
  `days` en vez de con la ventana efectiva.
- **El PDF del teléfono y el panel dicen números distintos** → se separaron las
  dos definiciones de `trackingSince`. Es una sola fórmula, en tres lugares que
  tienen que decir lo mismo.
- **Un día de descanso no aparece en otro teléfono** → volvió el bug de
  `rest_days`: fijarse que `day_markers` esté en el push y en el pull del
  cliente relacional.
- **Se agregó una tabla y no viaja** → el patrón es siempre el mismo. Tiene que
  estar en `subir()`, en `traer()`, en el documento que arma `pull`, en
  `LocalStore.toDocument`/`_restore` y —si se reconcilia por id— en
  `_timestampFields` de `document_merge.dart`. Cinco lugares; olvidarse de uno
  no rompe nada visible, que es exactamente por qué esto pasó tres veces.
