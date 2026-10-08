import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../core/services/local_whisper_service.dart';
import '../../data/document_tts_repository.dart';
import '../../domain/document_model.dart';
import '../../domain/tts_response_model.dart';
import '../../domain/voice_model.dart';

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
  final String selectedLanguage; // english, marathi, hindi
  final TtsResponseModel? currentTtsResponse;
  final PlayerState playerState;
  final Duration audioPosition;
  final Duration audioDuration;
  final double playbackRate;
  final String? errorMessage;
  final String? successMessage;

  DocumentTtsState({
    this.isExtracting = false,
    this.isGeneratingSpeech = false,
    this.isLoadingVoices = false,
    this.userDocuments = const [],
    this.activeDocument,
    List<VoiceModel>? voices,
    this.selectedVoiceId = 'default',
    this.selectedLanguage = 'english',
    this.currentTtsResponse,
    this.playerState = PlayerState.stopped,
    this.audioPosition = Duration.zero,
    this.audioDuration = Duration.zero,
    this.playbackRate = 1.0,
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
    TtsResponseModel? currentTtsResponse,
    bool clearTtsResponse = false,
    PlayerState? playerState,
    Duration? audioPosition,
    Duration? audioDuration,
    double? playbackRate,
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
      currentTtsResponse: clearTtsResponse ? null : (currentTtsResponse ?? this.currentTtsResponse),
      playerState: playerState ?? this.playerState,
      audioPosition: audioPosition ?? this.audioPosition,
      audioDuration: audioDuration ?? this.audioDuration,
      playbackRate: playbackRate ?? this.playbackRate,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

// State Notifier
class DocumentTtsNotifier extends StateNotifier<DocumentTtsState> {
  final DocumentTtsRepository _repository;
  final StorageService _storageService;
  final AudioPlayer _audioPlayer = AudioPlayer();

  DocumentTtsNotifier(this._repository, this._storageService) : super(DocumentTtsState()) {
    _initAudioPlayer();
    _loadInitialLocalHistory();
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

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        this.state = this.state.copyWith(
          playerState: PlayerState.completed,
          audioPosition: Duration.zero,
        );
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void setSelectedLanguage(String lang) {
    state = state.copyWith(selectedLanguage: lang);
  }

  void setSelectedVoice(String voiceId) {
    state = state.copyWith(selectedVoiceId: voiceId);
  }

  void setActiveDocument(DocumentModel doc) {
    state = state.copyWith(
      activeDocument: doc,
      selectedLanguage: doc.detectedLanguage,
    );
  }

  /// Auto-deletes history items older than 30 days, deduplicates, sorts by date, updates state & persists to storage.
  void _updateAndPersistDocuments(List<DocumentModel> docs) {
    final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
    final validDocs = docs.where((doc) {
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
          createdAt: existing.createdAt ?? doc.createdAt ?? DateTime.now(),
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
      state = state.copyWith(
        voices: voices.isNotEmpty ? voices : VoiceModel.defaultVoices(),
        isLoadingVoices: false,
      );
    } catch (_) {
      state = state.copyWith(
        voices: VoiceModel.defaultVoices(),
        isLoadingVoices: false,
      );
    }
  }

  Future<void> loadUserDocuments() async {
    try {
      final localRaw = _storageService.getHistoryDocs();
      final localDocs = localRaw.map((e) => DocumentModel.fromJson(e)).toList();

      List<DocumentModel> remoteDocs = [];
      try {
        remoteDocs = await _repository.getUserFiles();
      } catch (_) {}

      final combined = <DocumentModel>[...localDocs, ...remoteDocs, ...state.userDocuments];
      _updateAndPersistDocuments(combined);
    } catch (_) {}
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
  Future<DocumentModel?> transcribeAudioFile(String filePath) async {
    state = state.copyWith(isExtracting: true, errorMessage: null, successMessage: null);
    try {
      final lang = state.selectedLanguage.toLowerCase();
      String transcript = '';

      if (lang == 'marathi' || lang == 'mr' || lang == 'mr-in') {
        transcript = await LocalWhisperService().transcribeAudio(
          filePath,
          language: 'mr',
        );
      } else if (lang == 'hindi' || lang == 'hi' || lang == 'hi-in') {
        transcript = await LocalWhisperService().transcribeAudio(
          filePath,
          language: 'hi',
        );
      } else {
        // English / default -> route to existing Readora backend transcription
        transcript = await _repository.transcribeAudioBackend(
          filePath,
          language: 'en',
        );
      }

      final filename = filePath.split(RegExp(r'[/\\]')).last;
      final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : 'audio';
      final doc = DocumentModel(
        docId: 'stt_${DateTime.now().millisecondsSinceEpoch}',
        filename: filename,
        fileType: ext,
        text: transcript,
        detectedLanguage: state.selectedLanguage,
        wordCount: transcript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
        characterCount: transcript.length,
        createdAt: DateTime.now(),
      );

      final updatedDocs = [doc, ...state.userDocuments];
      _updateAndPersistDocuments(updatedDocs);
      state = state.copyWith(
        isExtracting: false,
        activeDocument: doc,
        successMessage: 'Audio transcribed successfully!',
      );
      return doc;
    } catch (e) {
      state = state.copyWith(
        isExtracting: false,
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

  Future<TtsResponseModel?> generateSpeech({
    required String text,
    required String baseUrl,
  }) async {
    if (text.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Please enter or extract text first');
      return null;
    }

    state = state.copyWith(isGeneratingSpeech: true, errorMessage: null, successMessage: null);
    try {
      final response = await _repository.generateSpeech(
        text: text,
        language: state.selectedLanguage,
        voiceId: state.selectedVoiceId,
        documentId: state.activeDocument?.docId,
      );

      state = state.copyWith(
        isGeneratingSpeech: false,
        currentTtsResponse: response,
        successMessage: 'Speech generated successfully!',
      );

      // Play generated audio automatically
      await playAudio(response.audioUrl, baseUrl);

      return response;
    } catch (e) {
      state = state.copyWith(
        isGeneratingSpeech: false,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  void resetTtsResponse() {
    _audioPlayer.stop();
    state = state.copyWith(
      clearTtsResponse: true,
      playerState: PlayerState.stopped,
      audioPosition: Duration.zero,
      audioDuration: Duration.zero,
    );
  }

  Future<void> playAudio(String audioPath, String baseUrl) async {
    try {
      final String fullUrl;
      if (audioPath.startsWith('http://') || audioPath.startsWith('https://')) {
        fullUrl = audioPath;
      } else {
        final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
        final cleanPath = audioPath.startsWith('/') ? audioPath : '/$audioPath';
        fullUrl = '$cleanBase$cleanPath';
      }
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(fullUrl));
    } catch (e) {
      state = state.copyWith(errorMessage: 'Audio playback error: $e');
    }
  }

  Future<void> togglePlayPause(String baseUrl) async {
    if (state.playerState == PlayerState.playing) {
      await _audioPlayer.pause();
    } else if (state.playerState == PlayerState.paused) {
      await _audioPlayer.resume();
    } else if (state.currentTtsResponse != null && state.currentTtsResponse!.audioUrl.isNotEmpty) {
      await playAudio(state.currentTtsResponse!.audioUrl, baseUrl);
    }
  }

  Future<void> pauseAudio() async {
    await _audioPlayer.pause();
  }

  Future<void> resumeAudio() async {
    await _audioPlayer.resume();
  }

  Future<void> stopAudio() async {
    await _audioPlayer.stop();
  }

  Future<void> seekAudio(Duration duration) async {
    await _audioPlayer.seek(duration);
  }

  Future<void> setPlaybackRate(double rate) async {
    await _audioPlayer.setPlaybackRate(rate);
    state = state.copyWith(playbackRate: rate);
  }
}

// Provider
final documentTtsNotifierProvider =
    StateNotifierProvider<DocumentTtsNotifier, DocumentTtsState>((ref) {
  final repository = ref.watch(documentTtsRepositoryProvider);
  final storageService = ref.watch(storageServiceProvider);
  return DocumentTtsNotifier(repository, storageService);
});
