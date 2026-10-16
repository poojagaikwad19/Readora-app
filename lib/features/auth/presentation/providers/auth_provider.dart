import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/image_processing_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../data/auth_repository.dart';
import '../../domain/user_model.dart';

// Storage Service Provider
final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Initialize storageServiceProvider in ProviderScope override');
});

// Api Client Provider
final apiClientProvider = Provider<ApiClient>((ref) {
  final storageService = ref.watch(storageServiceProvider);
  return ApiClient(storageService);
});

// Auth Repository Provider
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final storageService = ref.watch(storageServiceProvider);
  return AuthRepository(apiClient, storageService);
});

// Auth State enum
enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? errorMessage;
  final String? successMessage;

  AuthState({
    required this.status,
    this.user,
    this.errorMessage,
    this.successMessage,
  });

  factory AuthState.initial() => AuthState(status: AuthStatus.initial);

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? errorMessage,
    String? successMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

// Auth Notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;

  AuthNotifier(this._repository) : super(AuthState.initial());

  Future<void> checkAuthStatus() async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final user = await _repository.getMe();
      if (user != null) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
        );
      } else {
        state = state.copyWith(status: AuthStatus.unauthenticated);
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: e.toString(),
      );
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    String? phoneNumber,
    String? countryCode,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null, successMessage: null);
    try {
      final res = await _repository.register(
        name: name,
        email: email,
        password: password,
        phoneNumber: phoneNumber,
        countryCode: countryCode,
      );
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        successMessage: res['message'] ?? 'Registration successful! Please login with your credentials.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<bool> login({
    required String email,
    required String password,
    String? countryCode,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null, successMessage: null);
    try {
      final user = await _repository.login(
        email: email,
        password: password,
        countryCode: countryCode,
      );
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        successMessage: 'Welcome back, ${user.name}!',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? phoneNumber,
    String? countryCode,
  }) async {
    try {
      final result = await _repository.updateProfile(
        name: name,
        phoneNumber: phoneNumber,
        countryCode: countryCode,
      );
      final updatedUser = result['user'] as UserModel;
      state = state.copyWith(
        user: updatedUser,
        successMessage: result['message'] ?? 'Profile updated successfully',
      );
      return result;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<UserModel> uploadAvatar(String rawFilePath) async {
    try {
      final processed = await ImageProcessingService.processAvatarImage(rawFilePath);
      final updatedUser = await _repository.uploadAvatar(
        processed.path,
        filename: processed.filename,
        contentType: MediaType('image', 'jpeg'),
      );

      // Invalidate Flutter network image cache so updated avatar displays immediately
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      state = state.copyWith(
        user: updatedUser,
        successMessage: 'Profile photo updated successfully',
        errorMessage: null,
      );
      return updatedUser;
    } catch (e) {
      final message = e is FormatException ? e.message : e.toString();
      state = state.copyWith(errorMessage: message);
      rethrow;
    }
  }

  Future<UserModel> removeAvatar() async {
    try {
      final updatedUser = await _repository.removeAvatar();

      // Invalidate Flutter network image cache so removed avatar reverts to initials immediately
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      state = state.copyWith(
        user: updatedUser,
        successMessage: 'Profile photo removed',
        errorMessage: null,
      );
      return updatedUser;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<UserModel> verifyPhone(String otp) async {
    try {
      final updatedUser = await _repository.verifyPhone(otp);
      state = state.copyWith(
        user: updatedUser,
        successMessage: 'Mobile number verified successfully!',
      );
      return updatedUser;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<Map<String, dynamic>> resendPhoneOtp() async {
    try {
      return await _repository.resendPhoneOtp();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = state.copyWith(status: AuthStatus.unauthenticated, user: null);
  }
}

// Auth Notifier Provider
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthNotifier(repository);
});
