import 'timed_word_model.dart';

class DocumentModel {
  final String docId;
  final String filename;
  final String text;
  final int wordCount;
  final int characterCount;
  final String detectedLanguage;
  final String fileType;
  final bool isScanned;
  final bool ocrUsed;
  final List<dynamic> pages;
  final int pageCount;
  final DateTime? createdAt;
  final String? contentHash;
  final List<dynamic> chunks;
  final List<TimedWord> timedWords;
  final String? audioSourcePath;

  DocumentModel({
    required this.docId,
    required this.filename,
    required this.text,
    this.wordCount = 0,
    this.characterCount = 0,
    this.detectedLanguage = 'english',
    this.fileType = 'pdf',
    this.isScanned = false,
    this.ocrUsed = false,
    this.pages = const [],
    this.pageCount = 1,
    this.createdAt,
    this.contentHash,
    this.chunks = const [],
    this.timedWords = const [],
    this.audioSourcePath,
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    final pagesList = json['pages'] is List ? (json['pages'] as List) : [];
    final numPagesVal = json['pageCount'] ?? json['numPages'] ?? json['totalPages'];
    final computedPageCount = numPagesVal != null
        ? (int.tryParse(numPagesVal.toString()) ?? 1)
        : (pagesList.isNotEmpty ? pagesList.length : 1);

    final rawWords = json['timedWords'] ?? json['words'];
    final parsedTimedWords = (rawWords is List)
        ? rawWords
            .where((e) => e is Map)
            .map((e) => TimedWord.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <TimedWord>[];

    return DocumentModel(
      docId: json['docId'] ?? json['id'] ?? json['_id'] ?? '',
      filename: json['filename'] ?? json['originalName'] ?? 'Document',
      text: json['text'] ?? '',
      wordCount: json['wordCount'] ?? 0,
      characterCount: json['characterCount'] ?? 0,
      detectedLanguage: json['detectedLanguage'] ?? 'english',
      fileType: json['fileType'] ?? 'pdf',
      isScanned: json['isScanned'] ?? false,
      ocrUsed: json['ocrUsed'] ?? false,
      pages: pagesList,
      pageCount: computedPageCount,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      contentHash: json['contentHash'] ?? json['textHash'],
      chunks: json['chunks'] is List ? (json['chunks'] as List) : const [],
      timedWords: parsedTimedWords,
      audioSourcePath: json['audioSourcePath']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'docId': docId,
      'filename': filename,
      'text': text,
      'wordCount': wordCount,
      'characterCount': characterCount,
      'detectedLanguage': detectedLanguage,
      'fileType': fileType,
      'isScanned': isScanned,
      'ocrUsed': ocrUsed,
      'pages': pages,
      'pageCount': pageCount,
      'createdAt': createdAt?.toIso8601String(),
      'contentHash': contentHash,
      'chunks': chunks,
      'timedWords': timedWords.map((w) => w.toJson()).toList(),
      if (audioSourcePath != null) 'audioSourcePath': audioSourcePath,
    };
  }
}

