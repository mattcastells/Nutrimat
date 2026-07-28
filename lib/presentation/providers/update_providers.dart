import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/local/apk_installer.dart';
import '../../data/remote/github_releases_client.dart';
import '../../domain/models/app_release.dart';
import '../../domain/services/update_service.dart';

/// Providers del buscador de actualizaciones.
///
/// Se sobrescriben en los tests con un cliente y un instalador falsos; nada de
/// esto toca la red ni el sistema de archivos hasta que la persona lo pide.

final githubReleasesClientProvider = Provider<GithubReleasesClient>(
  (ref) => GithubReleasesClient(),
);

final apkInstallerProvider = Provider<ApkInstaller>(
  (ref) => const AndroidApkInstaller(),
);

final updateServiceProvider = Provider<UpdateService>(
  (ref) => UpdateService(
    client: ref.watch(githubReleasesClientProvider),
    installer: ref.watch(apkInstallerProvider),
  ),
);

/// Versión instalada, leída del propio paquete.
///
/// `package_info_plus` devuelve el `versionName` del manifest, que Gradle toma
/// de `pubspec.yaml`: una sola fuente de verdad para el número de versión.
final installedVersionProvider = FutureProvider<AppVersion>((ref) async {
  final info = await PackageInfo.fromPlatform();
  // Si el `versionName` no fuera semver la comparación no tendría sentido; el
  // 0.0.0 hace que cualquier release publicado se ofrezca como más nuevo.
  return AppVersion.tryParse(info.version) ?? const AppVersion(0, 0, 0);
});

/// Texto de la versión instalada para la pantalla "Acerca de": `1.2.0 (7)`.
final installedVersionLabelProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});
