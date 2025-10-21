import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/user_details.dart';

class SessionManager {
  SessionManager({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _cookiesKey = 'session_cookies';
  static const String _userDetailsKey = 'session_user_details';
  static const String _legacyCookiesKey = _cookiesKey;
  static const String _legacyUserDetailsKey = _userDetailsKey;

  final FlutterSecureStorage _secureStorage;
  bool _secureStorageUnavailable = false;

  Future<void> persistCookies(Map<String, String> cookies) async {
    final encoded = jsonEncode(cookies);
    final storedSecurely = await _writeSecure(_cookiesKey, encoded);
    if (!storedSecurely) {
      await _persistLegacyString(_legacyCookiesKey, encoded);
    }
  }

  Future<Map<String, String>> loadCookies() async {
    final stored = await _readSecure(_cookiesKey);
    if (stored != null && stored.isNotEmpty) {
      return _decodeStringMap(stored);
    }

    final legacy = await _readLegacyString(_legacyCookiesKey);
    if (legacy == null || legacy.isEmpty) {
      return const {};
    }

    final migrated = await _writeSecure(_cookiesKey, legacy);
    if (migrated) {
      await _removeLegacyKey(_legacyCookiesKey);
    }
    return _decodeStringMap(legacy);
  }

  Future<void> clearCookies() async {
    await _deleteSecure(_cookiesKey);
    await _removeLegacyKey(_legacyCookiesKey);
  }

  Future<void> persistUserDetails(UserDetails details) async {
    final encoded = jsonEncode(details.toJson());
    final storedSecurely = await _writeSecure(_userDetailsKey, encoded);
    if (!storedSecurely) {
      await _persistLegacyString(_legacyUserDetailsKey, encoded);
    }
  }

  Future<UserDetails?> loadUserDetails() async {
    final stored = await _readSecure(_userDetailsKey);
    if (stored != null && stored.isNotEmpty) {
      return _decodeUserDetails(stored);
    }

    final legacy = await _readLegacyString(_legacyUserDetailsKey);
    if (legacy == null || legacy.isEmpty) {
      return null;
    }

    final migrated = await _writeSecure(_userDetailsKey, legacy);
    if (migrated) {
      await _removeLegacyKey(_legacyUserDetailsKey);
    }
    return _decodeUserDetails(legacy);
  }

  Future<void> clearUserDetails() async {
    await _deleteSecure(_userDetailsKey);
    await _removeLegacyKey(_legacyUserDetailsKey);
  }

  Future<String?> _readLegacyString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> _persistLegacyString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _removeLegacyKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<String?> _readSecure(String key) async {
    if (_secureStorageUnavailable) {
      return null;
    }

    try {
      return await _secureStorage.read(key: key);
    } on MissingPluginException {
      _secureStorageUnavailable = true;
      return null;
    } on PlatformException {
      _secureStorageUnavailable = true;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _writeSecure(String key, String value) async {
    if (_secureStorageUnavailable) {
      return false;
    }

    try {
      await _secureStorage.write(key: key, value: value);
      return true;
    } on MissingPluginException {
      _secureStorageUnavailable = true;
      return false;
    } on PlatformException {
      _secureStorageUnavailable = true;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteSecure(String key) async {
    if (_secureStorageUnavailable) {
      return;
    }

    try {
      await _secureStorage.delete(key: key);
    } on MissingPluginException {
      _secureStorageUnavailable = true;
    } on PlatformException {
      _secureStorageUnavailable = true;
    }
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
