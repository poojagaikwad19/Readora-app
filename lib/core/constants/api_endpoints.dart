import 'dart:io';

class ApiEndpoints {
  // Default base URL fallback
  // For Android Emulator: 10.0.2.2:5000
  // For iOS / Desktop / Web / Real Device on local network: 127.0.0.1:5000 or custom IP
  static String get defaultBaseUrl {
    if (Platform.isAndroid) {
      return 'http://192.168.1.59:5000/api';
    } else {
      return 'http://localhost:5000/api';
    }
  }

  // Auth Endpoints
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String me = '/auth/me';

  // File & Document Extraction Endpoints
  static const String uploadFile = '/files/upload';
  static const String extractPdf = '/files/extract-pdf';
  static const String getFiles = '/files';
  static String deleteFile(String id) => '/files/$id';
  static String getFileContent(String id) => '/files/$id/content';

  // Text-to-Speech & Speech-to-Text Endpoints
  static const String textToSpeech = '/files/text-to-speech';
  static const String speechToText = '/files/speech-to-text';
  static const String getVoices = '/files/voices';
  static const String translate = '/files/translate';
  static String getAudioUrl(String filename) => '/files/audio/$filename';
}
