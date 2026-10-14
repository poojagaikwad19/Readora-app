import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:texttospeech/core/services/storage_service.dart';
import 'package:texttospeech/core/theme/app_theme.dart';
import 'package:texttospeech/features/auth/presentation/providers/auth_provider.dart';
import 'package:texttospeech/features/settings/domain/settings_model.dart';
import 'package:texttospeech/features/settings/presentation/providers/settings_provider.dart';
import 'package:texttospeech/features/downloads/domain/download_model.dart';
import 'package:texttospeech/features/downloads/presentation/screens/downloads_screen.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;
  final Directory docDir;

  MockPathProviderPlatform(this.tempDir, this.docDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => docDir.path;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDocsDir;
  late Directory testTempDir;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (MethodCall call) async {
      return 1;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global'), (MethodCall call) async {
      return 1;
    });

    SharedPreferences.setMockInitialValues({});
    testDocsDir = Directory.systemTemp.createTempSync('readora_test_docs');
    testTempDir = Directory.systemTemp.createTempSync('readora_test_temp');
    PathProviderPlatform.instance = MockPathProviderPlatform(testTempDir, testDocsDir);
  });

  tearDown(() {
    try {
      if (testDocsDir.existsSync()) testDocsDir.deleteSync(recursive: true);
      if (testTempDir.existsSync()) testTempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Downloads Filter & Classification Tests', () {
    test('Classifies downloaded file by actual type, NOT the source document', () {
      // Speech generated from a PDF source and saved as MP3
      final ttsFromPdf = DownloadModel(
        id: 'dl_tts_1',
        userId: 'user_1',
        sourceDocId: 'doc_annual_report',
        sourceDocName: 'Annual_Report_2026.pdf',
        displayFilename: 'Annual_Report_Speech.mp3',
        relativeFilePath: 'downloads/audio_1.mp3',
        mimeType: 'audio/mpeg',
        fileSize: 2048,
        language: 'english',
        downloadDate: DateTime.now(),
      );

      // Must be classified as AUDIO, NOT DOCUMENT
      expect(DownloadModel.isAudioType(ttsFromPdf), isTrue);
      expect(DownloadModel.isDocumentType(ttsFromPdf), isFalse);
      expect(DownloadModel.matchesFilter(ttsFromPdf, DownloadsFilter.all), isTrue);
      expect(DownloadModel.matchesFilter(ttsFromPdf, DownloadsFilter.audio), isTrue);
      expect(DownloadModel.matchesFilter(ttsFromPdf, DownloadsFilter.document), isFalse);
      expect(ttsFromPdf.isAudio, isTrue);
      expect(ttsFromPdf.isDocument, isFalse);
    });

    test('Classifies actual documents (PDF, DOCX, TXT, Images) correctly', () {
      final pdfDoc = DownloadModel(
        id: 'dl_doc_1',
        userId: 'user_1',
        displayFilename: 'Contract.PDF',
        relativeFilePath: 'downloads/contract.pdf',
        mimeType: 'application/pdf',
        fileSize: 50000,
        language: 'english',
        downloadDate: DateTime.now(),
      );
      expect(DownloadModel.isDocumentType(pdfDoc), isTrue);
      expect(DownloadModel.isAudioType(pdfDoc), isFalse);
      expect(DownloadModel.matchesFilter(pdfDoc, DownloadsFilter.document), isTrue);
      expect(pdfDoc.isDocument, isTrue);

      final txtDoc = DownloadModel(
        id: 'dl_doc_2',
        userId: 'user_1',
        displayFilename: 'Notes.txt',
        relativeFilePath: 'downloads/notes.txt',
        mimeType: 'text/plain',
        fileSize: 1200,
        language: 'english',
        downloadDate: DateTime.now(),
      );
      expect(DownloadModel.isDocumentType(txtDoc), isTrue);
      expect(DownloadModel.isAudioType(txtDoc), isFalse);
      expect(txtDoc.isDocument, isTrue);

      final imageDoc = DownloadModel(
        id: 'dl_doc_3',
        userId: 'user_1',
        displayFilename: 'Receipt.PNG',
        relativeFilePath: 'downloads/receipt.png',
        mimeType: 'image/png',
        fileSize: 85000,
        language: 'english',
        downloadDate: DateTime.now(),
      );
      expect(DownloadModel.isDocumentType(imageDoc), isTrue);
      expect(DownloadModel.isAudioType(imageDoc), isFalse);
      expect(imageDoc.isDocument, isTrue);
    });

    test('MIME priority and case-insensitive extension fallback', () {
      // Missing MIME type (empty), but filename ends with uppercase .WAV
      final wavAudio = DownloadModel(
        id: 'dl_audio_2',
        userId: 'user_1',
        displayFilename: 'Recording_Interview.WAV',
        relativeFilePath: 'downloads/interview.wav',
        mimeType: '',
        fileSize: 400000,
        language: 'english',
        downloadDate: DateTime.now(),
      );
      expect(DownloadModel.isAudioType(wavAudio), isTrue);
      expect(DownloadModel.isDocumentType(wavAudio), isFalse);
      expect(wavAudio.isAudio, isTrue);

      // Unknown file extension
      final unknownFile = DownloadModel(
        id: 'dl_unk',
        userId: 'user_1',
        displayFilename: 'archive.dat',
        relativeFilePath: 'downloads/archive.dat',
        mimeType: 'application/octet-stream',
        fileSize: 1024,
        language: 'english',
        downloadDate: DateTime.now(),
      );
      expect(DownloadModel.isAudioType(unknownFile), isFalse);
      expect(DownloadModel.isDocumentType(unknownFile), isFalse);
      // Remains visible in 'All'
      expect(DownloadModel.matchesFilter(unknownFile, DownloadsFilter.all), isTrue);
      expect(DownloadModel.matchesFilter(unknownFile, DownloadsFilter.audio), isFalse);
      expect(DownloadModel.matchesFilter(unknownFile, DownloadsFilter.document), isFalse);
    });
  });

  group('Downloads Filter Tabs UI & Empty States', () {
    testWidgets('DownloadsScreen displays All, Document, and Audio tabs and updates filter', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      // Add one audio download generated from a PDF
      final downloadsDir = Directory('${testDocsDir.path}/downloads');
      downloadsDir.createSync(recursive: true);
      final fakeAudio = File('${downloadsDir.path}/audio_dl.mp3');
      fakeAudio.writeAsBytesSync([1, 2, 3]);

      await storage.saveDownloads([
        {
          'id': 'dl_1',
          'userId': 'guest',
          'sourceDocName': 'biology_book.pdf',
          'displayFilename': 'biology_speech.mp3',
          'relativeFilePath': 'downloads/audio_dl.mp3',
          'mimeType': 'audio/mpeg',
          'fileSize': 1024,
          'durationMs': 30000,
          'language': 'english',
          'downloadDate': DateTime.now().toIso8601String(),
        }
      ], 'guest');

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: DownloadsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the three filter tabs exist
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Document'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);

      // 'All' is selected by default -> audio file is visible
      expect(find.text('biology_speech.mp3'), findsOneWidget);

      // Tap 'Document' tab
      await tester.tap(find.text('Document'));
      await tester.pumpAndSettle();

      // Audio file must NOT be visible under Document
      expect(find.text('biology_speech.mp3'), findsNothing);
      // Honest empty state for Document
      expect(find.text('No downloaded documents yet'), findsOneWidget);
      expect(find.text('Downloaded document files (PDF, DOCX, TXT) will appear here.'), findsOneWidget);

      // Tap 'Audio' tab
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();

      // Audio file must be visible under Audio
      expect(find.text('biology_speech.mp3'), findsOneWidget);
      expect(find.text('No downloaded documents yet'), findsNothing);
    });
  });

  group('Legacy Appearance Migration & Root Theme Propagation', () {
    test('Migrates legacy "system" preference to explicit choice and persists', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      // Simulate a legacy user having "system" in storage
      await storage.saveUser(id: 'user_mig', name: 'Migrating User', email: 'mig@test.com');
      await storage.saveSettings({
        'themeMode': 'system',
        'readerFontSize': 'medium',
      });

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
      );

      // Trigger provider initialization
      final settings = container.read(settingsProvider);

      // Must have migrated to an explicit mode (light or dark), never system
      expect(settings.themeMode, isNot(equals(AppThemeMode.system)));
      expect(settings.themeMode == AppThemeMode.light || settings.themeMode == AppThemeMode.dark, isTrue);

      // Stored JSON must now reflect the explicit mode
      final storedMap = storage.getSettings('user_mig');
      expect(storedMap?['themeMode'], isNot(equals('system')));
      expect(storedMap?['themeMode'], equals(settings.themeMode.name));
    });

    test('Preserves existing explicit "light" and "dark" choices without alteration', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      await storage.saveUser(id: 'user_dark', name: 'Dark User', email: 'dark@test.com');
      await storage.saveSettings({'themeMode': 'dark'});

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
      );

      expect(container.read(settingsProvider).themeMode, equals(AppThemeMode.dark));
    });

    testWidgets('Root theme propagates when switching between Light and Dark', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              final settings = ref.watch(settingsProvider);
              return MaterialApp(
                theme: AppTheme.theme,
                darkTheme: AppTheme.darkTheme,
                themeMode: settings.themeMode.toFlutterThemeMode(),
                home: Builder(
                  builder: (ctx) {
                    final isDark = Theme.of(ctx).brightness == Brightness.dark;
                    return Scaffold(
                      backgroundColor: ctx.scaffoldBg,
                      body: Text(
                        isDark ? 'ACTIVE_DARK' : 'ACTIVE_LIGHT',
                        style: TextStyle(color: ctx.textPrimaryColor),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initial state is Light (default)
      expect(find.text('ACTIVE_LIGHT'), findsOneWidget);
      expect(find.text('ACTIVE_DARK'), findsNothing);

      // Switch to Dark
      await container.read(settingsProvider.notifier).updateThemeMode(AppThemeMode.dark);
      await tester.pumpAndSettle();

      // Root theme must update immediately to Dark
      expect(find.text('ACTIVE_DARK'), findsOneWidget);
      expect(find.text('ACTIVE_LIGHT'), findsNothing);

      // Switch back to Light
      await container.read(settingsProvider.notifier).updateThemeMode(AppThemeMode.light);
      await tester.pumpAndSettle();

      // Restores Light immediately
      expect(find.text('ACTIVE_LIGHT'), findsOneWidget);
      expect(find.text('ACTIVE_DARK'), findsNothing);
    });
  });
}
