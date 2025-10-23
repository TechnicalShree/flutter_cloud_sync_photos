import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../data/services/thumbnail_disk_cache.dart';

class CachedThumbnailImageProvider
    extends ImageProvider<CachedThumbnailImageProvider> {
  CachedThumbnailImageProvider(
    this.asset, {
    required this.size,
    ThumbnailDiskCache? cache,
  })  : cache = cache ?? thumbnailDiskCache,
        revision = asset.modifiedDateTime.millisecondsSinceEpoch;

  final AssetEntity asset;
  final ThumbnailSize size;
  final ThumbnailDiskCache cache;
  final int revision;

  @override
  Future<CachedThumbnailImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<CachedThumbnailImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    CachedThumbnailImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_loadAsync(key, decode));
  }

  Future<ImageInfo> _loadAsync(
    CachedThumbnailImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    assert(key == this);
    try {
      final bytes = await cache.loadThumbnailBytes(
        key.asset,
        key.size,
        expectedRevision: key.revision,
      );
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final codec = await decode(buffer);
      final frame = await codec.getNextFrame();
      try {
        return ImageInfo(image: frame.image, scale: 1.0);
      } finally {
        codec.dispose();
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        FlutterError.presentError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'cached_thumbnail_image_provider',
          ),
        );
      }
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is CachedThumbnailImageProvider &&
        other.asset.id == asset.id &&
        other.size.width == size.width &&
        other.size.height == size.height &&
        other.revision == revision;
  }

  @override
  int get hashCode => Object.hash(
        asset.id,
        size.width,
        size.height,
        revision,
      );

  @override
  String toString() {
    return 'CachedThumbnailImageProvider(${asset.id}, '
        '${size.width}x${size.height}, rev: $revision)';
  }
}
