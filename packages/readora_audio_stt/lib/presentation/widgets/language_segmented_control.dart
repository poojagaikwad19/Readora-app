import 'package:flutter/material.dart';
import '../../config/stt_language.dart';

class LanguageSegmentedControl extends StatelessWidget {
  final SttLanguage selected;
  final ValueChanged<SttLanguage> onLanguageChanged;
  final Color primaryColor;

  const LanguageSegmentedControl({
    Key? key,
    required this.selected,
    required this.onLanguageChanged,
    this.primaryColor = const Color(0xFF6366F1), // Readora indigo primary
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.2),
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: SttLanguage.values.map((lang) {
          final isSelected = lang == selected;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onLanguageChanged(lang),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      lang.nativeName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Colors.white
                            : Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                    Text(
                      lang.displayName,
                      style: TextStyle(
                        fontSize: 10,
                        color: isSelected
                            ? Colors.white.withOpacity(0.85)
                            : Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
