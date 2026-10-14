import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:texttospeech/core/services/storage_service.dart';
import 'package:texttospeech/features/auth/presentation/providers/auth_provider.dart';
import 'package:texttospeech/features/document_tts/domain/voice_model.dart';
import 'package:texttospeech/features/settings/domain/settings_model.dart';
import 'package:texttospeech/features/settings/presentation/screens/settings_screen.dart';
import 'package:texttospeech/features/downloads/domain/download_model.dart';
import 'package:texttospeech/features/downloads/presentation/providers/downloads_provider.dart';
import 'package:texttospeech/features/downloads/presentation/screens/downloads_screen.dart';
import 'package:texttospeech/features/document_tts/presentation/providers/document_tts_provider.dart';
import 'package:texttospeech/features/settings/presentation/providers/settings_provider.dart';

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
    testDocsDir = Directory.systemTemp.createTempSync('readora_docs_test');
    testTempDir = Directory.systemTemp.createTempSync('readora_temp_test');
    PathProviderPlatform.instance = MockPathProviderPlatform(testTempDir, testDocsDir);
  });

  tearDown(() {
    try {
      if (testDocsDir.existsSync()) testDocsDir.deleteSync(recursive: true);
      if (testTempDir.existsSync()) testTempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Part A: Settings Domain, Persistence & Account Scoping Tests', () {
    test('SettingsModel has correct default values matching requirements', () {
      const settings = SettingsModel();

      expect(settings.themeMode, equals(AppThemeMode.light));
      expect(settings.readerFontSize, equals(ReaderFontSize.medium));
      expect(settings.readerFontSize.size, equals(15.0));

      expect(settings.defaultTtsLanguage, equals('english'));
      expect(settings.defaultTtsVoiceEnglish, equals('CwhRBWXzGAHq8TQ4Fs17')); // Roger
      expect(settings.defaultTtsVoiceMarathi, equals('CwhRBWXzGAHq8TQ4Fs17'));
      expect(settings.defaultTtsVoiceHindi, equals('CwhRBWXzGAHq8TQ4Fs17'));

      expect(settings.defaultSttLanguage, equals('english'));

      expect(settings.defaultTranscriptView, equals(TranscriptDefaultView.full));
      expect(settings.highlightCurrentWord, isTrue);
      expect(settings.autoScroll, isTrue);
      expect(settings.keepUpcomingWordsVisible, isFalse);

      expect(settings.defaultPlaybackSpeed, equals(1.0));
      expect(settings.autoPlayTts, isFalse);
      expect(settings.stopAudioOnLeaveScreen, isTrue);
    });

    test('TTS and STT default languages remain strictly independent', () {
      var settings = const SettingsModel();
      expect(settings.defaultTtsLanguage, equals('english'));
      expect(settings.defaultSttLanguage, equals('english'));

      settings = settings.copyWith(defaultTtsLanguage: 'marathi');
      expect(settings.defaultTtsLanguage, equals('marathi'));
      expect(settings.defaultSttLanguage, equals('english'));

      settings = settings.copyWith(defaultSttLanguage: 'hindi');
      expect(settings.defaultTtsLanguage, equals('marathi'));
      expect(settings.defaultSttLanguage, equals('hindi'));
    });

    test('Settings serialization preserves all fields', () {
      const original = SettingsModel(
        themeMode: AppThemeMode.dark,
        readerFontSize: ReaderFontSize.large,
        defaultTtsLanguage: 'hindi',
        defaultTtsVoiceEnglish: 'EXAVITQu4vr4xnSDxMaL',
        defaultTtsVoiceMarathi: 'CwhRBWXzGAHq8TQ4Fs17',
        defaultTtsVoiceHindi: 'FGY2WhTYpPnrIDTdsKH5',
        defaultSttLanguage: 'marathi',
        defaultTranscriptView: TranscriptDefaultView.follow,
        highlightCurrentWord: false,
        autoScroll: false,
        keepUpcomingWordsVisible: true,
        defaultPlaybackSpeed: 1.5,
        autoPlayTts: true,
        stopAudioOnLeaveScreen: false,
      );

      final json = original.toJson();
      final recovered = SettingsModel.fromJson(json);

      expect(recovered.themeMode, equals(AppThemeMode.dark));
      expect(recovered.readerFontSize, equals(ReaderFontSize.large));
      expect(recovered.readerFontSize.size, equals(18.0));
      expect(recovered.defaultTtsLanguage, equals('hindi'));
      expect(recovered.defaultTtsVoiceEnglish, equals('EXAVITQu4vr4xnSDxMaL'));
      expect(recovered.defaultTtsVoiceMarathi, equals('CwhRBWXzGAHq8TQ4Fs17'));
      expect(recovered.defaultTtsVoiceHindi, equals('FGY2WhTYpPnrIDTdsKH5'));
      expect(recovered.defaultSttLanguage, equals('marathi'));
      expect(recovered.defaultTranscriptView, equals(TranscriptDefaultView.follow));
      expect(recovered.highlightCurrentWord, isFalse);
      expect(recovered.autoScroll, isFalse);
      expect(recovered.keepUpcomingWordsVisible, isTrue);
      expect(recovered.defaultPlaybackSpeed, equals(1.5));
      expect(recovered.autoPlayTts, isTrue);
      expect(recovered.stopAudioOnLeaveScreen, isFalse);
    });

    test('Account switching separates settings without leakage', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      // User 1 logs in and saves custom settings
      await storage.saveUser(id: 'user_1', name: 'User 1', email: 'user1@test.com');
      await storage.saveSettings({
        'themeMode': 'dark',
        'readerFontSize': 'large',
        'defaultTtsLanguage': 'hindi',
      });

      // User 2 logs in and saves different settings
      await storage.saveUser(id: 'user_2', name: 'User 2', email: 'user2@test.com');
      await storage.saveSettings({
        'themeMode': 'light',
        'readerFontSize': 'small',
        'defaultTtsLanguage': 'marathi',
      });

      // Verify User 1 settings
      final u1Settings = storage.getSettings('user_1');
      expect(u1Settings?['themeMode'], equals('dark'));
      expect(u1Settings?['readerFontSize'], equals('large'));
      expect(u1Settings?['defaultTtsLanguage'], equals('hindi'));

      // Verify User 2 settings
      final u2Settings = storage.getSettings('user_2');
      expect(u2Settings?['themeMode'], equals('light'));
      expect(u2Settings?['readerFontSize'], equals('small'));
      expect(u2Settings?['defaultTtsLanguage'], equals('marathi'));
    });

    test('All 21 default neural voices in VoiceModel are valid and unique', () {
      final voices = VoiceModel.defaultVoices();
      expect(voices.length, equals(21));

      final voiceIds = voices.map((v) => v.voiceId).toSet();
      expect(voiceIds.length, equals(21), reason: 'All voice IDs must be unique');

      // Check default voice Roger is present
      expect(voices.any((v) => v.voiceId == 'CwhRBWXzGAHq8TQ4Fs17'), isTrue);
    });

    test('Default voice and language changes in settings automatically propagate to TTS state', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
      );

      // Initialize providers
      final settingsNotifier = container.read(settingsProvider.notifier);
      final ttsNotifier = container.read(documentTtsNotifierProvider.notifier);

      // Initial state
      expect(container.read(documentTtsNotifierProvider).selectedLanguage, equals('english'));
      expect(container.read(documentTtsNotifierProvider).selectedVoiceId, equals('CwhRBWXzGAHq8TQ4Fs17')); // Roger

      // 1. User changes Default English Voice to Harry ('SOYHLrjzK2X1ezoPC6cr')
      await settingsNotifier.updateDefaultTtsVoiceEnglish('SOYHLrjzK2X1ezoPC6cr');
      expect(container.read(documentTtsNotifierProvider).selectedVoiceId, equals('SOYHLrjzK2X1ezoPC6cr'));

      // 2. User changes Default Language to Marathi
      await settingsNotifier.updateDefaultTtsLanguage('marathi');
      expect(container.read(documentTtsNotifierProvider).selectedLanguage, equals('marathi'));
      // Marathi default voice is Roger
      expect(container.read(documentTtsNotifierProvider).selectedVoiceId, equals('CwhRBWXzGAHq8TQ4Fs17'));

      // 3. Switching TTS language back to English automatically selects Harry
      ttsNotifier.setSelectedLanguage('english');
      expect(container.read(documentTtsNotifierProvider).selectedLanguage, equals('english'));
      expect(container.read(documentTtsNotifierProvider).selectedVoiceId, equals('SOYHLrjzK2X1ezoPC6cr'));
    });
  });

  group('Part B: In-App Downloads Library Domain & Persistence Tests', () {
    test('DownloadModel serialization and helper properties format correctly', () {
      final download = DownloadModel(
        id: 'dl_123',
        userId: 'user_1',
        sourceDocId: 'doc_456',
        sourceDocName: 'test_doc.pdf',
        displayFilename: 'test_speech.mp3',
        relativeFilePath: 'downloads/audio_dl_123.mp3',
        fileSize: 2500000, // ~2.4 MB
        duration: const Duration(minutes: 2, seconds: 15),
        language: 'english',
        voiceId: 'CwhRBWXzGAHq8TQ4Fs17',
        voiceName: 'Roger',
        downloadDate: DateTime(2026, 10, 13),
        generationSessionId: 'sess_789',
      );

      expect(download.formattedSize, equals('2.4 MB'));
      expect(download.formattedDuration, equals('02:15'));
      expect(download.formattedDate, equals('2026-10-13'));

      final json = download.toJson();
      final restored = DownloadModel.fromJson(json);

      expect(restored.id, equals('dl_123'));
      expect(restored.userId, equals('user_1'));
      expect(restored.displayFilename, equals('test_speech.mp3'));
      expect(restored.relativeFilePath, equals('downloads/audio_dl_123.mp3'));
      expect(restored.fileSize, equals(2500000));
      expect(restored.duration?.inSeconds, equals(135));
      expect(restored.generationSessionId, equals('sess_789'));
    });

    test('Account switching separates downloads library records', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      // Save download for User A
      await storage.saveDownloads([
        {'id': 'dl_userA_1', 'displayFilename': 'doc_a.mp3', 'userId': 'user_A', 'fileSize': 1000, 'language': 'english'}
      ], 'user_A');

      // Save download for User B
      await storage.saveDownloads([
        {'id': 'dl_userB_1', 'displayFilename': 'doc_b.mp3', 'userId': 'user_B', 'fileSize': 2000, 'language': 'marathi'}
      ], 'user_B');

      final userADownloads = storage.getDownloads('user_A');
      final userBDownloads = storage.getDownloads('user_B');

      expect(userADownloads.length, equals(1));
      expect(userADownloads.first['displayFilename'], equals('doc_a.mp3'));

      expect(userBDownloads.length, equals(1));
      expect(userBDownloads.first['displayFilename'], equals('doc_b.mp3'));
    });

    test('DownloadsNotifier deduplicates downloads for same generation session', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
      );

      final notifier = container.read(downloadsProvider.notifier);

      // Create a fake offline file on disk in downloads folder
      final downloadsDir = Directory('${testDocsDir.path}/downloads');
      downloadsDir.createSync(recursive: true);
      final testAudioFile = File('${downloadsDir.path}/audio_existing.mp3');
      testAudioFile.writeAsBytesSync([1, 2, 3, 4, 5]);

      final initialModel = DownloadModel(
        id: 'existing_dl',
        userId: 'guest',
        displayFilename: 'lecture.mp3',
        relativeFilePath: 'downloads/audio_existing.mp3',
        fileSize: 5,
        language: 'english',
        generationSessionId: 'session_unique_101',
        downloadDate: DateTime.now(),
      );

      await storage.saveDownloads([initialModel.toJson()], 'guest');
      await notifier.loadDownloads('guest');

      expect(container.read(downloadsProvider).downloads.length, equals(1));

      // Attempt to save again with the same generation session
      final result = await notifier.saveAudioToLibrary(
        audioUrl: '/api/audio/lecture.mp3',
        baseUrl: 'http://localhost:5000',
        displayFilename: 'lecture.mp3',
        language: 'english',
        generationSessionId: 'session_unique_101',
      );

      // Should return existing item and NOT add duplicate to the list
      expect(result?.id, equals('existing_dl'));
      expect(container.read(downloadsProvider).downloads.length, equals(1));
    });

    test('DownloadsNotifier rename and delete maintain consistent state', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
      );

      final notifier = container.read(downloadsProvider.notifier);

      // Create fake file
      final downloadsDir = Directory('${testDocsDir.path}/downloads');
      downloadsDir.createSync(recursive: true);
      final testFile = File('${downloadsDir.path}/audio_test.mp3');
      testFile.writeAsBytesSync([10, 20, 30]);

      final item = DownloadModel(
        id: 'item_1',
        userId: 'guest',
        displayFilename: 'chapter_1.mp3',
        relativeFilePath: 'downloads/audio_test.mp3',
        fileSize: 3,
        language: 'english',
        downloadDate: DateTime.now(),
      );

      await storage.saveDownloads([item.toJson()], 'guest');
      await notifier.loadDownloads('guest');

      // 1. Rename
      final renamedSuccess = await notifier.renameDownload('item_1', 'Biology Chapter 1');
      expect(renamedSuccess, isTrue);

      final renamedItem = container.read(downloadsProvider).downloads.first;
      expect(renamedItem.displayFilename, equals('Biology Chapter 1.mp3'));
      // File path remains unchanged
      expect(renamedItem.relativeFilePath, equals('downloads/audio_test.mp3'));

      // 2. Delete
      final deleteSuccess = await notifier.deleteDownload('item_1');
      expect(deleteSuccess, isTrue);
      expect(container.read(downloadsProvider).downloads.isEmpty, isTrue);
      expect(testFile.existsSync(), isFalse);
    });
  });

  group('Part A & B: UI Integration Tests for Settings and Downloads Screens', () {
    testWidgets('SettingsScreen renders 4 simplified sections and interactive controls', (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the 4 simplified section titles are displayed
      expect(find.text('1. Reading & Display'), findsOneWidget);
      expect(find.text('2. Text to Speech'), findsOneWidget);
      expect(find.text('3. Speech to Text'), findsOneWidget);
      expect(find.text('4. Transcript Synchronisation'), findsOneWidget);

      // Verify Audio Playback and Downloads sections are removed from UI
      expect(find.text('5. Audio Playback'), findsNothing);
      expect(find.text('Audio Playback'), findsNothing);
      expect(find.text('6. Downloads'), findsNothing);
      expect(find.text('In-App Downloads Library'), findsNothing);

      // Verify Reader Preview box is present
      expect(find.textContaining('PREVIEW'), findsOneWidget);

      // Verify Appearance offers only Light and Dark (helper text: Light or dark theme)
      expect(find.text('Light or dark theme'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Auto'), findsNothing);
      expect(find.text('System'), findsNothing);

      // Verify Settings top-right action icon is removed
      final appBarFinder = find.byType(AppBar);
      expect(appBarFinder, findsOneWidget);
      final appBar = tester.widget<AppBar>(appBarFinder);
      expect(appBar.actions, isNull);
    });

    testWidgets('DownloadsScreen displays clean empty state when no downloads exist', (tester) async {
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
          child: const MaterialApp(
            home: DownloadsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No downloaded audio yet'), findsOneWidget);
      expect(find.text('Generate speech from a document, then choose Download Audio.'), findsOneWidget);
      expect(find.textContaining('Files stored inside Readora are private'), findsOneWidget);
    });

    testWidgets('DownloadsScreen displays download cards with metadata and action menu', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      final downloadsDir = Directory('${testDocsDir.path}/downloads');
      downloadsDir.createSync(recursive: true);
      final fakeAudio = File('${downloadsDir.path}/audio_card_test.mp3');
      fakeAudio.writeAsBytesSync([1, 2, 3, 4]);

      await storage.saveDownloads([
        {
          'id': 'card_test_id',
          'userId': 'guest',
          'displayFilename': 'Physics_Notes.mp3',
          'relativeFilePath': 'downloads/audio_card_test.mp3',
          'fileSize': 1048576, // 1 MB
          'durationMs': 75000, // 01:15
          'language': 'english',
          'downloadDate': DateTime(2026, 10, 13).toIso8601String(),
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

      // Verify card elements
      expect(find.text('Physics_Notes.mp3'), findsOneWidget);
      expect(find.text('ENGLISH'), findsOneWidget);
      expect(find.text('1.0 MB'), findsOneWidget);
      expect(find.text('•  01:15'), findsOneWidget);

      // Verify play icon and 3-dot popup menu
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    });
  });
}
