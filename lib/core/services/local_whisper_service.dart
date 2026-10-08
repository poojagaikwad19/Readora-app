import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

class LocalWhisperService {
  static final LocalWhisperService _instance = LocalWhisperService._internal();
  factory LocalWhisperService() => _instance;
  LocalWhisperService._internal();

  final WhisperController _whisperController = WhisperController();
  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

  Future<void> ensureModelDownloaded() async {
    if (_isDownloading) return;
    _isDownloading = true;
    try {
      debugPrint('📥 [WhisperController] Ensuring WhisperModel.small is ready...');
      await _whisperController.downloadModel(WhisperModel.small);
      debugPrint('✅ [WhisperController] WhisperModel.small ready');
    } catch (e) {
      debugPrint('❌ [WhisperController] Model download/check error: $e');
      rethrow;
    } finally {
      _isDownloading = false;
    }
  }

  Future<String> _convertToWav16kMono(String inputFilePath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}/whisper_converted_${DateTime.now().millisecondsSinceEpoch}.wav';

      debugPrint('🔄 [FFmpeg] Decoding & resampling audio: $inputFilePath -> $outputPath (16kHz 16-bit Mono WAV)...');
      final session = await FFmpegKit.execute('-y -i "$inputFilePath" -ar 16000 -ac 1 -c:a pcm_s16le "$outputPath"');
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode) && File(outputPath).existsSync() && File(outputPath).lengthSync() > 100) {
        debugPrint('✅ [FFmpeg] Audio conversion successful: $outputPath (${File(outputPath).lengthSync()} bytes)');
        return outputPath;
      } else {
        final logs = await session.getOutput();
        throw Exception('FFmpeg audio conversion failed: $logs');
      }
    } catch (e) {
      debugPrint('❌ [FFmpeg] Error converting audio to 16kHz WAV: $e');
      rethrow;
    }
  }

  Future<String> transcribeAudio(
    String audioFilePath, {
    required String language,
  }) async {
    if (!File(audioFilePath).existsSync()) {
      throw Exception('Audio file not found at $audioFilePath');
    }

    // Explicit language code mapping ('marathi'/'mr' -> 'mr', 'hindi'/'hi' -> 'hi', 'english'/'en' -> 'en')
    String langCode = language.toLowerCase().trim();
    if (langCode == 'marathi' || langCode == 'mr' || langCode == 'mr-in') {
      langCode = 'mr';
    } else if (langCode == 'hindi' || langCode == 'hi' || langCode == 'hi-in') {
      langCode = 'hi';
    } else if (langCode == 'english' || langCode == 'en') {
      langCode = 'en';
    }

    debugPrint('🎙️ [LOCAL WHISPER] Target language: "$language" -> Whisper code "$langCode"');

    // Ensure official multilingual WhisperModel.small is ready
    await ensureModelDownloaded();

    // Convert input audio file to 16kHz Mono WAV required by whisper_ggml / whisper.cpp
    final convertedAudioPath = await _convertToWav16kMono(audioFilePath);

    debugPrint('⚡ [LOCAL WHISPER] Executing WhisperController.transcribe...');
    debugPrint('   📁 Audio File: $convertedAudioPath');
    debugPrint('   🌐 Language: $langCode');

    try {
      final res = await _whisperController.transcribe(
        model: WhisperModel.small,
        audioPath: convertedAudioPath,
        lang: langCode,
      );

      final cleanTranscript = (res?.transcription.toString() ?? '').trim();
      debugPrint('✨ [LOCAL WHISPER] Transcription complete! Output length: ${cleanTranscript.length} chars');
      debugPrint('📝 [LOCAL WHISPER] Raw output: "$cleanTranscript"');

      if (cleanTranscript.isEmpty) {
        throw Exception('Whisper returned empty transcription text. Please verify audio volume or speech clarity.');
      }

      return cleanTranscript;
    } catch (e) {
      debugPrint('❌ [LOCAL WHISPER] Transcription failed: $e');
      rethrow;
    } finally {
      if (convertedAudioPath != audioFilePath && File(convertedAudioPath).existsSync()) {
        try { File(convertedAudioPath).deleteSync(); } catch (_) {}
      }
    }
  }
}
