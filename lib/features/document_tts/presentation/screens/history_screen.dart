import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../common_widgets/pdf_card.dart';
import '../../domain/document_model.dart';
import '../providers/document_tts_provider.dart';
import 'pdf_reader_screen.dart';

enum HistoryFilter { all, document, audio }

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  static bool isDocumentType(DocumentModel doc) {
    const docExts = {
      'pdf',
      'docx',
      'doc',
      'txt',
      'rtf',
      'png',
      'jpg',
      'jpeg',
      'webp',
      'bmp',
      'tiff',
      'gif',
    };
    final type = doc.fileType.trim().toLowerCase();
    if (docExts.contains(type)) return true;
    if (type.startsWith('image/') ||
        type == 'application/pdf' ||
        type.contains('word') ||
        type == 'text/plain') {
      return true;
    }

    if (doc.filename.contains('.')) {
      final ext = doc.filename.split('.').last.trim().toLowerCase();
      if (docExts.contains(ext)) return true;
    }
    return false;
  }

  static bool isAudioType(DocumentModel doc) {
    const audioExts = {
      'mp3',
      'wav',
      'm4a',
      'aac',
      'ogg',
      'flac',
      'opus',
      'wma',
      'audio',
    };
    final type = doc.fileType.trim().toLowerCase();
    if (audioExts.contains(type)) return true;
    if (type.startsWith('audio/')) return true;

    if (doc.filename.contains('.')) {
      final ext = doc.filename.split('.').last.trim().toLowerCase();
      if (audioExts.contains(ext)) return true;
    }
    return false;
  }

  static bool matchesFilter(DocumentModel doc, HistoryFilter filter) {
    switch (filter) {
      case HistoryFilter.all:
        return true;
      case HistoryFilter.document:
        return isDocumentType(doc);
      case HistoryFilter.audio:
        return isAudioType(doc);
    }
  }

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  HistoryFilter _selectedFilter = HistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final ttsState = ref.watch(documentTtsNotifierProvider);
    final allDocs = ttsState.userDocuments;
    final filteredDocs = allDocs.where((d) => HistoryScreen.matchesFilter(d, _selectedFilter)).toList();

    final isDark = context.isDark;

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        backgroundColor: context.surfaceBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimaryColor),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2E2452) : AppColors.accentPill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.history_rounded,
                color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Readora',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: context.textPrimaryColor,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(documentTtsNotifierProvider.notifier).loadUserDocuments();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Heading & Subtitle
            Text(
              'History',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: context.textPrimaryColor,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Recent uploaded documents and audio files',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 16),

            // Compact Three-Segment Filter Control (Lavender + Mint Theme)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _buildSegmentItem('All', HistoryFilter.all),
                  _buildSegmentItem('Document', HistoryFilter.document),
                  _buildSegmentItem('Audio', HistoryFilter.audio),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Filtered Items List
            Expanded(
              child: filteredDocs.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, index) {
                        final doc = filteredDocs[index];
                        return Dismissible(
                          key: ValueKey('history_dismiss_${doc.docId}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
                                SizedBox(width: 6),
                                Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onDismissed: (direction) async {
                            final success = await ref
                                .read(documentTtsNotifierProvider.notifier)
                                .deleteDocument(doc.docId);
                            if (!success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to delete item from history. Restored.'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          },
                          child: PdfCard(
                            document: doc,
                            onTap: () {
                              ref
                                  .read(documentTtsNotifierProvider.notifier)
                                  .setActiveDocument(doc);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PdfReaderScreen(document: doc),
                                ),
                              );
                            },
                            onPlaySpeech: () {
                              ref
                                  .read(documentTtsNotifierProvider.notifier)
                                  .setActiveDocument(doc);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PdfReaderScreen(document: doc),
                                ),
                              );
                            },
                            onDelete: () async {
                              final success = await ref
                                  .read(documentTtsNotifierProvider.notifier)
                                  .deleteDocument(doc.docId);
                              if (!success && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Failed to delete item from history.'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentItem(String label, HistoryFilter filter) {
    final isSelected = _selectedFilter == filter;
    final isDark = context.isDark;
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
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF2E2452) : const Color(0xFFF3F0FF))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? (isDark ? const Color(0xFFC4B5FD) : AppColors.primary)
                  : context.textSecondaryColor,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    IconData icon;
    String title;
    String subtitle;
    final isDark = context.isDark;

    switch (_selectedFilter) {
      case HistoryFilter.all:
        icon = Icons.history_rounded;
        title = 'No history items yet';
        subtitle = 'Uploaded documents and transcribed audio files will appear here.';
        break;
      case HistoryFilter.document:
        icon = Icons.description_outlined;
        title = 'No documents found';
        subtitle = 'Uploaded PDF, DOCX, TXT, and extracted images will appear here.';
        break;
      case HistoryFilter.audio:
        icon = Icons.graphic_eq_rounded;
        title = 'No audio files found';
        subtitle = 'Transcribed MP3, WAV, and M4A audio recordings will appear here.';
        break;
    }

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2E2452) : const Color(0xFFF3F0FF),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: context.textSecondaryColor,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
