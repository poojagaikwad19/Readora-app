import 'dart:io';

class ApiEndpoints {
  // Default base URL fallback
  // For Android Real Device (ADB reverse / USB): 127.0.0.1:5000
  // For Android Emulator: 10.0.2.2:5000
  // For Local Network / Wi-Fi: 192.168.1.68:5000
  // For iOS / Desktop / Web: localhost:5000
  static String get defaultBaseUrl {
    if (Platform.isAndroid) {
      return 'http://127.0.0.1:5000/api';
    } else {
      return 'http://localhost:5000/api';
    }
  }

  /// List of candidate backend API URLs across local dev environments
  static List<String> get candidateBaseUrls {
    if (Platform.isAndroid) {
      return const [
        'http://127.0.0.1:5000/api',     // USB / ADB Reverse on physical device
        'http://192.168.1.68:5000/api',    // Local Wi-Fi network host
        'http://10.0.2.2:5000/api',        // Android Emulator host loopback
        'http://localhost:5000/api',
      ];
    } else {
      return const [
        'http://localhost:5000/api',
        'http://127.0.0.1:5000/api',
        'http://192.168.1.68:5000/api',
      ];
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
