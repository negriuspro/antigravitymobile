import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';

class ProviderSelector extends StatelessWidget {
  final AIProvider selected;
  final ValueChanged<AIProvider> onChanged;

  const ProviderSelector({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: AIProvider.values.map((p) {
          final isSelected = p == selected;
          return GestureDetector(
            onTap: () => onChanged(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.accent : AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? AppTheme.accent : AppTheme.border),
              ),
              child: Text(
                p.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? AppTheme.bg : AppTheme.textPrimary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
