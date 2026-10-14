import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../downloads/presentation/screens/downloads_screen.dart';
import '../providers/document_tts_provider.dart';

class ReadoraAudioPlayer extends ConsumerStatefulWidget {
  final bool isCompact;

  const ReadoraAudioPlayer({
    super.key,
    this.isCompact = true,
  });

  @override
  ConsumerState<ReadoraAudioPlayer> createState() => _ReadoraAudioPlayerState();
}

class _ReadoraAudioPlayerState extends ConsumerState<ReadoraAudioPlayer> {
  final GlobalKey _menuButtonKey = GlobalKey();

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  RelativeRect? _getButtonPosition() {
    final renderObject = _menuButtonKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return null;

    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return null;

    final buttonBox = renderObject;
    final buttonSize = buttonBox.size;
    final buttonOffset = buttonBox.localToGlobal(Offset.zero, ancestor: overlay);

    return RelativeRect.fromRect(
      Rect.fromLTWH(
        buttonOffset.dx,
        buttonOffset.dy,
        buttonSize.width,
        buttonSize.height,
      ),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _handleDownload(String baseUrl) async {
    final notifier = ref.read(documentTtsNotifierProvider.notifier);
    final state = ref.read(documentTtsNotifierProvider);

    if (state.isDownloadingAudio) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download is already in progress...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Saving audio to Readora Downloads...'),
          ],
        ),
        duration: Duration(seconds: 4),
      ),
    );

    final downloadItem = await notifier.downloadAudioToLibrary(baseUrl);
    scaffoldMessenger.hideCurrentSnackBar();

    if (downloadItem != null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('✅ Saved to Readora Downloads!\n${downloadItem.displayFilename}'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DownloadsScreen()),
              );
            },
          ),
        ),
      );
    } else {
      final err = ref.read(documentTtsNotifierProvider).errorMessage ?? 'Download failed. Please try again.';
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('❌ $err'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _showMainMenu(String baseUrl, double currentSpeed) async {
    final position = _getButtonPosition();
    if (position == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937);
    final iconColor = isDark ? const Color(0xFFC4B5FD) : const Color(0xFF1F2937);

    final selected = await showMenu<String>(
      context: context,
      position: position,
      elevation: 6,
      shadowColor: Colors.black26,
      color: menuBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      constraints: const BoxConstraints(
        minWidth: 170,
        maxWidth: 220,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'download',
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                Icons.file_download_outlined,
                color: iconColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                'Download Audio',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'speed',
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                Icons.speed_rounded,
                color: iconColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                'Playback speed',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!mounted) return;

    if (selected == 'download') {
      _handleDownload(baseUrl);
    } else if (selected == 'speed') {
      _showSpeedMenu(currentSpeed);
    }
  }

  Future<void> _showSpeedMenu(double currentSpeed) async {
    final position = _getButtonPosition();
    if (position == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary;
    final lavenderSurface = isDark ? const Color(0xFF2E2452) : AppColors.lavenderSurface;
    final primaryColor = isDark ? const Color(0xFFC4B5FD) : AppColors.primary;

    final speeds = [
      {'label': '0.5x', 'value': 0.5},
      {'label': '0.75x', 'value': 0.75},
      {'label': 'Normal (1.0x)', 'value': 1.0},
      {'label': '1.25x', 'value': 1.25},
      {'label': '1.5x', 'value': 1.5},
      {'label': '2.0x', 'value': 2.0},
    ];

    final selectedRate = await showMenu<double>(
      context: context,
      position: position,
      elevation: 6,
      shadowColor: Colors.black26,
      color: menuBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      constraints: const BoxConstraints(
        minWidth: 160,
        maxWidth: 210,
        maxHeight: 280,
      ),
      items: speeds.map((item) {
        final rate = item['value'] as double;
        final label = item['label'] as String;
        final isSelected = (rate == currentSpeed);

        return PopupMenuItem<double>(
          value: rate,
          height: 42,
          padding: EdgeInsets.zero,
          child: Container(
            color: isSelected ? lavenderSurface : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? primaryColor : textColor,
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_rounded,
                    color: primaryColor,
                    size: 18,
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );

    if (selectedRate != null && mounted) {
      try {
        await ref.read(documentTtsNotifierProvider.notifier).setPlaybackRate(selectedRate);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update playback speed: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ttsState = ref.watch(documentTtsNotifierProvider);
    final response = ttsState.currentTtsResponse;
    if (response == null) return const SizedBox.shrink();

    final apiClient = ref.watch(apiClientProvider);
    final baseUrl = apiClient.baseUrl;

    final isPlaying = ttsState.playerState == PlayerState.playing;
    final maxSec = (ttsState.audioDuration.inSeconds > 0 ? ttsState.audioDuration.inSeconds : 1.0).toDouble();
    final curSec = ttsState.audioPosition.inSeconds.toDouble().clamp(0.0, maxSec);

    final isDark = context.isDark;
    final capsuleBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : Colors.grey.shade200;
    final iconColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937);
    final secondaryTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF374151);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: capsuleBg,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ttsState.isProgressive)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2E2452) : AppColors.lavenderSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.audiotrack_rounded,
                          size: 13,
                          color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Part ${ttsState.progressiveCurrentChunk} of ${ttsState.progressiveTotalChunks}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (ttsState.progressiveCompletedChunks < ttsState.progressiveTotalChunks)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Buffering (${ttsState.progressiveCompletedChunks}/${ttsState.progressiveTotalChunks})...',
                          style: TextStyle(
                            fontSize: 11,
                            color: secondaryTextColor,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'All parts ready',
                      style: TextStyle(
                        fontSize: 11,
                        color: secondaryTextColor,
                      ),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              // 1. Play / Pause Action Button
              InkWell(
                onTap: () {
                  ref.read(documentTtsNotifierProvider.notifier).togglePlayPause(baseUrl);
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: iconColor,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // 1.5 Stop Action Button
              InkWell(
                onTap: () {
                  ref.read(documentTtsNotifierProvider.notifier).stopAudio();
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.stop_rounded,
                    color: iconColor,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 8),

          // 2. Playback Duration (0:17 / 0:31)
          Text(
            '${_formatDuration(ttsState.audioPosition)} / ${_formatDuration(ttsState.audioDuration)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: secondaryTextColor,
            ),
          ),
          const SizedBox(width: 8),

          // 3. Progress Slider
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
                thumbColor: AppColors.primary,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: curSec,
                max: maxSec,
                onChanged: (val) {
                  ref.read(documentTtsNotifierProvider.notifier).seekAudio(Duration(seconds: val.toInt()));
                },
              ),
            ),
          ),
          const SizedBox(width: 6),

          // 4. Mute / Unmute Button
          InkWell(
            onTap: () {
              ref.read(documentTtsNotifierProvider.notifier).toggleMute();
            },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Icon(
                ttsState.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: ttsState.isMuted ? AppColors.error : secondaryTextColor,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 4),

          // 5. Three-dot Options Menu (Download & Speed)
          InkWell(
            key: _menuButtonKey,
            onTap: () {
              _showMainMenu(baseUrl, ttsState.playbackRate);
            },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Icon(
                Icons.more_vert_rounded,
                color: secondaryTextColor,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    ],
  ),
);
  }
}
