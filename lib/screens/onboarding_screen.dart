import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';
import '../l10n/locale_state.dart';
import '../services/backup_service.dart';
import '../services/business_service.dart';
import '../services/lang_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialog.dart';
import 'login_screen.dart';

/// Bienvenida de primer uso: explica la app y configura el taller.
/// Solo aparece en instalaciones nuevas (ver `_Root` en main.dart).
/// Con [isPreview] se puede ver desde Administración sin guardar nada.
class OnboardingScreen extends StatefulWidget {
  final bool isPreview;

  const OnboardingScreen({super.key, this.isPreview = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends LocaleAwareState<OnboardingScreen> {
  final _pageCtrl = PageController();
  final _nameCtrl = TextEditingController();
  int _page = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _next() {
    _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('onboarding_name_required'))),
      );
      return;
    }
    if (widget.isPreview) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await BusinessService.setName(name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Future<void> _setLang(String code) async {
    await LangService.setLocale(code);
  }


  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Restaura un respaldo desde la pantalla inicial: elige el archivo,
  /// confirma con el resumen y entra directo al login con los datos
  /// recuperados (sin crear ningún usuario antes).
  Future<void> _restoreFromBackup() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null || picked.path == null) return;
    final file = File(picked.path!);

    BackupSummary summary;
    try {
      summary = await BackupService.readBackup(file);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('admin_restore_invalid'))),
        );
      }
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('admin_restore_title')),
        content: Text(
          t('admin_restore_body', {
            'date': summary.exportedAt != null
                ? _fmtDate(summary.exportedAt!)
                : t('admin_restore_unknown_date'),
            'records': '${summary.recordCount}',
            'photos': '${summary.photoCount}',
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(ctx, false),
            child: Text(t('common_cancel')),
          ),
          ElevatedButton(
            onPressed: () => safePop(ctx, true),
            child: Text(t('admin_restore_confirm')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await const BackupService().restoreBackup(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(t('admin_restore_failed', {'error': '$e'}))),
        );
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 0 = bienvenida, 1..3 = funciones, 4 = nombre del taller
    const lastPage = 4;
    final features = [
      (
        icon: Icons.assignment_turned_in_outlined,
        title: t('onboarding_f1_title'),
        desc: t('onboarding_f1_desc'),
      ),
      (
        icon: Icons.build_circle_outlined,
        title: t('onboarding_f2_title'),
        desc: t('onboarding_f2_desc'),
      ),
      (
        icon: Icons.payments_outlined,
        title: t('onboarding_f3_title'),
        desc: t('onboarding_f3_desc'),
      ),
    ];
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: _page < lastPage
                  ? TextButton(
                      onPressed: () => _pageCtrl.jumpToPage(lastPage),
                      child: Text(t('onboarding_skip'),
                          style: const TextStyle(
                              color: AppTheme.textSecondary)),
                    )
                  : const SizedBox(height: 48),
            ),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _welcomePage(),
                  for (final f in features) _featurePage(f),
                  _businessPage(),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                lastPage + 1,
                (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page
                        ? AppTheme.accent
                        : AppTheme.textSecondary.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _page == lastPage ? _finish : _next,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _page == lastPage
                        ? (widget.isPreview
                            ? t('onboarding_close_preview')
                            : t('common_continue'))
                        : (_page == 0
                            ? t('onboarding_start')
                            : t('onboarding_next')),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _welcomePage() {
    final isEs = LangService.locale.value == LangService.spanish;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(32),
            ),
            child: const Icon(
              Icons.handyman,
              size: 72,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'MiTaller',
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t('onboarding_tagline'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _langButton('Español', LangService.spanish, isEs),
              const SizedBox(width: 12),
              _langButton('English', LangService.english, !isEs),
            ],
          ),
          if (!widget.isPreview) ...[
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _restoreFromBackup,
              icon: const Icon(Icons.restore_outlined),
              label: Text(t('onboarding_restore_btn')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: const BorderSide(color: AppTheme.accent, width: 2),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                t('onboarding_restore_hint'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _langButton(String label, String code, bool selected) {
    return OutlinedButton(
      onPressed: () => _setLang(code),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            selected ? AppTheme.accent : AppTheme.textSecondary,
        side: BorderSide(
          color: selected ? AppTheme.accent : AppTheme.textSecondary,
          width: selected ? 2 : 1,
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      child: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _featurePage(
      ({IconData icon, String title, String desc}) f) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(f.icon, size: 64, color: AppTheme.accent),
          ),
          const SizedBox(height: 24),
          Text(
            f.title,
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            f.desc,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _businessPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.store_outlined,
              size: 64, color: AppTheme.accent),
          const SizedBox(height: 24),
          Text(
            t('onboarding_business_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            t('onboarding_business_desc'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: t('onboarding_business_label'),
              hintText: t('onboarding_business_hint'),
              labelStyle:
                  const TextStyle(color: AppTheme.textSecondary),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
