import 'package:intl/intl.dart';

/// Utilidades de fecha.
///
/// El "día" del usuario se resuelve con `local_date`, calculada **en el
/// cliente** con la zona horaria del perfil y persistida (D-09). El servidor
/// nunca la recalcula.
const String appLocale = 'es_AR';

/// `YYYY-MM-DD` — la forma canónica de `local_date`.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Fecha sin hora, para comparar días.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime today() => dateOnly(DateTime.now());

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool isToday(DateTime d) => isSameDay(d, DateTime.now());

bool isYesterday(DateTime d) =>
    isSameDay(d, DateTime.now().subtract(const Duration(days: 1)));

bool isFuture(DateTime d) => dateOnly(d).isAfter(today());

/// Hasta cuántos días adelante se puede planificar una comida.
///
/// Tres alcanza para dejar armada la semana corta sin que Inicio se vuelva un
/// calendario: más que eso ya es otra pantalla.
const int maxPlanningDays = 3;

/// El día está dentro de la ventana en la que se puede cargar comida.
bool isPlannable(DateTime d) {
  final diff = dateOnly(d).difference(today()).inDays;
  return diff <= maxPlanningDays;
}

/// Lunes de la semana ISO que contiene [d].
DateTime startOfIsoWeek(DateTime d) {
  final day = dateOnly(d);
  return day.subtract(Duration(days: day.weekday - 1));
}

int daysBetween(DateTime from, DateTime to) =>
    dateOnly(to).difference(dateOnly(from)).inDays;

/// "Hoy" · "Ayer" · "vie 25 jul" — cabecera del selector de día en Inicio.
String friendlyDay(DateTime d) {
  if (isToday(d)) return 'Hoy';
  if (isYesterday(d)) return 'Ayer';
  if (isSameDay(d, DateTime.now().add(const Duration(days: 1)))) {
    return 'Mañana';
  }
  final formatted = DateFormat('EEE d MMM', appLocale).format(d);
  return _capitalize(formatted.replaceAll('.', ''));
}

/// "viernes 25 de julio" — títulos de detalle del día.
String longDay(DateTime d) =>
    _capitalize(DateFormat("EEEE d 'de' MMMM", appLocale).format(d));

/// "25 jul" — ejes de gráficos y filas densas.
String shortDay(DateTime d) =>
    DateFormat('d MMM', appLocale).format(d).replaceAll('.', '');

/// "Julio 2026" — encabezados de mes en Historial.
String monthTitle(DateTime d) =>
    _capitalize(DateFormat('MMMM yyyy', appLocale).format(d));

/// "14:30".
String timeOfDay(DateTime d) => DateFormat('HH:mm', appLocale).format(d);

/// "25/07/2026".
String numericDate(DateTime d) => DateFormat('dd/MM/yyyy', appLocale).format(d);

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
