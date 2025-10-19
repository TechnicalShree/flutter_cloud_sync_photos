class ApiConfig {
  ApiConfig({
    required this.baseUrl,
    Map<String, String>? defaultHeaders,
    Map<String, String>? defaultCookies,
    Duration? timeout,
  }) : defaultHeaders = Map.unmodifiable(defaultHeaders ?? const {}),
       defaultCookies = Map.unmodifiable(defaultCookies ?? const {}),
       timeout = timeout ?? const Duration(seconds: 30);

  final String baseUrl;
  final Map<String, String> defaultHeaders;
  final Map<String, String> defaultCookies;
  final Duration timeout;

  ApiConfig copyWith({
    String? baseUrl,
    Map<String, String>? defaultHeaders,
    Map<String, String>? defaultCookies,
    Duration? timeout,
  }) {
    return ApiConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      defaultCookies: defaultCookies ?? this.defaultCookies,
      timeout: timeout ?? this.timeout,
    );
  }
}
