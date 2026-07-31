import 'package:shared_preferences/shared_preferences.dart';

/// Memoria del aviso de versión nueva: cuándo se preguntó por última vez y qué
/// versión se dejó pasar.
///
/// Vive aparte del documento de datos a propósito. Esto no es información de la
/// persona: no se respalda, no se sincroniza y no tiene por qué viajar a otro
/// teléfono, porque describe **esta instalación**. Meterlo en el documento lo
/// haría subir a las tablas y volver por la reconciliación, y un "no me
/// preguntes por la 1.11" hecho en un teléfono apagaría el aviso en el otro.
class UpdatePromptStore {
  UpdatePromptStore._(this._prefs);

  static const String _lastCheckKey = 'nutrimat.updates.last_check';
  static const String _postponedKey = 'nutrimat.updates.postponed';

  /// Cada cuánto se pregunta al abrir la app.
  ///
  /// La consulta es un JSON de unos pocos kilobytes contra la API de releases,
  /// no la descarga; aun así hay dos motivos para no hacerla en cada arranque:
  /// GitHub limita a 60 pedidos por hora sin credenciales, y abrir la app diez
  /// veces en una tarde es lo normal.
  static const Duration checkInterval = Duration(hours: 6);

  final SharedPreferences _prefs;

  static Future<UpdatePromptStore> open() async =>
      UpdatePromptStore._(await SharedPreferences.getInstance());

  DateTime? get lastCheck {
    final raw = _prefs.getString(_lastCheckKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  bool shouldCheck({DateTime? now}) {
    final last = lastCheck;
    if (last == null) return true;
    return (now ?? DateTime.now()).difference(last) >= checkInterval;
  }

  Future<void> markChecked({DateTime? now}) =>
      _prefs.setString(_lastCheckKey, (now ?? DateTime.now()).toIso8601String());

  /// La versión que se eligió dejar pasar, si hay alguna.
  String? get postponed => _prefs.getString(_postponedKey);

  /// "Ahora no" es sobre **esa** versión, no sobre las actualizaciones.
  ///
  /// Un aviso que reaparece en cada arranque después de que alguien dijo que no
  /// deja de ser un aviso y pasa a ser una molestia, y la reacción a eso es
  /// aprender a descartarlo sin leerlo — justo cuando llegue el que importa.
  /// Con la siguiente versión el aviso vuelve solo.
  Future<void> postpone(String version) =>
      _prefs.setString(_postponedKey, version);

  bool isPostponed(String version) => postponed == version;
}
