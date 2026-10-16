import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/document_tts_provider.dart';
import '../widgets/readora_audio_player.dart';
import '../widgets/readora_voice_selector.dart';
import '../widgets/readora_language_selector.dart';
import '../widgets/original_audio_player.dart';
import '../widgets/timed_transcript_viewer.dart';
import '../widgets/readora_selector_manager.dart';
import '../../../settings/domain/settings_model.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../domain/document_model.dart';
import '../../domain/tts_response_model.dart';
import '../../domain/voice_model.dart';
import 'package:readora_audio_stt/readora_audio_stt.dart' as readora_stt hide TimedWord;

enum UploadMode { tts, stt, all }

class _PdfUploadViewState {
  final bool isExtracting;
  final bool isGeneratingSpeech;
  final String? originalAudioPath;
  final DocumentModel? activeDocument;
  final String selectedSttLanguage;
  final TtsResponseModel? currentTtsResponse;
  final String selectedLanguage;
  final List<VoiceModel> voices;
  final String selectedVoiceId;
  final PlayerState playerState;
  final TtsInputSource? _activeTtsTab;
  TtsInputSource get activeTtsTab => _activeTtsTab ?? TtsInputSource.document;

  const _PdfUploadViewState({
    required this.isExtracting,
    required this.isGeneratingSpeech,
    this.originalAudioPath,
    this.activeDocument,
    required this.selectedSttLanguage,
    this.currentTtsResponse,
    required this.selectedLanguage,
    required this.voices,
    required this.selectedVoiceId,
    required this.playerState,
    TtsInputSource? activeTtsTab = TtsInputSource.document,
  }) : _activeTtsTab = activeTtsTab ?? TtsInputSource.document;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PdfUploadViewState &&
          runtimeType == other.runtimeType &&
          isExtracting == other.isExtracting &&
          isGeneratingSpeech == other.isGeneratingSpeech &&
          originalAudioPath == other.originalAudioPath &&
          activeDocument == other.activeDocument &&
          selectedSttLanguage == other.selectedSttLanguage &&
          currentTtsResponse == other.currentTtsResponse &&
          selectedLanguage == other.selectedLanguage &&
          listEquals(voices, other.voices) &&
          selectedVoiceId == other.selectedVoiceId &&
          playerState == other.playerState &&
          activeTtsTab == other.activeTtsTab;

  @override
  int get hashCode => Object.hash(
        isExtracting,
        isGeneratingSpeech,
        originalAudioPath,
        activeDocument,
        selectedSttLanguage,
        currentTtsResponse,
        selectedLanguage,
        selectedVoiceId,
        playerState,
        activeTtsTab,
      );
}

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
  String? _sourceLanguage;         // Original detected language
  int _ttsInputTypeIndex = 0; // 0: Upload Document, 1: Enter Text
  final TextEditingController _textInputController = TextEditingController();
  final ScrollController _textInputScrollController = ScrollController();
  bool _isSpeechSettingsExpanded = false;
  int _sttRequestSeq = 0; // Request token to ignore superseded/obsolete STT responses

  @override
  void initState() {
    super.initState();
    if (widget.mode == UploadMode.stt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(documentTtsNotifierProvider.notifier).stopAudioAndClearQueue();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsProvider);
      if (widget.mode == UploadMode.tts) {
        ref.read(documentTtsNotifierProvider.notifier).switchTtsTab(TtsInputSource.document);
        if (_selectedFilePath == null) {
          final defLang = settings.defaultTtsLanguage;
          final defVoice = settings.defaultVoiceForLanguage(defLang);
          ref.read(documentTtsNotifierProvider.notifier).setSelectedLanguage(defLang, voiceId: defVoice);
        }
      } else if (widget.mode == UploadMode.stt && _selectedFilePath == null) {
        ref.read(documentTtsNotifierProvider.notifier).setSelectedSttLanguage(settings.defaultSttLanguage);
      }
    });
  }

  void _onSelectTtsTab(int index) {
    if (_ttsInputTypeIndex == index) return;
    final source = index == 0 ? TtsInputSource.document : TtsInputSource.text;
    ref.read(documentTtsNotifierProvider.notifier).switchTtsTab(source);
    setState(() {
      _ttsInputTypeIndex = index;
    });
  }

  DocumentTtsNotifier? _ttsNotifier;
  bool _stopAudioOnLeave = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ttsNotifier = ref.read(documentTtsNotifierProvider.notifier);
    _stopAudioOnLeave = ref.read(settingsProvider).stopAudioOnLeaveScreen;
  }

  @override
  void dispose() {
    _textInputController.dispose();
    _textInputScrollController.dispose();
    if (_stopAudioOnLeave) {
      try {
        _ttsNotifier?.stopAudioAndClearQueue();
        _ttsNotifier?.stopOriginalAudio();
      } catch (_) {}
    }
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
        final settings = ref.read(settingsProvider);
        final docVoice = settings.defaultVoiceForLanguage(detectedLang);
        ref.read(documentTtsNotifierProvider.notifier).setSelectedLanguage(detectedLang, voiceId: docVoice);

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

      _sttRequestSeq++;

      String? detectedFileLang;
      if (widget.mode == UploadMode.stt) {
        final lower = fileName.toLowerCase();
        if (lower.contains('marathi') || RegExp(r'[\b_\-]mr[\b_\-\.]').hasMatch(lower)) {
          detectedFileLang = 'marathi';
        } else if (lower.contains('hindi') || RegExp(r'[\b_\-]hi[\b_\-\.]').hasMatch(lower)) {
          detectedFileLang = 'hindi';
        } else if (lower.contains('english') || RegExp(r'[\b_\-]en[\b_\-\.]').hasMatch(lower)) {
          detectedFileLang = 'english';
        }
      }

      setState(() {
        _selectedFilePath = filePath;
        _selectedFileName = fileName;
        _originalExtractedText = null;
        _extractedText = null;
        _sourceLanguage = detectedFileLang ?? _sourceLanguage;
        _extractionError = null;
        _pageCount = 1;
        if (widget.mode == UploadMode.stt) {
          _isExtractingText = true;
        }
      });

      if (detectedFileLang != null) {
        ref.read(documentTtsNotifierProvider.notifier).setSelectedSttLanguage(detectedFileLang);
      }

      if (widget.mode == UploadMode.stt) {
        ref.read(documentTtsNotifierProvider.notifier).stopAudioAndClearQueue();
        _uploadAndExtract();
      } else {
        ref.read(documentTtsNotifierProvider.notifier).resetTtsResponse(source: TtsInputSource.document);
        _extractTextFromFile(filePath);
      }
    }
  }

  void _handleLanguageChange(String targetLanguage) async {
    final notifier = ref.read(documentTtsNotifierProvider.notifier);
    final settings = ref.read(settingsProvider);
    final targetVoice = settings.defaultVoiceForLanguage(targetLanguage);
    notifier.setSelectedLanguage(targetLanguage, voiceId: targetVoice);
    notifier.resetTtsResponse(); // Invalidate old generated audio

    if (_ttsInputTypeIndex == 0) {
      // Document Upload Mode: Translate from pristine _originalExtractedText
      if (_originalExtractedText == null || _originalExtractedText!.trim().isEmpty) return;

      final normTarget = targetLanguage.toLowerCase().trim();
      final normSource = (_sourceLanguage ?? 'english').toLowerCase().trim();

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
    final isDark = context.isDark;

    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: context.scaffoldBg,
          appBar: AppBar(
            backgroundColor: context.surfaceBg,
            elevation: 1,
            title: Text(
              widget.mode == UploadMode.stt ? 'Transcript' : 'Extracted Text (${language.toUpperCase()})',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimaryColor),
            ),
            leading: IconButton(
              icon: Icon(Icons.close_rounded, color: context.textPrimaryColor),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
                tooltip: 'Copy transcript',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Transcript copied to clipboard!')),
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: isDark ? const Color(0xFF1E293B) : AppColors.background,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.mode == UploadMode.stt
                          ? '$wordCount Words • ${text.length} Chars'
                          : '$_pageCount ${_pageCount == 1 ? 'Page' : 'Pages'} • $wordCount Words • ${text.length} Chars',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                    ),
                    Text(
                      'Language: ${language.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                      ),
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
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.7,
                          color: context.textPrimaryColor,
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

  void _removeSelectedFile() {
    _sttRequestSeq++;
    ref.read(documentTtsNotifierProvider.notifier).cancelStt();
    ref.read(documentTtsNotifierProvider.notifier).stopAudio();
    ref.read(documentTtsNotifierProvider.notifier).resetTtsResponse(source: TtsInputSource.document);
    setState(() {
      _isExtractingText = false;
      _selectedFilePath = null;
      _selectedFileName = null;
      _extractedText = null;
      _originalExtractedText = null;
      _sourceLanguage = null;
      _extractionError = null;
      _pageCount = 1;
    });
  }

  void _cancelTranscription() {
    _sttRequestSeq++;
    ref.read(documentTtsNotifierProvider.notifier).cancelStt();
    setState(() {
      _isExtractingText = false;
      _selectedFilePath = null;
      _selectedFileName = null;
      _extractionError = null;
      _extractedText = null;
      _originalExtractedText = null;
    });
  }

  void _showRetranscribeDialog(BuildContext context, Color primaryColor) {
    if (ref.read(documentTtsNotifierProvider).isExtracting) return;

    final audioPath = _selectedFilePath ??
        ref.read(documentTtsNotifierProvider).originalAudioPath ??
        ref.read(documentTtsNotifierProvider).activeDocument?.audioSourcePath;

    if (audioPath == null || !File(audioPath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Original recording unavailable. Please select the audio file again to re-transcribe.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final currentLang = _sourceLanguage ?? ref.read(documentTtsNotifierProvider).selectedSttLanguage;
    String chosenLang = currentLang.toLowerCase().trim();
    if (chosenLang != 'marathi' && chosenLang != 'hindi' && chosenLang != 'auto') {
      chosenLang = 'english';
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: context.surfaceBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.refresh_rounded, size: 20, color: context.textPrimaryColor),
                const SizedBox(width: 8),
                Text(
                  'Re-transcribe Audio',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimaryColor),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Re-transcribe this recording to refresh the transcript and word timestamps.',
                  style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Language',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.borderColor),
                    color: context.cardBg,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: chosenLang,
                      dropdownColor: context.cardBg,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        DropdownMenuItem(value: 'auto', child: Text('Auto Detect', style: TextStyle(color: context.textPrimaryColor))),
                        DropdownMenuItem(value: 'marathi', child: Text('Marathi (मराठी)', style: TextStyle(color: context.textPrimaryColor))),
                        DropdownMenuItem(value: 'hindi', child: Text('Hindi (हिन्दी)', style: TextStyle(color: context.textPrimaryColor))),
                        DropdownMenuItem(value: 'english', child: Text('English', style: TextStyle(color: context.textPrimaryColor))),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => chosenLang = val);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('Cancel', style: TextStyle(color: context.textSecondaryColor)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  ref.read(documentTtsNotifierProvider.notifier).setSelectedSttLanguage(chosenLang);
                  setState(() => _sourceLanguage = chosenLang);
                  _uploadAndExtract();
                },
                child: const Text('Re-transcribe'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _uploadAndExtract() async {
    final bool isStt = widget.mode == UploadMode.stt;
    final apiClient = ref.read(apiClientProvider);
    final baseUrl = apiClient.baseUrl.replaceAll('/api', '');

    final audioPath = _selectedFilePath ??
        ref.read(documentTtsNotifierProvider).originalAudioPath ??
        ref.read(documentTtsNotifierProvider).activeDocument?.audioSourcePath;

    if (!isStt && _selectedFilePath == null && _ttsInputTypeIndex == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a document or image file first')),
      );
      return;
    }

    if (isStt && audioPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an audio file first')),
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
            source: TtsInputSource.text,
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
    final fileToCheck = isStt ? (audioPath ?? '') : (_selectedFilePath ?? '');
    final ext = fileToCheck.contains('.') ? fileToCheck.split('.').last.toLowerCase() : '';
    final isAudio = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'webm', 'opus', 'amr', '3gp', 'mp4', 'wma'].contains(ext);

    if (isAudio || isStt) {
      if (ref.read(documentTtsNotifierProvider).isExtracting) return; // Prevent duplicate taps

      if (audioPath == null || !File(audioPath).existsSync()) {
        setState(() {
          _isExtractingText = false;
          _extractionError = 'Original recording unavailable. Please select the audio file again.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Original recording unavailable. Please select the audio file again to re-transcribe.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      try {
        readora_stt.AudioFormatValidator.validate(audioPath);
      } catch (valErr) {
        setState(() {
          _isExtractingText = false;
          _extractionError = valErr.toString().replaceAll('Exception: ', '');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(valErr.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      setState(() {
        _isExtractingText = true;
        _extractionError = null;
      });

      try {
        // Stop any active audio and clear old state before starting transcription
        await ref.read(documentTtsNotifierProvider.notifier).stopAudioAndClearQueue();

        final thisSeq = ++_sttRequestSeq;
        // Capture configured language when request starts without altering settings
        final selectedStt = ref.read(documentTtsNotifierProvider).selectedSttLanguage;
        final configuredLang = _sourceLanguage ?? selectedStt;

        final doc = await ref
            .read(documentTtsNotifierProvider.notifier)
            .transcribeAudioFile(audioPath, language: configuredLang);

        if (!mounted || thisSeq != _sttRequestSeq) {
          if (mounted) {
            setState(() {
              _isExtractingText = false;
            });
          }
          return;
        }

        if (doc != null && doc.text.trim().isNotEmpty) {
          setState(() {
            _isExtractingText = false;
            _extractedText = doc.text;
            _originalExtractedText = doc.text;
            _sourceLanguage = doc.detectedLanguage;
            _extractionError = null;
          });
          ref.read(documentTtsNotifierProvider.notifier).setSelectedSttLanguage(doc.detectedLanguage);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Transcribed audio ${doc.filename}!'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          final state = ref.read(documentTtsNotifierProvider);
          final errorMsg = state.errorMessage ?? 'No speech detected in audio file. Tap Retry to try again.';
          setState(() {
            _isExtractingText = false;
            _extractionError = errorMsg;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: AppColors.error,
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _uploadAndExtract(),
              ),
            ),
          );
        }
      } catch (err) {
        if (mounted) {
          setState(() {
            _isExtractingText = false;
            _extractionError = 'Audio transcription error: $err';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Audio transcription error: $err'),
              backgroundColor: AppColors.error,
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _uploadAndExtract(),
              ),
            ),
          );
        }
      } finally {
        if (mounted && _isExtractingText) {
          setState(() {
            _isExtractingText = false;
          });
        }
      }
      return;
    } else {
      // Document TTS: generate speech for extracted/translated text!
      final textToSpeech = (_ttsInputTypeIndex == 1)
          ? _textInputController.text.trim()
          : ((_extractedText != null && _extractedText!.trim().isNotEmpty)
              ? _extractedText!.trim()
              : (_selectedFilePath != null
                  ? ((await ref.read(documentTtsNotifierProvider.notifier).extractDocument(_selectedFilePath!))?.text ?? '')
                  : ''));

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
            source: TtsInputSource.document,
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
    final ttsState = ref.watch(
      documentTtsNotifierProvider.select(
        (s) => _PdfUploadViewState(
          isExtracting: s.isExtracting,
          isGeneratingSpeech: s.isGeneratingSpeech,
          originalAudioPath: s.originalAudioPath,
          activeDocument: s.activeDocument,
          selectedSttLanguage: s.selectedSttLanguage,
          currentTtsResponse: s.currentTtsResponse,
          selectedLanguage: s.selectedLanguage,
          voices: s.voices,
          selectedVoiceId: s.selectedVoiceId,
          playerState: s.playerState,
          activeTtsTab: s.activeTtsTab,
        ),
      ),
    );
    final isStt = widget.mode == UploadMode.stt;
    final primaryColor = isStt ? const Color(0xFF0D9488) : AppColors.primary;
    final apiClient = ref.read(apiClientProvider);
    final baseUrl = apiClient.baseUrl.replaceAll('/api', '');

    final bool hasSelectedFile = _selectedFilePath != null;

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        backgroundColor: context.surfaceBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimaryColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isStt ? 'Speech to Text' : 'Text to Speech',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: context.textPrimaryColor),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isStt) ...[
              // === SPEECH TO TEXT TARGET LAYOUT ===
              if (_extractedText != null && _extractedText!.isNotEmpty) ...[
                // STT RESULTS VIEW (Screenshot 3)
                // 1. Selected filename | Change file
                _buildSttFileRow(primaryColor, ttsState.isExtracting),
                const SizedBox(height: 10),

                // 2. Compact Original Audio player
                OriginalAudioPlayer(
                  audioPath: ttsState.originalAudioPath ??
                      ttsState.activeDocument?.audioSourcePath ??
                      _selectedFilePath,
                  audioTitle: _selectedFileName ?? ttsState.activeDocument?.filename,
                  fallbackDurationMs: (ttsState.activeDocument?.timedWords.isNotEmpty ?? false)
                      ? ttsState.activeDocument!.timedWords.last.endMs
                      : null,
                ),
                const SizedBox(height: 12),

                // 3. Timed Transcript Viewer (prioritised, large readable surface)
                TimedTranscriptViewer(
                  transcript: _extractedText!,
                  timedWords: ttsState.activeDocument?.timedWords ?? const [],
                  language: _sourceLanguage,
                  initialMode: ref.watch(settingsProvider).defaultTranscriptView == TranscriptDefaultView.follow
                      ? TranscriptViewerMode.follow
                      : TranscriptViewerMode.full,
                  height: (MediaQuery.of(context).size.height * 0.48).clamp(380.0, 560.0),
                  onExpandFullscreen: () => _showFullscreenTextViewerDialog(
                    context,
                    _extractedText!,
                    ttsState.selectedSttLanguage,
                  ),
                  onRetranscribe: () => _showRetranscribeDialog(context, primaryColor),
                  isRetranscribing: ttsState.isExtracting,
                ),
                const SizedBox(height: 12),

                // 5. Compact “Read transcript aloud” action (or TTS player when generated TTS is active)
                if (ttsState.currentTtsResponse == null) ...[
                  OutlinedButton.icon(
                    onPressed: (ttsState.isGeneratingSpeech)
                        ? null
                        : () async {
                            // Mutual audio exclusion: deactivate original audio first
                            await ref.read(documentTtsNotifierProvider.notifier).stopOriginalAudio();
                            ref.read(documentTtsNotifierProvider.notifier).generateSpeech(
                                  text: _extractedText!,
                                  baseUrl: baseUrl,
                                );
                          },
                    icon: ttsState.isGeneratingSpeech
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
                          )
                        : const Icon(Icons.volume_up_rounded, size: 16),
                    label: Text(
                      ttsState.isGeneratingSpeech ? 'Generating speech...' : 'Read transcript aloud',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: BorderSide(color: primaryColor.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ] else ...[
                  _buildCompactAudioPlayer(ttsState, primaryColor, baseUrl),
                ],
                const SizedBox(height: 12),
              ] else ...[
                // STT INITIAL UPLOAD / INLINE PROCESSING VIEW (Screenshot 1)
                _buildSttEmptyState(primaryColor),
              ],
            ] else ...[
              // === TEXT TO SPEECH VIEW (TTS PRESERVED UNCHANGED) ===
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
                      onTap: () => _onSelectTtsTab(0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInputTypeTab(
                      label: 'Enter Text',
                      isSelected: _ttsInputTypeIndex == 1,
                      primaryColor: primaryColor,
                      onTap: () => _onSelectTtsTab(1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (_ttsInputTypeIndex == 0) ...[
                if (hasSelectedFile) ...[
                  const Text(
                    'UPLOAD FILE',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 4),
                  _buildCompactSelectedFileCard(primaryColor, ttsState),
                  if (_extractionError != null && _extractionError!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildErrorCard(primaryColor),
                  ],
                  const SizedBox(height: 8),
                ] else ...[
                  _buildTtsEmptyState(primaryColor),
                ],

                if (hasSelectedFile) ...[
                  const Text(
                    'LANGUAGE',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 4),
                  _buildTtsLanguageDropdown(ttsState, primaryColor),
                  const SizedBox(height: 8),

                  const Text(
                    'VOICE',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 4),
                  _buildTtsVoiceDropdown(ttsState, primaryColor),
                  const SizedBox(height: 8),

                  _buildExtractedTextViewer(primaryColor),
                  const SizedBox(height: 12),

                  if (ttsState.currentTtsResponse != null) ...[
                    _buildCompactAudioPlayer(ttsState, primaryColor, baseUrl),
                    const SizedBox(height: 12),
                  ],

                  ElevatedButton(
                    onPressed: (ttsState.isExtracting || ttsState.isGeneratingSpeech || _isTranslating) ? null : _uploadAndExtract,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                      shadowColor: primaryColor.withValues(alpha: 0.3),
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
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    ttsState.currentTtsResponse != null ? 'Re-generate Speech' : 'Convert to Speech →',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                  ),
                ],
              ] else ...[
                _buildEnterTextView(ttsState, primaryColor, baseUrl),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // STT File row: Selected filename (with ellipsis) | Change file
  Widget _buildSttFileRow(Color primaryColor, bool isExtracting) {
    final fileName = _selectedFileName ??
        ref.watch(documentTtsNotifierProvider.select((s) => s.activeDocument?.filename)) ??
        'Audio recording';
    final isDark = context.isDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.audiotrack_rounded, size: 18, color: primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: context.textPrimaryColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: isExtracting ? null : _pickFile,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, size: 14, color: primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    'Change file',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: isExtracting ? null : _removeSelectedFile,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(4.0),
              child: Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  // ULTRA-COMPACT SLIM SELECTED FILE CARD
  Widget _buildCompactSelectedFileCard(Color primaryColor, _PdfUploadViewState ttsState) {
    final ext = _selectedFileName?.split('.').last.toUpperCase() ?? 'PDF';
    final isExtracting = _isExtractingText || ttsState.isExtracting;
    final isDark = context.isDark;

    return InkWell(
      onTap: isExtracting ? null : _pickFile,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryColor.withOpacity(0.3), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(isDark ? 0.15 : 0.04),
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isExtracting
                          ? primaryColor.withOpacity(0.1)
                          : (isDark ? const Color(0xFF2E2452) : AppColors.accentPill),
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
                        color: isExtracting
                            ? primaryColor
                            : (isDark ? const Color(0xFFC4B5FD) : AppColors.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: isExtracting ? null : _removeSelectedFile,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(4.0),
                child: Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ILLUSTRATED EMPTY STATES (TTS & STT) ---

  Widget _buildTtsEmptyState(Color primaryColor) {
    return _buildIllustratedEmptyState(
      isStt: false,
      accentColor: AppColors.primary,
      surfaceColor: AppColors.lavenderSurface,
      illustrationAsset: 'assets/images/tts.png',
      heading: 'Give your documents a voice',
      description: 'Upload a document or enter text to listen.',
      buttonLabel: 'Choose a document',
      buttonIcon: Icons.file_upload_outlined,
      formatChips: const ['PDF', 'DOCX', 'TXT', 'Images'],
      steps: const ['Upload', 'Choose voice', 'Listen'],
      tipText: 'Selectable-text PDFs usually extract faster than scanned pages.',
    );
  }

  Widget _buildSttEmptyState(Color primaryColor) {
    return _buildIllustratedEmptyState(
      isStt: true,
      accentColor: primaryColor,
      surfaceColor: AppColors.mintSurface,
      illustrationAsset: 'assets/images/stt.png',
      heading: 'Turn your audio into words',
      description: 'Upload a recording to create a readable transcript.',
      buttonLabel: 'Choose an audio file',
      buttonIcon: Icons.audio_file_outlined,
      formatChips: const ['MP3', 'WAV', 'M4A', 'AAC', 'FLAC', 'OGG'],
      steps: const ['Upload', 'Transcribe', 'Read'],
      tipText: 'Clear recordings help improve transcription accuracy.',
    );
  }

  Widget _buildIllustratedEmptyState({
    required bool isStt,
    required Color accentColor,
    required Color surfaceColor,
    required String illustrationAsset,
    required String heading,
    required String description,
    required String buttonLabel,
    required IconData buttonIcon,
    required List<String> formatChips,
    required List<String> steps,
    required String tipText,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;
    // Responsive illustration display height (135 on smaller phones, 170 on standard phones)
    final illustrationHeight = (screenHeight < 680) ? 135.0 : 170.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Existing illustration with soft radial glow
          _buildIllustratedBanner(
            isStt: isStt,
            illustrationAsset: illustrationAsset,
            illustrationHeight: illustrationHeight,
          ),
          const SizedBox(height: 14),

          // 2. Heading
          Text(
            heading,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: context.textPrimaryColor,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),

          // 3. Description
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // 4. Highlighted rounded upload card with dashed border
          _buildUploadCard(
            isStt: isStt,
            buttonLabel: buttonLabel,
            buttonIcon: buttonIcon,
            formatChips: formatChips,
          ),
          const SizedBox(height: 16),

          // 5. Compact instructional row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.borderColor),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                for (int i = 0; i < steps.length; i++) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 17,
                        height: 17,
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        steps[i],
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                  if (i < steps.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.0),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 6. Small tip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: context.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 15,
                  color: Colors.amber.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tipText,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.textSecondaryColor,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIllustratedBanner({
    required bool isStt,
    required String illustrationAsset,
    required double illustrationHeight,
  }) {
    final glowDiameter = illustrationHeight * 1.25;

    return SizedBox(
      height: illustrationHeight,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft decorative radial glow fading smoothly to transparent
          IgnorePointer(
            child: Container(
              width: glowDiameter,
              height: glowDiameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: isStt
                      ? [
                          const Color(0xFF2DD4BF).withValues(alpha: 0.28),
                          const Color(0xFF99F6E4).withValues(alpha: 0.12),
                          const Color(0xFFDDF7F2).withValues(alpha: 0.0),
                        ]
                      : [
                          const Color(0xFFA855F7).withValues(alpha: 0.25),
                          const Color(0xFFC084FC).withValues(alpha: 0.10),
                          const Color(0xFFEDE9FE).withValues(alpha: 0.0),
                        ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          // Crisp original illustration at full opacity
          ExcludeSemantics(
            child: Image.asset(
              illustrationAsset,
              height: illustrationHeight,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadCard({
    required bool isStt,
    required String buttonLabel,
    required IconData buttonIcon,
    required List<String> formatChips,
  }) {
    final isDark = context.isDark;
    final cardGradient = isDark
        ? (isStt
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F2926), Color(0xFF133E38)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1F1D36), Color(0xFF28204A)],
              ))
        : (isStt
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF3FCFA), Color(0xFFDDF7F2)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF8F5FF), Color(0xFFEDE9FE)],
              ));

    final dashedBorderColor = isDark
        ? (isStt
            ? const Color(0xFF2DD4BF).withValues(alpha: 0.35)
            : const Color(0xFFA855F7).withValues(alpha: 0.40))
        : (isStt
            ? const Color(0xFF0D9488).withValues(alpha: 0.45)
            : const Color(0xFF8B5CF6).withValues(alpha: 0.50));

    final iconColor = isDark
        ? (isStt ? const Color(0xFF2DD4BF) : const Color(0xFFC084FC))
        : (isStt ? const Color(0xFF0D9488) : const Color(0xFF7C3AED));

    final buttonGradient = isStt
        ? const [Color(0xFF0F766E), Color(0xFF0D9488)]
        : const [Color(0xFF6D28D9), Color(0xFF7C3AED)];

    final buttonShadowColor = isStt
        ? const Color(0xFF0F766E).withValues(alpha: 0.28)
        : const Color(0xFF6D28D9).withValues(alpha: 0.28);

    final chipBgColor = isDark
        ? (isStt ? const Color(0xFF133E38) : const Color(0xFF2E2452))
        : (isStt ? const Color(0xFFDDF7F2) : const Color(0xFFEDE9FE));
    final chipTextColor = isDark
        ? (isStt ? const Color(0xFF5EEAD4) : const Color(0xFFDDD6FE))
        : (isStt ? const Color(0xFF0F766E) : const Color(0xFF6D28D9));
    final chipBorderColor = isDark
        ? (isStt
            ? const Color(0xFF2DD4BF).withValues(alpha: 0.3)
            : const Color(0xFFA855F7).withValues(alpha: 0.3))
        : (isStt
            ? const Color(0xFFB7EBE1).withValues(alpha: 0.9)
            : const Color(0xFFDDD6FE).withValues(alpha: 0.9));

    final bool isExtracting = _isExtractingText ||
        ref.watch(documentTtsNotifierProvider.select((s) => s.isExtracting));
    final bool isProcessing = isStt && isExtracting && _selectedFilePath != null;
    final bool hasError = isStt && _extractionError != null && _extractionError!.isNotEmpty && !isProcessing;

    return CustomPaint(
      painter: DashedRectPainter(
        color: dashedBorderColor,
        strokeWidth: 1.2,
        dash: 6.0,
        gap: 4.0,
        radius: 18.0,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          gradient: cardGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: isStt
                  ? const Color(0xFF0D9488).withValues(alpha: 0.05)
                  : const Color(0xFF7C3AED).withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: isProcessing
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: -12,
                    right: -6,
                    child: Semantics(
                      label: 'Cancel transcription',
                      button: true,
                      child: IconButton(
                        icon: Icon(Icons.close_rounded, size: 20, color: context.textSecondaryColor),
                        tooltip: 'Cancel transcription',
                        onPressed: _cancelTranscription,
                        splashRadius: 20,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.8,
                            valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Transcribing in progress',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimaryColor,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _selectedFileName ?? 'Audio file',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : hasError
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.error_outline_rounded,
                            size: 22,
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _selectedFileName ?? 'Audio file',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _extractionError!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                if (ref.read(documentTtsNotifierProvider).isExtracting) return;
                                _uploadAndExtract();
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 15),
                              label: const Text('Retry', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0D9488),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 1,
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: _removeSelectedFile,
                              icon: const Icon(Icons.close_rounded, size: 15),
                              label: const Text('Remove', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.textSecondaryColor,
                                side: BorderSide(color: context.borderColor),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Upload icon in circular badge
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: iconColor.withValues(alpha: 0.10),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.cloud_upload_outlined,
                          size: 22,
                          color: iconColor,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Primary upload button with subtle gradient, white text, and restrained shadow
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: buttonGradient,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: buttonShadowColor,
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _pickFile,
                          icon: Icon(buttonIcon, size: 18, color: Colors.white),
                          label: Text(
                            buttonLabel,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            surfaceTintColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Supported format chips with tinted backgrounds and colored text
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: formatChips.map((chip) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: chipBgColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: chipBorderColor,
                                width: 0.9,
                              ),
                            ),
                            child: Text(
                              chip,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: chipTextColor,
                                letterSpacing: 0.2,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
      ),
    );
  }

  // INLINE ERROR CARD WITH RETRY AND REMOVE
  Widget _buildErrorCard(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _extractionError ?? 'Processing failed',
              style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _uploadAndExtract,
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                'Retry',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.error),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: _removeSelectedFile,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(4.0),
              child: Icon(Icons.close_rounded, size: 15, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  // EXTRACTED TEXT VIEWER COMPONENT — LARGE CONTENT AREA
  Widget _buildExtractedTextViewer(Color primaryColor) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double viewerHeight = screenHeight * 0.38; // Dynamic ~300-350px tall
    final isExtracting = _isExtractingText ||
        ref.watch(documentTtsNotifierProvider.select((s) => s.isExtracting));
    final selectedLanguage =
        ref.watch(documentTtsNotifierProvider.select((s) => s.selectedLanguage));
    final wordCount = _extractedText != null && _extractedText!.isNotEmpty
        ? _extractedText!.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length
        : 0;

    final isDark = context.isDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.mode == UploadMode.stt ? 'WHISPER AUDIO TRANSCRIPT' : 'EXTRACTED TEXT',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.8),
            ),
            if (_extractedText != null && _extractedText!.isNotEmpty)
              Row(
                children: [
                  Text(
                    widget.mode == UploadMode.stt
                        ? '$wordCount Words • ${_extractedText!.length} Chars'
                        : '$_pageCount ${_pageCount == 1 ? 'Page' : 'Pages'} • $wordCount Words • ${_extractedText!.length} Chars',
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
                        _showFullscreenTextViewerDialog(context, _extractedText!, selectedLanguage);
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
            color: context.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
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
                            'Translating text into ${selectedLanguage.toUpperCase()}...',
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
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.6,
                                color: context.textPrimaryColor,
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
                                style: TextStyle(fontSize: 12, color: context.textMutedColor),
                              ),
                            ),
        ),
      ],
    );
  }


  // TTS Language Selector - COMPACT & ANCHORED
  Widget _buildTtsLanguageDropdown(
    _PdfUploadViewState ttsState,
    Color primaryColor, {
    Widget Function(BuildContext, String, bool)? builder,
  }) {
    return ReadoraLanguageSelector(
      selectedLanguage: ttsState.selectedLanguage,
      onChanged: (val) {
        _handleLanguageChange(val);
      },
      builder: builder,
    );
  }

  // TTS Voice Selector - COMPACT & ANCHORED
  Widget _buildTtsVoiceDropdown(
    _PdfUploadViewState ttsState,
    Color primaryColor, {
    Widget Function(BuildContext, String, bool)? builder,
  }) {
    List<VoiceModel> voices = ttsState.voices.isNotEmpty ? ttsState.voices : VoiceModel.defaultVoices();

    final Map<String, VoiceModel> uniqueVoicesMap = {};
    for (var v in voices) {
      uniqueVoicesMap[v.voiceId] = v;
    }
    final uniqueVoices = uniqueVoicesMap.values.toList();

    final settings = ref.read(settingsProvider);
    final defaultForLang = settings.defaultVoiceForLanguage(ttsState.selectedLanguage);
    final selectedVoiceValue = uniqueVoices.any((v) => v.voiceId == ttsState.selectedVoiceId)
        ? ttsState.selectedVoiceId
        : (uniqueVoices.any((v) => v.voiceId == defaultForLang)
            ? defaultForLang
            : (uniqueVoices.isNotEmpty ? uniqueVoices.first.voiceId : 'CwhRBWXzGAHq8TQ4Fs17'));

    if (!uniqueVoices.any((v) => v.voiceId == ttsState.selectedVoiceId) && uniqueVoices.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(documentTtsNotifierProvider.notifier).setSelectedVoice(selectedVoiceValue);
      });
    }

    return ReadoraVoiceSelector(
      voices: uniqueVoices,
      selectedVoiceId: selectedVoiceValue,
      onVoiceSelected: (voiceId) {
        ref.read(documentTtsNotifierProvider.notifier).setSelectedVoice(voiceId);
      },
      builder: builder,
    );
  }

  Widget _buildInputTypeTab({
    required String label,
    required bool isSelected,
    required Color primaryColor,
    required VoidCallback onTap,
  }) {
    final isDark = context.isDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withOpacity(isDark ? 0.25 : 0.12) : context.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? primaryColor : context.borderColor),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected
                ? (isDark && primaryColor == AppColors.primary ? const Color(0xFFC4B5FD) : primaryColor)
                : context.textSecondaryColor,
          ),
        ),
      ),
    );
  }

  // SLEEK CAPSULE AUDIO PLAYER MATCHING USER REFERENCE SCREENSHOT
  Widget _buildCompactAudioPlayer(_PdfUploadViewState ttsState, Color primaryColor, String baseUrl) {
    return const ReadoraAudioPlayer();
  }

  // Redesigned Text to Speech -> Enter Text View (Matching Reference)
  Widget _buildEnterTextView(_PdfUploadViewState ttsState, Color primaryColor, String baseUrl) {
    final isDark = context.isDark;
    final isRunning = ttsState.isGeneratingSpeech || _isTranslating || ttsState.isExtracting;

    // Responsive editor height: occupies ~40-45% of usable screen height on typical phones
    final screenHeight = MediaQuery.of(context).size.height;
    final double editorHeight = (screenHeight * 0.42).clamp(270.0, 440.0);

    // Active Speech Settings Summary (e.g. "English · Roger")
    final currentLangKey = ttsState.selectedLanguage.toLowerCase().trim();
    final currentLangLabel = currentLangKey == 'marathi'
        ? 'Marathi'
        : (currentLangKey == 'hindi' ? 'Hindi' : 'English');

    final settings = ref.read(settingsProvider);
    final defaultForLang = settings.defaultVoiceForLanguage(ttsState.selectedLanguage);
    List<VoiceModel> voices = ttsState.voices.isNotEmpty ? ttsState.voices : VoiceModel.defaultVoices();
    final matchingVoice = voices.firstWhere(
      (v) => v.voiceId == ttsState.selectedVoiceId,
      orElse: () => voices.firstWhere(
        (v) => v.voiceId == defaultForLang,
        orElse: () => voices.isNotEmpty ? voices.first : VoiceModel.defaultVoices().first,
      ),
    );
    final currentVoiceName = processVoiceForDisplay(matchingVoice).name;
    final speechSettingsSummary = '$currentLangLabel · $currentVoiceName';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Glowing lavender-to-mint header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF7C3AED).withValues(alpha: 0.16),
                      const Color(0xFF0D9488).withValues(alpha: 0.12),
                    ]
                  : [
                      const Color(0xFFEDE9FE).withValues(alpha: 0.75),
                      const Color(0xFFDDF7F2).withValues(alpha: 0.75),
                    ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Give your words a voice',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                  color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Type or paste text, then choose how it sounds.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Large white text editor card with rounded corners and thin purple border
        Container(
          key: const Key('enter_text_editor_card'),
          height: editorHeight,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? const Color(0xFF8B5CF6).withValues(alpha: 0.5) : const Color(0xFFC7D2FE),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your text',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    scrollbarTheme: ScrollbarThemeData(
                      thumbColor: WidgetStateProperty.all(primaryColor.withValues(alpha: 0.6)),
                      radius: const Radius.circular(8),
                      thickness: WidgetStateProperty.all(4.0),
                    ),
                  ),
                  child: Scrollbar(
                    controller: _textInputScrollController,
                    thumbVisibility: true,
                    radius: const Radius.circular(8),
                    thickness: 4.0,
                    child: TextField(
                      controller: _textInputController,
                      scrollController: _textInputScrollController,
                      scrollPhysics: const ClampingScrollPhysics(),
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: context.textPrimaryColor,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Start typing or paste your text here…',
                        hintStyle: TextStyle(
                          color: context.textMutedColor,
                          fontSize: 14,
                          height: 1.5,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.only(right: 12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textInputController,
                  builder: (context, value, _) {
                    return Text(
                      '${value.text.length} characters',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: context.textMutedColor,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Compact collapsible Speech settings card
        Container(
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.borderColor, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Collapsible header row
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    ReadoraSelectorManager.closeActive();
                    setState(() {
                      _isSpeechSettingsExpanded = !_isSpeechSettingsExpanded;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Text(
                          'Speech settings',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!_isSpeechSettingsExpanded) ...[
                          Expanded(
                            child: Text(
                              speechSettingsSummary,
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: context.textSecondaryColor,
                              ),
                            ),
                          ),
                        ] else ...[
                          const Spacer(),
                        ],
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: _isSpeechSettingsExpanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 22,
                            color: isDark ? Colors.white70 : const Color(0xFF1E1B4B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Expandable content containing existing Language & Voice dropdowns
              ClipRect(
                child: AnimatedCrossFade(
                  firstChild: const SizedBox(width: double.infinity, height: 0),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(height: 1, thickness: 0.8, color: context.borderColor),
                      _buildTtsLanguageDropdown(
                        ttsState,
                        primaryColor,
                        builder: (context, currentLabel, isOpen) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDark ? const Color(0xFF312E81) : const Color(0xFFEDE9FE),
                                  ),
                                  child: const Icon(
                                    Icons.public_rounded,
                                    size: 20,
                                    color: Color(0xFF6366F1),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Language',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: context.textSecondaryColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        currentLabel,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                          color: context.textPrimaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                  color: isDark ? Colors.white70 : const Color(0xFF1E1B4B),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      Divider(height: 1, thickness: 0.8, color: context.borderColor),
                      _buildTtsVoiceDropdown(
                        ttsState,
                        primaryColor,
                        builder: (context, currentVoiceName, isOpen) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDark ? const Color(0xFF312E81) : const Color(0xFFEDE9FE),
                                  ),
                                  child: const Icon(
                                    Icons.record_voice_over_rounded,
                                    size: 19,
                                    color: Color(0xFF6366F1),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Voice',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: context.textSecondaryColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        currentVoiceName,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                          color: context.textPrimaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                  color: isDark ? Colors.white70 : const Color(0xFF1E1B4B),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  crossFadeState: _isSpeechSettingsExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 250),
                  sizeCurve: Curves.easeInOut,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. Audio player (if speech has been generated)
        if (ttsState.currentTtsResponse != null) ...[
          _buildCompactAudioPlayer(ttsState, primaryColor, baseUrl),
          const SizedBox(height: 14),
        ],

        // 5. Full-width purple gradient button
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _textInputController,
          builder: (context, value, _) {
            final hasText = value.text.trim().isNotEmpty;
            final canPress = hasText && !isRunning;

            return Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: canPress
                    ? const LinearGradient(
                        colors: [Color(0xFF5B3FF5), Color(0xFF7C3AED)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : null,
                color: canPress ? null : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                boxShadow: canPress
                    ? [
                        BoxShadow(
                          color: const Color(0xFF5B3FF5).withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: ElevatedButton(
                onPressed: canPress ? _uploadAndExtract : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: isRunning
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
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            ttsState.currentTtsResponse != null ? 'Re-generate Speech →' : 'Convert to Speech →',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: canPress ? Colors.white : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                            ),
                          ),
                        ],
                      ),
              ),
            );
          },
        ),
      ],
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

/// Subtle rounded dashed border painter for upload cards
class DashedRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dash;
  final double radius;

  const DashedRectPainter({
    required this.color,
    this.strokeWidth = 1.2,
    this.dash = 5.0,
    this.gap = 3.5,
    this.radius = 16.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        final extract = metric.extractPath(distance, next > metric.length ? metric.length : next);
        canvas.drawPath(extract, paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedRectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dash != dash ||
        oldDelegate.gap != gap ||
        oldDelegate.radius != radius;
  }
}


