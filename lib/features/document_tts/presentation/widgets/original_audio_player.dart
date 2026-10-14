import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/document_tts_provider.dart';

class OriginalAudioPlayer extends ConsumerWidget {
  final String? audioPath;
  final String? audioTitle;
  final int? fallbackDurationMs;

  const OriginalAudioPlayer({
    super.key,
    this.audioPath,
    this.audioTitle,
    this.fallbackDurationMs,
  });

  String _formatDuration(Duration duration) {
    if (duration.inMilliseconds <= 0) return '00:00';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ttsState = ref.watch(documentTtsNotifierProvider);
    final notifier = ref.read(documentTtsNotifierProvider.notifier);

    final effectivePath = audioPath ??
        ttsState.originalAudioPath ??
        ttsState.activeDocument?.audioSourcePath;

    if (effectivePath == null || effectivePath.isEmpty) {
      return const SizedBox.shrink();
    }

    final fileExists = File(effectivePath).existsSync();

    final isPlayingThis = ttsState.isPlayingOriginalAudio &&
        ttsState.playerState == PlayerState.playing;

    // Determine current position
    final posMs = ttsState.isPlayingOriginalAudio
        ? ttsState.audioPosition.inMilliseconds
        : 0;

    // Real audio duration from player or word timestamps fallback
    int durMs = ttsState.audioDuration.inMilliseconds;
    if (durMs <= 0 && fallbackDurationMs != null && fallbackDurationMs! > 0) {
      durMs = fallbackDurationMs!;
    }

    final bool hasValidDuration = durMs > 0;
    final safeMax = hasValidDuration ? durMs.toDouble() : 1.0;
    final safePos = hasValidDuration ? posMs.clamp(0, durMs).toDouble() : 0.0;

    final isDark = context.isDark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPlayingThis ? AppColors.primary.withValues(alpha: 0.35) : context.borderColor,
          width: isPlayingThis ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isPlayingThis
                ? AppColors.primary.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Section label: Original Audio
          Row(
            children: [
              const Icon(Icons.mic_rounded, size: 14, color: AppColors.primary),
              const SizedBox(width: 5),
              const Text(
                'Original Audio',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (isPlayingThis)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Playing',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),

          if (!fileExists) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.error),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Original source audio file is missing from device storage.',
                      style: TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 2),
            // Compact responsive control row: Play/Pause | Elapsed | Seek Bar | Total | Three-dot Menu
            Row(
              children: [
                // Play / Pause Button with min 48x48 touch target
                IconButton(
                  iconSize: 34,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  tooltip: isPlayingThis ? 'Pause' : 'Play Original Audio',
                  icon: Icon(
                    isPlayingThis ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                    color: AppColors.primary,
                  ),
                  onPressed: () => notifier.toggleOriginalAudio(effectivePath),
                ),
                const SizedBox(width: 2),

                // Elapsed time
                Text(
                  _formatDuration(Duration(milliseconds: safePos.toInt())),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondaryColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),

                // Seek bar
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: isDark ? const Color(0xFF334155) : AppColors.primary.withValues(alpha: 0.15),
                      thumbColor: AppColors.primary,
                      disabledActiveTrackColor: Colors.grey.shade300,
                      disabledInactiveTrackColor: Colors.grey.shade200,
                      disabledThumbColor: Colors.grey.shade400,
                    ),
                    child: Slider(
                      value: hasValidDuration ? safePos : 0.0,
                      min: 0.0,
                      max: safeMax,
                      onChanged: hasValidDuration
                          ? (val) {
                              notifier.seekAudio(Duration(milliseconds: val.toInt()));
                            }
                          : null,
                    ),
                  ),
                ),

                // Total duration or neutral placeholder
                Text(
                  hasValidDuration ? _formatDuration(Duration(milliseconds: durMs)) : '--:--',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.textMutedColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),

                // Three-dot menu: Playback Speed and Stop
                PopupMenuButton<String>(
                  tooltip: 'Player options',
                  icon: Icon(Icons.more_vert_rounded, color: context.textSecondaryColor, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onSelected: (val) {
                    if (val == 'stop') {
                      notifier.stopOriginalAudio();
                    } else if (val.startsWith('speed_')) {
                      final rate = double.tryParse(val.substring(6)) ?? 1.0;
                      notifier.setPlaybackRate(rate);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'stop',
                      child: Row(
                        children: [
                          const Icon(Icons.stop_circle_outlined, size: 18, color: AppColors.error),
                          const SizedBox(width: 8),
                          Text('Stop and Reset', style: TextStyle(fontSize: 13, color: context.textPrimaryColor)),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      enabled: false,
                      height: 24,
                      child: Text(
                        'PLAYBACK SPEED',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: context.textMutedColor),
                      ),
                    ),
                    ...[0.75, 1.0, 1.25, 1.5, 2.0].map((rate) {
                      final isSelected = (ttsState.playbackRate == rate);
                      return PopupMenuItem(
                        value: 'speed_$rate',
                        height: 36,
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.check_rounded : Icons.speed_rounded,
                              size: 16,
                              color: isSelected ? AppColors.primary : context.textMutedColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              rate == 1.0 ? '1.0x (Normal)' : '${rate}x',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? AppColors.primary : context.textPrimaryColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
