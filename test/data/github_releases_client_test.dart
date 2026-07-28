// El cliente de releases de GitHub, con respuestas fijas: los tests no salen a
// la red. Las respuestas son recortes reales de la API v2022-11-28.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nutrimat/core/error/app_error.dart';
import 'package:nutrimat/data/remote/github_releases_client.dart';
import 'package:nutrimat/domain/models/app_release.dart';
import 'package:nutrimat/domain/services/update_service.dart';

String _releaseJson({
  String tag = 'v1.1.0',
  String body = 'Arreglos varios.',
  List<Map<String, dynamic>>? assets,
}) => jsonEncode(<String, dynamic>{
  'tag_name': tag,
  'body': body,
  'published_at': '2026-07-28T15:04:05Z',
  'assets':
      assets ??
      <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'nutrimat-1.1.0-universal.apk',
          'size': 27262976,
          'browser_download_url':
              'https://github.com/mattcastells/Nutrimat/releases/download/v1.1.0/nutrimat-1.1.0-universal.apk',
        },
      ],
});

GithubReleasesClient _clientReturning(String body, {int status = 200}) =>
    GithubReleasesClient(
      client: MockClient(
        (request) async =>
            http.Response(body, status, headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            }),
      ),
    );

class _FakeInstaller implements ApkInstaller {
  List<int>? installed;
  String? name;

  @override
  Future<void> install(List<int> apkBytes, {required String fileName}) async {
    installed = apkBytes;
    name = fileName;
  }
}

void main() {
  group('fetchLatest', () {
    test('lee el tag, las notas y el APK universal', () async {
      final release = await _clientReturning(_releaseJson()).fetchLatest();

      expect(release, isNotNull);
      expect(release!.version, AppVersion.tryParse('1.1.0'));
      expect(release.tag, 'v1.1.0');
      expect(release.notes, 'Arreglos varios.');
      expect(release.apkSizeBytes, 27262976);
      expect(release.apkUrl.host, 'github.com');
    });

    test('elige el universal y no un APK por arquitectura', () async {
      final release = await _clientReturning(
        _releaseJson(
          assets: <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'nutrimat-1.1.0-arm64-v8a.apk',
              'size': 9000000,
              'browser_download_url': 'https://example.test/arm64.apk',
            },
            <String, dynamic>{
              'name': 'nutrimat-1.1.0-universal.apk',
              'size': 27262976,
              'browser_download_url': 'https://example.test/universal.apk',
            },
          ],
        ),
      ).fetchLatest();

      expect(release!.apkUrl.path, '/universal.apk');
    });

    test('un repositorio sin releases devuelve null, no un error', () async {
      final release = await _clientReturning(
        '{"message":"Not Found"}',
        status: 404,
      ).fetchLatest();
      expect(release, isNull);
    });

    test('un release sin APK universal se ignora', () async {
      final release = await _clientReturning(
        _releaseJson(
          assets: <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'mapping.txt',
              'size': 1024,
              'browser_download_url': 'https://example.test/mapping.txt',
            },
          ],
        ),
      ).fetchLatest();
      expect(release, isNull);
    });

    test('un tag que no es semver se ignora en vez de arriesgar', () async {
      final release = await _clientReturning(
        _releaseJson(tag: 'ultima-estable'),
      ).fetchLatest();
      expect(release, isNull);
    });

    test('el límite de la API se avisa como tal', () async {
      await expectLater(
        _clientReturning('{"message":"rate limit"}', status: 403).fetchLatest(),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.rateLimited,
          ),
        ),
      );
    });

    test('un JSON roto no se propaga como excepción de parseo', () async {
      await expectLater(
        _clientReturning('no soy json').fetchLatest(),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('UpdateService.check', () {
    UpdateService serviceReturning(String body, {int status = 200}) =>
        UpdateService(
          client: _clientReturning(body, status: status),
          installer: _FakeInstaller(),
        );

    test('ofrece la actualización cuando la publicada es posterior', () async {
      final status = await serviceReturning(
        _releaseJson(),
      ).check(current: const AppVersion(1, 0, 0));

      expect(status, isA<UpdateAvailable>());
      expect((status as UpdateAvailable).release.tag, 'v1.1.0');
    });

    test('no ofrece nada cuando ya está la última', () async {
      final status = await serviceReturning(
        _releaseJson(),
      ).check(current: const AppVersion(1, 1, 0));
      expect(status, isA<UpToDate>());
    });

    test('un build local más nuevo que el release no propone volver atrás', () async {
      final status = await serviceReturning(
        _releaseJson(),
      ).check(current: const AppVersion(1, 2, 0));
      expect(status, isA<UpToDate>());
    });

    test('sin releases publicados lo dice explícitamente', () async {
      final status = await serviceReturning(
        '{}',
        status: 404,
      ).check(current: const AppVersion(1, 0, 0));
      expect(status, isA<NoReleasesYet>());
    });
  });

  group('descarga', () {
    test('informa el avance y entrega los bytes al instalador', () async {
      final payload = List<int>.filled(2048, 7);
      final installer = _FakeInstaller();
      final service = UpdateService(
        client: GithubReleasesClient(
          client: MockClient(
            (request) async => http.Response.bytes(payload, 200),
          ),
        ),
        installer: installer,
      );

      final release = AppRelease(
        version: const AppVersion(1, 1, 0),
        tag: 'v1.1.0',
        notes: '',
        apkUrl: Uri.parse('https://example.test/app.apk'),
        apkSizeBytes: payload.length,
        publishedAt: DateTime(2026, 7, 28),
      );

      final progress = <double>[];
      await service.downloadAndInstall(release, onProgress: progress.add);

      expect(installer.installed, hasLength(payload.length));
      expect(installer.name, 'nutrimat-1.1.0.apk');
      expect(progress.last, 1.0);
    });

    test('una descarga incompleta falla en vez de instalar basura', () async {
      final service = UpdateService(
        client: GithubReleasesClient(
          client: MockClient(
            (request) async => http.Response.bytes(List<int>.filled(10, 0), 200),
          ),
        ),
        installer: _FakeInstaller(),
      );

      final release = AppRelease(
        version: const AppVersion(1, 1, 0),
        tag: 'v1.1.0',
        notes: '',
        apkUrl: Uri.parse('https://example.test/app.apk'),
        // El servidor manda 10 bytes pero el release declara 5000.
        apkSizeBytes: 5000,
        publishedAt: DateTime(2026, 7, 28),
      );

      await expectLater(
        service.downloadAndInstall(release),
        throwsA(isA<AppError>()),
      );
    });
  });
}
