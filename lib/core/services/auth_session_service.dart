import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthSessionService {
  static final AuthSessionService _instance = AuthSessionService._internal();
  factory AuthSessionService() => _instance;
  AuthSessionService._internal();

  static const String _authTokenKey = 'auth_token';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  Future<void> saveAuthToken(String token) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      await _secureStorage.write(key: _authTokenKey, value: token);
    } catch (e) {
      debugPrint('⚠️ Secure token storage failed, falling back to legacy cache: $e');
    }

    await prefs.setString(_authTokenKey, token);
  }

  Future<String?> readAuthToken() async {
    try {
      final token = await _secureStorage.read(key: _authTokenKey);
      if (token != null && token.isNotEmpty) {
        return token;
      }
    } catch (e) {
      debugPrint('⚠️ Secure token read failed, falling back to legacy cache: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_authTokenKey);
    if (legacyToken != null && legacyToken.isNotEmpty) {
      try {
        await _secureStorage.write(key: _authTokenKey, value: legacyToken);
      } catch (e) {
        debugPrint('⚠️ Could not backfill secure token cache: $e');
      }
      return legacyToken;
    }

    return null;
  }

  Future<void> clearAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _secureStorage.delete(key: _authTokenKey);
    } catch (e) {
      debugPrint('⚠️ Secure token delete failed: $e');
    }
    await prefs.remove(_authTokenKey);
  }
}