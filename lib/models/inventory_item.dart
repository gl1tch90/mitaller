/// Producto del inventario del taller (insumos que rotan: aceites,
/// filtros, bujías, líquidos).
/// Las refacciones compradas para un trabajo específico NO entran aquí:
/// se anotan como gasto de la orden.
class InventoryItem {
  final String id;
  final String name;
  final String? barcode;
  final double quantity; // existencias actuales
  final double minStock; // mínimo para avisar
  final double cost; // lo que le costó al taller (c/u)
  final double salePrice; // a lo que se le da al cliente (c/u)
  final DateTime createdAt;

  const InventoryItem({
    required this.id,
    required this.name,
    this.barcode,
    this.quantity = 0,
    this.minStock = 0,
    this.cost = 0,
    this.salePrice = 0,
    required this.createdAt,
  });

  /// True si llegó al mínimo (hay que resurtir).
  bool get isLow => quantity <= minStock;

  /// Margen de ganancia por unidad.
  double get margin => salePrice - cost;

  InventoryItem copyWith({
    String? name,
    String? barcode,
    bool clearBarcode = false,
    double? quantity,
    double? minStock,
    double? cost,
    double? salePrice,
  }) =>
      InventoryItem(
        id: id,
        name: name ?? this.name,
        barcode: clearBarcode ? null : (barcode ?? this.barcode),
        quantity: quantity ?? this.quantity,
        minStock: minStock ?? this.minStock,
        cost: cost ?? this.cost,
        salePrice: salePrice ?? this.salePrice,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'barcode': barcode,
        'quantity': quantity,
        'minStock': minStock,
        'cost': cost,
        'salePrice': salePrice,
        'createdAt': createdAt.toIso8601String(),
      };

  factory InventoryItem.fromJson(Map<String, dynamic> json) =>
      InventoryItem(
        id: json['id'] as String,
        name: json['name'] as String,
        barcode: json['barcode'] as String?,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        minStock: (json['minStock'] as num?)?.toDouble() ?? 0,
        cost: (json['cost'] as num?)?.toDouble() ?? 0,
        salePrice: (json['salePrice'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// Calcula el precio de venta sugerido a partir del costo y el margen.
/// [marginPct] es el porcentaje (ej. 30 = 30%).
double suggestSalePrice(double cost, double marginPct) {
  if (cost <= 0 || marginPct < 0) return cost;
  final suggested = cost * (1 + marginPct / 100);
  // Redondea a pesos cerrados para que el precio se vea limpio.
  return suggested.roundToDouble();
}
