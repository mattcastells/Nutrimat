/// Versión semántica de la app, para comparar la instalada contra la publicada.
///
/// Sigue la precedencia de [semver 2.0.0](https://semver.org/lang/es/): se
/// comparan mayor, menor y parche como números, una versión con pre-release
/// (`1.2.0-beta.1`) es **anterior** a la final (`1.2.0`), y los metadatos de
/// build (`+3`) no participan de la comparación.
///
/// El `versionCode` de Android no sirve acá: es un entero opaco que no dice
/// nada sobre qué cambió, y el tag de GitHub habla en semver.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease = const <String>[],
  });

  final int major;
  final int minor;
  final int patch;

  /// Identificadores separados por punto de `-alpha.2`, en orden. Vacío en una
  /// versión final.
  final List<String> preRelease;

  /// Acepta `1.2.3`, `v1.2.3`, `1.2.3-beta.1` y `1.2.3+4`; devuelve `null` si
  /// el texto no es una versión reconocible.
  ///
  /// Tolera la `v` inicial porque así se nombran los tags de git, y descarta el
  /// `+build` porque semver lo excluye de la precedencia.
  static AppVersion? tryParse(String raw) {
    var text = raw.trim();
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }

    final buildAt = text.indexOf('+');
    if (buildAt >= 0) text = text.substring(0, buildAt);

    final preAt = text.indexOf('-');
    final preRelease = <String>[];
    if (preAt >= 0) {
      final tail = text.substring(preAt + 1);
      text = text.substring(0, preAt);
      if (tail.isEmpty) return null;
      preRelease.addAll(tail.split('.'));
      if (preRelease.any((part) => part.isEmpty)) return null;
    }

    final parts = text.split('.');
    if (parts.length != 3) return null;

    final numbers = <int>[];
    for (final part in parts) {
      // `int.tryParse` acepta '+5', '-5' y ' 5'; acá solo valen dígitos.
      if (!_isAllDigits(part)) return null;
      final value = int.tryParse(part);
      if (value == null) return null;
      numbers.add(value);
    }

    return AppVersion(
      numbers[0],
      numbers[1],
      numbers[2],
      preRelease: preRelease,
    );
  }

  static bool _isAllDigits(String text) {
    if (text.isEmpty) return false;
    const zero = 0x30;
    const nine = 0x39;
    for (final code in text.codeUnits) {
      if (code < zero || code > nine) return false;
    }
    return true;
  }

  bool get isPreRelease => preRelease.isNotEmpty;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // Con el número igual: la final gana a cualquier pre-release.
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;

    for (var i = 0; i < preRelease.length && i < other.preRelease.length; i++) {
      final mine = preRelease[i];
      final theirs = other.preRelease[i];
      if (mine == theirs) continue;

      final mineNum = int.tryParse(mine);
      final theirsNum = int.tryParse(theirs);
      // Un identificador numérico siempre pesa menos que uno alfanumérico.
      if (mineNum != null && theirsNum != null) {
        return mineNum.compareTo(theirsNum);
      }
      if (mineNum != null) return -1;
      if (theirsNum != null) return 1;
      return mine.compareTo(theirs);
    }

    // Todos los identificadores comunes son iguales: gana el que tiene más.
    return preRelease.length.compareTo(other.preRelease.length);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease.join('.'));

  @override
  String toString() {
    final base = '$major.$minor.$patch';
    return isPreRelease ? '$base-${preRelease.join('.')}' : base;
  }
}

/// Una versión publicada como release de GitHub, con su APK adjunto.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.tag,
    required this.notes,
    required this.apkUrl,
    required this.apkSizeBytes,
    required this.publishedAt,
  });

  final AppVersion version;

  /// El tag tal como está en GitHub (`v1.2.0`), para mostrarlo y para armar la
  /// URL de la página del release.
  final String tag;

  /// Cuerpo del release en Markdown. Puede venir vacío.
  final String notes;

  final Uri apkUrl;
  final int apkSizeBytes;
  final DateTime publishedAt;

  /// Tamaño legible para mostrar antes de que la persona acepte descargar: en
  /// un teléfono con datos móviles, 28 MB no es un detalle.
  String get apkSizeLabel {
    const mb = 1024 * 1024;
    if (apkSizeBytes >= mb) {
      return '${(apkSizeBytes / mb).toStringAsFixed(1)} MB';
    }
    return '${(apkSizeBytes / 1024).round()} kB';
  }
}

/// Resultado de consultar si hay una versión nueva.
sealed class UpdateStatus {
  const UpdateStatus();
}

/// La instalada es la última publicada — o incluso posterior, si es un build
/// local hecho después del último release.
class UpToDate extends UpdateStatus {
  const UpToDate(this.current);

  final AppVersion current;
}

/// Todavía no hay ningún release publicado en el repositorio.
class NoReleasesYet extends UpdateStatus {
  const NoReleasesYet(this.current);

  final AppVersion current;
}

/// Hay una versión más nueva y su APK está disponible.
class UpdateAvailable extends UpdateStatus {
  const UpdateAvailable({required this.current, required this.release});

  final AppVersion current;
  final AppRelease release;
}
