import '../l10n/strings.dart';
import 'customer.dart';
import 'quick_service.dart';
import 'ticket.dart';
import 'vehicle.dart';
import 'vehicle_type.dart';

/// Estado de una orden de servicio (el trabajo en el taller).
/// Flujo: Pendiente → En curso ⇄ En pausa → En revisión → Completada (genera el ticket).
/// El cronómetro corre mientras está "En curso"; en "En pausa" se detiene
/// sin finalizar la orden.
enum OrderStatus { pending, inProgress, paused, inReview, completed }

extension OrderStatusX on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.pending:
        return 'Pendiente';
      case OrderStatus.inProgress:
        return 'En curso';
      case OrderStatus.paused:
        return 'En pausa';
      case OrderStatus.inReview:
        return 'En revisión';
      case OrderStatus.completed:
        return 'Completada';
    }
  }
}

/// Línea de la orden: servicio + precio.
/// El precio puede quedar pendiente (null) en el "Servicio rápido":
/// lo escribe el administrador al revisar la orden.
class OrderLine {
  final String serviceId;
  final String name;
  final double? price;
  final String? note; // descripción del servicio rápido

  const OrderLine({
    required this.serviceId,
    required this.name,
    this.price,
    this.note,
  });

  bool get isQuick => serviceId == quickServiceId;
  bool get needsPrice => price == null;

  Map<String, dynamic> toJson() => {
        'serviceId': serviceId,
        'name': name,
        'price': price,
        'note': note,
      };

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
        serviceId: json['serviceId'] as String,
        name: json['name'] as String,
        price: (json['price'] as num?)?.toDouble(),
        note: json['note'] as String?,
      );

  /// Convierte la línea en línea de ticket (el precio ya debe estar puesto).
  TicketLine toTicketLine() => TicketLine(
        serviceId: serviceId,
        name: note?.isNotEmpty == true ? '$name: $note' : name,
        price: price ?? 0,
      );
}

/// Material del inventario usado en la orden (insumo).
/// [source]: 'taller' (se descuenta del inventario) o 'cliente'
/// (lo trajo el cliente, no se descuenta).
class OrderMaterial {
  final String itemId; // id en el inventario ('' si se borró el producto)
  final String name;
  final double qty;
  final String source; // 'taller' | 'cliente'
  final double unitCost; // lo que le costó al taller (c/u)
  final double unitPrice; // precio de venta (c/u)

  const OrderMaterial({
    required this.itemId,
    required this.name,
    required this.qty,
    this.source = 'taller',
    this.unitCost = 0,
    this.unitPrice = 0,
  });

  bool get fromShop => source == 'taller';
  double get totalCost => unitCost * qty;
  double get totalPrice => unitPrice * qty;

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'name': name,
        'qty': qty,
        'source': source,
        'unitCost': unitCost,
        'unitPrice': unitPrice,
      };

  factory OrderMaterial.fromJson(Map<String, dynamic> json) =>
      OrderMaterial(
        itemId: json['itemId'] as String? ?? '',
        name: json['name'] as String,
        qty: (json['qty'] as num).toDouble(),
        source: json['source'] as String? ?? 'taller',
        unitCost: (json['unitCost'] as num?)?.toDouble() ?? 0,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
      );
}

/// Compra hecha para este trabajo específico (refacción que no está en
/// el inventario). No mueve el inventario; queda como gasto de la orden.
/// La foto del ticket es opcional.
class OrderPurchase {
  final String id;
  final String description;
  final double amount;
  final String? photoPath;

  const OrderPurchase({
    required this.id,
    required this.description,
    required this.amount,
    this.photoPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'amount': amount,
        'photoPath': photoPath,
      };

  factory OrderPurchase.fromJson(Map<String, dynamic> json) =>
      OrderPurchase(
        id: json['id'] as String,
        description: json['description'] as String,
        amount: (json['amount'] as num).toDouble(),
        photoPath: json['photoPath'] as String?,
      );
}

/// Orden de servicio: el trabajo que entra al taller.
/// Se crea desde el punto de venta, el mecánico la avanza en "Mis tareas"
/// y al terminarla la manda a revisión; el administrador la revisa,
/// pone los precios pendientes y completa el ticket.
class WorkOrder {
  final String id;
  final String folio; // "OS-0001"
  final VehicleType vehicleType;
  final Vehicle vehicle;
  final Customer customer;
  final Map<String, String> photos;
  final List<OrderLine> lines;
  final String mechanicId; // mecánico asignado
  final String createdById; // quién creó la orden
  final OrderStatus status;
  final DateTime createdAt;
  final int workSeconds; // tiempo trabajado acumulado (sin contar la racha actual)
  final DateTime? timerStart; // momento en que arrancó la racha actual (null = detenido)
  /// Fecha en que se hizo el trabajo cuando se registró manual ("Ya la
  /// realicé"). Null = se midió con el cronómetro.
  final DateTime? manualWorkDate;
  /// Id del vehículo del taller si la orden es trabajo interno.
  /// Null = orden normal de cliente.
  final String? shopVehicleId;
  /// Materiales del inventario usados (los reporta el mecánico al
  /// completar la información antes de mandar a revisión).
  final List<OrderMaterial> materials;
  /// Compras hechas para este trabajo (no pasan por el inventario).
  final List<OrderPurchase> purchases;

  const WorkOrder({
    required this.id,
    required this.folio,
    required this.vehicleType,
    required this.vehicle,
    required this.customer,
    required this.photos,
    required this.lines,
    required this.mechanicId,
    required this.createdById,
    this.status = OrderStatus.pending,
    required this.createdAt,
    this.workSeconds = 0,
    this.timerStart,
    this.manualWorkDate,
    this.shopVehicleId,
    this.materials = const [],
    this.purchases = const [],
  });

  /// Orden creada con el botón "Servicio rápido": una sola línea de
  /// servicio rápido y sin datos de vehículo ni cliente.
  bool get isQuickOrder =>
      lines.length == 1 && lines.first.isQuick && vehicle.brand.isEmpty;

  /// ¿El cronómetro está corriendo ahora mismo?
  bool get isTimerRunning => timerStart != null;

  /// ¿Es trabajo interno en un vehículo del taller (no de cliente)?
  bool get isInternal => shopVehicleId != null;

  /// Nombre del cliente para mostrar: en órdenes internas la etiqueta se
  /// traduce en vivo (la guardada quedó en el idioma de cuando se creó).
  String get displayCustomerName =>
      isInternal ? t('shop_vehicle_work_on_customer') : customer.name;

  /// Nombre de línea de servicio para mostrar: lo que se guardó en
  /// otro idioma se traduce en vivo (servicios semilla, servicio rápido
  /// y la línea auto-generada de órdenes internas).
  String displayLineName(OrderLine l) {
    if (isInternal && l.serviceId == quickServiceId) {
      return t('shop_vehicle_service_name');
    }
    return displayServiceLineName(l.serviceId, l.name);
  }

  /// Segundos trabajados en total, incluyendo la racha actual si corre.
  int get elapsedSeconds {
    var total = workSeconds;
    final start = timerStart;
    if (start != null) {
      total += DateTime.now().difference(start).inSeconds;
    }
    return total < 0 ? 0 : total;
  }

  WorkOrder copyWith({
    OrderStatus? status,
    List<OrderLine>? lines,
    List<OrderMaterial>? materials,
    List<OrderPurchase>? purchases,
    int? workSeconds,
    DateTime? timerStart,
    bool clearTimerStart = false,
    DateTime? manualWorkDate,
    String? shopVehicleId,
    String? mechanicId,
  }) =>
      WorkOrder(
        id: id,
        folio: folio,
        vehicleType: vehicleType,
        vehicle: vehicle,
        customer: customer,
        photos: photos,
        lines: lines ?? this.lines,
        materials: materials ?? this.materials,
        purchases: purchases ?? this.purchases,
        mechanicId: mechanicId ?? this.mechanicId,
        createdById: createdById,
        status: status ?? this.status,
        createdAt: createdAt,
        workSeconds: workSeconds ?? this.workSeconds,
        timerStart: clearTimerStart ? null : (timerStart ?? this.timerStart),
        manualWorkDate: manualWorkDate ?? this.manualWorkDate,
        shopVehicleId: shopVehicleId ?? this.shopVehicleId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'folio': folio,
        'vehicleType': vehicleType.name,
        'vehicle': vehicle.toJson(),
        'customer': customer.toJson(),
        'photos': photos,
        'lines': lines.map((l) => l.toJson()).toList(),
        'mechanicId': mechanicId,
        'createdById': createdById,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'workSeconds': workSeconds,
        'timerStart': timerStart?.toIso8601String(),
        'manualWorkDate': manualWorkDate?.toIso8601String(),
        'shopVehicleId': shopVehicleId,
        'materials': materials.map((m) => m.toJson()).toList(),
        'purchases': purchases.map((p) => p.toJson()).toList(),
      };

  /// Lee el estado guardado. Acepta el formato viejo (índice numérico,
  /// sin el estado "paused": 0 Pendiente, 1 En curso, 2 En revisión, 3 Completada).
  static OrderStatus _statusFromJson(dynamic raw) {
    if (raw is String) {
      return OrderStatus.values.byName(raw);
    }
    switch (raw as int) {
      case 0:
        return OrderStatus.pending;
      case 1:
        return OrderStatus.inProgress;
      case 2:
        return OrderStatus.inReview;
      default:
        return OrderStatus.completed;
    }
  }

  factory WorkOrder.fromJson(Map<String, dynamic> json) => WorkOrder(
        id: json['id'] as String,
        folio: json['folio'] as String,
        vehicleType: VehicleType.values.byName(json['vehicleType'] as String),
        vehicle:
            Vehicle.fromJson(Map<String, dynamic>.from(json['vehicle'] as Map)),
        customer: Customer.fromJson(
            Map<String, dynamic>.from(json['customer'] as Map)),
        photos: Map<String, String>.from(json['photos'] as Map),
        lines: (json['lines'] as List)
            .map((e) =>
                OrderLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        mechanicId: json['mechanicId'] as String,
        createdById: json['createdById'] as String? ?? '',
        status: _statusFromJson(json['status']),
        createdAt: DateTime.parse(json['createdAt'] as String),
        workSeconds: json['workSeconds'] as int? ?? 0,
        timerStart: json['timerStart'] == null
            ? null
            : DateTime.parse(json['timerStart'] as String),
        manualWorkDate: json['manualWorkDate'] == null
            ? null
            : DateTime.parse(json['manualWorkDate'] as String),
        shopVehicleId: json['shopVehicleId'] as String?,
        materials: (json['materials'] as List?)
                ?.map((e) => OrderMaterial.fromJson(
                    Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        purchases: (json['purchases'] as List?)
                ?.map((e) => OrderPurchase.fromJson(
                    Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
      );
}
