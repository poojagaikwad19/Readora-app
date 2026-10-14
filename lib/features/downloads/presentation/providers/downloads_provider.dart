import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/services/storage_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/download_model.dart';

class DownloadsState {
  final List<DownloadModel> downloads;
  final bool isLoading;
  final bool isDownloading;
  final double? downloadProgress; // 0.0 to 1.0 or null for indeterminate
  final String? activePlayingId;
  final PlayerState playerState;
  final Duration playbackPosition;
  final Duration playbackDuration;
  final String? errorMessage;
  final String? successMessage;

  const DownloadsState({
    this.downloads = const [],
    this.isLoading = false,
    this.isDownloading = false,
    this.downloadProgress,
    this.activePlayingId,
    this.playerState = PlayerState.stopped,
    this.playbackPosition = Duration.zero,
    this.playbackDuration = Duration.zero,
    this.errorMessage,
    this.successMessage,
  });

  DownloadsState copyWith({
    List<DownloadModel>? downloads,
    bool? isLoading,
    bool? isDownloading,
    double? downloadProgress,
    bool clearProgress = false,
    String? activePlayingId,
    bool clearPlayingId = false,
    PlayerState? playerState,
    Duration? playbackPosition,
    Duration? playbackDuration,
    String? errorMessage,
    bool clearError = false,
    String? successMessage,
    bool clearSuccess = false,
  }) {
    return DownloadsState(
      downloads: downloads ?? this.downloads,
      isLoading: isLoading ?? this.isLoading,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: clearProgress ? null : (downloadProgress ?? this.downloadProgress),
      activePlayingId: clearPlayingId ? null : (activePlayingId ?? this.activePlayingId),
      playerState: playerState ?? this.playerState,
      playbackPosition: playbackPosition ?? this.playbackPosition,
      playbackDuration: playbackDuration ?? this.playbackDuration,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }
}

class DownloadsNotifier extends StateNotifier<DownloadsState> {
  final StorageService _storageService;
  final AudioPlayer _audioPlayer = AudioPlayer();
  VoidCallback? onBeforePlay;

  DownloadsNotifier(this._storageService, {this.onBeforePlay}) : super(const DownloadsState()) {
    _initAudioPlayerListeners();
    loadDownloads();
  }

  void _initAudioPlayerListeners() {
    _audioPlayer.onPlayerStateChanged.listen((pState) {
      if (mounted) {
        state = state.copyWith(playerState: pState);
        if (pState == PlayerState.completed || pState == PlayerState.stopped) {
          state = state.copyWith(
            clearPlayingId: true,
            playbackPosition: Duration.zero,
          );
        }
      }
    });

    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) {
        state = state.copyWith(playbackPosition: pos);
      }
    });

    _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) {
        state = state.copyWith(playbackDuration: dur);
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _currentUserId() {
    return _storageService.getUser()['id'] ?? 'guest';
  }

  Future<String> getLocalAbsolutePath(String relativePath) async {
    final docsDir = await getApplicationDocumentsDirectory();
    return '${docsDir.path}/$relativePath';
  }

  Future<void> loadDownloads([String? explicitUserId]) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final userId = explicitUserId ?? _currentUserId();
    final rawList = _storageService.getDownloads(userId);
    final items = rawList.map((m) => DownloadModel.fromJson(m)).toList();
    // Sort descending by downloadDate
    items.sort((a, b) => b.downloadDate.compareTo(a.downloadDate));
    state = state.copyWith(isLoading: false, downloads: items);
  }

  Future<void> _persist() async {
    final userId = _currentUserId();
    final jsonList = state.downloads.map((d) => d.toJson()).toList();
    await _storageService.saveDownloads(jsonList, userId);
  }

  String _resolveAudioUrl(String audioPath, String baseUrl) {
    if (audioPath.startsWith('http://') || audioPath.startsWith('https://')) {
      return audioPath;
    }
    String cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    String cleanPath = audioPath.startsWith('/') ? audioPath : '/$audioPath';

    if (cleanBase.endsWith('/api') && cleanPath.startsWith('/api/')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - 4);
    }
    return '$cleanBase$cleanPath';
  }

  /// Saves complete generated document audio directly to durable in-app private storage
  Future<DownloadModel?> saveAudioToLibrary({
    required String audioUrl,
    required String baseUrl,
    required String displayFilename,
    required String language,
    String? sourceDocId,
    String? sourceDocName,
    String? voiceId,
    String? voiceName,
    String? generationSessionId,
    Duration? duration,
  }) async {
    if (state.isDownloading) {
      return null;
    }

    // Check for existing completed download with identical generation identity
    if (generationSessionId != null && generationSessionId.isNotEmpty) {
      final existing = state.downloads.where(
        (d) => d.generationSessionId == generationSessionId && d.language == language,
      );
      if (existing.isNotEmpty) {
        final existingItem = existing.first;
        final absPath = await getLocalAbsolutePath(existingItem.relativeFilePath);
        if (await File(absPath).exists()) {
          state = state.copyWith(
            successMessage: 'Audio already downloaded in your library',
          );
          return existingItem;
        }
      }
    }

    state = state.copyWith(
      isDownloading: true,
      downloadProgress: null,
      clearError: true,
      clearSuccess: true,
    );

    final downloadId = '${DateTime.now().millisecondsSinceEpoch}_${(displayFilename.hashCode.abs() % 10000)}';
    final relativePath = 'downloads/audio_$downloadId.mp3';

    File? tempFile;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${docsDir.path}/downloads');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final fullUrl = _resolveAudioUrl(audioUrl, baseUrl);
      final uri = Uri.parse(fullUrl);
      final token = _storageService.getToken();

      final request = http.Request('GET', uri);
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 45));
      if (streamedResponse.statusCode != 200) {
        throw Exception('Download failed with status code ${streamedResponse.statusCode}');
      }

      final tempPath = '${docsDir.path}/downloads/temp_$downloadId.tmp';
      tempFile = File(tempPath);
      final sink = tempFile.openWrite();

      final contentLength = streamedResponse.contentLength;
      int downloadedBytes = 0;

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (contentLength != null && contentLength > 0) {
          state = state.copyWith(
            downloadProgress: (downloadedBytes / contentLength).clamp(0.0, 1.0),
          );
        }
      }
      await sink.flush();
      await sink.close();

      final totalSize = await tempFile.length();
      if (totalSize == 0) {
        throw Exception('Downloaded audio file is empty (0 bytes)');
      }

      // Finalize file move from .tmp to final relative destination
      final finalPath = '${docsDir.path}/$relativePath';
      await tempFile.rename(finalPath);
      tempFile = null;

      String safeDisplay = displayFilename.trim();
      if (safeDisplay.isEmpty) safeDisplay = 'readora_audio.mp3';
      if (!safeDisplay.toLowerCase().endsWith('.mp3') &&
          !safeDisplay.toLowerCase().endsWith('.wav') &&
          !safeDisplay.toLowerCase().endsWith('.m4a')) {
        safeDisplay = '$safeDisplay.mp3';
      }

      final newModel = DownloadModel(
        id: downloadId,
        userId: _currentUserId(),
        sourceDocId: sourceDocId,
        sourceDocName: sourceDocName,
        displayFilename: safeDisplay,
        relativeFilePath: relativePath,
        mimeType: 'audio/mpeg',
        fileSize: totalSize,
        duration: duration,
        language: language,
        voiceId: voiceId,
        voiceName: voiceName,
        downloadDate: DateTime.now(),
        generationSessionId: generationSessionId,
      );

      final updated = [newModel, ...state.downloads];
      state = state.copyWith(
        isDownloading: false,
        clearProgress: true,
        downloads: updated,
        successMessage: 'Audio downloaded to Readora Library!',
      );

      await _persist();
      return newModel;
    } catch (e) {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }

      state = state.copyWith(
        isDownloading: false,
        clearProgress: true,
        errorMessage: 'Download failed: $e',
      );
      return null;
    }
  }

  // Playback control
  Future<void> playDownload(DownloadModel download) async {
    try {
      final absPath = await getLocalAbsolutePath(download.relativeFilePath);
      final file = File(absPath);
      if (!await file.exists() || await file.length() == 0) {
        state = state.copyWith(
          errorMessage: 'Audio file is missing or unreadable on this device.',
        );
        return;
      }

      // Stop any other active Readora playback (TTS or STT original audio)
      onBeforePlay?.call();
      await _audioPlayer.stop();

      state = state.copyWith(
        activePlayingId: download.id,
        playerState: PlayerState.playing,
        clearError: true,
      );

      await _audioPlayer.play(DeviceFileSource(absPath));
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Playback error: $e',
        clearPlayingId: true,
        playerState: PlayerState.stopped,
      );
    }
  }

  Future<void> pauseDownload() async {
    await _audioPlayer.pause();
    state = state.copyWith(playerState: PlayerState.paused);
  }

  Future<void> resumeDownload() async {
    await _audioPlayer.resume();
    state = state.copyWith(playerState: PlayerState.playing);
  }

  Future<void> stopPlayback() async {
    await _audioPlayer.stop();
    state = state.copyWith(
      clearPlayingId: true,
      playerState: PlayerState.stopped,
      playbackPosition: Duration.zero,
    );
  }

  Future<void> seekPlayback(Duration pos) async {
    await _audioPlayer.seek(pos);
  }

  // Rename Display Name
  Future<bool> renameDownload(String downloadId, String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty) return false;

    String finalName = clean;
    if (!finalName.toLowerCase().endsWith('.mp3') &&
        !finalName.toLowerCase().endsWith('.wav') &&
        !finalName.toLowerCase().endsWith('.m4a')) {
      finalName = '$finalName.mp3';
    }

    final updated = state.downloads.map((d) {
      if (d.id == downloadId) {
        return d.copyWith(displayFilename: finalName);
      }
      return d;
    }).toList();

    state = state.copyWith(downloads: updated, successMessage: 'Renamed successfully');
    await _persist();
    return true;
  }

  // Delete from App
  Future<bool> deleteDownload(String downloadId) async {
    final match = state.downloads.where((d) => d.id == downloadId);
    if (match.isEmpty) return false;

    final item = match.first;

    if (state.activePlayingId == downloadId) {
      await stopPlayback();
    }

    try {
      final absPath = await getLocalAbsolutePath(item.relativeFilePath);
      final file = File(absPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting local audio file: $e');
    }

    final updated = state.downloads.where((d) => d.id != downloadId).toList();
    state = state.copyWith(
      downloads: updated,
      successMessage: 'Audio removed from Readora library',
    );
    await _persist();
    return true;
  }

  // Save to Device via FilePicker
  Future<bool> exportToDevice(DownloadModel download) async {
    try {
      final absPath = await getLocalAbsolutePath(download.relativeFilePath);
      final file = File(absPath);
      if (!await file.exists()) {
        state = state.copyWith(errorMessage: 'Local audio file not found');
        return false;
      }

      final bytes = await file.readAsBytes();
      String fileName = download.displayFilename;
      if (!fileName.toLowerCase().endsWith('.mp3') &&
          !fileName.toLowerCase().endsWith('.wav') &&
          !fileName.toLowerCase().endsWith('.m4a')) {
        fileName = '$fileName.mp3';
      }

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Audio to Device',
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a'],
      );

      if (savePath == null) {
        // User cancelled picker dialog
        return false;
      }

      // Check if desktop platforms require explicit write
      final exportedFile = File(savePath);
      if (!await exportedFile.exists() || await exportedFile.length() == 0) {
        await exportedFile.writeAsBytes(bytes);
      }

      state = state.copyWith(
        successMessage: 'Saved to device successfully!',
      );
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Export failed: $e');
      return false;
    }
  }
}

final downloadsProvider = StateNotifierProvider<DownloadsNotifier, DownloadsState>((ref) {
  final storageService = ref.watch(storageServiceProvider);
  return DownloadsNotifier(storageService);
});
