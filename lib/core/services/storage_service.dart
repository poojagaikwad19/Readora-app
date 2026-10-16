import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyToken = 'auth_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUserName = 'user_name';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserPhone = 'user_phone';
  static const String _keyUserPhoneVerified = 'user_phone_verified';
  static const String _keyUserEmailVerified = 'user_email_verified';
  static const String _keyUserAvatar = 'user_avatar';
  static const String _keyBaseUrl = 'base_url';
  static const String _keyHistoryDocs = 'history_docs';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // Token Management
  Future<void> saveToken(String token) async {
    await _prefs.setString(_keyToken, token);
  }

  String? getToken() {
    return _prefs.getString(_keyToken);
  }

  Future<void> removeToken() async {
    await _prefs.remove(_keyToken);
  }

  // User Profile Persistence
  Future<void> saveUser({
    required String id,
    required String name,
    required String email,
    String? phoneNumber,
    bool isPhoneVerified = false,
    bool isEmailVerified = false,
    String? avatarUrl,
  }) async {
    await _prefs.setString(_keyUserId, id);
    await _prefs.setString(_keyUserName, name);
    await _prefs.setString(_keyUserEmail, email);
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      await _prefs.setString(_keyUserPhone, phoneNumber);
    } else {
      await _prefs.remove(_keyUserPhone);
    }
    await _prefs.setBool(_keyUserPhoneVerified, isPhoneVerified);
    await _prefs.setBool(_keyUserEmailVerified, isEmailVerified);
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      await _prefs.setString(_keyUserAvatar, avatarUrl);
    } else {
      await _prefs.remove(_keyUserAvatar);
    }

    // Account-scoped profile cache
    final profileData = {
      'id': id,
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'isPhoneVerified': isPhoneVerified,
      'isEmailVerified': isEmailVerified,
      'avatarUrl': avatarUrl,
    };
    await _prefs.setString('user_profile_$id', jsonEncode(profileData));
  }

  Map<String, dynamic> getUser([String? explicitUserId]) {
    if (explicitUserId != null && explicitUserId.isNotEmpty) {
      final cached = _prefs.getString('user_profile_$explicitUserId');
      if (cached != null) {
        try {
          return jsonDecode(cached) as Map<String, dynamic>;
        } catch (_) {}
      }
    }
    return {
      'id': _prefs.getString(_keyUserId),
      'name': _prefs.getString(_keyUserName),
      'email': _prefs.getString(_keyUserEmail),
      'phoneNumber': _prefs.getString(_keyUserPhone),
      'isPhoneVerified': _prefs.getBool(_keyUserPhoneVerified) ?? false,
      'isEmailVerified': _prefs.getBool(_keyUserEmailVerified) ?? false,
      'avatarUrl': _prefs.getString(_keyUserAvatar),
    };
  }

  Future<void> clearUser() async {
    await _prefs.remove(_keyUserId);
    await _prefs.remove(_keyUserName);
    await _prefs.remove(_keyUserEmail);
    await _prefs.remove(_keyUserPhone);
    await _prefs.remove(_keyUserPhoneVerified);
    await _prefs.remove(_keyUserEmailVerified);
    await _prefs.remove(_keyUserAvatar);
    await _prefs.remove(_keyToken);
  }

  // Dynamic Server Base URL Configuration
  Future<void> saveBaseUrl(String url) async {
    await _prefs.setString(_keyBaseUrl, url);
  }

  String? getBaseUrl() {
    return _prefs.getString(_keyBaseUrl);
  }

  // User-Scoped History Persistence
  String _getHistoryKey([String? explicitUserId]) {
    final userId = explicitUserId ?? _prefs.getString(_keyUserId) ?? 'guest';
    return 'history_docs_$userId';
  }

  Future<void> saveHistoryDocs(List<Map<String, dynamic>> docs, [String? explicitUserId]) async {
    final key = _getHistoryKey(explicitUserId);
    final encoded = jsonEncode(docs);
    await _prefs.setString(key, encoded);
  }

  List<Map<String, dynamic>> getHistoryDocs([String? explicitUserId]) {
    final key = _getHistoryKey(explicitUserId);
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List decoded = jsonDecode(raw);
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearHistoryDocs([String? explicitUserId]) async {
    final key = _getHistoryKey(explicitUserId);
    await _prefs.remove(key);
  }

  /// Safely migrate legacy global un-scoped history if it reliably belongs to current active user,
  /// then immediately destroy the un-scoped key to prevent cross-account leakage.
  void migrateLegacyHistoryDocsIfApplicable() {
    final legacy = _prefs.getString(_keyHistoryDocs);
    if (legacy != null && legacy.isNotEmpty) {
      final currentUserId = _prefs.getString(_keyUserId);
      if (currentUserId != null && currentUserId.isNotEmpty && currentUserId != 'guest') {
        final scopedKey = 'history_docs_$currentUserId';
        if (!_prefs.containsKey(scopedKey)) {
          _prefs.setString(scopedKey, legacy);
        }
      }
      _prefs.remove(_keyHistoryDocs);
    }
  }

  // Account-Scoped History Exclusion Persistence
  String _getExcludedHistoryKey([String? explicitUserId]) {
    final userId = explicitUserId ?? _prefs.getString(_keyUserId) ?? 'guest';
    return 'excluded_history_ids_$userId';
  }

  Set<String> getExcludedHistoryIds([String? explicitUserId]) {
    final key = _getExcludedHistoryKey(explicitUserId);
    final list = _prefs.getStringList(key);
    return list != null ? list.toSet() : <String>{};
  }

  Future<void> addExcludedHistoryId(String docId, [String? explicitUserId]) async {
    final key = _getExcludedHistoryKey(explicitUserId);
    final set = getExcludedHistoryIds(explicitUserId)..add(docId);
    await _prefs.setStringList(key, set.toList());
  }

  Future<void> removeExcludedHistoryId(String docId, [String? explicitUserId]) async {
    final key = _getExcludedHistoryKey(explicitUserId);
    final set = getExcludedHistoryIds(explicitUserId)..remove(docId);
    await _prefs.setStringList(key, set.toList());
  }

  // Account-Scoped Settings Persistence
  String _getSettingsKey([String? explicitUserId]) {
    final userId = explicitUserId ?? _prefs.getString(_keyUserId) ?? 'guest';
    return 'user_settings_$userId';
  }

  Future<void> saveSettings(Map<String, dynamic> settings, [String? explicitUserId]) async {
    final key = _getSettingsKey(explicitUserId);
    final encoded = jsonEncode(settings);
    await _prefs.setString(key, encoded);
  }

  Map<String, dynamic>? getSettings([String? explicitUserId]) {
    final key = _getSettingsKey(explicitUserId);
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  // Account-Scoped Downloads Persistence
  String _getDownloadsKey([String? explicitUserId]) {
    final userId = explicitUserId ?? _prefs.getString(_keyUserId) ?? 'guest';
    return 'user_downloads_$userId';
  }

  Future<void> saveDownloads(List<Map<String, dynamic>> downloads, [String? explicitUserId]) async {
    final key = _getDownloadsKey(explicitUserId);
    final encoded = jsonEncode(downloads);
    await _prefs.setString(key, encoded);
  }

  List<Map<String, dynamic>> getDownloads([String? explicitUserId]) {
    final key = _getDownloadsKey(explicitUserId);
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List decoded = jsonDecode(raw);
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
