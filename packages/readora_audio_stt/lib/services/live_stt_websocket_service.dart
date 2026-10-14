import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../config/stt_config.dart';
import '../config/stt_language.dart';
import '../domain/live_stt_event.dart';
import '../domain/timed_word.dart';

class LiveSttWebSocketService {
  final SttConfig config;
  WebSocket? _socket;
  StreamSubscription? _socketSubscription;

  LiveSttWebSocketService({required this.config});

  /// Connect to backend WebSocket and stream microphone PCM chunks
  Stream<LiveSttEvent> streamAudioChunks({
    required Stream<Uint8List> pcmStream,
    required SttLanguage language,
    required String jwtToken,
  }) {
    final controller = StreamController<LiveSttEvent>.broadcast();
    StreamSubscription<Uint8List>? audioSub;

    () async {
      try {
        final cleanWsUrl = config.baseWsUrl.endsWith('/')
            ? config.baseWsUrl.substring(0, config.baseWsUrl.length - 1)
            : config.baseWsUrl;

        final tokenParam = jwtToken.replaceFirst(RegExp(r'^Bearer\s+'), '');
        final uri = Uri.parse(
          '$cleanWsUrl/api/files/live-stt?token=$tokenParam&language=${language.code}&bcp47=${language.bcp47}&sampleRate=${config.sampleRate}',
        );

        _socket = await WebSocket.connect(uri.toString())
            .timeout(Duration(seconds: config.timeoutSeconds));

        // 1. Pipe incoming PCM audio bytes to the backend WebSocket
        audioSub = pcmStream.listen(
          (Uint8List chunk) {
            if (_socket != null && _socket!.readyState == WebSocket.open) {
              _socket!.add(chunk);
            }
          },
          onError: (err) {
            controller.add(LiveSttErrorEvent('Microphone stream error: $err'));
          },
          onDone: () {
            if (_socket != null && _socket!.readyState == WebSocket.open) {
              _socket!.add(jsonEncode({'action': 'STOP'}));
            }
          },
        );

        // 2. Receive transcripts emitted by backend
        _socketSubscription = _socket!.listen(
          (message) {
            try {
              final data = message is String ? jsonDecode(message) : {};
              if (data['error'] != null) {
                controller.add(LiveSttErrorEvent(data['error'].toString()));
                return;
              }

              final isFinal = data['isFinal'] == true;
              final transcript = data['transcript']?.toString() ?? '';
              final confidence = (data['confidence'] as num?)?.toDouble() ?? 0.95;
              final wordsRaw = data['words'] as List? ?? [];
              final timedWords = wordsRaw
                  .map((w) => TimedWord.fromJson(Map<String, dynamic>.from(w)))
                  .toList();

              if (isFinal) {
                controller.add(LiveSttFinalEvent(
                  transcript: transcript,
                  confidence: confidence,
                  words: timedWords,
                ));
              } else {
                controller.add(LiveSttInterimEvent(partialTranscript: transcript));
              }
            } catch (e) {
              controller.add(LiveSttErrorEvent('Failed to parse STT message: $e'));
            }
          },
          onError: (err) {
            controller.add(LiveSttErrorEvent('WebSocket connection error: $err'));
          },
          onDone: () {
            controller.close();
          },
        );
      } catch (e) {
        controller.add(LiveSttErrorEvent('Failed to establish live STT connection: $e'));
        controller.close();
      }
    }();

    controller.onCancel = () {
      audioSub?.cancel();
      disconnect();
    };

    return controller.stream;
  }

  void disconnect() {
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _socket?.close();
    _socket = null;
  }
}
