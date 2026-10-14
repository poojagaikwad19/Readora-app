import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../config/stt_config.dart';
import '../config/stt_language.dart';
import '../domain/audio_stt_result.dart';
import '../utils/audio_format_validator.dart';

class AudioFileSttService {
  final http.Client _client;
  final SttConfig config;

  AudioFileSttService({
    http.Client? client,
    required this.config,
  }) : _client = client ?? http.Client();

  /// Transcribe an audio file using the Readora backend Speech-to-Text API
  Future<AudioSttResult> transcribeAudioFile({
    required String filePath,
    required SttLanguage language,
    required String jwtToken,
  }) async {
    // 1. Validate file existence, format, and size
    AudioFormatValidator.validate(filePath);

    // 2. Prepare multipart request
    final cleanBaseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;
    final uri = Uri.parse('$cleanBaseUrl/api/files/speech-to-text');
    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = jwtToken.startsWith('Bearer ')
        ? jwtToken
        : 'Bearer $jwtToken';

    request.fields['language'] = language.code;
    request.fields['bcp47'] = language.bcp47;

    final fileName = p.basename(filePath);
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        filePath,
        filename: fileName,
      ),
    );

    try {
      // 3. Send request with timeout
      final streamedResponse = await _client
          .send(request)
          .timeout(Duration(seconds: config.timeoutSeconds));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return AudioSttResult.fromJson(decoded);
        }
        return AudioSttResult.failure('Unexpected response format from server');
      } else {
        String errorMsg = 'Transcription failed with HTTP ${response.statusCode}';
        try {
          final errorBody = jsonDecode(response.body);
          if (errorBody is Map && errorBody['message'] != null) {
            errorMsg = errorBody['message'].toString();
          }
        } catch (_) {}
        return AudioSttResult.failure(errorMsg);
      }
    } on SocketException catch (e) {
      return AudioSttResult.failure('Network connection error: ${e.message}');
    } on HttpException catch (e) {
      return AudioSttResult.failure('HTTP error: ${e.message}');
    } catch (e) {
      return AudioSttResult.failure('Transcription request failed: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}
