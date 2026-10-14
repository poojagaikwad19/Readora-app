class TimedWord {
  final String text;
  final int startMs;
  final int endMs;

  const TimedWord({
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  factory TimedWord.fromJson(Map<String, dynamic> json) {
    int startVal = 0;
    if (json['startMs'] != null) {
      startVal = (json['startMs'] as num).toInt();
    } else if (json['start'] != null) {
      startVal = ((json['start'] as num).toDouble() * 1000).round();
    }

    int endVal = startVal;
    if (json['endMs'] != null) {
      endVal = (json['endMs'] as num).toInt();
    } else if (json['end'] != null) {
      endVal = ((json['end'] as num).toDouble() * 1000).round();
    }

    return TimedWord(
      text: (json['text'] ?? json['word'] ?? '').toString().trim(),
      startMs: startVal,
      endMs: endVal,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'startMs': startMs,
      'endMs': endMs,
    };
  }

  @override
  String toString() => 'TimedWord($text, $startMs-$endMs ms)';
}
