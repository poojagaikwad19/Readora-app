import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../common_widgets/app_button.dart';
import '../../../common_widgets/language_selector.dart';
import '../../domain/document_model.dart';
import '../../domain/voice_model.dart';
import '../providers/document_tts_provider.dart';

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

    // Synchronize notifier selected language on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(documentTtsNotifierProvider.notifier).setSelectedLanguage(_activeLanguage);
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _onLanguageChanged(String newLang) async {
    final langKey = newLang.toLowerCase();
    ref.read(documentTtsNotifierProvider.notifier).setSelectedLanguage(langKey);

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
    final ttsState = ref.watch(documentTtsNotifierProvider);

    // All 21 Readora voices
    final rawVoices = ttsState.voices.isNotEmpty
        ? ttsState.voices
        : VoiceModel.defaultVoices();

    final Map<String, VoiceModel> uniqueVoicesMap = {};
    for (var v in rawVoices) {
      uniqueVoicesMap[v.voiceId] = v;
    }
    final uniqueVoices = uniqueVoicesMap.values.toList();

    final selectedVoiceValue = uniqueVoices.any((v) => v.voiceId == ttsState.selectedVoiceId)
        ? ttsState.selectedVoiceId
        : uniqueVoices.first.voiceId;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.document.filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: AppColors.textPrimary),
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
            color: AppColors.accentPill,
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Original: ${widget.document.detectedLanguage.toUpperCase()} | Active View: ${_activeLanguage.toUpperCase()} | Words: ${_displayedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} | Chars: ${_displayedText.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Target Language & Voice Accent Controls Bar
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.border)),
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
                          const Text(
                            'Target Language',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
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
                          const Text(
                            'Voice Accent',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedVoiceValue,
                                isExpanded: true,
                                onChanged: (val) {
                                  if (val != null) {
                                    ref.read(documentTtsNotifierProvider.notifier).setSelectedVoice(val);
                                  }
                                },
                                items: uniqueVoices.map((voice) {
                                  return DropdownMenuItem<String>(
                                    value: voice.voiceId,
                                    child: Text(
                                      voice.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
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
                        labelStyle: TextStyle(color: _activeLanguage == widget.document.detectedLanguage.toLowerCase() ? Colors.white : AppColors.textPrimary),
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
                        labelStyle: TextStyle(color: _activeLanguage == 'english' ? Colors.white : AppColors.textPrimary),
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
                        labelStyle: TextStyle(color: (_activeLanguage == 'marathi' || _activeLanguage == 'mr') ? Colors.white : AppColors.textPrimary),
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
                        labelStyle: TextStyle(color: (_activeLanguage == 'hindi' || _activeLanguage == 'hi') ? Colors.white : AppColors.textPrimary),
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
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
          ),

          // Bottom Action Section: Convert Button & Embedded Player
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: const Border(top: BorderSide(color: AppColors.border)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
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
    final response = ttsState.currentTtsResponse;
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      response?.filename ?? widget.document.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Language: ${ttsState.selectedLanguage.toUpperCase()}',
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${ttsState.playbackRate}x Speed',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Progress Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.primary,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: Slider(
              value: ttsState.audioPosition.inSeconds.toDouble().clamp(
                    0.0,
                    (ttsState.audioDuration.inSeconds > 0 ? ttsState.audioDuration.inSeconds : 1.0).toDouble(),
                  ),
              max: (ttsState.audioDuration.inSeconds > 0 ? ttsState.audioDuration.inSeconds : 1.0).toDouble(),
              onChanged: (val) {
                ref.read(documentTtsNotifierProvider.notifier).seekAudio(Duration(seconds: val.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(ttsState.audioPosition), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                Text(_formatDuration(ttsState.audioDuration), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Player Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 24,
                icon: const Icon(Icons.replay_10_rounded, color: AppColors.textPrimary),
                onPressed: () {
                  final newPos = ttsState.audioPosition - const Duration(seconds: 10);
                  ref.read(documentTtsNotifierProvider.notifier).seekAudio(
                        newPos < Duration.zero ? Duration.zero : newPos,
                      );
                },
              ),
              const SizedBox(width: 10),
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
                child: IconButton(
                  iconSize: 24,
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
              const SizedBox(width: 10),
              IconButton(
                iconSize: 24,
                icon: const Icon(Icons.forward_10_rounded, color: AppColors.textPrimary),
                onPressed: () {
                  final newPos = ttsState.audioPosition + const Duration(seconds: 10);
                  ref.read(documentTtsNotifierProvider.notifier).seekAudio(newPos);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Playback Speed Chips
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Speed: ',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted),
              ),
              const SizedBox(width: 4),
              Wrap(
                spacing: 4,
                children: speeds.map((speed) {
                  final isSelected = ttsState.playbackRate == speed;
                  return InkWell(
                    onTap: () {
                      ref.read(documentTtsNotifierProvider.notifier).setPlaybackRate(speed);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
                      ),
                      child: Text(
                        '${speed}x',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
