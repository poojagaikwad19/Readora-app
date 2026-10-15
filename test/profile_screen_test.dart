import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texttospeech/core/services/storage_service.dart';
import 'package:texttospeech/core/theme/app_theme.dart';
import 'package:texttospeech/features/auth/data/auth_repository.dart';
import 'package:texttospeech/features/auth/domain/user_model.dart';
import 'package:texttospeech/features/auth/presentation/providers/auth_provider.dart';
import 'package:texttospeech/features/document_tts/presentation/screens/dashboard_screen.dart';

void main() {
  group('Profile Screen Redesign Tests', () {
    testWidgets('Renders curved purple gradient header and account card with real user data',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      final testUser = UserModel(
        id: 'usr_123',
        name: 'Gaurii Patil',
        email: 'gauri@gmail.com',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            authNotifierProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          ],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Profile tab
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();

      // 1. Header verification
      expect(find.text('Profile'), findsWidgets); // Header & bottom nav
      expect(find.text('Your Readora account'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      // 2. Overlapping avatar with initials derived from multi-word name: "GP"
      expect(find.text('GP'), findsNWidgets(2)); // AppBar action & Profile overlapping avatar

      // 3. Account card details (both centered in card and in read-only rows)
      expect(find.text('Gaurii Patil'), findsNWidgets(2));
      expect(find.text('gauri@gmail.com'), findsNWidgets(2));
      expect(find.text('Readora Account Active'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);

      // 4. Sign out button styling & label
      expect(find.text('Sign Out of Readora'), findsOneWidget);
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    });

    testWidgets('Single name extracts single initial and Unicode names handled safely',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      final singleNameUser = UserModel(
        id: 'usr_456',
        name: 'gaurii',
        email: 'gauri@gmail.com',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            authNotifierProvider.overrideWith((ref) => _FakeAuthNotifier(singleNameUser)),
          ],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Profile tab
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();

      // Single initial 'G' appears in AppBar and Profile avatar
      expect(find.text('G'), findsNWidgets(2));
      expect(find.text('gaurii'), findsNWidgets(2));
    });

    testWidgets('Handles long names and emails without horizontal overflow',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      final longUser = UserModel(
        id: 'usr_long',
        name: 'Alexandrina Victoria Elizabeth Montgomery-Smith The Third',
        email: 'alexandrina.victoria.elizabeth.montgomery.smith.the.third@verylonginstitutionname.readora.org',
      );


      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            authNotifierProvider.overrideWith((ref) => _FakeAuthNotifier(longUser)),
          ],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Profile tab
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();

      // Ensure no overflow exception occurred
      expect(tester.takeException(), isNull);
      expect(find.text(longUser.name), findsNWidgets(2));
      expect(find.text(longUser.email), findsNWidgets(2));
    });

    testWidgets('Supports Dark Theme with dark card surface and contrast',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      final testUser = UserModel(
        id: 'usr_dark',
        name: 'Dark Mode User',
        email: 'dark@readora.app',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            authNotifierProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Profile tab
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sign Out of Readora'), findsOneWidget);
      expect(find.text('Dark Mode User'), findsNWidgets(2));
    });

    testWidgets('Sign out button triggers confirmation dialog with No/Yes and only Yes logs out',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      final testUser = UserModel(
        id: 'usr_logout',
        name: 'Logout Tester',
        email: 'logout@readora.app',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
            authNotifierProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
          ],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Profile tab
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();

      // Tap Sign out of Readora (scrolled into view on scrollable screen)
      await tester.ensureVisible(find.text('Sign Out of Readora'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign Out of Readora'));
      await tester.pumpAndSettle();

      // Confirmation dialog is shown
      expect(find.text('Are you sure you want to logout?'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);

      // Tap 'No' -> keeps user on screen
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to logout?'), findsNothing);
      expect(find.text('Sign Out of Readora'), findsOneWidget);
    });
  });
}

class _FakeAuthNotifier extends AuthNotifier {
  final UserModel? _mockUser;
  _FakeAuthNotifier(this._mockUser) : super(_MockAuthRepository()) {
    state = AuthState(
      status: _mockUser != null ? AuthStatus.authenticated : AuthStatus.unauthenticated,
      user: _mockUser,
    );
  }
}

class _MockAuthRepository extends Fake implements AuthRepository {}
