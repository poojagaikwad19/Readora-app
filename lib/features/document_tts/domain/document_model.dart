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
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    final pagesList = json['pages'] is List ? (json['pages'] as List) : [];
    final numPagesVal = json['pageCount'] ?? json['numPages'] ?? json['totalPages'];
    final computedPageCount = numPagesVal != null
        ? (int.tryParse(numPagesVal.toString()) ?? 1)
        : (pagesList.isNotEmpty ? pagesList.length : 1);

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
    };
  }
}
