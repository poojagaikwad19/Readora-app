import 'dart:io';
import 'package:path/path.dart' as p;

class AudioFormatValidator {
  static const Set<String> supportedExtensions = {
    '.mp3',
    '.wav',
    '.m4a',
    '.aac',
    '.ogg',
    '.flac',
    '.opus',
    '.webm',
    '.amr',
    '.3gp',
    '.mp4',
    '.wma',
  };

  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50MB

  static void validate(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('Audio file not found at path: $filePath');
    }

    final ext = p.extension(filePath).toLowerCase();
    if (!supportedExtensions.contains(ext)) {
      throw Exception(
        'Unsupported audio format: "$ext". Supported formats are: ${supportedExtensions.join(', ')}',
      );
    }

    final length = file.lengthSync();
    if (length <= 0) {
      throw Exception('Audio file is empty (0 bytes).');
    }

    if (length > maxFileSizeBytes) {
      final sizeMb = (length / (1024 * 1024)).toStringAsFixed(1);
      throw Exception('Audio file size (${sizeMb}MB) exceeds maximum limit of 50MB.');
    }
  }
}
