import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/storage_service.dart';
import '../domain/user_model.dart';

class AuthRepository {
  final ApiClient _apiClient;
  final StorageService _storageService;

  AuthRepository(this._apiClient, this._storageService);

  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(ApiEndpoints.register, {
      'name': name,
      'email': email,
      'password': password,
    });

    // If backend returns user info upon registration
    if (response['user'] != null) {
      return UserModel.fromJson(response['user']);
    }
    return UserModel(id: '', name: name, email: email);
  }

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(ApiEndpoints.login, {
      'email': email,
      'password': password,
    });

    final String token = response['token'] ?? '';
    final userData = response['user'] as Map<String, dynamic>;
    final user = UserModel.fromJson(userData);

    await _storageService.saveToken(token);
    await _storageService.saveUser(
      id: user.id,
      name: user.name,
      email: user.email,
    );

    return user;
  }

  Future<UserModel?> getMe() async {
    final token = _storageService.getToken();
    if (token == null || token.isEmpty) return null;

    try {
      final response = await _apiClient.get(ApiEndpoints.me);
      if (response['user'] != null) {
        final user = UserModel.fromJson(response['user']);
        await _storageService.saveUser(
          id: user.id,
          name: user.name,
          email: user.email,
        );
        return user;
      }
    } catch (_) {
      // Invalid/expired token
      await _storageService.clearUser();
    }
    return null;
  }

  Future<void> logout() async {
    await _storageService.clearUser();
  }
}
