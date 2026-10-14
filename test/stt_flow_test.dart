import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Flutter Backend & Google Cloud STT Language Routing Unit Tests', () {
    test('Verify Language Codes Routing Mapping for Google Cloud STT', () {
      String getLanguageCode(String selectedLang) {
        final lang = selectedLang.toLowerCase();
        if (lang == 'marathi' || lang == 'mr') return 'mr-IN';
        if (lang == 'hindi' || lang == 'hi') return 'hi-IN';
        return 'en';
      }

      expect(getLanguageCode('Marathi'), equals('mr-IN'));
      expect(getLanguageCode('mr'), equals('mr-IN'));
      expect(getLanguageCode('Hindi'), equals('hi-IN'));
      expect(getLanguageCode('hi'), equals('hi-IN'));
      expect(getLanguageCode('English'), equals('en'));
      expect(getLanguageCode('en'), equals('en'));
    });
  });
}
