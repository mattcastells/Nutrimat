// GENERADO desde docs/handoff/design-tokens.json — no editar a mano.
// Regenerar con: dart run tool/gen_tokens.dart
//
// Sistema de diseño: Nocturne · versión 1.0.0 · tema canónico: dark (D-10).
//
// ignore_for_file: unnecessary_import

import 'dart:ui';

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Roles de color de un tema (06-design-tokens.md §1.1).
class NmColorRoles {
  const NmColorRoles({
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.accentText,
    required this.divider,
    required this.section,
    required this.success,
    required this.caution,
    required this.danger,
    required this.info,
  });

  final Color bg;
  final Color surface;
  final Color surfaceRaised;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color accentText;
  final Color divider;
  final Color section;
  final Color success;
  final Color caution;
  final Color danger;
  final Color info;
}

/// Los dos temas entregados. El oscuro es la referencia (D-10).
abstract final class NmColors {
  static const NmColorRoles dark = NmColorRoles(
    bg: Color(0xFF161826),
    surface: Color(0xFF232532),
    surfaceRaised: Color(0xFF2B2E3D),
    text: Color(0xFFE9E9ED),
    textMuted: Color(0x8CE9E9ED),
    accent: Color(0xFF9184D9),
    accentText: Color(0xFFD2CEFD),
    divider: Color(0x29E9E9ED),
    section: Color(0xFF262A60),
    success: Color(0xFF6FBF9A),
    caution: Color(0xFFD9B46A),
    danger: Color(0xFFD97B7B),
    info: Color(0xFF7FA8D9),
  );

  static const NmColorRoles light = NmColorRoles(
    bg: Color(0xFFF7F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF0F0F6),
    text: Color(0xFF1B1C26),
    textMuted: Color(0x941B1C26),
    accent: Color(0xFF796CBF),
    accentText: Color(0xFF5D5294),
    divider: Color(0x1F1B1C26),
    section: Color(0xFF262A60),
    success: Color(0xFF2F8F6A),
    caution: Color(0xFF9A7420),
    danger: Color(0xFFB04141),
    info: Color(0xFF3C6EA8),
  );

}

/// Rampas 100→900 en escala perceptual compartida (§1.2).
abstract final class NmNeutral {
  static const Color c100 = Color(0xFFF3F5FE);
  static const Color c200 = Color(0xFFE4E7F5);
  static const Color c300 = Color(0xFFCFD3E5);
  static const Color c400 = Color(0xFFB2B6CA);
  static const Color c500 = Color(0xFF9397AB);
  static const Color c600 = Color(0xFF75798C);
  static const Color c700 = Color(0xFF595D6C);
  static const Color c800 = Color(0xFF3F424D);
  static const Color c900 = Color(0xFF292B31);

  static const List<Color> ramp = <Color>[
    c100,
    c200,
    c300,
    c400,
    c500,
    c600,
    c700,
    c800,
    c900,
  ];
}

abstract final class NmAccent {
  static const Color c100 = Color(0xFFF5F4FF);
  static const Color c200 = Color(0xFFE7E5FE);
  static const Color c300 = Color(0xFFD2CEFD);
  static const Color c400 = Color(0xFFB5ABFC);
  static const Color c500 = Color(0xFF968AE0);
  static const Color c600 = Color(0xFF796CBF);
  static const Color c700 = Color(0xFF5D5294);
  static const Color c800 = Color(0xFF423A6A);
  static const Color c900 = Color(0xFF2B2741);

  static const List<Color> ramp = <Color>[
    c100,
    c200,
    c300,
    c400,
    c500,
    c600,
    c700,
    c800,
    c900,
  ];
}

abstract final class NmAccent2 {
  static const Color c100 = Color(0xFFF5F4FF);
  static const Color c200 = Color(0xFFE7E5FE);
  static const Color c300 = Color(0xFFD2CEFD);
  static const Color c400 = Color(0xFFB5AFE8);
  static const Color c500 = Color(0xFF9690C9);
  static const Color c600 = Color(0xFF7972A9);
  static const Color c700 = Color(0xFF5C5783);
  static const Color c800 = Color(0xFF423E5D);
  static const Color c900 = Color(0xFF2B293A);

  static const List<Color> ramp = <Color>[
    c100,
    c200,
    c300,
    c400,
    c500,
    c600,
    c700,
    c800,
    c900,
  ];
}

/// Paleta de datos: orden fijo por categoría (§1.4).
abstract final class NmChartColors {
  static const Color walking = Color(0xFF9184D9);
  static const Color running = Color(0xFF7FA8D9);
  static const Color strength = Color(0xFFB5ABFC);
  static const Color cycling = Color(0xFF6FBF9A);
  static const Color sports = Color(0xFFD9B46A);
  static const Color other = Color(0xFF9397AB);
  static const Color intake = Color(0xFF968AE0);
  static const Color target = Color(0xFFCFD3E5);
  static const Color weight = Color(0xFFB5ABFC);
  static const Color trend = Color(0xFFE9E9ED);

  /// Series de categoría de actividad, en el orden canónico.
  static const List<Color> categories = <Color>[
    walking,
    running,
    strength,
    cycling,
    sports,
    other,
  ];
}

/// Escala tipográfica (§2). Familia única: Inter.
class NmTypeSpec {
  const NmTypeSpec({
    required this.size,
    required this.lineHeight,
    required this.weight,
    required this.tracking,
    this.uppercase = false,
  });

  final double size;
  final double lineHeight;
  final int weight;
  /// En em, tal cual el token; se multiplica por [size] para dp.
  final double tracking;
  final bool uppercase;

  double get letterSpacing => tracking * size;
}

abstract final class NmType {
  static const String fontFamily = 'Inter';
  static const int headingWeight = 500;
  static const int bodyWeight = 400;

  static const NmTypeSpec display = NmTypeSpec(
    size: 42.0,
    lineHeight: 1.12,
    weight: 500,
    tracking: -0.015,
  );
  static const NmTypeSpec h1 = NmTypeSpec(
    size: 32.0,
    lineHeight: 1.12,
    weight: 500,
    tracking: -0.015,
  );
  static const NmTypeSpec h2 = NmTypeSpec(
    size: 25.0,
    lineHeight: 1.15,
    weight: 500,
    tracking: -0.015,
  );
  static const NmTypeSpec h3 = NmTypeSpec(
    size: 20.0,
    lineHeight: 1.2,
    weight: 500,
    tracking: -0.01,
  );
  static const NmTypeSpec h4 = NmTypeSpec(
    size: 16.0,
    lineHeight: 1.3,
    weight: 500,
    tracking: 0.0,
  );
  static const NmTypeSpec body = NmTypeSpec(
    size: 15.0,
    lineHeight: 1.55,
    weight: 400,
    tracking: 0.0,
  );
  static const NmTypeSpec bodySm = NmTypeSpec(
    size: 14.0,
    lineHeight: 1.5,
    weight: 400,
    tracking: 0.0,
  );
  static const NmTypeSpec caption = NmTypeSpec(
    size: 13.0,
    lineHeight: 1.45,
    weight: 400,
    tracking: 0.0,
  );
  static const NmTypeSpec micro = NmTypeSpec(
    size: 11.0,
    lineHeight: 1.4,
    weight: 400,
    tracking: 0.02,
  );
  static const NmTypeSpec overline = NmTypeSpec(
    size: 10.0,
    lineHeight: 1.4,
    weight: 500,
    tracking: 0.1,
    uppercase: true,
  );
}

/// Escala de densidad 0,70× de Nocturne (§3).
abstract final class NmSpace {
  static const double s1 = 3.0;
  static const double s2 = 6.0;
  static const double s3 = 8.0;
  static const double s4 = 11.0;
  static const double s5 = 14.0;
  static const double s6 = 17.0;
  static const double s8 = 22.0;
  static const double s10 = 28.0;
  static const double s12 = 34.0;
}

abstract final class NmLayout {
  static const double screenPaddingCompact = 16.0;
  static const double screenPaddingMedium = 24.0;
  static const double contentMaxWidth = 720.0;
  static const double tabBarHeight = 56.0;
  static const double fabSize = 56.0;
  static const double minTouchTarget = 48.0;
}

abstract final class NmRadius {
  static const double sm = 4.0;
  static const double md = 8.0;
  static const double lg = 14.0;
  static const double full = 999.0;

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brFull = BorderRadius.all(Radius.circular(full));
}

/// Sombras por tema (§4). En claro son tinta suave sin borde.
abstract final class NmShadow {
  static const List<BoxShadow> darkSm = <BoxShadow>[
    BoxShadow(color: Color(0xFF3F424D), offset: Offset(0.0, 0.0), blurRadius: 0.0, spreadRadius: 1.0),
  ];
  static const List<BoxShadow> darkMd = <BoxShadow>[
    BoxShadow(color: Color(0xFF595D6C), offset: Offset(0.0, 0.0), blurRadius: 0.0, spreadRadius: 1.0),
    BoxShadow(color: Color(0x8C000000), offset: Offset(0.0, 6.0), blurRadius: 18.0, spreadRadius: 0.0),
  ];
  static const List<BoxShadow> darkLg = <BoxShadow>[
    BoxShadow(color: Color(0xFF9397AB), offset: Offset(0.0, 0.0), blurRadius: 0.0, spreadRadius: 1.0),
    BoxShadow(color: Color(0xA6000000), offset: Offset(0.0, 16.0), blurRadius: 40.0, spreadRadius: 0.0),
  ];
  static const List<BoxShadow> lightSm = <BoxShadow>[
    BoxShadow(color: Color(0x141B1C26), offset: Offset(0.0, 1.0), blurRadius: 2.0, spreadRadius: 0.0),
  ];
  static const List<BoxShadow> lightMd = <BoxShadow>[
    BoxShadow(color: Color(0x1A1B1C26), offset: Offset(0.0, 4.0), blurRadius: 14.0, spreadRadius: 0.0),
  ];
  static const List<BoxShadow> lightLg = <BoxShadow>[
    BoxShadow(color: Color(0x291B1C26), offset: Offset(0.0, 16.0), blurRadius: 40.0, spreadRadius: 0.0),
  ];
}

/// Iconos: phosphor, peso regular (§4).
abstract final class NmIconSize {
  static const double sm = 16.0;
  static const double md = 20.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
}

/// Duraciones y curvas (§5 y 21-motion-and-loading.md §1).
abstract final class NmMotion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 380);
  static const Duration chart = Duration(milliseconds: 520);
  static const Duration stagger = Duration(milliseconds: 40);
  static const Duration shimmerLoop = Duration(milliseconds: 1200);
  static const Duration spinnerLoop = Duration(milliseconds: 900);
  static const Duration loadingMinVisible = Duration(milliseconds: 400);
  static const Duration loadingThreshold = Duration(milliseconds: 200);

  /// Entradas y cambios de valor.
  static const Curve ease = Cubic(0.2, 0.8, 0.2, 1.0);
  /// Salidas y descartes.
  static const Curve easeOut = Cubic(0.4, 0.0, 1.0, 1.0);

  /// Techo de elementos que escalonan su entrada (§1).
  static const int staggerCap = 8;
}

abstract final class NmBreakpoint {
  static const double compact = 0.0;
  static const double medium = 600.0;
  static const double expanded = 905.0;
}

/// Elevaciones lógicas (z-index) del §6.
abstract final class NmElevation {
  static const int content = 0;
  static const int appBar = 10;
  static const int fab = 20;
  static const int sheet = 30;
  static const int dialog = 40;
  static const int snackbar = 50;
  static const int systemBanner = 60;
}

/// Estados de interacción (§7).
abstract final class NmStateToken {
  static const double hoverAccentAlpha = 0.12;
  static const double pressedAccentAlpha = 0.22;
  static const double hoverNeutralAlpha = 0.07;
  static const double pressedNeutralAlpha = 0.14;
  static const double disabledOpacity = 0.45;
  static const double focusRingWidth = 2.0;
  static const double focusRingOffset = 2.0;
}
