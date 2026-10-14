import 'timed_word.dart';

abstract class LiveSttEvent {
  const LiveSttEvent();
}

class LiveSttInterimEvent extends LiveSttEvent {
  final String partialTranscript;
  const LiveSttInterimEvent({required this.partialTranscript});
}

class LiveSttFinalEvent extends LiveSttEvent {
  final String transcript;
  final double confidence;
  final List<TimedWord> words;

  const LiveSttFinalEvent({
    required this.transcript,
    this.confidence = 0.95,
    this.words = const [],
  });
}

class LiveSttErrorEvent extends LiveSttEvent {
  final String message;
  const LiveSttErrorEvent(this.message);
}
