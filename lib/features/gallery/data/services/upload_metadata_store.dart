import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class UploadMetadata {
  UploadMetadata({
    required this.assetId,
    this.contentHash,
    this.sessionId,
    this.uploadedBytes = 0,
    this.totalBytes = 0,
    this.etag,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory UploadMetadata.fromJson(String assetId, dynamic json) {
    if (json is String) {
      return UploadMetadata(assetId: assetId, contentHash: json);
    }

    if (json is Map) {
      final uploaded = json['uploaded_bytes'];
      final total = json['total_bytes'];
      final updatedAtRaw = json['updated_at'];

      return UploadMetadata(
        assetId: assetId,
        contentHash: json['content_hash']?.toString(),
        sessionId: json['session_id']?.toString(),
        uploadedBytes: uploaded is int
            ? uploaded
            : int.tryParse(uploaded?.toString() ?? '') ?? 0,
        totalBytes:
            total is int ? total : int.tryParse(total?.toString() ?? '') ?? 0,
        etag: json['etag']?.toString(),
        updatedAt: updatedAtRaw is String
            ? DateTime.tryParse(updatedAtRaw)
            : updatedAtRaw is int
                ? DateTime.fromMillisecondsSinceEpoch(updatedAtRaw)
                : null,
      );
    }

    return UploadMetadata(assetId: assetId);
  }

  final String assetId;
  final String? contentHash;
  final String? sessionId;
  final int uploadedBytes;
  final int totalBytes;
  final String? etag;
  final DateTime updatedAt;

  bool get isUploaded => contentHash != null && contentHash!.isNotEmpty;

  UploadMetadata copyWith({
    String? contentHash,
    String? sessionId,
    int? uploadedBytes,
    int? totalBytes,
    String? etag,
    DateTime? updatedAt,
  }) {
    return UploadMetadata(
      assetId: assetId,
      contentHash: contentHash ?? this.contentHash,
      sessionId: sessionId ?? this.sessionId,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      etag: etag ?? this.etag,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (contentHash != null && contentHash!.isNotEmpty)
        'content_hash': contentHash,
      if (sessionId != null && sessionId!.isNotEmpty)
        'session_id': sessionId,
      if (uploadedBytes > 0) 'uploaded_bytes': uploadedBytes,
      if (totalBytes > 0) 'total_bytes': totalBytes,
      if (etag != null && etag!.isNotEmpty) 'etag': etag,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class UploadMetadataStore {
  UploadMetadataStore({SharedPreferences? preferences})
    : _prefsFuture = preferences != null
          ? Future.value(preferences)
          : SharedPreferences.getInstance();

  static const String _storageKey = 'asset_upload_metadata';

  final Future<SharedPreferences> _prefsFuture;

  Future<void> saveContentHash(String assetId, String contentHash) {
    return markCompleted(assetId: assetId, contentHash: contentHash);
  }

  Future<void> markCompleted({
    required String assetId,
    required String contentHash,
    String? etag,
  }) async {
    if (assetId.isEmpty || contentHash.isEmpty) {
      return;
    }

    final prefs = await _prefsFuture;
    final metadata = await _loadAll(prefs);
    final existing = metadata[assetId];
    metadata[assetId] = (existing ?? UploadMetadata(assetId: assetId)).copyWith(
      contentHash: contentHash,
      etag: etag ?? existing?.etag,
      uploadedBytes: existing?.totalBytes ?? existing?.uploadedBytes ?? 0,
      totalBytes: existing?.totalBytes ?? existing?.uploadedBytes ?? 0,
      sessionId: null,
      updatedAt: DateTime.now(),
    );
    await _persistAll(prefs, metadata);
  }

  Future<UploadMetadata?> metadataFor(String assetId) async {
    if (assetId.isEmpty) {
      return null;
    }
    final prefs = await _prefsFuture;
    final metadata = await _loadAll(prefs);
    return metadata[assetId];
  }

  Future<void> saveProgress({
    required String assetId,
    required int uploadedBytes,
    required int totalBytes,
    String? sessionId,
  }) async {
    if (assetId.isEmpty) {
      return;
    }
    final prefs = await _prefsFuture;
    final metadata = await _loadAll(prefs);
    final existing = metadata[assetId] ?? UploadMetadata(assetId: assetId);
    final safeUploaded = uploadedBytes < 0
        ? 0
        : (uploadedBytes > totalBytes ? totalBytes : uploadedBytes);
    metadata[assetId] = existing.copyWith(
      uploadedBytes: safeUploaded,
      totalBytes: totalBytes,
      sessionId: sessionId ?? existing.sessionId,
      updatedAt: DateTime.now(),
    );
    await _persistAll(prefs, metadata);
  }

  Future<void> ensureMetadata(String assetId, {int? totalBytes}) async {
    if (assetId.isEmpty) {
      return;
    }
    final prefs = await _prefsFuture;
    final metadata = await _loadAll(prefs);
    final existing = metadata[assetId] ?? UploadMetadata(assetId: assetId);
    metadata[assetId] = existing.copyWith(
      totalBytes: totalBytes ?? existing.totalBytes,
      updatedAt: DateTime.now(),
    );
    await _persistAll(prefs, metadata);
  }

  Future<void> clearProgress(String assetId) async {
    if (assetId.isEmpty) {
      return;
    }
    final prefs = await _prefsFuture;
    final metadata = await _loadAll(prefs);
    final existing = metadata[assetId];
    if (existing == null) {
      return;
    }
    metadata[assetId] = existing.copyWith(
      sessionId: null,
      uploadedBytes: 0,
      updatedAt: DateTime.now(),
    );
    await _persistAll(prefs, metadata);
  }

  Future<String?> getContentHash(String assetId) async {
    final metadata = await metadataFor(assetId);
    return metadata?.contentHash;
  }

  Future<bool> isUploaded(String assetId) async {
    final metadata = await metadataFor(assetId);
    return metadata?.isUploaded ?? false;
  }

  Future<bool> isContentHashUploaded(String contentHash) async {
    if (contentHash.isEmpty) {
      return false;
    }
    final prefs = await _prefsFuture;
    final metadata = await _loadAll(prefs);
    for (final entry in metadata.values) {
      if (entry.contentHash == contentHash && entry.contentHash!.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Future<void> remove(String assetId) async {
    if (assetId.isEmpty) {
      return;
    }
    final prefs = await _prefsFuture;
    final metadata = await _loadAll(prefs);
    if (!metadata.containsKey(assetId)) {
      return;
    }
    metadata.remove(assetId);
    await _persistAll(prefs, metadata);
  }

  Future<void> clearAll() async {
    final prefs = await _prefsFuture;
    await prefs.remove(_storageKey);
  }

  Future<Map<String, UploadMetadata>> _loadAll(
    SharedPreferences prefs,
  ) async {
    final stored = prefs.getString(_storageKey);
    if (stored == null || stored.isEmpty) {
      return <String, UploadMetadata>{};
    }

    final dynamic decoded = jsonDecode(stored);
    if (decoded is! Map) {
      return <String, UploadMetadata>{};
    }

    final Map<String, UploadMetadata> metadata = <String, UploadMetadata>{};
    decoded.forEach((key, value) {
      if (key != null) {
        final assetId = key.toString();
        metadata[assetId] = UploadMetadata.fromJson(assetId, value);
      }
    });
    return metadata;
  }

  Future<void> _persistAll(
    SharedPreferences prefs,
    Map<String, UploadMetadata> metadata,
  ) async {
    if (metadata.isEmpty) {
      await prefs.remove(_storageKey);
      return;
    }
    final encoded = metadata.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    await prefs.setString(_storageKey, jsonEncode(encoded));
  }
}
