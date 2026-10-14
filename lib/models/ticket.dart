import 'customer.dart';
import 'quick_service.dart';
import 'vehicle.dart';
import 'vehicle_type.dart';
import '../l10n/strings.dart';

/// Una línea del ticket: servicio + precio + cantidad.
class TicketLine {
  final String serviceId;
  final String name;
  final double price;
  final int quantity;

  const TicketLine({
    required this.serviceId,
    required this.name,
    required this.price,
    this.quantity = 1,
  });

  double get subtotal => price * quantity;


  /// Nombre para mostrar: traduce en vivo lo guardado en otro idioma.
  String get displayName => displayServiceLineName(serviceId, name);

  Map<String, dynamic> toJson() => {
        'serviceId': serviceId,
        'name': name,
        'price': price,
        'quantity': quantity,
      };

  factory TicketLine.fromJson(Map<String, dynamic> json) => TicketLine(
        serviceId: json['serviceId'] as String,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
        quantity: json['quantity'] as int,
      );
}

/// Un abono registrado contra un ticket crédito.
class TicketPayment {
  final DateTime date;
  final double amount;

  const TicketPayment({required this.date, required this.amount});

  Map<String, dynamic> toJson() =>
      {'date': date.toIso8601String(), 'amount': amount};

  factory TicketPayment.fromJson(Map<String, dynamic> json) => TicketPayment(
        date: DateTime.parse(json['date'] as String),
        amount: (json['amount'] as num).toDouble(),
      );
}

/// Venta cobrada del punto de venta: vehículo, cliente, fotos de condición,
/// niveles, servicios y datos del cobro.
class Ticket {
  final String id; // folio asignado al guardar ("0001")
  final DateTime dateTime;
  final String mechanicId;
  final String mechanicName;
  final VehicleType vehicleType;
  final Vehicle vehicle;
  final Customer customer;
  final Map<String, String> photos;
  final List<TicketLine> lines;
  final double total;
  final String? paymentMethod; // Efectivo | Tarjeta | Transferencia (null: no se registró)
  final double? amountReceived;
  final double? change;
  final int workSeconds; // tiempo que tomó el trabajo (se congela al completar)

  /// Lo ya cobrado del ticket. null = pagado completo (tickets viejos).
  final double? amountPaid;

  /// Historial de abonos.
  final List<TicketPayment> payments;

  /// Lo que falta por cobrar.
  double get balance => (total - (amountPaid ?? total)).clamp(0, double.infinity);

  bool get isPaid => balance < 0.01;

  const Ticket({
    required this.id,
    required this.dateTime,
    required this.mechanicId,
    required this.mechanicName,
    required this.vehicleType,
    required this.vehicle,
    required this.customer,
    required this.photos,
    required this.lines,
    required this.total,
    this.paymentMethod,
    this.amountReceived,
    this.change,
    this.workSeconds = 0,
    this.amountPaid,
    this.payments = const [],
  });

  Ticket copyWith({String? id, double? amountPaid, List<TicketPayment>? payments}) => Ticket(
        id: id ?? this.id,
        dateTime: dateTime,
        mechanicId: mechanicId,
        mechanicName: mechanicName,
        vehicleType: vehicleType,
        vehicle: vehicle,
        customer: customer,
        photos: photos,
        lines: lines,
        total: total,
        paymentMethod: paymentMethod,
        amountReceived: amountReceived,
        change: change,
        workSeconds: workSeconds,
        amountPaid: amountPaid ?? this.amountPaid,
        payments: payments ?? this.payments,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'dateTime': dateTime.toIso8601String(),
        'mechanicId': mechanicId,
        'mechanicName': mechanicName,
        'vehicleType': vehicleType.name,
        'vehicle': vehicle.toJson(),
        'customer': customer.toJson(),
        'photos': photos,
        'lines': lines.map((l) => l.toJson()).toList(),
        'total': total,
        'paymentMethod': paymentMethod,
        'amountReceived': amountReceived,
        'change': change,
        'workSeconds': workSeconds,
        'amountPaid': amountPaid,
        'payments': payments.map((p) => p.toJson()).toList(),
      };

  factory Ticket.fromJson(Map<String, dynamic> json) => Ticket(
        id: json['id'] as String,
        dateTime: DateTime.parse(json['dateTime'] as String),
        mechanicId: json['mechanicId'] as String,
        mechanicName: json['mechanicName'] as String,
        vehicleType: VehicleType.values.byName(json['vehicleType'] as String),
        vehicle:
            Vehicle.fromJson(Map<String, dynamic>.from(json['vehicle'] as Map)),
        customer: Customer.fromJson(
            Map<String, dynamic>.from(json['customer'] as Map)),
        photos: Map<String, String>.from(json['photos'] as Map),
        lines: (json['lines'] as List)
            .map((e) =>
                TicketLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        total: (json['total'] as num).toDouble(),
        paymentMethod: json['paymentMethod'] as String?,
        amountReceived: (json['amountReceived'] as num?)?.toDouble(),
        change: (json['change'] as num?)?.toDouble(),
        workSeconds: json['workSeconds'] as int? ?? 0,
        amountPaid: (json['amountPaid'] as num?)?.toDouble(),
        payments: ((json['payments'] as List?) ?? [])
            .map((e) =>
                TicketPayment.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  /// Ticket generado desde una orden de servicio rápido:
  /// sin vehículo ni cliente, solo la descripción del trabajo.
  bool get isQuickOrder =>
      lines.length == 1 &&
      lines.first.serviceId == quickServiceId &&
      vehicle.brand.isEmpty;
}
