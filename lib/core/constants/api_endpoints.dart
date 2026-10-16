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
  static const String profile = '/auth/profile';
  static const String avatar = '/auth/avatar';
  static const String verifyPhone = '/auth/verify-phone';
  static const String resendPhoneOtp = '/auth/resend-phone-otp';
  static const String forgotPasswordLookup = '/auth/forgot-password/lookup';
  static const String forgotPasswordSendOtp = '/auth/forgot-password/send-otp';
  static const String forgotPasswordVerifyOtp = '/auth/forgot-password/verify-otp';
  static const String forgotPasswordReset = '/auth/forgot-password/reset';

  /// Resolves relative avatar path (e.g. /uploads/avatars/...) to a full URL using current base URL
  static String? resolveAvatarUrl(String? avatarPath, String baseUrl) {
    if (avatarPath == null || avatarPath.isEmpty) return null;
    if (avatarPath.startsWith('http://') || avatarPath.startsWith('https://')) {
      return avatarPath;
    }
    // Remove '/api' suffix from baseUrl if present
    String origin = baseUrl;
    if (origin.endsWith('/api')) {
      origin = origin.substring(0, origin.length - 4);
    } else if (origin.endsWith('/api/')) {
      origin = origin.substring(0, origin.length - 5);
    }
    final cleanPath = avatarPath.startsWith('/') ? avatarPath : '/$avatarPath';
    return '$origin$cleanPath';
  }

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
