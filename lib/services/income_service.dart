import '../l10n/strings.dart';
import '../models/ticket.dart';

/// Un periodo (día, semana o mes) con sus tickets y su total cobrado.
class IncomeBucket {
  final DateTime start;
  final String label;
  final List<Ticket> tickets;

  const IncomeBucket({
    required this.start,
    required this.label,
    required this.tickets,
  });

  double get total => tickets.fold(0.0, (s, t) => s + t.total);
  int get count => tickets.length;
}

/// Claves de localización para los nombres de mes, abreviaturas y días
/// de semana que se muestran en las etiquetas de los periodos.
const _monthKeys = [
  'income_january',
  'income_february',
  'income_march',
  'income_april',
  'income_may',
  'income_june',
  'income_july',
  'income_august',
  'income_september',
  'income_october',
  'income_november',
  'income_december',
];

const _monthAbbrKeys = [
  'income_abbr_jan',
  'income_abbr_feb',
  'income_abbr_mar',
  'income_abbr_apr',
  'income_abbr_may',
  'income_abbr_jun',
  'income_abbr_jul',
  'income_abbr_aug',
  'income_abbr_sep',
  'income_abbr_oct',
  'income_abbr_nov',
  'income_abbr_dec',
];

const _weekdayKeys = [
  'income_monday',
  'income_tuesday',
  'income_wednesday',
  'income_thursday',
  'income_friday',
  'income_saturday',
  'income_sunday',
];

String _month(int m) => t(_monthKeys[m - 1]);
String _monthAbbr(int m) => t(_monthAbbrKeys[m - 1]);
String _weekday(int w) => t(_weekdayKeys[w - 1]);

String _two(int n) => n.toString().padLeft(2, '0');

/// Agrupa tickets por día (más reciente primero).
List<IncomeBucket> groupIncomeByDay(List<Ticket> tickets) {
  final map = <String, List<Ticket>>{};
  for (final t in tickets) {
    final d = t.dateTime;
    final key = '${d.year}-${_two(d.month)}-${_two(d.day)}';
    map.putIfAbsent(key, () => []).add(t);
  }
  final buckets = map.entries.map((e) {
    final d = e.value.first.dateTime;
    return IncomeBucket(
      start: DateTime(d.year, d.month, d.day),
      label: t('income_day_label', {
        'weekday': _weekday(d.weekday),
        'day': '${d.day}',
        'day2': _two(d.day),
        'month': _month(d.month),
      }),
      tickets: e.value,
    );
  }).toList();
  buckets.sort((a, b) => b.start.compareTo(a.start));
  return buckets;
}

/// Agrupa tickets por semana (lunes a domingo, más reciente primero).
List<IncomeBucket> groupIncomeByWeek(List<Ticket> tickets) {
  final map = <String, List<Ticket>>{};
  for (final t in tickets) {
    final d = t.dateTime;
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final key = '${monday.year}-${_two(monday.month)}-${_two(monday.day)}';
    map.putIfAbsent(key, () => []).add(t);
  }
  final buckets = map.entries.map((e) {
    final m = e.value.first.dateTime
        .subtract(Duration(days: e.value.first.dateTime.weekday - 1));
    final monday = DateTime(m.year, m.month, m.day);
    final sunday = monday.add(const Duration(days: 6));
    return IncomeBucket(
      start: monday,
      label: t('income_week_label', {
        'd1': _two(monday.day),
        'm1': _monthAbbr(monday.month),
        'd2': _two(sunday.day),
        'm2': _monthAbbr(sunday.month),
      }),
      tickets: e.value,
    );
  }).toList();
  buckets.sort((a, b) => b.start.compareTo(a.start));
  return buckets;
}

/// Agrupa tickets por mes (más reciente primero).
List<IncomeBucket> groupIncomeByMonth(List<Ticket> tickets) {
  final map = <String, List<Ticket>>{};
  for (final t in tickets) {
    final d = t.dateTime;
    final key = '${d.year}-${_two(d.month)}';
    map.putIfAbsent(key, () => []).add(t);
  }
  final buckets = map.entries.map((e) {
    final d = e.value.first.dateTime;
    return IncomeBucket(
      start: DateTime(d.year, d.month, 1),
      label: t('income_month_label', {
        'month': _month(d.month),
        'year': '${d.year}',
      }),
      tickets: e.value,
    );
  }).toList();
  buckets.sort((a, b) => b.start.compareTo(a.start));
  return buckets;
}
