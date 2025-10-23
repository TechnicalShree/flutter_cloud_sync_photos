import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThumbnailDiskCache {
  ThumbnailDiskCache({
    SharedPreferences? preferences,
    Future<Directory> Function()? directoryBuilder,
  })  : _prefsFuture =
            preferences != null ? Future.value(preferences) : SharedPreferences.getInstance(),
        _directoryFuture = _createDirectory(
          directoryBuilder ?? _defaultDirectoryBuilder,
        );

  static const String _indexStorageKey = 'cached_thumbnails_index';
  static const String _cacheFolderName = 'thumbnail_cache';

  final Future<SharedPreferences> _prefsFuture;
  final Future<Directory> _directoryFuture;

  Map<String, String>? _indexCache;
  Future<void>? _loadingIndex;
  final Map<String, Future<Uint8List>> _pendingLoads = <String, Future<Uint8List>>{};

  static Future<Directory> _createDirectory(
    Future<Directory> Function() builder,
  ) async {
    final directory = await builder();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<Directory> _defaultDirectoryBuilder() async {
    final baseDir = await getApplicationSupportDirectory();
    return Directory(p.join(baseDir.path, _cacheFolderName));
  }

  Future<Directory> get _directory async {
    return _directoryFuture;
  }

  Future<void> _ensureIndexLoaded() async {
    if (_indexCache != null) {
      return;
    }

    if (_loadingIndex != null) {
      await _loadingIndex;
      return;
    }

    final completer = Completer<void>();
    _loadingIndex = completer.future;

    try {
      final prefs = await _prefsFuture;
      final stored = prefs.getString(_indexStorageKey);
      if (stored == null || stored.isEmpty) {
        _indexCache = <String, String>{};
      } else {
        _indexCache = _decodeIndex(stored);
      }
    } finally {
      completer.complete();
      _loadingIndex = null;
    }
  }

  Map<String, String> _getIndexUnsafe() {
    return _indexCache ??= <String, String>{};
  }

  Map<String, String> _decodeIndex(String stored) {
    final dynamic decoded = jsonDecode(stored);
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }
    return <String, String>{};
  }

  Future<void> _persistIndex(Map<String, String> index) async {
    final prefs = await _prefsFuture;
    if (index.isEmpty) {
      await prefs.remove(_indexStorageKey);
    } else {
      await prefs.setString(_indexStorageKey, jsonEncode(index));
    }
  }

  Future<Uint8List> loadThumbnailBytes(
    AssetEntity asset,
    ThumbnailSize size, {
    int? expectedRevision,
  }) {
    final revision = expectedRevision ?? _revisionFor(asset);
    final pendingKey = _pendingKey(asset, size, revision);
    final existing = _pendingLoads[pendingKey];
    if (existing != null) {
      return existing;
    }

    final future = _loadThumbnailBytesInternal(asset, size, revision);
    _pendingLoads[pendingKey] = future;
    return future.whenComplete(() {
      _pendingLoads.remove(pendingKey);
    });
  }

  Future<Uint8List> _loadThumbnailBytesInternal(
    AssetEntity asset,
    ThumbnailSize size,
    int revision,
  ) async {
    final file = await _getValidCachedFile(asset, size, revision);
    if (file != null) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          return bytes;
        }
      } catch (_) {
        // Fall through to regenerate the thumbnail if reading fails.
      }
      await _evictFile(file, asset, size);
    }

    final bytes = await _generateThumbnailBytes(asset, size);
    if (bytes.isEmpty) {
      throw StateError('Failed to load thumbnail bytes for asset ${asset.id}');
    }

    await _storeThumbnail(asset, size, revision, bytes);
    return bytes;
  }

  Future<File?> _getValidCachedFile(
    AssetEntity asset,
    ThumbnailSize size,
    int revision,
  ) async {
    await _ensureIndexLoaded();
    final index = _getIndexUnsafe();
    final key = _indexKey(asset, size);
    final fileName = index[key];
    if (fileName == null || fileName.isEmpty) {
      return null;
    }

    final storedRevision = _extractRevision(fileName);
    if (storedRevision != revision) {
      await _evictIndexEntry(key, fileName);
      return null;
    }

    final directory = await _directory;
    final file = File(p.join(directory.path, fileName));
    if (!await file.exists()) {
      await _evictIndexEntry(key, fileName);
      return null;
    }
    return file;
  }

  Future<void> _storeThumbnail(
    AssetEntity asset,
    ThumbnailSize size,
    int revision,
    Uint8List bytes,
  ) async {
    await _ensureIndexLoaded();
    final directory = await _directory;
    final index = _getIndexUnsafe();
    final key = _indexKey(asset, size);
    final fileName = _buildFileName(asset, size, revision);
    final file = File(p.join(directory.path, fileName));

    final previous = index[key];
    if (previous != null && previous != fileName) {
      final previousFile = File(p.join(directory.path, previous));
      if (await previousFile.exists()) {
        await previousFile.delete();
      }
    }

    await file.writeAsBytes(bytes, flush: true);
    index[key] = fileName;
    await _persistIndex(index);
  }

  Future<void> _evictIndexEntry(String key, String fileName) async {
    await _ensureIndexLoaded();
    final index = _getIndexUnsafe();
    final removed = index.remove(key);
    if (removed != null) {
      await _persistIndex(index);
    }

    final directory = await _directory;
    final file = File(p.join(directory.path, fileName));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _evictFile(File file, AssetEntity asset, ThumbnailSize size) async {
    await _ensureIndexLoaded();
    final index = _getIndexUnsafe();
    final key = _indexKey(asset, size);
    final stored = index[key];
    if (stored != null) {
      final fileName = p.basename(file.path);
      if (stored == fileName) {
        index.remove(key);
        await _persistIndex(index);
      }
    }
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Uint8List> _generateThumbnailBytes(AssetEntity asset, ThumbnailSize size) async {
    Uint8List? bytes;
    try {
      bytes = await asset.thumbnailDataWithOption(_thumbnailOption(size));
    } catch (_) {
      // Ignore and try alternative methods.
    }

    bytes ??= await asset.thumbnailDataWithSize(size);
    bytes ??= await asset.thumbnailData;
    if (bytes == null && asset.type == AssetType.image) {
      bytes = await asset.originBytes;
    }
    return bytes ?? Uint8List(0);
  }

  ThumbnailOption _thumbnailOption(ThumbnailSize size) {
    if (Platform.isIOS || Platform.isMacOS) {
      return ThumbnailOption.ios(
        size: size,
        format: ThumbnailFormat.jpeg,
      );
    }
    return ThumbnailOption(
      size: size,
      format: ThumbnailFormat.jpeg,
    );
  }

  String _indexKey(AssetEntity asset, ThumbnailSize size) {
    return '${asset.id}|${size.width}|${size.height}';
  }

  String _pendingKey(AssetEntity asset, ThumbnailSize size, int revision) {
    return '${_indexKey(asset, size)}|$revision';
  }

  int _revisionFor(AssetEntity asset) {
    return asset.modifiedDateTime.millisecondsSinceEpoch;
  }

  String _buildFileName(AssetEntity asset, ThumbnailSize size, int revision) {
    final sanitizedId = _sanitize(asset.id);
    return '${sanitizedId}_${size.width}x${size.height}_$revision.jpg';
  }

  int? _extractRevision(String fileName) {
    final match = RegExp(r'_(\d+)\.[^.]+$').firstMatch(fileName);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  String _sanitize(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  Future<void> clear() async {
    await _ensureIndexLoaded();
    final index = _getIndexUnsafe();
    final directory = await _directory;

    for (final fileName in index.values) {
      final file = File(p.join(directory.path, fileName));
      if (await file.exists()) {
        await file.delete();
      }
    }

    index.clear();
    await _persistIndex(index);
  }
}

final ThumbnailDiskCache thumbnailDiskCache = ThumbnailDiskCache();
