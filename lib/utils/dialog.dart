import 'package:flutter/widgets.dart';

/// Cierra un diálogo (o ruta) de forma segura.
///
/// Quita el foco ANTES de hacer pop y espera un instante para que el
/// cambio de foco se procese por completo antes de iniciar la transición
/// de salida. Si se hace pop con un campo de texto enfocado (o recién
/// desenfocado sin que el framework lo haya procesado), la desactivación
/// de la ruta deja dependientes colgados y provoca la pantalla roja
/// ('_dependents.isEmpty': is not true).
///
/// El pop se difiere ~100 ms (imperceptible al tacto); si el contexto ya
/// no está montado cuando toca cerrar, no hace nada.
void safePop(BuildContext context, [Object? result]) {
  FocusManager.instance.primaryFocus?.unfocus();
  Future.delayed(const Duration(milliseconds: 100), () {
    if (!context.mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop(result);
  });
}

/// Libera los controladores de texto de un diálogo de forma segura.
///
/// El future de showDialog se completa en cuanto se llama a pop, ANTES de
/// que termine la animación de salida del diálogo. Liberar los
/// controladores en ese momento deja a los campos de texto todavía
/// montados (durante la animación) con un controlador muerto, lo que
/// provoca la pantalla roja. Se espera a que la transición termine.
void disposeDialogControllers(List<TextEditingController> ctrls) {
  Future.delayed(const Duration(milliseconds: 400), () {
    for (final c in ctrls) {
      c.dispose();
    }
  });
}
