import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../document_tts/domain/voice_model.dart';
import '../../../document_tts/presentation/providers/document_tts_provider.dart';
import '../../domain/settings_model.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Widget _buildGroupCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : AppColors.border;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2E2452) : AppColors.lavenderSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: isDark ? const Color(0xFFC4B5FD) : AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: borderColor),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required BuildContext context,
    required String label,
    required String description,
    required Widget control,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              control,
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final ttsState = ref.watch(documentTtsNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final allVoices = ttsState.voices.isNotEmpty
        ? ttsState.voices
        : VoiceModel.defaultVoices();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ==========================================
          // 1. READING & DISPLAY
          // ==========================================
          _buildGroupCard(
            context: context,
            title: '1. Reading & Display',
            icon: Icons.palette_outlined,
            children: [
              _buildSettingTile(
                context: context,
                label: 'Appearance',
                description: 'Light or dark theme',
                control: SegmentedButton<AppThemeMode>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: AppThemeMode.light, label: Text('Light', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: AppThemeMode.dark, label: Text('Dark', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {
                    settings.themeMode == AppThemeMode.dark ? AppThemeMode.dark : AppThemeMode.light,
                  },
                  onSelectionChanged: (val) {
                    if (val.isNotEmpty) {
                      settingsNotifier.updateThemeMode(val.first);
                    }
                  },
                ),
              ),
              const Divider(height: 16),
              _buildSettingTile(
                context: context,
                label: 'Reader Text Size',
                description: 'Adjusts document & transcript viewers',
                control: SegmentedButton<ReaderFontSize>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: ReaderFontSize.small, label: Text('Small', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: ReaderFontSize.medium, label: Text('Med', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: ReaderFontSize.large, label: Text('Large', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {settings.readerFontSize},
                  onSelectionChanged: (val) {
                    if (val.isNotEmpty) {
                      settingsNotifier.updateReaderFontSize(val.first);
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              // Reader Text Size Preview Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? const Color(0xFF334155) : AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PREVIEW (${settings.readerFontSize.label} - ${settings.readerFontSize.size.toInt()} pt)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF94A3B8) : AppColors.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Readora gives voice to your documents with natural speech and synchronised reading.',
                      style: TextStyle(
                        fontSize: settings.readerFontSize.size,
                        color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ==========================================
          // 2. TEXT TO SPEECH
          // ==========================================
          _buildGroupCard(
            context: context,
            title: '2. Text to Speech',
            icon: Icons.record_voice_over_outlined,
            children: [
              _buildSettingTile(
                context: context,
                label: 'Default Language',
                description: 'Initial language for new speech sessions',
                control: DropdownButton<String>(
                  value: settings.defaultTtsLanguage,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                  ),
                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  items: const [
                    DropdownMenuItem(value: 'english', child: Text('English')),
                    DropdownMenuItem(value: 'marathi', child: Text('Marathi (मराठी)')),
                    DropdownMenuItem(value: 'hindi', child: Text('Hindi (हिन्दी)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      settingsNotifier.updateDefaultTtsLanguage(val);
                      final targetVoice = settings.copyWith(defaultTtsLanguage: val).defaultVoiceForLanguage(val);
                      ref.read(documentTtsNotifierProvider.notifier).setSelectedLanguage(val, voiceId: targetVoice);
                    }
                  },
                ),
              ),
              const Divider(height: 16),
              _buildSettingTile(
                context: context,
                label: 'Default English Voice',
                description: 'Neural voice for English TTS',
                control: SizedBox(
                  width: 170,
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: allVoices.any((v) => v.voiceId == settings.defaultTtsVoiceEnglish)
                        ? settings.defaultTtsVoiceEnglish
                        : allVoices.first.voiceId,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                    ),
                    dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    items: allVoices.map((v) {
                      return DropdownMenuItem<String>(
                        value: v.voiceId,
                        child: Text(v.name, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        settingsNotifier.updateDefaultTtsVoiceEnglish(val);
                        final curLang = ref.read(documentTtsNotifierProvider).selectedLanguage;
                        if (curLang == 'english' || curLang == 'en' || settings.defaultTtsLanguage == 'english') {
                          ref.read(documentTtsNotifierProvider.notifier).setSelectedVoice(val);
                        }
                      }
                    },
                  ),
                ),
              ),
              const Divider(height: 16),
              _buildSettingTile(
                context: context,
                label: 'Default Marathi Voice',
                description: 'Neural voice for Marathi TTS',
                control: SizedBox(
                  width: 170,
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: allVoices.any((v) => v.voiceId == settings.defaultTtsVoiceMarathi)
                        ? settings.defaultTtsVoiceMarathi
                        : allVoices.first.voiceId,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                    ),
                    dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    items: allVoices.map((v) {
                      return DropdownMenuItem<String>(
                        value: v.voiceId,
                        child: Text(v.name, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        settingsNotifier.updateDefaultTtsVoiceMarathi(val);
                        final curLang = ref.read(documentTtsNotifierProvider).selectedLanguage;
                        if (curLang == 'marathi' || curLang == 'mr' || settings.defaultTtsLanguage == 'marathi') {
                          ref.read(documentTtsNotifierProvider.notifier).setSelectedVoice(val);
                        }
                      }
                    },
                  ),
                ),
              ),
              const Divider(height: 16),
              _buildSettingTile(
                context: context,
                label: 'Default Hindi Voice',
                description: 'Neural voice for Hindi TTS',
                control: SizedBox(
                  width: 170,
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: allVoices.any((v) => v.voiceId == settings.defaultTtsVoiceHindi)
                        ? settings.defaultTtsVoiceHindi
                        : allVoices.first.voiceId,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                    ),
                    dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    items: allVoices.map((v) {
                      return DropdownMenuItem<String>(
                        value: v.voiceId,
                        child: Text(v.name, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        settingsNotifier.updateDefaultTtsVoiceHindi(val);
                        final curLang = ref.read(documentTtsNotifierProvider).selectedLanguage;
                        if (curLang == 'hindi' || curLang == 'hi' || settings.defaultTtsLanguage == 'hindi') {
                          ref.read(documentTtsNotifierProvider.notifier).setSelectedVoice(val);
                        }
                      }
                    },
                  ),
                ),
              ),
            ],
          ),

          // ==========================================
          // 3. SPEECH TO TEXT
          // ==========================================
          _buildGroupCard(
            context: context,
            title: '3. Speech to Text',
            icon: Icons.graphic_eq_rounded,
            children: [
              _buildSettingTile(
                context: context,
                label: 'Default STT Language',
                description: 'Independent from TTS language',
                control: DropdownButton<String>(
                  value: settings.defaultSttLanguage,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFF8FAFC) : AppColors.textPrimary,
                  ),
                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  items: const [
                    DropdownMenuItem(value: 'english', child: Text('English')),
                    DropdownMenuItem(value: 'marathi', child: Text('Marathi (मराठी)')),
                    DropdownMenuItem(value: 'hindi', child: Text('Hindi (हिन्दी)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      settingsNotifier.updateDefaultSttLanguage(val);
                      ref.read(documentTtsNotifierProvider.notifier).setSelectedSttLanguage(val);
                    }
                  },
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'English uses backend speech transcription; Marathi and Hindi use local Whisper on-device processing.',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: isDark ? const Color(0xFF94A3B8) : AppColors.textMuted,
                ),
              ),
            ],
          ),

          // ==========================================
          // 4. TRANSCRIPT SYNCHRONISATION
          // ==========================================
          _buildGroupCard(
            context: context,
            title: '4. Transcript Synchronisation',
            icon: Icons.sync_rounded,
            children: [
              _buildSettingTile(
                context: context,
                label: 'Default View',
                description: 'Full text or audio synchronised mode',
                control: SegmentedButton<TranscriptDefaultView>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: TranscriptDefaultView.full, label: Text('Full', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: TranscriptDefaultView.follow, label: Text('Follow', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {settings.defaultTranscriptView},
                  onSelectionChanged: (val) {
                    if (val.isNotEmpty) {
                      settingsNotifier.updateDefaultTranscriptView(val.first);
                    }
                  },
                ),
              ),
              const Divider(height: 16),
              _buildSettingTile(
                context: context,
                label: 'Highlight Current Word',
                description: 'Visually highlight active spoken word',
                control: Switch(
                  value: settings.highlightCurrentWord,
                  onChanged: (val) => settingsNotifier.updateHighlightCurrentWord(val),
                ),
              ),
              const Divider(height: 16),
              _buildSettingTile(
                context: context,
                label: 'Auto-scroll with Audio',
                description: 'Keep spoken text centered in viewport',
                control: Switch(
                  value: settings.autoScroll,
                  onChanged: (val) => settingsNotifier.updateAutoScroll(val),
                ),
              ),
              const Divider(height: 16),
              _buildSettingTile(
                context: context,
                label: 'Keep Upcoming Words Visible',
                description: 'Show full text instead of progressive reveal',
                control: Switch(
                  value: settings.keepUpcomingWordsVisible,
                  onChanged: (val) => settingsNotifier.updateKeepUpcomingWordsVisible(val),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
