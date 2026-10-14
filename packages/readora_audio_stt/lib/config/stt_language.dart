enum SttLanguage {
  english(code: 'en', bcp47: 'en-IN', displayName: 'English', nativeName: 'English'),
  hindi(code: 'hi', bcp47: 'hi-IN', displayName: 'Hindi', nativeName: 'हिन्दी'),
  marathi(code: 'mr', bcp47: 'mr-IN', displayName: 'Marathi', nativeName: 'मराठी');

  final String code;
  final String bcp47;
  final String displayName;
  final String nativeName;

  const SttLanguage({
    required this.code,
    required this.bcp47,
    required this.displayName,
    required this.nativeName,
  });

  static SttLanguage fromCode(String? code) {
    if (code == null) return SttLanguage.english;
    final clean = code.toLowerCase().trim();
    if (clean == 'hi' || clean == 'hin' || clean == 'hindi' || clean == 'hi-in') {
      return SttLanguage.hindi;
    }
    if (clean == 'mr' || clean == 'mar' || clean == 'marathi' || clean == 'mr-in') {
      return SttLanguage.marathi;
    }
    return SttLanguage.english;
  }
}
