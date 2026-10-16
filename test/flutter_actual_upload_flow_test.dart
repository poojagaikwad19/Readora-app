import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readora_audio_stt/readora_audio_stt.dart';
import 'package:texttospeech/features/document_tts/domain/document_model.dart';
import 'package:texttospeech/features/document_tts/domain/timed_word_model.dart' as tts_model;

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  const String backendBaseUrl = 'http://127.0.0.1:5000';
  const String audioFilePathEn = r'C:\Projects\Readora\backend\uploads\audio\readora_english_CwhRBWXz_1789538667615-820128.mp3';
  const String audioFilePathMr = r'C:\Projects\Readora\backend\uploads\test_mr.mp3';
  const String audioFilePathHi = r'C:\Projects\Readora\backend\uploads\test_hi.mp3';

  group('Actual Flutter Upload Flow Diagnosis & Consecutive Timings', () {
    test('Diagnose live upload flow, compare Request 1 vs Request 2, and log timing breakdown', () async {
      final audioFile = File(audioFilePathEn);
      expect(audioFile.existsSync(), isTrue, reason: 'Test audio file must exist at $audioFilePathEn');

      final sttService = AudioFileSttService(
        config: SttConfig(
          baseUrl: backendBaseUrl,
          candidateBaseUrls: const [],
          timeoutSeconds: 30,
        ),
      );

      print('\n=================================================================================');
      print('>>> RUNNING ACTUAL FLUTTER UPLOAD FLOW: REQUEST 1 (Initial Request)');
      print('=================================================================================');

      final req1Watch = Stopwatch()..start();
      final result1 = await sttService.transcribeAudioFile(
        filePath: audioFilePathEn,
        language: SttLanguage.english,
        jwtToken: '',
      );
      req1Watch.stop();

      final renderWatch1 = Stopwatch()..start();
      final doc1 = DocumentModel(
        docId: 'stt_req1',
        filename: 'readora_english_19s.mp3',
        text: result1.transcript,
        detectedLanguage: result1.language,
        wordCount: result1.transcript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
        characterCount: result1.transcript.length,
        timedWords: result1.timedWords.map((w) => tts_model.TimedWord(text: w.word, startMs: w.startMs, endMs: w.endMs)).toList(),
      );
      renderWatch1.stop();

      expect(result1.success, isTrue, reason: 'Request 1 should succeed: ${result1.errorMessage}');
      expect(result1.transcript.isNotEmpty, isTrue);
      expect(result1.timedWords.isNotEmpty, isTrue);

      final t1Upload = result1.uploadMs;
      final t1Queue = result1.queueWaitMs;
      final t1Init = result1.modelInitMs;
      final t1Decode = result1.decodingMs;
      final t1Transcribe = result1.transcriptionMs;
      final t1Backend = result1.backendTotalMs;
      final t1Roundtrip = result1.roundtripMs ?? req1Watch.elapsedMilliseconds;
      final t1Render = renderWatch1.elapsedMilliseconds;
      final t1TotalEndToEnd = t1Roundtrip + t1Render;

      print('\n=================================================================================');
      print('>>> RUNNING ACTUAL FLUTTER UPLOAD FLOW: REQUEST 2 (Second Consecutive Request)');
      print('=================================================================================');

      final req2Watch = Stopwatch()..start();
      final result2 = await sttService.transcribeAudioFile(
        filePath: audioFilePathEn,
        language: SttLanguage.english,
        jwtToken: '',
      );
      req2Watch.stop();

      final renderWatch2 = Stopwatch()..start();
      final doc2 = DocumentModel(
        docId: 'stt_req2',
        filename: 'readora_english_19s.mp3',
        text: result2.transcript,
        detectedLanguage: result2.language,
        wordCount: result2.transcript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
        characterCount: result2.transcript.length,
        timedWords: result2.timedWords.map((w) => tts_model.TimedWord(text: w.word, startMs: w.startMs, endMs: w.endMs)).toList(),
      );
      renderWatch2.stop();

      expect(result2.success, isTrue, reason: 'Request 2 should succeed: ${result2.errorMessage}');
      expect(result2.transcript, equals(result1.transcript));
      expect(result2.timedWords.length, equals(result1.timedWords.length));

      final t2Upload = result2.uploadMs;
      final t2Queue = result2.queueWaitMs;
      final t2Init = result2.modelInitMs;
      final t2Decode = result2.decodingMs;
      final t2Transcribe = result2.transcriptionMs;
      final t2Backend = result2.backendTotalMs;
      final t2Roundtrip = result2.roundtripMs ?? req2Watch.elapsedMilliseconds;
      final t2Render = renderWatch2.elapsedMilliseconds;
      final t2TotalEndToEnd = t2Roundtrip + t2Render;

      print('\n' + '=' * 81);
      print('               READORA SPEECH-TO-TEXT TIMING COMPARISON REPORT');
      print('                 (19.10-Second Recording Consecutive Test)');
      print('=' * 81);
      print(String.fromCharCodes(Iterable.generate(81, (_) => 0x2D)));
      print(' Metric / Phase                 | Request 1 (Initial)  | Request 2 (Warm Worker)');
      print(String.fromCharCodes(Iterable.generate(81, (_) => 0x2D)));
      print(' 1. Upload (HTTP multipart)     | ${t1Upload.toString().padRight(17)} ms | ${t2Upload.toString().padRight(17)} ms');
      print(' 2. Queue Wait (Concurrency)   | ${t1Queue.toString().padRight(17)} ms | ${t2Queue.toString().padRight(17)} ms');
      print(' 3. Model Initialization        | ${t1Init.toString().padRight(17)} ms | ${t2Init.toString().padRight(17)} ms');
      print(' 4. Decoding & Feature Prep     | ${t1Decode.toString().padRight(17)} ms | ${t2Decode.toString().padRight(17)} ms');
      print(' 5. Neural Transcription (STT)  | ${t1Transcribe.toString().padRight(17)} ms | ${t2Transcribe.toString().padRight(17)} ms');
      print(' 6. Backend Total Processing    | ${t1Backend.toString().padRight(17)} ms | ${t2Backend.toString().padRight(17)} ms');
      print(' 7. Flutter Network Roundtrip   | ${t1Roundtrip.toString().padRight(17)} ms | ${t2Roundtrip.toString().padRight(17)} ms');
      print(' 8. Flutter Rendering / Model   | ${t1Render.toString().padRight(17)} ms | ${t2Render.toString().padRight(17)} ms');
      print(String.fromCharCodes(Iterable.generate(81, (_) => 0x2D)));
      print(' TOTAL END-TO-END LATENCY       | ${t1TotalEndToEnd.toString().padRight(17)} ms | ${t2TotalEndToEnd.toString().padRight(17)} ms');
      print(' Active Device / GPU            | ${result1.device?.toUpperCase() ?? "CUDA"} (${result1.gpuName ?? "RTX 2050"})');
      print(' Whisper Model                  | ${result1.model ?? "large-v3-turbo"} (Reusable In-Memory Worker)');
      print(' Word Timestamps Captured       | ${result2.timedWords.length} words');
      print(' Transcript Sample              | "${doc2.text.substring(0, 50)}..."');
      print('=' * 81 + '\n');

      sttService.dispose();
    });

    test('Verify Marathi & Hindi Accuracy and Word Timestamps on Persistent CUDA Worker', () async {
      final sttService = AudioFileSttService(
        config: SttConfig(
          baseUrl: backendBaseUrl,
          candidateBaseUrls: const [],
          timeoutSeconds: 30,
        ),
      );

      // 1. Marathi test
      final mrResult = await sttService.transcribeAudioFile(
        filePath: audioFilePathMr,
        language: SttLanguage.marathi,
        jwtToken: '',
      );
      expect(mrResult.success, isTrue);
      expect(mrResult.language, equals('mr'));
      expect(mrResult.transcript.contains('नमस्कार'), isTrue);
      expect(mrResult.timedWords.isNotEmpty, isTrue);
      print('✅ Marathi STT: "${mrResult.transcript}" (${mrResult.timedWords.length} timed words, ${mrResult.backendTotalMs}ms)');

      // 2. Hindi test
      final hiResult = await sttService.transcribeAudioFile(
        filePath: audioFilePathHi,
        language: SttLanguage.hindi,
        jwtToken: '',
      );
      expect(hiResult.success, isTrue);
      expect(hiResult.language, equals('hi'));
      expect(hiResult.transcript.contains('नमस्ते'), isTrue);
      expect(hiResult.timedWords.isNotEmpty, isTrue);
      print('✅ Hindi STT: "${hiResult.transcript}" (${hiResult.timedWords.length} timed words, ${hiResult.backendTotalMs}ms)');

      sttService.dispose();
    });

    test('Verify Empty / Worker Failure / Error Handling and State Cleanliness', () async {
      final sttService = AudioFileSttService(
        config: SttConfig(
          baseUrl: backendBaseUrl,
          candidateBaseUrls: const [],
          timeoutSeconds: 30,
        ),
      );

      // Create an empty temporary file (0 bytes) to test validation & error handling
      final emptyFile = File('${Directory.systemTemp.path}/empty_audio_test.mp3');
      emptyFile.writeAsBytesSync([]);

      expect(
        () => sttService.transcribeAudioFile(
          filePath: emptyFile.path,
          language: SttLanguage.english,
          jwtToken: '',
        ),
        throwsA(isA<Exception>()),
        reason: 'AudioFormatValidator should cleanly reject 0-byte audio without hanging',
      );

      emptyFile.deleteSync();
      sttService.dispose();
    });
  });
}
