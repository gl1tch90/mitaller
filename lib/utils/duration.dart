/// Formatea segundos trabajados: "45s", "12m 30s", "2h 5m".
String formatWorkTime(int totalSeconds) {
  final s = totalSeconds < 0 ? 0 : totalSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${sec}s';
  return '${sec}s';
}
