enum SttLanguage {
  auto(code: 'auto', bcp47: 'auto', displayName: 'Auto', nativeName: 'Auto Detect'),
  marathi(code: 'mr', bcp47: 'mr-IN', displayName: 'Marathi', nativeName: 'मराठी'),
  hindi(code: 'hi', bcp47: 'hi-IN', displayName: 'Hindi', nativeName: 'हिन्दी'),
  english(code: 'en', bcp47: 'en-IN', displayName: 'English', nativeName: 'English');

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
    if (clean == 'auto' || clean == 'detect') {
      return SttLanguage.auto;
    }
    if (clean == 'hi' || clean == 'hin' || clean == 'hindi' || clean == 'hi-in') {
      return SttLanguage.hindi;
    }
    if (clean == 'mr' || clean == 'mar' || clean == 'marathi' || clean == 'mr-in') {
      return SttLanguage.marathi;
    }
    return SttLanguage.english;
  }
}
