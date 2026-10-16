# MiTaller

Punto de venta en Flutter para un taller mecánico de carros y motos.
Funciona en **un solo celular**: todos los datos se guardan en el dispositivo
(`SharedPreferences` + fotos en el almacenamiento de la app). No hay servidor.

Versión actual: ver `lib/version.dart` (`kAppVersion`, se muestra al pie
del login como diagnóstico). Formato: `AAAA.MM.DD-letra` (ej. `2026.10.08-h`).

## Requisitos

- Flutter 3.47.x (canal stable) + Android Studio / SDK de Android
- Un dispositivo Android para probar (`flutter devices`)

## Cómo correr la app

```bash
flutter clean
flutter pub get
flutter run
```

Pruebas y análisis:

```bash
flutter test
flutter analyze
```

> **Ojo:** los cambios en código nativo de Android (`android/`) requieren
> `flutter run` completo; hot restart (`R`) **no** los aplica.

## Estructura

```
lib/
  main.dart              # Entrada. _Root decide: onboarding (instalación
                         # nueva) o login. Reconstruye MaterialApp al cambiar
                         # el idioma.
  version.dart           # kAppVersion: se sube con cada ZIP/build entregado.
  l10n/
    strings.dart         # ~520 frases ES/EN + función t('clave').
    locale_state.dart     # LocaleAwareState: clase base de los State de
                         # pantallas; reconstruye la pantalla al cambiar
                         # el idioma sin reiniciar las rutas.
  models/                # 13 modelos (mechanic, task, work_order, ticket,
                         # vehicle, customer, inventory_item, attendance,
                         # shop_vehicle, service_item, client_summary...)
  services/              # 22 servicios (persistencia y lógica)
  screens/               # 27 pantallas
  widgets/               # Diálogos y componentes reutilizables
  theme/app_theme.dart   # Tema oscuro, acento azul eléctrico #2E9BFF
  utils/                 # money, dates, duration, dialog (safePop), search
test/                    # Pruebas de widget/unidad (24)
android/                 # Canal nativo: guardado de respaldos en
                         # Descargas/MiTaller vía MediaStore
```

## Módulos (pantallas principales)

| Pantalla | Qué hace |
|---|---|
| `onboarding_screen` | Bienvenida en instalaciones nuevas, idioma ES/EN, nombre del taller, restaurar respaldo |
| `login_screen` / `pin_screen` | Selector de mecánico + PIN. Reingreso a los 15 min de inactividad |
| `home_screen` | Inicio por sección (carros/motos): Servicio rápido, Punto de venta, Órdenes, Mis tareas, Tickets, Clientes, Inventario (mecánico: solo lectura), Vehículos del taller |
| `pos_screen` | Tabs Vender (→ `vehicle_data_screen` → `services_screen`) y Tickets |
| `vehicle_data_screen` | Ingreso de vehículo: 4 fotos obligatorias, VIN opcional, aceite/anticongelante (3 niveles), gasolina con aguja arrastrable, notas |
| `services_screen` | Catálogo de servicios + Servicio rápido (descripción libre) |
| `quick_service_screen` | Crea orden solo con descripción; el creador es el dueño |
| `orders_screen` / `order_detail_screen` | Órdenes activas; cronómetro pausable por orden, reasignar (admin), corregir tiempo, mandar a revisión |
| `complete_order_screen` | "Completar información": materiales del inventario (pregunta si son del taller o del cliente), compras para el trabajo, notas |
| `my_tasks_screen` | Tareas del mecánico: Pendiente → En curso → (confirmación) → Revisión; reasignar (admin/fundador) |
| `tickets_screen` / `ticket_detail_screen` / `ticket_summary_screen` | Historial de tickets; compartir en PDF/imagen |
| `clients_screen` / `client_detail_screen` | Directorio auto-agregado por teléfono, historial, botón "Nuevo servicio" por vehículo |
| `inventory_screen` / `inventory_form_screen` | Insumos que rotan: costo + precio de venta (margen 30% configurable), stock mínimo, escáner de código de barras, "Cargar insumos comunes" (27), resurtir con contador |
| `my_hours_screen` | Horas semanales del mecánico + tarjeta "Hoy" en vivo |
| `admin_screen` | Tabs: Mecánicos, Tareas, Horas, Servicios, Ingresos, Por cobrar, Negocio (idioma, nombre del taller, respaldo/restaurar, PINs) |
| `shop_vehicles_screen` / `shop_vehicle_detail_screen` | Vehículos del taller: bitácora, documentos con vencimiento, gastos (los del mecánico quedan "En revisión") |
| `profile_screen` | Mi perfil: avatar, puestos, idioma |

## Flujo principal

1. **Punto de venta** crea la orden (folio `OS-XXXX`, con vehículo/cliente/fotos) o
   **Servicio rápido** (solo descripción).
2. El mecánico la avanza en **Mis tareas**: Pendiente → En curso (cronómetro)
   → **Mandar a revisión** (abre "Completar información": materiales y compras).
3. El **admin** la revisa, tasa (precio libre) y completa → se genera el
   **ticket** (folio `0001…`).
4. Cobro: Pagado / Abono / Crédito → tab **Por cobrar** para saldos.

**Tareas** (internas): Pendiente → En curso → Revisión (admin aprueba ✓ o
rechaza ✕ con nota) → Terminada. No se puede hacer tarea y orden a la vez:
al iniciar una con cronómetro corriendo, la app pide pausar la otra.

## Roles

- **Fundador**: el primer usuario. No se puede eliminar ni degradar; nadie lo
  edita. Único que ve/cambia PINs ajenos y que respalda/restaura.
- **Admin**: operación diaria (reasignar, corregir tiempos, revisar tickets,
  aprobar gastos, ver ingresos y reportes).
- **Mecánico**: sus órdenes/tareas, inventario en solo lectura
  ("Consultar existencias"), sus horas.

Login = selector de mecánico + PIN (con confirmación al crear usuario).
Recuperación de PIN con código único en papel.

## Turnos y horas

Compuerta de turno para mecánicos (admin exento): sin entrada registrada no
pueden arrancar/reanudar cronómetros. "Registrar salida" pide confirmación y
auto-pausa cronómetros. Turno olvidado: al entrar pide la hora real de salida
y el admin la confirma en Horas.

## Respaldo

`BackupService.exportBackup()`: vuelca todo `SharedPreferences` + fotos
(base64) a un JSON. El respaldo **manual** (Negocio → Respaldar) se guarda en
`Descargas/MiTaller/` (visible en Mis archivos) y abre el menú compartir.
El **automático** (configurable cada 3/7/15/30 días) guarda ahí los 5 más
recientes. Restaurar **reemplaza** todos los datos: respaldar antes de
desinstalar.

## Idioma (bilingüe ES/EN)

- Un solo idioma global para toda la app (`LangService.locale`).
- Textos con `t('clave')` / `t('clave', {'arg': 'x'})` en `l10n/strings.dart`.
- Las pantallas extienden `LocaleAwareState` para re-renderizarse al cambiar
  el idioma sin perder la navegación.
- Los nombres guardados en otro idioma se traducen en vivo donde aplica
  (`displayServiceLineName`, `positionLabel`).

## Convenciones para contribuir

1. **Enums persistidos**: los índices se guardan en disco. Valores nuevos
   **siempre al final** (ej. `TaskStatus.inReview` se agregó al final).
2. **Diálogos con campos de texto**: el diálogo debe ser `StatefulWidget`
   dueño de sus controladores (dispose propio). Nunca `dispose()` justo
   después de `await showDialog` — la ventana sigue montada durante la
   animación de salida y provoca **pantalla roja**. Ver `lib/widgets/task_dialog.dart`
   como referencia; `utils/dialog.dart` tiene `safePop` y
   `disposeDialogControllers`.
3. **Versión**: subir `kAppVersion` en `lib/version.dart` con cada build
   entregado (formato `AAAA.MM.DD-letra`).
4. **George dirige el producto**: no agregar/quitar/reordenar funciones sin
   su visto bueno; preview visual antes de construir pantallas nuevas.
5. **Avisos persistentes**: lo ocultado con ✕ solo reaparece con algo nuevo.
6. Correr `flutter test` y `flutter analyze` antes de entregar; 0 errores.
