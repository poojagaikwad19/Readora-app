import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../common_widgets/app_button.dart';
import '../../../common_widgets/language_selector.dart';
import '../../domain/document_model.dart';
import '../../domain/voice_model.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../providers/document_tts_provider.dart';
import '../widgets/readora_audio_player.dart';
import '../widgets/readora_voice_selector.dart';

class PdfReaderScreen extends ConsumerStatefulWidget {
  final DocumentModel document;

  const PdfReaderScreen({super.key, required this.document});

  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen> {
  late String _displayedText;
  late String _activeLanguage;
  bool _isTranslating = false;
  final Map<String, String> _translations = {};

  @override
  void initState() {
    super.initState();
    _displayedText = widget.document.text;
    _activeLanguage = widget.document.detectedLanguage.toLowerCase();
    _translations[_activeLanguage] = widget.document.text;

    // Synchronize active document and language on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsProvider);
      final currentActive = ref.read(documentTtsNotifierProvider).activeDocument;
      final lang = _activeLanguage;
      final defVoice = settings.defaultVoiceForLanguage(lang);
      if (currentActive?.docId != widget.document.docId) {
        ref.read(documentTtsNotifierProvider.notifier).setActiveDocument(widget.document);
      }
      ref.read(documentTtsNotifierProvider.notifier).setSelectedLanguage(lang, voiceId: defVoice);
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
    if (_stopAudioOnLeave) {
      try {
        _ttsNotifier?.stopAudio();
      } catch (_) {}
    }
    super.dispose();
  }



  void _onLanguageChanged(String newLang) async {
    final langKey = newLang.toLowerCase();
    final settings = ref.read(settingsProvider);
    final targetVoice = settings.defaultVoiceForLanguage(langKey);
    ref.read(documentTtsNotifierProvider.notifier).setSelectedLanguage(langKey, voiceId: targetVoice);

    // 1. If already translated & cached
    if (_translations.containsKey(langKey)) {
      setState(() {
        _activeLanguage = langKey;
        _displayedText = _translations[langKey]!;
      });
      return;
    }

    // 2. If selecting original document language
    if (langKey == widget.document.detectedLanguage.toLowerCase()) {
      setState(() {
        _activeLanguage = langKey;
        _displayedText = widget.document.text;
      });
      return;
    }

    // 3. Otherwise translate document text to selected language
    setState(() {
      _isTranslating = true;
    });

    final translated = await ref
        .read(documentTtsNotifierProvider.notifier)
        .translateText(widget.document.text, langKey);

    if (!mounted) return;

    if (translated != null && translated.isNotEmpty) {
      _translations[langKey] = translated;
      setState(() {
        _activeLanguage = langKey;
        _displayedText = translated;
        _isTranslating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Document translated into ${langKey.toUpperCase()}!'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      setState(() {
        _isTranslating = false;
      });
    }
  }

  void _handleConvertAndSpeak() async {
    final ttsNotifier = ref.read(documentTtsNotifierProvider.notifier);
    final apiClient = ref.read(apiClientProvider);

    final response = await ttsNotifier.generateSpeech(
      text: _displayedText,
      baseUrl: apiClient.baseUrl.replaceAll('/api', ''),
    );

    if (!mounted) return;

    if (response != null) {
      if (response.translatedText != null && response.translatedText!.isNotEmpty) {
        final langKey = ref.read(documentTtsNotifierProvider).selectedLanguage.toLowerCase();
        _translations[langKey] = response.translatedText!;
        setState(() {
          _activeLanguage = langKey;
          _displayedText = response.translatedText!;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech generated successfully! Playing audio...'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final ttsState = ref.watch(documentTtsNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : AppColors.border;
    final textColor = isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary;

    // All 21 Readora voices
    final rawVoices = ttsState.voices.isNotEmpty
        ? ttsState.voices
        : VoiceModel.defaultVoices();

    final Map<String, VoiceModel> uniqueVoicesMap = {};
    for (var v in rawVoices) {
      uniqueVoicesMap[v.voiceId] = v;
    }
    final uniqueVoices = uniqueVoicesMap.values.toList();

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

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppColors.background,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        title: Text(
          widget.document.filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: textColor),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.copy_rounded, color: textColor),
            tooltip: 'Copy Text',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _displayedText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Text copied to clipboard!')),
              );
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Detected Info & Character Counter Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: isDark ? const Color(0xFF2E2452) : AppColors.accentPill,
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Original: ${widget.document.detectedLanguage.toUpperCase()} | Active View: ${_activeLanguage.toUpperCase()} | Words: ${_displayedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} | Chars: ${_displayedText.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Target Language & Voice Accent Controls Bar
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardBg,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Target Language',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.textSecondaryColor),
                          ),
                          const SizedBox(height: 4),
                          LanguageSelector(
                            selectedLanguage: ttsState.selectedLanguage,
                            onChanged: _onLanguageChanged,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Voice Accent',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.textSecondaryColor),
                          ),
                          const SizedBox(height: 4),
                          ReadoraVoiceSelector(
                            voices: uniqueVoices,
                            selectedVoiceId: selectedVoiceValue,
                            onVoiceSelected: (voiceId) {
                              ref.read(documentTtsNotifierProvider.notifier).setSelectedVoice(voiceId);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Readora Web Style Mode Selection Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        avatar: const Icon(Icons.description_outlined, size: 14),
                        label: Text('Original (${widget.document.detectedLanguage.toUpperCase()})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        selected: _activeLanguage == widget.document.detectedLanguage.toLowerCase(),
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: _activeLanguage == widget.document.detectedLanguage.toLowerCase() ? Colors.white : textColor),
                        onSelected: (selected) {
                          if (selected) {
                            _onLanguageChanged(widget.document.detectedLanguage);
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        avatar: const Icon(Icons.g_translate_rounded, size: 14),
                        label: const Text('English Speech', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        selected: _activeLanguage == 'english',
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: _activeLanguage == 'english' ? Colors.white : textColor),
                        onSelected: (selected) {
                          if (selected) {
                            _onLanguageChanged('english');
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        avatar: const Icon(Icons.translate_rounded, size: 14),
                        label: const Text('Marathi Speech (मराठी)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        selected: _activeLanguage == 'marathi' || _activeLanguage == 'mr',
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: (_activeLanguage == 'marathi' || _activeLanguage == 'mr') ? Colors.white : textColor),
                        onSelected: (selected) {
                          if (selected) {
                            _onLanguageChanged('marathi');
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        avatar: const Icon(Icons.language_rounded, size: 14),
                        label: const Text('Hindi Speech (हिन्दी)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        selected: _activeLanguage == 'hindi' || _activeLanguage == 'hi',
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: (_activeLanguage == 'hindi' || _activeLanguage == 'hi') ? Colors.white : textColor),
                        onSelected: (selected) {
                          if (selected) {
                            _onLanguageChanged('hindi');
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Extracted & Translated Document Viewer Area
          Expanded(
            child: _isTranslating
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: AppColors.primary),
                        const SizedBox(height: 16),
                        Text(
                          'Translating document into ${ttsState.selectedLanguage.toUpperCase()}...',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Preserving document structure and formatting',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
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

          // Bottom Action Section: Convert Button & Embedded Player
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              border: Border(top: BorderSide(color: borderColor)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppButton(
                    label: _isTranslating
                        ? 'Translating document...'
                        : 'Convert & Listen to Speech (${ttsState.selectedLanguage.toUpperCase()})',
                    icon: Icons.volume_up_rounded,
                    isLoading: ttsState.isGeneratingSpeech || _isTranslating,
                    onPressed: _isTranslating ? null : _handleConvertAndSpeak,
                  ),

                  // Embedded Player Widget if Speech Active
                  if (ttsState.currentTtsResponse != null) ...[
                    const SizedBox(height: 14),
                    _buildEmbeddedPlayerCard(ttsState),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Embedded Audio Player Widget
  Widget _buildEmbeddedPlayerCard(DocumentTtsState ttsState) {
    return const ReadoraAudioPlayer();
  }
}
