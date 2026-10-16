import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texttospeech/core/services/storage_service.dart';
import 'package:texttospeech/core/theme/app_theme.dart';
import 'package:texttospeech/features/auth/data/auth_repository.dart';
import 'package:texttospeech/features/auth/domain/user_model.dart';
import 'package:texttospeech/features/auth/presentation/providers/auth_provider.dart';
import 'package:texttospeech/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:texttospeech/features/auth/presentation/screens/login_screen.dart';
import 'package:texttospeech/features/auth/presentation/screens/registration_screen.dart';
import 'package:texttospeech/features/auth/presentation/widgets/country_code_picker.dart';
import 'package:texttospeech/features/auth/presentation/widgets/edit_profile_dialog.dart';
import 'package:texttospeech/features/document_tts/presentation/screens/dashboard_screen.dart';

void main() {
  group('Email-Only Auth & Profile UI Tests', () {
    testWidgets('Profile tab renders initials avatar, edit icon badge, account details, and Edit Profile button',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      final testUser = UserModel(
        id: 'usr_abc',
        name: 'Sarah Connor',
        email: 'sarah@resistance.org',
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

      // Overlapping initials avatar "SC"
      expect(find.text('SC'), findsNWidgets(2)); // AppBar action & Profile overlapping avatar

      // Avatar edit icon badge
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);

      // Account Card details
      expect(find.text('Sarah Connor'), findsNWidgets(2));
      expect(find.text('sarah@resistance.org'), findsNWidgets(2));

      // Mobile Number should NOT be present in profile tab
      expect(find.text('Mobile Number'), findsNothing);

      // Edit Profile button
      expect(find.text('Edit Profile'), findsOneWidget);

      // Tap Edit Profile button -> opens EditProfileDialog
      await tester.ensureVisible(find.text('Edit Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();

      expect(find.byType(EditProfileDialog), findsOneWidget);
      expect(find.text('Save Profile Changes'), findsOneWidget);
      expect(find.text('Change Photo'), findsOneWidget);
      // No phone field in edit profile
      expect(find.text('Mobile Number'), findsNothing);
    });

    testWidgets('LoginScreen displays "Email Address", email hint, and "Forgot password?" without phone login',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
          ],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Label verification - Email Address only
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Email address or mobile number'), findsNothing);

      // 2. Forgot password link
      expect(find.text('Forgot password?'), findsOneWidget);

      // 3. Country code pill is not present
      expect(find.byType(CountryCodePickerPill), findsNothing);

      // 4. Tap "Forgot password?" navigates to ForgotPasswordScreen
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
    });

    testWidgets('RegistrationScreen displays Full Name, Email, Password without phone fields',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
          ],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const RegistrationScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Mobile Number'), findsNothing);
      expect(find.text('Mobile Number (Optional)'), findsNothing);
      expect(find.byType(CountryCodePickerPill), findsNothing);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
      expect(find.text('Create Account'), findsNWidgets(2)); // Title and button
    });

    testWidgets('ForgotPasswordScreen provides email-only recovery flow without SMS method selection',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageServiceProvider.overrideWithValue(storage),
          ],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const ForgotPasswordScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Send Code'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      // Ensure no method selection or phone prompts
      expect(find.text('Choose Recovery Method'), findsNothing);
      expect(find.text('SMS OTP'), findsNothing);
    });
  });
}

class _FakeAuthNotifier extends AuthNotifier {
  final UserModel? _mockUser;
  _FakeAuthNotifier(this._mockUser) : super(_MockAuthRepo()) {
    state = AuthState(
      status: _mockUser != null ? AuthStatus.authenticated : AuthStatus.unauthenticated,
      user: _mockUser,
    );
  }
}

class _MockAuthRepo extends Fake implements AuthRepository {}
