import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/services/storage_service.dart';
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

// Repository Provider
final documentTtsRepositoryProvider = Provider<DocumentTtsRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return DocumentTtsRepository(apiClient);
});

// State Class
class DocumentTtsState {
  final bool isExtracting;
  final bool isGeneratingSpeech;
  final bool isLoadingVoices;
  final List<DocumentModel> userDocuments;
  final DocumentModel? activeDocument;
  final List<VoiceModel> voices;
  final String selectedVoiceId;
  final String selectedLanguage; // english, marathi, hindi for TTS
  final String selectedSttLanguage; // english, marathi, hindi for STT
  final TtsResponseModel? currentTtsResponse;
  final PlayerState playerState;
  final Duration audioPosition;
  final Duration audioDuration;
  final double playbackRate;
  final bool isMuted;
  final double volume; // 0.0 to 1.0
  final bool isDownloadingAudio;
  final bool isProgressive;
  final int progressiveCurrentChunk;
  final int progressiveTotalChunks;
  final int progressiveCompletedChunks;
  final String? completeAudioUrl;
  final String? completeFilename;
  final bool isBufferingNextChunk;
  final bool isPlayingOriginalAudio;
  final String? originalAudioPath;
  final String? errorMessage;
  final String? successMessage;

  DocumentTtsState({
    this.isExtracting = false,
    this.isGeneratingSpeech = false,
    this.isLoadingVoices = false,
    this.userDocuments = const [],
    this.activeDocument,
    List<VoiceModel>? voices,
    this.selectedVoiceId = 'CwhRBWXzGAHq8TQ4Fs17',
    this.selectedLanguage = 'english',
    this.selectedSttLanguage = 'english',
    this.currentTtsResponse,
    this.playerState = PlayerState.stopped,
    this.audioPosition = Duration.zero,
    this.audioDuration = Duration.zero,
    this.playbackRate = 1.0,
    this.isMuted = false,
    this.volume = 1.0,
    this.isDownloadingAudio = false,
    this.isProgressive = false,
    this.progressiveCurrentChunk = 1,
    this.progressiveTotalChunks = 1,
    this.progressiveCompletedChunks = 0,
    this.completeAudioUrl,
    this.completeFilename,
    this.isBufferingNextChunk = false,
    this.isPlayingOriginalAudio = false,
    this.originalAudioPath,
    this.errorMessage,
    this.successMessage,
  }) : voices = voices ?? VoiceModel.defaultVoices();

  DocumentTtsState copyWith({
    bool? isExtracting,
    bool? isGeneratingSpeech,
    bool? isLoadingVoices,
    List<DocumentModel>? userDocuments,
    DocumentModel? activeDocument,
    List<VoiceModel>? voices,
    String? selectedVoiceId,
    String? selectedLanguage,
    String? selectedSttLanguage,
    TtsResponseModel? currentTtsResponse,
    bool clearTtsResponse = false,
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
  }) {
    return DocumentTtsState(
      isExtracting: isExtracting ?? this.isExtracting,
      isGeneratingSpeech: isGeneratingSpeech ?? this.isGeneratingSpeech,
      isLoadingVoices: isLoadingVoices ?? this.isLoadingVoices,
      userDocuments: userDocuments ?? this.userDocuments,
      activeDocument: activeDocument ?? this.activeDocument,
      voices: voices ?? this.voices,
      selectedVoiceId: selectedVoiceId ?? this.selectedVoiceId,
      selectedLanguage: selectedLanguage ?? this.selectedLanguage,
      selectedSttLanguage: selectedSttLanguage ?? this.selectedSttLanguage,
      currentTtsResponse: clearTtsResponse ? null : (currentTtsResponse ?? this.currentTtsResponse),
      playerState: playerState ?? this.playerState,
      audioPosition: audioPosition ?? this.audioPosition,
      audioDuration: audioDuration ?? this.audioDuration,
      playbackRate: playbackRate ?? this.playbackRate,
      isMuted: isMuted ?? this.isMuted,
      volume: volume ?? this.volume,
      isDownloadingAudio: isDownloadingAudio ?? this.isDownloadingAudio,
      isProgressive: isProgressive ?? this.isProgressive,
      progressiveCurrentChunk: progressiveCurrentChunk ?? this.progressiveCurrentChunk,
      progressiveTotalChunks: progressiveTotalChunks ?? this.progressiveTotalChunks,
      progressiveCompletedChunks: progressiveCompletedChunks ?? this.progressiveCompletedChunks,
      completeAudioUrl: completeAudioUrl ?? this.completeAudioUrl,
      completeFilename: completeFilename ?? this.completeFilename,
      isBufferingNextChunk: isBufferingNextChunk ?? this.isBufferingNextChunk,
      isPlayingOriginalAudio: isPlayingOriginalAudio ?? this.isPlayingOriginalAudio,
      originalAudioPath: clearOriginalAudio ? null : (originalAudioPath ?? this.originalAudioPath),
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

// State Notifier
class DocumentTtsNotifier extends StateNotifier<DocumentTtsState> {
  final DocumentTtsRepository _repository;
  final StorageService _storageService;
  final Ref? _ref;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _activeSessionId = '';
  String _lastBaseUrl = '';
  List<TtsResponseModel?> _progressiveAudioQueue = [];
  final Set<String> _pendingDeletions = {};

  DocumentTtsNotifier(this._repository, this._storageService, [this._ref]) : super(DocumentTtsState()) {
    _initAudioPlayer();
    _loadInitialLocalHistory();
    _applyInitialSettings();
    if (_ref != null) {
      _ref!.read(downloadsProvider.notifier).onBeforePlay = () {
        stopAudioAndClearQueue();
        stopOriginalAudio();
      };
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
      final localRaw = _storageService.getHistoryDocs();
      final localDocs = localRaw.map((e) => DocumentModel.fromJson(e)).toList();
      _updateAndPersistDocuments(localDocs);
    } catch (_) {}
  }

  void _initAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        this.state = this.state.copyWith(playerState: state);
      }
    });

    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) {
        this.state = this.state.copyWith(audioPosition: pos);
      }
    });

    _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) {
        this.state = this.state.copyWith(audioDuration: dur);
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

      // Guard: If session was invalidated or player was stopped, do NOT advance or restart playback
      if (_activeSessionId.isEmpty || state.playerState == PlayerState.stopped) {
        state = state.copyWith(
          playerState: PlayerState.completed,
          audioPosition: Duration.zero,
          isBufferingNextChunk: false,
        );
        return;
      }

      if (state.isProgressive && state.progressiveCurrentChunk < state.progressiveTotalChunks) {
        final nextIndex = state.progressiveCurrentChunk; // 0-based index of next chunk
        final nextChunkNumber = nextIndex + 1; // 1-based chunk number

        if (_progressiveAudioQueue.length > nextIndex && _progressiveAudioQueue[nextIndex] != null) {
          final nextChunk = _progressiveAudioQueue[nextIndex]!;
          final wasPaused = (state.playerState == PlayerState.paused);

          state = state.copyWith(
            progressiveCurrentChunk: nextChunkNumber,
            currentTtsResponse: nextChunk,
            audioPosition: Duration.zero,
            isBufferingNextChunk: false,
          );

          if (!wasPaused && _activeSessionId.isNotEmpty && state.playerState != PlayerState.stopped) {
            await playAudio(nextChunk.audioUrl, _lastBaseUrl);
          }
          return;
        } else {
          // Next chunk is still buffering in the background
          state = state.copyWith(
            progressiveCurrentChunk: nextChunkNumber,
            isBufferingNextChunk: true,
            playerState: PlayerState.completed,
          );
          return;
        }
      }

      state = state.copyWith(
        playerState: PlayerState.completed,
        audioPosition: Duration.zero,
        isBufferingNextChunk: false,
      );
    });
  }

  void _invalidateActiveSession() {
    _activeSessionId = '';
    _progressiveAudioQueue = [];
    _audioPlayer.stop();
  }

  /// Stops audio playback immediately and clears progressive queue.
  Future<void> stopAudio() async {
    _invalidateActiveSession();
    await _audioPlayer.stop();
    state = state.copyWith(
      playerState: PlayerState.stopped,
      audioPosition: Duration.zero,
      isPlayingOriginalAudio: false,
      isProgressive: false,
      progressiveCurrentChunk: 1,
      progressiveTotalChunks: 1,
      progressiveCompletedChunks: 0,
      isBufferingNextChunk: false,
    );
  }

  /// Stops audio playback immediately, invalidates active sessions, and wipes current TTS response.
  Future<void> stopAudioAndClearQueue() async {
    _invalidateActiveSession();
    await _audioPlayer.stop();
    state = state.copyWith(
      clearTtsResponse: true,
      playerState: PlayerState.stopped,
      isPlayingOriginalAudio: false,
      audioPosition: Duration.zero,
      audioDuration: Duration.zero,
      isProgressive: false,
      progressiveCurrentChunk: 1,
      progressiveTotalChunks: 1,
      progressiveCompletedChunks: 0,
      completeAudioUrl: null,
      completeFilename: null,
      isBufferingNextChunk: false,
    );
  }

  @visibleForTesting
  void setTtsResponseForTesting(TtsResponseModel? response) {
    state = state.copyWith(currentTtsResponse: response);
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
      _invalidateActiveSession();
      state = state.copyWith(
        selectedLanguage: clean,
        selectedVoiceId: effectiveVoice,
        clearTtsResponse: true,
        playerState: PlayerState.stopped,
        audioPosition: Duration.zero,
        audioDuration: Duration.zero,
        isProgressive: false,
        progressiveCurrentChunk: 1,
        progressiveTotalChunks: 1,
        progressiveCompletedChunks: 0,
        completeAudioUrl: null,
        completeFilename: null,
        isBufferingNextChunk: false,
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
      _invalidateActiveSession();
      state = state.copyWith(
        selectedVoiceId: voiceId,
        clearTtsResponse: true,
        playerState: PlayerState.stopped,
        audioPosition: Duration.zero,
        audioDuration: Duration.zero,
        isProgressive: false,
        progressiveCurrentChunk: 1,
        progressiveTotalChunks: 1,
        progressiveCompletedChunks: 0,
        completeAudioUrl: null,
        completeFilename: null,
        isBufferingNextChunk: false,
      );
    }
  }

  void setActiveDocument(DocumentModel doc) {
    if (doc.docId != state.activeDocument?.docId) {
      _invalidateActiveSession();
      state = state.copyWith(
        activeDocument: doc,
        selectedLanguage: doc.detectedLanguage,
        clearTtsResponse: true,
        playerState: PlayerState.stopped,
        audioPosition: Duration.zero,
        audioDuration: Duration.zero,
        isProgressive: false,
        progressiveCurrentChunk: 1,
        progressiveTotalChunks: 1,
        progressiveCompletedChunks: 0,
        completeAudioUrl: null,
        completeFilename: null,
        isBufferingNextChunk: false,
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
  void _updateAndPersistDocuments(List<DocumentModel> docs) {
    final excludedIds = _storageService.getExcludedHistoryIds();
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
      _storageService.saveHistoryDocs(docsJson);
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

  Future<void> loadUserDocuments() async {
    try {
      final excludedIds = _storageService.getExcludedHistoryIds();
      final localRaw = _storageService.getHistoryDocs();
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

      final combined = <DocumentModel>[...localDocs, ...remoteDocs, ...state.userDocuments];
      _updateAndPersistDocuments(combined);
    } catch (_) {}
  }

  /// Delete document from history with optimistic removal, account-scoped persistence, and failure rollback.
  Future<bool> deleteDocument(String docId) async {
    if (docId.isEmpty || _pendingDeletions.contains(docId)) return false;
    _pendingDeletions.add(docId);

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
      await _storageService.addExcludedHistoryId(docId);
      final docsJson = updatedList.map((d) => d.toJson()).toList();
      await _storageService.saveHistoryDocs(docsJson);
      return true;
    } catch (e) {
      // Persistence failed: rollback optimistic removal
      await _storageService.removeExcludedHistoryId(docId);
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
    state = state.copyWith(isExtracting: true, errorMessage: null, successMessage: null);
    try {
      final rawDoc = await _repository.extractDocument(filePath);
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
      _updateAndPersistDocuments(updatedDocs);
      state = state.copyWith(
        isExtracting: false,
        activeDocument: doc,
        selectedLanguage: doc.detectedLanguage,
        successMessage: 'Text extracted successfully (${doc.characterCount} chars)!',
      );
      return doc;
    } catch (e) {
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
      // 2. Retain a usable local source file in app storage for original audio playback
      String persistentAudioPath = filePath;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final audioDir = Directory('${appDir.path}/stt_audio');
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

      String transcript = '';
      List<TimedWord> timedWords = [];

      if (effectiveLang == 'marathi' || effectiveLang == 'mr' || effectiveLang == 'mr-in') {
        final res = await LocalWhisperService().transcribeAudioDetailed(
          filePath,
          language: 'mr',
        );
        transcript = res.text;
        timedWords = res.words;
      } else if (effectiveLang == 'hindi' || effectiveLang == 'hi' || effectiveLang == 'hi-in') {
        final res = await LocalWhisperService().transcribeAudioDetailed(
          filePath,
          language: 'hi',
        );
        transcript = res.text;
        timedWords = res.words;
      } else {
        // English / default -> route to existing Readora backend transcription
        final res = await _repository.transcribeAudioBackendDetailed(
          filePath,
          language: 'en',
        );
        transcript = (res['transcript'] ?? res['text'] ?? '').toString();
        if (res['words'] is List) {
          timedWords = (res['words'] as List)
              .map((w) => TimedWord.fromJson(Map<String, dynamic>.from(w as Map)))
              .toList();
        }
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
        }
      } catch (e) {
        debugPrint('Could not probe audio duration: $e');
      }

      final filename = filePath.split(RegExp(r'[/\\]')).last;
      final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : 'audio';
      final doc = DocumentModel(
        docId: 'stt_${DateTime.now().millisecondsSinceEpoch}',
        filename: filename,
        fileType: ext,
        text: transcript,
        detectedLanguage: effectiveLang,
        wordCount: transcript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
        characterCount: transcript.length,
        createdAt: DateTime.now(),
        timedWords: timedWords,
        audioSourcePath: persistentAudioPath,
      );

      final updatedDocs = [doc, ...state.userDocuments];
      _updateAndPersistDocuments(updatedDocs);
      state = state.copyWith(
        isExtracting: false,
        activeDocument: doc,
        originalAudioPath: persistentAudioPath,
        isPlayingOriginalAudio: false,
        clearTtsResponse: true,
        playerState: PlayerState.stopped,
        audioPosition: Duration.zero,
        audioDuration: probedDuration,
        successMessage: 'Audio transcribed successfully!',
      );
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
  }) async {
    final cleanText = text.trim();
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

    final sessionId = '${DateTime.now().millisecondsSinceEpoch}_${(cleanText.hashCode.abs() % 10000)}';
    _activeSessionId = sessionId;
    _lastBaseUrl = baseUrl;

    final chunks = splitTextIntoSafeChunks(cleanText, maxChunkSize: 3500);
    final totalChunks = chunks.length;

    // Reset audio player & progressive queue
    await _audioPlayer.stop();
    _progressiveAudioQueue = List.filled(totalChunks, null, growable: true);

    state = state.copyWith(
      isGeneratingSpeech: true,
      errorMessage: null,
      successMessage: null,
      isProgressive: totalChunks > 1,
      progressiveCurrentChunk: 1,
      progressiveTotalChunks: totalChunks,
      progressiveCompletedChunks: 0,
      completeAudioUrl: null,
      completeFilename: null,
      isBufferingNextChunk: false,
    );

    if (totalChunks <= 1) {
      // Single chunk: standard fast conversion
      try {
        final response = await _repository.generateSpeech(
          text: cleanText,
          language: state.selectedLanguage,
          voiceId: effectiveVoiceId,
          documentId: state.activeDocument?.docId,
          textHash: state.activeDocument?.contentHash,
        );

        if (_activeSessionId != sessionId) return null;

        state = state.copyWith(
          isGeneratingSpeech: false,
          currentTtsResponse: response,
          successMessage: 'Speech generated successfully!',
          progressiveCompletedChunks: 1,
          completeAudioUrl: response.audioUrl,
          completeFilename: response.filename,
        );

        final shouldAutoPlay = _ref?.read(settingsProvider).autoPlayTts ?? false;
        if (shouldAutoPlay) {
          await playAudio(response.audioUrl, baseUrl);
        }
        return response;
      } catch (e) {
        if (_activeSessionId != sessionId) return null;
        state = state.copyWith(
          isGeneratingSpeech: false,
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
        documentId: state.activeDocument?.docId,
        textHash: state.activeDocument?.contentHash,
        chunkIndex: 0,
        totalChunks: totalChunks,
        sessionId: sessionId,
      );

      if (_activeSessionId != sessionId) return null;

      _progressiveAudioQueue[0] = chunk0Response;

      // Stop loading spinner immediately — Chunk 0 audio is ready!
      state = state.copyWith(
        isGeneratingSpeech: false,
        currentTtsResponse: chunk0Response,
        progressiveCompletedChunks: 1,
        successMessage: 'Playing Part 1 of $totalChunks (buffering remaining in background...)',
      );

      // Begin audio playback if autoplay enabled
      final shouldAutoPlay = _ref?.read(settingsProvider).autoPlayTts ?? false;
      if (shouldAutoPlay) {
        await playAudio(chunk0Response.audioUrl, baseUrl);
      }

      // 2. Buffer subsequent chunks sequentially in the background
      _bufferSubsequentChunks(
        chunks: chunks,
        effectiveVoiceId: effectiveVoiceId,
        sessionId: sessionId,
        baseUrl: baseUrl,
      );

      return chunk0Response;
    } catch (e) {
      if (_activeSessionId != sessionId) return null;
      state = state.copyWith(
        isGeneratingSpeech: false,
        isProgressive: false,
        errorMessage: 'Failed to start speech conversion: $e',
      );
      return null;
    }
  }

  void _bufferSubsequentChunks({
    required List<String> chunks,
    required String effectiveVoiceId,
    required String sessionId,
    required String baseUrl,
  }) async {
    for (int i = 1; i < chunks.length; i++) {
      if (_activeSessionId != sessionId) break;

      int retries = 2;
      bool success = false;
      while (retries > 0 && !success && _activeSessionId == sessionId) {
        try {
          final chunkResponse = await _repository.generateSpeech(
            text: chunks[i],
            language: state.selectedLanguage,
            voiceId: effectiveVoiceId,
            documentId: state.activeDocument?.docId,
            textHash: state.activeDocument?.contentHash,
            chunkIndex: i,
            totalChunks: chunks.length,
            sessionId: sessionId,
          );

          if (_activeSessionId != sessionId) break;

          _progressiveAudioQueue[i] = chunkResponse;
          success = true;

          state = state.copyWith(
            progressiveCompletedChunks: i + 1,
            completeAudioUrl: chunkResponse.completeAudioUrl ?? state.completeAudioUrl,
            completeFilename: chunkResponse.completeFilename ?? state.completeFilename,
          );

          // If playback of previous chunk finished while waiting for this chunk:
          if (_activeSessionId == sessionId &&
              state.playerState != PlayerState.stopped &&
              state.isBufferingNextChunk &&
              state.progressiveCurrentChunk == i + 1) {
            state = state.copyWith(isBufferingNextChunk: false, currentTtsResponse: chunkResponse);
            if (state.playerState != PlayerState.paused && state.playerState != PlayerState.stopped) {
              await playAudio(chunkResponse.audioUrl, baseUrl);
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

  void resetTtsResponse() {
    _invalidateActiveSession();
    state = state.copyWith(
      clearTtsResponse: true,
      playerState: PlayerState.stopped,
      audioPosition: Duration.zero,
      audioDuration: Duration.zero,
      isProgressive: false,
      progressiveCurrentChunk: 1,
      progressiveTotalChunks: 1,
      progressiveCompletedChunks: 0,
      completeAudioUrl: null,
      completeFilename: null,
      isBufferingNextChunk: false,
    );
  }

  String resolveAudioUrl(String audioPath, String baseUrl) {
    if (audioPath.startsWith('http://') || audioPath.startsWith('https://')) {
      return audioPath;
    }
    String cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    String cleanPath = audioPath.startsWith('/') ? audioPath : '/$audioPath';

    if (cleanBase.endsWith('/api') && cleanPath.startsWith('/api/')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - 4);
    }

    return '$cleanBase$cleanPath';
  }

  Future<void> playAudio(String audioPath, String baseUrl) async {
    try {
      _lastBaseUrl = baseUrl;
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
        await playAudio(state.currentTtsResponse!.audioUrl, baseUrl);
      }
      return;
    }
    if (state.playerState == PlayerState.playing) {
      await _audioPlayer.pause();
    } else if (state.playerState == PlayerState.paused) {
      await _audioPlayer.resume();
    } else if (state.currentTtsResponse != null && state.currentTtsResponse!.audioUrl.isNotEmpty) {
      await playAudio(state.currentTtsResponse!.audioUrl, baseUrl);
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

        final downloadItem = await downloadsNotifier.saveAudioToLibrary(
          audioUrl: targetAudioUrl,
          baseUrl: baseUrl,
          displayFilename: targetFilename,
          language: state.selectedLanguage,
          sourceDocId: state.activeDocument?.docId,
          sourceDocName: state.activeDocument?.filename,
          voiceId: state.selectedVoiceId,
          voiceName: voiceName,
          generationSessionId: _activeSessionId,
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
