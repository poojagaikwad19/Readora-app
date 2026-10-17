import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../document_tts/domain/document_model.dart';

class PdfCard extends StatelessWidget {
  final DocumentModel document;
  final VoidCallback onTap;
  final VoidCallback? onPlaySpeech;
  final VoidCallback? onDelete;

  const PdfCard({
    super.key,
    required this.document,
    required this.onTap,
    this.onPlaySpeech,
    this.onDelete,
  });

  String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  @override
  Widget build(BuildContext context) {
    final lowerType = document.fileType.toLowerCase();
    final isPdf = lowerType == 'pdf';
    final isImage = ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'tiff', 'gif'].contains(lowerType);
    final isAudio = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'opus', 'audio'].contains(lowerType) ||
        document.filename.toLowerCase().endsWith('.mp3') ||
        document.filename.toLowerCase().endsWith('.wav') ||
        document.filename.toLowerCase().endsWith('.m4a');

    final IconData icon = isPdf
        ? Icons.picture_as_pdf_rounded
        : isImage
            ? Icons.image_rounded
            : isAudio
                ? Icons.graphic_eq_rounded
                : Icons.description_rounded;

    final Color iconColor = isPdf
        ? const Color(0xFFE11D48)
        : isImage
            ? const Color(0xFF059669)
            : isAudio
                ? const Color(0xFF7C3AED)
                : AppColors.primary;

    final isDark = context.isDark;

    final Color iconBg = isDark
        ? iconColor.withOpacity(0.18)
        : (isPdf
            ? const Color(0xFFFFE4E6)
            : isImage
                ? const Color(0xFFD1FAE5)
                : isAudio
                    ? const Color(0xFFEDE9FE)
                    : const Color(0xFFF3F0FF));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFEDE9FE),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? const Color(0xFF7C3AED) : const Color(0xFF6D28D9)).withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // File Type Icon Box
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 23),
                ),
                const SizedBox(width: 12),

                // Document Metadata Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        document.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimaryColor,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF2E2452)
                                    : const Color(0xFFEDE9FE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                document.detectedLanguage.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? const Color(0xFFC4B5FD) : const Color(0xFF7C3AED),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_formatNumber(document.characterCount)} chars',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: context.textSecondaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '•  ${document.fileType.toUpperCase()}',
                              style: TextStyle(
                                fontSize: 11,
                                color: context.textMutedColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Actions
                if (onPlaySpeech != null)
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    padding: EdgeInsets.zero,
                    icon: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2E2452) : const Color(0xFFEDE9FE),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: isDark ? const Color(0xFFC4B5FD) : const Color(0xFF7C3AED),
                        size: 22,
                      ),
                    ),
                    tooltip: 'Play Speech',
                    onPressed: onPlaySpeech,
                  ),
                if (onDelete != null)
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: context.textMutedColor,
                      size: 20,
                    ),
                    tooltip: 'Delete',
                    onPressed: onDelete,
                  )
                else if (onPlaySpeech == null)
                  Icon(Icons.chevron_right_rounded, color: context.textMutedColor, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
