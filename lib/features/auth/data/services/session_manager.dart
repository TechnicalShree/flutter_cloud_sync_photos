import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  const SessionManager();

  static const String _cookiesKey = 'session_cookies';

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
}
