/// Los pasos reales del análisis por foto.
///
/// Existen para que la pantalla de espera diga lo que **está pasando** en vez
/// de animar algo decorativo. Los tres primeros son observables desde la app:
/// se sabe con exactitud cuándo empieza y termina cada uno. El último no —
/// cuánto tarda el modelo no lo decide Nutrimat— y por eso se trata distinto.
enum AnalysisStage {
  /// Comprimiendo y dejando la foto lista para subir. Es instantáneo.
  preparing('Preparando la foto…'),

  /// Subiendo al bucket. Depende de la conexión, no del modelo.
  uploading('Subiendo la foto…'),

  /// Esperando al modelo. Es el 80 % de la espera y el único paso cuya
  /// duración no controlamos.
  analyzing('Analizando la comida…');

  const AnalysisStage(this.label);

  final String label;

  /// Cuánto pesa cada paso en la barra, sobre 1.
  ///
  /// No son números elegidos a ojo: salen de medir el circuito real. La
  /// llamada al modelo tiene una mediana de 12,3 s contra menos de 2 s de
  /// preparación y subida juntas, así que se lleva la mayor parte de la barra.
  double get weight => switch (this) {
    AnalysisStage.preparing => 0.05,
    AnalysisStage.uploading => 0.15,
    AnalysisStage.analyzing => 0.80,
  };

  /// Fracción de la barra ya completada cuando **arranca** este paso.
  double get start {
    var acc = 0.0;
    for (final s in AnalysisStage.values) {
      if (s == this) return acc;
      acc += s.weight;
    }
    return acc;
  }
}

/// Tiempos medidos del análisis por foto, para calibrar la espera.
///
/// Salen de las corridas reales guardadas en `ai_analyses`, no de una
/// estimación: mediana 12,3 s, percentil 90 en 24,9 s y un máximo de 35,8 s
/// —ese último fue un reintento, porque un JSON inválido dispara una segunda
/// llamada al modelo y duplica el tiempo—.
///
/// Importa porque el aviso de "está tardando más de lo normal" estaba en 15 s,
/// y a los 15 s **todavía es normal**: la mitad de los análisis buenos siguen
/// corriendo. Un aviso que salta durante el funcionamiento correcto enseña a
/// ignorarlo.
abstract final class AnalysisTiming {
  /// Mediana medida de la llamada al modelo.
  static const Duration typical = Duration(milliseconds: 12300);

  /// Percentil 90 medido. Recién acá tiene sentido decir que se demora.
  static const Duration slow = Duration(milliseconds: 24900);

  /// A partir de acá sí es raro: por encima del máximo observado.
  static const Duration tooLong = Duration(seconds: 38);
}
