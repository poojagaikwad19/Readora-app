import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class LanguageSelector extends StatelessWidget {
  final String selectedLanguage;
  final ValueChanged<String> onChanged;

  const LanguageSelector({
    super.key,
    required this.selectedLanguage,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final languages = [
      {'key': 'english', 'label': 'English', 'flag': '🇺🇸'},
      {'key': 'marathi', 'label': 'Marathi (मराठी)', 'flag': '🇮🇳'},
      {'key': 'hindi', 'label': 'Hindi (हिन्दी)', 'flag': '🇮🇳'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: languages.any((l) => l['key'] == selectedLanguage.toLowerCase())
              ? selectedLanguage.toLowerCase()
              : 'english',
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
          isExpanded: true,
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
          items: languages.map((lang) {
            return DropdownMenuItem<String>(
              value: lang['key'],
              child: Row(
                children: [
                  Text(lang['flag']!, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      lang['label']!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
