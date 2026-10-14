import 'package:flutter/material.dart';

/// Tipo de vehículo que atiende la sección activa de la app.
enum VehicleType { moto, carro }

extension VehicleTypeX on VehicleType {
  String get label => this == VehicleType.moto ? 'Motos' : 'Carros';

  String get singular => this == VehicleType.moto ? 'moto' : 'carro';

  String get description => this == VehicleType.moto
      ? 'Servicios para motocicletas'
      : 'Servicios para automóviles';

  IconData get icon =>
      this == VehicleType.moto ? Icons.two_wheeler : Icons.directions_car;
}
