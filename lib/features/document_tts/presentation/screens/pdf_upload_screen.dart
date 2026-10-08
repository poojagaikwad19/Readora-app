import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/document_tts_provider.dart';
import '../../domain/voice_model.dart';
import 'pdf_reader_screen.dart';

enum UploadMode { tts, stt, all }

class PdfUploadScreen extends ConsumerStatefulWidget {
  final UploadMode mode;

  const PdfUploadScreen({super.key, this.mode = UploadMode.all});

  @override
  ConsumerState<PdfUploadScreen> createState() => _PdfUploadScreenState();
}

class _PdfUploadScreenState extends ConsumerState<PdfUploadScreen> {
  String? _selectedFilePath;
  String? _selectedFileName;
  String? _originalExtractedText; // Pristine original extracted text
  String? _extractedText;         // Currently displayed text (original or translated)
  String? _extractionError;
  int _pageCount = 1;
  bool _isExtractingText = false;
  bool _isTranslating = false;     // Translation loading state
  String _sourceLanguage = 'english'; // Original detected language
  int _ttsInputTypeIndex = 0; // 0: Upload Document, 1: Enter Text
  final TextEditingController _textInputController = TextEditingController();

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _textInputController.dispose();
    super.dispose();
  }

  void _extractTextFromFile(String filePath) async {
    setState(() {
      _isExtractingText = true;
      _extractionError = null;
      _extractedText = null;
      _originalExtractedText = null;
    });

    final ext = filePath.split('.').last.toLowerCase();
    final isAudio = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'webm', 'opus', 'amr', '3gp', 'mp4', 'wma'].contains(ext);

    if (!isAudio && widget.mode != UploadMode.stt) {
      final doc = await ref
          .read(documentTtsNotifierProvider.notifier)
          .extractDocument(filePath);

      if (mounted) {
        String? extracted = doc?.text;
        int pages = doc?.pageCount ?? 1;
        String detectedLang = doc?.detectedLanguage ?? 'english';

        // Fallback for plain text files if backend returns empty
        if ((extracted == null || extracted.trim().isEmpty) &&
            (ext == 'txt' || ext == 'text' || ext == 'json' || ext == 'md')) {
          try {
            final file = File(filePath);
            if (file.existsSync()) {
              extracted = file.readAsStringSync();
            }
          } catch (_) {}
        }

        final err = ref.read(documentTtsNotifierProvider).errorMessage;

        setState(() {
          _isExtractingText = false;
          _originalExtractedText = extracted;
          _extractedText = extracted;
          _sourceLanguage = detectedLang;
          _pageCount = pages;
          _extractionError = (extracted == null || extracted.trim().isEmpty)
              ? (err ?? 'Failed to extract text from file')
              : null;
        });

        // Initially align TTS language selection with detected document language
        ref.read(documentTtsNotifierProvider.notifier).setSelectedLanguage(detectedLang);

        if (_extractionError != null && _extractionError!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_extractionError!),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isExtractingText = false;
        });
      }
    }
  }

  void _pickFile() async {
    final List<String> allowedExtensions;
    if (widget.mode == UploadMode.tts) {
      allowedExtensions = ['pdf', 'txt', 'doc', 'docx', 'jpg', 'jpeg', 'png'];
    } else if (widget.mode == UploadMode.stt) {
      allowedExtensions = [
        'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'webm', 'opus', 'amr', '3gp', 'mp4', 'wma'
      ];
    } else {
      allowedExtensions = [
        'pdf', 'txt', 'doc', 'docx', 'jpg', 'jpeg', 'png',
        'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'webm', 'opus', 'amr', '3gp', 'mp4', 'wma'
      ];
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      final fileName = result.files.single.name;

      setState(() {
        _selectedFilePath = filePath;
        _selectedFileName = fileName;
        _originalExtractedText = null;
        _extractedText = null;
        _extractionError = null;
        _pageCount = 1;
      });

      ref.read(documentTtsNotifierProvider.notifier).resetTtsResponse();
      _extractTextFromFile(filePath);
    }
  }

  void _handleLanguageChange(String targetLanguage) async {
    final notifier = ref.read(documentTtsNotifierProvider.notifier);
    notifier.setSelectedLanguage(targetLanguage);
    notifier.resetTtsResponse(); // Invalidate old generated audio

    if (_ttsInputTypeIndex == 0) {
      // Document Upload Mode: Translate from pristine _originalExtractedText
      if (_originalExtractedText == null || _originalExtractedText!.trim().isEmpty) return;

      final normTarget = targetLanguage.toLowerCase().trim();
      final normSource = _sourceLanguage.toLowerCase().trim();

      if (normTarget == normSource) {
        // Target matches original source language -> restore pristine original text directly!
        setState(() {
          _extractedText = _originalExtractedText;
        });
        return;
      }

      // Translate directly from _originalExtractedText (prevents chained translation degradation)
      setState(() {
        _isTranslating = true;
      });

      final translated = await notifier.translateText(
        _originalExtractedText!,
        targetLanguage,
        sourceLanguage: _sourceLanguage,
      );

      if (mounted) {
        setState(() {
          _isTranslating = false;
          if (translated != null && translated.trim().isNotEmpty) {
            _extractedText = translated;
          }
        });

        if (translated == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Translation failed. Please try again.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } else {
      // Enter Text Mode: Translate current typed text if available
      final currentInput = _textInputController.text.trim();
      if (currentInput.isEmpty) return;

      setState(() {
        _isTranslating = true;
      });

      final translated = await notifier.translateText(
        currentInput,
        targetLanguage,
      );

      if (mounted) {
        setState(() {
          _isTranslating = false;
          if (translated != null && translated.trim().isNotEmpty) {
            _textInputController.text = translated;
          }
        });

        if (translated == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Translation failed. Please try again.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  void _showFullscreenTextViewerDialog(BuildContext context, String text, String language) {
    final wordCount = text.isNotEmpty ? text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length : 0;

    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 1,
            title: Text(
              'Extracted Text (${language.toUpperCase()})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
                tooltip: 'Copy text',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Extracted text copied to clipboard!')),
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.background,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$_pageCount ${_pageCount == 1 ? 'Page' : 'Pages'} • $wordCount Words • ${text.length} Chars',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                    ),
                    Text(
                      'Language: ${language.toUpperCase()}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: SelectableText(
                        text,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.7,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _uploadAndExtract() async {
    final bool isStt = widget.mode == UploadMode.stt;
    final apiClient = ref.read(apiClientProvider);
    final baseUrl = apiClient.baseUrl.replaceAll('/api', '');

    if (_selectedFilePath == null && (!isStt && _ttsInputTypeIndex == 0)) {
      final msg = isStt
          ? 'Please select an audio file first'
          : 'Please select a document or image file first';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      return;
    }

    // Direct Text Input for TTS
    if (!isStt && _ttsInputTypeIndex == 1) {
      final text = _textInputController.text.trim();
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No text available to convert to speech.')),
        );
        return;
      }

      final response = await ref.read(documentTtsNotifierProvider.notifier).generateSpeech(
            text: text,
            baseUrl: baseUrl,
          );

      if (!mounted) return;
      if (response != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Speech generated & playing!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        final err = ref.read(documentTtsNotifierProvider).errorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err ?? 'Failed to generate speech'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // File Extraction / STT Transcription
    final ext = _selectedFilePath!.split('.').last.toLowerCase();
    final isAudio = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'webm', 'opus', 'amr', '3gp', 'mp4', 'wma'].contains(ext);

    if (isAudio || isStt) {
      final doc = await ref
          .read(documentTtsNotifierProvider.notifier)
          .transcribeAudioFile(_selectedFilePath!);

      if (!mounted) return;
      if (doc != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transcribed audio ${doc.filename}!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PdfReaderScreen(document: doc),
          ),
        );
      } else {
        final state = ref.read(documentTtsNotifierProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.errorMessage ?? 'File processing failed'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } else {
      // Document TTS: generate speech for extracted/translated text!
      final textToSpeech = (_extractedText != null && _extractedText!.trim().isNotEmpty)
          ? _extractedText!.trim()
          : (_selectedFilePath != null
              ? ((await ref.read(documentTtsNotifierProvider.notifier).extractDocument(_selectedFilePath!))?.text ?? '')
              : '');

      if (!mounted) return;
      if (textToSpeech.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No text available to convert to speech.')),
        );
        return;
      }

      final response = await ref.read(documentTtsNotifierProvider.notifier).generateSpeech(
            text: textToSpeech,
            baseUrl: baseUrl,
          );

      if (!mounted) return;
      if (response != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Speech generated & playing!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        final err = ref.read(documentTtsNotifierProvider).errorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err ?? 'Failed to generate speech'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ttsState = ref.watch(documentTtsNotifierProvider);
    final isStt = widget.mode == UploadMode.stt;
    final primaryColor = isStt ? const Color(0xFF0D9488) : AppColors.primary;
    final apiClient = ref.read(apiClientProvider);
    final baseUrl = apiClient.baseUrl.replaceAll('/api', '');

    final bool hasSelectedFile = _selectedFilePath != null;
    final bool isEnterTextMode = !isStt && _ttsInputTypeIndex == 1;
    final bool showOptionsAndButton = hasSelectedFile || isEnterTextMode;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isStt ? 'Speech to Text' : 'Text to Speech',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Readora Settings')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. INPUT TYPE TOGGLE (TTS only) - COMPACT
            if (!isStt) ...[
              const Text(
                'INPUT TYPE',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.8),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _buildInputTypeTab(
                      label: 'Upload Document',
                      isSelected: _ttsInputTypeIndex == 0,
                      primaryColor: primaryColor,
                      onTap: () => setState(() => _ttsInputTypeIndex = 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInputTypeTab(
                      label: 'Enter Text',
                      isSelected: _ttsInputTypeIndex == 1,
                      primaryColor: primaryColor,
                      onTap: () => setState(() => _ttsInputTypeIndex = 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // 2. FILE SELECTION AREA (LARGE UPLOAD BOX WHEN NO FILE / ULTRA-COMPACT CARD WHEN FILE SELECTED)
            if (isStt || _ttsInputTypeIndex == 0) ...[
              Text(
                isStt ? 'AUDIO FILE' : 'UPLOAD FILE',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.8),
              ),
              const SizedBox(height: 4),

              if (hasSelectedFile)
                // ULTRA-COMPACT SLIM FILE CARD WHEN FILE IS SELECTED
                _buildCompactSelectedFileCard(primaryColor, ttsState)
              else
                // LARGE UPLOAD AREA WHEN NO FILE IS SELECTED
                _buildLargeUploadBox(primaryColor, ttsState, isStt),

              const SizedBox(height: 8),
            ] else ...[
              // ENTER TEXT AREA (TTS mode)
              const Text(
                'ENTER TEXT',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.8),
              ),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _textInputController,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Type or paste text here to convert into speech...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // 3. LANGUAGE, VOICE, EXTRACTED TEXT & CONVERT OPTIONS
            if (showOptionsAndButton) ...[
              // LANGUAGE DROPDOWN - COMPACT
              const Text(
                'LANGUAGE',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.8),
              ),
              const SizedBox(height: 4),
              isStt ? _buildSttLanguageDropdown(primaryColor) : _buildTtsLanguageDropdown(ttsState, primaryColor),
              const SizedBox(height: 8),

              // VOICE DROPDOWN (TTS only) - COMPACT
              if (!isStt) ...[
                const Text(
                  'VOICE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.8),
                ),
                const SizedBox(height: 4),
                _buildTtsVoiceDropdown(ttsState, primaryColor),
                const SizedBox(height: 8),
              ],

              // SUPPORTED LANGUAGES BADGES FOR STT
              if (isStt) ...[
                const Text(
                  'SUPPORTED LANGUAGES',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.8),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    _buildLanguageBadge('English (en)', primaryColor, Icons.language_rounded),
                    const SizedBox(width: 8),
                    _buildLanguageBadge('Marathi (mr-IN)', primaryColor, Icons.translate_rounded),
                    const SizedBox(width: 8),
                    _buildLanguageBadge('Hindi (hi-IN)', primaryColor, Icons.translate_rounded),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // 4. EXTRACTED TEXT VIEWER (TTS mode when document is uploaded) - EXPANDED / LARGE
              if (!isStt && _ttsInputTypeIndex == 0) ...[
                _buildExtractedTextViewer(primaryColor),
                const SizedBox(height: 12),
              ],

              // 4.5 COMPACT READORA AUDIO PLAYER (shown when speech is generated and ready/playing)
              if (!isStt && ttsState.currentTtsResponse != null) ...[
                _buildCompactAudioPlayer(ttsState, primaryColor, baseUrl),
                const SizedBox(height: 12),
              ],

              // 5. CONVERT / TRANSCRIBE BUTTON
              ElevatedButton(
                onPressed: (ttsState.isExtracting || ttsState.isGeneratingSpeech || _isTranslating) ? null : _uploadAndExtract,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                  shadowColor: primaryColor.withOpacity(0.3),
                ),
                child: ttsState.isGeneratingSpeech
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Generating Speech...',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      )
                    : _isTranslating
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Translating Text...',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ],
                          )
                        : ttsState.isExtracting
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Extracting Text...',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    isStt
                                        ? 'Transcribe →'
                                        : (ttsState.currentTtsResponse != null ? 'Re-generate Speech' : 'Convert to Speech →'),
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ULTRA-COMPACT SLIM SELECTED FILE CARD
  Widget _buildCompactSelectedFileCard(Color primaryColor, DocumentTtsState ttsState) {
    final ext = _selectedFileName?.split('.').last.toUpperCase() ?? 'PDF';
    final isExtracting = _isExtractingText || ttsState.isExtracting;

    return InkWell(
      onTap: isExtracting ? null : _pickFile,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryColor.withOpacity(0.3), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                widget.mode == UploadMode.stt ? Icons.audiotrack_rounded : Icons.description_rounded,
                color: primaryColor,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _selectedFileName ?? 'Selected File',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isExtracting ? primaryColor.withOpacity(0.1) : AppColors.accentPill,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isExtracting
                          ? 'Extracting...'
                          : (_extractedText != null && _extractedText!.isNotEmpty
                              ? '$_pageCount ${_pageCount == 1 ? 'Page' : 'Pages'}'
                              : '$ext selected'),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isExtracting ? primaryColor : AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () {
                setState(() {
                  _selectedFilePath = null;
                  _selectedFileName = null;
                  _extractedText = null;
                  _pageCount = 1;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Icon(Icons.close_rounded, size: 16, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // LARGE UPLOAD AREA BOX (SHOWN WHEN NO FILE IS SELECTED)
  Widget _buildLargeUploadBox(Color primaryColor, DocumentTtsState ttsState, bool isStt) {
    return InkWell(
      onTap: (ttsState.isExtracting || _isExtractingText) ? null : _pickFile,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.border,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              Icons.cloud_upload_outlined,
              size: 44,
              color: primaryColor,
            ),
            const SizedBox(height: 12),
            Text(
              'Tap to upload or select file',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isStt ? 'MP3, WAV, M4A, etc.' : 'PDF, DOCX, TXT, etc.',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  // EXTRACTED TEXT VIEWER COMPONENT — LARGE CONTENT AREA
  Widget _buildExtractedTextViewer(Color primaryColor) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double viewerHeight = screenHeight * 0.38; // Dynamic ~300-350px tall
    final ttsState = ref.watch(documentTtsNotifierProvider);
    final isExtracting = _isExtractingText || ttsState.isExtracting;
    final wordCount = _extractedText != null && _extractedText!.isNotEmpty
        ? _extractedText!.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'EXTRACTED TEXT',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.8),
            ),
            if (_extractedText != null && _extractedText!.isNotEmpty)
              Row(
                children: [
                  Text(
                    '$_pageCount ${_pageCount == 1 ? 'Page' : 'Pages'} • $wordCount Words • ${_extractedText!.length} Chars',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      if (_extractedText != null && _extractedText!.isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: _extractedText!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Extracted text copied to clipboard!')),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Icon(Icons.copy_rounded, size: 14, color: primaryColor),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      if (_extractedText != null && _extractedText!.isNotEmpty) {
                        _showFullscreenTextViewerDialog(context, _extractedText!, ttsState.selectedLanguage);
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Icon(Icons.open_in_full_rounded, size: 14, color: primaryColor),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: viewerHeight < 260 ? 260 : viewerHeight,
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isExtracting
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: primaryColor),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Extracting text & page count from document...',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryColor),
                      ),
                    ],
                  ),
                )
              : _isTranslating
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: primaryColor),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Translating text into ${ttsState.selectedLanguage.toUpperCase()}...',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryColor),
                          ),
                        ],
                      ),
                    )
                  : (_extractedText != null && _extractedText!.isNotEmpty)
                      ? Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: SelectableText(
                              _extractedText!,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.6,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        )
                      : _extractionError != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 32),
                                    const SizedBox(height: 8),
                                    Text(
                                      _extractionError!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.error),
                                    ),
                                    const SizedBox(height: 12),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        if (_selectedFilePath != null) {
                                          _extractTextFromFile(_selectedFilePath!);
                                        }
                                      },
                                      icon: const Icon(Icons.refresh_rounded, size: 16),
                                      label: const Text('Retry Extraction', style: TextStyle(fontSize: 12)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryColor,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                'No text extracted yet or file is empty.',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                              ),
                            ),
        ),
      ],
    );
  }

  // STT Language Dropdown (English en, Marathi mr-IN, Hindi hi-IN) - COMPACT
  Widget _buildSttLanguageDropdown(Color primaryColor) {
    final currentLang = ref.watch(documentTtsNotifierProvider).selectedLanguage;

    final sttLanguages = [
      {'code': 'english', 'label': 'English (en)', 'value': 'english'},
      {'code': 'marathi', 'label': 'Marathi (mr-IN)', 'value': 'marathi'},
      {'code': 'hindi', 'label': 'Hindi (hi-IN)', 'value': 'hindi'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: sttLanguages.any((l) => l['value'] == currentLang.toLowerCase()) ? currentLang.toLowerCase() : 'marathi',
          isExpanded: true,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: primaryColor, size: 20),
          items: sttLanguages.map((lang) {
            return DropdownMenuItem<String>(
              value: lang['value'],
              child: Row(
                children: [
                  Icon(Icons.language_rounded, size: 16, color: primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lang['label']!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              ref.read(documentTtsNotifierProvider.notifier).setSelectedLanguage(val);
            }
          },
        ),
      ),
    );
  }

  // TTS Language Dropdown - COMPACT
  Widget _buildTtsLanguageDropdown(DocumentTtsState ttsState, Color primaryColor) {
    final ttsLanguages = [
      {'label': 'English', 'value': 'english'},
      {'label': 'Marathi', 'value': 'marathi'},
      {'label': 'Hindi', 'value': 'hindi'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: ttsLanguages.any((l) => l['value'] == ttsState.selectedLanguage.toLowerCase())
              ? ttsState.selectedLanguage.toLowerCase()
              : 'english',
          isExpanded: true,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: primaryColor, size: 20),
          items: ttsLanguages.map((lang) {
            return DropdownMenuItem<String>(
              value: lang['value'],
              child: Row(
                children: [
                  Icon(Icons.public_rounded, size: 16, color: primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lang['label']!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              _handleLanguageChange(val);
            }
          },
        ),
      ),
    );
  }

  // TTS Voice Dropdown - COMPACT
  Widget _buildTtsVoiceDropdown(DocumentTtsState ttsState, Color primaryColor) {
    List<VoiceModel> voices = ttsState.voices.isNotEmpty ? ttsState.voices : VoiceModel.defaultVoices();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: voices.any((v) => v.voiceId == ttsState.selectedVoiceId) ? ttsState.selectedVoiceId : voices.first.voiceId,
          isExpanded: true,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: primaryColor, size: 20),
          items: voices.map((voice) {
            return DropdownMenuItem<String>(
              value: voice.voiceId,
              child: Row(
                children: [
                  Icon(Icons.person_pin_rounded, size: 16, color: primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${voice.name} (${voice.category})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              ref.read(documentTtsNotifierProvider.notifier).setSelectedVoice(val);
            }
          },
        ),
      ),
    );
  }

  Widget _buildInputTypeTab({
    required String label,
    required bool isSelected,
    required Color primaryColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? primaryColor : AppColors.border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? primaryColor : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageBadge(String label, Color primaryColor, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: primaryColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  // SLEEK CAPSULE AUDIO PLAYER MATCHING USER REFERENCE SCREENSHOT
  Widget _buildCompactAudioPlayer(DocumentTtsState ttsState, Color primaryColor, String baseUrl) {
    final response = ttsState.currentTtsResponse;
    if (response == null) return const SizedBox.shrink();

    final isPlaying = ttsState.playerState == PlayerState.playing;
    final maxSec = (ttsState.audioDuration.inSeconds > 0 ? ttsState.audioDuration.inSeconds : 1.0).toDouble();
    final curSec = ttsState.audioPosition.inSeconds.toDouble().clamp(0.0, maxSec);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40), // Capsule pill shape
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: Row(
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
                color: const Color(0xFF1F2937),
                size: 26,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 2. Playback Duration (0:17 / 0:31)
          Text(
            '${_formatDuration(ttsState.audioPosition)} / ${_formatDuration(ttsState.audioDuration)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(width: 12),

          // 3. Pink-to-Cyan Gradient Progress Bar
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackShape: const GradientRectSliderTrackShape(),
                trackHeight: 7,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0, disabledThumbRadius: 0),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                activeTrackColor: const Color(0xFFEC4899),
                inactiveTrackColor: const Color(0xFF374151).withOpacity(0.18),
                thumbColor: Colors.transparent,
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
          const SizedBox(width: 10),

          // 4. Volume Button
          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4.0),
              child: Icon(
                Icons.volume_up_rounded,
                color: Color(0xFF374151),
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 6),

          // 5. Options / Replay 10s Button
          InkWell(
            onTap: () {
              final newPos = ttsState.audioPosition - const Duration(seconds: 10);
              ref.read(documentTtsNotifierProvider.notifier).seekAudio(
                    newPos < Duration.zero ? Duration.zero : newPos,
                  );
            },
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4.0),
              child: Icon(
                Icons.more_vert_rounded,
                color: Color(0xFF374151),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GradientRectSliderTrackShape extends RectangularSliderTrackShape {
  final LinearGradient gradient;

  const GradientRectSliderTrackShape({
    this.gradient = const LinearGradient(
      colors: [Color(0xFFEC4899), Color(0xFF06B6D4)],
    ),
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    double additionalActiveTrackHeight = 0,
  }) {
    assert(sliderTheme.disabledActiveTrackColor != null);
    assert(sliderTheme.disabledInactiveTrackColor != null);
    assert(sliderTheme.activeTrackColor != null);
    assert(sliderTheme.inactiveTrackColor != null);
    assert(sliderTheme.thumbShape != null);

    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final activeGradientPaint = Paint()
      ..shader = gradient.createShader(trackRect)
      ..style = PaintingStyle.fill;

    final inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor!
      ..style = PaintingStyle.fill;

    final Radius trackRadius = Radius.circular(trackRect.height / 2);

    // Inactive track (full width)
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, trackRadius),
      inactivePaint,
    );

    // Active track (from left to thumbCenter)
    final Rect activeRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
    );

    if (activeRect.width > 0) {
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, trackRadius),
        activeGradientPaint,
      );
    }
  }
}
