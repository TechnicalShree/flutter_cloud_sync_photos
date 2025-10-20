import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class UploadMetadataStore {
  UploadMetadataStore({SharedPreferences? preferences})
    : _prefsFuture = preferences != null
          ? Future.value(preferences)
          : SharedPreferences.getInstance();

  static const String _storageKey = 'asset_upload_metadata';

  final Future<SharedPreferences> _prefsFuture;

  Future<void> saveContentHash(String assetId, String contentHash) async {
    if (assetId.isEmpty || contentHash.isEmpty) {
      return;
    }

    final prefs = await _prefsFuture;
    final stored = prefs.getString(_storageKey);
    final metadata = stored == null || stored.isEmpty
        ? <String, String>{}
        : _decode(stored);
    metadata[assetId] = contentHash;
    await prefs.setString(_storageKey, jsonEncode(metadata));
  }

  Future<String?> getContentHash(String assetId) async {
    if (assetId.isEmpty) {
      return null;
    }

    final prefs = await _prefsFuture;
    final stored = prefs.getString(_storageKey);
    if (stored == null || stored.isEmpty) {
      return null;
    }

    final metadata = _decode(stored);
    final hash = metadata[assetId];
    if (hash == null || hash.isEmpty) {
      return null;
    }
    return hash;
  }

  Future<bool> isUploaded(String assetId) async {
    final hash = await getContentHash(assetId);
    return hash != null && hash.isNotEmpty;
  }

  Future<void> remove(String assetId) async {
    if (assetId.isEmpty) {
      return;
    }

    final prefs = await _prefsFuture;
    final stored = prefs.getString(_storageKey);
    if (stored == null || stored.isEmpty) {
      return;
    }

    final metadata = _decode(stored);
    if (!metadata.containsKey(assetId)) {
      return;
    }

    metadata.remove(assetId);
    await prefs.setString(_storageKey, jsonEncode(metadata));
  }

  Future<void> clearAll() async {
    final prefs = await _prefsFuture;
    await prefs.remove(_storageKey);
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
