import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Escala de movimiento del tema (21-motion-and-loading.md §6).
///
/// Con "Reducir movimiento" activo en el sistema, todas las duraciones de
/// desplazamiento y escala pasan a 0 ms y los fundidos se reducen a 90 ms.
/// El spinner es la excepción consciente: se mantiene girando, porque es el
/// único indicador de actividad.
@immutable
class NmMotionScale {
  const NmMotionScale({required this.reduced});

  final bool reduced;

  static const Duration _reducedFade = Duration(milliseconds: 90);

  /// Desplazamientos, escalas, crecimientos: se anulan en modo reducido.
  Duration move(Duration d) => reduced ? Duration.zero : d;

  /// Fundidos: se conservan, reducidos a 90 ms.
  Duration fade(Duration d) => reduced ? _reducedFade : d;

  /// Retraso escalonado entre hermanos: 40 ms con techo de 8 elementos (§1).
  Duration staggerFor(int index) => reduced
      ? Duration.zero
      : NmMotion.stagger * math.min(index, NmMotion.staggerCap);

  /// Los contadores muestran el valor final sin count-up (§6).
  bool get animatesCounters => !reduced;

  /// Los gráficos se dibujan en su estado final, sin crecimiento (§6).
  bool get animatesCharts => !reduced;

  /// El shimmer del skeleton se detiene; el bloque estático permanece (§6).
  bool get animatesShimmer => !reduced;

  /// Curva de entrada, neutralizada cuando no hay movimiento.
  Curve get ease => reduced ? Curves.linear : NmMotion.ease;

  Curve get easeOut => reduced ? Curves.linear : NmMotion.easeOut;
}

extension NmMotionContext on BuildContext {
  /// Duraciones ya escaladas según la preferencia de accesibilidad del sistema.
  NmMotionScale get motion =>
      NmMotionScale(reduced: MediaQuery.maybeDisableAnimationsOf(this) ?? false);
}
