class TimedWord {
  final String word;
  final int startMs;
  final int endMs;
  final double confidence;

  const TimedWord({
    required this.word,
    required this.startMs,
    required this.endMs,
    this.confidence = 1.0,
  });

  factory TimedWord.fromJson(Map<String, dynamic> json) {
    return TimedWord(
      word: json['word']?.toString() ?? '',
      startMs: (json['startMs'] as num?)?.toInt() ?? 
               ((json['start'] as num?) != null ? ((json['start'] as num) * 1000).round() : 0),
      endMs: (json['endMs'] as num?)?.toInt() ?? 
             ((json['end'] as num?) != null ? ((json['end'] as num) * 1000).round() : 0),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'word': word,
    'startMs': startMs,
    'endMs': endMs,
    'confidence': confidence,
  };
}
