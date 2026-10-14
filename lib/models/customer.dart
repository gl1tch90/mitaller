/// Datos del cliente que deja su vehículo o moto en el taller.
class Customer {
  final String name;
  final String phone;

  const Customer({
    required this.name,
    required this.phone,
  });

  /// "Juan Pérez · 4431234567"
  String get label => '$name · $phone';

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        name: json['name'] as String,
        phone: json['phone'] as String,
      );
}
