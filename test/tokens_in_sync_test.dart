// 06-design-tokens.md §8: un test de CI falla si el archivo generado difiere
// del JSON fuente.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tokens.dart está en sincronía con design-tokens.json', () {
    final result = Process.runSync('dart', <String>[
      'run',
      'tool/gen_tokens.dart',
      '--check',
    ], runInShell: true);

    expect(
      result.exitCode,
      0,
      reason:
          'tokens.dart quedó desactualizado. Regenerá con: '
          'dart run tool/gen_tokens.dart\n${result.stderr}',
    );
  });
}
