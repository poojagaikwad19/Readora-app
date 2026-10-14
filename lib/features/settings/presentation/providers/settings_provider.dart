import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/storage_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/settings_model.dart';

class SettingsNotifier extends StateNotifier<SettingsModel> {
  final StorageService _storageService;

  SettingsNotifier(this._storageService) : super(const SettingsModel(themeMode: AppThemeMode.light)) {
    _loadSettings();
  }

  void _loadSettings([String? userId]) {
    final data = _storageService.getSettings(userId);
    if (data != null) {
      final parsed = SettingsModel.fromJson(data);
      // Migrate old saved Auto/System preference once to the effective device appearance
      if (data['themeMode'] == 'system' || parsed.themeMode == AppThemeMode.system) {
        final platformBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
        final migratedMode = platformBrightness == Brightness.dark ? AppThemeMode.dark : AppThemeMode.light;
        state = parsed.copyWith(themeMode: migratedMode);
        _persist();
      } else {
        state = parsed;
      }
    } else {
      state = const SettingsModel(themeMode: AppThemeMode.light);
    }
  }

  void reloadSettingsForUser([String? userId]) {
    _loadSettings(userId);
  }

  Future<void> _persist() async {
    await _storageService.saveSettings(state.toJson());
  }

  // 1. Reading & Display
  Future<void> updateThemeMode(AppThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _persist();
  }

  Future<void> updateReaderFontSize(ReaderFontSize size) async {
    state = state.copyWith(readerFontSize: size);
    await _persist();
  }

  // 2. Text to Speech
  Future<void> updateDefaultTtsLanguage(String lang) async {
    state = state.copyWith(defaultTtsLanguage: lang);
    await _persist();
  }

  Future<void> updateDefaultTtsVoiceEnglish(String voiceId) async {
    state = state.copyWith(defaultTtsVoiceEnglish: voiceId);
    await _persist();
  }

  Future<void> updateDefaultTtsVoiceMarathi(String voiceId) async {
    state = state.copyWith(defaultTtsVoiceMarathi: voiceId);
    await _persist();
  }

  Future<void> updateDefaultTtsVoiceHindi(String voiceId) async {
    state = state.copyWith(defaultTtsVoiceHindi: voiceId);
    await _persist();
  }

  // 3. Speech to Text
  Future<void> updateDefaultSttLanguage(String lang) async {
    state = state.copyWith(defaultSttLanguage: lang);
    await _persist();
  }

  // 4. Transcript Synchronisation
  Future<void> updateDefaultTranscriptView(TranscriptDefaultView view) async {
    state = state.copyWith(defaultTranscriptView: view);
    await _persist();
  }

  Future<void> updateHighlightCurrentWord(bool value) async {
    state = state.copyWith(highlightCurrentWord: value);
    await _persist();
  }

  Future<void> updateAutoScroll(bool value) async {
    state = state.copyWith(autoScroll: value);
    await _persist();
  }

  Future<void> updateKeepUpcomingWordsVisible(bool value) async {
    state = state.copyWith(keepUpcomingWordsVisible: value);
    await _persist();
  }

  // 5. Audio Playback
  Future<void> updateDefaultPlaybackSpeed(double speed) async {
    state = state.copyWith(defaultPlaybackSpeed: speed);
    await _persist();
  }

  Future<void> updateAutoPlayTts(bool value) async {
    state = state.copyWith(autoPlayTts: value);
    await _persist();
  }

  Future<void> updateStopAudioOnLeaveScreen(bool value) async {
    state = state.copyWith(stopAudioOnLeaveScreen: value);
    await _persist();
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsModel>((ref) {
  final storageService = ref.watch(storageServiceProvider);
  return SettingsNotifier(storageService);
});
