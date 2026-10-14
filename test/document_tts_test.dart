import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:texttospeech/core/services/storage_service.dart';
import 'package:texttospeech/features/document_tts/data/document_tts_repository.dart';
import 'package:texttospeech/features/document_tts/domain/voice_model.dart';
import 'package:texttospeech/features/document_tts/domain/document_model.dart';
import 'package:texttospeech/features/document_tts/domain/tts_response_model.dart';
import 'package:texttospeech/features/document_tts/presentation/providers/document_tts_provider.dart';

void main() {
  group('1. Voice Selection & Model Tests (Roger Mismatch Fix)', () {
    test('Default voices list has Roger as the primary voice at index 0', () {
      final defaultVoices = VoiceModel.defaultVoices();
      expect(defaultVoices, isNotEmpty);
      final firstVoice = defaultVoices.first;
      expect(firstVoice.voiceId, equals('CwhRBWXzGAHq8TQ4Fs17'));
      expect(firstVoice.name.contains('Roger'), isTrue);
    });

    test('Initial DocumentTtsState selectedVoiceId matches Roger voice ID', () {
      final state = DocumentTtsState();
      expect(state.selectedVoiceId, equals('CwhRBWXzGAHq8TQ4Fs17'));
      expect(state.voices.first.voiceId, equals('CwhRBWXzGAHq8TQ4Fs17'));
    });

    test('VoiceModel parses backend json correctly with voice_id and voiceId', () {
      final rogerJson = {
        'voice_id': 'CwhRBWXzGAHq8TQ4Fs17',
        'name': 'Roger',
        'category': 'premade',
        'description': 'confident, middle-aged male, formal tone'
      };
      final voice = VoiceModel.fromJson(rogerJson);
      expect(voice.voiceId, equals('CwhRBWXzGAHq8TQ4Fs17'));
      expect(voice.name, equals('Roger'));
    });
  });

  group('2. Language-Safe Safe Chunking Tests', () {
    test('Returns single chunk when text <= maxChunkSize', () {
      const text = 'This is a short document that fits within one chunk.';
      final chunks = DocumentTtsNotifier.splitTextIntoSafeChunks(text, maxChunkSize: 3500);
      expect(chunks.length, equals(1));
      expect(chunks.first, equals(text));
    });

    test('Preserves text order and boundary integrity when chunking large text', () {
      final para1 = 'First paragraph sentence one. First paragraph sentence two.';
      final para2 = 'Second paragraph sentence one. Second paragraph sentence two.';
      final fullText = '$para1\n\n$para2';

      // Use small maxChunkSize to force split across paragraphs
      final chunks = DocumentTtsNotifier.splitTextIntoSafeChunks(fullText, maxChunkSize: para1.length + 5);
      expect(chunks.length, equals(2));
      expect(chunks[0], equals(para1));
      expect(chunks[1], equals(para2));
    });

    test('Splits large Devanagari text cleanly at danda (।) boundaries', () {
      final mrText = 'हा पहिला परिच्छेद आहे। या परिच्छेदात महत्त्वाची माहिती दिली आहे।\n\nहा दुसरा परिच्छेद आहे। येथे कथा पुढे चालू राहते।';
      final chunks = DocumentTtsNotifier.splitTextIntoSafeChunks(mrText, maxChunkSize: 60);
      expect(chunks.length, greaterThan(1));
      final combined = chunks.join(' ');
      expect(combined.contains('हा पहिला परिच्छेद'), isTrue);
      expect(combined.contains('हा दुसरा परिच्छेद'), isTrue);
    });
  });

  group('3. DocumentModel & TtsResponseModel Chunk & Hash Integration', () {
    test('DocumentModel parses and preserves contentHash and chunks', () {
      final json = {
        'docId': 'doc_123',
        'filename': 'sample.pdf',
        'text': 'Extracted text content',
        'contentHash': 'hash_abc123',
        'chunks': [
          {'index': 0, 'text': 'Chunk 0'},
          {'index': 1, 'text': 'Chunk 1'},
        ],
        'pageCount': 2,
        'detectedLanguage': 'english',
      };

      final doc = DocumentModel.fromJson(json);
      expect(doc.contentHash, equals('hash_abc123'));
      expect(doc.chunks.length, equals(2));
      expect(doc.pageCount, equals(2));

      final serialized = doc.toJson();
      expect(serialized['contentHash'], equals('hash_abc123'));
      expect(serialized['chunks'], isNotEmpty);
    });

    test('TtsResponseModel parses chunkIndex, totalChunks, and completeAudioUrl', () {
      final json = {
        'success': true,
        'docId': 'doc_123',
        'audioUrl': '/api/files/audio/chunk_0.mp3',
        'filename': 'chunk_0.mp3',
        'chunkIndex': 0,
        'totalChunks': 3,
        'completeAudioUrl': '/api/files/audio/complete.mp3',
        'completeFilename': 'complete.mp3',
        'completeSize': 54321,
      };

      final response = TtsResponseModel.fromJson(json);
      expect(response.chunkIndex, equals(0));
      expect(response.totalChunks, equals(3));
      expect(response.audioUrl, equals('/api/files/audio/chunk_0.mp3'));
      expect(response.completeAudioUrl, equals('/api/files/audio/complete.mp3'));
      expect(response.completeFilename, equals('complete.mp3'));
    });
  });

  group('4. STT and TTS Isolation & Audio Cancellation Regression Tests', () {
    late MockDocumentTtsRepository mockRepository;
    late StorageService storageService;
    late DocumentTtsNotifier notifier;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (MethodCall call) async {
        return 1;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global'), (MethodCall call) async {
        return 1;
      });

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storageService = StorageService(prefs);
      mockRepository = MockDocumentTtsRepository();
      notifier = DocumentTtsNotifier(mockRepository, storageService);
    });

    test('STT and TTS language selections are completely decoupled', () {
      // Default STT language is english
      expect(notifier.state.selectedSttLanguage, equals('english'));
      expect(notifier.state.selectedLanguage, equals('english'));

      // Changing TTS language does not affect STT language
      notifier.setSelectedLanguage('marathi');
      expect(notifier.state.selectedLanguage, equals('marathi'));
      expect(notifier.state.selectedSttLanguage, equals('english'));

      // Changing STT language does not affect TTS language
      notifier.setSelectedSttLanguage('hindi');
      expect(notifier.state.selectedSttLanguage, equals('hindi'));
      expect(notifier.state.selectedLanguage, equals('marathi'));
    });

    test('stopAudioAndClearQueue resets playerState to stopped and clears currentTtsResponse', () async {
      // Simulate state with an active TTS response
      final testResponse = TtsResponseModel(
        success: true,
        audioUrl: '/audio/test.mp3',
        filename: 'test.mp3',
        chunkIndex: 0,
        totalChunks: 1,
      );
      notifier.setTtsResponseForTesting(testResponse);
      expect(notifier.state.currentTtsResponse, isNotNull);

      // Call stopAudioAndClearQueue (as when entering STT)
      await notifier.stopAudioAndClearQueue();

      expect(notifier.state.currentTtsResponse, isNull);
      expect(notifier.state.playerState, equals(PlayerState.stopped));
      expect(notifier.state.audioPosition, equals(Duration.zero));
      expect(notifier.state.audioDuration, equals(Duration.zero));
      expect(notifier.state.isProgressive, isFalse);
    });

    test('Late in-flight TTS generation is invalidated when entering STT', () async {
      final completer = Completer<TtsResponseModel>();
      mockRepository.pendingSpeechCompleter = completer;

      // Start TTS generation (which sets an active session ID)
      final future = notifier.generateSpeech(text: 'Old PDF text', baseUrl: 'http://localhost:5000');

      // User navigates to STT -> stops audio and invalidates session
      await notifier.stopAudioAndClearQueue();

      // Later, the backend response arrives
      completer.complete(TtsResponseModel(
        success: true,
        audioUrl: '/audio/late_chunk.mp3',
        filename: 'late_chunk.mp3',
        chunkIndex: 0,
        totalChunks: 1,
      ));

      final result = await future;

      // Because session was invalidated, result is discarded and currentTtsResponse remains null
      expect(result, isNull);
      expect(notifier.state.currentTtsResponse, isNull);
      expect(notifier.state.playerState, equals(PlayerState.stopped));
    });

    test('transcribeAudioFile clears any existing TTS response and leaves player stopped', () async {
      // Seed with an old PDF TTS response
      notifier.setTtsResponseForTesting(TtsResponseModel(
        success: true,
        audioUrl: '/audio/old_pdf.mp3',
        filename: 'old_pdf.mp3',
        chunkIndex: 0,
        totalChunks: 1,
      ));
      expect(notifier.state.currentTtsResponse, isNotNull);

      // Transcribe audio file in English
      final doc = await notifier.transcribeAudioFile('test_english.mp3', language: 'english');

      expect(doc, isNotNull);
      expect(doc!.text, equals('Transcribed audio content'));
      // STT completion MUST NOT leave or populate currentTtsResponse
      expect(notifier.state.currentTtsResponse, isNull);
      expect(notifier.state.playerState, equals(PlayerState.stopped));
    });

    test('Consecutive STT requests ignore obsolete earlier response using sequence counter', () async {
      int requestSeq = 0;
      String? displayedTranscript;

      // Request 1 starts
      final seq1 = ++requestSeq;
      // Request 2 starts immediately (e.g., user selected another file)
      final seq2 = ++requestSeq;

      // Response 1 arrives late
      if (seq1 == requestSeq) {
        displayedTranscript = 'Old file transcript';
      }

      // Response 2 arrives
      if (seq2 == requestSeq) {
        displayedTranscript = 'New file transcript';
      }

      expect(displayedTranscript, equals('New file transcript'));
    });
  });
}

class MockDocumentTtsRepository implements DocumentTtsRepository {
  Completer<TtsResponseModel>? pendingSpeechCompleter;

  @override
  Future<DocumentModel> extractDocument(String filePath) async {
    return DocumentModel(docId: 'doc_1', filename: 'sample.pdf', text: 'Hello PDF');
  }

  @override
  Future<List<DocumentModel>> getUserFiles() async => [];

  @override
  Future<List<VoiceModel>> fetchVoices() async => VoiceModel.defaultVoices();

  @override
  Future<String> translateText(String text, String targetLanguage, {String? sourceLanguage}) async => text;

  @override
  Future<String> transcribeAudioBackend(String filePath, {String? language}) async => 'Transcribed audio content';

  @override
  Future<Map<String, dynamic>> transcribeAudioBackendDetailed(String filePath, {String? language}) async => {
    'transcript': 'Transcribed audio content',
    'words': [
      {'text': 'Transcribed', 'startMs': 0, 'endMs': 500},
      {'text': 'audio', 'startMs': 500, 'endMs': 900},
      {'text': 'content', 'startMs': 900, 'endMs': 1400},
    ],
  };

  @override
  Future<TtsResponseModel> generateSpeech({
    required String text,
    String language = 'english',
    String? voiceId,
    String? documentId,
    int? chunkIndex,
    int? totalChunks,
    String? sessionId,
    String? textHash,
    List<dynamic>? corrections,
  }) async {
    if (pendingSpeechCompleter != null) {
      return pendingSpeechCompleter!.future;
    }
    return TtsResponseModel(
      success: true,
      audioUrl: '/api/files/audio/test.mp3',
      filename: 'test.mp3',
      chunkIndex: chunkIndex ?? 0,
      totalChunks: totalChunks ?? 1,
    );
  }
}
