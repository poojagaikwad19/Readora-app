import 'timed_word.dart';

class AudioSttResult {
  final bool success;
  final String transcript;
  final String language;
  final double confidence;
  final List<TimedWord> timedWords;
  final String? audioPath;
  final String? errorMessage;
  final Map<String, dynamic>? timings;
  final String? device;
  final String? model;
  final String? gpuName;
  final int? roundtripMs;

  const AudioSttResult({
    required this.success,
    required this.transcript,
    required this.language,
    this.confidence = 0.95,
    this.timedWords = const [],
    this.audioPath,
    this.errorMessage,
    this.timings,
    this.device,
    this.model,
    this.gpuName,
    this.roundtripMs,
  });

  int get uploadMs => timings?['uploadMs'] is int ? timings!['uploadMs'] as int : 0;
  int get queueWaitMs => timings?['queueWaitMs'] is int ? timings!['queueWaitMs'] as int : 0;
  int get modelInitMs => timings?['modelInitMs'] is int ? timings!['modelInitMs'] as int : 0;
  int get decodingMs => timings?['decodingMs'] is int ? timings!['decodingMs'] as int : 0;
  int get transcriptionMs => timings?['transcriptionMs'] is int ? timings!['transcriptionMs'] as int : 0;
  int get backendTotalMs => timings?['backendTotalMs'] is int ? timings!['backendTotalMs'] as int : 0;

  factory AudioSttResult.fromJson(Map<String, dynamic> json, {int? roundtripMs}) {
    final rawWords = json['words'] as List? ?? [];
    final rawTimings = json['timings'] is Map<String, dynamic>
        ? json['timings'] as Map<String, dynamic>
        : (json['timings'] is Map ? Map<String, dynamic>.from(json['timings'] as Map) : null);

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
      timings: rawTimings,
      device: json['device']?.toString(),
      model: json['model']?.toString(),
      gpuName: json['gpuName']?.toString(),
      roundtripMs: roundtripMs,
    );
  }

  factory AudioSttResult.failure(String message, {int? roundtripMs}) {
    return AudioSttResult(
      success: false,
      transcript: '',
      language: 'en',
      errorMessage: message,
      roundtripMs: roundtripMs,
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
    'timings': timings,
    'device': device,
    'model': model,
    'gpuName': gpuName,
    'roundtripMs': roundtripMs,
  };
}
