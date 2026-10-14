import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texttospeech/App.dart';
import 'package:texttospeech/core/services/storage_service.dart';
import 'package:texttospeech/features/auth/presentation/providers/auth_provider.dart';

void main() {
  testWidgets('shows the Readora splash screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storageService = await StorageService.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storageService),
        ],
        child: const ReadoraApp(),
      ),
    );

    expect(find.text('Readora'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
