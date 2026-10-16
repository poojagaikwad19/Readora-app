import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:texttospeech/core/network/api_client.dart';
import 'package:texttospeech/core/services/image_processing_service.dart';
import 'package:texttospeech/core/services/storage_service.dart';
import 'package:texttospeech/core/theme/app_theme.dart';
import 'package:texttospeech/features/auth/data/auth_repository.dart';
import 'package:texttospeech/features/auth/domain/user_model.dart';
import 'package:texttospeech/features/auth/presentation/providers/auth_provider.dart';
import 'package:texttospeech/features/auth/presentation/widgets/edit_name_dialog.dart';
import 'package:texttospeech/features/auth/presentation/widgets/photo_options_bottom_sheet.dart';
import 'package:texttospeech/features/document_tts/domain/document_model.dart';
import 'package:texttospeech/features/document_tts/domain/voice_model.dart';
import 'package:texttospeech/features/document_tts/data/document_tts_repository.dart';
import 'package:texttospeech/features/document_tts/presentation/providers/document_tts_provider.dart';
import 'package:texttospeech/features/document_tts/presentation/screens/dashboard_screen.dart';

class MockAuthRepository extends AuthRepository {
  UserModel? mockUser;
  bool shouldFailUpdate = false;
  bool shouldFailUpload = false;

  MockAuthRepository(super.apiClient, super.storageService);

  @override
  Future<UserModel?> getMe() async => mockUser;

  @override
  Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? phoneNumber,
    String? countryCode,
  }) async {
    if (shouldFailUpdate) {
      throw Exception('Network connection timed out. Please try again.');
    }
    mockUser = mockUser?.copyWith(name: name) ?? UserModel(id: '1', name: name ?? '', email: 'test@example.com');
    return {
      'user': mockUser!,
      'message': 'Profile updated successfully',
    };
  }

  @override
  Future<UserModel> uploadAvatar(String filePath, {String? filename, dynamic contentType}) async {
    if (shouldFailUpload) {
      throw Exception('Upload failed. Server error.');
    }
    mockUser = mockUser?.copyWith(avatarUrl: '/uploads/avatars/new_avatar.jpg') ??
        UserModel(id: '1', name: 'User', email: 'test@example.com', avatarUrl: '/uploads/avatars/new_avatar.jpg');
    return mockUser!;
  }

  @override
  Future<UserModel> removeAvatar() async {
    mockUser = UserModel(
      id: mockUser?.id ?? '1',
      name: mockUser?.name ?? 'User',
      email: mockUser?.email ?? 'test@example.com',
      avatarUrl: null,
    );
    return mockUser!;
  }
}

class TestAuthNotifier extends AuthNotifier {
  TestAuthNotifier(super.repository, UserModel initialUser) {
    state = AuthState(
      status: AuthStatus.authenticated,
      user: initialUser,
    );
  }
}

class MockDocumentTtsRepository extends DocumentTtsRepository {
  MockDocumentTtsRepository(super.apiClient);

  @override
  Future<List<DocumentModel>> getUserFiles() async => [];

  @override
  Future<List<VoiceModel>> fetchVoices() async => VoiceModel.defaultVoices();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storageService;
  late MockAuthRepository mockAuthRepository;
  late ProviderContainer container;

  setUp(() async {
    // Setup Mock Method Channel for path_provider
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (MethodCall call) async {
      return Directory.systemTemp.path;
    });

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storageService = StorageService(prefs);
    final apiClient = ApiClient(storageService);
    mockAuthRepository = MockAuthRepository(apiClient, storageService);
    final initialUser = UserModel(
      id: 'user_123',
      name: 'Sham Kumar',
      email: 'sham@example.com',
      avatarUrl: '/uploads/avatars/sham.jpg',
    );
    mockAuthRepository.mockUser = initialUser;

    container = ProviderContainer(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
        authRepositoryProvider.overrideWithValue(mockAuthRepository),
        authNotifierProvider.overrideWith((ref) => TestAuthNotifier(mockAuthRepository, initialUser)),
        documentTtsRepositoryProvider.overrideWithValue(MockDocumentTtsRepository(apiClient)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('Profile Controls & Mockup Alignment Tests', () {
    testWidgets('Dashboard Profile tab renders pencil icon next to name and NO separate Edit Profile button', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Profile Tab (index 1)
      final profileNavBtn = find.text('Profile');
      expect(profileNavBtn, findsOneWidget);
      await tester.tap(profileNavBtn);
      await tester.pumpAndSettle();

      // 1. Verify separate "Edit Profile" button is REMOVED
      expect(find.text('Edit Profile'), findsNothing);

      // 2. Verify purple pencil icon is placed next to displayed name
      expect(find.text('Sham Kumar'), findsNWidgets(2)); // in header card and in Account Details
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);

      // 3. Verify teal camera icon exists
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);

      // 4. Verify Account active pill badge is shown
      expect(find.text('Account active'), findsOneWidget);

      // 5. Verify Account details heading
      expect(find.text('Account details'), findsOneWidget);
    });

    testWidgets('Tapping pencil icon opens EditNameDialog with current name', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Profile
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      // Tap pencil icon next to name
      final pencilIcon = find.byIcon(Icons.edit_rounded);
      await tester.tap(pencilIcon);
      await tester.pumpAndSettle();

      // Verify Edit Name dialog appears
      expect(find.text('Edit Name'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Sham Kumar'), findsWidgets);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Modify name and save
      final nameField = find.byType(TextFormField);
      await tester.enterText(nameField, 'Sham Sundar');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Dialog should close and name updated in repository
      expect(find.text('Edit Name'), findsNothing);
      expect(mockAuthRepository.mockUser?.name, equals('Sham Sundar'));
    });

    testWidgets('PhotoOptionsBottomSheet displays Remove photo only when user has photo', (tester) async {
      // 1. User with photo
      final userWithPhoto = UserModel(
        id: '1',
        name: 'Sham',
        email: 'sham@example.com',
        avatarUrl: '/uploads/avatars/photo.jpg',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: PhotoOptionsBottomSheet(user: userWithPhoto),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Profile photo'), findsOneWidget);
      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(find.text('Remove photo'), findsOneWidget); // Shown because photo exists

      // 2. User without photo
      final userWithoutPhoto = UserModel(
        id: '2',
        name: 'Bob',
        email: 'bob@example.com',
        avatarUrl: null,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: PhotoOptionsBottomSheet(user: userWithoutPhoto),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(find.text('Remove photo'), findsNothing); // NOT shown when no photo exists!
    });
  });

  group('Flexible Image Processing Tests', () {
    test('ImageProcessingService decodes, normalizes, resizes, and converts image to JPEG', () async {
      // Create a test image using image package
      final testImage = img.Image(width: 1500, height: 1000);
      img.fill(testImage, color: img.ColorRgb8(100, 150, 200));

      final pngBytes = img.encodePng(testImage);
      final tempDir = Directory.systemTemp.createTempSync('readora_img_test');
      final inputPath = '${tempDir.path}/test_large.png';
      File(inputPath).writeAsBytesSync(pngBytes);

      try {
        final result = await ImageProcessingService.processAvatarImage(inputPath);

        expect(result.mimeType, equals('image/jpeg'));
        expect(result.filename.endsWith('.jpg'), isTrue);
        expect(File(result.path).existsSync(), isTrue);

        // Verify converted dimensions are scaled down to <= maxDimension (1024)
        final decodedConverted = img.decodeJpg(File(result.path).readAsBytesSync());
        expect(decodedConverted, isNotNull);
        expect(decodedConverted!.width, equals(1024));
        expect(decodedConverted.height, closeTo(683, 1)); // Preserved aspect ratio!
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('ImageProcessingService throws friendly error for invalid/corrupted non-image files', () async {
      final tempDir = Directory.systemTemp.createTempSync('readora_corrupt_test');
      final fakeImagePath = '${tempDir.path}/fake_corrupted.jpg';
      File(fakeImagePath).writeAsStringSync('THIS IS NOT AN IMAGE');

      try {
        await expectLater(
          ImageProcessingService.processAvatarImage(fakeImagePath),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains("This photo couldn't be opened. Please choose another photo."),
          )),
        );
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });

  group('Account Scoping & Data Isolation Tests', () {
    test('StorageService scopes user profile data by userId', () async {
      await storageService.saveUser(
        id: 'user_alice',
        name: 'Alice',
        email: 'alice@test.com',
        avatarUrl: '/avatars/alice.jpg',
      );

      final aliceData = storageService.getUser('user_alice');
      expect(aliceData['name'], equals('Alice'));
      expect(aliceData['avatarUrl'], equals('/avatars/alice.jpg'));

      // Save User B
      await storageService.saveUser(
        id: 'user_bob',
        name: 'Bob',
        email: 'bob@test.com',
        avatarUrl: null,
      );

      final bobData = storageService.getUser('user_bob');
      expect(bobData['name'], equals('Bob'));
      expect(bobData['avatarUrl'], isNull);

      // Alice's data remains intact under user_alice scope
      final aliceDataAgain = storageService.getUser('user_alice');
      expect(aliceDataAgain['name'], equals('Alice'));
      expect(aliceDataAgain['avatarUrl'], equals('/avatars/alice.jpg'));
    });
  });
}
