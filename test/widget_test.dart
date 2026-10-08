import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:texttospeech/App.dart';

void main() {
  testWidgets('shows the Readora splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ReadoraApp(),
      ),
    );

    expect(find.text('Readora'), findsOneWidget);
  });
}
