import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mitaller/models/mechanic.dart';
import 'package:mitaller/screens/admin_screen.dart';
import 'package:mitaller/services/mechanic_service.dart';

void main() {
  testWidgets('Agregar mecánico: abre el diálogo, guarda y aparece',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Fundador George.
    await MechanicService().addMechanic('George', '1234',
        isAdmin: true, isFounder: true);
    final mechs = await MechanicService().loadMechanics();
    final george = mechs.firstWhere((m) => m.name == 'George');

    await tester.pumpWidget(MaterialApp(
      home:
          AdminScreen(currentMechanicId: george.id, initialTab: 0),
    ));
    await tester.pumpAndSettle();

    // Tocar "Agregar".
    final addBtn = find.widgetWithText(ElevatedButton, 'Agregar');
    expect(addBtn, findsOneWidget,
        reason: 'debe existir el botón Agregar');
    await tester.tap(addBtn);
    await tester.pumpAndSettle();

    // El diálogo debe estar visible.
    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'el diálogo de mecánico debe abrirse');

    // Llenar nombre y PIN (4 dígitos + confirmación).
    final fields = find.byType(TextField);
    expect(fields, findsWidgets);
    await tester.enterText(fields.first, 'Juan');
    // Los campos de PIN: el segundo y tercero.
    await tester.enterText(fields.at(1), '9999');
    await tester.enterText(fields.at(2), '9999');
    await tester.pump();

    // Guardar.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
    await tester.pumpAndSettle();

    // El diálogo se cierra y Juan aparece en la lista.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Juan'), findsWidgets);

    final all = await MechanicService().loadMechanics();
    expect(all.any((m) => m.name == 'Juan'), isTrue);
    // Dejar que los timers cortos (snackbars, focos) terminen.
    await tester.pump(const Duration(seconds: 3));
  });
}
