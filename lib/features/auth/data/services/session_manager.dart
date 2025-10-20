import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/user_details.dart';

class SessionManager {
  const SessionManager();

  static const String _cookiesKey = 'session_cookies';
  static const String _userDetailsKey = 'session_user_details';

  Future<void> persistCookies(Map<String, String> cookies) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(cookies);
    await prefs.setString(_cookiesKey, encoded);
  }

  Future<Map<String, String>> loadCookies() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_cookiesKey);
    if (stored == null || stored.isEmpty) {
      return const {};
    }

    final Map<String, dynamic> decoded =
        jsonDecode(stored) as Map<String, dynamic>;
    final cookies = decoded.map(
      (key, value) => MapEntry(key, value.toString()),
    );

    return cookies;
  }

  Future<void> clearCookies() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cookiesKey);
  }

  Future<void> persistUserDetails(UserDetails details) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(details.toJson());
    await prefs.setString(_userDetailsKey, encoded);
  }

  Future<UserDetails?> loadUserDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_userDetailsKey);
    if (stored == null || stored.isEmpty) {
      return null;
    }

    final Map<String, dynamic> decoded =
        jsonDecode(stored) as Map<String, dynamic>;
    return UserDetails.fromJson(decoded);
  }

  Future<void> clearUserDetails() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userDetailsKey);
  }
}
