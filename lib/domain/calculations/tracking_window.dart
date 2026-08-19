import '../../core/utils/dates.dart';

/// El período que **de verdad** se podía registrar.
///
/// Los períodos de la app salen del calendario —"los últimos 30 días"— y los
/// denominadores salían de ahí también. Alguien que empezó el 18 de agosto
/// aparecía, el 19, con "1 de 30 · 29 sin registrar". Ninguno de esos 29 días
/// es un incumplimiento: son días en que la app no existía para esa persona.
///
/// La regla, que vale para **toda** métrica temporal:
///
/// > Ningún cálculo cuenta como "sin registro" un día anterior al primero del
/// > que hay algo cargado.
///
/// Esto vive acá y no adentro de cada pantalla porque el error es invisible
/// cuando está bien: un gráfico que respeta la ventana y otro que no se ven
/// exactamente igual hasta que alguien empieza a mitad de mes, y para entonces
/// ya hay quince lugares donde revisar.
///
/// La misma fórmula está en `backoffice/lib/tracking.ts` y en
/// `public.tracking_since(uuid)`. Son tres, y tienen que decir lo mismo: si el
/// PDF que genera el teléfono y la pantalla que mira la nutricionista contaran
/// distinto, estarían discutiendo sobre dos números que se llaman igual.
/// Ver `docs/contexto-diario.md`.
class TrackingWindow {
  const TrackingWindow._({
    required this.from,
    required this.to,
    required this.effectiveFrom,
    required this.trackingSince,
  });

  /// La ventana que pidió la pantalla.
  final DateTime from;
  final DateTime to;

  /// El primer día que cuenta: el de la ventana, o el primero de la persona si
  /// empezó más tarde.
  final DateTime effectiveFrom;

  /// El primer día del que hay algo cargado. `null` en una cuenta sin nada.
  final DateTime? trackingSince;

  /// Arma la ventana a partir de la que se pidió y de cuándo arrancó la persona.
  factory TrackingWindow({
    required DateTime from,
    required DateTime to,
    DateTime? trackingSince,
  }) {
    final desde = dateOnly(from);
    final hasta = dateOnly(to);
    final inicio = trackingSince == null ? null : dateOnly(trackingSince);

    return TrackingWindow._(
      from: desde,
      to: hasta,
      effectiveFrom: inicio != null && inicio.isAfter(desde) ? inicio : desde,
      trackingSince: inicio,
    );
  }

  /// Cuántos días se podían registrar. Cero si la cuenta no tiene nada, o si la
  /// persona arrancó después del final de la ventana.
  ///
  /// Nunca negativo: pedir "la semana pasada" de alguien que empezó ayer da 0,
  /// no −5, y con 0 los porcentajes se muestran como `—` en vez de dividir.
  int get effectiveDays {
    if (trackingSince == null) return 0;
    if (effectiveFrom.isAfter(to)) return 0;
    return daysBetween(effectiveFrom, to) + 1;
  }

  /// La persona empezó a usar la app después de que arrancara el período. Es lo
  /// que la pantalla tiene que **decir**, no solo tener en cuenta: "13 de 13"
  /// sin la aclaración parece un período de 13 días elegido a mano.
  bool get startedMidPeriod =>
      trackingSince != null && effectiveFrom.isAfter(from);

  /// No hay un solo día que contar.
  bool get isEmpty => effectiveDays == 0;

  /// El día cae dentro del período efectivo.
  ///
  /// Es el filtro que reemplaza a `!d.isBefore(from) && !d.isAfter(to)` en
  /// cualquier cálculo que después divida por una cantidad de días.
  bool contains(DateTime day) {
    if (trackingSince == null) return false;
    final d = dateOnly(day);
    return !d.isBefore(effectiveFrom) && !d.isAfter(to);
  }

  /// Todos los días del período efectivo, del más viejo al más nuevo.
  List<DateTime> get days => <DateTime>[
    for (var i = 0; i < effectiveDays; i++)
      effectiveFrom.add(Duration(days: i)),
  ];

  /// Qué proporción de los días que se podían registrar tienen algo.
  ///
  /// `null` —y no 0— cuando no hay ningún día que contar: un porcentaje sobre
  /// cero días no es cero por ciento, es una pregunta sin sentido.
  int? coveragePct(int daysWithRecords) {
    if (effectiveDays <= 0) return null;
    return (daysWithRecords / effectiveDays * 100).round();
  }
}

/// El primer día del que hay algo cargado, a partir de las tres colecciones que
/// lo definen.
///
/// Se pasan las fechas ya filtradas de borrados. Entran comidas, actividades y
/// pesos: el peso porque el alta guiada lo registra antes que cualquier otra
/// cosa, así que para casi todo el mundo es el primero de los tres. Se ignoran
/// agua y sueño **a propósito** — se pueden cargar hacia atrás y no marcan
/// cuándo empezó nadie.
DateTime? earliestTrackedDay(Iterable<DateTime> dates) {
  DateTime? first;
  for (final date in dates) {
    final day = dateOnly(date);
    if (first == null || day.isBefore(first)) first = day;
  }
  return first;
}
