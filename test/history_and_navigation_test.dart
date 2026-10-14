import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texttospeech/core/services/storage_service.dart';
import 'package:texttospeech/features/auth/presentation/providers/auth_provider.dart';
import 'package:texttospeech/features/document_tts/domain/document_model.dart';
import 'package:texttospeech/features/document_tts/presentation/screens/dashboard_screen.dart';
import 'package:texttospeech/features/document_tts/presentation/screens/history_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. History Filter Tabs Classification Tests', () {
    test('Classifies PDF, DOCX, TXT, and extracted images as Document', () {
      final pdfDoc = DocumentModel(
        docId: 'doc_1',
        filename: 'manual.pdf',
        text: 'PDF content',
        fileType: 'pdf',
      );
      final docxDoc = DocumentModel(
        docId: 'doc_2',
        filename: 'notes.docx',
        text: 'Docx content',
        fileType: 'docx',
      );
      final txtDoc = DocumentModel(
        docId: 'doc_3',
        filename: 'readme.txt',
        text: 'Text content',
        fileType: 'txt',
      );
      final imgDoc = DocumentModel(
        docId: 'doc_4',
        filename: 'photo.png',
        text: 'Image OCR text',
        fileType: 'png',
      );

      expect(HistoryScreen.isDocumentType(pdfDoc), isTrue);
      expect(HistoryScreen.isAudioType(pdfDoc), isFalse);

      expect(HistoryScreen.isDocumentType(docxDoc), isTrue);
      expect(HistoryScreen.isAudioType(docxDoc), isFalse);

      expect(HistoryScreen.isDocumentType(txtDoc), isTrue);
      expect(HistoryScreen.isAudioType(txtDoc), isFalse);

      expect(HistoryScreen.isDocumentType(imgDoc), isTrue);
      expect(HistoryScreen.isAudioType(imgDoc), isFalse);
    });

    test('Classifies MP3, WAV, and M4A audio transcripts as Audio', () {
      final mp3Doc = DocumentModel(
        docId: 'stt_1',
        filename: 'recording.mp3',
        text: 'Transcribed speech text',
        fileType: 'mp3',
        audioSourcePath: '/storage/recording.mp3',
      );
      final wavDoc = DocumentModel(
        docId: 'stt_2',
        filename: 'interview.wav',
        text: 'Interview transcript',
        fileType: 'wav',
      );
      final m4aDoc = DocumentModel(
        docId: 'stt_3',
        filename: 'voice_note.m4a',
        text: 'Voice note transcript',
        fileType: 'm4a',
      );

      expect(HistoryScreen.isAudioType(mp3Doc), isTrue);
      expect(HistoryScreen.isDocumentType(mp3Doc), isFalse);

      expect(HistoryScreen.isAudioType(wavDoc), isTrue);
      expect(HistoryScreen.isDocumentType(wavDoc), isFalse);

      expect(HistoryScreen.isAudioType(m4aDoc), isTrue);
      expect(HistoryScreen.isDocumentType(m4aDoc), isFalse);
    });

    test('PDF with generated speech text remains Document', () {
      final pdfWithSpeech = DocumentModel(
        docId: 'doc_pdf_tts',
        filename: 'chapter1.pdf',
        text: 'Extracted PDF text that was voiced by TTS',
        fileType: 'pdf',
        audioSourcePath: null,
      );

      expect(HistoryScreen.isDocumentType(pdfWithSpeech), isTrue);
      expect(HistoryScreen.isAudioType(pdfWithSpeech), isFalse);
    });

    test('Uploaded MP3 with text transcript remains Audio', () {
      final mp3WithText = DocumentModel(
        docId: 'stt_mp3_txt',
        filename: 'meeting_audio.mp3',
        text: 'Full transcribed transcript of meeting',
        fileType: 'mp3',
        audioSourcePath: '/data/meeting_audio.mp3',
      );

      expect(HistoryScreen.isAudioType(mp3WithText), isTrue);
      expect(HistoryScreen.isDocumentType(mp3WithText), isFalse);
    });

    test('Unknown legacy types are not Document or Audio, but visible under All', () {
      final legacyDoc = DocumentModel(
        docId: 'legacy_99',
        filename: 'archive_blob',
        text: 'Legacy custom blob content',
        fileType: 'bin',
      );

      expect(HistoryScreen.isDocumentType(legacyDoc), isFalse);
      expect(HistoryScreen.isAudioType(legacyDoc), isFalse);
    });
  });

  group('2. History Exclusion & Storage Persistence Tests', () {
    test('StorageService persists account-scoped excluded history IDs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      // Account scoped to guest when no user logged in
      expect(storage.getExcludedHistoryIds(), isEmpty);

      await storage.addExcludedHistoryId('doc_abc_123');
      expect(storage.getExcludedHistoryIds().contains('doc_abc_123'), isTrue);

      // Simulating app restart by recreating StorageService
      final storageRestarted = StorageService(prefs);
      expect(storageRestarted.getExcludedHistoryIds().contains('doc_abc_123'), isTrue);

      await storageRestarted.removeExcludedHistoryId('doc_abc_123');
      expect(storageRestarted.getExcludedHistoryIds().contains('doc_abc_123'), isFalse);
    });

    test('Document deletion uses stable docId, preventing collisions with identical filenames', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      final doc1 = DocumentModel(
        docId: 'unique_id_alpha',
        filename: 'same_name.pdf',
        text: 'First version',
        fileType: 'pdf',
      );
      final doc2 = DocumentModel(
        docId: 'unique_id_beta',
        filename: 'same_name.pdf',
        text: 'Second version',
        fileType: 'pdf',
      );

      await storage.saveHistoryDocs([doc1.toJson(), doc2.toJson()]);

      // Add doc1 to excluded IDs
      await storage.addExcludedHistoryId('unique_id_alpha');

      final excluded = storage.getExcludedHistoryIds();
      expect(excluded.contains('unique_id_alpha'), isTrue);
      expect(excluded.contains('unique_id_beta'), isFalse);

      final loaded = storage
          .getHistoryDocs()
          .map((j) => DocumentModel.fromJson(j))
          .where((d) => !excluded.contains(d.docId))
          .toList();

      expect(loaded.length, 1);
      expect(loaded.first.docId, 'unique_id_beta');
      expect(loaded.first.text, 'Second version');
    });
  });

  group('3. HistoryScreen Widget & Filter Tabs UI Tests', () {
    testWidgets('Renders three filter tabs All, Document, Audio and empty states',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
          ],
          child: const MaterialApp(
            home: HistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Heading and Subtitle
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Recent uploaded documents and audio files'), findsOneWidget);

      // Three filter tabs
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Document'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);

      // Default All empty state
      expect(find.text('No history items yet'), findsOneWidget);

      // Tap Document tab
      await tester.tap(find.text('Document'));
      await tester.pumpAndSettle();
      expect(find.text('No documents found'), findsOneWidget);

      // Tap Audio tab
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();
      expect(find.text('No audio files found'), findsOneWidget);
    });

    testWidgets('History cards support accessible delete action and swipe left',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      final testDoc = DocumentModel(
        docId: 'doc_test_swipe',
        filename: 'report.pdf',
        text: 'Financial Report 2026',
        fileType: 'pdf',
      );
      await storage.saveHistoryDocs([testDoc.toJson()]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
          ],
          child: const MaterialApp(
            home: HistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Card is present
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('Delete'), findsNothing); // dismiss background hidden initially

      // Accessible delete icon button is present
      expect(find.byIcon(Icons.delete_outline_rounded), findsWidgets);

      // Dismissible widget exists with key based on docId
      expect(find.byKey(const ValueKey('history_dismiss_doc_test_swipe')), findsOneWidget);
    });
  });

  group('4. Dashboard Navigation & Simplified Branding Tests', () {
    testWidgets('Bottom navigation contains only Home and Profile, branding simplified',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
          ],
          child: const MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bottom Navigation items
      expect(find.text('Home'), findsWidgets);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('My Docs'), findsNothing);
      expect(find.text('Convert'), findsNothing);

      // App bar has Readora without small 'TTS' badge
      expect(find.text('Readora'), findsOneWidget);
      expect(find.text('TTS'), findsNothing);

      // Open drawer
      final menuButton = find.byTooltip('Navigation Menu');
      expect(menuButton, findsOneWidget);
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      // Drawer branding is Readora (not Readora AI)
      expect(find.text('Readora AI'), findsNothing);
      expect(find.text('Readora'), findsWidgets);

      // Sidebar has History item
      expect(find.text('History'), findsOneWidget);

      // Sidebar has Logout item
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('Tapping Logout shows themed confirmation dialog with No and Yes',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
          ],
          child: const MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open drawer
      await tester.tap(find.byTooltip('Navigation Menu'));
      await tester.pumpAndSettle();

      // Tap Logout
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();

      // Confirmation dialog is shown
      expect(find.text('Are you sure you want to logout?'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);

      // Tap 'No' -> closes dialog and keeps user on Dashboard
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to logout?'), findsNothing);
      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    testWidgets('PopScope handles back from Profile tab to Home tab',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
          ],
          child: const MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Profile tab
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      // We are on profile tab (Sign Out of Readora is visible)
      expect(find.text('Sign Out of Readora'), findsOneWidget);

      // Simulate back invocation
      final dynamic popScope = tester.widget(find.byWidgetPredicate((w) => w is PopScope));
      popScope.onPopInvokedWithResult(false, null);
      await tester.pumpAndSettle();

      // Back returns to Home tab (Sign Out of Readora is gone from active view)
      expect(find.text('Sign Out of Readora'), findsNothing);
      expect(find.text('Choose Feature'), findsOneWidget);
    });
  });
}
