import 'package:flutter/material.dart';
import '../document_tts/presentation/widgets/readora_language_selector.dart';

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
    return ReadoraLanguageSelector(
      selectedLanguage: selectedLanguage,
      onChanged: onChanged,
    );
  }
}
