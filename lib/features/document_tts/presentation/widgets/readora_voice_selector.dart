import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/voice_model.dart';
import 'readora_selector_manager.dart';

class ProcessedVoice {
  final String name;
  final String description;

  ProcessedVoice({
    required this.name,
    required this.description,
  });
}

ProcessedVoice processVoiceForDisplay(VoiceModel voice) {
  // Hide redundant "(premade)" suffix in UI only
  String rawName = voice.name.replaceAll(RegExp(r'\s*\(\s*premade\s*\)', caseSensitive: false), '').trim();

  String namePart = rawName;
  String descPart = voice.description.trim();

  if (rawName.contains(' - ')) {
    final parts = rawName.split(' - ');
    namePart = parts[0].trim();
    if (descPart.isEmpty && parts.length > 1) {
      descPart = parts.sublist(1).join(' - ').trim();
    }
  } else if (rawName.contains(' (') && rawName.endsWith(')')) {
    final idx = rawName.indexOf(' (');
    namePart = rawName.substring(0, idx).trim();
    if (descPart.isEmpty) {
      descPart = rawName.substring(idx + 2, rawName.length - 1).trim();
    }
  }

  return ProcessedVoice(
    name: namePart.isNotEmpty ? namePart : voice.name,
    description: descPart,
  );
}

class ReadoraVoiceSelector extends StatefulWidget {
  final List<VoiceModel> voices;
  final String selectedVoiceId;
  final ValueChanged<String> onVoiceSelected;

  const ReadoraVoiceSelector({
    super.key,
    required this.voices,
    required this.selectedVoiceId,
    required this.onVoiceSelected,
  });

  @override
  State<ReadoraVoiceSelector> createState() => _ReadoraVoiceSelectorState();
}

class _ReadoraVoiceSelectorState extends State<ReadoraVoiceSelector> {
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void didUpdateWidget(covariant ReadoraVoiceSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.selectedVoiceId != widget.selectedVoiceId || oldWidget.voices.length != widget.voices.length) && _isOpen) {
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
    if (widget.voices.isEmpty) return;
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

    final double maxAllowedHeight = math.min(320.0, availableScreenHeight * 0.40);

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

    final selectedIndex = widget.voices.indexWhere((v) => v.voiceId == widget.selectedVoiceId);
    const double itemHeight = 52.0;
    final double maxScroll = math.max(0.0, (widget.voices.length * itemHeight) - actualHeight + 8.0);
    final double initialScrollOffset = selectedIndex > 0
        ? (selectedIndex * itemHeight).clamp(0.0, maxScroll)
        : 0.0;

    final scrollController = ScrollController(initialScrollOffset: initialScrollOffset);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB);
    final textPrimary = isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary;
    final textSecondary = isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary;
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
                      child: Scrollbar(
                        controller: scrollController,
                        thumbVisibility: true,
                        radius: const Radius.circular(4),
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: widget.voices.length,
                          itemExtent: itemHeight,
                          itemBuilder: (context, index) {
                            if (index < 0 || index >= widget.voices.length) {
                              return const SizedBox.shrink();
                            }
                            final voice = widget.voices[index];
                            final isSelected = voice.voiceId == widget.selectedVoiceId;
                            final processed = processVoiceForDisplay(voice);

                            return InkWell(
                              onTap: () {
                                _closeDropdown();
                                widget.onVoiceSelected(voice.voiceId);
                              },
                              child: Container(
                                color: isSelected ? lavenderSurface : Colors.transparent,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.record_voice_over_rounded,
                                      size: 18,
                                      color: isSelected ? primaryColor : AppColors.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            processed.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                              color: isSelected ? primaryColor : textPrimary,
                                            ),
                                          ),
                                          if (processed.description.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              processed.description,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.normal,
                                                color: isSelected ? primaryColor : textSecondary,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (isSelected) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.check_rounded,
                                        size: 18,
                                        color: primaryColor,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
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
    VoiceModel? selectedVoice;
    try {
      selectedVoice = widget.voices.firstWhere(
        (v) => v.voiceId == widget.selectedVoiceId,
        orElse: () => widget.voices.isNotEmpty
            ? widget.voices.first
            : VoiceModel(
                voiceId: 'CwhRBWXzGAHq8TQ4Fs17',
                name: 'Roger (Laid-back & Natural)',
                category: 'Neural AI',
              ),
      );
    } catch (_) {
      selectedVoice = VoiceModel(
        voiceId: 'CwhRBWXzGAHq8TQ4Fs17',
        name: 'Roger (Laid-back & Natural)',
        category: 'Neural AI',
      );
    }

    if (!widget.voices.any((v) => v.voiceId == widget.selectedVoiceId) && widget.voices.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onVoiceSelected(widget.voices.first.voiceId);
      });
    }

    final processed = processVoiceForDisplay(selectedVoice);

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
              Icons.record_voice_over_rounded,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                processed.name,
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
