import '../../core/error/app_error.dart';
import '../enums/enums.dart';
import 'rounding.dart';

/// TDEE = BMR × factor de nivel de actividad (11-calculation-rules.md §2).
///
/// El factor **ya incluye** la actividad habitual. Por eso el crédito de
/// ejercicio por defecto es 0 % (D-02): sumar el ejercicio registrado sobre un
/// TDEE que ya lo contempla es doble conteo.
int tdee({required int bmr, required ActivityLevel activityLevel}) {
  if (bmr <= 0) {
    throw const CalculationError('tdee', 'bmr', 'debe ser mayor que cero');
  }
  return roundHalfUp(bmr * activityLevel.factor);
}
