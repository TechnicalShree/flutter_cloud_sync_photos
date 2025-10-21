import 'dart:async';

import 'package:flutter_cloud_sync_photos/core/network/api_client.dart' as network;
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
    String? contentHash,
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
        if (contentHash != null && contentHash.isNotEmpty)
          'content_hash': contentHash,
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

  Future<ResumableUploadSession?> startResumableUpload({
    required String fileName,
    required bool isPrivate,
    required String folder,
    required bool optimize,
    required int totalBytes,
    String? contentHash,
    String? resumeSessionId,
    int? resumeOffset,
  }) async {
    try {
      final response = await _apiClient.sendToEndpoint<Map<String, dynamic>>(
        method: network.ApiMethod.post,
        endpoint: ApiEndpoint.startResumableUpload,
        parser: (data) =>
            (data as Map<String, dynamic>? ?? <String, dynamic>{}),
        body: {
          'file_name': fileName,
          'is_private': isPrivate ? '1' : '0',
          'folder': folder,
          'optimize': optimize ? '1' : '0',
          'total_bytes': totalBytes,
          if (contentHash != null && contentHash.isNotEmpty)
            'content_hash': contentHash,
          if (resumeSessionId != null) 'session_id': resumeSessionId,
          if (resumeOffset != null) 'resume_offset': resumeOffset,
        },
      );

      final dynamic payload = response.data['message'];
      final Map<String, dynamic> body =
          payload is Map<String, dynamic> ? payload : response.data;

      if (body.isEmpty) {
        return null;
      }

      final session = ResumableUploadSession.fromJson(body);
      if (session.sessionId.isEmpty) {
        return null;
      }
      return session;
    } on ApiException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 400) {
        return null;
      }
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<ResumableChunkAck> uploadChunk({
    required ResumableUploadSession session,
    required List<int> bytes,
    required int start,
    required int total,
    required bool isLast,
    String? contentHash,
  }) async {
    if (session.uploadUrl != null && session.uploadUrl!.isNotEmpty) {
      final uri = Uri.parse(session.uploadUrl!);
      final request = http.Request('PUT', uri);
      request.bodyBytes = bytes;
      final headers = <String, String>{
        'Content-Range': 'bytes $start-${start + bytes.length - 1}/$total',
        'Content-Length': '${bytes.length}',
        ...session.headers,
      };
      if (contentHash != null && contentHash.isNotEmpty) {
        headers.putIfAbsent('x-content-sha256', () => contentHash);
        headers.putIfAbsent('x-amz-meta-content-sha256', () => contentHash);
      }
      request.headers.addAll(headers);

      http.Response response;
      final client = http.Client();
      try {
        final streamed =
            await client.send(request).timeout(_apiClient.config.timeout);
        response = await http.Response.fromStream(streamed);
      } on TimeoutException catch (error) {
        throw ApiException(
          message: 'Chunk upload timed out',
          body: error.toString(),
        );
      } on Exception catch (error) {
        throw ApiException(
          message: 'Failed to upload chunk',
          body: error.toString(),
        );
      } finally {
        client.close();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          message: 'Chunk upload failed',
          statusCode: response.statusCode,
          body: response.body,
        );
      }

      final uploadedHeader = response.headers['x-uploaded-bytes'];
      final confirmed = uploadedHeader != null
          ? int.tryParse(uploadedHeader) ?? (start + bytes.length)
          : (start + bytes.length);

      final etag = response.headers['etag'] ?? response.headers['ETag'];
      final hashHeader = response.headers['x-content-hash'] ??
          response.headers['x-amz-meta-content-sha256'] ??
          response.headers['x-content-sha256'];

      return ResumableChunkAck(
        confirmedBytes: confirmed,
        contentHash: hashHeader?.isNotEmpty == true ? hashHeader : null,
        etag: etag,
      );
    }

    final fields = <String, String>{
      'session_id': session.sessionId,
      'offset': '$start',
      'total': '$total',
      'is_last': isLast ? '1' : '0',
      if (contentHash != null && contentHash.isNotEmpty)
        'content_hash': contentHash,
    };

    final file = http.MultipartFile.fromBytes(
      'chunk',
      bytes,
      filename: '${session.sessionId}_${start}_chunk',
    );

    final response = await _apiClient.sendMultipart<Map<String, dynamic>>(
      path: ApiEndpoint.uploadChunk.path,
      files: [file],
      fields: fields,
      parser: (data) =>
          (data as Map<String, dynamic>? ?? <String, dynamic>{}),
    );

    final dynamic payload = response.data['message'];
    final Map<String, dynamic> body =
        payload is Map<String, dynamic> ? payload : response.data;

    return ResumableChunkAck.fromJson(body);
  }

  Future<ResumableUploadCompletion> completeResumableUpload({
    required String sessionId,
    String? contentHash,
  }) async {
    try {
      final response = await _apiClient.sendToEndpoint<Map<String, dynamic>>(
        method: network.ApiMethod.post,
        endpoint: ApiEndpoint.completeResumableUpload,
        body: {
          'session_id': sessionId,
          if (contentHash != null && contentHash.isNotEmpty)
            'content_hash': contentHash,
        },
        parser: (data) =>
            (data as Map<String, dynamic>? ?? <String, dynamic>{}),
      );
      final dynamic payload = response.data['message'];
      final Map<String, dynamic> body =
          payload is Map<String, dynamic> ? payload : response.data;
      return ResumableUploadCompletion.fromJson(body);
    } on ApiException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 400) {
        return const ResumableUploadCompletion();
      }
      rethrow;
    } catch (_) {
      return const ResumableUploadCompletion();
    }
  }
}

class ResumableUploadSession {
  const ResumableUploadSession({
    required this.sessionId,
    this.chunkSize,
    this.uploadUrl,
    Map<String, String>? headers,
  }) : headers = headers == null
            ? const <String, String>{}
            : Map.unmodifiable(headers);

  factory ResumableUploadSession.fromJson(Map<String, dynamic> json) {
    final headers = <String, String>{};
    final dynamic jsonHeaders = json['headers'];
    if (jsonHeaders is Map) {
      jsonHeaders.forEach((key, value) {
        if (key != null && value != null) {
          headers[key.toString()] = value.toString();
        }
      });
    }

    return ResumableUploadSession(
      sessionId: json['session_id']?.toString() ?? '',
      chunkSize: json['chunk_size'] is int
          ? json['chunk_size'] as int
          : int.tryParse(json['chunk_size']?.toString() ?? ''),
      uploadUrl: json['upload_url']?.toString(),
      headers: headers,
    );
  }

  final String sessionId;
  final int? chunkSize;
  final String? uploadUrl;
  final Map<String, String> headers;

  int get effectiveChunkSize =>
      chunkSize != null && chunkSize! > 0 ? chunkSize! : 2 * 1024 * 1024;
}

class ResumableChunkAck {
  const ResumableChunkAck({
    required this.confirmedBytes,
    this.contentHash,
    this.etag,
  });

  factory ResumableChunkAck.fromJson(Map<String, dynamic> json) {
    final confirmed = json['confirmed_bytes'];
    return ResumableChunkAck(
      confirmedBytes: confirmed is int
          ? confirmed
          : int.tryParse(confirmed?.toString() ?? '') ?? 0,
      contentHash: json['content_hash']?.toString(),
      etag: json['etag']?.toString(),
    );
  }

  final int confirmedBytes;
  final String? contentHash;
  final String? etag;
}

class ResumableUploadCompletion {
  const ResumableUploadCompletion({
    this.contentHash,
    this.etag,
  });

  factory ResumableUploadCompletion.fromJson(Map<String, dynamic> json) {
    return ResumableUploadCompletion(
      contentHash: json['content_hash']?.toString(),
      etag: json['etag']?.toString(),
    );
  }

  final String? contentHash;
  final String? etag;
}

final AuthService globalAuthService = AuthService();
