import 'dart:io';

import 'package:flutter_cloud_sync_photos/core/logging/upload_error_logger.dart';
import 'package:test/test.dart';

void main() {
  group('UploadErrorLogger', () {
    test('writes timestamped entries to the log file', () async {
      final tempDir = await Directory.systemTemp.createTemp('upload_error_logger');
      final logger = UploadErrorLogger(
        directoryBuilder: () async => tempDir,
      );

      await logger.logError('first failure');
      await logger.logError('second failure');

      final logFile = File('${tempDir.path}${Platform.pathSeparator}upload_errors.log');
      expect(await logFile.exists(), isTrue);

      final lines = await logFile.readAsLines();
      expect(lines, hasLength(2));
      expect(lines[0], contains('first failure'));
      expect(lines[1], contains('second failure'));
    });

    test('swallows errors thrown by the directory builder', () async {
      final logger = UploadErrorLogger(
        directoryBuilder: () async {
          throw Exception('Directory unavailable');
        },
      );

      await logger.logError('should not throw');
    });
  });
}
