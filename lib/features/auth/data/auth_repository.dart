import 'package:http_parser/http_parser.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/storage_service.dart';
import '../domain/user_model.dart';

class AuthRepository {
  final ApiClient _apiClient;
  final StorageService _storageService;

  AuthRepository(this._apiClient, this._storageService);

  ApiClient get apiClient => _apiClient;

  Future<void> _persistUser(UserModel user) async {
    await _storageService.saveUser(
      id: user.id,
      name: user.name,
      email: user.email,
      phoneNumber: user.phoneNumber,
      isPhoneVerified: user.isPhoneVerified,
      isEmailVerified: user.isEmailVerified,
      avatarUrl: user.avatarUrl,
    );
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? phoneNumber,
    String? countryCode,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'email': email,
      'password': password,
    };
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      payload['phoneNumber'] = phoneNumber.trim();
      if (countryCode != null && countryCode.isNotEmpty) {
        payload['countryCode'] = countryCode;
      }
    }

    final response = await _apiClient.post(ApiEndpoints.register, payload);

    UserModel? user;
    if (response['user'] != null) {
      user = UserModel.fromJson(response['user']);
    } else {
      user = UserModel(id: '', name: name, email: email, phoneNumber: phoneNumber);
    }

    return {
      'user': user,
      'message': response['message'] ?? 'Registration successful!',
      'requiresPhoneVerification': response['requiresPhoneVerification'] == true,
      'phoneOtpSent': response['phoneOtpSent'] == true,
      'smsNotice': response['smsNotice'],
    };
  }

  Future<UserModel> login({
    required String email,
    required String password,
    String? countryCode,
  }) async {
    final payload = <String, dynamic>{
      'email': email,
      'identifier': email,
      'password': password,
    };
    if (countryCode != null && countryCode.isNotEmpty) {
      payload['countryCode'] = countryCode;
    }

    final response = await _apiClient.post(ApiEndpoints.login, payload);

    final String token = response['token'] ?? '';
    final userData = response['user'] as Map<String, dynamic>;
    final user = UserModel.fromJson(userData);

    await _storageService.saveToken(token);
    await _persistUser(user);

    return user;
  }

  Future<UserModel?> getMe() async {
    final token = _storageService.getToken();
    if (token == null || token.isEmpty) return null;

    try {
      final response = await _apiClient.get(ApiEndpoints.me);
      if (response['user'] != null) {
        final user = UserModel.fromJson(response['user']);
        await _persistUser(user);
        return user;
      }
    } catch (_) {
      // Invalid/expired token or session invalidated
      await _storageService.clearUser();
    }
    return null;
  }

  Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? phoneNumber,
    String? countryCode,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (phoneNumber != null) payload['phoneNumber'] = phoneNumber;
    if (countryCode != null) payload['countryCode'] = countryCode;

    final response = await _apiClient.put(ApiEndpoints.profile, payload);
    final user = UserModel.fromJson(response['user']);
    await _persistUser(user);

    return {
      'user': user,
      'message': response['message'] ?? 'Profile updated successfully',
      'phoneChanged': response['phoneChanged'] == true,
      'requiresPhoneVerification': response['requiresPhoneVerification'] == true,
      'smsNotice': response['smsNotice'],
    };
  }

  Future<UserModel> uploadAvatar(
    String filePath, {
    String? filename,
    MediaType? contentType,
  }) async {
    final response = await _apiClient.uploadFile(
      ApiEndpoints.avatar,
      filePath,
      'avatar',
      filename: filename,
      contentType: contentType,
    );
    final user = UserModel.fromJson(response['user']);
    await _persistUser(user);
    return user;
  }

  Future<UserModel> removeAvatar() async {
    final response = await _apiClient.delete(ApiEndpoints.avatar);
    final user = UserModel.fromJson(response['user']);
    await _persistUser(user);
    return user;
  }

  Future<UserModel> verifyPhone(String otp) async {
    final response = await _apiClient.post(ApiEndpoints.verifyPhone, {
      'otp': otp.trim(),
    });
    final user = UserModel.fromJson(response['user']);
    await _persistUser(user);
    return user;
  }

  Future<Map<String, dynamic>> resendPhoneOtp() async {
    final response = await _apiClient.post(ApiEndpoints.resendPhoneOtp, {});
    return response is Map<String, dynamic> ? response : {};
  }

  // Forgot Password Flow
  Future<Map<String, dynamic>> forgotPasswordSendEmailOtp({
    required String email,
  }) async {
    final response = await _apiClient.post(ApiEndpoints.forgotPasswordSendOtp, {
      'email': email.trim(),
      'channel': 'email',
    });
    return response is Map<String, dynamic> ? response : {};
  }

  Future<String> forgotPasswordVerifyEmailOtp({
    required String lookupToken,
    required String otp,
    String? email,
  }) async {
    final response = await _apiClient.post(ApiEndpoints.forgotPasswordVerifyOtp, {
      'lookupToken': lookupToken,
      'channel': 'email',
      'email': email,
      'otp': otp.trim(),
    });
    return (response['resetToken'] ?? '').toString();
  }

  Future<Map<String, dynamic>> forgotPasswordLookup({
    required String identifier,
    String? countryCode,
  }) async {
    final payload = <String, dynamic>{'identifier': identifier.trim()};
    if (countryCode != null && countryCode.isNotEmpty) {
      payload['countryCode'] = countryCode;
    }
    final response = await _apiClient.post(ApiEndpoints.forgotPasswordLookup, payload);
    return response is Map<String, dynamic> ? response : {};
  }

  Future<Map<String, dynamic>> forgotPasswordSendOtp({
    required String lookupToken,
    required String channel,
  }) async {
    final response = await _apiClient.post(ApiEndpoints.forgotPasswordSendOtp, {
      'lookupToken': lookupToken,
      'channel': channel,
    });
    return response is Map<String, dynamic> ? response : {};
  }

  Future<String> forgotPasswordVerifyOtp({
    required String lookupToken,
    required String channel,
    required String otp,
  }) async {
    final response = await _apiClient.post(ApiEndpoints.forgotPasswordVerifyOtp, {
      'lookupToken': lookupToken,
      'channel': channel,
      'otp': otp.trim(),
    });
    return (response['resetToken'] ?? '').toString();
  }

  Future<String> forgotPasswordReset({
    required String resetToken,
    required String newPassword,
  }) async {
    final response = await _apiClient.post(ApiEndpoints.forgotPasswordReset, {
      'resetToken': resetToken,
      'newPassword': newPassword,
    });
    return (response['message'] ?? 'Password reset successfully!').toString();
  }

  Future<void> logout() async {
    await _storageService.clearUser();
  }
}
