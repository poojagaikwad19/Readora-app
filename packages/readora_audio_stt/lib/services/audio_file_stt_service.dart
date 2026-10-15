import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../config/stt_config.dart';
import '../config/stt_language.dart';
import '../domain/audio_stt_result.dart';
import '../utils/audio_format_validator.dart';

class AudioFileSttService {
  final http.Client _client;
  final SttConfig config;
  String? successfulBaseUrl;

  AudioFileSttService({
    http.Client? client,
    required this.config,
  }) : _client = client ?? http.Client();

  /// Transcribe an audio file using the Readora backend Speech-to-Text API,
  /// trying candidate endpoints if the primary endpoint is unreachable.
  Future<AudioSttResult> transcribeAudioFile({
    required String filePath,
    required SttLanguage language,
    required String jwtToken,
  }) async {
    // 1. Validate file existence, format, and size
    AudioFormatValidator.validate(filePath);

    final fileName = p.basename(filePath);
    final allBaseUrls = <String>[
      config.baseUrl,
      ...config.candidateBaseUrls,
    ].where((u) => u.trim().isNotEmpty).toSet().toList();

    AudioSttResult? lastFailure;

    for (final rawBase in allBaseUrls) {
      final cleanBaseUrl = rawBase.endsWith('/')
          ? rawBase.substring(0, rawBase.length - 1)
          : rawBase;
      final uri = Uri.parse('$cleanBaseUrl/api/files/speech-to-text');

      try {
        final request = http.MultipartRequest('POST', uri);
        if (jwtToken.isNotEmpty) {
          request.headers['Authorization'] = jwtToken.startsWith('Bearer ')
              ? jwtToken
              : 'Bearer $jwtToken';
        }

        request.fields['language'] = language.code;
        request.fields['bcp47'] = language.bcp47;

        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: fileName,
          ),
        );

        final streamedResponse = await _client
            .send(request)
            .timeout(Duration(seconds: config.timeoutSeconds));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200 || response.statusCode == 201) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            successfulBaseUrl = cleanBaseUrl;
            return AudioSttResult.fromJson(decoded);
          }
          lastFailure = AudioSttResult.failure('Unexpected response format from server');
        } else {
          String errorMsg = 'Transcription failed with HTTP ${response.statusCode}';
          try {
            final errorBody = jsonDecode(response.body);
            if (errorBody is Map && errorBody['message'] != null) {
              errorMsg = errorBody['message'].toString();
            }
          } catch (_) {}
          lastFailure = AudioSttResult.failure(errorMsg);
        }
      } catch (e) {
        lastFailure = AudioSttResult.failure('Failed connecting to $cleanBaseUrl: $e');
      }
    }

    return lastFailure ??
        AudioSttResult.failure('Transcription request failed across all candidate endpoints');
  }

  void dispose() {
    _client.close();
  }
}
