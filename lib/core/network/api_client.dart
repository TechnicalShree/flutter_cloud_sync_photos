import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';

enum ApiMethod { get, post, put, delete, patch, head }

typedef ResponseParser<T> = T Function(dynamic data);

class ApiResponse<T> {
  ApiResponse({
    required this.statusCode,
    required this.data,
    required this.headers,
    required this.uri,
    this.rawData,
  });

  final int statusCode;
  final T data;
  final Map<String, String> headers;
  final Uri uri;
  final dynamic rawData;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;
}

class ApiClient {
  ApiClient({required ApiConfig config, http.Client? httpClient})
    : _config = config,
      _httpClient = httpClient ?? http.Client();

  ApiConfig get config => _config;

  void updateConfig(ApiConfig config) {
    _config = config;
  }

  void setDefaultHeaders(Map<String, String> headers) {
    updateConfig(_config.copyWith(defaultHeaders: headers));
  }

  void setDefaultCookies(Map<String, String> cookies) {
    updateConfig(_config.copyWith(defaultCookies: cookies));
  }

  Future<ApiResponse<T>> send<T>({
    required ApiMethod method,
    required String path,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Map<String, String>? cookies,
    Object? body,
    Duration? timeout,
    ResponseParser<T>? parser,
    bool Function(int statusCode)? validateStatus,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final requestHeaders = _prepareHeaders(headers, cookies);
    final requestBody = _encodeBody(body, requestHeaders);
    final response = await _sendRequest(
      method: method,
      uri: uri,
      headers: requestHeaders,
      body: requestBody,
      timeout: timeout ?? _config.timeout,
    );

    final decodedBody = _decodeBody(response.body);
    final isValid =
        validateStatus?.call(response.statusCode) ??
        _isSuccessful(response.statusCode);

    if (!isValid) {
      throw ApiException(
        message:
            'Request failed for ${method.name.toUpperCase()} ${uri.toString()}',
        statusCode: response.statusCode,
        body: decodedBody,
      );
    }

    final T parsedBody = parser != null
        ? parser(decodedBody)
        : decodedBody as T;

    return ApiResponse<T>(
      statusCode: response.statusCode,
      data: parsedBody,
      headers: response.headers,
      uri: uri,
      rawData: decodedBody,
    );
  }

  void close() {
    _httpClient.close();
  }

  ApiConfig _config;
  final http.Client _httpClient;

  Uri _buildUri(String path, Map<String, String>? queryParameters) {
    final baseUri = Uri.parse(_config.baseUrl);
    final resolved = baseUri.resolve(path);
    final combinedQueryParameters = <String, String>{
      ...baseUri.queryParameters,
      if (queryParameters != null) ...queryParameters,
    };

    return resolved.replace(
      queryParameters: combinedQueryParameters.isEmpty
          ? null
          : combinedQueryParameters,
    );
  }

  Map<String, String> _prepareHeaders(
    Map<String, String>? headers,
    Map<String, String>? cookies,
  ) {
    final mergedHeaders = {
      ..._config.defaultHeaders,
      if (headers != null) ...headers,
    };

    final mergedCookies = {
      ..._config.defaultCookies,
      if (cookies != null) ...cookies,
    };

    if (mergedCookies.isNotEmpty && !_hasCookieHeader(mergedHeaders)) {
      mergedHeaders['cookie'] = _buildCookieHeader(mergedCookies);
    }

    return mergedHeaders;
  }

  Object? _encodeBody(Object? body, Map<String, String> headers) {
    if (body == null) {
      return null;
    }

    if (body is Map || body is Iterable) {
      headers.putIfAbsent('Content-Type', () => 'application/json');
      return jsonEncode(body);
    }

    return body;
  }

  Future<http.Response> _sendRequest({
    required ApiMethod method,
    required Uri uri,
    required Map<String, String> headers,
    Object? body,
    required Duration timeout,
  }) {
    switch (method) {
      case ApiMethod.get:
        return _httpClient.get(uri, headers: headers).timeout(timeout);
      case ApiMethod.post:
        return _httpClient
            .post(uri, headers: headers, body: body)
            .timeout(timeout);
      case ApiMethod.put:
        return _httpClient
            .put(uri, headers: headers, body: body)
            .timeout(timeout);
      case ApiMethod.delete:
        return _httpClient
            .delete(uri, headers: headers, body: body)
            .timeout(timeout);
      case ApiMethod.patch:
        return _httpClient
            .patch(uri, headers: headers, body: body)
            .timeout(timeout);
      case ApiMethod.head:
        return _httpClient.head(uri, headers: headers).timeout(timeout);
    }
  }

  dynamic _decodeBody(String body) {
    if (body.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  bool _isSuccessful(int statusCode) => statusCode >= 200 && statusCode < 300;

  bool _hasCookieHeader(Map<String, String> headers) {
    return headers.keys.any((key) => key.toLowerCase() == 'cookie');
  }

  String _buildCookieHeader(Map<String, String> cookies) {
    final entries = cookies.entries.map(
      (entry) => '${entry.key}=${entry.value}',
    );
    return entries.join('; ');
  }
}

/// Global API client. Update the base URL and defaults to match your backend.
final apiClient = ApiClient(
  config: ApiConfig(
    baseUrl: 'https://frappe.technicalshree.in/',
    defaultHeaders: const {'Accept': 'application/json'},
  ),
);
