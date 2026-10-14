import 'package:flutter/material.dart';

enum AppThemeMode {
  light,
  dark,
  system;

  ThemeMode toFlutterThemeMode() {
    switch (this) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  String get label {
    switch (this) {
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.system:
        return 'Light';
    }
  }
}

enum ReaderFontSize {
  small,
  medium,
  large;

  double get size {
    switch (this) {
      case ReaderFontSize.small:
        return 13.0;
      case ReaderFontSize.medium:
        return 15.0;
      case ReaderFontSize.large:
        return 18.0;
    }
  }

  String get label {
    switch (this) {
      case ReaderFontSize.small:
        return 'Small';
      case ReaderFontSize.medium:
        return 'Medium';
      case ReaderFontSize.large:
        return 'Large';
    }
  }
}

enum TranscriptDefaultView {
  full,
  follow;

  String get label {
    switch (this) {
      case TranscriptDefaultView.full:
        return 'Full Transcript';
      case TranscriptDefaultView.follow:
        return 'Follow Audio';
    }
  }
}

class SettingsModel {
  // 1. Reading & Display
  final AppThemeMode themeMode;
  final ReaderFontSize readerFontSize;

  // 2. Text to Speech
  final String defaultTtsLanguage; // 'english', 'marathi', 'hindi'
  final String defaultTtsVoiceEnglish;
  final String defaultTtsVoiceMarathi;
  final String defaultTtsVoiceHindi;

  // 3. Speech to Text
  final String defaultSttLanguage; // 'english', 'marathi', 'hindi'

  // 4. Transcript Synchronisation
  final TranscriptDefaultView defaultTranscriptView;
  final bool highlightCurrentWord;
  final bool autoScroll;
  final bool keepUpcomingWordsVisible;

  // 5. Audio Playback
  final double defaultPlaybackSpeed;
  final bool autoPlayTts;
  final bool stopAudioOnLeaveScreen;

  const SettingsModel({
    this.themeMode = AppThemeMode.light,
    this.readerFontSize = ReaderFontSize.medium,
    this.defaultTtsLanguage = 'english',
    this.defaultTtsVoiceEnglish = 'CwhRBWXzGAHq8TQ4Fs17',
    this.defaultTtsVoiceMarathi = 'CwhRBWXzGAHq8TQ4Fs17',
    this.defaultTtsVoiceHindi = 'CwhRBWXzGAHq8TQ4Fs17',
    this.defaultSttLanguage = 'english',
    this.defaultTranscriptView = TranscriptDefaultView.full,
    this.highlightCurrentWord = true,
    this.autoScroll = true,
    this.keepUpcomingWordsVisible = false,
    this.defaultPlaybackSpeed = 1.0,
    this.autoPlayTts = false,
    this.stopAudioOnLeaveScreen = true,
  });

  String defaultVoiceForLanguage(String language) {
    final clean = language.toLowerCase().trim();
    if (clean == 'marathi' || clean == 'mr') {
      return defaultTtsVoiceMarathi;
    } else if (clean == 'hindi' || clean == 'hi') {
      return defaultTtsVoiceHindi;
    }
    return defaultTtsVoiceEnglish;
  }

  SettingsModel copyWith({
    AppThemeMode? themeMode,
    ReaderFontSize? readerFontSize,
    String? defaultTtsLanguage,
    String? defaultTtsVoiceEnglish,
    String? defaultTtsVoiceMarathi,
    String? defaultTtsVoiceHindi,
    String? defaultSttLanguage,
    TranscriptDefaultView? defaultTranscriptView,
    bool? highlightCurrentWord,
    bool? autoScroll,
    bool? keepUpcomingWordsVisible,
    double? defaultPlaybackSpeed,
    bool? autoPlayTts,
    bool? stopAudioOnLeaveScreen,
  }) {
    return SettingsModel(
      themeMode: themeMode ?? this.themeMode,
      readerFontSize: readerFontSize ?? this.readerFontSize,
      defaultTtsLanguage: defaultTtsLanguage ?? this.defaultTtsLanguage,
      defaultTtsVoiceEnglish: defaultTtsVoiceEnglish ?? this.defaultTtsVoiceEnglish,
      defaultTtsVoiceMarathi: defaultTtsVoiceMarathi ?? this.defaultTtsVoiceMarathi,
      defaultTtsVoiceHindi: defaultTtsVoiceHindi ?? this.defaultTtsVoiceHindi,
      defaultSttLanguage: defaultSttLanguage ?? this.defaultSttLanguage,
      defaultTranscriptView: defaultTranscriptView ?? this.defaultTranscriptView,
      highlightCurrentWord: highlightCurrentWord ?? this.highlightCurrentWord,
      autoScroll: autoScroll ?? this.autoScroll,
      keepUpcomingWordsVisible: keepUpcomingWordsVisible ?? this.keepUpcomingWordsVisible,
      defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
      autoPlayTts: autoPlayTts ?? this.autoPlayTts,
      stopAudioOnLeaveScreen: stopAudioOnLeaveScreen ?? this.stopAudioOnLeaveScreen,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeMode': themeMode.name,
      'readerFontSize': readerFontSize.name,
      'defaultTtsLanguage': defaultTtsLanguage,
      'defaultTtsVoiceEnglish': defaultTtsVoiceEnglish,
      'defaultTtsVoiceMarathi': defaultTtsVoiceMarathi,
      'defaultTtsVoiceHindi': defaultTtsVoiceHindi,
      'defaultSttLanguage': defaultSttLanguage,
      'defaultTranscriptView': defaultTranscriptView.name,
      'highlightCurrentWord': highlightCurrentWord,
      'autoScroll': autoScroll,
      'keepUpcomingWordsVisible': keepUpcomingWordsVisible,
      'defaultPlaybackSpeed': defaultPlaybackSpeed,
      'autoPlayTts': autoPlayTts,
      'stopAudioOnLeaveScreen': stopAudioOnLeaveScreen,
    };
  }

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    AppThemeMode parseTheme(dynamic val) {
      if (val == 'light') return AppThemeMode.light;
      if (val == 'dark') return AppThemeMode.dark;
      return AppThemeMode.system;
    }

    ReaderFontSize parseFontSize(dynamic val) {
      if (val == 'small') return ReaderFontSize.small;
      if (val == 'large') return ReaderFontSize.large;
      return ReaderFontSize.medium;
    }

    TranscriptDefaultView parseView(dynamic val) {
      if (val == 'follow') return TranscriptDefaultView.follow;
      return TranscriptDefaultView.full;
    }

    return SettingsModel(
      themeMode: parseTheme(json['themeMode']),
      readerFontSize: parseFontSize(json['readerFontSize']),
      defaultTtsLanguage: json['defaultTtsLanguage'] as String? ?? 'english',
      defaultTtsVoiceEnglish: json['defaultTtsVoiceEnglish'] as String? ?? 'CwhRBWXzGAHq8TQ4Fs17',
      defaultTtsVoiceMarathi: json['defaultTtsVoiceMarathi'] as String? ?? 'CwhRBWXzGAHq8TQ4Fs17',
      defaultTtsVoiceHindi: json['defaultTtsVoiceHindi'] as String? ?? 'CwhRBWXzGAHq8TQ4Fs17',
      defaultSttLanguage: json['defaultSttLanguage'] as String? ?? 'english',
      defaultTranscriptView: parseView(json['defaultTranscriptView']),
      highlightCurrentWord: json['highlightCurrentWord'] as bool? ?? true,
      autoScroll: json['autoScroll'] as bool? ?? true,
      keepUpcomingWordsVisible: json['keepUpcomingWordsVisible'] as bool? ?? false,
      defaultPlaybackSpeed: (json['defaultPlaybackSpeed'] as num?)?.toDouble() ?? 1.0,
      autoPlayTts: json['autoPlayTts'] as bool? ?? false,
      stopAudioOnLeaveScreen: json['stopAudioOnLeaveScreen'] as bool? ?? true,
    );
  }
}
