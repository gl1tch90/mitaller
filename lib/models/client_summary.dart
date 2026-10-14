import 'customer.dart';
import 'ticket.dart';
import 'vehicle.dart';
import 'work_order.dart';

/// Cliente agregado a partir de órdenes y tickets: sus vehículos
/// y su historial (órdenes activas + tickets cobrados).
class ClientSummary {
  final String name;
  final String phone;
  final List<Vehicle> vehicles;
  final List<WorkOrder> orders;
  final List<Ticket> tickets;

  const ClientSummary({
    required this.name,
    required this.phone,
    required this.vehicles,
    required this.orders,
    required this.tickets,
  });

  /// Llave para agrupar: el teléfono si hay, si no el nombre.
  static String keyOf(Customer c) {
    final phone = c.phone.trim();
    if (phone.isNotEmpty) return 'tel:$phone';
    return 'nom:${c.name.trim().toLowerCase()}';
  }

  int get totalVisits => orders.length + tickets.length;

  /// Agrupa órdenes y tickets por cliente (omite servicios rápidos,
  /// que no tienen cliente).
  static List<ClientSummary> aggregate({
    required List<WorkOrder> orders,
    required List<Ticket> tickets,
  }) {
    final Map<String, _Bucket> buckets = {};

    _Bucket bucketFor(Customer c) =>
        buckets.putIfAbsent(keyOf(c), () => _Bucket(c.name, c.phone));

    for (final o in orders) {
      if (o.isQuickOrder || o.customer.name.trim().isEmpty) continue;
      final b = bucketFor(o.customer);
      b.orders.add(o);
      if (b.vehicles.every((v) => v.plate != o.vehicle.plate)) {
        b.vehicles.add(o.vehicle);
      }
    }
    for (final t in tickets) {
      if (t.isQuickOrder || t.customer.name.trim().isEmpty) continue;
      final b = bucketFor(t.customer);
      b.tickets.add(t);
      if (b.vehicles.every((v) => v.plate != t.vehicle.plate)) {
        b.vehicles.add(t.vehicle);
      }
    }

    final list = buckets.values
        .map((b) => ClientSummary(
              name: b.name,
              phone: b.phone,
              vehicles: b.vehicles,
              orders: b.orders
                ..sort((a, c) => c.createdAt.compareTo(a.createdAt)),
              tickets: b.tickets
                ..sort((a, c) => c.dateTime.compareTo(a.dateTime)),
            ))
        .toList()
      ..sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }
}

class _Bucket {
  final String name;
  final String phone;
  final List<Vehicle> vehicles = [];
  final List<WorkOrder> orders = [];
  final List<Ticket> tickets = [];

  _Bucket(this.name, this.phone);
}
