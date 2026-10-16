import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texttospeech/core/services/storage_service.dart';
import 'package:texttospeech/features/document_tts/data/document_tts_repository.dart';
import 'package:texttospeech/features/document_tts/domain/document_model.dart';
import 'package:texttospeech/features/document_tts/domain/tts_response_model.dart';
import 'package:texttospeech/features/document_tts/domain/voice_model.dart';
import 'package:texttospeech/features/document_tts/presentation/providers/document_tts_provider.dart';

class MockIsolationRepository implements DocumentTtsRepository {
  Completer<DocumentModel>? delayedExtractCompleter;
  List<DocumentModel> remoteUserDocs = [];

  @override
  Future<DocumentModel> extractDocument(String filePath) async {
    if (delayedExtractCompleter != null) {
      return delayedExtractCompleter!.future;
    }
    return DocumentModel(
      docId: 'doc_${DateTime.now().millisecondsSinceEpoch}',
      filename: 'alice_doc.pdf',
      text: 'Confidential Alice Content',
    );
  }

  @override
  Future<List<DocumentModel>> getUserFiles() async => remoteUserDocs;

  @override
  Future<void> deleteFile(String id) async {
    remoteUserDocs.removeWhere((d) => d.docId == id);
  }

  @override
  Future<List<VoiceModel>> fetchVoices() async => VoiceModel.defaultVoices();

  @override
  Future<String> translateText(String text, String targetLanguage, {String? sourceLanguage}) async => text;

  @override
  Future<String> transcribeAudioBackend(String filePath, {String? language}) async => 'Transcript';

  @override
  Future<Map<String, dynamic>> transcribeAudioBackendDetailed(String filePath, {String? language}) async => {
        'transcript': 'Transcript',
        'words': [],
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
    return TtsResponseModel(
      success: true,
      audioUrl: '/api/files/audio/speech.mp3',
      filename: 'speech.mp3',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (MethodCall call) async {
      return 1;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global'), (MethodCall call) async {
      return 1;
    });
  });

  group('Cross-Account History & State Isolation Tests', () {
    late MockIsolationRepository mockRepository;
    late StorageService storageService;
    late DocumentTtsNotifier notifier;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storageService = StorageService(prefs);
      mockRepository = MockIsolationRepository();
      notifier = DocumentTtsNotifier(mockRepository, storageService);
    });

    test('User A logs in, adds documents, and documents are persisted under User A key', () async {
      await notifier.switchUser('user_alice_123');

      final docAlice = await notifier.extractDocument('alice_file.pdf');
      expect(docAlice, isNotNull);
      expect(notifier.state.userDocuments.length, equals(1));
      expect(notifier.state.userDocuments.first.docId, equals(docAlice!.docId));

      // Check SharedPreferences scoping
      final aliceDocsRaw = storageService.getHistoryDocs('user_alice_123');
      expect(aliceDocsRaw.length, equals(1));
      expect(aliceDocsRaw.first['docId'], equals(docAlice.docId));

      // Global or un-scoped key must be empty
      final guestDocs = storageService.getHistoryDocs('guest');
      expect(guestDocs, isEmpty);
    });

    test('On logout, clearUserData() completely flushes in-memory state and active player', () async {
      await notifier.switchUser('user_alice_123');
      final docAlice = await notifier.extractDocument('alice_file.pdf');
      expect(notifier.state.userDocuments, isNotEmpty);

      // Perform logout
      await notifier.clearUserData();

      expect(notifier.state.userDocuments, isEmpty);
      expect(notifier.state.activeDocument, isNull);
      expect(notifier.state.originalAudioPath, isNull);
      expect(notifier.activeUserId, isNull);
    });

    test('User B logs in on same device and sees 0 of User A documents', () async {
      // Step 1: Alice creates document
      await notifier.switchUser('user_alice_123');
      final docAlice = await notifier.extractDocument('alice_file.pdf');
      expect(docAlice, isNotNull);

      // Step 2: Alice logs out
      await notifier.clearUserData();
      expect(notifier.state.userDocuments, isEmpty);

      // Step 3: Bob logs in
      mockRepository.remoteUserDocs = []; // Bob has no remote docs yet
      await notifier.switchUser('user_bob_456');

      expect(notifier.activeUserId, equals('user_bob_456'));
      expect(notifier.state.userDocuments, isEmpty);

      // Step 4: Bob creates his own document
      final docBob = await notifier.extractDocument('bob_notes.pdf');
      expect(docBob, isNotNull);
      expect(notifier.state.userDocuments.length, equals(1));
      expect(notifier.state.userDocuments.first.docId, equals(docBob!.docId));

      // Bob's cache has only Bob's doc
      final bobDocs = storageService.getHistoryDocs('user_bob_456');
      expect(bobDocs.length, equals(1));
      expect(bobDocs.first['docId'], equals(docBob.docId));

      // Alice's cache still has only Alice's doc
      final aliceDocs = storageService.getHistoryDocs('user_alice_123');
      expect(aliceDocs.length, equals(1));
      expect(aliceDocs.first['docId'], equals(docAlice!.docId));

      // Step 5: Bob logs out and Alice logs back in
      await notifier.clearUserData();
      await notifier.switchUser('user_alice_123');

      expect(notifier.state.userDocuments.length, equals(1));
      expect(notifier.state.userDocuments.first.docId, equals(docAlice.docId));
      expect(notifier.state.userDocuments.any((d) => d.docId == docBob.docId), isFalse);
    });

    test('Late response guard: In-flight extraction from Session A does not populate Session B', () async {
      await notifier.switchUser('user_alice_123');

      final completer = Completer<DocumentModel>();
      mockRepository.delayedExtractCompleter = completer;

      // Alice starts an extraction that hangs
      final extractionFuture = notifier.extractDocument('heavy_alice.pdf');

      // Before it completes, Alice logs out and Bob logs in
      await notifier.clearUserData();
      await notifier.switchUser('user_bob_456');

      // Now the delayed response arrives from the server
      completer.complete(DocumentModel(
        docId: 'late_alice_doc',
        filename: 'heavy_alice.pdf',
        text: 'Alice late content',
      ));

      final result = await extractionFuture;

      // The returned result for the stale request should be null
      expect(result, isNull);

      // And Bob's state must NOT contain Alice's late document
      expect(notifier.state.userDocuments, isEmpty);
      expect(storageService.getHistoryDocs('user_bob_456'), isEmpty);
    });

    test('resolveAudioUrl appends ?token= for authenticated audio streaming', () async {
      await storageService.saveToken('jwt_alice_secret_token');

      final url = notifier.resolveAudioUrl('api/files/audio/sample.mp3', 'http://127.0.0.1:5000');
      expect(url, contains('token=jwt_alice_secret_token'));
      expect(url, equals('http://127.0.0.1:5000/api/files/audio/sample.mp3?token=jwt_alice_secret_token'));
    });
  });
}
