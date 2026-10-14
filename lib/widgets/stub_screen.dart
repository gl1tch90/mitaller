import 'package:flutter/material.dart';
import '../l10n/strings.dart';
import '../models/vehicle_type.dart';
import '../theme/app_theme.dart';

/// Pantalla base para los módulos aún no implementados.
class StubScreen extends StatelessWidget {
  final VehicleType vehicleType;
  final String title;
  final IconData icon;
  final String description;

  const StubScreen({
    super.key,
    required this.vehicleType,
    required this.title,
    required this.icon,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              '$title · ${vehicleType == VehicleType.moto ? t('home_motos') : t('home_carros')}')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(icon, size: 48, color: AppTheme.accent),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t('stub_under_construction'),
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
