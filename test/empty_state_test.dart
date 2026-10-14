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

  Widget buildTestScreen(UploadMode mode) {
    return ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
        documentTtsRepositoryProvider.overrideWithValue(mockRepo),
      ],
      child: MaterialApp(
        home: PdfUploadScreen(mode: mode),
      ),
    );
  }

  group('TTS Illustrated Empty State Tests', () {
    testWidgets('Renders all required elements for TTS Upload Document empty state', (tester) async {
      await tester.pumpWidget(buildTestScreen(UploadMode.tts));
      await tester.pumpAndSettle();

      // Heading and description
      expect(find.text('Give your documents a voice'), findsOneWidget);
      expect(find.text('Upload a document or enter text to listen.'), findsOneWidget);

      // Choose document button
      expect(find.text('Choose a document'), findsOneWidget);
      expect(find.byIcon(Icons.file_upload_outlined), findsOneWidget);

      // Format chips
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('DOCX'), findsOneWidget);
      expect(find.text('TXT'), findsOneWidget);
      expect(find.text('Images'), findsOneWidget);

      // Instructional steps
      expect(find.text('Upload'), findsOneWidget);
      expect(find.text('Choose voice'), findsOneWidget);
      expect(find.text('Listen'), findsOneWidget);

      // Tip
      expect(find.text('Selectable-text PDFs usually extract faster than scanned pages.'), findsOneWidget);

      // Verify TTS illustration asset widget
      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.image, isA<AssetImage>());
      expect((imageWidget.image as AssetImage).assetName, equals('assets/images/tts.png'));
    });

    testWidgets('Toggling Enter Text mode hides illustration and shows text input', (tester) async {
      await tester.pumpWidget(buildTestScreen(UploadMode.tts));
      await tester.pumpAndSettle();

      expect(find.text('Give your documents a voice'), findsOneWidget);

      // Tap "Enter Text" tab
      await tester.tap(find.text('Enter Text'));
      await tester.pumpAndSettle();

      // In Enter Text mode, illustration must NOT be displayed over the text editor
      expect(find.text('Give your documents a voice'), findsNothing);
      expect(find.text('Choose a document'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);

      // Tap back to "Upload Document" tab
      await tester.tap(find.text('Upload Document'));
      await tester.pumpAndSettle();

      // Illustration is restored
      expect(find.text('Give your documents a voice'), findsOneWidget);
      expect(find.text('Choose a document'), findsOneWidget);
    });
  });

  group('STT Illustrated Empty State Tests', () {
    testWidgets('Renders all required elements for STT empty state', (tester) async {
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

      // Instructional steps
      expect(find.text('Upload'), findsOneWidget);
      expect(find.text('Choose language'), findsOneWidget);
      expect(find.text('Transcribe'), findsOneWidget);

      // Tip
      expect(find.text('Choose the language spoken in your recording.'), findsOneWidget);

      // Verify STT illustration asset widget
      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.image, isA<AssetImage>());
      expect((imageWidget.image as AssetImage).assetName, equals('assets/images/stt.png'));
    });
  });

  group('Responsiveness and Compact Screen Tests', () {
    testWidgets('Builds without overflow on small screen (360x640) for both TTS and STT', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScreen(UploadMode.stt));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Turn your audio into words'), findsOneWidget);
      expect(find.text('Choose an audio file'), findsOneWidget);

      await tester.pumpWidget(buildTestScreen(UploadMode.tts));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Give your documents a voice'), findsOneWidget);
      expect(find.text('Choose a document'), findsOneWidget);
    });

    testWidgets('Builds without overflow on narrow width (320px) with 1.4x larger text', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storageService),
            documentTtsRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.4)),
              child: PdfUploadScreen(mode: UploadMode.tts),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Choose a document'), findsOneWidget);
    });
  });
}
