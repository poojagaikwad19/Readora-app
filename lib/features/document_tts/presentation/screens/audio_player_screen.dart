import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/document_tts_provider.dart';

class AudioPlayerScreen extends ConsumerWidget {
  const AudioPlayerScreen({super.key});

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ttsState = ref.watch(documentTtsNotifierProvider);
    final response = ttsState.currentTtsResponse;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Readora Speech Player'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Audio Animation Disk Icon
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: 64,
                ),
              ),
              const SizedBox(height: 32),

              // Title & Info
              Text(
                response?.filename ?? 'Generated Speech',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Language: ${ttsState.selectedLanguage.toUpperCase()} ${response?.cached == true ? "(Cached)" : ""}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // Progress Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: AppColors.border,
                  thumbColor: AppColors.primary,
                ),
                child: Slider(
                  value: ttsState.audioPosition.inSeconds.toDouble().clamp(
                        0.0,
                        (ttsState.audioDuration.inSeconds > 0 ? ttsState.audioDuration.inSeconds : 1.0).toDouble(),
                      ),
                  max: (ttsState.audioDuration.inSeconds > 0 ? ttsState.audioDuration.inSeconds : 1.0).toDouble(),
                  onChanged: (val) {
                    ref
                        .read(documentTtsNotifierProvider.notifier)
                        .seekAudio(Duration(seconds: val.toInt()));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(ttsState.audioPosition),
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    Text(
                      _formatDuration(ttsState.audioDuration),
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Player Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.replay_10_rounded, color: AppColors.textPrimary),
                    onPressed: () {
                      final newPos = ttsState.audioPosition - const Duration(seconds: 10);
                      ref.read(documentTtsNotifierProvider.notifier).seekAudio(
                            newPos < Duration.zero ? Duration.zero : newPos,
                          );
                    },
                  ),
                  const SizedBox(width: 20),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                    child: IconButton(
                      iconSize: 36,
                      icon: Icon(
                        ttsState.playerState == PlayerState.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        if (ttsState.playerState == PlayerState.playing) {
                          ref.read(documentTtsNotifierProvider.notifier).pauseAudio();
                        } else {
                          ref.read(documentTtsNotifierProvider.notifier).resumeAudio();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.forward_10_rounded, color: AppColors.textPrimary),
                    onPressed: () {
                      final newPos = ttsState.audioPosition + const Duration(seconds: 10);
                      ref.read(documentTtsNotifierProvider.notifier).seekAudio(newPos);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
