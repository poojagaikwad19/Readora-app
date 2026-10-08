import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../domain/document_model.dart';
import '../domain/tts_response_model.dart';
import '../domain/voice_model.dart';

class DocumentTtsRepository {
  final ApiClient _apiClient;

  DocumentTtsRepository(this._apiClient);

  /// Extract text from uploaded PDF/Image/TXT file
  Future<DocumentModel> extractDocument(String filePath) async {
    final response = await _apiClient.uploadFile(
      ApiEndpoints.extractPdf,
      filePath,
      'file',
    );
    return DocumentModel.fromJson(response);
  }

  /// Get list of user documents
  Future<List<DocumentModel>> getUserFiles() async {
    final response = await _apiClient.get(ApiEndpoints.getFiles);
    if (response is Map && response.containsKey('files')) {
      final List filesList = response['files'];
      return filesList.map((e) => DocumentModel.fromJson(e)).toList();
    }
    return [];
  }

  /// Convert text to speech via backend TTS route
  Future<TtsResponseModel> generateSpeech({
    required String text,
    String language = 'english',
    String? voiceId,
    String? documentId,
  }) async {
    final response = await _apiClient.post(ApiEndpoints.textToSpeech, {
      'text': text,
      'language': language,
      if (voiceId != null && voiceId.isNotEmpty) 'voiceId': voiceId,
      if (documentId != null && documentId.isNotEmpty) 'documentId': documentId,
    });
    return TtsResponseModel.fromJson(response);
  }

  /// Fetch available TTS voices
  Future<List<VoiceModel>> fetchVoices() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.getVoices);
      if (response is Map && response.containsKey('voices')) {
        final List voicesList = response['voices'];
        return voicesList.map((e) => VoiceModel.fromJson(e)).toList();
      }
    } catch (_) {}
    return VoiceModel.defaultVoices();
  }

  /// Translate text (e.g. English <-> Marathi <-> Hindi)
  Future<String> translateText(String text, String targetLanguage, {String? sourceLanguage}) async {
    final response = await _apiClient.post(ApiEndpoints.translate, {
      'text': text,
      'targetLanguage': targetLanguage,
      if (sourceLanguage != null && sourceLanguage.isNotEmpty) 'sourceLanguage': sourceLanguage,
    });
    return response['translatedText'] ?? text;
  }

  /// Transcribe audio file via Readora backend API (used for English)
  Future<String> transcribeAudioBackend(String filePath, {String? language}) async {
    final response = await _apiClient.uploadFile(
      ApiEndpoints.speechToText,
      filePath,
      'file',
    );
    if (response is Map && response.containsKey('transcript')) {
      return response['transcript'] ?? '';
    }
    throw ApiException(response['message'] ?? 'Backend audio transcription failed');
  }
}
