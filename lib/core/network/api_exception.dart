class ApiException implements Exception {
  ApiException({required this.message, this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final dynamic body;

  @override
  String toString() {
    final buffer = StringBuffer('ApiException: $message');
    if (statusCode != null) {
      buffer.write(' (statusCode: $statusCode)');
    }
    if (body != null) {
      buffer.write(', body: $body');
    }
    return buffer.toString();
  }
}
