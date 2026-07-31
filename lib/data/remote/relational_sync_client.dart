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
/// Los dos caminos escriben. El documento sigue siendo la fuente de verdad de
/// la app y las filas se llenan en paralelo, así que un fallo de este lado no
/// puede romper nada de lo que ya funcionaba. Cuando las filas estén
/// verificadas contra el uso real, se da vuelta: mandan las tablas y el
/// documento queda como respaldo.
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

    Future<void> subir(String tabla, List<Map<String, dynamic>> filas) async {
      if (filas.isEmpty) {
        escritas[tabla] = 0;
        return;
      }
      await _db.from(tabla).upsert(filas).timeout(timeout);
      escritas[tabla] = filas.length;
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
          },
      ]);

      await subir('water_logs', <Map<String, dynamic>>[
        for (final w in store.waterLogs)
          <String, dynamic>{
            'id': w.id,
            'user_id': userId,
            'local_date': isoDate(w.localDate),
            'glasses': w.glasses,
          },
      ]);

      await subir('sleep_logs', <Map<String, dynamic>>[
        for (final s in store.sleepLogs)
          <String, dynamic>{
            'id': s.id,
            'user_id': userId,
            'local_date': isoDate(s.localDate),
            'minutes': s.minutes,
            'quality': s.quality.wire,
            'logged_at': s.loggedAt.toUtc().toIso8601String(),
            'notes': s.notes,
          },
      ]);

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
      await subir('meals', <Map<String, dynamic>>[
        for (final m in store.meals)
          if (!m.isDeleted)
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
        if (a.isDeleted) continue;
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
        });
      }
      await subir('activities', actividades);

      return escritas;
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

      Future<List<Map<String, dynamic>>> traer(String tabla) async {
        final rows = await _db
            .from(tabla)
            .select()
            .eq('user_id', userId)
            .timeout(timeout);
        return rows.cast<Map<String, dynamic>>();
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

      final itemsPorComida = <String, List<Map<String, dynamic>>>{};
      if (meals.isNotEmpty) {
        final items = await _db
            .from('meal_items')
            .select()
            .inFilter('meal_id', meals.map((m) => m['id'] as String).toList())
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

      String isoOf(Object? v) => v == null ? '' : v.toString();

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
              'syncStatus': 'synced',
              'createdAt': isoOf(m['created_at']),
              'updatedAt': isoOf(m['updated_at']),
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
