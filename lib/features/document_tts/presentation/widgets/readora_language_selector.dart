import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import 'readora_selector_manager.dart';

class ReadoraLanguageSelector extends StatefulWidget {
  final String selectedLanguage;
  final ValueChanged<String> onChanged;

  const ReadoraLanguageSelector({
    super.key,
    required this.selectedLanguage,
    required this.onChanged,
  });

  @override
  State<ReadoraLanguageSelector> createState() => _ReadoraLanguageSelectorState();
}

class _ReadoraLanguageSelectorState extends State<ReadoraLanguageSelector> {
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  static const List<Map<String, String>> _languages = [
    {'key': 'english', 'label': 'English'},
    {'key': 'marathi', 'label': 'Marathi'},
    {'key': 'hindi', 'label': 'Hindi'},
  ];

  @override
  void didUpdateWidget(covariant ReadoraLanguageSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedLanguage.toLowerCase() != widget.selectedLanguage.toLowerCase() && _isOpen) {
      _closeDropdown();
    }
  }

  @override
  void dispose() {
    ReadoraSelectorManager.unregister(_closeDropdown);
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isOpen = false;
    super.dispose();
  }

  void _toggleDropdown() {
    if (_overlayEntry != null) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _closeDropdown() {
    ReadoraSelectorManager.unregister(_closeDropdown);
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() {
        _isOpen = false;
      });
    }
  }

  void _openDropdown() {
    ReadoraSelectorManager.registerOpen(_closeDropdown);

    final renderBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final fieldSize = renderBox.size;
    final fieldOffset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    final availableScreenHeight = screenSize.height - keyboardHeight;

    double popupWidth = fieldSize.width;
    double left = fieldOffset.dx;

    if (left < 16.0) {
      left = 16.0;
    }
    if (left + popupWidth > screenSize.width - 16.0) {
      popupWidth = screenSize.width - 32.0;
      left = 16.0;
    }

    const double rowHeight = 48.0;
    final double contentHeight = (_languages.length * rowHeight) + 8.0; // 152px
    final double maxAllowedHeight = math.min(contentHeight, availableScreenHeight * 0.40);

    final double spaceBelow = availableScreenHeight - (fieldOffset.dy + fieldSize.height) - padding.bottom - 8.0;
    final double spaceAbove = fieldOffset.dy - padding.top - 8.0;

    bool showAbove = false;
    double actualHeight = maxAllowedHeight;

    if (spaceBelow < maxAllowedHeight && spaceAbove > spaceBelow) {
      showAbove = true;
      actualHeight = math.min(maxAllowedHeight, spaceAbove);
    } else {
      actualHeight = math.min(maxAllowedHeight, spaceBelow);
    }

    final double top = showAbove
        ? math.max(padding.top + 8.0, fieldOffset.dy - actualHeight - 6.0)
        : (fieldOffset.dy + fieldSize.height + 6.0);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB);
    final textPrimary = isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary;
    final textMuted = isDark ? const Color(0xFF94A3B8) : AppColors.textMuted;
    final lavenderSurface = isDark ? const Color(0xFF2E2452) : AppColors.lavenderSurface;
    final primaryColor = isDark ? const Color(0xFFC4B5FD) : AppColors.primary;

    setState(() {
      _isOpen = true;
    });

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return PopScope(
          onPopInvokedWithResult: (didPop, result) {
            _closeDropdown();
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeDropdown,
                  child: Container(color: Colors.transparent),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                width: popupWidth,
                height: actualHeight,
                child: Material(
                  elevation: 8,
                  shadowColor: Colors.black.withOpacity(isDark ? 0.3 : 0.12),
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor, width: 1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _languages.map((lang) {
                          final key = lang['key']!;
                          final label = lang['label']!;
                          final isSelected = key == widget.selectedLanguage.toLowerCase();

                          return InkWell(
                            onTap: () {
                              _closeDropdown();
                              widget.onChanged(key);
                            },
                            child: Container(
                              height: rowHeight,
                              color: isSelected ? lavenderSurface : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.public_rounded,
                                    size: 18,
                                    color: isSelected ? primaryColor : textMuted,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected ? primaryColor : textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                      color: primaryColor,
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final currentKey = widget.selectedLanguage.toLowerCase();
    final selectedLang = _languages.firstWhere(
      (l) => l['key'] == currentKey,
      orElse: () => _languages.first,
    );

    return InkWell(
      key: _fieldKey,
      onTap: _toggleDropdown,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isOpen ? AppColors.primary : context.borderColor,
            width: _isOpen ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.public_rounded,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selectedLang['label']!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimaryColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              color: _isOpen ? AppColors.primary : context.textSecondaryColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
