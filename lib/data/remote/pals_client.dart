import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error/app_error.dart';
import '../../core/utils/dates.dart';
import '../../domain/models/pal.dart';

/// Resultado de pedir un pal por código. Lo devuelve el RPC.
enum PalRequestResult {
  sent('sent'),
  notFound('not_found'),
  self('self'),
  already('already');

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
          .eq('id', _me);
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
          .maybeSingle();
      return row?['pal_code'] as String?;
    } on Exception {
      return null;
    }
  }

  Future<PalRequestResult> request(String code) async {
    try {
      final result = await _db.rpc<String>(
        'request_pal',
        params: <String, dynamic>{'p_code': code},
      );
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
  /// El nombre sale de un join con `profiles`, que RLS abre solo entre pals
  /// aceptados o con solicitud en curso.
  Future<List<Pal>> list() async {
    try {
      final rows = await _db
          .from('pals')
          .select(
            'id, status, requester_id, addressee_id, '
            'requester:profiles!pals_requester_id_fkey(id, display_name), '
            'addressee:profiles!pals_addressee_id_fkey(id, display_name)',
          )
          .order('created_at');

      return rows.map<Pal>((row) {
        final incoming = row['addressee_id'] == _me;
        final other =
            (incoming ? row['requester'] : row['addressee'])
                as Map<String, dynamic>?;
        return Pal(
          id: row['id'] as String,
          userId: (incoming ? row['requester_id'] : row['addressee_id'])
              as String,
          displayName: other?['display_name'] as String? ?? '',
          status: PalStatus.fromWire(row['status'] as String?),
          isIncoming: incoming,
        );
      }).toList();
    } on Exception {
      throw _offline;
    }
  }

  Future<void> accept(String palId) => _setStatus(palId, PalStatus.accepted);

  Future<void> remove(String palId) async {
    try {
      await _db.from('pals').delete().eq('id', palId);
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
          .eq('id', palId);
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
          .maybeSingle();
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on Exception {
      throw _offline;
    }
  }

  static const AppError _offline = AppError(
    code: ApiErrorCode.offline,
    message: 'Sin conexión: se reintenta cuando vuelva internet.',
  );
}
