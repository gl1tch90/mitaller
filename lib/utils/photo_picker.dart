import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

/// Hoja inferior para elegir foto: Cámara o Galería.
/// Devuelve el XFile elegido (comprimido igual que la cámara),
/// o null si el usuario canceló.
Future<XFile?> pickPhotoChoice(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(
              Icons.photo_camera,
              color: AppTheme.accent,
            ),
            title: Text(t('photo_take')),
            onTap: () =>
                Navigator.of(ctx).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(
              Icons.photo_library,
              color: AppTheme.accent,
            ),
            title: Text(t('photo_gallery')),
            onTap: () =>
                Navigator.of(ctx).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  return ImagePicker().pickImage(
    source: source,
    maxWidth: 1600,
    imageQuality: 70,
  );
}
