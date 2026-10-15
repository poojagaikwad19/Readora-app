import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texttospeech/core/services/storage_service.dart';
import 'package:texttospeech/features/auth/presentation/providers/auth_provider.dart';
import 'package:texttospeech/features/document_tts/domain/document_model.dart';
import 'package:texttospeech/features/document_tts/presentation/screens/pdf_reader_screen.dart';
import 'package:texttospeech/features/document_tts/presentation/widgets/original_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storageService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storageService = StorageService(prefs);
  });

  Widget buildTestScreen(DocumentModel doc) {
    return ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
      ],
      child: MaterialApp(
        home: PdfReaderScreen(document: doc),
      ),
    );
  }

  group('PdfReaderScreen Simplified View Tests', () {
    testWidgets('Opening a PDF shows pure text and NO language, voice, or convert speech options', (tester) async {
      final pdfDoc = DocumentModel(
        docId: 'doc_1',
        filename: '1.PDF',
        text: 'REMOTE SENSING, GIS AND GPS AS A TOOL TO SUPPORT PRECISION FORESTRY',
        fileType: 'pdf',
        detectedLanguage: 'english',
        characterCount: 68,
      );

      await tester.pumpWidget(buildTestScreen(pdfDoc));
      await tester.pumpAndSettle();

      // 1. Filename and copy button in AppBar
      expect(find.text('1.PDF'), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);

      // 2. Extracted PDF text is rendered
      expect(find.text(pdfDoc.text), findsOneWidget);

      // 3. Info banner shows document stats
      expect(find.textContaining('Document (ENGLISH)'), findsOneWidget);

      // 4. MUST NOT show language selector, voice accent, choice chips, or convert speech button
      expect(find.text('Target Language'), findsNothing);
      expect(find.text('Voice Accent'), findsNothing);
      expect(find.text('English Speech'), findsNothing);
      expect(find.text('Marathi Speech (मराठी)'), findsNothing);
      expect(find.text('Hindi Speech (हिन्दी)'), findsNothing);
      expect(find.textContaining('Convert & Listen to Speech'), findsNothing);
      expect(find.textContaining('Convert to Speech'), findsNothing);
    });

    testWidgets('Opening an Audio file shows audio player, transcript, and NO language, voice, or convert speech options', (tester) async {
      final audioDoc = DocumentModel(
        docId: 'audio_1',
        filename: 'marathi-audioE.mp3',
        text: 'येथे पर्यावरणाचे महत्त्व या विषयावर ट्रान्सक्रिप्ट आहे.',
        fileType: 'mp3',
        detectedLanguage: 'marathi',
        audioSourcePath: '/mock/path/marathi-audioE.mp3',
        characterCount: 54,
      );

      await tester.pumpWidget(buildTestScreen(audioDoc));
      await tester.pumpAndSettle();

      // 1. Filename and copy button in AppBar
      expect(find.text('marathi-audioE.mp3'), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);

      // 2. Audio player is displayed for audio
      expect(find.byType(OriginalAudioPlayer), findsOneWidget);

      // 3. Transcript text is rendered
      expect(find.text(audioDoc.text), findsOneWidget);

      // 4. Info banner shows audio transcript stats
      expect(find.textContaining('Audio Transcript (MARATHI)'), findsOneWidget);

      // 5. MUST NOT show language selector, voice accent, choice chips, or convert speech button
      expect(find.text('Target Language'), findsNothing);
      expect(find.text('Voice Accent'), findsNothing);
      expect(find.text('English Speech'), findsNothing);
      expect(find.text('Marathi Speech (मराठी)'), findsNothing);
      expect(find.text('Hindi Speech (हिन्दी)'), findsNothing);
      expect(find.textContaining('Convert & Listen to Speech'), findsNothing);
      expect(find.textContaining('Convert to Speech'), findsNothing);
    });
  });
}
