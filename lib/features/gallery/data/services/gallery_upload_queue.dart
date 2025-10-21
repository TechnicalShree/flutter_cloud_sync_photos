import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_cloud_sync_photos/core/network/api_exception.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../auth/data/models/photo_media.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../settings/data/upload_preferences_store.dart';
import 'upload_metadata_store.dart';

enum UploadJobStatus { queued, uploading, completed, failed, skipped, cancelled }

class UploadJob {
  UploadJob({
    required this.asset,
    required this.assetId,
    required this.fileName,
    required this.folder,
    required this.preferences,
  }) : enqueuedAt = DateTime.now();

  final AssetEntity asset;
  final String assetId;
  final String fileName;
  final String folder;
  final UploadPreferences preferences;
  final DateTime enqueuedAt;

  UploadJobStatus status = UploadJobStatus.queued;
  String? error;

  bool get isActive =>
      status == UploadJobStatus.queued || status == UploadJobStatus.uploading;

  bool get isFinished =>
      status == UploadJobStatus.completed ||
      status == UploadJobStatus.failed ||
      status == UploadJobStatus.skipped ||
      status == UploadJobStatus.cancelled;
}

class UploadEnqueueSummary {
  const UploadEnqueueSummary({
    required this.totalRequested,
    required this.enqueued,
    required this.duplicates,
    required this.alreadyUploaded,
  });

  final int totalRequested;
  final int enqueued;
  final int duplicates;
  final int alreadyUploaded;

  bool get hasEnqueued => enqueued > 0;
}

class GalleryUploadQueue extends ChangeNotifier {
  GalleryUploadQueue({
    UploadMetadataStore? metadataStore,
    UploadPreferencesStore? preferencesStore,
    AuthService? authService,
  })  : _metadataStore = metadataStore ?? UploadMetadataStore(),
        _preferencesStore = preferencesStore ?? uploadPreferencesStore,
        _authService = authService ?? globalAuthService;

  final UploadMetadataStore _metadataStore;
  final UploadPreferencesStore _preferencesStore;
  final AuthService _authService;

  final Map<String, UploadJob> _jobs = <String, UploadJob>{};
  final Queue<UploadJob> _queue = Queue<UploadJob>();

  bool _processing = false;

  List<UploadJob> get jobs {
    final items = _jobs.values.toList()
      ..sort(
        (a, b) => b.enqueuedAt.compareTo(a.enqueuedAt),
      );
    return List.unmodifiable(items);
  }

  bool get hasActiveUploads =>
      _jobs.values.any((job) => job.status == UploadJobStatus.uploading) ||
      _queue.isNotEmpty;

  Iterable<String> get activeAssetIds sync* {
    for (final job in _jobs.values) {
      if (job.isActive) {
        yield job.assetId;
      }
    }
  }

  UploadJobStatus? statusFor(String assetId) =>
      _jobs[assetId]?.status;

  Future<UploadEnqueueSummary> enqueueAssets(
    List<AssetEntity> assets, {
    String? fallbackAlbumName,
  }) async {
    if (assets.isEmpty) {
      return const UploadEnqueueSummary(
        totalRequested: 0,
        enqueued: 0,
        duplicates: 0,
        alreadyUploaded: 0,
      );
    }

    final prefs = await _preferencesStore.load();
    int enqueued = 0;
    int duplicates = 0;
    int alreadyUploaded = 0;

    for (final asset in assets) {
      final assetId = asset.id;

      final existing = _jobs[assetId];
      if (existing != null && existing.isActive) {
        duplicates += 1;
        continue;
      }

      final isUploaded = await _metadataStore.isUploaded(assetId);
      if (isUploaded) {
        alreadyUploaded += 1;
        continue;
      }

      final fileName = await _resolveFileName(asset);
      final folder = _resolveFolder(asset, fallbackAlbumName);

      final job = UploadJob(
        asset: asset,
        assetId: assetId,
        fileName: fileName,
        folder: folder,
        preferences: prefs,
      );

      _jobs[assetId] = job;
      _queue.add(job);
      enqueued += 1;
    }

    if (enqueued > 0) {
      unawaited(_processQueue());
    }

    if (enqueued > 0 || duplicates > 0 || alreadyUploaded > 0) {
      notifyListeners();
    }

    return UploadEnqueueSummary(
      totalRequested: assets.length,
      enqueued: enqueued,
      duplicates: duplicates,
      alreadyUploaded: alreadyUploaded,
    );
  }

  void clearFinished() {
    _jobs.removeWhere((_, job) => job.isFinished);
    notifyListeners();
  }

  bool cancelJob(String assetId) {
    final job = _jobs[assetId];
    if (job == null) {
      return false;
    }
    if (job.status != UploadJobStatus.queued) {
      return false;
    }

    _queue.removeWhere((queuedJob) => queuedJob.assetId == assetId);
    job.status = UploadJobStatus.cancelled;
    notifyListeners();
    return true;
  }

  Future<void> _processQueue() async {
    if (_processing) {
      return;
    }
    _processing = true;
    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      if (job.status != UploadJobStatus.queued) {
        continue;
      }

      job.status = UploadJobStatus.uploading;
      notifyListeners();

      try {
        final wasUploaded = await _metadataStore.isUploaded(job.assetId);
        if (wasUploaded) {
          job.status = UploadJobStatus.skipped;
          continue;
        }

        final bytes = await _loadAssetBytes(job.asset);
        final response = await _authService.uploadFile(
          fileName: job.fileName,
          bytes: bytes,
          isPrivate: job.preferences.isPrivate,
          folder: job.folder,
          optimize: job.preferences.optimize,
        );

        final contentHash = _findContentHash(response);
        if (contentHash != null && contentHash.isNotEmpty) {
          await _metadataStore.saveContentHash(job.assetId, contentHash);
        }

        job.status = UploadJobStatus.completed;
      } on ApiException catch (error) {
        job.status = UploadJobStatus.failed;
        job.error = error.message;
      } catch (_) {
        job.status = UploadJobStatus.failed;
        job.error = 'Upload failed';
      } finally {
        notifyListeners();
      }
    }
    _processing = false;
  }

  Future<String> _resolveFileName(AssetEntity asset) async {
    final rawTitle = await asset.titleAsync;
    final trimmed = rawTitle.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return 'photo_${asset.id}.jpg';
  }

  String _resolveFolder(AssetEntity asset, String? fallbackAlbumName) {
    final relativePath = asset.relativePath?.trim();
    if (relativePath != null && relativePath.isNotEmpty) {
      final sanitized = relativePath.replaceAll(RegExp(r'[\\/]+$'), '');
      final segments = sanitized.split(RegExp(r'[\\/]'));
      if (segments.isNotEmpty) {
        final last = segments.last.trim();
        if (last.isNotEmpty) {
          return _authService.buildFolderPath(
            PhotoMedia(bucketDisplayName: last),
          );
        }
      }
      return _authService.buildFolderPath(
        PhotoMedia(bucketDisplayName: sanitized),
      );
    }

    if (fallbackAlbumName != null && fallbackAlbumName.trim().isNotEmpty) {
      return _authService.buildFolderPath(
        PhotoMedia(bucketDisplayName: fallbackAlbumName),
      );
    }

    return _authService.buildFolderPath(
      const PhotoMedia(bucketDisplayName: 'Unsorted'),
    );
  }

  Future<Uint8List> _loadAssetBytes(AssetEntity asset) async {
    Uint8List? bytes = await asset.originBytes;
    bytes ??= await asset.thumbnailDataWithSize(
      const ThumbnailSize.square(1200),
    );

    if (bytes == null) {
      throw ApiException(message: 'Unable to read photo data');
    }

    return bytes;
  }

  String? _findContentHash(Map<String, dynamic> response) {
    for (final entry in response.entries) {
      final dynamic value = entry.value;
      if (entry.key.toLowerCase() == 'content_hash' &&
          value is String &&
          value.isNotEmpty) {
        return value;
      }
      if (value is Map<String, dynamic>) {
        final nested = _findContentHash(value);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      } else if (value is Iterable) {
        for (final element in value) {
          if (element is Map<String, dynamic>) {
            final nested = _findContentHash(element);
            if (nested != null && nested.isNotEmpty) {
              return nested;
            }
          }
        }
      }
    }
    return null;
  }
}

final GalleryUploadQueue galleryUploadQueue = GalleryUploadQueue();
