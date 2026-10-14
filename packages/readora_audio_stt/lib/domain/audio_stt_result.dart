import 'timed_word.dart';

class AudioSttResult {
  final bool success;
  final String transcript;
  final String language;
  final double confidence;
  final List<TimedWord> timedWords;
  final String? audioPath;
  final String? errorMessage;

  const AudioSttResult({
    required this.success,
    required this.transcript,
    required this.language,
    this.confidence = 0.95,
    this.timedWords = const [],
    this.audioPath,
    this.errorMessage,
  });

  factory AudioSttResult.fromJson(Map<String, dynamic> json) {
    final rawWords = json['words'] as List? ?? [];
    return AudioSttResult(
      success: json['success'] == true,
      transcript: json['transcript']?.toString() ?? '',
      language: json['language']?.toString() ?? 'en',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.95,
      timedWords: rawWords
          .map((w) => TimedWord.fromJson(Map<String, dynamic>.from(w)))
          .toList(),
      audioPath: json['audioPath']?.toString(),
      errorMessage: json['message']?.toString(),
    );
  }

  factory AudioSttResult.failure(String message) {
    return AudioSttResult(
      success: false,
      transcript: '',
      language: 'en',
      errorMessage: message,
    );
  }

  Map<String, dynamic> toJson() => {
    'success': success,
    'transcript': transcript,
    'language': language,
    'confidence': confidence,
    'words': timedWords.map((w) => w.toJson()).toList(),
    'audioPath': audioPath,
    'errorMessage': errorMessage,
  };
}
