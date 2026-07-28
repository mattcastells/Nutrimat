// Generador de tokens: docs/handoff/design-tokens.json -> lib/core/theme/tokens.dart
//
// 06-design-tokens.md §8: `design-tokens.json` es la fuente. Este script produce el
// archivo Dart y el test `tokens_in_sync_test` falla si el generado difiere del JSON.
//
// Uso:  dart run tool/gen_tokens.dart          (escribe el archivo)
//       dart run tool/gen_tokens.dart --check  (falla si está desactualizado)

import 'dart:convert';
import 'dart:io';

const _source = 'docs/handoff/design-tokens.json';
const _output = 'lib/core/theme/tokens.dart';

void main(List<String> args) {
  final json =
      jsonDecode(File(_source).readAsStringSync()) as Map<String, dynamic>;
  final generated = _generate(json);

  if (args.contains('--check')) {
    final current = File(_output).existsSync()
        ? File(_output).readAsStringSync().replaceAll('\r\n', '\n')
        : '';
    if (current != generated) {
      stderr.writeln('tokens.dart está desincronizado con $_source.');
      stderr.writeln('Regenerá con: dart run tool/gen_tokens.dart');
      exit(1);
    }
    stdout.writeln('tokens.dart en sincronía con $_source.');
    return;
  }

  File(_output)
    ..createSync(recursive: true)
    ..writeAsStringSync(generated);
  stdout.writeln('Escrito $_output desde $_source.');
}

String _generate(Map<String, dynamic> t) {
  final b = StringBuffer();
  final meta = t['meta'] as Map<String, dynamic>;
  final color = t['color'] as Map<String, dynamic>;
  final ramp = color['ramp'] as Map<String, dynamic>;
  final chart = color['chart'] as Map<String, dynamic>;
  final type = t['type'] as Map<String, dynamic>;
  final space = t['space'] as Map<String, dynamic>;
  final layout = t['layout'] as Map<String, dynamic>;
  final radius = t['radius'] as Map<String, dynamic>;
  final shadow = t['shadow'] as Map<String, dynamic>;
  final icon = t['icon'] as Map<String, dynamic>;
  final motion = t['motion'] as Map<String, dynamic>;
  final breakpoint = t['breakpoint'] as Map<String, dynamic>;
  final elevation = t['elevationOrder'] as Map<String, dynamic>;
  final state = t['state'] as Map<String, dynamic>;

  b.writeln('// GENERADO desde $_source — no editar a mano.');
  b.writeln('// Regenerar con: dart run tool/gen_tokens.dart');
  b.writeln('//');
  b.writeln(
    '// Sistema de diseño: ${meta['basedOn']} · versión ${meta['version']} '
    '· tema canónico: ${meta['canonicalTheme']} (D-10).',
  );
  b.writeln('//');
  b.writeln('// ignore_for_file: unnecessary_import');
  b.writeln();
  b.writeln("import 'dart:ui';");
  b.writeln();
  b.writeln("import 'package:flutter/animation.dart';");
  b.writeln("import 'package:flutter/painting.dart';");
  b.writeln();

  // ── Esquema de color por tema ──────────────────────────────────────────
  b.writeln('/// Roles de color de un tema (06-design-tokens.md §1.1).');
  b.writeln('class NmColorRoles {');
  b.writeln('  const NmColorRoles({');
  for (final k in _roleKeys) {
    b.writeln('    required this.$k,');
  }
  b.writeln('  });');
  b.writeln();
  for (final k in _roleKeys) {
    b.writeln('  final Color $k;');
  }
  b.writeln('}');
  b.writeln();

  b.writeln('/// Los dos temas entregados. El oscuro es la referencia (D-10).');
  b.writeln('abstract final class NmColors {');
  for (final theme in const ['dark', 'light']) {
    final c = color[theme] as Map<String, dynamic>;
    b.writeln('  static const NmColorRoles $theme = NmColorRoles(');
    for (final k in _roleKeys) {
      b.writeln('    $k: ${_color(c[k] as String)},');
    }
    b.writeln('  );');
    b.writeln();
  }
  b.writeln('}');
  b.writeln();

  // ── Rampas ─────────────────────────────────────────────────────────────
  b.writeln('/// Rampas 100→900 en escala perceptual compartida (§1.2).');
  for (final entry in ramp.entries) {
    final name = 'Nm${_pascal(entry.key)}';
    final steps = entry.value as Map<String, dynamic>;
    b.writeln('abstract final class $name {');
    for (final step in steps.entries) {
      b.writeln(
        '  static const Color c${step.key} = ${_color(step.value as String)};',
      );
    }
    b.writeln();
    b.writeln('  static const List<Color> ramp = <Color>[');
    for (final step in steps.entries) {
      b.writeln('    c${step.key},');
    }
    b.writeln('  ];');
    b.writeln('}');
    b.writeln();
  }

  // ── Paleta de datos ────────────────────────────────────────────────────
  b.writeln('/// Paleta de datos: orden fijo por categoría (§1.4).');
  b.writeln('abstract final class NmChartColors {');
  for (final e in chart.entries) {
    b.writeln('  static const Color ${e.key} = ${_color(e.value as String)};');
  }
  b.writeln();
  b.writeln('  /// Series de categoría de actividad, en el orden canónico.');
  b.writeln('  static const List<Color> categories = <Color>[');
  for (final k in const [
    'walking',
    'running',
    'strength',
    'cycling',
    'sports',
    'other',
  ]) {
    b.writeln('    $k,');
  }
  b.writeln('  ];');
  b.writeln('}');
  b.writeln();

  // ── Tipografía ─────────────────────────────────────────────────────────
  final font = t['font'] as Map<String, dynamic>;
  b.writeln('/// Escala tipográfica (§2). Familia única: ${font['heading']}.');
  b.writeln('class NmTypeSpec {');
  b.writeln('  const NmTypeSpec({');
  b.writeln('    required this.size,');
  b.writeln('    required this.lineHeight,');
  b.writeln('    required this.weight,');
  b.writeln('    required this.tracking,');
  b.writeln('    this.uppercase = false,');
  b.writeln('  });');
  b.writeln();
  b.writeln('  final double size;');
  b.writeln('  final double lineHeight;');
  b.writeln('  final int weight;');
  b.writeln('  /// En em, tal cual el token; se multiplica por [size] para dp.');
  b.writeln('  final double tracking;');
  b.writeln('  final bool uppercase;');
  b.writeln();
  b.writeln('  double get letterSpacing => tracking * size;');
  b.writeln('}');
  b.writeln();
  b.writeln('abstract final class NmType {');
  b.writeln("  static const String fontFamily = '${font['heading']}';");
  b.writeln('  static const int headingWeight = ${font['headingWeight']};');
  b.writeln('  static const int bodyWeight = ${font['bodyWeight']};');
  b.writeln();
  for (final e in type.entries) {
    final v = e.value as Map<String, dynamic>;
    final upper = v['transform'] == 'uppercase';
    b.writeln('  static const NmTypeSpec ${e.key} = NmTypeSpec(');
    b.writeln('    size: ${_d(v['size'])},');
    b.writeln('    lineHeight: ${_d(v['lineHeight'])},');
    b.writeln('    weight: ${v['weight']},');
    b.writeln('    tracking: ${_d(_em(v['tracking'] as String))},');
    if (upper) b.writeln('    uppercase: true,');
    b.writeln('  );');
  }
  b.writeln('}');
  b.writeln();

  // ── Espaciado y layout ─────────────────────────────────────────────────
  b.writeln('/// Escala de densidad 0,70× de Nocturne (§3).');
  b.writeln('abstract final class NmSpace {');
  for (final e in space.entries) {
    b.writeln('  static const double s${e.key} = ${_d(e.value)};');
  }
  b.writeln('}');
  b.writeln();
  b.writeln('abstract final class NmLayout {');
  for (final e in layout.entries) {
    b.writeln('  static const double ${e.key} = ${_d(e.value)};');
  }
  b.writeln('}');
  b.writeln();

  // ── Radios ─────────────────────────────────────────────────────────────
  b.writeln('abstract final class NmRadius {');
  for (final e in radius.entries) {
    b.writeln('  static const double ${e.key} = ${_d(e.value)};');
  }
  b.writeln();
  for (final e in radius.entries) {
    b.writeln(
      '  static const BorderRadius br${_pascal(e.key)} = '
      'BorderRadius.all(Radius.circular(${e.key}));',
    );
  }
  b.writeln('}');
  b.writeln();

  // ── Sombras ────────────────────────────────────────────────────────────
  b.writeln('/// Sombras por tema (§4). En claro son tinta suave sin borde.');
  b.writeln('abstract final class NmShadow {');
  for (final theme in const ['dark', 'light']) {
    final s = shadow[theme] as Map<String, dynamic>;
    for (final e in s.entries) {
      final name = '$theme${_pascal(e.key)}';
      b.writeln('  static const List<BoxShadow> $name = <BoxShadow>[');
      for (final shadowSpec in _splitShadows(e.value as String)) {
        b.writeln('    ${_shadow(shadowSpec)},');
      }
      b.writeln('  ];');
    }
  }
  b.writeln('}');
  b.writeln();

  // ── Iconos ─────────────────────────────────────────────────────────────
  b.writeln("/// Iconos: ${icon['set']}, peso ${icon['weight']} (§4).");
  b.writeln('abstract final class NmIconSize {');
  for (final e in icon.entries) {
    if (e.value is num) {
      b.writeln('  static const double ${e.key} = ${_d(e.value)};');
    }
  }
  b.writeln('}');
  b.writeln();

  // ── Movimiento ─────────────────────────────────────────────────────────
  b.writeln('/// Duraciones y curvas (§5 y 21-motion-and-loading.md §1).');
  b.writeln('abstract final class NmMotion {');
  for (final e in motion.entries) {
    if (e.value is num) {
      b.writeln(
        '  static const Duration ${e.key} = '
        'Duration(milliseconds: ${e.value});',
      );
    }
  }
  b.writeln();
  b.writeln('  /// Entradas y cambios de valor.');
  b.writeln('  static const Curve ease = ${_cubic(motion['ease'] as String)};');
  b.writeln('  /// Salidas y descartes.');
  b.writeln(
    '  static const Curve easeOut = ${_cubic(motion['easeOut'] as String)};',
  );
  b.writeln();
  b.writeln('  /// Techo de elementos que escalonan su entrada (§1).');
  b.writeln('  static const int staggerCap = 8;');
  b.writeln('}');
  b.writeln();

  // ── Breakpoints y elevación ────────────────────────────────────────────
  b.writeln('abstract final class NmBreakpoint {');
  for (final e in breakpoint.entries) {
    b.writeln('  static const double ${e.key} = ${_d(e.value)};');
  }
  b.writeln('}');
  b.writeln();
  b.writeln('/// Elevaciones lógicas (z-index) del §6.');
  b.writeln('abstract final class NmElevation {');
  for (final e in elevation.entries) {
    b.writeln('  static const int ${e.key} = ${e.value};');
  }
  b.writeln('}');
  b.writeln();

  // ── Estados de interacción ─────────────────────────────────────────────
  b.writeln('/// Estados de interacción (§7).');
  b.writeln('abstract final class NmStateToken {');
  for (final e in state.entries) {
    if (e.value is num) {
      b.writeln('  static const double ${e.key} = ${_d(e.value)};');
    }
  }
  final focus = state['focusRing'] as Map<String, dynamic>;
  b.writeln('  static const double focusRingWidth = ${_d(focus['width'])};');
  b.writeln('  static const double focusRingOffset = ${_d(focus['offset'])};');
  b.writeln('}');

  return b.toString();
}

const _roleKeys = <String>[
  'bg',
  'surface',
  'surfaceRaised',
  'text',
  'textMuted',
  'accent',
  'accentText',
  'divider',
  'section',
  'success',
  'caution',
  'danger',
  'info',
];

String _pascal(String s) => s[0].toUpperCase() + s.substring(1);

String _d(Object? v) {
  final n = (v as num).toDouble();
  return n == n.roundToDouble() ? '${n.toInt()}.0' : '$n';
}

double _em(String tracking) =>
    double.parse(tracking.replaceAll('em', '').trim());

/// `#rrggbb` o `rgba(r,g,b,a)` -> literal `Color(...)`.
String _color(String raw) {
  final v = raw.trim();
  if (v.startsWith('#')) {
    final hex = v.substring(1);
    return 'Color(0xFF${hex.toUpperCase()})';
  }
  final inner = v.substring(v.indexOf('(') + 1, v.lastIndexOf(')'));
  final parts = inner.split(',').map((e) => e.trim()).toList();
  final r = int.parse(parts[0]);
  final g = int.parse(parts[1]);
  final bl = int.parse(parts[2]);
  final a = parts.length > 3 ? double.parse(parts[3]) : 1.0;
  final alpha = (a * 255).round();
  final hex = [alpha, r, g, bl]
      .map((c) => c.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();
  return 'Color(0x$hex)';
}

/// Separa una lista CSS de sombras respetando los paréntesis de `rgba()`.
List<String> _splitShadows(String raw) {
  final out = <String>[];
  var depth = 0;
  final buf = StringBuffer();
  for (final ch in raw.split('')) {
    if (ch == '(') depth++;
    if (ch == ')') depth--;
    if (ch == ',' && depth == 0) {
      out.add(buf.toString().trim());
      buf.clear();
      continue;
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) out.add(buf.toString().trim());
  return out;
}

/// `0 6px 18px rgba(0,0,0,.55)` -> `BoxShadow(...)`.
String _shadow(String spec) {
  final tokens = <String>[];
  var depth = 0;
  final buf = StringBuffer();
  for (final ch in spec.split('')) {
    if (ch == '(') depth++;
    if (ch == ')') depth--;
    if (ch == ' ' && depth == 0) {
      if (buf.isNotEmpty) tokens.add(buf.toString());
      buf.clear();
      continue;
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) tokens.add(buf.toString());

  double px(String s) => double.parse(s.replaceAll('px', ''));

  final x = px(tokens[0]);
  final y = px(tokens[1]);
  final blur = px(tokens[2]);
  final hasSpread = tokens.length == 5;
  final spread = hasSpread ? px(tokens[3]) : 0.0;
  final colorToken = tokens.last;

  return 'BoxShadow('
      'color: ${_color(colorToken)}, '
      'offset: Offset(${_d(x)}, ${_d(y)}), '
      'blurRadius: ${_d(blur)}, '
      'spreadRadius: ${_d(spread)})';
}

/// `cubic-bezier(0.2,0.8,0.2,1)` -> `Cubic(0.2, 0.8, 0.2, 1.0)`.
String _cubic(String raw) {
  final inner = raw.substring(raw.indexOf('(') + 1, raw.lastIndexOf(')'));
  final p = inner.split(',').map((e) => double.parse(e.trim())).toList();
  return 'Cubic(${_d(p[0])}, ${_d(p[1])}, ${_d(p[2])}, ${_d(p[3])})';
}
