/// Formato de moneda MXN sin decimales: 1800 -> "$1,800".
String formatMoney(double value) {
  final digits = value.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final pos = digits.length - i;
    buf.write(digits[i]);
    if (pos > 1 && pos % 3 == 1) buf.write(',');
  }
  return '\$$buf';
}
