import 'package:shared_preferences/shared_preferences.dart';

/// Small persistence layer for the auth token and the configurable API base URL.
class AuthStore {
  static const _tokenKey = 'atten_access_token';
  static const _baseUrlKey = 'atten_base_url';

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static Future<String?> getToken() async => (await _prefs).getString(_tokenKey);

  static Future<void> setToken(String token) async =>
      (await _prefs).setString(_tokenKey, token);

  static Future<void> clearToken() async => (await _prefs).remove(_tokenKey);

  static Future<String?> getBaseUrl() async => (await _prefs).getString(_baseUrlKey);

  static Future<void> setBaseUrl(String url) async =>
      (await _prefs).setString(_baseUrlKey, url);
}
