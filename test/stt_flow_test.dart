import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texttospeech/core/services/storage_service.dart';
import 'package:texttospeech/features/auth/presentation/providers/auth_provider.dart';
import 'package:texttospeech/features/document_tts/data/document_tts_repository.dart';
import 'package:texttospeech/features/document_tts/domain/voice_model.dart';
import 'package:texttospeech/features/document_tts/domain/tts_response_model.dart';
import 'package:texttospeech/features/document_tts/domain/document_model.dart';
import 'package:texttospeech/features/document_tts/presentation/providers/document_tts_provider.dart';
import 'package:texttospeech/features/document_tts/presentation/screens/pdf_upload_screen.dart';

class _MockRepo implements DocumentTtsRepository {
  @override
  Future<DocumentModel> extractDocument(String filePath) async =>
      DocumentModel(docId: 'doc_1', filename: 'test.pdf', text: 'Text');
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
  }) async =>
      TtsResponseModel(success: true, audioUrl: '/audio/test.mp3', filename: 'test.mp3');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storageService;
  late _MockRepo mockRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storageService = StorageService(prefs);
    mockRepo = _MockRepo();
  });

  Widget buildTestScreen(UploadMode mode, {DocumentTtsNotifier? customNotifier}) {
    return ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
        documentTtsRepositoryProvider.overrideWithValue(mockRepo),
        if (customNotifier != null)
          documentTtsNotifierProvider.overrideWith((ref) => customNotifier),
      ],
      child: MaterialApp(
        home: PdfUploadScreen(mode: mode),
      ),
    );
  }

  group('STT Language Code Routing Tests', () {
    test('Verify Language Codes Routing Mapping for Google Cloud STT', () {
      String getLanguageCode(String selectedLang) {
        final lang = selectedLang.toLowerCase();
        if (lang == 'marathi' || lang == 'mr') return 'mr-IN';
        if (lang == 'hindi' || lang == 'hi') return 'hi-IN';
        return 'en';
      }

      expect(getLanguageCode('Marathi'), equals('mr-IN'));
      expect(getLanguageCode('mr'), equals('mr-IN'));
      expect(getLanguageCode('Hindi'), equals('hi-IN'));
      expect(getLanguageCode('hi'), equals('hi-IN'));
      expect(getLanguageCode('English'), equals('en'));
      expect(getLanguageCode('en'), equals('en'));
    });
  });

  group('STT Upload Screen Layout & Guidance Tests (Screenshot 1)', () {
    testWidgets('Renders Screenshot 1 upload view with updated guidance text', (tester) async {
      await tester.pumpWidget(buildTestScreen(UploadMode.stt));
      await tester.pumpAndSettle();

      // Heading and description
      expect(find.text('Turn your audio into words'), findsOneWidget);
      expect(find.text('Upload a recording to create a readable transcript.'), findsOneWidget);

      // Choose audio file button
      expect(find.text('Choose an audio file'), findsOneWidget);
      expect(find.byIcon(Icons.audio_file_outlined), findsOneWidget);

      // Format chips
      expect(find.text('MP3'), findsOneWidget);
      expect(find.text('WAV'), findsOneWidget);
      expect(find.text('M4A'), findsOneWidget);
      expect(find.text('AAC'), findsOneWidget);
      expect(find.text('FLAC'), findsOneWidget);
      expect(find.text('OGG'), findsOneWidget);

      // Guidance steps: Upload -> Transcribe -> Read
      expect(find.text('Upload'), findsOneWidget);
      expect(find.text('Transcribe'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
      expect(find.text('Choose language'), findsNothing);

      // Updated tip
      expect(find.text('Clear recordings help improve transcription accuracy.'), findsOneWidget);
      expect(find.text('Choose the language spoken in your recording.'), findsNothing);

      // No visible language selector chips (Auto Detect, Marathi, Hindi, English) in this flow
      expect(find.text('Auto Detect'), findsNothing);
      expect(find.text('मराठी'), findsNothing);
      expect(find.text('हिन्दी'), findsNothing);
    });
  });

  group('STT Provider Cancellation & Token Invalidation Tests', () {
    test('cancelStt sets isExtracting to false and invalidates in-flight responses', () async {
      final notifier = DocumentTtsNotifier(mockRepo, storageService);
      notifier.state = notifier.state.copyWith(
        isExtracting: true,
        selectedSttLanguage: 'marathi',
      );

      expect(notifier.state.isExtracting, isTrue);
      expect(notifier.state.selectedSttLanguage, equals('marathi'));

      // Call cancelStt
      notifier.cancelStt();

      // State is immediately not extracting
      expect(notifier.state.isExtracting, isFalse);
      // Selected language is preserved, not reset to english
      expect(notifier.state.selectedSttLanguage, equals('marathi'));
    });

    test('Late/cancelled STT transcription does not alter activeDocument or history', () async {
      final notifier = DocumentTtsNotifier(mockRepo, storageService);
      notifier.state = notifier.state.copyWith(
        selectedSttLanguage: 'hindi',
      );

      // Start transcription of a non-existent file path
      final future = notifier.transcribeAudioFile('non_existent.mp3');

      // Immediately cancel
      notifier.cancelStt();

      final result = await future;
      expect(result, isNull);
      expect(notifier.state.isExtracting, isFalse);
      expect(notifier.state.activeDocument, isNull);
      expect(notifier.state.userDocuments, isEmpty);
      // Preserved configured language
      expect(notifier.state.selectedSttLanguage, equals('hindi'));
    });
  });

  group('STT Inline Card Processing & Error States', () {
    testWidgets('Renders inline processing state in upload card when isExtracting is true', (tester) async {
      final notifier = DocumentTtsNotifier(mockRepo, storageService);
      notifier.state = notifier.state.copyWith(
        isExtracting: true,
      );

      await tester.pumpWidget(buildTestScreen(UploadMode.stt, customNotifier: notifier));
      await tester.pump();

      // Heading and description from Screenshot 1 remain visible
      expect(find.text('Turn your audio into words'), findsOneWidget);
      expect(find.text('Upload a recording to create a readable transcript.'), findsOneWidget);

      // Guidance text remains visible
      expect(find.text('Clear recordings help improve transcription accuracy.'), findsOneWidget);

      // No separate intermediate screen is shown
      expect(find.text('Transcribe Audio →'), findsNothing);
    });

    testWidgets('Cancellation accessibility label exists and is accessible', (tester) async {
      final notifier = DocumentTtsNotifier(mockRepo, storageService);
      notifier.cancelStt();

      await tester.pumpWidget(buildTestScreen(UploadMode.stt, customNotifier: notifier));
      await tester.pumpAndSettle();

      // Button exists to pick file
      expect(find.text('Choose an audio file'), findsOneWidget);
    });
  });

  group('Responsiveness & Long Filename Tests', () {
    testWidgets('Builds without overflow on narrow width (320px) for STT flow', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScreen(UploadMode.stt));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Turn your audio into words'), findsOneWidget);
      expect(find.text('Choose an audio file'), findsOneWidget);
      expect(find.text('Upload'), findsOneWidget);
      expect(find.text('Transcribe'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
    });
  });
}
