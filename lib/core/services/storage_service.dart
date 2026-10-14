import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyToken = 'auth_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUserName = 'user_name';
  static const String _keyUserEmail = 'user_email';
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
  }) async {
    await _prefs.setString(_keyUserId, id);
    await _prefs.setString(_keyUserName, name);
    await _prefs.setString(_keyUserEmail, email);
  }

  Map<String, String?> getUser() {
    return {
      'id': _prefs.getString(_keyUserId),
      'name': _prefs.getString(_keyUserName),
      'email': _prefs.getString(_keyUserEmail),
    };
  }

  Future<void> clearUser() async {
    await _prefs.remove(_keyUserId);
    await _prefs.remove(_keyUserName);
    await _prefs.remove(_keyUserEmail);
    await _prefs.remove(_keyToken);
  }

  // Dynamic Server Base URL Configuration
  Future<void> saveBaseUrl(String url) async {
    await _prefs.setString(_keyBaseUrl, url);
  }

  String? getBaseUrl() {
    return _prefs.getString(_keyBaseUrl);
  }

  // History Persistence
  Future<void> saveHistoryDocs(List<Map<String, dynamic>> docs) async {
    final encoded = jsonEncode(docs);
    await _prefs.setString(_keyHistoryDocs, encoded);
  }

  List<Map<String, dynamic>> getHistoryDocs() {
    final raw = _prefs.getString(_keyHistoryDocs);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List decoded = jsonDecode(raw);
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // Account-Scoped History Exclusion Persistence
  String _getExcludedHistoryKey() {
    final userId = _prefs.getString(_keyUserId) ?? 'guest';
    return 'excluded_history_ids_$userId';
  }

  Set<String> getExcludedHistoryIds() {
    final key = _getExcludedHistoryKey();
    final list = _prefs.getStringList(key);
    return list != null ? list.toSet() : <String>{};
  }

  Future<void> addExcludedHistoryId(String docId) async {
    final key = _getExcludedHistoryKey();
    final set = getExcludedHistoryIds()..add(docId);
    await _prefs.setStringList(key, set.toList());
  }

  Future<void> removeExcludedHistoryId(String docId) async {
    final key = _getExcludedHistoryKey();
    final set = getExcludedHistoryIds()..remove(docId);
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
