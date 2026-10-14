import 'dart:async';

import 'package:flutter/material.dart';

import '../models/attendance.dart';

/// Texto con horas en vivo, actualizándose solo cada 30 segundos.
/// Para ver "el tiempo que va en el día" sin recargar la pantalla.
/// Si no hay ningún turno abierto, muestra el número fijo sin temporizador.
class LiveHoursText extends StatefulWidget {
  final AttendanceRecord? record;

  /// Suma en vivo de varios registros (ej. todo lo de hoy).
  final List<AttendanceRecord>? records;

  final TextStyle? style;

  const LiveHoursText({
    super.key,
    required AttendanceRecord this.record,
    this.style,
  }) : records = null;

  const LiveHoursText.sum({
    super.key,
    required List<AttendanceRecord> this.records,
    this.style,
  }) : record = null;

  @override
  State<LiveHoursText> createState() => _LiveHoursTextState();
}

class _LiveHoursTextState extends State<LiveHoursText> {
  Timer? _timer;

  bool get _hasOpen => widget.records != null
      ? widget.records!.any((r) => r.isOpen)
      : widget.record!.isOpen;

  double get _value => widget.records != null
      ? widget.records!.fold<double>(0, (s, r) => s + r.hoursSoFar)
      : widget.record!.hoursSoFar;

  @override
  void initState() {
    super.initState();
    if (_hasOpen) {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(formatHours(_value), style: widget.style);
  }
}
