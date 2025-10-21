import 'package:flutter_cloud_sync_photos/core/utils/folder_path_builder.dart';
import 'package:test/test.dart';

void main() {
  group('defaultFolderPathResolver', () {
    test('returns Unsorted for null input', () {
      expect(defaultFolderPathResolver(null), equals('Unsorted'));
    });

    test('trims whitespace-only values to Unsorted', () {
      expect(defaultFolderPathResolver('   '), equals('Unsorted'));
    });

    test('replaces forward slashes with underscores', () {
      expect(defaultFolderPathResolver('DCIM/Camera'), equals('DCIM_Camera'));
    });

    test('replaces backward slashes with underscores', () {
      expect(defaultFolderPathResolver(r'Screenshots\2024'),
          equals('Screenshots_2024'));
    });

    test('preserves valid names', () {
      expect(defaultFolderPathResolver('Family Trip'), equals('Family Trip'));
    });
  });
}
