import '../../core/utils/dates.dart';
import '../calculations/rounding.dart';
import '../enums/enums.dart';
import '../models/body.dart';
import '../models/goal.dart';
import '../models/summaries.dart';
import '../models/user_profile.dart';

/// Un promedio con cuántos días lo sostienen.
///
/// Los dos números van juntos siempre. "2.100 kcal por día" sobre dos días
/// registrados no es un promedio, es una anécdota, y el informe tiene que poder
/// decir la diferencia en vez de dibujar los dos iguales.
class ReportAverage {
  const ReportAverage({required this.value, required this.days});

  const ReportAverage.empty() : value = 0, days = 0;

  final double value;

  /// Sobre cuántos días con registro se calculó.
  final int days;

  bool get hasData => days > 0;
}

/// Una fila de la tabla de nutrientes: cuánto se comió en promedio y cuál era
/// el objetivo.
class ReportNutrient {
  const ReportNutrient({
    required this.label,
    required this.average,
    required this.targetPerDay,
    required this.unit,
  });

  final String label;
  final ReportAverage average;
  final int targetPerDay;
  final String unit;

  /// Qué porcentaje del objetivo cubre el promedio. `null` sin objetivo.
  int? get pctOfTarget => targetPerDay <= 0
      ? null
      : roundHalfUp(average.value / targetPerDay * 100);
}

/// Cómo cambió una medida entre el principio y el final del período.
class ReportDelta {
  const ReportDelta({
    required this.first,
    required this.last,
    required this.label,
    required this.unit,
  });

  final double first;
  final double last;
  final String label;
  final String unit;

  double get delta => double.parse((last - first).toStringAsFixed(1));
}

/// Todo lo que muestra el informe, ya calculado.
///
/// Es un objeto de datos sin nada de PDF ni de Flutter adentro: lo arma
/// [ReportBuilder] a partir del repositorio y lo dibuja `pdf_report.dart`. La
/// separación es la de siempre —la aritmética se puede probar sin generar un
/// archivo— y además deja la puerta abierta a mostrar lo mismo en pantalla.
class NutritionReport {
  const NutritionReport({
    required this.name,
    required this.from,
    required this.to,
    required this.trackingSince,
    required this.generatedAt,
    required this.daysWithRecords,
    required this.daysNotOver,
    required this.goal,
    required this.calories,
    required this.exerciseCalories,
    required this.progress,
    required this.nutrients,
    required this.weight,
    required this.water,
    required this.waterByDay,
    required this.sleepMinutes,
    required this.sleepByDay,
    required this.measurements,
    required this.dietaryLabels,
  });

  final String name;
  final DateTime from;
  final DateTime to;

  /// Desde cuándo esta persona usa la app, si empezó **dentro** del período.
  ///
  /// Es lo que evita el "16 de 30 · 53 %" de alguien que instaló la app hace
  /// dos semanas: esos catorce días de antes no son huecos en su registro, son
  /// días en los que no tenía la app. `null` cuando ya venía usándola desde
  /// antes, que es el caso en que el período entero sí es comparable.
  final DateTime? trackingSince;
  final DateTime generatedAt;

  /// Días con al menos una comida o una actividad. Es el denominador honesto
  /// de todo lo demás.
  final int daysWithRecords;

  /// De los días registrados, en cuántos no se pasó del objetivo.
  ///
  /// Es la misma regla que usa el Historial (`HistoryDay.isWithinTarget`):
  /// consumido ≤ objetivo del día, con el ejercicio aplicado si corresponde.
  /// Antes acá se contaban los días **dentro de una banda de ±10 %**, que es
  /// otra cosa: comer 1.400 con un objetivo de 2.000 no contaba, y para quien
  /// mira su informe eso es exactamente un día en el que no se pasó.
  final int daysNotOver;

  final Goal? goal;

  /// Calorías consumidas por día, en promedio.
  final ReportAverage calories;

  /// Calorías estimadas de ejercicio por día, en promedio.
  final ReportAverage exerciseCalories;

  final ProgressSummary progress;
  final List<ReportNutrient> nutrients;

  /// Peso al principio y al final del período. `null` sin registros.
  final ReportDelta? weight;

  final ReportAverage water;

  /// Vasos por día, solo los días que tienen registro. Es lo que dibuja el
  /// gráfico: un día sin cargar no es un día sin tomar agua.
  final List<ChartPoint> waterByDay;

  final ReportAverage sleepMinutes;

  /// Minutos dormidos por noche, solo las noches registradas.
  final List<ChartPoint> sleepByDay;

  /// Las medidas corporales que se movieron en el período.
  final List<ReportDelta> measurements;

  /// Preferencias y alergias, para que el informe diga bajo qué condiciones se
  /// comió. Vacío si no hay ninguna.
  final List<String> dietaryLabels;

  /// Los días del período que efectivamente se podían registrar.
  ///
  /// Arranca cuando arrancó la persona, no cuando arranca la ventana elegida.
  int get totalDays => daysBetween(countingFrom, to) + 1;

  /// El primer día que cuenta: el del período, o el primero de la persona si
  /// empezó más tarde.
  DateTime get countingFrom =>
      trackingSince != null && trackingSince!.isAfter(from)
      ? trackingSince!
      : from;

  /// Si la ventana elegida es más larga que el tiempo que lleva usando la app.
  bool get startedMidPeriod => countingFrom.isAfter(from);

  /// Qué proporción de los días que se podían registrar tienen algo. Es lo que
  /// permite leer el resto con la desconfianza que corresponda.
  int get coveragePct =>
      totalDays <= 0 ? 0 : roundHalfUp(daysWithRecords / totalDays * 100);

  bool get hasEnoughData => daysWithRecords >= 3;
}

/// Arma el informe con lo que ya sabe la app.
///
/// No inventa nada ni completa huecos: un día sin registro no cuenta como cero
/// —eso bajaría todos los promedios y haría parecer que alguien comió menos de
/// lo que comió—, cuenta como un día que no está. Por eso cada promedio viaja
/// con su cantidad de días.
abstract final class ReportBuilder {
  static NutritionReport build({
    required UserProfile profile,
    required Goal? goal,
    required ProgressSummary progress,
    required List<DailySummary> days,
    required int Function(DateTime) glassesOn,
    required int? Function(DateTime) sleepMinutesOn,
    required List<BodyMeasurement> Function(MeasurementMetric) measurementsOf,
    required DateTime generatedAt,
    DateTime? trackingSince,
  }) {
    final conRegistro = days.where((d) => d.hasRecords).toList();

    final calories = _average(
      conRegistro.map((d) => d.consumedKcal.toDouble()),
    );
    final exercise = _average(
      conRegistro.map((d) => d.exerciseEstimatedKcal.toDouble()),
    );

    // Los macros salen de los mismos días que las calorías: mezclarlos con días
    // sin registro daría un promedio de proteína que no se corresponde con el
    // de calorías, y las dos filas están una al lado de la otra.
    final nutrients = <ReportNutrient>[
      ReportNutrient(
        label: 'Proteínas',
        average: _average(conRegistro.map((d) => d.macros.protein.current)),
        targetPerDay: goal?.proteinG ?? 0,
        unit: 'g',
      ),
      ReportNutrient(
        label: 'Carbohidratos',
        average: _average(conRegistro.map((d) => d.macros.carbs.current)),
        targetPerDay: goal?.carbsG ?? 0,
        unit: 'g',
      ),
      ReportNutrient(
        label: 'Grasas',
        average: _average(conRegistro.map((d) => d.macros.fat.current)),
        targetPerDay: goal?.fatG ?? 0,
        unit: 'g',
      ),
    ];

    // Agua y sueño se promedian sobre los días **que tienen ese dato**, no
    // sobre los que tienen comida: alguien puede registrar todas sus comidas y
    // el agua solo los días que se acuerda, y contar los otros como cero diría
    // que toma la mitad de lo que toma.
    final vasos = <ChartPoint>[];
    final sueno = <ChartPoint>[];
    for (final day in days) {
      final glasses = glassesOn(day.date);
      if (glasses > 0) {
        vasos.add(ChartPoint(day.date, glasses.toDouble()));
      }
      final minutes = sleepMinutesOn(day.date);
      if (minutes != null && minutes > 0) {
        sueno.add(ChartPoint(day.date, minutes.toDouble()));
      }
    }

    // Los días en que no se pasó, con la misma regla que el Historial: el
    // objetivo del día más lo que sumó el ejercicio, si es que suma.
    var sinPasarse = 0;
    for (final day in conRegistro) {
      if (day.consumedKcal <= 0) continue;
      if (day.consumedKcal <= day.adjustedTarget) sinPasarse++;
    }

    return NutritionReport(
      name: profile.displayName?.trim().isNotEmpty ?? false
          ? profile.displayName!.trim()
          : 'Tu informe',
      from: progress.from,
      to: progress.to,
      trackingSince: trackingSince == null
          ? null
          : dateOnly(trackingSince),
      generatedAt: generatedAt,
      daysWithRecords: conRegistro.length,
      daysNotOver: sinPasarse,
      goal: goal,
      calories: calories,
      exerciseCalories: exercise,
      progress: progress,
      nutrients: nutrients,
      weight: _weightDelta(progress),
      water: _average(vasos.map((p) => p.value)),
      waterByDay: vasos,
      sleepMinutes: _average(sueno.map((p) => p.value)),
      sleepByDay: sueno,
      measurements: _measurementDeltas(
        measurementsOf: measurementsOf,
        from: progress.from,
        to: progress.to,
      ),
      dietaryLabels: <String>[
        for (final flag in profile.dietaryFlags) flag.label,
      ],
    );
  }

  static ReportAverage _average(Iterable<double> values) {
    final list = values.toList();
    if (list.isEmpty) return const ReportAverage.empty();
    final total = list.fold<double>(0, (acc, v) => acc + v);
    return ReportAverage(value: total / list.length, days: list.length);
  }

  static ReportDelta? _weightDelta(ProgressSummary progress) {
    if (progress.weightPoints.isEmpty) return null;
    return ReportDelta(
      first: progress.weightPoints.first.value,
      last: progress.weightPoints.last.value,
      label: 'Peso',
      unit: 'kg',
    );
  }

  /// Las medidas con al menos dos registros en el período: con una sola no hay
  /// nada que comparar, y mostrarla como "sin cambios" sería mentir.
  static List<ReportDelta> _measurementDeltas({
    required List<BodyMeasurement> Function(MeasurementMetric) measurementsOf,
    required DateTime from,
    required DateTime to,
  }) {
    final out = <ReportDelta>[];
    for (final metric in MeasurementMetric.values) {
      final inRange =
          measurementsOf(metric)
              .where(
                (m) =>
                    !m.isDeleted &&
                    !m.localDate.isBefore(from) &&
                    !m.localDate.isAfter(to),
              )
              .toList()
            ..sort((a, b) => a.localDate.compareTo(b.localDate));
      if (inRange.length < 2) continue;
      out.add(
        ReportDelta(
          first: inRange.first.value,
          last: inRange.last.value,
          // La etiqueta corta: la unidad ya viaja con cada valor, y con
          // `longLabel` la fila terminaba diciendo "Cintura (cm) · 78,0 cm".
          // Dos métricas homónimas en distinta unidad se distinguen igual,
          // porque la unidad está en los números.
          label: metric.label,
          unit: metric.unitLabel,
        ),
      );
    }
    // Las que más se movieron primero: son las que alguien mira.
    out.sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));
    return out.take(6).toList();
  }

  /// Una frase que resume el período, o `null` si no hay con qué.
  ///
  /// Una sola, y de las que se pueden sostener con los números de arriba. El
  /// informe no es el lugar para consejos: es el lugar para decir qué pasó.
  static String? headline(NutritionReport report) {
    if (!report.hasEnoughData) return null;

    final weight = report.weight;
    final trend = report.progress.trendKgPerWeek;
    if (weight != null && trend != null && trend.abs() >= 0.05) {
      final direccion = trend < 0 ? 'bajando' : 'subiendo';
      final ritmo = trend.abs().toStringAsFixed(2).replaceAll('.', ',');
      return 'En estos ${report.totalDays} días venís $direccion a un ritmo '
          'de $ritmo kg por semana.';
    }
    if (weight != null && weight.delta.abs() < 0.5) {
      return 'En estos ${report.totalDays} días tu peso se mantuvo: '
          '${_kg(weight.first)} a ${_kg(weight.last)}.';
    }
    if (report.calories.hasData) {
      return 'Registraste ${report.daysWithRecords} de los '
          '${report.totalDays} días, con un promedio de '
          '${roundHalfUp(report.calories.value)} kcal por día.';
    }
    return null;
  }

  /// Cuánto se comió de más o de menos por día, contra el objetivo.
  ///
  /// `null` sin objetivo o sin días con registro. Es el número que dice si el
  /// promedio de arriba está lejos o cerca, sin obligar a restar de cabeza.
  static int? averageVsTarget(NutritionReport report) {
    final target = report.goal?.baseCalorieTarget ?? 0;
    if (target <= 0 || !report.calories.hasData) return null;
    return roundHalfUp(report.calories.value - target);
  }

  static String _kg(double value) =>
      '${value.toStringAsFixed(1).replaceAll('.', ',')} kg';

  /// El día de mayor y el de menor consumo, para poner los extremos al lado del
  /// promedio. `null` con menos de dos días registrados.
  static (CaloriesDay, CaloriesDay)? calorieExtremes(NutritionReport report) {
    final conDatos =
        report.progress.calorieDays.where((d) => d.consumed > 0).toList();
    if (conDatos.length < 2) return null;
    var min = conDatos.first;
    var max = conDatos.first;
    for (final day in conDatos) {
      if (day.consumed < min.consumed) min = day;
      if (day.consumed > max.consumed) max = day;
    }
    return (min, max);
  }

  /// El día con más y con menos de una serie. `null` con menos de dos puntos:
  /// con uno solo no hay extremos, hay un dato.
  static (ChartPoint, ChartPoint)? extremes(List<ChartPoint> points) {
    if (points.length < 2) return null;
    var min = points.first;
    var max = points.first;
    for (final p in points) {
      if (p.value < min.value) min = p;
      if (p.value > max.value) max = p;
    }
    return (min, max);
  }
}
