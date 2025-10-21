import 'package:flutter_cloud_sync_photos/core/network/api_client.dart'
    as network;
import 'package:flutter_cloud_sync_photos/core/network/api_exception.dart';
import 'package:flutter_cloud_sync_photos/core/network/network_config.dart';
import 'package:flutter_cloud_sync_photos/core/network/network_service.dart';
import 'package:http/http.dart' as http;

import 'session_manager.dart';
import '../../domain/models/user_details.dart';
import '../models/photo_media.dart';
import '../../../../core/utils/folder_path_builder.dart';

enum AuthStatus { authenticated, unauthenticated, offline }

class AuthService {
  AuthService({
    network.ApiClient? apiClient,
    SessionManager? sessionManager,
    NetworkService? networkService,
  }) : _apiClient = apiClient ?? network.apiClient,
       _sessionManager = sessionManager ?? SessionManager(),
       _networkService = networkService ?? NetworkService();

  final network.ApiClient _apiClient;
  final SessionManager _sessionManager;
  final NetworkService _networkService;
  Map<String, String> _sessionCookies = const {};
  UserDetails? _userDetails;

  Map<String, String> get sessionCookies => Map.unmodifiable(_sessionCookies);

  UserDetails? get currentUser => _userDetails;

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
    await _loadAndPersistUserDetails();

    return sessionCookies;
  }

  Future<AuthStatus> resolveInitialAuth() async {
    final online = await _networkService.isOnline();

    if (!online) {
      final storedCookies = await _sessionManager.loadCookies();
      if (storedCookies.isNotEmpty) {
        _sessionCookies = storedCookies;
        _apiClient.setDefaultCookies(storedCookies, merge: false);
        _userDetails = await _sessionManager.loadUserDetails();
      }
      return AuthStatus.offline;
    }

    final hasSession = await verifySession();
    if (hasSession) {
      _userDetails = await _sessionManager.loadUserDetails();
      if (_userDetails == null) {
        await _loadAndPersistUserDetails();
      }
    }
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
    _userDetails = null;
    await _sessionManager.clearCookies();
    await _sessionManager.clearUserDetails();
    _apiClient.setDefaultCookies({}, merge: false);
  }

  Future<UserDetails> fetchUserDetails() async {
    try {
      final response = await _apiClient.sendToEndpoint<Map<String, dynamic>>(
        method: network.ApiMethod.get,
        endpoint: ApiEndpoint.userDetails,
        parser: (data) =>
            (data as Map<String, dynamic>? ?? <String, dynamic>{}),
      );

      final message = response.data['message'];
      final userDetails = message is Map<String, dynamic>
          ? UserDetails.fromJson(message)
          : UserDetails.fromJson(response.data);

      _userDetails = userDetails;
      await _sessionManager.persistUserDetails(userDetails);
      return userDetails;
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(message: 'Failed to load user details', body: error);
    }
  }

  Future<void> _loadAndPersistUserDetails() async {
    await fetchUserDetails();
  }

  Future<Map<String, dynamic>> uploadFile({
    required String fileName,
    required List<int> bytes,
    required bool isPrivate,
    required String folder,
    required bool optimize,
  }) async {
    try {
      final file = http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      );

      final fields = <String, String>{
        'is_private': isPrivate ? '1' : '0',
        'folder': folder,
        'optimize': optimize ? '1' : '0',
      };

      final response = await _apiClient.sendMultipart<Map<String, dynamic>>(
        path: ApiEndpoint.uploadFile.path,
        files: [file],
        fields: fields,
        parser: (data) =>
            (data as Map<String, dynamic>? ?? <String, dynamic>{}),
      );

      final message = response.data['message'];
      if (message is Map<String, dynamic>) {
        return message;
      }
      return response.data;
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(message: 'File upload failed', body: error);
    }
  }

  Future<Map<String, dynamic>> unsyncFile({
    required String contentHash,
  }) async {
    if (contentHash.isEmpty) {
      throw ApiException(message: 'Missing content hash');
    }

    try {
      final response = await _apiClient.sendToEndpoint<Map<String, dynamic>>(
        method: network.ApiMethod.post,
        endpoint: ApiEndpoint.unsyncFile,
        body: {'content_hash': contentHash},
        parser: (data) =>
            (data as Map<String, dynamic>? ?? <String, dynamic>{}),
      );

      final message = response.data['message'];
      if (message is Map<String, dynamic>) {
        return message;
      }
      return response.data;
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(message: 'Failed to unsync file', body: error);
    }
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

  String buildFolderPath(PhotoMedia photo) {
    return defaultFolderPathResolver(photo.bucketDisplayName);
  }
}

final AuthService globalAuthService = AuthService();
