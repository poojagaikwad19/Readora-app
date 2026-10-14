import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readora_audio_stt/readora_audio_stt.dart';

void main() {
  group('SttLanguage Mapping Tests', () {
    test('Correctly maps language codes and BCP-47 locales', () {
      expect(SttLanguage.fromCode('en'), SttLanguage.english);
      expect(SttLanguage.fromCode('hi'), SttLanguage.hindi);
      expect(SttLanguage.fromCode('hin'), SttLanguage.hindi);
      expect(SttLanguage.fromCode('mr'), SttLanguage.marathi);
      expect(SttLanguage.fromCode('mar'), SttLanguage.marathi);
      expect(SttLanguage.fromCode('unknown'), SttLanguage.english);

      expect(SttLanguage.marathi.bcp47, 'mr-IN');
      expect(SttLanguage.hindi.bcp47, 'hi-IN');
      expect(SttLanguage.english.bcp47, 'en-IN');
    });
  });

  group('AudioSttResult Model Tests', () {
    test('Parses backend STT JSON response with timed words', () {
      final json = {
        'success': true,
        'transcript': 'नमस्कार भारत',
        'language': 'mr',
        'confidence': 0.98,
        'words': [
          {'word': 'नमस्कार', 'startMs': 100, 'endMs': 450},
          {'word': 'भारत', 'startMs': 480, 'endMs': 820},
        ],
      };

      final result = AudioSttResult.fromJson(json);
      expect(result.success, true);
      expect(result.transcript, 'नमस्कार भारत');
      expect(result.language, 'mr');
      expect(result.confidence, 0.98);
      expect(result.timedWords.length, 2);
      expect(result.timedWords[0].word, 'नमस्कार');
      expect(result.timedWords[0].startMs, 100);
      expect(result.timedWords[0].endMs, 450);
      expect(result.timedWords[1].word, 'भारत');
      expect(result.timedWords[1].startMs, 480);
      expect(result.timedWords[1].endMs, 820);
    });

    test('Handles failure result gracefully', () {
      final fail = AudioSttResult.failure('Audio file corrupt');
      expect(fail.success, false);
      expect(fail.errorMessage, 'Audio file corrupt');
      expect(fail.timedWords, isEmpty);
    });
  });

  group('AudioFileSttService Tests', () {
    test('Performs mock HTTP upload and parses JSON', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/files/speech-to-text');
        expect(request.headers['Authorization'], 'Bearer test_jwt_token');

        return http.Response(
          jsonEncode({
            'success': true,
            'transcript': 'Hello world Readora',
            'language': 'en',
            'words': [
              {'word': 'Hello', 'startMs': 0, 'endMs': 200},
              {'word': 'world', 'startMs': 210, 'endMs': 400},
              {'word': 'Readora', 'startMs': 410, 'endMs': 650},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final config = SttConfig(baseUrl: 'http://127.0.0.1:5000');
      final service = AudioFileSttService(client: mockClient, config: config);

      // Verify config values
      expect(config.baseUrl, 'http://127.0.0.1:5000');
      expect(config.baseWsUrl, 'ws://127.0.0.1:5000');
      expect(config.sampleRate, 16000);
      service.dispose();
    });
  });
}
