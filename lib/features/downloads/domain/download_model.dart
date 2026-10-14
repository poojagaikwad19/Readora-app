enum DownloadsFilter { all, document, audio }

class DownloadModel {
  static const Set<String> documentExtensions = {
    'pdf',
    'docx',
    'doc',
    'txt',
    'rtf',
    'odt',
    'md',
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
    'tiff',
    'tif',
    'gif',
  };

  static const Set<String> audioExtensions = {
    'mp3',
    'wav',
    'm4a',
    'aac',
    'ogg',
    'flac',
    'opus',
    'wma',
    'webm',
    'audio',
  };

  static bool isDocumentType(DownloadModel item) {
    final mime = item.mimeType.trim().toLowerCase();
    final filename = item.displayFilename.trim().toLowerCase();
    final path = item.relativeFilePath.trim().toLowerCase();

    String ext = '';
    if (filename.contains('.')) {
      ext = filename.split('.').last.trim();
    } else if (path.contains('.')) {
      ext = path.split('.').last.trim();
    }

    // Classify by downloaded file's actual type, NOT the source used to create it.
    // If extension explicitly indicates an audio file, it belongs under audio.
    if (ext.isNotEmpty && audioExtensions.contains(ext)) {
      return false;
    }

    if (mime.startsWith('image/') ||
        mime == 'application/pdf' ||
        mime.contains('word') ||
        mime == 'text/plain' ||
        mime == 'text/markdown' ||
        mime == 'application/rtf') {
      return true;
    }

    if (ext.isNotEmpty && documentExtensions.contains(ext)) {
      return true;
    }

    return false;
  }

  static bool isAudioType(DownloadModel item) {
    final mime = item.mimeType.trim().toLowerCase();
    final filename = item.displayFilename.trim().toLowerCase();
    final path = item.relativeFilePath.trim().toLowerCase();

    String ext = '';
    if (filename.contains('.')) {
      ext = filename.split('.').last.trim();
    } else if (path.contains('.')) {
      ext = path.split('.').last.trim();
    }

    // If extension explicitly indicates a document file, it belongs under document
    if (ext.isNotEmpty && documentExtensions.contains(ext)) {
      return false;
    }

    if (mime.startsWith('audio/') || mime == 'audio/mpeg' || mime == 'audio/mp3') {
      return true;
    }

    if (ext.isNotEmpty && audioExtensions.contains(ext)) {
      return true;
    }

    return false;
  }

  static bool matchesFilter(DownloadModel item, DownloadsFilter filter) {
    switch (filter) {
      case DownloadsFilter.all:
        return true;
      case DownloadsFilter.document:
        return isDocumentType(item);
      case DownloadsFilter.audio:
        return isAudioType(item);
    }
  }

  final String id;
  final String userId;
  final String? sourceDocId;
  final String? sourceDocName;
  final String displayFilename;
  final String relativeFilePath;
  final String mimeType;
  final int fileSize; // bytes
  final Duration? duration;
  final String language;
  final String? voiceId;
  final String? voiceName;
  final DateTime downloadDate;
  final String? generationSessionId;

  const DownloadModel({
    required this.id,
    required this.userId,
    this.sourceDocId,
    this.sourceDocName,
    required this.displayFilename,
    required this.relativeFilePath,
    this.mimeType = 'audio/mpeg',
    required this.fileSize,
    this.duration,
    required this.language,
    this.voiceId,
    this.voiceName,
    required this.downloadDate,
    this.generationSessionId,
  });

  bool get isAudio => DownloadModel.isAudioType(this);
  bool get isDocument => DownloadModel.isDocumentType(this);

  String get formattedSize {
    if (fileSize <= 0) return '0 B';
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String? get formattedDuration {
    if (duration == null || duration == Duration.zero) return null;
    final minutes = duration!.inMinutes;
    final seconds = duration!.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedDate {
    final year = downloadDate.year;
    final month = downloadDate.month.toString().padLeft(2, '0');
    final day = downloadDate.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  DownloadModel copyWith({
    String? id,
    String? userId,
    String? sourceDocId,
    String? sourceDocName,
    String? displayFilename,
    String? relativeFilePath,
    String? mimeType,
    int? fileSize,
    Duration? duration,
    String? language,
    String? voiceId,
    String? voiceName,
    DateTime? downloadDate,
    String? generationSessionId,
  }) {
    return DownloadModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      sourceDocId: sourceDocId ?? this.sourceDocId,
      sourceDocName: sourceDocName ?? this.sourceDocName,
      displayFilename: displayFilename ?? this.displayFilename,
      relativeFilePath: relativeFilePath ?? this.relativeFilePath,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      duration: duration ?? this.duration,
      language: language ?? this.language,
      voiceId: voiceId ?? this.voiceId,
      voiceName: voiceName ?? this.voiceName,
      downloadDate: downloadDate ?? this.downloadDate,
      generationSessionId: generationSessionId ?? this.generationSessionId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'sourceDocId': sourceDocId,
      'sourceDocName': sourceDocName,
      'displayFilename': displayFilename,
      'relativeFilePath': relativeFilePath,
      'mimeType': mimeType,
      'fileSize': fileSize,
      'durationMs': duration?.inMilliseconds,
      'language': language,
      'voiceId': voiceId,
      'voiceName': voiceName,
      'downloadDate': downloadDate.toIso8601String(),
      'generationSessionId': generationSessionId,
    };
  }

  factory DownloadModel.fromJson(Map<String, dynamic> json) {
    Duration? parsedDuration;
    if (json['durationMs'] != null) {
      parsedDuration = Duration(milliseconds: json['durationMs'] as int);
    }

    DateTime parsedDate;
    try {
      parsedDate = json['downloadDate'] != null
          ? DateTime.parse(json['downloadDate'] as String)
          : DateTime.now();
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return DownloadModel(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? 'guest',
      sourceDocId: json['sourceDocId'] as String?,
      sourceDocName: json['sourceDocName'] as String?,
      displayFilename: json['displayFilename'] as String? ?? 'audio.mp3',
      relativeFilePath: json['relativeFilePath'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? 'audio/mpeg',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      duration: parsedDuration,
      language: json['language'] as String? ?? 'english',
      voiceId: json['voiceId'] as String?,
      voiceName: json['voiceName'] as String?,
      downloadDate: parsedDate,
      generationSessionId: json['generationSessionId'] as String?,
    );
  }
}
