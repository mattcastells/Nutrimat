import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../core/utils/dates.dart';
import '../local/local_store.dart';

/// Sube y baja los datos del usuario **como filas**, en las tablas del
/// esquema, además del documento JSON del respaldo.
///
/// ## Por qué existe
///
/// Hasta acá todo colgaba de un único documento en Storage. Eso alcanzaba para
/// no perder nada y cambiar de teléfono, pero:
///
/// - Viaja **entero en cada cambio**. Anotar un vaso de agua subía el
///   documento completo, que ya pasó de 38 a 81 kB en un día.
/// - Es todo o nada: si se corrompe, se pierde junto.
/// - El servidor no puede leer nada adentro. Estadísticas, resúmenes o que un
///   pal vea algo real son imposibles contra un blob opaco.
///
/// ## Cómo convive con el respaldo
///
/// Los dos caminos escriben, y **ya se dio vuelta**: mandan las tablas y el
/// documento es la copia con la que trabaja cada dispositivo. Al entrar y al
/// volver a la app se traen las filas y se reconcilian contra lo local
/// (`document_merge.dart`); el respaldo del documento entero al bucket quedó
/// como red de seguridad, no como fuente. El comentario anterior describía el
/// paso previo, cuando esto todavía se estaba verificando.
///
/// ## Lo que hay que saber del esquema
///
/// `activities.activity_type_id` tiene **clave foránea** a `activity_types`,
/// cuyos ids los generó el servidor. El catálogo que viaja en el APK no trae
/// esos ids —solo el `slug`— así que hay que mapear por slug antes de
/// insertar. Y los tipos que crea la persona no existen del lado del servidor:
/// esas actividades se apoyan en el tipo `custom` y conservan el nombre en
/// `custom_name`, que es lo que la app muestra igual.
class RelationalSyncClient {
  RelationalSyncClient(this._db);

  factory RelationalSyncClient.fromInstance() =>
      RelationalSyncClient(Supabase.instance.client);

  final SupabaseClient _db;

  /// Corto: es trabajo de fondo y no puede quedar colgado ocupando la red.
  static const Duration timeout = Duration(seconds: 30);

  /// `slug` → id remoto de `activity_types`. Se resuelve una vez por sesión:
  /// el catálogo lo siembra una migración y no cambia entre corridas.
  Map<String, String>? _typeIdBySlug;

  Future<Map<String, String>> _activityTypeIds() async {
    final cached = _typeIdBySlug;
    if (cached != null) return cached;

    final rows = await _db
        .from('activity_types')
        .select('id, slug')
        .timeout(timeout);
    final map = <String, String>{
      for (final row in rows)
        row['slug'] as String: row['id'] as String,
    };
    _typeIdBySlug = map;
    return map;
  }

  /// Escribe todo el contenido del usuario como filas.
  ///
  /// Es un *upsert* completo, no un diff: para el volumen de una persona
  /// —cientos de filas— es más barato y muchísimo más simple de razonar que
  /// llevar un registro de cambios, y no puede quedar desincronizado.
  ///
  /// Devuelve cuántas filas se escribieron por tabla, que es lo que permite
  /// verificar contra el documento sin adivinar.
  Future<Map<String, int>> push({
    required String userId,
    required LocalStore store,
  }) async {
    final escritas = <String, int>{};

    /// Las tablas que fallaron, con el motivo. Se juntan en vez de cortar.
    final fallaron = <String, String>{};

    /// Sube una tabla y **se queda con su fallo**.
    ///
    /// Antes las once tablas compartían un `try`: la primera que fallaba
    /// abortaba el método y las que venían después no se intentaban siquiera.
    /// Fue lo que convirtió una restricción desactualizada en una base sin una
    /// sola comida — `body_measurements` es la cuarta de once, y con ella se
    /// perdieron las siete que le siguen.
    ///
    /// Ahora cada tabla se juega su suerte sola. Al final se lanza igual, con
    /// los nombres de las que fallaron, pero lo que sí entró queda escrito.
    ///
    /// [onConflict] nombra la clave contra la que se resuelve el choque. Sin
    /// él, el upsert resuelve **contra la primary key**, y eso alcanza solo
    /// mientras el id sea la única forma de que dos filas se pisen.
    Future<void> subir(
      String tabla,
      List<Map<String, dynamic>> filas, {
      String? onConflict,
    }) async {
      if (filas.isEmpty) {
        escritas[tabla] = 0;
        return;
      }
      try {
        await _db
            .from(tabla)
            .upsert(filas, onConflict: onConflict)
            .timeout(timeout);
        escritas[tabla] = filas.length;
      } on PostgrestException catch (error) {
        escritas[tabla] = 0;
        fallaron[tabla] = error.message;
      } on TimeoutException {
        escritas[tabla] = 0;
        fallaron[tabla] = 'tardó demasiado';
      } on Exception catch (error) {
        escritas[tabla] = 0;
        fallaron[tabla] = error.toString();
      }
    }

    try {
      // El perfil primero: todo lo demás lo referencia por `user_id`.
      final profile = store.profile;
      if (profile != null) {
        await _db
            .from('profiles')
            .upsert(<String, dynamic>{
              'id': userId,
              'display_name': profile.displayName,
              'biological_sex': profile.biologicalSex.wire,
              'birth_date': profile.birthDate == null
                  ? null
                  : isoDate(profile.birthDate!),
              'height_cm': profile.heightCm,
              'activity_level': profile.activityLevel.wire,
              'timezone': profile.timezone,
              'unit_system': profile.unitSystem.wire,
              'theme_mode': profile.themeMode.wire,
              'locale': profile.locale,
              'exercise_credit_percentage': profile.exerciseCreditPercentage,
              'exercise_credit_enabled': profile.exerciseCreditEnabled,
              'show_net_calories': profile.showNetCalories,
            })
            .timeout(timeout);
        escritas['profiles'] = 1;
      }

      await subir('goals', <Map<String, dynamic>>[
        for (final g in store.goals)
          <String, dynamic>{
            'id': g.id,
            'user_id': userId,
            'goal_type': g.goalType.wire,
            'rate_kg_per_week': g.rateKgPerWeek,
            'target_weight_kg': g.targetWeightKg,
            'base_calorie_target': g.baseCalorieTarget,
            'target_method': g.targetMethod.wire,
            'bmr_kcal': g.bmrKcal,
            'tdee_kcal': g.tdeeKcal,
            'protein_g': g.proteinG,
            'carbs_g': g.carbsG,
            'fat_g': g.fatG,
            'macro_method': g.macroMethod,
            'starts_on': isoDate(g.startsOn),
            'ends_on': g.endsOn == null ? null : isoDate(g.endsOn!),
            'updated_at': (g.updatedAt ?? DateTime.now())
                .toUtc()
                .toIso8601String(),
          },
      ]);

      await subir('weight_logs', <Map<String, dynamic>>[
        for (final w in store.weightLogs)
          <String, dynamic>{
            'id': w.id,
            'user_id': userId,
            'weight_kg': w.weightKg,
            'local_date': isoDate(w.localDate),
            'logged_at': w.loggedAt.toUtc().toIso8601String(),
            'source': w.source,
            'notes': w.notes,
            // A diferencia de comidas/actividades (que simplemente dejan de
            // subirse al borrarse), el peso sí escribe `deleted_at`: es lo que
            // permite que un borrado sobreviva a un restore en otro teléfono.
            'deleted_at': w.deletedAt?.toUtc().toIso8601String(),
          },
      ]);

      await subir('body_measurements', <Map<String, dynamic>>[
        for (final m in store.measurements)
          <String, dynamic>{
            'id': m.id,
            'user_id': userId,
            'metric': m.metric.wire,
            'value': m.value,
            'unit': m.metric.unit,
            'local_date': isoDate(m.localDate),
            'notes': m.notes,
            // La lápida viaja: sin esto, borrar una medida la sacaba del
            // teléfono y la dejaba viva en la tabla, y la reconciliación
            // siguiente la traía de vuelta. Y `updated_at` es lo que le
            // permite ganar el desempate a la corrección más reciente.
            'updated_at': (m.updatedAt ?? DateTime.now())
                .toUtc()
                .toIso8601String(),
            'deleted_at': m.deletedAt?.toUtc().toIso8601String(),
          },
      ]);

      // El agua y el sueño **no se resuelven por id**: ver `_unaPorDia` y el
      // comentario de `onConflict` de arriba. Las dos tablas tienen una segunda
      // clave única `(user_id, local_date)`, y esa es la que manda.
      await subir(
        'water_logs',
        <Map<String, dynamic>>[
          for (final w in _unaPorDia(
            store.waterLogs,
            (w) => w.localDate,
            (w) => w.updatedAt,
          ))
            <String, dynamic>{
              'id': w.id,
              'user_id': userId,
              'local_date': isoDate(w.localDate),
              'glasses': w.glasses,
            },
        ],
        onConflict: 'user_id,local_date',
      );

      await subir(
        'sleep_logs',
        <Map<String, dynamic>>[
          for (final s in _unaPorDia(
            store.sleepLogs,
            (s) => s.localDate,
            (s) => s.loggedAt,
          ))
            <String, dynamic>{
              'id': s.id,
              'user_id': userId,
              'local_date': isoDate(s.localDate),
              'minutes': s.minutes,
              'quality': s.quality.wire,
              'logged_at': s.loggedAt.toUtc().toIso8601String(),
              'notes': s.notes,
              'deleted_at': s.deletedAt?.toUtc().toIso8601String(),
            },
        ],
        onConflict: 'user_id,local_date',
      );

      await subir('activity_goals', <Map<String, dynamic>>[
        for (final g in store.activityGoals)
          <String, dynamic>{
            'id': g.id,
            'user_id': userId,
            'goal_type': g.goalType.wire,
            'target_value': g.targetValue,
            'unit': g.goalType.unit,
            'period': g.period.wire,
            'start_date': isoDate(g.startDate),
            'end_date': g.endDate == null ? null : isoDate(g.endDate!),
            'enabled': g.enabled,
          },
      ]);

      await subir('foods', <Map<String, dynamic>>[
        for (final f in store.userFoods)
          <String, dynamic>{
            'id': f.id,
            'user_id': userId,
            'name': f.name,
            'brand': f.brand,
            'barcode': f.barcode,
            'serving_size': f.servingSize,
            'serving_unit': f.servingUnit,
            'kcal': f.kcal,
            'protein_g': f.proteinG,
            'carbs_g': f.carbsG,
            'fat_g': f.fatG,
            'is_favorite': f.isFavorite,
            'source': 'user',
          },
      ]);

      // Las comidas antes que sus ítems: `meal_items.meal_id` es FK.
      //
      // Las borradas **también suben**, con su lápida. Antes se filtraban con
      // `if (!m.isDeleted)`, así que un borrado se quedaba en el teléfono: la
      // fila seguía viva en la tabla, y como las tablas son la fuente de
      // verdad, la comida volvía entera en un teléfono nuevo o en la web — con
      // la foto ya purgada del bucket, o sea con `photo_path` roto. De paso,
      // `purge_soft_deleted` sobre `meals` era un no-op perpetuo: nunca había
      // una fila con `deleted_at`, así que el servidor se quedaba para siempre
      // con lo que alguien había pedido borrar.
      await subir('meals', <Map<String, dynamic>>[
        for (final m in store.meals)
          <String, dynamic>{
            'id': m.id,
            'user_id': userId,
            'slot': m.slot.wire,
            'logged_at': m.loggedAt.toUtc().toIso8601String(),
            'local_date': isoDate(m.localDate),
            'name': m.name,
            'total_kcal': m.totalKcal,
            'total_protein_g': m.totalProteinG,
            'total_carbs_g': m.totalCarbsG,
            'total_fat_g': m.totalFatG,
            'source': m.source.wire,
            'photo_path': m.photoPath,
            'notes': m.notes,
            'is_favorite': m.isFavorite,
            // El vínculo con el análisis de IA no viajaba, así que cada vez
            // que la reconciliación traía una comida de vuelta se perdía sin
            // que nada lo dijera.
            'ai_analysis_id': m.aiAnalysisId,
            'updated_at': m.updatedAt.toUtc().toIso8601String(),
            'deleted_at': m.deletedAt?.toUtc().toIso8601String(),
          },
      ]);

      await subir('meal_items', <Map<String, dynamic>>[
        for (final m in store.meals)
          if (!m.isDeleted)
            for (final i in m.items)
              <String, dynamic>{
                'id': i.id,
                'meal_id': m.id,
                'name': i.name,
                'quantity': i.quantity,
                'unit': i.unit,
                'kcal': i.kcal,
                'protein_g': i.proteinG,
                'carbs_g': i.carbsG,
                'fat_g': i.fatG,
                'ai_confidence': i.aiConfidence,
                'was_ai_corrected': i.wasAiCorrected,
                'position': i.position,
                // `food_id` queda en null a propósito: apunta a `foods`, y los
                // ítems que salen del catálogo externo o de la IA no tienen
                // una fila propia ahí. El nombre y los macros son un snapshot,
                // así que la comida se reconstruye igual.
              },
      ]);

      // Las actividades al final: necesitan el mapa de tipos.
      final tipos = await _activityTypeIds();
      final custom = tipos['custom'];
      final actividades = <Map<String, dynamic>>[];
      for (final a in store.activities) {
        // Las borradas suben con su lápida, por lo mismo que las comidas: un
        // borrado que no llega al servidor no es un borrado, es un borrado en
        // este teléfono.
        final tipoLocal = store.typeById(a.activityTypeId);
        // Un tipo creado por la persona no existe del lado del servidor: la
        // actividad se apoya en `custom` y el nombre viaja en `custom_name`,
        // que es lo que la app muestra igual.
        final remoteTypeId = tipos[tipoLocal?.slug] ?? custom;
        if (remoteTypeId == null) continue;

        actividades.add(<String, dynamic>{
          'id': a.id,
          'user_id': userId,
          'activity_type_id': remoteTypeId,
          'custom_name': a.customName ?? tipoLocal?.displayName,
          'started_at': a.startedAt.toUtc().toIso8601String(),
          'ended_at': a.endedAt?.toUtc().toIso8601String(),
          'local_date': isoDate(a.localDate),
          'duration_minutes': a.durationMinutes,
          'intensity': a.intensity.wire,
          'distance_meters': a.distanceMeters,
          'steps': a.steps,
          'estimated_calories': a.estimatedCalories,
          'original_calories': a.originalCalories,
          'applied_calories': a.appliedCalories,
          'exercise_credit_percentage': a.exerciseCreditPercentage,
          'estimation_method': a.estimationMethod.wire,
          'met_value': a.metValue,
          'weight_kg_used': a.weightKgUsed,
          'override_reason': a.overrideReason,
          'source_type': a.sourceType.wire,
          'notes': a.notes,
          'is_favorite': a.isFavorite,
          'updated_at': a.updatedAt.toUtc().toIso8601String(),
          'deleted_at': a.deletedAt?.toUtc().toIso8601String(),
        });
      }
      await subir('activities', actividades);

      // Lo que entró, entró. Pero una tabla que no sube es un dato de alguien
      // que no está en la base, así que esto **tiene** que llegar a la pantalla
      // en vez de quedar en un log: el mensaje nombra las tablas.
      if (fallaron.isNotEmpty) {
        final detalle = fallaron.entries
            .map((e) => '${e.key}: ${e.value}')
            .join('; ');
        throw AppError(
          code: ApiErrorCode.server,
          message: 'No pudimos guardar ${fallaron.keys.join(', ')} en la base '
              '($detalle).',
          requestId: fallaron.keys.join(','),
        );
      }

      return escritas;
    } on AppError {
      // Va **primero** y no es decorativo: `AppError implements Exception`, así
      // que sin esta rama el error de arriba —el que nombra las tablas que no
      // subieron y por qué— lo atrapaba el `on Exception` de abajo y salía como
      // "Sin conexión: se guarda cuando vuelva internet".
      //
      // Eso no era un mensaje impreciso, era uno que mentía en las dos mitades:
      // no había problema de conexión, y no se iba a guardar cuando volviera
      // internet porque internet nunca se había ido. Con el respaldo en archivo
      // subiendo bien al lado, la pantalla decía "sin conexión" mientras
      // acababa de subir 176 kB.
      //
      // El resultado es que una tabla podía dejar de sincronizar durante días
      // sin que nada dijera cuál ni por qué, que es exactamente el fallo
      // silencioso que el resto de este archivo se esfuerza en evitar.
      rethrow;
    } on PostgrestException catch (error) {
      throw AppError(
        code: ApiErrorCode.server,
        message: 'No pudimos guardar en la base (${error.message}).',
        requestId: error.code,
      );
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: 'La base tardó demasiado. Se reintenta con el próximo cambio.',
      );
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'Sin conexión: se guarda en la base cuando vuelva internet.',
      );
    }
  }

  /// Trae todo lo del usuario **desde las tablas** y lo devuelve con la forma
  /// del documento local.
  ///
  /// Devolver la misma forma que `LocalStore.toDocument()` no es capricho: así
  /// lo consume `restoreDocument`, que ya sabe leer de manera tolerante —un
  /// registro raro se saltea y el resto sobrevive—. Un segundo lector sería un
  /// segundo lugar donde equivocarse.
  ///
  /// Devuelve `null` si la base no tiene nada de este usuario, para que quien
  /// llame pueda distinguir "no hay" de "vino vacío".
  Future<Map<String, dynamic>?> pull({
    required String userId,
    required LocalStore store,
  }) async {
    try {
      final perfil = await _db
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle()
          .timeout(timeout);
      if (perfil == null) return null;

      /// Trae una tabla entera, de a páginas.
      ///
      /// PostgREST corta en `max_rows` (1000 por omisión) **sin decir nada**:
      /// no es un error, es un límite, así que una consulta plana devuelve las
      /// primeras mil filas y parece completa. A cuatro comidas por día con
      /// tres ítems cada una, `meal_items` cruza esa marca en unos tres meses
      /// de uso — y desde ahí cada reconciliación reconstruía las comidas con
      /// ítems faltantes contra una base que es la fuente de verdad.
      ///
      /// El orden por `id` es lo que hace que paginar sea correcto: sin un
      /// orden estable, dos páginas pueden repetir y saltear filas.
      Future<List<Map<String, dynamic>>> traer(String tabla) async {
        const tamano = 500;
        final todo = <Map<String, dynamic>>[];
        for (var desde = 0; ; desde += tamano) {
          final pagina = await _db
              .from(tabla)
              .select()
              .eq('user_id', userId)
              .order('id')
              .range(desde, desde + tamano - 1)
              .timeout(timeout);
          todo.addAll(pagina.cast<Map<String, dynamic>>());
          if (pagina.length < tamano) break;
        }
        return todo;
      }

      final goals = await traer('goals');
      final meals = await traer('meals');
      final activities = await traer('activities');
      final weightLogs = await traer('weight_logs');
      final measurements = await traer('body_measurements');
      final waterLogs = await traer('water_logs');
      final sleepLogs = await traer('sleep_logs');
      final activityGoals = await traer('activity_goals');
      final foods = await traer('foods');

      // Sin ninguna fila de contenido no hay nada que traer: devolver un
      // documento vacío haría que la app pisara lo local con nada, que es
      // exactamente el modo de falla que ya conocemos.
      final hayContenido = meals.isNotEmpty ||
          activities.isNotEmpty ||
          weightLogs.isNotEmpty ||
          measurements.isNotEmpty ||
          waterLogs.isNotEmpty ||
          sleepLogs.isNotEmpty ||
          foods.isNotEmpty;
      if (!hayContenido) return null;

      // Los ítems, de a tandas de comidas.
      //
      // Antes se pedían todos de una con un `inFilter` sobre la lista completa
      // de ids. PostgREST codifica eso como `in.(...)` en el **query string**
      // de un GET, así que la URL crece con el historial: un año de uso son
      // ~1.400 uuids, más de 50 kB de URL, bastante por encima de lo que
      // aceptan los proxies. El pull entero fallaba, `refresh` devolvía false
      // en silencio y el teléfono dejaba de reconciliar — justo en las cuentas
      // con más datos, que son las que más lo necesitan.
      final itemsPorComida = <String, List<Map<String, dynamic>>>{};
      const porTanda = 200;
      final idsDeComidas = meals.map((m) => m['id'] as String).toList();
      for (var i = 0; i < idsDeComidas.length; i += porTanda) {
        final tanda = idsDeComidas.sublist(
          i,
          i + porTanda > idsDeComidas.length ? idsDeComidas.length : i + porTanda,
        );
        final items = await _db
            .from('meal_items')
            .select()
            .inFilter('meal_id', tanda)
            .timeout(timeout);
        for (final item in items) {
          (itemsPorComida[item['meal_id'] as String] ??=
                  <Map<String, dynamic>>[])
              .add(item);
        }
      }

      // Del id remoto de tipo al id local, pasando por el slug: son dos
      // catálogos distintos que solo comparten esa clave.
      final tipos = await _activityTypeIds();
      final slugPorId = <String, String>{
        for (final e in tipos.entries) e.value: e.key,
      };

      /// Un `timestamptz` de PostgREST, pasado a la hora local del teléfono.
      ///
      /// Vuelven en UTC (`2026-07-31T16:30:00+00:00`) y el documento guarda las
      /// fechas en hora local y sin desfase, que es lo que escribe la app. Sin
      /// convertir acá, `DateTime.parse` dejaba un `DateTime` en UTC y las
      /// pantallas lo formateaban tal cual: **un almuerzo registrado 13:30 se
      /// mostraba 16:30** en cuanto la reconciliación traía esa comida de
      /// vuelta. Y `duplicateMeal` copiaba esa hora corrida a la comida nueva.
      String isoOf(Object? v) {
        if (v == null) return '';
        final parsed = DateTime.tryParse(v.toString());
        return parsed == null ? v.toString() : parsed.toLocal().toIso8601String();
      }

      return <String, dynamic>{
        'schemaVersion': LocalStore.schemaVersion,
        'profile': <String, dynamic>{
          'id': userId,
          'displayName': perfil['display_name'],
          'biologicalSex': perfil['biological_sex'],
          'birthDate': perfil['birth_date'] == null
              ? null
              : '${perfil['birth_date']}T00:00:00.000',
          'heightCm': perfil['height_cm'],
          'activityLevel': perfil['activity_level'],
          'timezone': perfil['timezone'],
          'unitSystem': perfil['unit_system'],
          'themeMode': perfil['theme_mode'],
          'locale': perfil['locale'],
          'exerciseCreditPercentage': perfil['exercise_credit_percentage'],
          'exerciseCreditEnabled': perfil['exercise_credit_enabled'],
          'showNetCalories': perfil['show_net_calories'],
          'isDemo': false,
          'createdAt': isoOf(perfil['created_at']),
          'updatedAt': isoOf(perfil['updated_at']),
        },
        'goals': <Map<String, dynamic>>[
          for (final g in goals)
            <String, dynamic>{
              'id': g['id'],
              'goalType': g['goal_type'],
              'rateKgPerWeek': g['rate_kg_per_week'],
              'targetWeightKg': g['target_weight_kg'],
              'baseCalorieTarget': g['base_calorie_target'],
              'targetMethod': g['target_method'],
              'bmrKcal': g['bmr_kcal'],
              'tdeeKcal': g['tdee_kcal'],
              'proteinG': g['protein_g'],
              'carbsG': g['carbs_g'],
              'fatG': g['fat_g'],
              'macroMethod': g['macro_method'],
              'startsOn': g['starts_on'],
              'endsOn': g['ends_on'],
              'updatedAt': isoOf(g['updated_at']),
            },
        ],
        'meals': <Map<String, dynamic>>[
          for (final m in meals)
            <String, dynamic>{
              'id': m['id'],
              'slot': m['slot'],
              'loggedAt': isoOf(m['logged_at']),
              'localDate': m['local_date'],
              'name': m['name'],
              'source': m['source'],
              'photoPath': m['photo_path'],
              'notes': m['notes'],
              'isFavorite': m['is_favorite'],
              'aiAnalysisId': m['ai_analysis_id'],
              'syncStatus': 'synced',
              'createdAt': isoOf(m['created_at']),
              'updatedAt': isoOf(m['updated_at']),
              // Sin mapear la lápida, una comida borrada desde otro
              // dispositivo volvía viva en cada reconciliación.
              'deletedAt': m['deleted_at'] == null
                  ? null
                  : isoOf(m['deleted_at']),
              'items': <Map<String, dynamic>>[
                for (final i
                    in (itemsPorComida[m['id']] ?? const <Map<String, dynamic>>[]))
                  <String, dynamic>{
                    'id': i['id'],
                    'name': i['name'],
                    'quantity': i['quantity'],
                    'unit': i['unit'],
                    'kcal': i['kcal'],
                    'proteinG': i['protein_g'],
                    'carbsG': i['carbs_g'],
                    'fatG': i['fat_g'],
                    'aiConfidence': i['ai_confidence'],
                    'wasAiCorrected': i['was_ai_corrected'],
                    'position': i['position'],
                  },
              ],
            },
        ],
        'activities': <Map<String, dynamic>>[
          for (final a in activities)
            if (store.typeBySlug(slugPorId[a['activity_type_id']] ?? '') != null)
              <String, dynamic>{
                'id': a['id'],
                'activityTypeId': store
                    .typeBySlug(slugPorId[a['activity_type_id']] ?? '')!
                    .id,
                'customName': a['custom_name'],
                'startedAt': isoOf(a['started_at']),
                'endedAt': a['ended_at'] == null ? null : isoOf(a['ended_at']),
                'localDate': a['local_date'],
                'durationMinutes': a['duration_minutes'],
                'intensity': a['intensity'],
                'distanceMeters': a['distance_meters'],
                'steps': a['steps'],
                'estimatedCalories': a['estimated_calories'],
                'originalCalories': a['original_calories'],
                'appliedCalories': a['applied_calories'],
                'exerciseCreditPercentage': a['exercise_credit_percentage'],
                'estimationMethod': a['estimation_method'],
                'metValue': a['met_value'],
                'weightKgUsed': a['weight_kg_used'],
                'overrideReason': a['override_reason'],
                'sourceType': a['source_type'],
                'notes': a['notes'],
                'isFavorite': a['is_favorite'],
                'syncStatus': 'synced',
                'createdAt': isoOf(a['created_at']),
                'updatedAt': isoOf(a['updated_at']),
                'deletedAt': a['deleted_at'] == null
                    ? null
                    : isoOf(a['deleted_at']),
              },
        ],
        'weightLogs': <Map<String, dynamic>>[
          for (final w in weightLogs)
            <String, dynamic>{
              'id': w['id'],
              'weightKg': w['weight_kg'],
              'localDate': w['local_date'],
              'loggedAt': isoOf(w['logged_at']),
              'source': w['source'],
              'notes': w['notes'],
              'syncStatus': 'synced',
              'deletedAt': w['deleted_at'] == null
                  ? null
                  : isoOf(w['deleted_at']),
            },
        ],
        'measurements': <Map<String, dynamic>>[
          for (final m in measurements)
            <String, dynamic>{
              'id': m['id'],
              'metric': m['metric'],
              'value': m['value'],
              'localDate': m['local_date'],
              'notes': m['notes'],
              'updatedAt': isoOf(m['updated_at']),
              'deletedAt': m['deleted_at'] == null
                  ? null
                  : isoOf(m['deleted_at']),
            },
        ],
        'waterLogs': <Map<String, dynamic>>[
          for (final w in waterLogs)
            <String, dynamic>{
              'id': w['id'],
              'localDate': w['local_date'],
              'glasses': w['glasses'],
              'updatedAt': isoOf(w['updated_at']),
              'syncStatus': 'synced',
            },
        ],
        'sleepLogs': <Map<String, dynamic>>[
          for (final s in sleepLogs)
            <String, dynamic>{
              'id': s['id'],
              'localDate': s['local_date'],
              'minutes': s['minutes'],
              'quality': s['quality'],
              'loggedAt': isoOf(s['logged_at']),
              'notes': s['notes'],
              'syncStatus': 'synced',
              'deletedAt': s['deleted_at'] == null
                  ? null
                  : isoOf(s['deleted_at']),
            },
        ],
        'activityGoals': <Map<String, dynamic>>[
          for (final g in activityGoals)
            <String, dynamic>{
              'id': g['id'],
              'goalType': g['goal_type'],
              'targetValue': (g['target_value'] as num).toInt(),
              'period': g['period'],
              'startDate': g['start_date'],
              'endDate': g['end_date'],
              'enabled': g['enabled'],
            },
        ],
        'userFoods': <Map<String, dynamic>>[
          for (final f in foods)
            <String, dynamic>{
              'id': f['id'],
              'name': f['name'],
              'brand': f['brand'],
              'barcode': f['barcode'],
              'source': 'user',
              'servingSize': f['serving_size'],
              'servingUnit': f['serving_unit'],
              'kcal': f['kcal'],
              'proteinG': f['protein_g'],
              'carbsG': f['carbs_g'],
              'fatG': f['fat_g'],
              'isFavorite': f['is_favorite'],
            },
        ],
      };
    } on AppError {
      // Por lo mismo que en `push`: un `AppError` que naciera acá adentro se
      // convertiría en "sin conexión" y perdería lo que sabía.
      rethrow;
    } on PostgrestException catch (error) {
      throw AppError(
        code: ApiErrorCode.server,
        message: 'No pudimos leer tus datos de la base (${error.message}).',
      );
    } on TimeoutException {
      throw const AppError(
        code: ApiErrorCode.upstreamTimeout,
        message: 'La base tardó demasiado en responder.',
      );
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'Sin conexión: no pudimos traer tus datos de la base.',
      );
    }
  }

  // `counts` se fue junto con el botón de Comparar que lo usaba: nueve
  // consultas contra el servidor cuyo único destino era una pantalla que le
  // pedía a quien usa la app que interpretara dos columnas de números.
}

/// Un solo registro por día, el más reciente.
///
/// `water_logs` y `sleep_logs` son las dos tablas con una segunda clave única
/// —`(user_id, local_date)`— además de la primary key, y con `onConflict`
/// apuntando a esa clave **mandar dos filas del mismo día rompe el upsert
/// entero**: Postgres contesta "ON CONFLICT DO UPDATE command cannot affect row
/// a second time".
///
/// Y el mismo día con dos filas es un estado que ocurre de verdad, no una
/// hipótesis: la reconciliación (`document_merge.dart`) une las listas **por
/// id**, así que si la fila del servidor y la local tienen ids distintos para
/// el mismo día, las dos sobreviven. Que los ids difieran tampoco es raro:
/// `_dailyId` los deriva de la identidad de la cuenta, que cambia al iniciar
/// sesión, y `repararRegistrosViejos` regeneró a propósito los del agua.
///
/// Se queda con el más reciente porque es el que la persona vio último en la
/// pantalla. Esto no arregla el documento local —de eso se ocupa la reparación
/// del repositorio—, solo evita que un duplicado tire abajo la subida.
Iterable<T> _unaPorDia<T>(
  Iterable<T> items,
  DateTime Function(T) dia,
  DateTime Function(T) marca,
) {
  final porDia = <String, T>{};
  for (final item in items) {
    final clave = isoDate(dia(item));
    final actual = porDia[clave];
    if (actual == null || marca(item).isAfter(marca(actual))) {
      porDia[clave] = item;
    }
  }
  return porDia.values;
}
