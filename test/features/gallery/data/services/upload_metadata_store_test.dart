import 'package:test/test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_cloud_sync_photos/features/gallery/data/services/upload_metadata_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object?>{});
  });

  test('markCompleted stores hash and reports uploaded', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = UploadMetadataStore(preferences: prefs);

    await store.markCompleted(assetId: 'asset-1', contentHash: 'abc123', etag: 'etag-1');

    expect(await store.isUploaded('asset-1'), isTrue);
    expect(await store.getContentHash('asset-1'), equals('abc123'));

    final metadata = await store.metadataFor('asset-1');
    expect(metadata?.etag, equals('etag-1'));
    expect(metadata?.sessionId, isNull);
  });

  test('saveProgress persists session state', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = UploadMetadataStore(preferences: prefs);

    await store.saveProgress(
      assetId: 'asset-2',
      uploadedBytes: 1024,
      totalBytes: 4096,
      sessionId: 'session-1',
    );

    var metadata = await store.metadataFor('asset-2');
    expect(metadata?.uploadedBytes, equals(1024));
    expect(metadata?.totalBytes, equals(4096));
    expect(metadata?.sessionId, equals('session-1'));

    await store.saveProgress(
      assetId: 'asset-2',
      uploadedBytes: 4096,
      totalBytes: 4096,
      sessionId: 'session-1',
    );

    metadata = await store.metadataFor('asset-2');
    expect(metadata?.uploadedBytes, equals(4096));
    expect(metadata?.totalBytes, equals(4096));

    await store.clearProgress('asset-2');
    metadata = await store.metadataFor('asset-2');
    expect(metadata?.sessionId, isNull);
    expect(metadata?.uploadedBytes, equals(0));
  });

  test('isContentHashUploaded returns true when any asset matches hash', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = UploadMetadataStore(preferences: prefs);

    await store.markCompleted(assetId: 'asset-3', contentHash: 'duplicate-hash');

    expect(await store.isContentHashUploaded('duplicate-hash'), isTrue);

    await store.markCompleted(assetId: 'asset-4', contentHash: 'duplicate-hash');

    final metadata = await store.metadataFor('asset-4');
    expect(metadata?.contentHash, equals('duplicate-hash'));
  });
}
