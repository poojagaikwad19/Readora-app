import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../settings/domain/settings_model.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/timed_word_model.dart';
import '../providers/document_tts_provider.dart';

enum TranscriptViewerMode {
  full,
  follow,
}

class TimedTranscriptViewer extends ConsumerStatefulWidget {
  final String transcript;
  final List<TimedWord> timedWords;
  final String? language;
  final double height;
  final VoidCallback? onExpandFullscreen;
  final VoidCallback? onRetranscribe;
  final bool isRetranscribing;
  final TranscriptViewerMode? initialMode;

  const TimedTranscriptViewer({
    super.key,
    required this.transcript,
    required this.timedWords,
    this.language,
    this.height = 380,
    this.onExpandFullscreen,
    this.onRetranscribe,
    this.isRetranscribing = false,
    this.initialMode,
  });

  @override
  ConsumerState<TimedTranscriptViewer> createState() => _TimedTranscriptViewerState();
}

class _TimedTranscriptViewerState extends ConsumerState<TimedTranscriptViewer> {
  late TranscriptViewerMode _currentMode;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _richTextKey = GlobalKey();

  bool _userScrolledAway = false;
  int _lastActiveIndex = -1;
  int? _lastPosMs;
  bool _isProgrammaticallyScrolling = false;
  bool _isDisposed = false;
  List<int> _currentCharOffsets = const [];

  bool get _hasValidTimings {
    return widget.timedWords.isNotEmpty &&
        widget.timedWords.any((w) => w.endMs > 0 || w.startMs > 0);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialMode != null) {
      _currentMode = (widget.initialMode == TranscriptViewerMode.follow && _hasValidTimings)
          ? TranscriptViewerMode.follow
          : TranscriptViewerMode.full;
    } else {
      _currentMode = _hasValidTimings
          ? TranscriptViewerMode.follow
          : TranscriptViewerMode.full;
    }
  }

  @override
  void didUpdateWidget(covariant TimedTranscriptViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasValidTimings && _currentMode == TranscriptViewerMode.follow) {
      _currentMode = TranscriptViewerMode.full;
    }
    if (oldWidget.transcript != widget.transcript) {
      _userScrolledAway = false;
      _lastActiveIndex = -1;
      _lastPosMs = null;
      _currentCharOffsets = const [];
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveWord(int activeIndex, {bool force = false}) {
    if (!mounted || _isDisposed || !_scrollController.hasClients) return;
    final autoScroll = ref.read(settingsProvider).autoScroll;
    if (!autoScroll && !force) return;
    if (_userScrolledAway && !force) return;
    if (_currentCharOffsets.isEmpty || activeIndex < 0 || activeIndex >= _currentCharOffsets.length) return;

    final renderParagraph = _richTextKey.currentContext?.findRenderObject() as RenderParagraph?;
    if (renderParagraph == null) return;

    final charOffset = _currentCharOffsets[activeIndex];
    final wordText = (activeIndex < widget.timedWords.length)
        ? widget.timedWords[activeIndex].text
        : '';
    final int wordLen = wordText.isNotEmpty ? wordText.length : 1;
    final totalPlainLen = renderParagraph.text.toPlainText().length;
    if (charOffset >= totalPlainLen) return;

    final boxes = renderParagraph.getBoxesForSelection(
      TextSelection(
        baseOffset: charOffset,
        extentOffset: (charOffset + wordLen).clamp(0, totalPlainLen),
      ),
    );

    if (boxes.isEmpty) return;

    final wordBox = boxes.first;
    // Account for SingleChildScrollView top padding
    const double contentPaddingTop = 14.0;
    final double wordContentTop = contentPaddingTop + wordBox.top;
    final double wordContentBottom = contentPaddingTop + wordBox.bottom;

    final double currentScroll = _scrollController.offset;
    final double viewportHeight = _scrollController.position.viewportDimension;
    final double maxScroll = _scrollController.position.maxScrollExtent;

    if (viewportHeight <= 0 || maxScroll <= 0) return;

    final double wordVisibleTop = wordContentTop - currentScroll;
    final double wordVisibleBottom = wordContentBottom - currentScroll;

    // Viewport boundaries: keep active word comfortably in reading zone (18% to 68%)
    final double upperBoundary = viewportHeight * 0.18;
    final double lowerBoundary = viewportHeight * 0.68;

    bool shouldScroll = force;
    if (!shouldScroll) {
      if (wordVisibleBottom > lowerBoundary || wordVisibleTop < upperBoundary) {
        shouldScroll = true;
      }
    }

    if (!shouldScroll) return;

    // Position current line around middle / lower-middle (~42% from top of viewport)
    final double targetScroll = (wordContentTop - (viewportHeight * 0.42)).clamp(0.0, maxScroll);

    // Skip micro-scrolls smaller than 6 pixels unless forced
    if ((targetScroll - currentScroll).abs() < 6.0 && !force) return;

    // Avoid stacking animations
    if (_isProgrammaticallyScrolling && !force) return;

    _isProgrammaticallyScrolling = true;

    final bool shouldReduceMotion = MediaQuery.of(context).disableAnimations;
    if (shouldReduceMotion) {
      _scrollController.jumpTo(targetScroll);
      _isProgrammaticallyScrolling = false;
    } else {
      _scrollController.animateTo(
        targetScroll,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ).whenComplete(() {
        if (!_isDisposed && mounted) {
          _isProgrammaticallyScrolling = false;
        }
      });
    }
  }

  void _copyToClipboard() {
    if (widget.transcript.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: widget.transcript));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transcript copied to clipboard!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showTimingUnavailableExplanation() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Synchronised word timing is unavailable for this transcript. Re-transcribe audio (⋮) to enable Follow Audio.',
        ),
        duration: const Duration(seconds: 4),
        action: widget.onRetranscribe != null
            ? SnackBarAction(
                label: 'Re-transcribe',
                textColor: Colors.amber.shade200,
                onPressed: () => widget.onRetranscribe?.call(),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ttsState = ref.watch(documentTtsNotifierProvider);

    final hasTimings = _hasValidTimings;
    final isOriginalAudioActive = ttsState.isPlayingOriginalAudio;
    final isCompleted = isOriginalAudioActive && ttsState.playerState == PlayerState.completed;
    final currentPosMs = isOriginalAudioActive ? ttsState.audioPosition.inMilliseconds : 0;

    // Detect user seek (sudden jump in audio position)
    final bool didSeek = isOriginalAudioActive &&
        (_lastPosMs != null) &&
        (currentPosMs < _lastPosMs! - 200 || (currentPosMs - _lastPosMs!) > 800);
    _lastPosMs = currentPosMs;

    // Reset follow state when audio stops or restarts from beginning
    if (!isOriginalAudioActive && currentPosMs == 0 && _lastActiveIndex != -1) {
      _lastActiveIndex = -1;
      _userScrolledAway = false;
      if (_scrollController.hasClients && _scrollController.offset > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          _scrollController.jumpTo(0);
        });
      }
    }

    // Determine revealed words and active word index
    int activeIndex = -1;
    final List<TimedWord> revealedWords = [];
    final settings = ref.watch(settingsProvider);
    final readerFontSize = settings.readerFontSize.size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : AppColors.border;

    if (hasTimings && _currentMode == TranscriptViewerMode.follow) {
      if (settings.keepUpcomingWordsVisible) {
        // Keep upcoming words visible: show all timed words, highlight active word
        revealedWords.addAll(widget.timedWords);
        if (isOriginalAudioActive) {
          for (int i = 0; i < widget.timedWords.length; i++) {
            final w = widget.timedWords[i];
            if (currentPosMs >= w.startMs && currentPosMs < w.endMs) {
              activeIndex = i;
              break;
            }
          }
        }
      } else if (isCompleted) {
        // Natural completion: retain complete transcript, clear active highlight
        revealedWords.addAll(widget.timedWords);
        activeIndex = -1;
      } else if (!isOriginalAudioActive && currentPosMs == 0) {
        // Player is stopped or hasn't started yet: position is 0
        for (int i = 0; i < widget.timedWords.length; i++) {
          final w = widget.timedWords[i];
          if (w.startMs <= 0) {
            revealedWords.add(w);
            if (currentPosMs >= w.startMs && currentPosMs < w.endMs) {
              activeIndex = i;
            }
          }
        }
      } else {
        // Active playback or seeking
        for (int i = 0; i < widget.timedWords.length; i++) {
          final w = widget.timedWords[i];
          if (w.startMs <= currentPosMs) {
            revealedWords.add(w);
            if (currentPosMs >= w.startMs && currentPosMs < w.endMs) {
              activeIndex = i;
            }
          }
        }
      }

      // Handle seeking or active word progression
      if (activeIndex != -1) {
        if (didSeek && !_userScrolledAway) {
          _lastActiveIndex = activeIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scrollToActiveWord(activeIndex, force: true);
          });
        } else if (activeIndex != _lastActiveIndex) {
          _lastActiveIndex = activeIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scrollToActiveWord(activeIndex);
          });
        }
      } else if (didSeek && !_userScrolledAway && currentPosMs == 0) {
        // Seeked back to start/silence before first word
        if (_scrollController.hasClients && _scrollController.offset > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _userScrolledAway || !_scrollController.hasClients) return;
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        }
      }
    }

    final wordCount = widget.transcript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Area: Divided into 2 non-overflowing rows
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(
                bottom: BorderSide(color: borderColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ROW 1: "Transcript" header & actual word count + ⋮ menu
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Transcript',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$wordCount words',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF94A3B8) : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _buildTranscriptOptionsMenu(isDark),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // ROW 2: Segmented-control Mode Selector + Info Label if timing unavailable
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    // Segmented control: [Full Transcript] [Follow Audio]
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: _buildModeTab(
                              label: 'Full Transcript',
                              icon: Icons.menu_book_rounded,
                              isSelected: _currentMode == TranscriptViewerMode.full,
                              isEnabled: true,
                              isDark: isDark,
                              onTap: () {
                                if (_currentMode != TranscriptViewerMode.full) {
                                  setState(() => _currentMode = TranscriptViewerMode.full);
                                }
                              },
                            ),
                          ),
                          Flexible(
                            child: _buildModeTab(
                              label: 'Follow Audio',
                              icon: Icons.sync_rounded,
                              isSelected: _currentMode == TranscriptViewerMode.follow,
                              isEnabled: hasTimings,
                              isDark: isDark,
                              onTap: () {
                                if (!hasTimings) {
                                  _showTimingUnavailableExplanation();
                                  return;
                                }
                                if (_currentMode != TranscriptViewerMode.follow) {
                                  setState(() {
                                    _currentMode = TranscriptViewerMode.follow;
                                    _userScrolledAway = false;
                                  });
                                  if (activeIndex != -1) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (!mounted) return;
                                      _scrollToActiveWord(activeIndex, force: true);
                                    });
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Small info label when word timing is unavailable
                    if (!hasTimings)
                      InkWell(
                        onTap: _showTimingUnavailableExplanation,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline_rounded, size: 13, color: Colors.amber.shade800),
                              const SizedBox(width: 4),
                              Text(
                                'Word timing unavailable',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Content Area: Prioritized readable scrollable transcript
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (_isProgrammaticallyScrolling) {
                  if (notification is ScrollStartNotification && notification.dragDetails != null) {
                    _isProgrammaticallyScrolling = false;
                    if (!_userScrolledAway) {
                      setState(() => _userScrolledAway = true);
                    }
                  }
                  return false;
                }

                if (notification is ScrollStartNotification) {
                  if (notification.dragDetails != null) {
                    if (!_userScrolledAway) {
                      setState(() => _userScrolledAway = true);
                    }
                  }
                } else if (notification is UserScrollNotification) {
                  if (notification.direction != ScrollDirection.idle) {
                    if (!_userScrolledAway) {
                      setState(() => _userScrolledAway = true);
                    }
                  }
                }
                return false;
              },
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                interactive: true,
                radius: const Radius.circular(4),
                thickness: 3.5,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 48),
                  child: _buildTranscriptBody(
                    hasTimings: hasTimings,
                    revealedWords: revealedWords,
                    activeIndex: activeIndex,
                    isOriginalAudioActive: isOriginalAudioActive,
                    currentPosMs: currentPosMs,
                    fontSize: readerFontSize,
                    isDark: isDark,
                    settings: settings,
                  ),
                ),
              ),
            ),
          ),

          // Reserved Compact Footer: Dedicated space outside text viewport
          _buildTranscriptFooter(
            hasTimings: hasTimings,
            activeIndex: activeIndex,
            isOriginalAudioActive: isOriginalAudioActive,
            isDark: isDark,
            borderColor: borderColor,
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptFooter({
    required bool hasTimings,
    required int activeIndex,
    required bool isOriginalAudioActive,
    required bool isDark,
    required Color borderColor,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border(
          top: BorderSide(color: borderColor, width: 0.9),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left status indicator
          if (_currentMode == TranscriptViewerMode.follow && hasTimings)
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isOriginalAudioActive ? const Color(0xFF10B981) : AppColors.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _userScrolledAway
                          ? 'Manual scroll'
                          : (isOriginalAudioActive ? 'Follow Audio synced' : 'Follow Audio ready'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            const Expanded(
              child: Text(
                'Full transcript view',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          // Right action: "Follow current word" button (appears ONLY when manual scroll is suspended)
          if (_currentMode == TranscriptViewerMode.follow &&
              hasTimings &&
              _userScrolledAway &&
              activeIndex != -1)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() => _userScrolledAway = false);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _scrollToActiveWord(activeIndex, force: true);
                  });
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 1.5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.center_focus_strong_rounded, size: 13, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Follow current word',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required String label,
    required IconData icon,
    required bool isSelected,
    required bool isEnabled,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final opacity = isEnabled ? 1.0 : 0.45;
    return Opacity(
      opacity: opacity,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? (isDark ? const Color(0xFF1E293B) : Colors.white) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTranscriptOptionsMenu(bool isDark) {
    final borderColor = isDark ? const Color(0xFF334155) : AppColors.border;
    final textColor = isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary;
    final iconColor = isDark ? const Color(0xFFC4B5FD) : AppColors.textSecondary;

    return PopupMenuButton<String>(
      tooltip: 'Transcript options',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 160),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: iconColor,
      ),
      onSelected: (val) {
        if (val == 'copy') {
          _copyToClipboard();
        } else if (val == 'expand') {
          widget.onExpandFullscreen?.call();
        } else if (val == 'retranscribe') {
          widget.onRetranscribe?.call();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          value: 'copy',
          height: 38,
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 16, color: iconColor),
              const SizedBox(width: 10),
              Text(
                'Copy transcript',
                style: TextStyle(fontSize: 13, color: textColor),
              ),
            ],
          ),
        ),
        if (widget.onExpandFullscreen != null)
          PopupMenuItem<String>(
            value: 'expand',
            height: 38,
            child: Row(
              children: [
                Icon(Icons.open_in_full_rounded, size: 16, color: iconColor),
                const SizedBox(width: 10),
                Text(
                  'Expand transcript',
                  style: TextStyle(fontSize: 13, color: textColor),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'retranscribe',
          height: 38,
          enabled: !widget.isRetranscribing,
          child: Row(
            children: [
              if (widget.isRetranscribing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              else
                Icon(Icons.refresh_rounded, size: 16, color: iconColor),
              const SizedBox(width: 10),
              Text(
                widget.isRetranscribing ? 'Transcribing...' : 'Re-transcribe audio',
                style: TextStyle(fontSize: 13, color: textColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTranscriptBody({
    required bool hasTimings,
    required List<TimedWord> revealedWords,
    required int activeIndex,
    required bool isOriginalAudioActive,
    required int currentPosMs,
    required double fontSize,
    required bool isDark,
    required SettingsModel settings,
  }) {
    final textColor = isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary;

    if (!hasTimings || _currentMode == TranscriptViewerMode.full) {
      return SelectableText(
        widget.transcript.isNotEmpty ? widget.transcript : 'No transcript available.',
        style: TextStyle(
          fontSize: fontSize,
          height: 1.7,
          color: textColor,
        ),
      );
    }

    // Follow Audio mode with timed words: stopped state at pos 0 when upcoming words are hidden
    if (revealedWords.isEmpty && currentPosMs == 0 && !settings.keepUpcomingWordsVisible) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2E2452) : AppColors.lavenderSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 28,
                  color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Play Original Audio above',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Transcript will appear word-by-word synchronised to speech.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xFF94A3B8) : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Build RichText with styled word spans
    final spans = <InlineSpan>[];
    final List<int> charOffsets = [];
    int runningCharOffset = 0;

    for (int i = 0; i < revealedWords.length; i++) {
      final word = revealedWords[i];
      final bool isActive = (i == activeIndex);
      final bool isUpcoming = settings.keepUpcomingWordsVisible &&
          isOriginalAudioActive &&
          word.startMs > currentPosMs;

      final bool shouldHighlight = settings.highlightCurrentWord && isActive;

      Color wordColor;
      Color wordBg;
      FontWeight wordWeight;

      if (shouldHighlight) {
        wordColor = isDark ? const Color(0xFFC4B5FD) : AppColors.primary;
        wordBg = isDark ? const Color(0xFF2E2452) : AppColors.lavenderSurface;
        wordWeight = FontWeight.w800;
      } else if (isUpcoming) {
        wordColor = isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary;
        wordBg = Colors.transparent;
        wordWeight = FontWeight.w400;
      } else {
        wordColor = textColor;
        wordBg = Colors.transparent;
        wordWeight = FontWeight.w400;
      }

      charOffsets.add(runningCharOffset);

      spans.add(
        TextSpan(
          text: word.text,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.7,
            color: wordColor,
            backgroundColor: wordBg,
            fontWeight: wordWeight,
          ),
        ),
      );

      runningCharOffset += word.text.length;

      // Preserve spaces between words
      if (i < revealedWords.length - 1) {
        spans.add(
          TextSpan(
            text: ' ',
            style: TextStyle(fontSize: fontSize, height: 1.7),
          ),
        );
        runningCharOffset += 1;
      }
    }
    _currentCharOffsets = charOffsets;

    return RichText(
      key: _richTextKey,
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          height: 1.7,
          color: textColor,
          fontFamily: 'Roboto',
        ),
        children: spans,
      ),
    );
  }
}
