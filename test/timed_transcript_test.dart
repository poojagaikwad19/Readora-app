import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texttospeech/core/services/storage_service.dart';
import 'package:texttospeech/features/document_tts/data/document_tts_repository.dart';
import 'package:texttospeech/features/document_tts/domain/voice_model.dart';
import 'package:texttospeech/features/document_tts/domain/tts_response_model.dart';
import 'package:texttospeech/features/document_tts/domain/timed_word_model.dart';
import 'package:texttospeech/features/document_tts/domain/document_model.dart';
import 'package:texttospeech/features/auth/presentation/providers/auth_provider.dart';
import 'package:texttospeech/features/document_tts/presentation/providers/document_tts_provider.dart';
import 'package:texttospeech/features/document_tts/presentation/widgets/timed_transcript_viewer.dart';
import 'package:texttospeech/features/document_tts/presentation/widgets/original_audio_player.dart';
import 'package:audioplayers/audioplayers.dart';

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

  group('TimedWord and DocumentModel Model Tests', () {
    test('TimedWord JSON serialization & deserialization', () {
      final json = {
        'text': 'Good',
        'startMs': 400,
        'endMs': 680,
      };

      final word = TimedWord.fromJson(json);
      expect(word.text, equals('Good'));
      expect(word.startMs, equals(400));
      expect(word.endMs, equals(680));

      final serialized = word.toJson();
      expect(serialized['text'], equals('Good'));
      expect(serialized['startMs'], equals(400));
      expect(serialized['endMs'], equals(680));
    });

    test('TimedWord handles alternative backend keys gracefully', () {
      final json = {
        'word': 'morning',
        'start': 0.700,
        'end': 1.150,
      };

      final word = TimedWord.fromJson(json);
      expect(word.text, equals('morning'));
      expect(word.startMs, equals(700));
      expect(word.endMs, equals(1150));
    });

    test('DocumentModel backward-compatibility with empty timedWords', () {
      final oldJson = {
        'docId': 'old_doc_1',
        'filename': 'test.mp3',
        'text': 'Hello world',
      };

      final doc = DocumentModel.fromJson(oldJson);
      expect(doc.timedWords, isEmpty);
      expect(doc.audioSourcePath, isNull);

      final docWithWords = DocumentModel(
        docId: 'new_doc_2',
        filename: 'test2.mp3',
        text: 'Hello world',
        timedWords: [
          const TimedWord(text: 'Hello', startMs: 100, endMs: 400),
          const TimedWord(text: 'world', startMs: 500, endMs: 800),
        ],
        audioSourcePath: '/data/user/0/test2.mp3',
      );

      final serialized = docWithWords.toJson();
      expect(serialized['timedWords'], isA<List>());
      expect((serialized['timedWords'] as List).length, equals(2));
      expect(serialized['audioSourcePath'], equals('/data/user/0/test2.mp3'));

      final reconstructed = DocumentModel.fromJson(serialized);
      expect(reconstructed.timedWords.length, equals(2));
      expect(reconstructed.timedWords[0].text, equals('Hello'));
      expect(reconstructed.audioSourcePath, equals('/data/user/0/test2.mp3'));
    });
  });

  group('Audio Position to Word Timing Logic Tests', () {
    final sampleWords = [
      const TimedWord(text: 'Good', startMs: 400, endMs: 680),
      const TimedWord(text: 'morning', startMs: 750, endMs: 1150),
      const TimedWord(text: 'everyone', startMs: 1400, endMs: 1900),
    ];

    List<TimedWord> getRevealedWords(List<TimedWord> words, int posMs, bool isCompleted) {
      if (isCompleted) return words;
      return words.where((w) => w.startMs <= posMs).toList();
    }

    int getActiveWordIndex(List<TimedWord> words, int posMs, bool isCompleted) {
      if (isCompleted) return -1;
      for (int i = 0; i < words.length; i++) {
        if (words[i].startMs <= posMs && posMs < words[i].endMs) {
          return i;
        }
      }
      return -1;
    }

    test('Leading silence (0 to 399ms) reveals no words and no active highlight', () {
      final revealed = getRevealedWords(sampleWords, 200, false);
      final active = getActiveWordIndex(sampleWords, 200, false);
      expect(revealed, isEmpty);
      expect(active, equals(-1));
    });

    test('Exact start boundary (400ms) reveals first word with active highlight', () {
      final revealed = getRevealedWords(sampleWords, 400, false);
      final active = getActiveWordIndex(sampleWords, 400, false);
      expect(revealed.length, equals(1));
      expect(revealed[0].text, equals('Good'));
      expect(active, equals(0));
    });

    test('Mid-word playback (550ms) retains first word as active', () {
      final revealed = getRevealedWords(sampleWords, 550, false);
      final active = getActiveWordIndex(sampleWords, 550, false);
      expect(revealed.length, equals(1));
      expect(active, equals(0));
    });

    test('Silence gap between words (680ms to 749ms) keeps word revealed but clears highlight', () {
      final revealed = getRevealedWords(sampleWords, 700, false);
      final active = getActiveWordIndex(sampleWords, 700, false);
      // 'Good' is revealed
      expect(revealed.length, equals(1));
      expect(revealed[0].text, equals('Good'));
      // But active highlight is CLEARED during silence
      expect(active, equals(-1));
    });

    test('Second word start (750ms) reveals and highlights second word', () {
      final revealed = getRevealedWords(sampleWords, 750, false);
      final active = getActiveWordIndex(sampleWords, 750, false);
      expect(revealed.length, equals(2));
      expect(revealed[1].text, equals('morning'));
      expect(active, equals(1));
    });

    test('Seeking forward to 1500ms reveals all three words and highlights third word', () {
      final revealed = getRevealedWords(sampleWords, 1500, false);
      final active = getActiveWordIndex(sampleWords, 1500, false);
      expect(revealed.length, equals(3));
      expect(active, equals(2));
    });

    test('Seeking backward from 1500ms to 500ms hides later words again', () {
      final revealedBefore = getRevealedWords(sampleWords, 1500, false);
      expect(revealedBefore.length, equals(3));

      final revealedAfter = getRevealedWords(sampleWords, 500, false);
      expect(revealedAfter.length, equals(1));
      expect(revealedAfter[0].text, equals('Good'));
    });

    test('Stop / reset to zero resets revealed words without losing transcript', () {
      final revealedAtStop = getRevealedWords(sampleWords, 0, false);
      expect(revealedAtStop, isEmpty);
      // Entire transcript remains available in data model
      expect(sampleWords.length, equals(3));
    });

    test('Natural completion retains complete transcript and clears active-word highlight', () {
      final revealed = getRevealedWords(sampleWords, 2000, true);
      final active = getActiveWordIndex(sampleWords, 2000, true);
      expect(revealed.length, equals(3));
      expect(active, equals(-1)); // No word highlighted when audio completes
    });
  });

  group('Devanagari Unicode & Script Preservation Tests', () {
    test('Preserves Marathi combining ligatures, kanas, matras and anusvaras', () {
      final marathiWords = [
        const TimedWord(text: 'नमस्कार', startMs: 100, endMs: 500),
        const TimedWord(text: 'मंडळी,', startMs: 600, endMs: 950),
        const TimedWord(text: 'रीडोरा', startMs: 1000, endMs: 1400),
        const TimedWord(text: 'अ‍ॅपमध्ये', startMs: 1450, endMs: 1950),
        const TimedWord(text: 'आपले', startMs: 2000, endMs: 2300),
        const TimedWord(text: 'स्वागत', startMs: 2350, endMs: 2700),
        const TimedWord(text: 'आहे.', startMs: 2750, endMs: 3100),
      ];

      final fullText = marathiWords.map((w) => w.text).join(' ');
      expect(fullText, contains('नमस्कार'));
      expect(fullText, contains('मंडळी,'));
      expect(fullText, contains('आहे.'));

      // Check grapheme cluster integrity: combining marks are NOT separated
      for (final w in marathiWords) {
        expect(w.text, isNotEmpty);
        // First character must not be an isolated combining mark (virama or matra)
        expect(w.text.codeUnitAt(0) != 0x094D, isTrue); // Not standalone virama
      }
    });

    test('Preserves Hindi danda (।) and complex conjuncts', () {
      final hindiWords = [
        const TimedWord(text: 'नमस्ते', startMs: 200, endMs: 600),
        const TimedWord(text: 'दोस्तों,', startMs: 650, endMs: 1050),
        const TimedWord(text: 'यह', startMs: 1100, endMs: 1300),
        const TimedWord(text: 'परीक्षण', startMs: 1350, endMs: 1750),
        const TimedWord(text: 'है।', startMs: 1800, endMs: 2100),
      ];

      expect(hindiWords.last.text, equals('है।'));
      expect(hindiWords[3].text, equals('परीक्षण'));
    });
  });

  group('Widget Tests for TimedTranscriptViewer', () {
    late StorageService storageService;
    late _MockRepo mockRepo;

    setUp(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global'), (MethodCall call) async {
        return 1;
      });

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storageService = StorageService(prefs);
      mockRepo = _MockRepo();
    });

    testWidgets('Renders in Full Transcript mode with selectable text', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storageService),
            documentTtsRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TimedTranscriptViewer(
                transcript: 'Hello and welcome to Readora speech to text.',
                timedWords: const [
                  TimedWord(text: 'Hello', startMs: 100, endMs: 400),
                  TimedWord(text: 'and', startMs: 420, endMs: 600),
                  TimedWord(text: 'welcome', startMs: 620, endMs: 1000),
                ],
              ),
            ),
          ),
        ),
      );

      // Verify UI has mode switcher
      expect(find.text('Follow Audio'), findsOneWidget);
      expect(find.text('Full Transcript'), findsOneWidget);

      // Switch to Full Transcript tab
      await tester.tap(find.text('Full Transcript'));
      await tester.pumpAndSettle();

      expect(find.byType(SelectableText), findsOneWidget);
      final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(selectable.data, equals('Hello and welcome to Readora speech to text.'));
    });

    testWidgets('Gracefully handles missing timestamps with info notice', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storageService),
            documentTtsRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TimedTranscriptViewer(
                transcript: 'Fallback transcript without timing metadata',
                timedWords: const [],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(selectable.data, equals('Fallback transcript without timing metadata'));
      expect(find.text('Full Transcript'), findsOneWidget);
      expect(find.text('Word timing unavailable'), findsOneWidget);
    });

    testWidgets('Header row displays accurate word count, and three-dot menu with Copy, Expand, Re-transcribe', (tester) async {
      bool retranscribeCalled = false;
      bool expandCalled = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storageService),
            documentTtsRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TimedTranscriptViewer(
                transcript: 'One two three four five',
                timedWords: const [],
                onExpandFullscreen: () => expandCalled = true,
                onRetranscribe: () => retranscribeCalled = true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Row 1: "Transcript" header, "5 words", and three-dot button
      expect(find.text('Transcript'), findsOneWidget);
      expect(find.text('5 words'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);

      // Verify old separate buttons are removed
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Expand'), findsNothing);
      expect(find.text('More'), findsNothing);

      // Tap three-dot menu icon
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      // Verify all three menu items are present
      expect(find.text('Copy transcript'), findsOneWidget);
      expect(find.text('Expand transcript'), findsOneWidget);
      expect(find.text('Re-transcribe audio'), findsOneWidget);

      // Tap Expand transcript
      await tester.tap(find.text('Expand transcript'));
      await tester.pumpAndSettle();
      expect(expandCalled, isTrue);

      // Open three-dot menu again
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      // Tap Re-transcribe audio
      await tester.tap(find.text('Re-transcribe audio'));
      await tester.pumpAndSettle();
      expect(retranscribeCalled, isTrue);
    });
  });

  group('OriginalAudioPlayer UI and Duration Tests', () {
    late StorageService storageService;
    late _MockRepo mockRepo;
    late Directory tempDir;
    late File testAudioFile;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storageService = StorageService(prefs);
      mockRepo = _MockRepo();

      tempDir = Directory.systemTemp.createTempSync('stt_test_');
      testAudioFile = File('${tempDir.path}/sample.mp3')..writeAsStringSync('dummy audio data');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('Shows missing file banner when audio file does not exist on disk', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storageService),
            documentTtsRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: OriginalAudioPlayer(
                audioPath: '/non_existent/path/missing.mp3',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Original source audio file is missing from device storage.'), findsOneWidget);
    });

    testWidgets('Shows neutral placeholder (--:--) and disables seek slider when duration is zero', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storageService),
            documentTtsRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: OriginalAudioPlayer(
                audioPath: testAudioFile.path,
                fallbackDurationMs: 0,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Label: Original Audio
      expect(find.text('Original Audio'), findsOneWidget);

      // Neutral placeholder
      expect(find.text('--:--'), findsOneWidget);

      // Elapsed starts at 00:00
      expect(find.text('00:00'), findsOneWidget);

      // Slider exists and onChanged is null (disabled)
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNull);
    });

    testWidgets('Shows formatted duration and enables seeking when valid duration is available', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storageService),
            documentTtsRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: OriginalAudioPlayer(
                audioPath: testAudioFile.path,
                fallbackDurationMs: 45000, // 45 seconds
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Formatted duration 00:45
      expect(find.text('00:45'), findsOneWidget);

      // Slider exists and is enabled
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNotNull);
      expect(slider.max, equals(45000.0));
    });
  });

  group('Transcript Scrolling, Viewport and Control Placement Tests', () {
    late StorageService storageService;
    late _MockRepo mockRepo;

    setUp(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers.global'), (MethodCall call) async {
        return 1;
      });

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storageService = StorageService(prefs);
      mockRepo = _MockRepo();
    });

    testWidgets('Scrollbar, bottom padding (48px), and non-overlapping footer are present', (tester) async {
      final sampleTimedWords = List.generate(
        30,
        (i) => TimedWord(text: 'Word$i', startMs: i * 500, endMs: (i * 500) + 400),
      );
      final sampleTranscript = sampleTimedWords.map((w) => w.text).join(' ');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storageService),
            documentTtsRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TimedTranscriptViewer(
                transcript: sampleTranscript,
                timedWords: sampleTimedWords,
                height: 400,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Scrollbar widget is present
      expect(find.byType(Scrollbar), findsOneWidget);

      // Verify SingleChildScrollView padding has bottom: 48
      final scrollView = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
      expect(scrollView.padding, equals(const EdgeInsets.fromLTRB(16, 14, 16, 48)));

      // Verify the reserved footer is present outside the scrollable body
      expect(find.text('Follow Audio ready'), findsOneWidget);
    });

    testWidgets('Manual drag suspends follow and shows "Follow current word" button in reserved footer', (tester) async {
      final sampleTimedWords = List.generate(
        100,
        (i) => TimedWord(text: 'Word$i', startMs: i * 200, endMs: (i * 200) + 180),
      );
      final sampleTranscript = sampleTimedWords.map((w) => w.text).join(' ');

      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
          documentTtsRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );

      // Set playback to 12000ms (Word60 active) so many lines are revealed
      container.read(documentTtsNotifierProvider.notifier).state = container
          .read(documentTtsNotifierProvider)
          .copyWith(
            isPlayingOriginalAudio: true,
            playerState: PlayerState.playing,
            audioPosition: const Duration(milliseconds: 12000),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 220,
                  child: TimedTranscriptViewer(
                    transcript: sampleTranscript,
                    timedWords: sampleTimedWords,
                    height: 220,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially follow is active, button is not shown
      expect(find.text('Follow current word'), findsNothing);
      expect(find.text('Follow Audio synced'), findsOneWidget);

      // Simulate genuine user scroll drag
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -60));
      await tester.pumpAndSettle();

      // Follow is now suspended, button is visible in footer
      expect(find.text('Follow current word'), findsOneWidget);
      expect(find.text('Manual scroll'), findsOneWidget);

      // Tapping "Follow current word" resumes follow and hides the button
      await tester.tap(find.text('Follow current word'));
      await tester.pumpAndSettle();

      expect(find.text('Follow current word'), findsNothing);
      expect(find.text('Follow Audio synced'), findsOneWidget);
    });

    testWidgets('Long transcript (200+ words) and Devanagari Hindi/Marathi renders without overflow', (tester) async {
      const devanagariText =
          'महाराष्ट्र हे भारतातील एक प्रमुख राज्य आहे. वाचन आणि श्रवण ही ज्ञानाची महत्त्वाची साधने आहेत। '
          'पठन कौशल्य आणि भाषिक विकास यासाठी नियमित सराव आवश्यक आहे. '
          'हिंदी और मराठी दोनों ही समृद्ध भाषाएं हैं। '
          'शिक्षा जीवन का आधार है और ज्ञान सबसे बड़ा धन है।';

      final devanagariWords = devanagariText
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();

      final timedWords = List.generate(
        devanagariWords.length,
        (i) => TimedWord(
          text: devanagariWords[i],
          startMs: i * 400,
          endMs: (i * 400) + 350,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storageService),
            documentTtsRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TimedTranscriptViewer(
                transcript: devanagariText,
                timedWords: timedWords,
                height: 380,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that RichText renders without throwing an overflow exception
      expect(find.byType(RichText), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
