library readora_audio_stt;

// Config
export 'config/stt_config.dart';
export 'config/stt_language.dart';

// Domain
export 'domain/audio_stt_result.dart';
export 'domain/timed_word.dart';
export 'domain/live_stt_event.dart';

// Services
export 'services/audio_file_stt_service.dart';
export 'services/live_stt_websocket_service.dart';
export 'services/live_mic_recorder_service.dart';

// Presentation
export 'presentation/providers/audio_stt_provider.dart';
export 'presentation/widgets/language_segmented_control.dart';
export 'presentation/widgets/live_recording_visualizer.dart';

// Utils
export 'utils/audio_format_validator.dart';
