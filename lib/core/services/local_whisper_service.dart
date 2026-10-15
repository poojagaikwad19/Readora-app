import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';
import '../../features/document_tts/domain/timed_word_model.dart';

class WhisperTranscriptionResult {
  final String transcript;
  final List<TimedWord> timedWords;

  const WhisperTranscriptionResult({
    required this.transcript,
    required this.timedWords,
  });

  String get text => transcript;
  List<TimedWord> get words => timedWords;
}

class LocalWhisperService {
  static final LocalWhisperService _instance = LocalWhisperService._internal();
  factory LocalWhisperService() => _instance;
  LocalWhisperService._internal();

  final WhisperController _whisperController = WhisperController();
  bool _isDownloading = false;
  Future<void>? _activeExecution;

  bool get isDownloading => _isDownloading;

  Future<WhisperModel> _resolveAvailableModel() async {
    // 1. Check for pre-downloaded base model (~140 MB, optimal for mobile)
    try {
      final basePath = await _whisperController.getPath(WhisperModel.base);
      final baseFile = File(basePath);
      if (baseFile.existsSync() && baseFile.lengthSync() > 50 * 1024 * 1024) {
        debugPrint('✅ Found pre-downloaded WhisperModel.base (${(baseFile.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB)');
        return WhisperModel.base;
      }
    } catch (_) {}

    // 2. Check for pre-downloaded tiny model (~75 MB, ultra-fast)
    try {
      final tinyPath = await _whisperController.getPath(WhisperModel.tiny);
      final tinyFile = File(tinyPath);
      if (tinyFile.existsSync() && tinyFile.lengthSync() > 20 * 1024 * 1024) {
        debugPrint('✅ Found pre-downloaded WhisperModel.tiny (${(tinyFile.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB)');
        return WhisperModel.tiny;
      }
    } catch (_) {}

    // 3. Check for pre-downloaded small model
    try {
      final smallPath = await _whisperController.getPath(WhisperModel.small);
      final smallFile = File(smallPath);
      if (smallFile.existsSync() && smallFile.lengthSync() > 100 * 1024 * 1024) {
        debugPrint('✅ Found pre-downloaded WhisperModel.small (${(smallFile.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB)');
        return WhisperModel.small;
      }
    } catch (_) {}

    // Default to base model (140 MB vs 466 MB small): 3x faster download and 3-5x faster inference
    return WhisperModel.base;
  }

  Future<WhisperModel> ensureModelDownloaded() async {
    final modelToUse = await _resolveAvailableModel();
    final modelPath = await _whisperController.getPath(modelToUse);
    final modelFile = File(modelPath);

    // If file is 0-byte or corrupt from interrupted download, clean it up
    if (modelFile.existsSync() && modelFile.lengthSync() < 10 * 1024 * 1024) {
      debugPrint('⚠️ Model file at $modelPath is incomplete (${modelFile.lengthSync()} bytes). Removing...');
      try {
        modelFile.deleteSync();
      } catch (_) {}
    }

    if (!modelFile.existsSync()) {
      if (_isDownloading) return modelToUse;
      _isDownloading = true;
      try {
        debugPrint('📥 [WhisperController] Downloading ${modelToUse.name} model...');
        await _whisperController.downloadModel(modelToUse);
        debugPrint('✅ [WhisperController] ${modelToUse.name} ready');
      } catch (e) {
        debugPrint('❌ [WhisperController] Model download error: $e');
        rethrow;
      } finally {
        _isDownloading = false;
      }
    }
    return modelToUse;
  }

  Future<String> _convertToWav16kMono(String inputFilePath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}/whisper_converted_${DateTime.now().millisecondsSinceEpoch}.wav';

      debugPrint('🔄 [FFmpeg] Resampling audio: $inputFilePath -> $outputPath (16kHz Mono WAV)...');
      final session = await FFmpegKit.execute('-y -i "$inputFilePath" -vn -ar 16000 -ac 1 -c:a pcm_s16le "$outputPath"');
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

  Future<WhisperTranscriptionResult> transcribeAudioDetailed(
    String audioFilePath, {
    required String language,
  }) async {
    while (_activeExecution != null) {
      try {
        await _activeExecution;
      } catch (_) {}
    }
    final completer = Completer<void>();
    _activeExecution = completer.future;

    try {
      return await _transcribeAudioDetailedInternal(audioFilePath, language: language);
    } finally {
      completer.complete();
      _activeExecution = null;
    }
  }

  Future<WhisperTranscriptionResult> _transcribeAudioDetailedInternal(
    String audioFilePath, {
    required String language,
  }) async {
    if (!File(audioFilePath).existsSync()) {
      throw Exception('Audio file not found at $audioFilePath');
    }

    // Explicit language code mapping ('marathi'/'mr' -> 'mr', 'hindi'/'hi' -> 'hi', 'english'/'en' -> 'en', 'auto' -> 'auto')
    String langCode = language.toLowerCase().trim();
    if (langCode == 'marathi' || langCode == 'mr' || langCode == 'mr-in') {
      langCode = 'mr';
    } else if (langCode == 'hindi' || langCode == 'hi' || langCode == 'hi-in') {
      langCode = 'hi';
    } else if (langCode == 'english' || langCode == 'en') {
      langCode = 'en';
    } else if (langCode == 'auto' || langCode.isEmpty) {
      langCode = 'auto';
    }

    // Smart filename hint fallback: If filename clearly indicates Marathi or Hindi, avoid defaulting to English
    final audioFileName = audioFilePath.split(RegExp(r'[/\\]')).last.toLowerCase();
    if (audioFileName.contains('marathi') || RegExp(r'[\b_\-]mr[\b_\-\.]').hasMatch(audioFileName)) {
      if (langCode != 'mr') {
        debugPrint('🎙️ [LOCAL WHISPER] Audio filename "$audioFileName" contains Marathi indicator. Setting langCode to "mr".');
        langCode = 'mr';
      }
    } else if (audioFileName.contains('hindi') || RegExp(r'[\b_\-]hi[\b_\-\.]').hasMatch(audioFileName)) {
      if (langCode != 'hi') {
        debugPrint('🎙️ [LOCAL WHISPER] Audio filename "$audioFileName" contains Hindi indicator. Setting langCode to "hi".');
        langCode = 'hi';
      }
    }

    debugPrint('🎙️ [LOCAL WHISPER] Target language: "$language" -> Whisper code "$langCode"');

    // Ensure model is ready (prioritizes pre-downloaded WhisperModel.small)
    final modelToUse = await ensureModelDownloaded();

    // Convert input audio file to 16kHz Mono WAV required by whisper_ggml / whisper.cpp
    final convertedAudioPath = await _convertToWav16kMono(audioFilePath);

    debugPrint('⚡ [LOCAL WHISPER] Executing WhisperController.transcribe with segments...');
    debugPrint('   📁 Audio File: $convertedAudioPath');
    debugPrint('   🌐 Language: $langCode');
    debugPrint('   🤖 Model: ${modelToUse.name}');

    try {
      final res = await _whisperController.transcribe(
        model: modelToUse,
        audioPath: convertedAudioPath,
        lang: langCode,
        withSegments: true,
        splitOnWord: true,
      );

      final cleanTranscript = (res?.transcription.toString() ?? '').trim();
      debugPrint('✨ [LOCAL WHISPER] Transcription complete! Output length: ${cleanTranscript.length} chars');

      final timedWords = <TimedWord>[];
      final segments = res?.transcription.segments;
      if (segments != null && segments.isNotEmpty) {
        for (final seg in segments) {
          final segText = seg.text.trim();
          if (segText.isEmpty) continue;

          final words = segText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
          final startMs = seg.fromTs.inMilliseconds;
          final endMs = seg.toTs.inMilliseconds;

          if (words.length <= 1) {
            timedWords.add(TimedWord(
              text: segText,
              startMs: startMs,
              endMs: endMs > startMs ? endMs : startMs + 120,
            ));
          } else {
            final duration = (endMs - startMs).clamp(0, 9999999);
            final perWord = duration / words.length;
            for (int i = 0; i < words.length; i++) {
              final wStart = (startMs + i * perWord).round();
              final wEnd = (startMs + (i + 1) * perWord).round();
              timedWords.add(TimedWord(
                text: words[i],
                startMs: wStart,
                endMs: wEnd > wStart ? wEnd : wStart + 120,
              ));
            }
          }
        }
      }

      if (cleanTranscript.isEmpty && timedWords.isEmpty) {
        throw Exception('Whisper returned empty transcription text. Please verify audio volume or speech clarity.');
      }

      final finalTranscript = cleanTranscript.isNotEmpty
          ? cleanTranscript
          : timedWords.map((w) => w.text).join(' ');

      return WhisperTranscriptionResult(
        transcript: finalTranscript,
        timedWords: timedWords,
      );
    } catch (e) {
      debugPrint('❌ [LOCAL WHISPER] Transcription failed: $e');
      rethrow;
    } finally {
      if (convertedAudioPath != audioFilePath && File(convertedAudioPath).existsSync()) {
        try { File(convertedAudioPath).deleteSync(); } catch (_) {}
      }
    }
  }

  Future<String> transcribeAudio(
    String audioFilePath, {
    required String language,
  }) async {
    final result = await transcribeAudioDetailed(audioFilePath, language: language);
    return result.transcript;
  }
}
