import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/user_details.dart';

class SessionManager {
  const SessionManager({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _cookiesKey = 'session_cookies';
  static const String _userDetailsKey = 'session_user_details';
  static const String _legacyCookiesKey = _cookiesKey;
  static const String _legacyUserDetailsKey = _userDetailsKey;

  final FlutterSecureStorage _secureStorage;

  Future<void> persistCookies(Map<String, String> cookies) async {
    final encoded = jsonEncode(cookies);
    await _secureStorage.write(key: _cookiesKey, value: encoded);
  }

  Future<Map<String, String>> loadCookies() async {
    final stored = await _secureStorage.read(key: _cookiesKey);
    if (stored != null && stored.isNotEmpty) {
      return _decodeStringMap(stored);
    }

    final legacy = await _readLegacyString(_legacyCookiesKey);
    if (legacy == null || legacy.isEmpty) {
      return const {};
    }

    await _secureStorage.write(key: _cookiesKey, value: legacy);
    await _removeLegacyKey(_legacyCookiesKey);
    return _decodeStringMap(legacy);
  }

  Future<void> clearCookies() async {
    await _secureStorage.delete(key: _cookiesKey);
    await _removeLegacyKey(_legacyCookiesKey);
  }

  Future<void> persistUserDetails(UserDetails details) async {
    final encoded = jsonEncode(details.toJson());
    await _secureStorage.write(key: _userDetailsKey, value: encoded);
  }

  Future<UserDetails?> loadUserDetails() async {
    final stored = await _secureStorage.read(key: _userDetailsKey);
    if (stored != null && stored.isNotEmpty) {
      return _decodeUserDetails(stored);
    }

    final legacy = await _readLegacyString(_legacyUserDetailsKey);
    if (legacy == null || legacy.isEmpty) {
      return null;
    }

    await _secureStorage.write(key: _userDetailsKey, value: legacy);
    await _removeLegacyKey(_legacyUserDetailsKey);
    return _decodeUserDetails(legacy);
  }

  Future<void> clearUserDetails() async {
    await _secureStorage.delete(key: _userDetailsKey);
    await _removeLegacyKey(_legacyUserDetailsKey);
  }

  Future<String?> _readLegacyString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> _removeLegacyKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Map<String, String> _decodeStringMap(String stored) {
    final Map<String, dynamic> decoded =
        jsonDecode(stored) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  UserDetails _decodeUserDetails(String stored) {
    final Map<String, dynamic> decoded =
        jsonDecode(stored) as Map<String, dynamic>;
    return UserDetails.fromJson(decoded);
  }
}
