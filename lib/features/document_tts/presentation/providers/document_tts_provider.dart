import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/constants/api_endpoints.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../core/services/local_whisper_service.dart';
import '../../data/document_tts_repository.dart';
import '../../domain/document_model.dart';
import '../../domain/timed_word_model.dart';
import '../../domain/tts_response_model.dart';
import '../../domain/voice_model.dart';
import '../../../downloads/domain/download_model.dart';
import '../../../downloads/presentation/providers/downloads_provider.dart';
import '../../../settings/domain/settings_model.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import 'package:readora_audio_stt/readora_audio_stt.dart' as readora_stt hide TimedWord;

// Repository Provider
final documentTtsRepositoryProvider = Provider<DocumentTtsRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return DocumentTtsRepository(apiClient);
});

// Tab Source Enum
enum TtsInputSource {
  document,
  text,
}

// Per-tab TTS & Playback State
class TtsTabState {
  final TtsResponseModel? response;
  final bool isGenerating;
  final PlayerState playerState;
  final Duration position;
  final Duration duration;
  final bool isProgressive;
  final int progressiveCurrentChunk;
  final int progressiveTotalChunks;
  final int progressiveCompletedChunks;
  final String? completeAudioUrl;
  final String? completeFilename;
  final bool isBufferingNextChunk;

  const TtsTabState({
    this.response,
    this.isGenerating = false,
    this.playerState = PlayerState.stopped,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isProgressive = false,
    this.progressiveCurrentChunk = 1,
    this.progressiveTotalChunks = 1,
    this.progressiveCompletedChunks = 0,
    this.completeAudioUrl,
    this.completeFilename,
    this.isBufferingNextChunk = false,
  });

  TtsTabState copyWith({
    TtsResponseModel? response,
    bool clearResponse = false,
    bool? isGenerating,
    PlayerState? playerState,
    Duration? position,
    Duration? duration,
    bool? isProgressive,
    int? progressiveCurrentChunk,
    int? progressiveTotalChunks,
    int? progressiveCompletedChunks,
    String? completeAudioUrl,
    String? completeFilename,
    bool? isBufferingNextChunk,
  }) {
    return TtsTabState(
      response: clearResponse ? null : (response ?? this.response),
      isGenerating: isGenerating ?? this.isGenerating,
      playerState: playerState ?? this.playerState,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isProgressive: isProgressive ?? this.isProgressive,
      progressiveCurrentChunk: progressiveCurrentChunk ?? this.progressiveCurrentChunk,
      progressiveTotalChunks: progressiveTotalChunks ?? this.progressiveTotalChunks,
      progressiveCompletedChunks: progressiveCompletedChunks ?? this.progressiveCompletedChunks,
      completeAudioUrl: completeAudioUrl ?? this.completeAudioUrl,
      completeFilename: completeFilename ?? this.completeFilename,
      isBufferingNextChunk: isBufferingNextChunk ?? this.isBufferingNextChunk,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsTabState &&
          runtimeType == other.runtimeType &&
          response == other.response &&
          isGenerating == other.isGenerating &&
          playerState == other.playerState &&
          position == other.position &&
          duration == other.duration &&
          isProgressive == other.isProgressive &&
          progressiveCurrentChunk == other.progressiveCurrentChunk &&
          progressiveTotalChunks == other.progressiveTotalChunks &&
          progressiveCompletedChunks == other.progressiveCompletedChunks &&
          completeAudioUrl == other.completeAudioUrl &&
          completeFilename == other.completeFilename &&
          isBufferingNextChunk == other.isBufferingNextChunk;

  @override
  int get hashCode => Object.hash(
        response,
        isGenerating,
        playerState,
        position,
        duration,
        isProgressive,
        progressiveCurrentChunk,
        progressiveTotalChunks,
        progressiveCompletedChunks,
        completeAudioUrl,
        completeFilename,
        isBufferingNextChunk,
      );
}

// State Class
class DocumentTtsState {
  final bool isExtracting;
  final bool isLoadingVoices;
  final bool isLoadingDocuments;
  final List<DocumentModel> userDocuments;
  final DocumentModel? activeDocument;
  final List<VoiceModel> voices;
  final String selectedVoiceId;
  final String selectedLanguage; // english, marathi, hindi for TTS
  final String selectedSttLanguage; // english, marathi, hindi for STT
  final double playbackRate;
  final bool isMuted;
  final double volume; // 0.0 to 1.0
  final bool isDownloadingAudio;
  final bool isPlayingOriginalAudio;
  final String? originalAudioPath;
  final String? errorMessage;
  final String? successMessage;

  // Independent per-tab state
  final TtsInputSource? _activeTtsTab;
  TtsInputSource get activeTtsTab => _activeTtsTab ?? TtsInputSource.document;

  final TtsTabState? _documentTabState;
  TtsTabState get documentTabState => _documentTabState ?? const TtsTabState();

  final TtsTabState? _textTabState;
  TtsTabState get textTabState => _textTabState ?? const TtsTabState();

  final TtsInputSource? playingSource;

  DocumentTtsState({
    this.isExtracting = false,
    bool? isGeneratingSpeech,
    this.isLoadingVoices = false,
    this.isLoadingDocuments = false,
    this.userDocuments = const [],
    this.activeDocument,
    List<VoiceModel>? voices,
    this.selectedVoiceId = 'CwhRBWXzGAHq8TQ4Fs17',
    this.selectedLanguage = 'english',
    this.selectedSttLanguage = 'english',
    TtsResponseModel? currentTtsResponse,
    PlayerState? playerState,
    Duration? audioPosition,
    Duration? audioDuration,
    this.playbackRate = 1.0,
    this.isMuted = false,
    this.volume = 1.0,
    this.isDownloadingAudio = false,
    bool? isProgressive,
    int? progressiveCurrentChunk,
    int? progressiveTotalChunks,
    int? progressiveCompletedChunks,
    String? completeAudioUrl,
    String? completeFilename,
    bool? isBufferingNextChunk,
    this.isPlayingOriginalAudio = false,
    this.originalAudioPath,
    this.errorMessage,
    this.successMessage,
    TtsInputSource? activeTtsTab = TtsInputSource.document,
    TtsTabState? documentTabState,
    TtsTabState? textTabState,
    this.playingSource,
  })  : voices = voices ?? VoiceModel.defaultVoices(),
        _activeTtsTab = activeTtsTab ?? TtsInputSource.document,
        _documentTabState = documentTabState ??
            TtsTabState(
              response: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.document ? currentTtsResponse : null,
              isGenerating: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.document ? (isGeneratingSpeech ?? false) : false,
              playerState: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.document ? (playerState ?? PlayerState.stopped) : PlayerState.stopped,
              position: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.document ? (audioPosition ?? Duration.zero) : Duration.zero,
              duration: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.document ? (audioDuration ?? Duration.zero) : Duration.zero,
              isProgressive: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.document ? (isProgressive ?? false) : false,
              progressiveCurrentChunk: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.document ? (progressiveCurrentChunk ?? 1) : 1,
              progressiveTotalChunks: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.document ? (progressiveTotalChunks ?? 1) : 1,
              progressiveCompletedChunks: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.document ? (progressiveCompletedChunks ?? 0) : 0,
              completeAudioUrl: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.document ? completeAudioUrl : null,
              completeFilename: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.document ? completeFilename : null,
              isBufferingNextChunk: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.document ? (isBufferingNextChunk ?? false) : false,
            ),
        _textTabState = textTabState ??
            TtsTabState(
              response: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.text ? currentTtsResponse : null,
              isGenerating: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.text ? (isGeneratingSpeech ?? false) : false,
              playerState: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.text ? (playerState ?? PlayerState.stopped) : PlayerState.stopped,
              position: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.text ? (audioPosition ?? Duration.zero) : Duration.zero,
              duration: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.text ? (audioDuration ?? Duration.zero) : Duration.zero,
              isProgressive: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.text ? (isProgressive ?? false) : false,
              progressiveCurrentChunk: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.text ? (progressiveCurrentChunk ?? 1) : 1,
              progressiveTotalChunks: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.text ? (progressiveTotalChunks ?? 1) : 1,
              progressiveCompletedChunks: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.text ? (progressiveCompletedChunks ?? 0) : 0,
              completeAudioUrl: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.text ? completeAudioUrl : null,
              completeFilename: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.text ? completeFilename : null,
              isBufferingNextChunk: (activeTtsTab ?? TtsInputSource.document) == TtsInputSource.text ? (isBufferingNextChunk ?? false) : false,
            );

  // Dynamic getters reflecting the active tab
  TtsResponseModel? get currentTtsResponse =>
      activeTtsTab == TtsInputSource.text ? textTabState.response : documentTabState.response;

  TtsResponseModel? get documentTtsResponse => documentTabState.response;
  TtsResponseModel? get textTtsResponse => textTabState.response;

  bool get isGeneratingSpeech =>
      activeTtsTab == TtsInputSource.text ? textTabState.isGenerating : documentTabState.isGenerating;

  bool get isGeneratingDocumentSpeech => documentTabState.isGenerating;
  bool get isGeneratingTextSpeech => textTabState.isGenerating;

  PlayerState get playerState =>
      activeTtsTab == TtsInputSource.text ? textTabState.playerState : documentTabState.playerState;

  Duration get audioPosition =>
      activeTtsTab == TtsInputSource.text ? textTabState.position : documentTabState.position;

  Duration get audioDuration =>
      activeTtsTab == TtsInputSource.text ? textTabState.duration : documentTabState.duration;

  bool get isProgressive =>
      activeTtsTab == TtsInputSource.text ? textTabState.isProgressive : documentTabState.isProgressive;

  int get progressiveCurrentChunk =>
      activeTtsTab == TtsInputSource.text ? textTabState.progressiveCurrentChunk : documentTabState.progressiveCurrentChunk;

  int get progressiveTotalChunks =>
      activeTtsTab == TtsInputSource.text ? textTabState.progressiveTotalChunks : documentTabState.progressiveTotalChunks;

  int get progressiveCompletedChunks =>
      activeTtsTab == TtsInputSource.text ? textTabState.progressiveCompletedChunks : documentTabState.progressiveCompletedChunks;

  String? get completeAudioUrl =>
      activeTtsTab == TtsInputSource.text ? textTabState.completeAudioUrl : documentTabState.completeAudioUrl;

  String? get completeFilename =>
      activeTtsTab == TtsInputSource.text ? textTabState.completeFilename : documentTabState.completeFilename;

  bool get isBufferingNextChunk =>
      activeTtsTab == TtsInputSource.text ? textTabState.isBufferingNextChunk : documentTabState.isBufferingNextChunk;

  DocumentTtsState copyWith({
    bool? isExtracting,
    bool? isGeneratingSpeech,
    bool? isLoadingVoices,
    bool? isLoadingDocuments,
    List<DocumentModel>? userDocuments,
    DocumentModel? activeDocument,
    List<VoiceModel>? voices,
    String? selectedVoiceId,
    String? selectedLanguage,
    String? selectedSttLanguage,
    TtsResponseModel? currentTtsResponse,
    bool clearTtsResponse = false,
    bool clearAllTtsResponses = false,
    PlayerState? playerState,
    Duration? audioPosition,
    Duration? audioDuration,
    double? playbackRate,
    bool? isMuted,
    double? volume,
    bool? isDownloadingAudio,
    bool? isProgressive,
    int? progressiveCurrentChunk,
    int? progressiveTotalChunks,
    int? progressiveCompletedChunks,
    String? completeAudioUrl,
    String? completeFilename,
    bool? isBufferingNextChunk,
    bool? isPlayingOriginalAudio,
    String? originalAudioPath,
    bool clearOriginalAudio = false,
    String? errorMessage,
    String? successMessage,
    TtsInputSource? activeTtsTab,
    TtsTabState? documentTabState,
    TtsTabState? textTabState,
    TtsInputSource? playingSource,
    bool clearPlayingSource = false,
  }) {
    final effectiveActiveTab = activeTtsTab ?? this.activeTtsTab;

    TtsTabState newDocTabState = documentTabState ?? this.documentTabState;
    TtsTabState newTextTabState = textTabState ?? this.textTabState;

    if (clearAllTtsResponses) {
      newDocTabState = newDocTabState.copyWith(clearResponse: true);
      newTextTabState = newTextTabState.copyWith(clearResponse: true);
    } else if (clearTtsResponse) {
      if (effectiveActiveTab == TtsInputSource.document) {
        newDocTabState = newDocTabState.copyWith(clearResponse: true);
      } else {
        newTextTabState = newTextTabState.copyWith(clearResponse: true);
      }
    } else if (currentTtsResponse != null) {
      if (effectiveActiveTab == TtsInputSource.document) {
        newDocTabState = newDocTabState.copyWith(response: currentTtsResponse);
      } else {
        newTextTabState = newTextTabState.copyWith(response: currentTtsResponse);
      }
    }

    if (isGeneratingSpeech != null) {
      if (effectiveActiveTab == TtsInputSource.document) {
        newDocTabState = newDocTabState.copyWith(isGenerating: isGeneratingSpeech);
      } else {
        newTextTabState = newTextTabState.copyWith(isGenerating: isGeneratingSpeech);
      }
    }

    if (playerState != null) {
      final target = playingSource ?? this.playingSource ?? effectiveActiveTab;
      if (target == TtsInputSource.document) {
        newDocTabState = newDocTabState.copyWith(playerState: playerState);
      } else {
        newTextTabState = newTextTabState.copyWith(playerState: playerState);
      }
    }

    if (audioPosition != null) {
      final target = playingSource ?? this.playingSource ?? effectiveActiveTab;
      if (target == TtsInputSource.document) {
        newDocTabState = newDocTabState.copyWith(position: audioPosition);
      } else {
        newTextTabState = newTextTabState.copyWith(position: audioPosition);
      }
    }

    if (audioDuration != null) {
      final target = playingSource ?? this.playingSource ?? effectiveActiveTab;
      if (target == TtsInputSource.document) {
        newDocTabState = newDocTabState.copyWith(duration: audioDuration);
      } else {
        newTextTabState = newTextTabState.copyWith(duration: audioDuration);
      }
    }

    if (isProgressive != null ||
        progressiveCurrentChunk != null ||
        progressiveTotalChunks != null ||
        progressiveCompletedChunks != null ||
        completeAudioUrl != null ||
        completeFilename != null ||
        isBufferingNextChunk != null) {
      if (effectiveActiveTab == TtsInputSource.document) {
        newDocTabState = newDocTabState.copyWith(
          isProgressive: isProgressive,
          progressiveCurrentChunk: progressiveCurrentChunk,
          progressiveTotalChunks: progressiveTotalChunks,
          progressiveCompletedChunks: progressiveCompletedChunks,
          completeAudioUrl: completeAudioUrl,
          completeFilename: completeFilename,
          isBufferingNextChunk: isBufferingNextChunk,
        );
      } else {
        newTextTabState = newTextTabState.copyWith(
          isProgressive: isProgressive,
          progressiveCurrentChunk: progressiveCurrentChunk,
          progressiveTotalChunks: progressiveTotalChunks,
          progressiveCompletedChunks: progressiveCompletedChunks,
          completeAudioUrl: completeAudioUrl,
          completeFilename: completeFilename,
          isBufferingNextChunk: isBufferingNextChunk,
        );
      }
    }

    return DocumentTtsState(
      isExtracting: isExtracting ?? this.isExtracting,
      isLoadingVoices: isLoadingVoices ?? this.isLoadingVoices,
      isLoadingDocuments: isLoadingDocuments ?? this.isLoadingDocuments,
      userDocuments: userDocuments ?? this.userDocuments,
      activeDocument: activeDocument ?? this.activeDocument,
      voices: voices ?? this.voices,
      selectedVoiceId: selectedVoiceId ?? this.selectedVoiceId,
      selectedLanguage: selectedLanguage ?? this.selectedLanguage,
      selectedSttLanguage: selectedSttLanguage ?? this.selectedSttLanguage,
      playbackRate: playbackRate ?? this.playbackRate,
      isMuted: isMuted ?? this.isMuted,
      volume: volume ?? this.volume,
      isDownloadingAudio: isDownloadingAudio ?? this.isDownloadingAudio,
      isPlayingOriginalAudio: isPlayingOriginalAudio ?? this.isPlayingOriginalAudio,
      originalAudioPath: clearOriginalAudio ? null : (originalAudioPath ?? this.originalAudioPath),
      errorMessage: errorMessage,
      successMessage: successMessage,
      activeTtsTab: effectiveActiveTab,
      documentTabState: newDocTabState,
      textTabState: newTextTabState,
      playingSource: clearPlayingSource ? null : (playingSource ?? this.playingSource),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentTtsState &&
          runtimeType == other.runtimeType &&
          isExtracting == other.isExtracting &&
          isLoadingVoices == other.isLoadingVoices &&
          isLoadingDocuments == other.isLoadingDocuments &&
          listEquals(userDocuments, other.userDocuments) &&
          activeDocument == other.activeDocument &&
          listEquals(voices, other.voices) &&
          selectedVoiceId == other.selectedVoiceId &&
          selectedLanguage == other.selectedLanguage &&
          selectedSttLanguage == other.selectedSttLanguage &&
          playbackRate == other.playbackRate &&
          isMuted == other.isMuted &&
          volume == other.volume &&
          isDownloadingAudio == other.isDownloadingAudio &&
          isPlayingOriginalAudio == other.isPlayingOriginalAudio &&
          originalAudioPath == other.originalAudioPath &&
          errorMessage == other.errorMessage &&
          successMessage == other.successMessage &&
          activeTtsTab == other.activeTtsTab &&
          documentTabState == other.documentTabState &&
          textTabState == other.textTabState &&
          playingSource == other.playingSource;

  @override
  int get hashCode => Object.hashAll([
        isExtracting,
        isLoadingVoices,
        isLoadingDocuments,
        userDocuments,
        activeDocument,
        voices,
        selectedVoiceId,
        selectedLanguage,
        selectedSttLanguage,
        playbackRate,
        isMuted,
        volume,
        isDownloadingAudio,
        isPlayingOriginalAudio,
        originalAudioPath,
        errorMessage,
        successMessage,
        activeTtsTab,
        documentTabState,
        textTabState,
        playingSource,
      ]);
}

// State Notifier
class DocumentTtsNotifier extends StateNotifier<DocumentTtsState> {
  final DocumentTtsRepository _repository;
  final StorageService _storageService;
  final Ref? _ref;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<TtsInputSource, String> _tabActiveSessionId = {
    TtsInputSource.document: '',
    TtsInputSource.text: '',
  };
  final Map<TtsInputSource, int> _tabRequestSeq = {
    TtsInputSource.document: 0,
    TtsInputSource.text: 0,
  };
  final Map<TtsInputSource, List<TtsResponseModel?>> _tabProgressiveAudioQueue = {
    TtsInputSource.document: [],
    TtsInputSource.text: [],
  };
  TtsInputSource? _playingSource;
  String _lastBaseUrl = '';
  final Set<String> _pendingDeletions = {};
  int _activeSttToken = 0;
  readora_stt.AudioFileSttService? _currentSttService;

  String? _activeUserId;
  int _sessionGeneration = 0;

  String get _activeSessionId => _tabActiveSessionId[state.activeTtsTab] ?? '';
  String? get activeUserId => _activeUserId;
  String get _currentUserId => _activeUserId ?? _storageService.getUser()['id'] ?? 'guest';

  DocumentTtsNotifier(this._repository, this._storageService, [this._ref]) : super(DocumentTtsState()) {
    _storageService.migrateLegacyHistoryDocsIfApplicable();
    _activeUserId = _storageService.getUser()['id'];
    _initAudioPlayer();
    _loadInitialLocalHistory();
    _applyInitialSettings();
    if (_ref != null) {
      _ref!.read(downloadsProvider.notifier).onBeforePlay = () {
        stopAudioAndClearQueue();
        stopOriginalAudio();
      };

      // Listen for authenticated user changes to enforce strict cross-account isolation
      _ref!.listen<AuthState>(authNotifierProvider, (previous, next) {
        final prevUserId = previous?.user?.id;
        final nextUserId = next.user?.id;
        if (prevUserId != nextUserId) {
          if (nextUserId == null) {
            clearUserData();
          } else {
            switchUser(nextUserId);
          }
        }
      });

      _ref!.listen<SettingsModel>(settingsProvider, (previous, next) {
        if (previous == null) {
          final defVoice = next.defaultVoiceForLanguage(next.defaultTtsLanguage);
          state = state.copyWith(
            selectedLanguage: next.defaultTtsLanguage,
            selectedVoiceId: defVoice,
            selectedSttLanguage: next.defaultSttLanguage,
          );
          return;
        }

        // 1. If default TTS language changed in settings:
        if (previous.defaultTtsLanguage != next.defaultTtsLanguage) {
          final defVoice = next.defaultVoiceForLanguage(next.defaultTtsLanguage);
          state = state.copyWith(
            selectedLanguage: next.defaultTtsLanguage,
            selectedVoiceId: defVoice,
          );
        }

        // 2. If English default voice changed in settings:
        if (previous.defaultTtsVoiceEnglish != next.defaultTtsVoiceEnglish) {
          if (state.selectedLanguage == 'english' || state.selectedLanguage == 'en' || next.defaultTtsLanguage == 'english') {
            state = state.copyWith(selectedVoiceId: next.defaultTtsVoiceEnglish);
          }
        }

        // 3. If Marathi default voice changed in settings:
        if (previous.defaultTtsVoiceMarathi != next.defaultTtsVoiceMarathi) {
          if (state.selectedLanguage == 'marathi' || state.selectedLanguage == 'mr' || next.defaultTtsLanguage == 'marathi') {
            state = state.copyWith(selectedVoiceId: next.defaultTtsVoiceMarathi);
          }
        }

        // 4. If Hindi default voice changed in settings:
        if (previous.defaultTtsVoiceHindi != next.defaultTtsVoiceHindi) {
          if (state.selectedLanguage == 'hindi' || state.selectedLanguage == 'hi' || next.defaultTtsLanguage == 'hindi') {
            state = state.copyWith(selectedVoiceId: next.defaultTtsVoiceHindi);
          }
        }

        // 5. If default STT language changed in settings:
        if (previous.defaultSttLanguage != next.defaultSttLanguage) {
          state = state.copyWith(selectedSttLanguage: next.defaultSttLanguage);
        }
      });
    }
  }

  void _applyInitialSettings() {
    try {
      if (_ref != null) {
        final settings = _ref!.read(settingsProvider);
        final defLang = settings.defaultTtsLanguage.toLowerCase().trim();
        final defVoice = settings.defaultVoiceForLanguage(defLang);
        final defStt = settings.defaultSttLanguage.toLowerCase().trim();
        state = state.copyWith(
          selectedLanguage: defLang,
          selectedVoiceId: defVoice,
          selectedSttLanguage: defStt,
        );
        return;
      }
      final settingsData = _storageService.getSettings();
      if (settingsData != null) {
        final parsed = SettingsModel.fromJson(settingsData);
        final defLang = parsed.defaultTtsLanguage.toLowerCase().trim();
        final defVoice = parsed.defaultVoiceForLanguage(defLang);
        final defStt = parsed.defaultSttLanguage.toLowerCase().trim();
        state = state.copyWith(
          selectedLanguage: defLang,
          selectedVoiceId: defVoice,
          selectedSttLanguage: defStt,
        );
      }
    } catch (_) {}
  }

  void _loadInitialLocalHistory() {
    try {
      final effectiveUserId = _activeUserId ?? _storageService.getUser()['id'] ?? 'guest';
      final excludedIds = _storageService.getExcludedHistoryIds(effectiveUserId);
      final localRaw = _storageService.getHistoryDocs(effectiveUserId);
      final localDocs = localRaw
          .map((e) => DocumentModel.fromJson(e))
          .where((d) => !excludedIds.contains(d.docId))
          .toList();
      _updateAndPersistDocuments(localDocs, effectiveUserId);
    } catch (_) {}
  }

  void _initAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((pState) {
      if (!mounted) return;
      if (state.isPlayingOriginalAudio) {
        state = state.copyWith(playerState: pState);
        return;
      }

      final source = _playingSource;
      if (source == null) {
        if (pState == PlayerState.stopped) {
          state = state.copyWith(
            documentTabState: state.documentTabState.copyWith(playerState: PlayerState.stopped),
            textTabState: state.textTabState.copyWith(playerState: PlayerState.stopped),
          );
        }
        return;
      }

      if (source == TtsInputSource.document) {
        state = state.copyWith(
          documentTabState: state.documentTabState.copyWith(playerState: pState),
        );
      } else {
        state = state.copyWith(
          textTabState: state.textTabState.copyWith(playerState: pState),
        );
      }
    });

    _audioPlayer.onPositionChanged.listen((pos) {
      if (!mounted) return;
      if (state.isPlayingOriginalAudio) {
        state = state.copyWith(audioPosition: pos);
        return;
      }

      final source = _playingSource;
      if (source == null) return;

      if (source == TtsInputSource.document) {
        state = state.copyWith(
          documentTabState: state.documentTabState.copyWith(position: pos),
        );
      } else {
        state = state.copyWith(
          textTabState: state.textTabState.copyWith(position: pos),
        );
      }
    });

    _audioPlayer.onDurationChanged.listen((dur) {
      if (!mounted) return;
      if (state.isPlayingOriginalAudio) {
        state = state.copyWith(audioDuration: dur);
        return;
      }

      final source = _playingSource;
      if (source == null) return;

      if (source == TtsInputSource.document) {
        state = state.copyWith(
          documentTabState: state.documentTabState.copyWith(duration: dur),
        );
      } else {
        state = state.copyWith(
          textTabState: state.textTabState.copyWith(duration: dur),
        );
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) async {
      if (!mounted) return;

      if (state.isPlayingOriginalAudio) {
        state = state.copyWith(
          playerState: PlayerState.completed,
          audioPosition: state.audioDuration,
          isBufferingNextChunk: false,
        );
        return;
      }

      final source = _playingSource;
      if (source == null) return;

      final tabState = source == TtsInputSource.document
          ? state.documentTabState
          : state.textTabState;

      final sessionId = _tabActiveSessionId[source] ?? '';

      // Guard: If session was invalidated or player was stopped, do NOT advance or restart playback
      if (sessionId.isEmpty || tabState.playerState == PlayerState.stopped) {
        final doneTab = tabState.copyWith(
          playerState: PlayerState.completed,
          position: Duration.zero,
          isBufferingNextChunk: false,
        );
        state = state.copyWith(
          documentTabState: source == TtsInputSource.document ? doneTab : null,
          textTabState: source == TtsInputSource.text ? doneTab : null,
        );
        return;
      }

      if (tabState.isProgressive && tabState.progressiveCurrentChunk < tabState.progressiveTotalChunks) {
        final nextIndex = tabState.progressiveCurrentChunk; // 0-based index of next chunk
        final nextChunkNumber = nextIndex + 1; // 1-based chunk number
        final queue = _tabProgressiveAudioQueue[source] ?? [];

        if (queue.length > nextIndex && queue[nextIndex] != null) {
          final nextChunk = queue[nextIndex]!;
          final wasPaused = (tabState.playerState == PlayerState.paused);

          final advTab = tabState.copyWith(
            progressiveCurrentChunk: nextChunkNumber,
            response: nextChunk,
            position: Duration.zero,
            isBufferingNextChunk: false,
          );

          state = state.copyWith(
            documentTabState: source == TtsInputSource.document ? advTab : null,
            textTabState: source == TtsInputSource.text ? advTab : null,
          );

          if (!wasPaused && sessionId.isNotEmpty && tabState.playerState != PlayerState.stopped) {
            await playAudio(nextChunk.audioUrl, _lastBaseUrl, source: source);
          }
          return;
        } else {
          // Next chunk is still buffering in the background
          final bufferTab = tabState.copyWith(
            progressiveCurrentChunk: nextChunkNumber,
            isBufferingNextChunk: true,
            playerState: PlayerState.completed,
          );
          state = state.copyWith(
            documentTabState: source == TtsInputSource.document ? bufferTab : null,
            textTabState: source == TtsInputSource.text ? bufferTab : null,
          );
          return;
        }
      }

      final completedTab = tabState.copyWith(
        playerState: PlayerState.completed,
        position: Duration.zero,
        isBufferingNextChunk: false,
      );
      state = state.copyWith(
        documentTabState: source == TtsInputSource.document ? completedTab : null,
        textTabState: source == TtsInputSource.text ? completedTab : null,
      );
    });
  }

  void _invalidateActiveSession([TtsInputSource? source]) {
    if (source != null) {
      _tabActiveSessionId[source] = '';
      _tabProgressiveAudioQueue[source] = [];
    } else {
      _tabActiveSessionId[TtsInputSource.document] = '';
      _tabActiveSessionId[TtsInputSource.text] = '';
      _tabProgressiveAudioQueue[TtsInputSource.document] = [];
      _tabProgressiveAudioQueue[TtsInputSource.text] = [];
    }
    _playingSource = null;
    _audioPlayer.stop();
  }

  /// Switches active TTS tab between Upload Document and Enter Text,
  /// immediately stopping any in-progress playback without auto-playing destination audio.
  Future<void> switchTtsTab(TtsInputSource newTab) async {
    if (state.activeTtsTab == newTab) return;

    _playingSource = null;
    state = state.copyWith(
      activeTtsTab: newTab,
      documentTabState: state.documentTabState.copyWith(
        playerState: PlayerState.stopped,
      ),
      textTabState: state.textTabState.copyWith(
        playerState: PlayerState.stopped,
      ),
      clearPlayingSource: true,
      isPlayingOriginalAudio: false,
    );

    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  @visibleForTesting
  void setPlayerStateForTesting(PlayerState pState, {TtsInputSource? source}) {
    final target = source ?? state.activeTtsTab;
    if (pState == PlayerState.playing) {
      _playingSource = target;
    } else if (pState == PlayerState.stopped && _playingSource == target) {
      _playingSource = null;
    }
    state = state.copyWith(
      documentTabState: target == TtsInputSource.document
          ? state.documentTabState.copyWith(playerState: pState)
          : null,
      textTabState: target == TtsInputSource.text
          ? state.textTabState.copyWith(playerState: pState)
          : null,
    );
  }

  /// Stops audio playback immediately and clears progressive queue for the active tab.
  Future<void> stopAudio() async {
    _playingSource = null;
    await _audioPlayer.stop();
    final stoppedTab = (state.activeTtsTab == TtsInputSource.document
            ? state.documentTabState
            : state.textTabState)
        .copyWith(
      playerState: PlayerState.stopped,
      position: Duration.zero,
      isProgressive: false,
      progressiveCurrentChunk: 1,
      progressiveTotalChunks: 1,
      progressiveCompletedChunks: 0,
      isBufferingNextChunk: false,
    );
    state = state.copyWith(
      documentTabState: state.activeTtsTab == TtsInputSource.document ? stoppedTab : null,
      textTabState: state.activeTtsTab == TtsInputSource.text ? stoppedTab : null,
      isPlayingOriginalAudio: false,
      clearPlayingSource: true,
    );
  }

  /// Cancels any active in-flight STT transcription and invalidates pending results
  void cancelStt() {
    _activeSttToken++;
    try {
      _currentSttService?.dispose();
    } catch (_) {}
    _currentSttService = null;
    _invalidateActiveSession();
    state = state.copyWith(
      isExtracting: false,
      errorMessage: null,
    );
  }

  /// Stops audio playback immediately, invalidates active sessions, and wipes all TTS responses.
  Future<void> stopAudioAndClearQueue() async {
    _activeSttToken++;
    try {
      _currentSttService?.dispose();
    } catch (_) {}
    _currentSttService = null;
    _invalidateActiveSession();
    _playingSource = null;
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    state = state.copyWith(
      clearAllTtsResponses: true,
      documentTabState: const TtsTabState(),
      textTabState: const TtsTabState(),
      clearPlayingSource: true,
      isPlayingOriginalAudio: false,
    );
  }

  /// Completely clears the previous account's in-memory history, dashboard items, transcripts,
  /// selected files, and playback state on logout or account teardown.
  Future<void> clearUserData() async {
    _sessionGeneration++;
    _activeSttToken++;
    try {
      _currentSttService?.dispose();
    } catch (_) {}
    _currentSttService = null;
    _invalidateActiveSession();
    _playingSource = null;
    try {
      await _audioPlayer.stop();
    } catch (_) {}

    _activeUserId = null;
    state = DocumentTtsState(
      isLoadingVoices: false,
      isLoadingDocuments: false,
      isExtracting: false,
      userDocuments: const [],
      activeDocument: null,
      originalAudioPath: null,
      isPlayingOriginalAudio: false,
      documentTabState: const TtsTabState(),
      textTabState: const TtsTabState(),
      playingSource: null,
    );
  }

  /// Explicitly switches active user context, stops previous playback, cancels in-flight operations,
  /// isolates local cached documents, and fetches the new user's remote records.
  Future<void> switchUser(String? newUserId) async {
    final currentGen = ++_sessionGeneration;
    _activeSttToken++;
    try {
      _currentSttService?.dispose();
    } catch (_) {}
    _currentSttService = null;
    _invalidateActiveSession();
    _playingSource = null;
    try {
      await _audioPlayer.stop();
    } catch (_) {}

    _activeUserId = newUserId;

    if (newUserId == null || newUserId.isEmpty) {
      await clearUserData();
      return;
    }

    // 1. Immediately scope to the new user's persistent local cache (never show old user's data)
    final localRaw = _storageService.getHistoryDocs(newUserId);
    final excludedIds = _storageService.getExcludedHistoryIds(newUserId);
    final localDocs = localRaw
        .map((e) => DocumentModel.fromJson(e))
        .where((d) => !excludedIds.contains(d.docId))
        .toList();

    state = DocumentTtsState(
      isLoadingVoices: false,
      isLoadingDocuments: true,
      isExtracting: false,
      userDocuments: localDocs,
      activeDocument: null,
      originalAudioPath: null,
      isPlayingOriginalAudio: false,
      documentTabState: const TtsTabState(),
      textTabState: const TtsTabState(),
      playingSource: null,
    );

    // 2. Fetch authenticated user's remote records
    await loadUserDocuments(newUserId, currentGen);
  }

  @visibleForTesting
  void setTtsResponseForTesting(TtsResponseModel? response, {TtsInputSource source = TtsInputSource.document}) {
    final updatedTab = (source == TtsInputSource.document
            ? state.documentTabState
            : state.textTabState)
        .copyWith(response: response);
    state = state.copyWith(
      documentTabState: source == TtsInputSource.document ? updatedTab : null,
      textTabState: source == TtsInputSource.text ? updatedTab : null,
    );
  }

  @override
  void dispose() {
    _invalidateActiveSession();
    _audioPlayer.dispose();
    super.dispose();
  }

  void setSelectedLanguage(String lang, {String? voiceId}) {
    final clean = lang.toLowerCase().trim();
    String effectiveVoice = voiceId ?? state.selectedVoiceId;
    if (voiceId == null && _ref != null) {
      try {
        final settings = _ref!.read(settingsProvider);
        effectiveVoice = settings.defaultVoiceForLanguage(clean);
      } catch (_) {}
    }

    if (clean != state.selectedLanguage || effectiveVoice != state.selectedVoiceId) {
      _invalidateActiveSession(state.activeTtsTab);
      state = state.copyWith(
        selectedLanguage: clean,
        selectedVoiceId: effectiveVoice,
        clearTtsResponse: true,
      );
    }
  }

  void setSelectedSttLanguage(String lang) {
    final clean = lang.toLowerCase().trim();
    if (clean != state.selectedSttLanguage) {
      state = state.copyWith(selectedSttLanguage: clean);
    }
  }

  void setSelectedVoice(String voiceId) {
    if (voiceId != state.selectedVoiceId) {
      _invalidateActiveSession(state.activeTtsTab);
      state = state.copyWith(
        selectedVoiceId: voiceId,
        clearTtsResponse: true,
      );
    }
  }

  void setActiveDocument(DocumentModel doc) {
    if (doc.docId != state.activeDocument?.docId) {
      _invalidateActiveSession(TtsInputSource.document);
      state = state.copyWith(
        activeDocument: doc,
        selectedLanguage: doc.detectedLanguage,
        documentTabState: const TtsTabState(),
        originalAudioPath: doc.audioSourcePath,
        clearOriginalAudio: doc.audioSourcePath == null,
        isPlayingOriginalAudio: false,
      );

      if (doc.audioSourcePath != null) {
        _probeAudioDuration(doc.audioSourcePath!);
      }
    }
  }

  Future<void> _probeAudioDuration(String path) async {
    try {
      if (File(path).existsSync()) {
        await _audioPlayer.setSource(DeviceFileSource(path));
        final dur = await _audioPlayer.getDuration();
        if (dur != null && dur > Duration.zero && mounted) {
          state = state.copyWith(audioDuration: dur);
        }
      }
    } catch (_) {}
  }

  /// Auto-deletes history items older than 30 days, filters excluded IDs, deduplicates, sorts by date, updates state & persists to storage.
  void _updateAndPersistDocuments(List<DocumentModel> docs, [String? explicitUserId]) {
    final effectiveUserId = explicitUserId ?? _activeUserId ?? _storageService.getUser()['id'] ?? 'guest';
    final excludedIds = _storageService.getExcludedHistoryIds(effectiveUserId);
    final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
    final validDocs = docs.where((doc) {
      if (excludedIds.contains(doc.docId)) return false;
      final date = doc.createdAt ?? DateTime.now();
      return date.isAfter(cutoffDate);
    }).toList();

    final Map<String, DocumentModel> uniqueDocs = {};
    for (var doc in validDocs) {
      final key = doc.docId.isNotEmpty ? doc.docId : '${doc.filename}_${doc.characterCount}';
      if (!uniqueDocs.containsKey(key)) {
        uniqueDocs[key] = doc;
      } else {
        final existing = uniqueDocs[key]!;
        final mergedDoc = DocumentModel(
          docId: existing.docId.isNotEmpty ? existing.docId : doc.docId,
          filename: existing.filename.isNotEmpty ? existing.filename : doc.filename,
          text: existing.text.isNotEmpty ? existing.text : doc.text,
          wordCount: existing.wordCount > 0 ? existing.wordCount : doc.wordCount,
          characterCount: existing.characterCount > 0 ? existing.characterCount : doc.characterCount,
          detectedLanguage: existing.detectedLanguage,
          fileType: existing.fileType != 'pdf' ? existing.fileType : doc.fileType,
          isScanned: existing.isScanned || doc.isScanned,
          ocrUsed: existing.ocrUsed || doc.ocrUsed,
          pages: existing.pages.isNotEmpty ? existing.pages : doc.pages,
          pageCount: existing.pageCount > 1 ? existing.pageCount : doc.pageCount,
          createdAt: existing.createdAt ?? doc.createdAt ?? DateTime.now(),
          contentHash: existing.contentHash ?? doc.contentHash,
          chunks: existing.chunks.isNotEmpty ? existing.chunks : doc.chunks,
          timedWords: existing.timedWords.isNotEmpty ? existing.timedWords : doc.timedWords,
          audioSourcePath: existing.audioSourcePath ?? doc.audioSourcePath,
        );
        uniqueDocs[key] = mergedDoc;
      }
    }

    final finalList = uniqueDocs.values.toList();
    finalList.sort((a, b) {
      final dateA = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return dateB.compareTo(dateA);
    });

    state = state.copyWith(userDocuments: finalList);

    try {
      final docsJson = finalList.map((d) => d.toJson()).toList();
      _storageService.saveHistoryDocs(docsJson, effectiveUserId);
    } catch (_) {}
  }

  Future<void> loadVoices() async {
    state = state.copyWith(isLoadingVoices: true);
    try {
      final voices = await _repository.fetchVoices();
      final validVoices = voices.isNotEmpty ? voices : VoiceModel.defaultVoices();

      String preferredVoice = state.selectedVoiceId;
      if (_ref != null) {
        try {
          final settings = _ref!.read(settingsProvider);
          preferredVoice = settings.defaultVoiceForLanguage(state.selectedLanguage);
        } catch (_) {}
      }

      final isCurrentVoiceValid = validVoices.any((v) => v.voiceId == state.selectedVoiceId);
      final isPreferredVoiceValid = validVoices.any((v) => v.voiceId == preferredVoice);
      final newSelectedVoiceId = isCurrentVoiceValid
          ? state.selectedVoiceId
          : (isPreferredVoiceValid ? preferredVoice : validVoices.first.voiceId);

      state = state.copyWith(
        voices: validVoices,
        selectedVoiceId: newSelectedVoiceId,
        isLoadingVoices: false,
      );
    } catch (_) {
      final fallbackVoices = VoiceModel.defaultVoices();
      String preferredVoice = state.selectedVoiceId;
      if (_ref != null) {
        try {
          final settings = _ref!.read(settingsProvider);
          preferredVoice = settings.defaultVoiceForLanguage(state.selectedLanguage);
        } catch (_) {}
      }
      final isCurrentVoiceValid = fallbackVoices.any((v) => v.voiceId == state.selectedVoiceId);
      final isPreferredVoiceValid = fallbackVoices.any((v) => v.voiceId == preferredVoice);
      final newSelectedVoiceId = isCurrentVoiceValid
          ? state.selectedVoiceId
          : (isPreferredVoiceValid ? preferredVoice : fallbackVoices.first.voiceId);

      state = state.copyWith(
        voices: fallbackVoices,
        selectedVoiceId: newSelectedVoiceId,
        isLoadingVoices: false,
      );
    }
  }

  Future<void> loadUserDocuments([String? explicitUserId, int? generationToken]) async {
    final targetGen = generationToken ?? _sessionGeneration;
    final effectiveUserId = explicitUserId ?? _activeUserId ?? _storageService.getUser()['id'] ?? 'guest';
    _activeUserId = effectiveUserId;

    state = state.copyWith(isLoadingDocuments: true);

    try {
      final excludedIds = _storageService.getExcludedHistoryIds(effectiveUserId);
      final localRaw = _storageService.getHistoryDocs(effectiveUserId);
      final localDocs = localRaw
          .map((e) => DocumentModel.fromJson(e))
          .where((d) => !excludedIds.contains(d.docId))
          .toList();

      List<DocumentModel> remoteDocs = [];
      try {
        remoteDocs = (await _repository.getUserFiles())
            .where((d) => !excludedIds.contains(d.docId))
            .toList();
      } catch (_) {}

      // Guard: Ignore late responses from a previous session or if user changed
      if (_sessionGeneration != targetGen || _activeUserId != effectiveUserId) {
        return;
      }

      // Combine ONLY authenticated user's local docs and remote docs (NEVER old in-memory state.userDocuments)
      final combined = <DocumentModel>[...localDocs, ...remoteDocs];
      _updateAndPersistDocuments(combined, effectiveUserId);
    } finally {
      if (_sessionGeneration == targetGen && _activeUserId == effectiveUserId) {
        state = state.copyWith(isLoadingDocuments: false);
      }
    }
  }

  /// Delete document from history with optimistic removal, account-scoped persistence, and backend synchronization.
  Future<bool> deleteDocument(String docId) async {
    if (docId.isEmpty || _pendingDeletions.contains(docId)) return false;
    _pendingDeletions.add(docId);

    final effectiveUserId = _activeUserId ?? _storageService.getUser()['id'] ?? 'guest';
    final docIndex = state.userDocuments.indexWhere((d) => d.docId == docId);
    if (docIndex == -1) {
      _pendingDeletions.remove(docId);
      return false;
    }

    final docToDelete = state.userDocuments[docIndex];

    // Optimistically remove from state
    final updatedList = List<DocumentModel>.from(state.userDocuments)..removeAt(docIndex);
    state = state.copyWith(userDocuments: updatedList);

    // If the deleted entry owns the currently playing audio, stop that playback
    final bool isThisDocPlaying = (state.activeDocument?.docId == docId) ||
        (docToDelete.audioSourcePath != null &&
            state.originalAudioPath != null &&
            state.originalAudioPath == docToDelete.audioSourcePath);

    if (isThisDocPlaying) {
      if (state.isPlayingOriginalAudio) {
        await stopOriginalAudio();
      } else {
        await stopAudioAndClearQueue();
      }
      state = state.copyWith(activeDocument: null, clearOriginalAudio: true);
    }

    try {
      // Persist account-scoped exclusion and updated history
      await _storageService.addExcludedHistoryId(docId, effectiveUserId);
      final docsJson = updatedList.map((d) => d.toJson()).toList();
      await _storageService.saveHistoryDocs(docsJson, effectiveUserId);

      // Enforce remote deletion from backend if doc has a backend ID
      if (!docId.startsWith('doc_') && !docId.startsWith('stt_')) {
        try {
          await _repository.deleteFile(docId);
        } catch (backendErr) {
          debugPrint('[Delete] Remote backend delete info: $backendErr');
        }
      }
      return true;
    } catch (e) {
      // Persistence failed: rollback optimistic removal
      await _storageService.removeExcludedHistoryId(docId, effectiveUserId);
      final rollbackList = List<DocumentModel>.from(state.userDocuments);
      if (docIndex <= rollbackList.length) {
        rollbackList.insert(docIndex, docToDelete);
      } else {
        rollbackList.add(docToDelete);
      }
      state = state.copyWith(
        userDocuments: rollbackList,
        errorMessage: 'Failed to delete history item: ${e.toString()}',
      );
      return false;
    } finally {
      _pendingDeletions.remove(docId);
    }
  }

  Future<DocumentModel?> extractDocument(String filePath) async {
    final gen = _sessionGeneration;
    final reqUserId = _currentUserId;
    state = state.copyWith(isExtracting: true, errorMessage: null, successMessage: null);
    try {
      final rawDoc = await _repository.extractDocument(filePath);

      // Guard against stale response if user switched
      if (_sessionGeneration != gen || _currentUserId != reqUserId) {
        return null;
      }

      final doc = DocumentModel(
        docId: rawDoc.docId.isNotEmpty ? rawDoc.docId : 'doc_${DateTime.now().millisecondsSinceEpoch}',
        filename: rawDoc.filename,
        text: rawDoc.text,
        wordCount: rawDoc.wordCount,
        characterCount: rawDoc.characterCount,
        detectedLanguage: rawDoc.detectedLanguage,
        fileType: rawDoc.fileType,
        isScanned: rawDoc.isScanned,
        ocrUsed: rawDoc.ocrUsed,
        pages: rawDoc.pages,
        pageCount: rawDoc.pageCount,
        createdAt: rawDoc.createdAt ?? DateTime.now(),
        contentHash: rawDoc.contentHash,
        chunks: rawDoc.chunks,
      );

      final updatedDocs = [doc, ...state.userDocuments];
      _updateAndPersistDocuments(updatedDocs, reqUserId);
      state = state.copyWith(
        isExtracting: false,
        activeDocument: doc,
        selectedLanguage: doc.detectedLanguage,
        successMessage: 'Text extracted successfully (${doc.characterCount} chars)!',
      );
      return doc;
    } catch (e) {
      if (_sessionGeneration != gen || _currentUserId != reqUserId) {
        return null;
      }
      state = state.copyWith(
        isExtracting: false,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  /// Transcribe audio file using Local Whisper for Marathi & Hindi, or Backend for English
  Future<DocumentModel?> transcribeAudioFile(
    String filePath, {
    String? language,
  }) async {
    final int requestToken = ++_activeSttToken;
    final int requestSessionGen = _sessionGeneration;
    final String requestUserId = _currentUserId;

    // 1. Immediately invalidate any active TTS session and stop lingering audio
    _invalidateActiveSession();

    final effectiveLang = (language ?? state.selectedSttLanguage).toLowerCase().trim();

    final previousDoc = state.activeDocument;
    final previousAudioPath = state.originalAudioPath;
    final previousAudioDuration = state.audioDuration;

    state = state.copyWith(
      isExtracting: true,
      clearTtsResponse: true,
      isPlayingOriginalAudio: false,
      playerState: PlayerState.stopped,
      audioPosition: Duration.zero,
      isProgressive: false,
      progressiveCurrentChunk: 1,
      progressiveTotalChunks: 1,
      progressiveCompletedChunks: 0,
      completeAudioUrl: null,
      completeFilename: null,
      isBufferingNextChunk: false,
      errorMessage: null,
      successMessage: null,
    );

    try {
      // 2. Retain a usable local source file in user-scoped app storage for original audio playback
      String persistentAudioPath = filePath;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final audioDir = Directory('${appDir.path}/users/$requestUserId/stt_audio');
        if (!await audioDir.exists()) {
          await audioDir.create(recursive: true);
        }
        final srcFile = File(filePath);
        if (await srcFile.exists()) {
          final cleanBaseName = filePath.split(RegExp(r'[/\\]')).last;
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_$cleanBaseName';
          final destFile = File('${audioDir.path}/$fileName');
          await srcFile.copy(destFile.path);
          persistentAudioPath = destFile.path;
        }
      } catch (e) {
        debugPrint('Failed to copy audio to app storage: $e');
      }

      if (requestToken != _activeSttToken || _sessionGeneration != requestSessionGen || _currentUserId != requestUserId) return null;

      String transcript = '';
      List<TimedWord> timedWords = [];

      final sttLang = readora_stt.SttLanguage.fromCode(effectiveLang);

      // Validate audio file format and size using readora_audio_stt
      try {
        readora_stt.AudioFormatValidator.validate(filePath);
      } catch (valErr) {
        debugPrint('[readora_audio_stt] File validation info: $valErr');
      }

      bool pkgSucceeded = false;
      // 1. Attempt fast backend transcription first (completes in 1-3 seconds on host server)
      readora_stt.AudioFileSttService? sttService;
      try {
        final token = _storageService.getToken() ?? '';
        final saved = _storageService.getBaseUrl();
        final clientUrl = _ref?.read(apiClientProvider).baseUrl ?? '';

        final rawCandidates = <String>[
          if (clientUrl.isNotEmpty) clientUrl.replaceAll('/api', ''),
          if (saved != null && saved.isNotEmpty) saved.replaceAll('/api', ''),
          ...ApiEndpoints.candidateBaseUrls.map((u) => u.replaceAll('/api', '')),
        ].map((u) => u.endsWith('/') ? u.substring(0, u.length - 1) : u).toSet().toList();

        final primaryBaseUrl = rawCandidates.isNotEmpty ? rawCandidates.first : 'http://127.0.0.1:5000';
        final otherCandidates = rawCandidates.where((u) => u != primaryBaseUrl).toList();

        sttService = readora_stt.AudioFileSttService(
          config: readora_stt.SttConfig(
            baseUrl: primaryBaseUrl,
            candidateBaseUrls: otherCandidates,
            timeoutSeconds: 120,
          ),
        );
        _currentSttService = sttService;

        final pkgResult = await sttService.transcribeAudioFile(
          filePath: filePath,
          language: sttLang,
          jwtToken: token,
        );

        if (pkgResult.success) {
          pkgSucceeded = true;
          if (sttService.successfulBaseUrl != null) {
            final activeApiUrl = '${sttService.successfulBaseUrl}/api';
            _storageService.saveBaseUrl(activeApiUrl);
            _ref?.read(apiClientProvider).updateBaseUrl(activeApiUrl);
          }

          if (pkgResult.transcript.trim().isEmpty) {
            // Handled empty audio / no speech detected cleanly without redundant fallbacks
            if (requestToken == _activeSttToken && _sessionGeneration == requestSessionGen && _currentUserId == requestUserId) {
              state = state.copyWith(
                isExtracting: false,
                activeDocument: previousDoc,
                originalAudioPath: previousAudioPath,
                audioDuration: previousAudioDuration,
                clearTtsResponse: true,
                errorMessage: 'No speech was detected in this recording. Please speak clearly and try again.',
              );
            }
            return null;
          }

          transcript = pkgResult.transcript;
          timedWords = pkgResult.timedWords.map((w) => TimedWord(
            text: w.word,
            startMs: w.startMs,
            endMs: w.endMs,
          )).toList();

          debugPrint('⚡ [STT] High-speed server transcription completed: ${transcript.length} chars');
        }
      } catch (pkgErr) {
        debugPrint('[readora_audio_stt] Server transcription error: $pkgErr');
      } finally {
        if (_currentSttService == sttService) {
          _currentSttService = null;
        }
        sttService?.dispose();
      }

      if (requestToken != _activeSttToken || _sessionGeneration != requestSessionGen || _currentUserId != requestUserId) {
        state = state.copyWith(isExtracting: false);
        return null;
      }

      // 2. If server was offline or failed, run optimized on-device Whisper (base model) or repo detailed fallback
      if (!pkgSucceeded) {
        final langParam = sttLang == readora_stt.SttLanguage.marathi
            ? 'mr'
            : (sttLang == readora_stt.SttLanguage.hindi
                ? 'hi'
                : (sttLang == readora_stt.SttLanguage.auto ? 'auto' : 'en'));
        debugPrint('📱 [STT] Attempting on-device Whisper or repository detailed fallback ($langParam)...');
        try {
          final res = await LocalWhisperService().transcribeAudioDetailed(
            filePath,
            language: langParam,
          );
          transcript = res.text;
          timedWords = res.words;
          if (transcript.isNotEmpty) pkgSucceeded = true;
        } catch (localErr) {
          debugPrint('📱 [STT] Local whisper fallback error: $localErr, attempting repo detailed fallback...');
          try {
            final res = await _repository.transcribeAudioBackendDetailed(
              filePath,
              language: langParam == 'auto' ? 'mr' : langParam,
            );
            transcript = (res['transcript'] ?? res['text'] ?? '').toString();
            if (res['words'] is List) {
              timedWords = (res['words'] as List)
                  .map((w) => TimedWord.fromJson(Map<String, dynamic>.from(w as Map)))
                  .toList();
            }
            if (transcript.isNotEmpty) pkgSucceeded = true;
          } catch (repoErr) {
            debugPrint('📱 [STT] Repository detailed fallback error: $repoErr');
          }
        }

        if (!pkgSucceeded && transcript.isEmpty) {
          if (requestToken == _activeSttToken && _sessionGeneration == requestSessionGen && _currentUserId == requestUserId) {
            state = state.copyWith(
              isExtracting: false,
              activeDocument: previousDoc,
              originalAudioPath: previousAudioPath,
              audioDuration: previousAudioDuration,
              clearTtsResponse: true,
              errorMessage: 'Could not transcribe audio. Please check your network and tap Retry.',
            );
          }
          return null;
        }
      }

      if (requestToken != _activeSttToken || _sessionGeneration != requestSessionGen || _currentUserId != requestUserId) {
        state = state.copyWith(isExtracting: false);
        return null;
      }

      // 3. Probe real duration from the media player without guessing
      Duration probedDuration = Duration.zero;
      try {
        if (File(persistentAudioPath).existsSync()) {
          await _audioPlayer.setSource(DeviceFileSource(persistentAudioPath));
          final dur = await _audioPlayer.getDuration();
          if (dur != null && dur > Duration.zero) {
            probedDuration = dur;
          }
          await _audioPlayer.stop(); // Cleanly close native MediaPlayer stream/FD
        }
      } catch (e) {
        debugPrint('Could not probe audio duration: $e');
      }

      if (requestToken != _activeSttToken || _sessionGeneration != requestSessionGen || _currentUserId != requestUserId) {
        state = state.copyWith(isExtracting: false);
        return null;
      }

      final filename = filePath.split(RegExp(r'[/\\]')).last;
      final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : 'audio';

      // Smart detected language resolution: preserve Devanagari script integrity
      String resolvedDocLang = effectiveLang;
      if (RegExp(r'[\u0900-\u097F]').hasMatch(transcript)) {
        resolvedDocLang = (effectiveLang == 'marathi' || effectiveLang == 'mr' || filename.toLowerCase().contains('marathi'))
            ? 'marathi'
            : 'hindi';
      } else if (resolvedDocLang == 'auto') {
        resolvedDocLang = 'english';
      }

      final doc = DocumentModel(
        docId: 'stt_${DateTime.now().millisecondsSinceEpoch}',
        filename: filename,
        fileType: ext,
        text: transcript,
        detectedLanguage: resolvedDocLang,
        wordCount: transcript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
        characterCount: transcript.length,
        createdAt: DateTime.now(),
        timedWords: timedWords,
        audioSourcePath: persistentAudioPath,
      );

      final renderStart2 = DateTime.now();
      final updatedDocs = [doc, ...state.userDocuments];
      _updateAndPersistDocuments(updatedDocs, requestUserId);
      state = state.copyWith(
        isExtracting: false,
        activeDocument: doc,
        selectedSttLanguage: resolvedDocLang,
        originalAudioPath: persistentAudioPath,
        isPlayingOriginalAudio: false,
        clearTtsResponse: true,
        playerState: PlayerState.stopped,
        audioPosition: Duration.zero,
        audioDuration: probedDuration,
        successMessage: 'Audio transcribed successfully!',
      );

      final renderDurationMs = DateTime.now().difference(renderStart2).inMilliseconds;
      debugPrint('⏱️ [READORA STT TIMINGS BREAKDOWN]');
      debugPrint('⏱️   Flutter Rendering:  $renderDurationMs ms');
      debugPrint('⏱️   Transcribed:        ${doc.wordCount} words, ${doc.characterCount} chars');

      return doc;
    } catch (e) {
      state = state.copyWith(
        isExtracting: false,
        activeDocument: previousDoc,
        originalAudioPath: previousAudioPath,
        audioDuration: previousAudioDuration,
        clearTtsResponse: true,
        errorMessage: 'Audio transcription failed: $e',
      );
      return null;
    }
  }

  Future<String?> translateText(String text, String targetLanguage, {String? sourceLanguage}) async {
    if (text.trim().isEmpty) return null;
    state = state.copyWith(isExtracting: true, errorMessage: null);
    try {
      final translated = await _repository.translateText(text, targetLanguage, sourceLanguage: sourceLanguage);
      state = state.copyWith(isExtracting: false);
      return translated;
    } catch (e) {
      state = state.copyWith(
        isExtracting: false,
        errorMessage: 'Translation error: $e',
      );
      return null;
    }
  }

  static List<String> splitTextIntoSafeChunks(String text, {int maxChunkSize = 3500}) {
    if (text.trim().isEmpty) return [];
    if (text.length <= maxChunkSize) return [text];

    final chunks = <String>[];
    final paragraphs = text.split(RegExp(r'\n{2,}'));
    String currentChunk = '';

    for (final para in paragraphs) {
      final trimmedPara = para.trim();
      if (trimmedPara.isEmpty) continue;

      final prospectiveLength = currentChunk.isEmpty
          ? trimmedPara.length
          : currentChunk.length + 2 + trimmedPara.length;

      if (prospectiveLength <= maxChunkSize) {
        currentChunk = currentChunk.isEmpty ? trimmedPara : '$currentChunk\n\n$trimmedPara';
      } else {
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk);
          currentChunk = '';
        }

        if (trimmedPara.length <= maxChunkSize) {
          currentChunk = trimmedPara;
        } else {
          final sentenceMatches = RegExp(r'[^.!?।\n]+(?:[.!?।]+|$)').allMatches(trimmedPara);
          final sentences = sentenceMatches.map((m) => m.group(0) ?? '').where((s) => s.trim().isNotEmpty).toList();
          final effectiveSentences = sentences.isNotEmpty ? sentences : [trimmedPara];

          for (final sent in effectiveSentences) {
            final trimmedSent = sent.trim();
            if (trimmedSent.isEmpty) continue;

            final sentLength = currentChunk.isEmpty
                ? trimmedSent.length
                : currentChunk.length + 1 + trimmedSent.length;

            if (sentLength <= maxChunkSize) {
              currentChunk = currentChunk.isEmpty ? trimmedSent : '$currentChunk $trimmedSent';
            } else {
              if (currentChunk.isNotEmpty) {
                chunks.add(currentChunk);
                currentChunk = '';
              }

              if (trimmedSent.length > maxChunkSize) {
                final words = trimmedSent.split(RegExp(r'\s+'));
                for (final w in words) {
                  final wordLength = currentChunk.isEmpty
                      ? w.length
                      : currentChunk.length + 1 + w.length;
                  if (wordLength <= maxChunkSize) {
                    currentChunk = currentChunk.isEmpty ? w : '$currentChunk $w';
                  } else {
                    if (currentChunk.isNotEmpty) chunks.add(currentChunk);
                    currentChunk = w;
                  }
                }
              } else {
                currentChunk = trimmedSent;
              }
            }
          }
        }
      }
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk);
    }

    return chunks;
  }

  Future<TtsResponseModel?> generateSpeech({
    required String text,
    required String baseUrl,
    TtsInputSource? source,
  }) async {
    final cleanText = text.trim();
    final targetSource = source ?? state.activeTtsTab;

    if (cleanText.isEmpty) {
      state = state.copyWith(errorMessage: 'Please enter or extract text first');
      return null;
    }

    // Ensure selected voice ID is valid and not empty or 'default'
    String effectiveVoiceId = state.selectedVoiceId;
    if (effectiveVoiceId == 'default' || effectiveVoiceId.isEmpty) {
      effectiveVoiceId = state.voices.isNotEmpty ? state.voices.first.voiceId : 'CwhRBWXzGAHq8TQ4Fs17';
      state = state.copyWith(selectedVoiceId: effectiveVoiceId);
    }

    final currentSeq = (_tabRequestSeq[targetSource] ?? 0) + 1;
    _tabRequestSeq[targetSource] = currentSeq;
    final requestId = currentSeq;
    final sessionId = '${targetSource.name}_${requestId}_${DateTime.now().millisecondsSinceEpoch}_${(cleanText.hashCode.abs() % 10000)}';
    _tabActiveSessionId[targetSource] = sessionId;
    _lastBaseUrl = baseUrl;

    final chunks = splitTextIntoSafeChunks(cleanText, maxChunkSize: 3500);
    final totalChunks = chunks.length;

    _tabProgressiveAudioQueue[targetSource] = List.filled(totalChunks, null, growable: true);

    final generatingTab = (targetSource == TtsInputSource.document
            ? state.documentTabState
            : state.textTabState)
        .copyWith(
      isGenerating: true,
      playerState: PlayerState.stopped,
      isProgressive: totalChunks > 1,
      progressiveCurrentChunk: 1,
      progressiveTotalChunks: totalChunks,
      progressiveCompletedChunks: 0,
      completeAudioUrl: null,
      completeFilename: null,
      isBufferingNextChunk: false,
    );

    state = state.copyWith(
      documentTabState: targetSource == TtsInputSource.document ? generatingTab : null,
      textTabState: targetSource == TtsInputSource.text ? generatingTab : null,
      errorMessage: null,
      successMessage: null,
    );

    // Reset audio player if playing this source
    if (_playingSource == targetSource || _playingSource == null) {
      _playingSource = null;
      try {
        await _audioPlayer.stop();
      } catch (_) {}
    }

    if (totalChunks <= 1) {
      // Single chunk: standard fast conversion
      try {
        final response = await _repository.generateSpeech(
          text: cleanText,
          language: state.selectedLanguage,
          voiceId: effectiveVoiceId,
          documentId: targetSource == TtsInputSource.document ? state.activeDocument?.docId : null,
          textHash: targetSource == TtsInputSource.document ? state.activeDocument?.contentHash : null,
        );

        if (_tabActiveSessionId[targetSource] != sessionId || _tabRequestSeq[targetSource] != requestId) {
          return null;
        }

        final doneTab = (targetSource == TtsInputSource.document
                ? state.documentTabState
                : state.textTabState)
            .copyWith(
          isGenerating: false,
          response: response,
          progressiveCompletedChunks: 1,
          completeAudioUrl: response.audioUrl,
          completeFilename: response.filename,
        );

        state = state.copyWith(
          documentTabState: targetSource == TtsInputSource.document ? doneTab : null,
          textTabState: targetSource == TtsInputSource.text ? doneTab : null,
          successMessage: 'Speech generated successfully!',
        );

        final shouldAutoPlay = _ref?.read(settingsProvider).autoPlayTts ?? false;
        // ONLY auto-play if user is still on the originating tab!
        if (shouldAutoPlay && state.activeTtsTab == targetSource) {
          await playAudio(response.audioUrl, baseUrl, source: targetSource);
        }
        return response;
      } catch (e) {
        if (_tabActiveSessionId[targetSource] != sessionId || _tabRequestSeq[targetSource] != requestId) {
          return null;
        }
        final failTab = (targetSource == TtsInputSource.document
                ? state.documentTabState
                : state.textTabState)
            .copyWith(
          isGenerating: false,
        );
        state = state.copyWith(
          documentTabState: targetSource == TtsInputSource.document ? failTab : null,
          textTabState: targetSource == TtsInputSource.text ? failTab : null,
          errorMessage: 'Speech generation failed: $e',
        );
        return null;
      }
    }

    // MULTI-CHUNK PROGRESSIVE FLOW (Matching website behavior)
    try {
      // 1. Request CHUNK 0 immediately for instant playback
      final chunk0Response = await _repository.generateSpeech(
        text: chunks[0],
        language: state.selectedLanguage,
        voiceId: effectiveVoiceId,
        documentId: targetSource == TtsInputSource.document ? state.activeDocument?.docId : null,
        textHash: targetSource == TtsInputSource.document ? state.activeDocument?.contentHash : null,
        chunkIndex: 0,
        totalChunks: totalChunks,
        sessionId: sessionId,
      );

      if (_tabActiveSessionId[targetSource] != sessionId || _tabRequestSeq[targetSource] != requestId) {
        return null;
      }

      _tabProgressiveAudioQueue[targetSource]![0] = chunk0Response;

      final chunk0DoneTab = (targetSource == TtsInputSource.document
              ? state.documentTabState
              : state.textTabState)
          .copyWith(
        isGenerating: false,
        response: chunk0Response,
        progressiveCompletedChunks: 1,
      );

      state = state.copyWith(
        documentTabState: targetSource == TtsInputSource.document ? chunk0DoneTab : null,
        textTabState: targetSource == TtsInputSource.text ? chunk0DoneTab : null,
        successMessage: 'Playing Part 1 of $totalChunks (buffering remaining in background...)',
      );

      final shouldAutoPlay = _ref?.read(settingsProvider).autoPlayTts ?? false;
      if (shouldAutoPlay && state.activeTtsTab == targetSource) {
        await playAudio(chunk0Response.audioUrl, baseUrl, source: targetSource);
      }

      // 2. Buffer subsequent chunks sequentially in the background
      _bufferSubsequentChunks(
        chunks: chunks,
        effectiveVoiceId: effectiveVoiceId,
        sessionId: sessionId,
        requestId: requestId,
        targetSource: targetSource,
        baseUrl: baseUrl,
      );

      return chunk0Response;
    } catch (e) {
      if (_tabActiveSessionId[targetSource] != sessionId || _tabRequestSeq[targetSource] != requestId) {
        return null;
      }
      final failTab = (targetSource == TtsInputSource.document
              ? state.documentTabState
              : state.textTabState)
          .copyWith(
        isGenerating: false,
        isProgressive: false,
      );
      state = state.copyWith(
        documentTabState: targetSource == TtsInputSource.document ? failTab : null,
        textTabState: targetSource == TtsInputSource.text ? failTab : null,
        errorMessage: 'Failed to start speech conversion: $e',
      );
      return null;
    }
  }

  void _bufferSubsequentChunks({
    required List<String> chunks,
    required String effectiveVoiceId,
    required String sessionId,
    required int requestId,
    required TtsInputSource targetSource,
    required String baseUrl,
  }) async {
    for (int i = 1; i < chunks.length; i++) {
      if (_tabActiveSessionId[targetSource] != sessionId || _tabRequestSeq[targetSource] != requestId) break;

      int retries = 2;
      bool success = false;
      while (retries > 0 && !success && _tabActiveSessionId[targetSource] == sessionId && _tabRequestSeq[targetSource] == requestId) {
        try {
          final chunkResponse = await _repository.generateSpeech(
            text: chunks[i],
            language: state.selectedLanguage,
            voiceId: effectiveVoiceId,
            documentId: targetSource == TtsInputSource.document ? state.activeDocument?.docId : null,
            textHash: targetSource == TtsInputSource.document ? state.activeDocument?.contentHash : null,
            chunkIndex: i,
            totalChunks: chunks.length,
            sessionId: sessionId,
          );

          if (_tabActiveSessionId[targetSource] != sessionId || _tabRequestSeq[targetSource] != requestId) break;

          _tabProgressiveAudioQueue[targetSource]![i] = chunkResponse;
          success = true;

          final curTabState = targetSource == TtsInputSource.document
              ? state.documentTabState
              : state.textTabState;

          final updatedTabState = curTabState.copyWith(
            progressiveCompletedChunks: i + 1,
            completeAudioUrl: chunkResponse.completeAudioUrl ?? curTabState.completeAudioUrl,
            completeFilename: chunkResponse.completeFilename ?? curTabState.completeFilename,
          );

          state = state.copyWith(
            documentTabState: targetSource == TtsInputSource.document ? updatedTabState : null,
            textTabState: targetSource == TtsInputSource.text ? updatedTabState : null,
          );

          // If playback of previous chunk finished while waiting for this chunk:
          if (_playingSource == targetSource &&
              _tabActiveSessionId[targetSource] == sessionId &&
              updatedTabState.playerState != PlayerState.stopped &&
              updatedTabState.isBufferingNextChunk &&
              updatedTabState.progressiveCurrentChunk == i + 1) {
            final nextChunkTab = updatedTabState.copyWith(
              isBufferingNextChunk: false,
              response: chunkResponse,
            );
            state = state.copyWith(
              documentTabState: targetSource == TtsInputSource.document ? nextChunkTab : null,
              textTabState: targetSource == TtsInputSource.text ? nextChunkTab : null,
            );
            if (nextChunkTab.playerState != PlayerState.paused && nextChunkTab.playerState != PlayerState.stopped) {
              await playAudio(chunkResponse.audioUrl, baseUrl, source: targetSource);
            }
          }
        } catch (err) {
          retries--;
          if (retries > 0) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }
    }
  }

  void resetTtsResponse({TtsInputSource? source}) {
    final targetSource = source ?? state.activeTtsTab;
    _invalidateActiveSession(targetSource);
    final resetTab = const TtsTabState();
    state = state.copyWith(
      documentTabState: targetSource == TtsInputSource.document ? resetTab : null,
      textTabState: targetSource == TtsInputSource.text ? resetTab : null,
    );
  }

  String resolveAudioUrl(String audioPath, String baseUrl) {
    if (audioPath.startsWith('http://') || audioPath.startsWith('https://')) {
      return _attachTokenIfMissing(audioPath);
    }
    String cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    String cleanPath = audioPath.startsWith('/') ? audioPath : '/$audioPath';

    if (cleanBase.endsWith('/api') && cleanPath.startsWith('/api/')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - 4);
    }

    return _attachTokenIfMissing('$cleanBase$cleanPath');
  }

  String _attachTokenIfMissing(String url) {
    final token = _storageService.getToken();
    if (token != null && token.isNotEmpty && !url.contains('token=')) {
      final separator = url.contains('?') ? '&' : '?';
      return '$url${separator}token=$token';
    }
    return url;
  }

  Future<void> playAudio(String audioPath, String baseUrl, {TtsInputSource? source}) async {
    try {
      final playSource = source ?? state.activeTtsTab;
      _lastBaseUrl = baseUrl;
      _playingSource = playSource;
      final String fullUrl = resolveAudioUrl(audioPath, baseUrl);
      try {
        _ref?.read(downloadsProvider.notifier).stopPlayback();
      } catch (_) {}
      await _audioPlayer.stop();
      state = state.copyWith(isPlayingOriginalAudio: false);
      await _audioPlayer.setVolume(state.isMuted ? 0.0 : state.volume);
      await _audioPlayer.play(UrlSource(fullUrl));
      await _audioPlayer.setPlaybackRate(state.playbackRate);
      await _audioPlayer.setVolume(state.isMuted ? 0.0 : state.volume);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Audio playback error: $e');
    }
  }

  Future<void> playOriginalAudio([String? filePath]) async {
    try {
      _ref?.read(downloadsProvider.notifier).stopPlayback();
    } catch (_) {}
    final path = filePath ?? state.originalAudioPath ?? state.activeDocument?.audioSourcePath;
    if (path == null || path.isEmpty) {
      state = state.copyWith(errorMessage: 'Original audio file not found');
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      state = state.copyWith(errorMessage: 'Audio file does not exist on device: $path');
      return;
    }

    try {
      _invalidateActiveSession();
      await _audioPlayer.stop();

      state = state.copyWith(
        isPlayingOriginalAudio: true,
        originalAudioPath: path,
        clearTtsResponse: true,
        audioPosition: Duration.zero,
        errorMessage: null,
      );

      await _audioPlayer.setVolume(state.isMuted ? 0.0 : state.volume);
      await _audioPlayer.play(DeviceFileSource(path));
      await _audioPlayer.setPlaybackRate(state.playbackRate);
    } catch (e) {
      state = state.copyWith(
        isPlayingOriginalAudio: false,
        errorMessage: 'Failed to play original audio: $e',
      );
    }
  }

  /// Toggle play/pause for original source audio
  Future<void> toggleOriginalAudio([String? filePath]) async {
    if (state.isPlayingOriginalAudio) {
      if (state.playerState == PlayerState.playing) {
        await _audioPlayer.pause();
      } else if (state.playerState == PlayerState.paused) {
        await _audioPlayer.resume();
      } else if (state.playerState == PlayerState.completed) {
        await _audioPlayer.seek(Duration.zero);
        await _audioPlayer.resume();
      } else {
        await playOriginalAudio(filePath);
      }
    } else {
      await playOriginalAudio(filePath);
    }
  }

  /// Stop original audio and reset to zero position
  Future<void> stopOriginalAudio() async {
    await _audioPlayer.stop();
    state = state.copyWith(
      playerState: PlayerState.stopped,
      audioPosition: Duration.zero,
      isPlayingOriginalAudio: false,
    );
  }

  Future<void> togglePlayPause(String baseUrl) async {
    if (state.isPlayingOriginalAudio) {
      if (state.currentTtsResponse != null && state.currentTtsResponse!.audioUrl.isNotEmpty) {
        await playAudio(state.currentTtsResponse!.audioUrl, baseUrl, source: state.activeTtsTab);
      }
      return;
    }

    final activeTab = state.activeTtsTab;
    final tabState = activeTab == TtsInputSource.document
        ? state.documentTabState
        : state.textTabState;

    if (tabState.playerState == PlayerState.playing && _playingSource == activeTab) {
      await _audioPlayer.pause();
    } else if (tabState.playerState == PlayerState.paused && _playingSource == activeTab) {
      await _audioPlayer.resume();
    } else if (tabState.response != null && tabState.response!.audioUrl.isNotEmpty) {
      await playAudio(tabState.response!.audioUrl, baseUrl, source: activeTab);
    }
  }

  Future<void> toggleMute() async {
    final newMute = !state.isMuted;
    final targetVol = newMute ? 0.0 : (state.volume > 0 ? state.volume : 1.0);
    await _audioPlayer.setVolume(targetVol);
    state = state.copyWith(isMuted: newMute);
  }

  Future<void> setVolume(double vol) async {
    final targetVol = vol.clamp(0.0, 1.0);
    await _audioPlayer.setVolume(targetVol);
    state = state.copyWith(
      volume: targetVol,
      isMuted: targetVol == 0.0,
    );
  }

  Future<void> pauseAudio() async {
    await _audioPlayer.pause();
  }

  Future<void> resumeAudio() async {
    await _audioPlayer.resume();
  }

  Future<void> seekAudio(Duration duration) async {
    await _audioPlayer.seek(duration);
    final target = _playingSource ?? state.activeTtsTab;
    final updatedTab = (target == TtsInputSource.document
            ? state.documentTabState
            : state.textTabState)
        .copyWith(position: duration);
    state = state.copyWith(
      documentTabState: target == TtsInputSource.document ? updatedTab : null,
      textTabState: target == TtsInputSource.text ? updatedTab : null,
    );
  }

  Future<void> setPlaybackRate(double rate) async {
    try {
      await _audioPlayer.setPlaybackRate(rate);
      state = state.copyWith(playbackRate: rate, errorMessage: null);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to change playback speed: $e');
      rethrow;
    }
  }

  Future<DownloadModel?> downloadAudioToLibrary(String baseUrl) async {
    final response = state.currentTtsResponse;
    if (response == null || response.audioUrl.isEmpty) {
      state = state.copyWith(errorMessage: 'No audio available to download');
      return null;
    }

    if (state.isDownloadingAudio) {
      return null;
    }

    if (state.isProgressive && state.completeAudioUrl == null && state.progressiveCompletedChunks < state.progressiveTotalChunks) {
      state = state.copyWith(
        errorMessage: 'Still preparing complete audio file (${state.progressiveCompletedChunks}/${state.progressiveTotalChunks} parts ready). Please wait a few seconds...',
      );
      return null;
    }

    state = state.copyWith(isDownloadingAudio: true, errorMessage: null, successMessage: null);

    try {
      final targetAudioUrl = (state.completeAudioUrl != null && state.completeAudioUrl!.isNotEmpty)
          ? state.completeAudioUrl!
          : (response.completeAudioUrl != null && response.completeAudioUrl!.isNotEmpty)
              ? response.completeAudioUrl!
              : response.audioUrl;

      final targetFilename = (state.completeFilename != null && state.completeFilename!.isNotEmpty)
          ? state.completeFilename!
          : (response.completeFilename != null && response.completeFilename!.isNotEmpty)
              ? response.completeFilename!
              : response.filename;

      if (_ref != null) {
        final downloadsNotifier = _ref!.read(downloadsProvider.notifier);
        final voiceName = state.voices.firstWhere(
          (v) => v.voiceId == state.selectedVoiceId,
          orElse: () => VoiceModel(voiceId: state.selectedVoiceId, name: 'Voice'),
        ).name;

        final isDoc = state.activeTtsTab == TtsInputSource.document;
        final downloadItem = await downloadsNotifier.saveAudioToLibrary(
          audioUrl: targetAudioUrl,
          baseUrl: baseUrl,
          displayFilename: targetFilename,
          language: state.selectedLanguage,
          sourceDocId: isDoc ? state.activeDocument?.docId : null,
          sourceDocName: isDoc ? state.activeDocument?.filename : 'Typed Text',
          voiceId: state.selectedVoiceId,
          voiceName: voiceName,
          generationSessionId: _tabActiveSessionId[state.activeTtsTab] ?? '',
          duration: state.audioDuration,
        );

        state = state.copyWith(
          isDownloadingAudio: false,
          successMessage: downloadItem != null ? 'Audio saved to Downloads library' : null,
        );
        return downloadItem;
      }
      state = state.copyWith(isDownloadingAudio: false);
      return null;
    } catch (e) {
      state = state.copyWith(
        isDownloadingAudio: false,
        errorMessage: 'Download failed: $e',
      );
      return null;
    }
  }

  Future<String?> downloadAudio(String baseUrl) async {
    final response = state.currentTtsResponse;
    if (response == null || response.audioUrl.isEmpty) {
      state = state.copyWith(errorMessage: 'No audio available to download');
      return null;
    }

    if (state.isDownloadingAudio) {
      return null;
    }

    if (state.isProgressive && state.completeAudioUrl == null && state.progressiveCompletedChunks < state.progressiveTotalChunks) {
      state = state.copyWith(
        errorMessage: 'Still preparing complete audio file (${state.progressiveCompletedChunks}/${state.progressiveTotalChunks} parts ready). Please wait a few seconds...',
      );
      return null;
    }

    state = state.copyWith(isDownloadingAudio: true, errorMessage: null, successMessage: null);
    try {
      final targetAudioUrl = (state.completeAudioUrl != null && state.completeAudioUrl!.isNotEmpty)
          ? state.completeAudioUrl!
          : (response.completeAudioUrl != null && response.completeAudioUrl!.isNotEmpty)
              ? response.completeAudioUrl!
              : response.audioUrl;

      final targetFilename = (state.completeFilename != null && state.completeFilename!.isNotEmpty)
          ? state.completeFilename!
          : (response.completeFilename != null && response.completeFilename!.isNotEmpty)
              ? response.completeFilename!
              : response.filename;

      final String fullUrl = resolveAudioUrl(targetAudioUrl, baseUrl);
      final uri = Uri.parse(fullUrl);
      final token = _storageService.getToken();
      final headers = <String, String>{};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 45));
      if (res.statusCode != 200) {
        throw Exception('Download failed with status code ${res.statusCode}');
      }
      if (res.bodyBytes.isEmpty) {
        throw Exception('Downloaded audio content is empty (0 bytes)');
      }

      String fileName = targetFilename.isNotEmpty ? targetFilename : 'readora_audio.mp3';
      if (!fileName.endsWith('.mp3') && !fileName.endsWith('.wav') && !fileName.endsWith('.m4a')) {
        fileName = '$fileName.mp3';
      }
      final cleanFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

      String? savePath;
      bool wasCancelled = false;

      try {
        savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Audio File',
          fileName: cleanFileName,
          bytes: res.bodyBytes,
          type: FileType.custom,
          allowedExtensions: ['mp3', 'wav', 'm4a'],
        );
        if (savePath == null) {
          wasCancelled = true;
        }
      } catch (_) {
        savePath = null;
      }

      if (wasCancelled) {
        state = state.copyWith(
          isDownloadingAudio: false,
          successMessage: 'Download cancelled',
        );
        return 'CANCELLED';
      }

      if (savePath != null) {
        final file = File(savePath);
        if (!file.existsSync() || file.lengthSync() == 0) {
          await file.writeAsBytes(res.bodyBytes);
        }
      } else {
        Directory? dir;
        if (Platform.isAndroid) {
          dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        } else {
          dir = await getApplicationDocumentsDirectory();
        }
        savePath = '${dir.path}/$cleanFileName';
        final file = File(savePath);
        await file.writeAsBytes(res.bodyBytes);
      }

      state = state.copyWith(
        isDownloadingAudio: false,
        successMessage: 'Audio saved successfully: $cleanFileName',
      );
      return savePath;
    } catch (e) {
      state = state.copyWith(
        isDownloadingAudio: false,
        errorMessage: 'Download failed: $e',
      );
      return null;
    }
  }
}

// Provider
final documentTtsNotifierProvider =
    StateNotifierProvider<DocumentTtsNotifier, DocumentTtsState>((ref) {
  final repository = ref.watch(documentTtsRepositoryProvider);
  final storageService = ref.watch(storageServiceProvider);
  return DocumentTtsNotifier(repository, storageService, ref);
});
