import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/error/app_error.dart';
import '../../domain/models/app_release.dart';

/// Lee los releases publicados en GitHub para saber si hay una versión nueva.
///
/// El repositorio es **público**, así que la API se consulta sin credenciales:
/// no hay ningún token embebido en el APK, que es justamente lo que no puede
/// haber en una app que cualquiera puede descompilar. El límite sin autenticar
/// es de 60 consultas por hora y por IP — de sobra para un chequeo manual.
///
/// > Si el repositorio pasara a privado, esto deja de funcionar y **no alcanza
/// > con agregarle un token acá**: habría que mover la consulta a una Edge
/// > Function que guarde el token del lado del servidor.
class GithubReleasesClient {
  GithubReleasesClient({
    http.Client? client,
    this.owner = defaultOwner,
    this.repo = defaultRepo,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String owner;
  final String repo;

  static const String defaultOwner = 'mattcastells';
  static const String defaultRepo = 'Nutrimat';

  static const String _host = 'api.github.com';

  /// Sufijo del asset que instala el updater. El release también publica un APK
  /// por ABI (más chico), pero elegir entre ellos exige conocer la arquitectura
  /// del teléfono: para actualizar sin equivocarse va el universal.
  static const String universalApkSuffix = '-universal.apk';

  static const Duration timeout = Duration(seconds: 10);

  /// Devuelve el último release publicado, o `null` si el repositorio todavía
  /// no tiene ninguno.
  ///
  /// Ignora borradores y prereleases: `/releases/latest` ya los excluye.
  Future<AppRelease?> fetchLatest() async {
    final uri = Uri.https(_host, '/repos/$owner/$repo/releases/latest');

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: <String, String>{
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'Nutrimat',
          })
          .timeout(timeout);
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message:
            'No pudimos consultar si hay una versión nueva. Revisá tu conexión '
            'y probá de nuevo.',
      );
    }

    // Un repositorio sin releases responde 404, igual que uno inexistente.
    if (response.statusCode == 404) return null;

    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const AppError(
        code: ApiErrorCode.rateLimited,
        message:
            'GitHub limitó las consultas por un rato. Probá de nuevo en unos '
            'minutos.',
      );
    }

    if (response.statusCode != 200) {
      throw AppError(
        code: ApiErrorCode.upstreamFailed,
        message:
            'GitHub respondió ${response.statusCode} al buscar actualizaciones.',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const AppError(
        code: ApiErrorCode.upstreamFailed,
        message: 'GitHub devolvió una respuesta que no pudimos interpretar.',
      );
    }

    return _toRelease(body);
  }

  AppRelease? _toRelease(Map<String, dynamic> body) {
    final tag = body['tag_name'] as String?;
    if (tag == null) return null;

    final version = AppVersion.tryParse(tag);
    // Un tag que no es semver no se puede comparar: mejor callar que ofrecer
    // una actualización que quizá sea vieja.
    if (version == null) return null;

    final assets = body['assets'] as List<dynamic>? ?? <dynamic>[];
    Map<String, dynamic>? apk;
    for (final raw in assets) {
      final asset = raw as Map<String, dynamic>;
      final name = asset['name'] as String? ?? '';
      if (name.endsWith(universalApkSuffix)) {
        apk = asset;
        break;
      }
    }
    // Un release sin APK universal no es instalable desde la app.
    if (apk == null) return null;

    final url = apk['browser_download_url'] as String?;
    if (url == null) return null;
    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null) return null;

    return AppRelease(
      version: version,
      tag: tag,
      notes: (body['body'] as String? ?? '').trim(),
      apkUrl: parsedUrl,
      apkSizeBytes: (apk['size'] as num?)?.toInt() ?? 0,
      publishedAt:
          DateTime.tryParse(body['published_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  /// Descarga el APK reportando el avance de 0 a 1.
  ///
  /// Devuelve los bytes; escribirlos en disco es responsabilidad de quien
  /// llama, para que esta clase no dependa del sistema de archivos.
  Future<List<int>> downloadApk(
    AppRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', release.apkUrl)
      ..headers['User-Agent'] = 'Nutrimat';

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } on Exception {
      throw const AppError(
        code: ApiErrorCode.offline,
        message: 'Se cortó la descarga. Revisá tu conexión y probá de nuevo.',
      );
    }

    if (response.statusCode != 200) {
      throw AppError(
        code: ApiErrorCode.upstreamFailed,
        message: 'La descarga falló con el código ${response.statusCode}.',
      );
    }

    // Para la barra alcanza con lo que diga la respuesta; `contentLength`
    // puede venir nulo y ahí el tamaño del asset es el plan B.
    final expected = response.contentLength ?? release.apkSizeBytes;
    final bytes = <int>[];

    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      if (onProgress != null && expected > 0) {
        onProgress((bytes.length / expected).clamp(0.0, 1.0));
      }
    }

    // El control de integridad va contra el tamaño que declaró la API de
    // GitHub, no contra el `Content-Length` de la descarga: si un proxy corta
    // la respuesta y ajusta el header, comparar contra el header no detecta
    // nada. Instalar un APK truncado es peor que fallar.
    if (release.apkSizeBytes > 0 && bytes.length != release.apkSizeBytes) {
      throw const AppError(
        code: ApiErrorCode.upstreamFailed,
        message:
            'La descarga quedó incompleta. Probá de nuevo con mejor conexión.',
      );
    }

    onProgress?.call(1);
    return bytes;
  }

  /// Página del release en GitHub, para quien prefiera bajarlo a mano.
  Uri releasePage(AppRelease release) =>
      Uri.https('github.com', '/$owner/$repo/releases/tag/${release.tag}');
}
