import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../core/utils/dates.dart';
import '../../domain/models/pal.dart';

/// Resultado de pedir un pal por código. Lo devuelve el RPC.
enum PalRequestResult {
  sent('sent'),
  notFound('not_found'),
  self('self'),
  already('already'),
  rateLimited('rate_limited');

  const PalRequestResult(this.wire);

  final String wire;

  static PalRequestResult fromWire(String? w) =>
      PalRequestResult.values.firstWhere(
        (r) => r.wire == w,
        orElse: () => PalRequestResult.notFound,
      );
}

/// Vínculos con otras personas y sus días compartidos.
class PalsClient {
  PalsClient(this._db);

  factory PalsClient.fromInstance() => PalsClient(Supabase.instance.client);

  final SupabaseClient _db;

  /// Ningún `await` contra la red sin plazo propio.
  ///
  /// Los clientes de Supabase no lo traen, y acá la falta se pagaba caro:
  /// `PalPublisher.publish` se queda con `_publishing = true` para siempre, así
  /// que **la cuenta deja de publicar su día** hasta que se reinicie la app; y
  /// la pantalla de Pals se queda en el esqueleto, o con "Enviar solicitud"
  /// girando, sin error y sin salida. Con señal mala —el socket se abre y no
  /// contesta— el `Future` no termina nunca.
  static const Duration timeout = Duration(seconds: 30);

  String get _me => _db.auth.currentUser?.id ?? '';

  /// El nombre que ven los pals.
  ///
  /// Vive en `profiles`, que es la única tabla de servidor que la app escribe
  /// fuera del respaldo. Si no se setea nunca, el trigger de alta deja la parte
  /// del correo anterior a la arroba, y eso es lo que terminan viendo los
  /// demás.
  Future<void> setDisplayName(String name) async {
    try {
      await _db
          .from('profiles')
          .update(<String, dynamic>{'display_name': name})
          .eq('id', _me)
          .timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }

  /// Código propio, el que se le pasa a alguien para que te agregue.
  Future<String?> myCode() async {
    try {
      final row = await _db
          .from('profiles')
          .select('pal_code')
          .eq('id', _me)
          .maybeSingle()
          .timeout(timeout);
      return row?['pal_code'] as String?;
    } on Exception {
      return null;
    }
  }

  Future<PalRequestResult> request(String code) async {
    try {
      final result = await _db
          .rpc<String>(
            'request_pal',
            params: <String, dynamic>{'p_code': code},
          )
          .timeout(timeout);
      return PalRequestResult.fromWire(result);
    } on PostgrestException catch (error) {
      throw AppError(
        code: ApiErrorCode.server,
        message: 'No pudimos mandar la solicitud.',
        requestId: error.message,
      );
    } on Exception {
      throw _offline;
    }
  }

  /// Todos los vínculos, en las dos direcciones.
  ///
  /// El nombre sale de `pal_profiles` y no de un join con `profiles`. Es una
  /// vista de dos columnas —id y nombre— que existe justamente porque la
  /// policy que abría `profiles` a los pals abría **la fila entera**: fecha de
  /// nacimiento, altura, sexo y el código de pal, y encima con la solicitud
  /// todavía sin aceptar (migración 28).
  ///
  /// Son dos consultas y no un join embebido porque PostgREST solo embebe
  /// atravesando una FK, y una vista no la tiene. El costo es una consulta
  /// más sobre una lista de ids que tiene el tamaño de la agenda de alguien.
  Future<List<Pal>> list() async {
    try {
      final rows = await _db
          .from('pals')
          .select('id, status, requester_id, addressee_id')
          .order('created_at')
          .timeout(timeout);
      if (rows.isEmpty) return const <Pal>[];

      String otherOf(Map<String, dynamic> row) =>
          (row['addressee_id'] == _me
                  ? row['requester_id']
                  : row['addressee_id'])
              as String;

      final names = await _db
          .from('pal_profiles')
          .select('id, display_name')
          .inFilter('id', rows.map(otherOf).toSet().toList())
          .timeout(timeout);
      final nameById = <String, String>{
        for (final n in names)
          n['id'] as String: n['display_name'] as String? ?? '',
      };

      return rows.map<Pal>((row) {
        final other = otherOf(row);
        return Pal(
          id: row['id'] as String,
          userId: other,
          // Vacío si la vista no lo devuelve: la pantalla ya sabe mostrar un
          // vínculo sin nombre, y quedarse sin la lista entera por un nombre
          // que falta sería peor.
          displayName: nameById[other] ?? '',
          status: PalStatus.fromWire(row['status'] as String?),
          isIncoming: row['addressee_id'] == _me,
        );
      }).toList();
    } on Exception {
      throw _offline;
    }
  }

  Future<void> accept(String palId) => _setStatus(palId, PalStatus.accepted);

  Future<void> remove(String palId) async {
    try {
      await _db.from('pals').delete().eq('id', palId).timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }

  Future<void> _setStatus(String palId, PalStatus status) async {
    try {
      await _db
          .from('pals')
          .update(<String, dynamic>{
            'status': status.wire,
            'responded_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', palId)
          .timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }

  /// El día de un pal. `null` si todavía no publicó nada ese día.
  Future<PalDay?> dayOf(String userId, DateTime date) async {
    try {
      final row = await _db
          .from('shared_days')
          .select()
          .eq('user_id', userId)
          .eq('local_date', isoDate(date))
          .maybeSingle()
          .timeout(timeout);
      return row == null ? null : PalDay.fromRow(row);
    } on Exception {
      throw _offline;
    }
  }

  /// Publica el día propio. Sobrescribe el de esa fecha.
  Future<void> publishDay(PalDay day) async {
    try {
      await _db.from('shared_days').upsert(<String, dynamic>{
        'user_id': _me,
        'local_date': isoDate(day.date),
        'meals': day.meals.map((m) => m.toJson()).toList(),
        'activity_minutes': day.activityMinutes,
        'activity_count': day.activityCount,
        'activities': day.activities.map((a) => a.toJson()).toList(),
        'water_glasses': day.waterGlasses,
        'sleep_minutes': day.sleepMinutes,
        'sleep_quality': day.sleepQuality?.wire,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }

  /// Qué categorías, además de comida y actividad, comparte esta cuenta.
  Future<PalSharingPrefs> mySharingPrefs() async {
    try {
      final row = await _db
          .from('profiles')
          .select(
            'pal_share_photos, pal_share_water, pal_share_sleep, '
            'pal_share_activity_detail',
          )
          .eq('id', _me)
          .maybeSingle()
          .timeout(timeout);
      return row == null ? const PalSharingPrefs() : PalSharingPrefs.fromRow(row);
    } on Exception {
      throw _offline;
    }
  }

  Future<void> setSharingPrefs(PalSharingPrefs prefs) async {
    try {
      await _db
          .from('profiles')
          .update(<String, dynamic>{
            'pal_share_photos': prefs.photos,
            'pal_share_water': prefs.water,
            'pal_share_sleep': prefs.sleep,
            'pal_share_activity_detail': prefs.activityDetail,
          })
          .eq('id', _me)
          .timeout(timeout);
    } on Exception {
      throw _offline;
    }
  }

  static const AppError _offline = AppError(
    code: ApiErrorCode.offline,
    message: 'Sin conexión: se reintenta cuando vuelva internet.',
  );
}
