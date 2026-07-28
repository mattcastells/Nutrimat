# 17 — Acceptance Criteria

Formato Given / When / Then. Cada criterio es verificable y trazable a un test de
`16-test-plan.md`. Se agrupan por funcionalidad del MVP.

---

## AC-01 · Onboarding

```
Given que soy un usuario nuevo con la cuenta recién creada
When abro la aplicación
Then veo el paso 1 de 6 del onboarding
And no puedo llegar a Inicio sin completarlo
```

```
Given que soy mujer, tengo 30 años, mido 165 cm y peso 70 kg
And elijo nivel de actividad "ligero"
And elijo bajar 0,5 kg por semana
When llego al paso de objetivo calórico
Then veo un BMR de 1.420 kcal
And un TDEE de 1.953 kcal
And un objetivo sugerido de 1.403 kcal
And puedo cambiarlo manualmente
```

```
Given que el objetivo calculado da menos de 1.200 kcal para un perfil femenino
When se muestra el objetivo
Then la aplicación muestra 1.200 kcal
And explica "Ajustamos tu objetivo al mínimo saludable de 1.200 kcal"
```

```
Given que estoy en el paso de crédito de ejercicio
When lo veo por primera vez
Then la opción seleccionada es "No sumar"
And leo el texto "Las calorías quemadas durante el ejercicio suelen sobreestimarse.
     Podés decidir cuánto de ese gasto agregar a tu presupuesto diario."
```

## AC-02 · Estimación de ejercicio por MET  ★

```
Given que el usuario pesa 100 kg
And selecciona caminata moderada con MET 3,5
When registra una duración de 30 minutos
Then la aplicación calcula aproximadamente 184 kcal
And muestra que el resultado es estimado
And permite modificarlo antes de guardar
```

```
Given que estoy registrando una caminata de 30 minutos
When cambio la intensidad de moderada a intensa
Then el gasto estimado se recalcula con el MET vigoroso del tipo
And el valor mostrado se actualiza sin que yo tenga que guardar
```

```
Given que no tengo ningún peso registrado ni en el perfil
When abro el registro de actividad
Then no se muestra una estimación
And veo "Necesitamos tu peso para estimar" con un acceso para registrarlo
```

```
Given que los valores MET se leen del catálogo
When se actualiza el MET de "caminata" en la base de datos
Then la aplicación usa el valor nuevo sin necesidad de publicar una versión
```

## AC-03 · Corrección de calorías

```
Given que una actividad tiene 184 kcal estimadas por MET
When ingreso manualmente 210 kcal y elijo el motivo "Mi reloj marcó otra cosa"
Then la actividad guarda 210 kcal como valor vigente
And conserva 184 kcal como valor original
And el método pasa a "corregido por vos"
And el detalle muestra "≈ 210 kcal · corregido por vos (cálculo original: 184 kcal)"
And puedo restaurar el valor calculado
```

## AC-04 · Ajuste por ejercicio y balance diario  ★

```
Given que mi objetivo base es 2.100 kcal
And consumí 1.640 kcal
And registré 240 kcal de actividad
And mi crédito de ejercicio es 50 %
When abro Inicio
Then veo "Objetivo base 2.100"
And veo "Consumido 1.640"
And veo "Actividad 240 kcal (estimadas)"
And veo "Ajuste aplicado +120"
And veo "Objetivo ajustado 2.220"
And veo "Te quedan 580 kcal"
```

```
Given los mismos datos con crédito 100 %
When abro Inicio
Then el ajuste aplicado es +240
And el objetivo ajustado es 2.340
And me quedan 700 kcal
```

```
Given que mi crédito de ejercicio es 0 %
When registro una actividad
Then mi objetivo ajustado sigue siendo igual al objetivo base
And la fila "Ajuste aplicado" no se muestra
And veo el texto "El ejercicio no suma a tu presupuesto · Cambiar"
```

```
Given que desactivo completamente el ajuste por ejercicio
When vuelvo a Inicio
Then las calorías de actividad se siguen mostrando en la sección Actividad
And no afectan de ninguna manera las calorías restantes
```

```
Given que hoy registré actividades con crédito 0 %
When cambio el crédito a 50 %
Then las actividades de hoy recalculan su aporte a 50 %
And las actividades de días anteriores conservan el porcentaje con el que se guardaron
And la aplicación me avisa "Aplicamos el cambio desde hoy"
```

## AC-05 · Transparencia del cálculo

```
Given que estoy en Inicio
When toco "¿Cómo se calcula?"
Then veo la fórmula "objetivo ajustado = objetivo base + calorías de ejercicio aplicadas"
And veo "calorías restantes = objetivo ajustado − calorías consumidas"
And veo cada término con el valor real del día
And puedo ir directo a cambiar el crédito de ejercicio
```

```
Given cualquier actividad en cualquier pantalla
When veo sus calorías
Then siempre aparecen precedidas por "≈"
And siempre indican el método de estimación
And nunca se presentan como una medición exacta
```

## AC-06 · Registro rápido de ejercicio

```
Given que abro el registro rápido desde el botón principal
When elijo "Caminata", 30 minutos e intensidad moderada
And toco Guardar
Then la actividad queda registrada en el día actual
And vuelvo a la pantalla desde la que empecé
And veo un aviso "Actividad guardada" con acción "Ver"
And todo el recorrido me tomó menos de 15 segundos
```

```
Given que registro una actividad que se solapa con otra ya existente del mismo tipo
When toco Guardar
Then la aplicación me advierte "Ya tenés una actividad en ese horario. ¿Es otra distinta?"
And puedo guardar igual o revisar
And nunca se borra nada automáticamente
```

## AC-07 · Entrenamiento de fuerza

```
Given que elijo "Entrenamiento de fuerza"
When cargo nombre, duración, intensidad y notas
Then la sesión se guarda como una actividad de tipo fuerza
And veo el aviso "Series y repeticiones llegan en una próxima versión"
And el modelo de datos permite agregar ejercicios y series después sin migrar lo existente
```

## AC-08 · Importación desde Health Connect

```
Given que no conecté ninguna integración de salud
When uso la aplicación
Then puedo registrar comidas, ejercicio, peso y ver mi progreso sin ninguna limitación
```

```
Given que voy a conectar Health Connect
When toco "Conectar"
Then antes del diálogo del sistema veo una explicación de cada permiso y para qué se usa
```

```
Given que conecté Health Connect
When se ejecuta la sincronización
Then solo se traen los registros posteriores a la última sincronización
And cada actividad importada muestra "Importado · Health Connect"
And se guarda la fecha de la última sincronización
```

```
Given que edité manualmente las calorías de una actividad importada
When esa actividad se vuelve a importar
Then mi valor no se sobrescribe
And la sincronización registra que se omitió por edición del usuario
```

```
Given que una actividad importada no trae calorías activas válidas
When se procesa
Then la aplicación la recalcula por MET
And marca el método como "recalculado"
```

```
Given que desconecto una integración
When confirmo
Then puedo elegir conservar o borrar los datos ya importados
And mis registros manuales nunca se tocan
```

## AC-09 · Prevención de doble conteo  ★

```
Given que registré manualmente una caminata de 30 minutos a las 11:00
And Health Connect aporta una caminata de 32 minutos a las 11:00
When se ejecuta la sincronización
Then la aplicación detecta un posible duplicado
And me muestra las dos versiones comparadas
And me deja elegir cuál conservar o conservar ambas
And no borra ninguna de las dos por su cuenta
```

```
Given que la misma sesión llega dos veces del mismo proveedor
When se procesa la segunda
Then no se crea un registro nuevo
And si el proveedor cambió el dato, el existente se actualiza
```

```
Given que no resuelvo un posible duplicado
When vuelvo a Inicio
Then la actividad aparece con la marca "Revisar"
And puedo resolverla más tarde
```

## AC-10 · Registro de comida por foto

```
Given que saco una foto de un plato
When el análisis termina
Then veo la pantalla de revisión con los alimentos detectados
And veo el aviso "Estimación de IA — revisá antes de guardar"
And cada alimento muestra su nivel de confianza con texto, no solo con color
And no se guarda nada hasta que yo confirmo
```

```
Given que un alimento detectado tiene confianza baja
When veo la revisión
Then su campo de cantidad aparece resaltado para que lo revise
```

```
Given que corrijo dos ítems y elimino uno
When guardo
Then la comida guarda mis valores corregidos
And el análisis original queda registrado junto con el diff de mis correcciones
```

```
Given que no tengo conexión
When saco una foto de una comida
Then la foto queda guardada y encolada
And veo "Foto pendiente de análisis" con acción para reintentar
And puedo cargar la comida a mano mientras tanto
```

## AC-11 · Historial

```
Given que tengo registros de los últimos 30 días
When abro Historial
Then cada día muestra calorías consumidas, calorías de actividad, calorías aplicadas
     al objetivo, duración total de ejercicio y cantidad de actividades
And muestra los pasos si hay información disponible
```

```
Given que aplico el filtro "solo ejercicio"
When veo la lista
Then no aparece información de comidas
And puedo limpiar el filtro con una sola acción
```

## AC-12 · Progreso de actividad

```
Given que registré actividad en 4 de los últimos 7 días
When abro el progreso de actividad
Then leo "Registraste actividad durante 4 de los últimos 7 días"
And el mensaje no me culpabiliza ni menciona rachas rotas
```

```
Given que esta semana acumulé 130 minutos y la semana pasada 105
When veo el progreso
Then leo "Esta semana acumulaste 130 minutos de actividad"
And leo la comparación con la semana anterior en términos neutrales
```

```
Given que marqué un día como descanso planificado
When se calculan los días con actividad
Then ese día no cuenta como un día sin actividad
And ningún mensaje me penaliza por descansar
```

## AC-13 · Objetivos de actividad

```
Given que no configuré ningún objetivo de actividad
When uso la aplicación
Then no se me exige configurarlo
And no aparece ninguna advertencia por no tenerlo
```

```
Given que configuré 150 minutos activos por semana y llevo 130
When veo el objetivo
Then veo el progreso 130 de 150
And ese progreso se muestra separado del objetivo calórico
And no cumplirlo no reduce mis calorías permitidas
```

## AC-14 · Peso

```
Given que hoy ya registré 99,2 kg
When registro 99,5 kg el mismo día
Then se actualiza el registro de hoy en lugar de crear uno nuevo
And la aplicación me avisa que actualizó el peso de hoy
```

```
Given que registré un peso nuevo
When vuelvo a registrar una actividad
Then la estimación por MET usa el peso más reciente
```

## AC-15 · Sin conexión

```
Given que no tengo conexión
When registro una comida, una actividad y un peso
Then los tres quedan guardados y visibles de inmediato
And cada uno muestra que está pendiente de sincronizar
And al recuperar la conexión se sincronizan sin duplicarse
```

```
Given que una operación falla por un error del servidor
When reintento automáticamente
Then mi registro no se pierde ni desaparece de la pantalla
And si el error es de validación, se revierte y se me explica por qué
```

## AC-16 · Cambio de objetivo

```
Given que mi objetivo vigente es 2.100 kcal
When lo cambio a 1.900 kcal
Then desde hoy rige 1.900
And los días anteriores conservan 2.100 en el historial
```

## AC-17 · Privacidad y eliminación de cuenta

```
Given que quiero eliminar mi cuenta
When entro al flujo de eliminación
Then veo la lista explícita de lo que se borra
And se me ofrece exportar mis datos antes
And debo reautenticarme y escribir ELIMINAR para confirmar
```

```
Given que confirmé la eliminación
When inicio sesión dentro de los 7 días
Then se me avisa la fecha de eliminación
And puedo cancelarla
```

```
Given que pasaron los 7 días
When se ejecuta el borrado
Then no queda ningún dato mío en la base ni en el almacenamiento de archivos
```

## AC-18 · Accesibilidad

```
Given que uso un lector de pantalla
When recorro la tarjeta principal de Inicio
Then escucho "Te quedan 580 calorías de 2.220"
And cada fila del desglose se lee como etiqueta y valor
```

```
Given que tengo el tamaño de texto al 200 %
When abro cualquier pantalla
Then no se corta ningún contenido
And puedo completar todos los flujos
```

```
Given que tengo activada la reducción de movimiento
When navego entre pantallas
Then no hay animaciones de desplazamiento
And ninguna información se pierde por eso
```

## AC-19 · Tono del producto

```
Given que me pasé del objetivo calórico
When veo Inicio
Then leo "Te pasaste por 120 kcal" en tono neutral
And el color usado no es el de error
And no aparece ningún mensaje de culpa ni de fracaso
```

```
Given cualquier pantalla de la aplicación
When leo los textos
Then no hay lenguaje que moralice la comida ni castigue días sin registro
```
