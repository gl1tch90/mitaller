/// Pruebas del módulo de inventario.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mitaller/models/inventory_item.dart';
import 'package:mitaller/models/mechanic.dart';
import 'package:mitaller/services/pendings_service.dart';
import 'package:mitaller/models/work_order.dart';
import 'package:mitaller/models/customer.dart';
import 'package:mitaller/models/ticket.dart';
import 'package:mitaller/models/vehicle.dart';
import 'package:mitaller/models/vehicle_type.dart';
import 'package:mitaller/services/inventory_service.dart';
import 'package:mitaller/services/work_order_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InventoryItem', () {
    test('round-trip JSON', () {
      final item = InventoryItem(
        id: 'i1',
        name: 'Aceite 5W-30',
        barcode: '7501234567890',
        quantity: 6,
        minStock: 2,
        cost: 100,
        salePrice: 130,
        createdAt: DateTime(2026, 10, 7),
      );
      final back = InventoryItem.fromJson(
          jsonDecode(jsonEncode(item.toJson()))
              as Map<String, dynamic>);
      expect(back.id, 'i1');
      expect(back.barcode, '7501234567890');
      expect(back.quantity, 6);
      expect(back.salePrice, 130);
    });

    test('isLow cuando llega al mínimo', () {
      final low = InventoryItem(
        id: 'i1',
        name: 'X',
        quantity: 2,
        minStock: 2,
        createdAt: DateTime.now(),
      );
      expect(low.isLow, isTrue);
      final ok = InventoryItem(
        id: 'i2',
        name: 'Y',
        quantity: 3,
        minStock: 2,
        createdAt: DateTime.now(),
      );
      expect(ok.isLow, isFalse);
    });

    test('suggestSalePrice con 30%', () {
      expect(suggestSalePrice(100, 30), 130);
      expect(suggestSalePrice(99, 30), 129); // 128.7 -> 129
      expect(suggestSalePrice(0, 30), 0);
    });
  });

  group('InventoryService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('add + deduct + restock', () async {
      final svc = InventoryService();
      await svc.add(InventoryItem(
        id: 'i1',
        name: 'Aceite 5W-30',
        barcode: 'ABC123',
        quantity: 6,
        minStock: 2,
        cost: 100,
        salePrice: 130,
        createdAt: DateTime.now(),
      ));

      // Buscar por código
      final found = await svc.findByBarcode('ABC123');
      expect(found, isNotNull);
      expect(found!.name, 'Aceite 5W-30');
      expect(await svc.findByBarcode('NOPE'), isNull);

      // Descontar
      expect(await svc.deduct('i1', 1), isTrue);
      var items = await svc.load();
      expect(items.first.quantity, 5);

      // No deja bajar de cero
      expect(await svc.deduct('i1', 99), isFalse);
      items = await svc.load();
      expect(items.first.quantity, 5);

      // Resurtir con nuevo costo
      await svc.restock('i1', 10, newCost: 110);
      items = await svc.load();
      expect(items.first.quantity, 15);
      expect(items.first.cost, 110);
      // El precio de venta se recalcula con el margen (30% por defecto)
      expect(items.first.salePrice, 143);

      // Resurtir sin cambiar el costo no toca el precio de venta
      await svc.restock('i1', 5, newCost: 110);
      items = await svc.load();
      expect(items.first.quantity, 20);
      expect(items.first.salePrice, 143);
    });

    test('lowStock', () async {
      final svc = InventoryService();
      await svc.add(InventoryItem(
        id: 'i1',
        name: 'A',
        quantity: 1,
        minStock: 2,
        createdAt: DateTime.now(),
      ));
      await svc.add(InventoryItem(
        id: 'i2',
        name: 'B',
        quantity: 10,
        minStock: 2,
        createdAt: DateTime.now(),
      ));
      final low = await svc.lowStock();
      expect(low.length, 1);
      expect(low.first.id, 'i1');
    });

    test('seedCatalog agrega y no duplica', () async {
      final svc = InventoryService();
      final first = await svc.seedCatalog();
      expect(first, greaterThan(20));
      final items = await svc.load();
      expect(items.length, first);
      // Segunda vez no agrega nada
      final second = await svc.seedCatalog();
      expect(second, 0);
      // Se puede eliminar uno
      await svc.delete(items.first.id);
      expect((await svc.load()).length, first - 1);
    });

    test('margen configurable', () async {
      final svc = InventoryService();
      expect(await svc.marginPct(), 30);
      await svc.setMarginPct(50);
      expect(await svc.marginPct(), 50);
    });
  });

  group('Materiales en la orden', () {
    test('OrderMaterial round-trip', () {
      const m = OrderMaterial(
        itemId: 'i1',
        name: 'Bujías',
        qty: 6,
        source: 'taller',
        unitCost: 40,
        unitPrice: 52,
      );
      final back = OrderMaterial.fromJson(
          jsonDecode(jsonEncode(m.toJson()))
              as Map<String, dynamic>);
      expect(back.qty, 6);
      expect(back.totalCost, 240);
      expect(back.totalPrice, 312);
      expect(back.fromShop, isTrue);
    });

    test('OrderPurchase round-trip', () {
      const p = OrderPurchase(
        id: 'p1',
        description: 'Tapa de válvulas Toyota',
        amount: 850,
        photoPath: '/tmp/foto.jpg',
      );
      final back = OrderPurchase.fromJson(
          jsonDecode(jsonEncode(p.toJson()))
              as Map<String, dynamic>);
      expect(back.amount, 850);
      expect(back.photoPath, '/tmp/foto.jpg');
    });

    test('completeInfo descuenta y manda a revisión', () async {
      SharedPreferences.setMockInitialValues({});
      final inv = InventoryService();
      await inv.add(InventoryItem(
        id: 'i1',
        name: 'Bujías',
        quantity: 10,
        cost: 40,
        salePrice: 52,
        createdAt: DateTime.now(),
      ));
      final svc = WorkOrderService();
      final order = WorkOrder(
        id: 'o1',
        folio: 'OS-0001',
        vehicleType: VehicleType.carro,
        vehicle: Vehicle(
            id: 'v1',
            type: VehicleType.carro,
            year: 2005,
            brand: 'Nissan',
            model: 'Tsuru',
            plate: 'ABC'),
        customer: Customer(name: 'Juan', phone: '555'),
        photos: const {},
        lines: const [
          OrderLine(serviceId: 's1', name: 'Afinación')
        ],
        mechanicId: 'm1',
        createdById: 'a1',
        createdAt: DateTime.now(),
      );
      // Guardar la orden directo en prefs
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'work_orders',
          jsonEncode([order.toJson()]));

      final ok = await svc.completeInfo('o1', const [
        OrderMaterial(
            itemId: 'i1',
            name: 'Bujías',
            qty: 6,
            source: 'taller',
            unitCost: 40,
            unitPrice: 52),
      ], const [
        OrderPurchase(
            id: 'p1',
            description: 'Tapa de válvulas',
            amount: 850),
      ]);
      expect(ok, isTrue);

      // Inventario descontado
      final items = await inv.load();
      expect(items.first.quantity, 4);

      // Orden en revisión con materiales y compras
      final updated = await svc.byId('o1');
      expect(updated, isNotNull);
      expect(updated!.status, OrderStatus.inReview);
      expect(updated.materials.length, 1);
      expect(updated.purchases.length, 1);
      expect(updated.purchases.first.amount, 850);
    });

    test('completeInfo falla sin existencias', () async {
      SharedPreferences.setMockInitialValues({});
      final inv = InventoryService();
      await inv.add(InventoryItem(
        id: 'i1',
        name: 'Aceite',
        quantity: 1,
        createdAt: DateTime.now(),
      ));
      final svc = WorkOrderService();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'work_orders',
          jsonEncode([
            WorkOrder(
              id: 'o1',
              folio: 'OS-0001',
              vehicleType: VehicleType.carro,
              vehicle: Vehicle(
                  id: 'v1',
                  type: VehicleType.carro,
                  year: 2005,
                  brand: 'Nissan',
                  model: 'Tsuru',
                  plate: 'ABC'),
              customer: Customer(name: 'Juan', phone: '555'),
              photos: const {},
              lines: const [],
              mechanicId: 'm1',
              createdById: 'a1',
              createdAt: DateTime.now(),
            ).toJson()
          ]));
      final ok = await svc.completeInfo('o1', const [
        OrderMaterial(
            itemId: 'i1', name: 'Aceite', qty: 5),
      ], const []);
      expect(ok, isFalse);
      // No se descontó nada
      final items = await inv.load();
      expect(items.first.quantity, 1);
    });

    test('material del cliente no suma al ticket', () {
      const clientMat = OrderMaterial(
        itemId: 'i1',
        name: 'Aceite',
        qty: 1,
        source: 'cliente',
        unitCost: 100,
        unitPrice: 130,
      );
      expect(clientMat.fromShop, isFalse);
      // Solo lo del taller va al ticket
      final toTicket = [clientMat]
          .where((m) => m.fromShop)
          .fold(0.0, (s, m) => s + m.totalPrice);
      expect(toTicket, 0);
    });
  });

  group('Avatar de mecánico', () {
    test('default y sanitize', () {
      expect(MechanicAvatars.def, '🧑‍🔧');
      expect(MechanicAvatars.options.length, 12);
      expect(MechanicAvatars.sanitize('🔧'), '🔧');
      expect(MechanicAvatars.sanitize('xx'),
          MechanicAvatars.def);
      expect(MechanicAvatars.sanitize(null),
          MechanicAvatars.def);
    });

    test('round-trip con avatar', () {
      final m = Mechanic(
        id: 'm1',
        name: 'Pedro',
        pin: '1111',
        avatar: '🏍️',
      );
      final back = Mechanic.fromJson(
          jsonDecode(jsonEncode(m.toJson()))
              as Map<String, dynamic>);
      expect(back.avatar, '🏍️');
    });

    test('datos viejos sin avatar usan el default', () {
      final json = {
        'id': 'm1',
        'name': 'Pedro',
        'pin': '1111',
      };
      final back = Mechanic.fromJson(json);
      expect(back.avatar, MechanicAvatars.def);
    });

    test('copyWith cambia el avatar', () {
      final m = Mechanic(id: 'm1', name: 'P', pin: '1');
      final updated = m.copyWith(avatar: '⚙️');
      expect(updated.avatar, '⚙️');
      expect(m.avatar, MechanicAvatars.def);
    });
  });

  group('Pendientes (campanita)', () {
    test('total suma todos los grupos', () {
      const d = PendingsData(
        reviewCarro: 2,
        reviewMoto: 1,
        pendingExpenses: 1,
        lowStockIds: ['a', 'b'],
        lowStockNames: ['Aceite', 'Filtro'],
        vehicleAlerts: ['Aceite vencido: Tsuru'],
      );
      expect(d.reviewTotal, 3);
      expect(d.total, 7);
    });

    test('vacío da total cero', () {
      const d = PendingsData();
      expect(d.total, 0);
      expect(d.reviewTotal, 0);
    });

    test('la firma cambia si algo cambia', () {
      const a = PendingsData(reviewCarro: 1);
      const b = PendingsData(reviewCarro: 2);
      const c = PendingsData(
          reviewCarro: 1, pendingExpenses: 1);
      const d = PendingsData(
          reviewCarro: 1,
          lowStockIds: ['x'],
          lowStockNames: ['Y']);
      expect(a.signature == b.signature, isFalse);
      expect(a.signature == c.signature, isFalse);
      expect(a.signature == d.signature, isFalse);
      // Mismo conjunto, misma firma
      const a2 = PendingsData(reviewCarro: 1);
      expect(a.signature, a2.signature);
    });

    test('la firma distingue qué insumos están bajos', () {
      const a = PendingsData(
          lowStockIds: ['x'], lowStockNames: ['X']);
      const b = PendingsData(
          lowStockIds: ['y'], lowStockNames: ['Y']);
      expect(a.signature == b.signature, isFalse);
    });
  });

  group('Pendientes del mecánico', () {
    test('total y firma', () {
      const d = MechanicPendingsData(
        pendingCarro: ['o1', 'o2'],
        pausedCarro: ['o3'],
        pendingMoto: ['o4'],
      );
      expect(d.tasksTotal, 4);
      expect(d.total, 4);
      expect(d.tasksSignature(VehicleType.carro), 'p:o1,o2|z:o3');
      expect(d.tasksSignature(VehicleType.moto), 'p:o4|z:');
    });

    test('la firma cambia con altas y bajas', () {
      const a = MechanicPendingsData(pendingCarro: ['o1']);
      const b = MechanicPendingsData(
          pendingCarro: ['o1', 'o2']);
      const c = MechanicPendingsData(pausedCarro: ['o1']);
      expect(a.signature == b.signature, isFalse);
      expect(a.signature == c.signature, isFalse);
      const a2 = MechanicPendingsData(pendingCarro: ['o1']);
      expect(a.signature, a2.signature);
    });

    test('vacío da total cero', () {
      const d = MechanicPendingsData();
      expect(d.total, 0);
    });
  });
}
