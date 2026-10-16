import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:texttospeech/core/services/storage_service.dart';
import 'package:texttospeech/features/document_tts/data/document_tts_repository.dart';
import 'package:texttospeech/features/document_tts/domain/voice_model.dart';
import 'package:texttospeech/features/document_tts/domain/document_model.dart';
import 'package:texttospeech/features/document_tts/domain/tts_response_model.dart';
import 'package:texttospeech/features/document_tts/presentation/providers/document_tts_provider.dart';
import 'package:texttospeech/features/document_tts/presentation/screens/pdf_upload_screen.dart';
import 'package:texttospeech/features/auth/presentation/providers/auth_provider.dart';
import 'package:texttospeech/features/document_tts/presentation/widgets/readora_audio_player.dart';

class MockTtsRepository implements DocumentTtsRepository {
  Completer<TtsResponseModel>? pendingSpeechCompleter;
  final Map<String, Completer<TtsResponseModel>> textCompleters = {};
  int generateCallCount = 0;
  String? lastText;
  String? lastDocumentId;

  @override
  Future<DocumentModel> extractDocument(String filePath) async {
    return DocumentModel(docId: 'doc_1', filename: 'sample.pdf', text: 'Sample document text');
  }

  @override
  Future<List<DocumentModel>> getUserFiles() async => [];

  @override
  Future<void> deleteFile(String id) async {}

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
    generateCallCount++;
    lastText = text;
    lastDocumentId = documentId;
    if (textCompleters.containsKey(text)) {
      return textCompleters[text]!.future;
    }
    if (pendingSpeechCompleter != null) {
      return pendingSpeechCompleter!.future;
    }
    return TtsResponseModel(
      success: true,
      audioUrl: '/audio/test_${chunkIndex ?? 0}.mp3',
      filename: 'test_${chunkIndex ?? 0}.mp3',
      chunkIndex: chunkIndex ?? 0,
      totalChunks: totalChunks ?? 1,
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

  group('TTS Tab State Isolation Tests', () {
    late MockTtsRepository mockRepository;
    late StorageService storageService;
    late DocumentTtsNotifier notifier;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storageService = StorageService(prefs);
      mockRepository = MockTtsRepository();
      notifier = DocumentTtsNotifier(mockRepository, storageService);
    });

    test('Document-generated audio does NOT leak into Enter Text', () async {
      // 1. Generate speech on Document tab
      notifier.setTtsResponseForTesting(
        TtsResponseModel(
          success: true,
          audioUrl: '/audio/doc_audio.mp3',
          filename: 'doc_audio.mp3',
          chunkIndex: 0,
          totalChunks: 1,
        ),
        source: TtsInputSource.document,
      );

      expect(notifier.state.activeTtsTab, equals(TtsInputSource.document));
      expect(notifier.state.documentTtsResponse, isNotNull);
      expect(notifier.state.currentTtsResponse, isNotNull);
      expect(notifier.state.textTtsResponse, isNull);

      // 2. Switch to Enter Text tab
      await notifier.switchTtsTab(TtsInputSource.text);

      expect(notifier.state.activeTtsTab, equals(TtsInputSource.text));
      // In Enter Text: currentTtsResponse MUST be null!
      expect(notifier.state.currentTtsResponse, isNull);
      expect(notifier.state.textTtsResponse, isNull);
      // Document response is safely preserved in its own slot
      expect(notifier.state.documentTtsResponse, isNotNull);

      // 3. Switch back to Document tab
      await notifier.switchTtsTab(TtsInputSource.document);

      expect(notifier.state.activeTtsTab, equals(TtsInputSource.document));
      expect(notifier.state.currentTtsResponse, isNotNull);
      expect(notifier.state.currentTtsResponse!.filename, equals('doc_audio.mp3'));
    });

    test('Typed-text audio does NOT leak into Upload Document', () async {
      // 1. Switch to text tab and seed text TTS response
      await notifier.switchTtsTab(TtsInputSource.text);
      notifier.setTtsResponseForTesting(
        TtsResponseModel(
          success: true,
          audioUrl: '/audio/text_audio.mp3',
          filename: 'text_audio.mp3',
          chunkIndex: 0,
          totalChunks: 1,
        ),
        source: TtsInputSource.text,
      );

      expect(notifier.state.activeTtsTab, equals(TtsInputSource.text));
      expect(notifier.state.textTtsResponse, isNotNull);
      expect(notifier.state.currentTtsResponse, isNotNull);
      expect(notifier.state.documentTtsResponse, isNull);

      // 2. Switch to Document tab
      await notifier.switchTtsTab(TtsInputSource.document);

      expect(notifier.state.activeTtsTab, equals(TtsInputSource.document));
      // In Document: currentTtsResponse MUST be null!
      expect(notifier.state.currentTtsResponse, isNull);
      expect(notifier.state.documentTtsResponse, isNull);
      expect(notifier.state.textTtsResponse, isNotNull);

      // 3. Switch back to Enter Text tab
      await notifier.switchTtsTab(TtsInputSource.text);

      expect(notifier.state.activeTtsTab, equals(TtsInputSource.text));
      expect(notifier.state.currentTtsResponse, isNotNull);
      expect(notifier.state.currentTtsResponse!.filename, equals('text_audio.mp3'));
    });

    test('Playback stops on tab switch in both directions and does not auto-resume', () async {
      // 1. Start playback on Document tab
      notifier.setPlayerStateForTesting(PlayerState.playing, source: TtsInputSource.document);
      expect(notifier.state.playerState, equals(PlayerState.playing));

      // 2. Switch to Enter Text tab -> playback MUST stop
      await notifier.switchTtsTab(TtsInputSource.text);
      expect(notifier.state.playerState, equals(PlayerState.stopped));
      expect(notifier.state.documentTabState.playerState, equals(PlayerState.stopped));
      expect(notifier.state.textTabState.playerState, equals(PlayerState.stopped));

      // 3. Switch back to Document tab -> MUST NOT auto-resume
      await notifier.switchTtsTab(TtsInputSource.document);
      expect(notifier.state.playerState, equals(PlayerState.stopped));

      // 4. Test reverse direction: Text tab playing -> switch to Document
      await notifier.switchTtsTab(TtsInputSource.text);
      notifier.setPlayerStateForTesting(PlayerState.playing, source: TtsInputSource.text);
      expect(notifier.state.playerState, equals(PlayerState.playing));

      await notifier.switchTtsTab(TtsInputSource.document);
      expect(notifier.state.playerState, equals(PlayerState.stopped));

      await notifier.switchTtsTab(TtsInputSource.text);
      expect(notifier.state.playerState, equals(PlayerState.stopped));
    });

    test('Switching tabs during Document speech generation binds response to Document tab only', () async {
      final completer = Completer<TtsResponseModel>();
      mockRepository.pendingSpeechCompleter = completer;

      // User starts Document generation
      final genFuture = notifier.generateSpeech(
        text: 'Document content',
        baseUrl: 'http://localhost:5000',
        source: TtsInputSource.document,
      );

      expect(notifier.state.isGeneratingDocumentSpeech, isTrue);

      // User switches to Enter Text tab during generation
      await notifier.switchTtsTab(TtsInputSource.text);
      // In Enter Text: isGeneratingSpeech must be FALSE
      expect(notifier.state.isGeneratingSpeech, isFalse);
      expect(notifier.state.isGeneratingTextSpeech, isFalse);
      expect(notifier.state.isGeneratingDocumentSpeech, isTrue);

      // Backend completes the document speech request
      completer.complete(TtsResponseModel(
        success: true,
        audioUrl: '/audio/doc_result.mp3',
        filename: 'doc_result.mp3',
        chunkIndex: 0,
        totalChunks: 1,
      ));

      final result = await genFuture;
      expect(result, isNotNull);

      // Currently on Text tab: text state MUST NOT have received the document response
      expect(notifier.state.activeTtsTab, equals(TtsInputSource.text));
      expect(notifier.state.currentTtsResponse, isNull);
      expect(notifier.state.textTtsResponse, isNull);
      expect(notifier.state.playerState, equals(PlayerState.stopped));

      // Document tab state received the response
      expect(notifier.state.documentTtsResponse, isNotNull);
      expect(notifier.state.documentTtsResponse!.filename, equals('doc_result.mp3'));
      expect(notifier.state.documentTabState.isGenerating, isFalse);

      // Switching back to Document tab displays the result
      await notifier.switchTtsTab(TtsInputSource.document);
      expect(notifier.state.currentTtsResponse, isNotNull);
      expect(notifier.state.currentTtsResponse!.filename, equals('doc_result.mp3'));
    });

    test('Switching tabs during Enter Text speech generation binds response to Text tab only', () async {
      final completer = Completer<TtsResponseModel>();
      mockRepository.pendingSpeechCompleter = completer;

      await notifier.switchTtsTab(TtsInputSource.text);

      // User starts Enter Text generation
      final genFuture = notifier.generateSpeech(
        text: 'Typed text content',
        baseUrl: 'http://localhost:5000',
        source: TtsInputSource.text,
      );

      expect(notifier.state.isGeneratingTextSpeech, isTrue);

      // User switches to Document tab during generation
      await notifier.switchTtsTab(TtsInputSource.document);
      expect(notifier.state.isGeneratingSpeech, isFalse);
      expect(notifier.state.isGeneratingDocumentSpeech, isFalse);
      expect(notifier.state.isGeneratingTextSpeech, isTrue);

      // Backend completes the text speech request
      completer.complete(TtsResponseModel(
        success: true,
        audioUrl: '/audio/text_result.mp3',
        filename: 'text_result.mp3',
        chunkIndex: 0,
        totalChunks: 1,
      ));

      final result = await genFuture;
      expect(result, isNotNull);

      // Currently on Document tab: document state MUST NOT have received text response
      expect(notifier.state.activeTtsTab, equals(TtsInputSource.document));
      expect(notifier.state.currentTtsResponse, isNull);
      expect(notifier.state.documentTtsResponse, isNull);

      // Text tab received the response
      expect(notifier.state.textTtsResponse, isNotNull);
      expect(notifier.state.textTtsResponse!.filename, equals('text_result.mp3'));

      // Switch back to Text tab
      await notifier.switchTtsTab(TtsInputSource.text);
      expect(notifier.state.currentTtsResponse, isNotNull);
      expect(notifier.state.currentTtsResponse!.filename, equals('text_result.mp3'));
    });

    test('Late response from superseded request ID is discarded', () async {
      final req1Completer = Completer<TtsResponseModel>();
      final req2Completer = Completer<TtsResponseModel>();
      mockRepository.textCompleters['First text'] = req1Completer;
      mockRepository.textCompleters['Second text'] = req2Completer;

      // Request 1 starts
      final future1 = notifier.generateSpeech(
        text: 'First text',
        baseUrl: 'http://localhost:5000',
        source: TtsInputSource.document,
      );

      // Request 2 starts immediately for document tab
      final future2 = notifier.generateSpeech(
        text: 'Second text',
        baseUrl: 'http://localhost:5000',
        source: TtsInputSource.document,
      );

      // Request 1 finishes late
      req1Completer.complete(TtsResponseModel(
        success: true,
        audioUrl: '/audio/req1.mp3',
        filename: 'req1.mp3',
        chunkIndex: 0,
        totalChunks: 1,
      ));
      final res1 = await future1;
      // Stale response must be discarded
      expect(res1, isNull);

      // Request 2 completes
      req2Completer.complete(TtsResponseModel(
        success: true,
        audioUrl: '/audio/req2.mp3',
        filename: 'req2.mp3',
        chunkIndex: 0,
        totalChunks: 1,
      ));
      final res2 = await future2;
      expect(res2, isNotNull);
      expect(notifier.state.documentTtsResponse!.filename, equals('req2.mp3'));
    });

    test('Shared language & voice preferences remain shared while generated content stays separate', () async {
      // Seed responses in both tabs
      notifier.setTtsResponseForTesting(
        TtsResponseModel(success: true, audioUrl: '/audio/doc.mp3', filename: 'doc.mp3', chunkIndex: 0, totalChunks: 1),
        source: TtsInputSource.document,
      );
      notifier.setTtsResponseForTesting(
        TtsResponseModel(success: true, audioUrl: '/audio/text.mp3', filename: 'text.mp3', chunkIndex: 0, totalChunks: 1),
        source: TtsInputSource.text,
      );

      // Switch to Enter Text tab and change language
      await notifier.switchTtsTab(TtsInputSource.text);
      notifier.setSelectedLanguage('marathi', voiceId: 'marathi_voice_1');

      // Shared language & voice preferences updated
      expect(notifier.state.selectedLanguage, equals('marathi'));
      expect(notifier.state.selectedVoiceId, equals('marathi_voice_1'));

      // Active tab (Text) had its response cleared for regeneration with new voice
      expect(notifier.state.textTtsResponse, isNull);
      // Inactive tab (Document) PRESERVED its generated audio!
      expect(notifier.state.documentTtsResponse, isNotNull);
      expect(notifier.state.documentTtsResponse!.filename, equals('doc.mp3'));
    });
  });

  group('Widget Tests: PdfUploadScreen Tab Isolation', () {
    testWidgets('Empty Enter Text hides audio player and shows disabled Convert to Speech button after Document TTS',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final repo = MockTtsRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            documentTtsRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: PdfUploadScreen(mode: UploadMode.tts),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(PdfUploadScreen));
      final container = ProviderScope.containerOf(element);

      // 1. Simulate Document TTS speech generation on Document tab
      container.read(documentTtsNotifierProvider.notifier).setTtsResponseForTesting(
            TtsResponseModel(
              success: true,
              audioUrl: '/audio/doc.mp3',
              filename: 'doc.mp3',
              chunkIndex: 0,
              totalChunks: 1,
            ),
            source: TtsInputSource.document,
          );
      await tester.pumpAndSettle();

      // 2. Switch to Enter Text tab
      final enterTextTab = find.text('Enter Text');
      expect(enterTextTab, findsOneWidget);
      await tester.tap(enterTextTab);
      await tester.pumpAndSettle();

      // Verify Bug Fix:
      // - Audio player MUST NOT appear in Enter Text tab
      expect(find.byType(ReadoraAudioPlayer), findsNothing);

      // - Editor is empty
      expect(find.text('0 characters'), findsOneWidget);

      // - Button shows "Convert to Speech →" (NOT "Re-generate Speech →")
      expect(find.text('Convert to Speech →'), findsOneWidget);
      expect(find.text('Re-generate Speech →'), findsNothing);

      // - Button is disabled (onPressed == null)
      final elevatedButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton).last);
      expect(elevatedButton.onPressed, isNull);

      // 3. Type text into editor: button changes to enabled "Convert to Speech →"
      await tester.enterText(find.byType(TextField).first, 'Hello Readora');
      await tester.pumpAndSettle();

      expect(find.text('13 characters'), findsOneWidget);
      final enabledButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton).last);
      expect(enabledButton.onPressed, isNotNull);
      expect(find.text('Convert to Speech →'), findsOneWidget);
      // Audio player is still hidden until speech is generated
      expect(find.byType(ReadoraAudioPlayer), findsNothing);

      // 4. Switch back to Upload Document tab: document audio player is present!
      final uploadDocTab = find.text('Upload Document');
      await tester.tap(uploadDocTab);
      await tester.pumpAndSettle();

      // Document tab displays its preserved document audio player!
      expect(container.read(documentTtsNotifierProvider).currentTtsResponse, isNotNull);
      expect(container.read(documentTtsNotifierProvider).currentTtsResponse!.filename, equals('doc.mp3'));
    });
  });
}
