import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class UploadMetadataStore {
  UploadMetadataStore({SharedPreferences? preferences})
    : _prefsFuture = preferences != null
          ? Future.value(preferences)
          : SharedPreferences.getInstance();

  static const String _storageKey = 'asset_upload_metadata';

  final Future<SharedPreferences> _prefsFuture;
  SharedPreferences? _prefs;
  Map<String, String>? _cache;
  Future<void>? _loadingFuture;

  Future<SharedPreferences> _getPrefs() async {
    final cached = _prefs;
    if (cached != null) {
      return cached;
    }
    final prefs = await _prefsFuture;
    _prefs = prefs;
    return prefs;
  }

  Future<void> _ensureCacheLoaded() async {
    if (_cache != null) {
      return;
    }

    if (_loadingFuture != null) {
      await _loadingFuture;
      return;
    }

    final completer = Completer<void>();
    _loadingFuture = completer.future;

    try {
      final prefs = await _getPrefs();
      final stored = prefs.getString(_storageKey);
      _cache = stored == null || stored.isEmpty
          ? <String, String>{}
          : _decode(stored);
    } finally {
      completer.complete();
      _loadingFuture = null;
    }
  }

  Map<String, String> _getCacheUnsafe() {
    return _cache ??= <String, String>{};
  }

  Future<void> saveContentHash(String assetId, String contentHash) async {
    if (assetId.isEmpty || contentHash.isEmpty) {
      return;
    }

    await _ensureCacheLoaded();
    final prefs = await _getPrefs();
    final metadata = _getCacheUnsafe();
    metadata[assetId] = contentHash;
    await prefs.setString(_storageKey, jsonEncode(metadata));
  }

  Future<String?> getContentHash(String assetId) async {
    if (assetId.isEmpty) {
      return null;
    }

    await _ensureCacheLoaded();
    final metadata = _getCacheUnsafe();
    final hash = metadata[assetId];
    if (hash == null || hash.isEmpty) {
      return null;
    }
    return hash;
  }

  Future<bool> isUploaded(String assetId) async {
    if (assetId.isEmpty) {
      return false;
    }
    await _ensureCacheLoaded();
    final metadata = _getCacheUnsafe();
    final hash = metadata[assetId];
    return hash != null && hash.isNotEmpty;
  }

  Future<List<String>> getUploadedAssetIds() async {
    await _ensureCacheLoaded();
    final metadata = _getCacheUnsafe();
    return List<String>.from(metadata.keys);
  }

  Future<void> remove(String assetId) async {
    if (assetId.isEmpty) {
      return;
    }

    await _ensureCacheLoaded();
    final metadata = _getCacheUnsafe();
    if (!metadata.containsKey(assetId)) {
      return;
    }

    metadata.remove(assetId);
    final prefs = await _getPrefs();
    await prefs.setString(_storageKey, jsonEncode(metadata));
  }

  Future<void> clearAll() async {
    final prefs = await _getPrefs();
    await prefs.remove(_storageKey);
    _cache = <String, String>{};
  }

  Future<Map<String, String>> loadAll() async {
    await _ensureCacheLoaded();
    return Map.unmodifiable(Map<String, String>.from(_getCacheUnsafe()));
  }

  Map<String, String> _decode(String stored) {
    final dynamic decoded = jsonDecode(stored);
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }
    return <String, String>{};
  }
}
