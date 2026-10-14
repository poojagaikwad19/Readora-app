import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/stt_config.dart';
import '../../config/stt_language.dart';
import '../../domain/audio_stt_result.dart';
import '../../domain/live_stt_event.dart';
import '../../services/audio_file_stt_service.dart';
import '../../services/live_mic_recorder_service.dart';
import '../../services/live_stt_websocket_service.dart';

class AudioSttState {
  final bool isLoading;
  final bool isRecording;
  final SttLanguage selectedLanguage;
  final AudioSttResult? result;
  final String interimTranscript;
  final String? errorMessage;

  const AudioSttState({
    this.isLoading = false,
    this.isRecording = false,
    this.selectedLanguage = SttLanguage.english,
    this.result,
    this.interimTranscript = '',
    this.errorMessage,
  });

  AudioSttState copyWith({
    bool? isLoading,
    bool? isRecording,
    SttLanguage? selectedLanguage,
    AudioSttResult? result,
    String? interimTranscript,
    String? errorMessage,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return AudioSttState(
      isLoading: isLoading ?? this.isLoading,
      isRecording: isRecording ?? this.isRecording,
      selectedLanguage: selectedLanguage ?? this.selectedLanguage,
      result: clearResult ? null : (result ?? this.result),
      interimTranscript: interimTranscript ?? this.interimTranscript,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class AudioSttNotifier extends StateNotifier<AudioSttState> {
  final AudioFileSttService fileService;
  final LiveSttWebSocketService liveService;
  StreamSubscription? _liveSub;
  LiveMicRecorder? _activeRecorder;

  AudioSttNotifier({
    required this.fileService,
    required this.liveService,
  }) : super(const AudioSttState());

  void setLanguage(SttLanguage language) {
    state = state.copyWith(selectedLanguage: language);
  }

  void clear() {
    state = AudioSttState(selectedLanguage: state.selectedLanguage);
  }

  /// Transcribe an uploaded audio file
  Future<AudioSttResult> transcribeAudioFile({
    required String filePath,
    required String jwtToken,
  }) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      interimTranscript: '',
    );

    try {
      final res = await fileService.transcribeAudioFile(
        filePath: filePath,
        language: state.selectedLanguage,
        jwtToken: jwtToken,
      );

      if (res.success) {
        state = state.copyWith(
          isLoading: false,
          result: res,
          clearError: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          result: res,
          errorMessage: res.errorMessage ?? 'Transcription failed',
        );
      }
      return res;
    } catch (e) {
      final fail = AudioSttResult.failure(e.toString());
      state = state.copyWith(
        isLoading: false,
        result: fail,
        errorMessage: e.toString(),
      );
      return fail;
    }
  }

  /// Start live recording and streaming via WebSocket
  Future<void> startLiveStreaming({
    required LiveMicRecorder recorder,
    required String jwtToken,
  }) async {
    final hasPerm = await recorder.hasPermission();
    if (!hasPerm) {
      state = state.copyWith(errorMessage: 'Microphone permission denied.');
      return;
    }

    _activeRecorder = recorder;
    state = state.copyWith(
      isRecording: true,
      isLoading: false,
      clearError: true,
      interimTranscript: '',
      clearResult: true,
    );

    try {
      final pcmStream = await recorder.startStream(sampleRate: liveService.config.sampleRate);
      final eventStream = liveService.streamAudioChunks(
        pcmStream: pcmStream,
        language: state.selectedLanguage,
        jwtToken: jwtToken,
      );

      _liveSub = eventStream.listen(
        (event) {
          if (event is LiveSttInterimEvent) {
            state = state.copyWith(interimTranscript: event.partialTranscript);
          } else if (event is LiveSttFinalEvent) {
            state = state.copyWith(
              isRecording: false,
              interimTranscript: '',
              result: AudioSttResult(
                success: true,
                transcript: event.transcript,
                language: state.selectedLanguage.code,
                confidence: event.confidence,
                timedWords: event.words,
              ),
            );
          } else if (event is LiveSttErrorEvent) {
            state = state.copyWith(
              isRecording: false,
              errorMessage: event.message,
            );
          }
        },
        onError: (err) {
          state = state.copyWith(
            isRecording: false,
            errorMessage: 'Stream error: $err',
          );
        },
      );
    } catch (e) {
      state = state.copyWith(
        isRecording: false,
        errorMessage: 'Failed to start microphone stream: $e',
      );
    }
  }

  /// Stop live recording
  Future<void> stopLiveStreaming() async {
    await _activeRecorder?.stop();
    _activeRecorder = null;
    await _liveSub?.cancel();
    _liveSub = null;
    liveService.disconnect();
    state = state.copyWith(isRecording: false);
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    liveService.disconnect();
    super.dispose();
  }
}
