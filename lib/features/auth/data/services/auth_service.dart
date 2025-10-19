import 'package:flutter_cloud_sync_photos/core/network/api_client.dart'
    as network;
import 'package:flutter_cloud_sync_photos/core/network/api_exception.dart';
import 'package:flutter_cloud_sync_photos/core/network/network_config.dart';
import 'package:flutter_cloud_sync_photos/core/network/network_service.dart';

import 'session_manager.dart';

enum AuthStatus { authenticated, unauthenticated, offline }

class AuthService {
  AuthService({
    network.ApiClient? apiClient,
    SessionManager? sessionManager,
    NetworkService? networkService,
  }) : _apiClient = apiClient ?? network.apiClient,
       _sessionManager = sessionManager ?? const SessionManager(),
        _networkService = networkService ?? NetworkService();

  final network.ApiClient _apiClient;
  final SessionManager _sessionManager;
  final NetworkService _networkService;
  Map<String, String> _sessionCookies = const {};

  Map<String, String> get sessionCookies => Map.unmodifiable(_sessionCookies);

  Future<Map<String, String>> login({
    required String username,
    required String password,
  }) async {
    final online = await _networkService.isOnline();
    if (!online) {
      throw ApiException(
        message: 'No internet connection. Please reconnect and try again.',
      );
    }

    final response = await _apiClient.sendToEndpoint<Map<String, dynamic>>(
      method: network.ApiMethod.post,
      endpoint: ApiEndpoint.login,
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'usr': username, 'pwd': password},
      parser: (data) => (data as Map<String, dynamic>? ?? <String, dynamic>{}),
    );

    final cookies = _extractCookies(response.headers);

    if (cookies.isEmpty) {
      throw ApiException(
        message: 'Authentication cookies missing in login response.',
        statusCode: response.statusCode,
        body: response.rawData,
      );
    }

    _sessionCookies = cookies;
    await _sessionManager.persistCookies(cookies);
    _apiClient.setDefaultCookies(cookies, merge: false);

    return sessionCookies;
  }

  Future<AuthStatus> resolveInitialAuth() async {
    final online = await _networkService.isOnline();

    if (!online) {
      final storedCookies = await _sessionManager.loadCookies();
      if (storedCookies.isNotEmpty) {
        _sessionCookies = storedCookies;
        _apiClient.setDefaultCookies(storedCookies, merge: false);
      }
      return AuthStatus.offline;
    }

    final hasSession = await verifySession();
    return hasSession ? AuthStatus.authenticated : AuthStatus.unauthenticated;
  }

  Future<bool> verifySession() async {
    final storedCookies = await _sessionManager.loadCookies();
    if (storedCookies.isEmpty) {
      return false;
    }

    _sessionCookies = storedCookies;
    _apiClient.setDefaultCookies(storedCookies, merge: false);

    try {
      await _apiClient.sendToEndpoint<Map<String, dynamic>>(
        method: network.ApiMethod.get,
        endpoint: ApiEndpoint.verifySession,
        parser: (data) =>
            (data as Map<String, dynamic>? ?? <String, dynamic>{}),
      );
      return true;
    } on ApiException {
      await logout();
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    _sessionCookies = const {};
    await _sessionManager.clearCookies();
    _apiClient.setDefaultCookies({}, merge: false);
  }

  Map<String, String> _extractCookies(Map<String, String> headers) {
    final setCookie = headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) {
      return const {};
    }

    final cookieSegments = setCookie.split(RegExp(r', (?=[^;,\s]+=)'));
    final cookies = <String, String>{};

    for (final segment in cookieSegments) {
      final pair = segment.split(';').first.trim();
      if (pair.isEmpty) {
        continue;
      }

      final separatorIndex = pair.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }

      final name = pair.substring(0, separatorIndex).trim();
      final value = pair.substring(separatorIndex + 1).trim();

      if (name.isEmpty) {
        continue;
      }

      cookies[name] = value;
    }

    return cookies;
  }
}

final AuthService globalAuthService = AuthService();
