import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Barrita de búsqueda con botón para limpiar.
class SearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const SearchField({super.key, required this.hint, required this.onChanged});

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _ctrl,
        onChanged: (v) {
          setState(() {});
          widget.onChanged(v);
        },
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(color: AppTheme.textSecondary),
          prefixIcon:
              const Icon(Icons.search, color: AppTheme.textSecondary),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear,
                      color: AppTheme.textSecondary),
                  onPressed: () {
                    _ctrl.clear();
                    setState(() {});
                    widget.onChanged('');
                  },
                ),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        ),
      ),
    );
  }
}
