import 'dart:io';

typedef UploadLogDirectoryBuilder = Future<Directory> Function();

class UploadErrorLogger {
  UploadErrorLogger({
    UploadLogDirectoryBuilder? directoryBuilder,
    String fileName = 'upload_errors.log',
  })  : _directoryBuilder = directoryBuilder ?? _defaultDirectoryBuilder,
        _fileName = fileName;

  final UploadLogDirectoryBuilder _directoryBuilder;
  final String _fileName;
  File? _logFile;

  static Future<Directory> _defaultDirectoryBuilder() async {
    final Directory tempBase = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}flutter_cloud_sync_photos',
    );
    if (!await tempBase.exists()) {
      await tempBase.create(recursive: true);
    }
    return tempBase;
  }

  Future<void> logError(String message) async {
    try {
      final file = await _ensureFile();
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString(
        '[$timestamp] $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Intentionally swallow logging errors to avoid breaking the caller.
    }
  }

  Future<File> _ensureFile() async {
    if (_logFile != null) {
      return _logFile!;
    }
    final directory = await _directoryBuilder();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final filePath =
        '${directory.path}${Platform.pathSeparator}$_fileName';
    final file = File(filePath);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    _logFile = file;
    return file;
  }
}
