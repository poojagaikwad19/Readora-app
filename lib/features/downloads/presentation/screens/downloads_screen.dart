import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../document_tts/presentation/providers/document_tts_provider.dart';
import '../../domain/download_model.dart';
import '../providers/downloads_provider.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  final Map<String, bool> _fileExistenceCache = {};
  DownloadsFilter _selectedFilter = DownloadsFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(downloadsProvider.notifier).loadDownloads();
      _checkFilesExistence();
    });
  }

  Future<void> _checkFilesExistence() async {
    final downloads = ref.read(downloadsProvider).downloads;
    final notifier = ref.read(downloadsProvider.notifier);
    final cache = <String, bool>{};

    for (final item in downloads) {
      final path = await notifier.getLocalAbsolutePath(item.relativeFilePath);
      cache[item.id] = await File(path).exists();
    }

    if (mounted) {
      setState(() {
        _fileExistenceCache.addAll(cache);
      });
    }
  }

  void _showRenameDialog(DownloadModel item) {
    final controller = TextEditingController(text: item.displayFilename);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename Audio File', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Display Name',
            hintText: 'Enter new filename',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(ctx);
                await ref.read(downloadsProvider.notifier).renameDownload(item.id, newName);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Audio renamed successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _confirmAndDelete(DownloadModel item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 22),
            SizedBox(width: 8),
            Text('Delete from Readora', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Delete "${item.displayFilename}" from Readora?\n\nThis removes the in-app offline audio file. Any copies previously saved to your device will remain untouched.',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(downloadsProvider.notifier).deleteDownload(item.id);
              if (mounted) {
                _checkFilesExistence();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Audio deleted from Readora library'),
                    backgroundColor: AppColors.textPrimary,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePlayPause(DownloadModel item) async {
    final notifier = ref.read(downloadsProvider.notifier);
    final state = ref.read(downloadsProvider);

    // Stop active TTS & STT original audio playback to prevent overlap
    await ref.read(documentTtsNotifierProvider.notifier).stopAudioAndClearQueue();
    await ref.read(documentTtsNotifierProvider.notifier).stopOriginalAudio();

    if (state.activePlayingId == item.id && state.playerState == PlayerState.playing) {
      await notifier.pauseDownload();
    } else if (state.activePlayingId == item.id && state.playerState == PlayerState.paused) {
      await notifier.resumeDownload();
    } else {
      await notifier.playDownload(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadsState = ref.watch(downloadsProvider);
    final notifier = ref.read(downloadsProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredDownloads = downloadsState.downloads
        .where((d) => DownloadModel.matchesFilter(d, _selectedFilter))
        .toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppColors.background,
      appBar: AppBar(
        title: const Text('Downloads'),
      ),
      body: downloadsState.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Active Playback Bar if audio is currently playing/paused
                if (downloadsState.activePlayingId != null)
                  _buildActivePlaybackBar(context, downloadsState, isDark),

                // Downloads Heading, Subtitle & Three-Segment Filter Control
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Downloads',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Offline audio files and documents saved in Readora',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Compact Three-Segment Filter Control (Lavender + Mint Theme)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            _buildSegmentItem('All', DownloadsFilter.all, isDark),
                            _buildSegmentItem('Document', DownloadsFilter.document, isDark),
                            _buildSegmentItem('Audio', DownloadsFilter.audio, isDark),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Filtered List or Tab-specific Empty State
                Expanded(
                  child: filteredDownloads.isEmpty
                      ? _buildEmptyState(context, isDark)
                      : _buildDownloadsList(context, downloadsState, filteredDownloads, isDark),
                ),

                // Bottom Disclaimer Note
                _buildDisclaimerFooter(isDark),
              ],
            ),
    );
  }

  Widget _buildSegmentItem(String label, DownloadsFilter filter, bool isDark) {
    final isSelected = _selectedFilter == filter;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _selectedFilter = filter;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF7C64F7) : const Color(0xFFF3F0FF))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? (isDark ? Colors.white : AppColors.primary)
                  : (isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary),
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    IconData icon;
    String title;
    String subtitle;

    switch (_selectedFilter) {
      case DownloadsFilter.all:
        icon = Icons.file_download_outlined;
        title = 'No downloaded audio yet';
        subtitle = 'Generate speech from a document, then choose Download Audio.';
        break;
      case DownloadsFilter.document:
        icon = Icons.description_outlined;
        title = 'No downloaded documents yet';
        subtitle = 'Downloaded document files (PDF, DOCX, TXT) will appear here.';
        break;
      case DownloadsFilter.audio:
        icon = Icons.graphic_eq_rounded;
        title = 'No downloaded audio yet';
        subtitle = 'Generate speech from a document, then choose Download Audio.';
        break;
    }

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2E2452) : AppColors.lavenderSurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 48,
                  color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF94A3B8) : AppColors.textMuted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDisclaimerFooter(bool isDark) {
    final borderColor = isDark ? const Color(0xFF334155) : AppColors.border;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
        border: Border(
          top: BorderSide(color: borderColor, width: 0.8),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: isDark ? const Color(0xFF94A3B8) : AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Files stored inside Readora are private to the app and may be removed if the app is uninstalled. Use "Save to device" (⋮) to permanently export audio to your device storage.',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xFF94A3B8) : AppColors.textMuted,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadsList(
    BuildContext context,
    DownloadsState state,
    List<DownloadModel> items,
    bool isDark,
  ) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : AppColors.border;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        final isPlayingThis = state.activePlayingId == item.id && state.playerState == PlayerState.playing;
        final isPausedThis = state.activePlayingId == item.id && state.playerState == PlayerState.paused;
        final fileExists = _fileExistenceCache[item.id] ?? true;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPlayingThis
                  ? (isDark ? const Color(0xFF8B5CF6) : AppColors.primary)
                  : borderColor,
              width: isPlayingThis ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // File Icon / Audio Avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2E2452) : AppColors.lavenderSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      item.isDocument
                          ? Icons.description_rounded
                          : isPlayingThis
                              ? Icons.graphic_eq_rounded
                              : Icons.audiotrack_rounded,
                      color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Title, Language & Metadata
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayFilename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF143834) : AppColors.mintSurface,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.language.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? const Color(0xFF2DD4BF) : AppColors.tealAccent,
                                ),
                              ),
                            ),
                            Text(
                              item.formattedSize,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? const Color(0xFF94A3B8) : AppColors.textMuted,
                              ),
                            ),
                            if (item.formattedDuration != null)
                              Text(
                                '•  ${item.formattedDuration}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? const Color(0xFF94A3B8) : AppColors.textMuted,
                                ),
                              ),
                            Text(
                              '•  ${item.formattedDate}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? const Color(0xFF94A3B8) : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        if (!fileExists) ...[
                          const SizedBox(height: 4),
                          const Text(
                            '⚠️ File missing from device storage',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Play/Pause Action Button
                  if (fileExists && item.isAudio)
                    IconButton(
                      icon: Icon(
                        isPlayingThis
                            ? Icons.pause_circle_filled_rounded
                            : isPausedThis
                                ? Icons.play_circle_fill_rounded
                                : Icons.play_circle_outline_rounded,
                        color: AppColors.primary,
                        size: 32,
                      ),
                      tooltip: isPlayingThis ? 'Pause' : 'Play offline',
                      onPressed: () => _handlePlayPause(item),
                    ),

                  // Three-Dot Popup Menu
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
                      size: 20,
                    ),
                    tooltip: 'Options',
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (val) async {
                      if (val == 'save') {
                        final messenger = ScaffoldMessenger.of(context);
                        final success = await ref.read(downloadsProvider.notifier).exportToDevice(item);
                        if (mounted && success) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Audio saved to device: ${item.displayFilename}'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } else if (val == 'rename') {
                        _showRenameDialog(item);
                      } else if (val == 'delete') {
                        _confirmAndDelete(item);
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem<String>(
                        value: 'save',
                        child: Row(
                          children: [
                            const Icon(Icons.save_alt_rounded, size: 18, color: AppColors.primary),
                            const SizedBox(width: 10),
                            Text(
                              'Save to device',
                              style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18, color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary),
                            const SizedBox(width: 10),
                            Text(
                              'Rename',
                              style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                            SizedBox(width: 10),
                            Text('Delete from app', style: TextStyle(fontSize: 13, color: AppColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActivePlaybackBar(BuildContext context, DownloadsState state, bool isDark) {
    final activeItem = state.downloads.firstWhere(
      (d) => d.id == state.activePlayingId,
      orElse: () => DownloadModel(
        id: '',
        userId: '',
        displayFilename: 'Audio',
        relativeFilePath: '',
        fileSize: 0,
        language: 'english',
        downloadDate: DateTime.now(),
      ),
    );

    final isPlaying = state.playerState == PlayerState.playing;
    final maxSec = (state.playbackDuration.inSeconds > 0 ? state.playbackDuration.inSeconds : 1).toDouble();
    final curSec = state.playbackPosition.inSeconds.toDouble().clamp(0.0, maxSec);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2E2452) : AppColors.lavenderSurface,
        border: Border(
          bottom: BorderSide(color: isDark ? const Color(0xFF7C64F7) : AppColors.selectedBorder),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isPlaying ? Icons.volume_up_rounded : Icons.pause_rounded,
                color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Playing: ${activeItem.displayFilename}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                iconSize: 22,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  if (isPlaying) {
                    ref.read(downloadsProvider.notifier).pauseDownload();
                  } else {
                    ref.read(downloadsProvider.notifier).resumeDownload();
                  }
                },
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.stop_rounded),
                color: AppColors.error,
                iconSize: 22,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  ref.read(downloadsProvider.notifier).stopPlayback();
                },
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: Colors.black12,
              thumbColor: AppColors.primary,
            ),
            child: Slider(
              value: curSec,
              min: 0.0,
              max: maxSec,
              onChanged: (val) {
                ref.read(downloadsProvider.notifier).seekPlayback(Duration(seconds: val.toInt()));
              },
            ),
          ),
        ],
      ),
    );
  }
}
