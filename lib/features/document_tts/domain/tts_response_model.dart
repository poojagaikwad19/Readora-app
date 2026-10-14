class TtsResponseModel {
  final bool success;
  final String? docId;
  final String audioUrl;
  final String filename;
  final String language;
  final int size;
  final String? translatedText;
  final bool cached;
  final int? chunkIndex;
  final int? totalChunks;
  final String? completeAudioUrl;
  final String? completeFilename;

  TtsResponseModel({
    required this.success,
    this.docId,
    required this.audioUrl,
    required this.filename,
    this.language = 'english',
    this.size = 0,
    this.translatedText,
    this.cached = false,
    this.chunkIndex,
    this.totalChunks,
    this.completeAudioUrl,
    this.completeFilename,
  });

  factory TtsResponseModel.fromJson(Map<String, dynamic> json) {
    return TtsResponseModel(
      success: json['success'] ?? true,
      docId: json['docId'],
      audioUrl: json['audioUrl'] ?? json['completeAudioUrl'] ?? '',
      filename: json['filename'] ?? json['completeFilename'] ?? '',
      language: json['language'] ?? 'english',
      size: json['size'] ?? json['completeSize'] ?? 0,
      translatedText: json['translatedText'],
      cached: json['cached'] ?? false,
      chunkIndex: json['chunkIndex'] != null ? int.tryParse(json['chunkIndex'].toString()) : null,
      totalChunks: json['totalChunks'] != null ? int.tryParse(json['totalChunks'].toString()) : null,
      completeAudioUrl: json['completeAudioUrl'],
      completeFilename: json['completeFilename'],
    );
  }
}
