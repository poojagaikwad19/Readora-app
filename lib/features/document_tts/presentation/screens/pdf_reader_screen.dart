import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/document_model.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../providers/document_tts_provider.dart';
import '../widgets/readora_audio_player.dart';
import '../widgets/original_audio_player.dart';

class PdfReaderScreen extends ConsumerStatefulWidget {
  final DocumentModel document;
  final bool autoPlayAudio;

  const PdfReaderScreen({
    super.key,
    required this.document,
    this.autoPlayAudio = false,
  });

  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen> {
  late String _displayedText;
  DocumentTtsNotifier? _ttsNotifier;
  bool _stopAudioOnLeave = true;

  @override
  void initState() {
    super.initState();
    _displayedText = widget.document.text;

    // Synchronize active document on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentActive = ref.read(documentTtsNotifierProvider).activeDocument;
      if (currentActive?.docId != widget.document.docId) {
        ref.read(documentTtsNotifierProvider.notifier).setActiveDocument(widget.document);
      }
      if (widget.autoPlayAudio) {
        final audioPath = widget.document.audioSourcePath ??
            ref.read(documentTtsNotifierProvider).originalAudioPath;
        if (audioPath != null && audioPath.isNotEmpty) {
          ref.read(documentTtsNotifierProvider.notifier).playOriginalAudio(audioPath);
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ttsNotifier = ref.read(documentTtsNotifierProvider.notifier);
    _stopAudioOnLeave = ref.read(settingsProvider).stopAudioOnLeaveScreen;
  }

  @override
  void dispose() {
    if (_stopAudioOnLeave) {
      try {
        _ttsNotifier?.stopAudio();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final ttsState = ref.watch(documentTtsNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary;

    final lowerType = widget.document.fileType.toLowerCase();
    final lowerFilename = widget.document.filename.toLowerCase();
    final bool isAudio = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'opus', 'audio'].contains(lowerType) ||
        lowerFilename.endsWith('.mp3') ||
        lowerFilename.endsWith('.wav') ||
        lowerFilename.endsWith('.m4a') ||
        lowerFilename.endsWith('.aac') ||
        lowerFilename.endsWith('.ogg') ||
        lowerFilename.endsWith('.flac') ||
        widget.document.audioSourcePath != null;

    final wordCount = _displayedText.isNotEmpty
        ? _displayedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length
        : 0;

    final effectiveAudioPath = widget.document.audioSourcePath ?? ttsState.originalAudioPath;
    final bool hasAudioSource = effectiveAudioPath != null && effectiveAudioPath.isNotEmpty;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppColors.background,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.document.filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: textColor),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.copy_rounded, color: textColor),
            tooltip: isAudio ? 'Copy Transcript' : 'Copy Text',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _displayedText));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(isAudio ? 'Transcript copied to clipboard!' : 'Text copied to clipboard!')),
              );
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Detected Info & Stats Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: isDark ? const Color(0xFF2E2452) : AppColors.accentPill,
            child: Row(
              children: [
                Icon(
                  isAudio ? Icons.graphic_eq_rounded : Icons.description_outlined,
                  color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${isAudio ? 'Audio Transcript' : 'Document'} (${widget.document.detectedLanguage.toUpperCase()})  •  $wordCount words  •  ${_displayedText.length} characters',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // If Audio file: show Audio player
          if (isAudio && hasAudioSource) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: OriginalAudioPlayer(
                audioPath: effectiveAudioPath,
                audioTitle: widget.document.filename,
                fallbackDurationMs: (widget.document.timedWords.isNotEmpty)
                    ? widget.document.timedWords.last.endMs
                    : null,
              ),
            ),
          ] else if (isAudio && ttsState.currentTtsResponse != null) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: ReadoraAudioPlayer(),
            ),
          ],

          // Extracted Document Text / Audio Transcript Viewer Area
          Expanded(
            child: _displayedText.isEmpty
                ? Center(
                    child: Text(
                      isAudio ? 'No transcript available for this audio.' : 'No text extracted for this document.',
                      style: TextStyle(fontSize: 13, color: context.textMutedColor),
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(20.0),
                      child: SelectableText(
                        _displayedText,
                        style: TextStyle(
                          fontSize: settings.readerFontSize.size,
                          height: 1.6,
                          color: textColor,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
