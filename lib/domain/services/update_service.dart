import '../../data/remote/github_releases_client.dart';
import '../models/app_release.dart';

/// Instala un APK ya descargado. La implementación real depende de la
/// plataforma; se inyecta para poder probar el servicio sin tocar Android.
abstract interface class ApkInstaller {
  /// Guarda los bytes y le pide al sistema que abra el instalador de paquetes.
  ///
  /// Devuelve cuando el diálogo del sistema quedó a la vista: si la persona
  /// confirma o cancela ya no es asunto de la app, porque a partir de ahí el
  /// proceso lo maneja Android.
  Future<void> install(List<int> apkBytes, {required String fileName});
}

/// Decide si hay que actualizar y, si la persona acepta, baja e instala.
///
/// La comprobación es **siempre manual**: no hay chequeo automático al abrir la
/// app. Una app de salud que sale a internet sola, sin que nadie se lo pida, es
/// exactamente lo que el handoff evita en el resto del producto.
class UpdateService {
  const UpdateService({
    required GithubReleasesClient client,
    required ApkInstaller installer,
  }) : _client = client,
       _installer = installer;

  final GithubReleasesClient _client;
  final ApkInstaller _installer;

  /// Compara la versión instalada contra el último release.
  ///
  /// Si la instalada es **posterior** a la publicada devuelve [UpToDate]: eso
  /// pasa en un build local hecho después del último tag, y ofrecerle a quien
  /// desarrolla que "actualice" hacia atrás no tendría sentido.
  Future<UpdateStatus> check({required AppVersion current}) async {
    final release = await _client.fetchLatest();
    if (release == null) return NoReleasesYet(current);

    if (release.version > current) {
      return UpdateAvailable(current: current, release: release);
    }
    return UpToDate(current);
  }

  Future<void> downloadAndInstall(
    AppRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    final bytes = await _client.downloadApk(release, onProgress: onProgress);
    await _installer.install(
      bytes,
      fileName: 'nutrimat-${release.version}.apk',
    );
  }

  Uri releasePage(AppRelease release) => _client.releasePage(release);
}
