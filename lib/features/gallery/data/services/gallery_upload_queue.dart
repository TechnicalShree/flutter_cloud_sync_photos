import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cloud_sync_photos/core/network/api_exception.dart';
import 'package:flutter_cloud_sync_photos/core/network/network_service.dart';
import 'package:flutter_cloud_sync_photos/core/system/power_service.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../auth/data/services/auth_service.dart';
import '../../../../core/utils/folder_path_builder.dart';
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
    this.contentHash,
    this.totalBytes,
  }) : enqueuedAt = DateTime.now();

  final AssetEntity asset;
  final String assetId;
  final String fileName;
  final String folder;
  final UploadPreferences preferences;
  final DateTime enqueuedAt;

  String? contentHash;
  int? totalBytes;
  int uploadedBytes = 0;
  String? etag;

  UploadJobStatus status = UploadJobStatus.queued;
  String? error;

  bool get isActive =>
      status == UploadJobStatus.queued || status == UploadJobStatus.uploading;

  bool get isFinished =>
      status == UploadJobStatus.completed ||
      status == UploadJobStatus.failed ||
      status == UploadJobStatus.skipped ||
      status == UploadJobStatus.cancelled;

  double? get progress {
    final total = totalBytes;
    if (total == null || total == 0) {
      return null;
    }
    return (uploadedBytes / total).clamp(0.0, 1.0);
  }
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
    FolderPathResolver? folderPathResolver,
    NetworkService? networkService,
    PowerService? powerService,
  })  : _metadataStore = metadataStore ?? UploadMetadataStore(),
        _preferencesStore = preferencesStore ?? uploadPreferencesStore,
        _authService = authService ?? globalAuthService,
        _folderPathResolver = folderPathResolver ?? defaultFolderPathResolver,
        _networkService = networkService ?? NetworkService(),
        _powerService = powerService ?? PowerService() {
    _networkSubscription =
        _networkService.onConditionsChanged.listen((conditions) {
      _latestNetworkConditions = conditions;
      _handleEnvironmentUpdate();
    });
    _powerSubscription = _powerService.onStatusChanged.listen((status) {
      _latestPowerStatus = status;
      _handleEnvironmentUpdate();
    });
    unawaited(_primeEnvironment());
  }

  final UploadMetadataStore _metadataStore;
  final UploadPreferencesStore _preferencesStore;
  final AuthService _authService;
  final FolderPathResolver _folderPathResolver;
  final NetworkService _networkService;
  final PowerService _powerService;

  final Map<String, UploadJob> _jobs = <String, UploadJob>{};
  final Queue<UploadJob> _queue = Queue<UploadJob>();

  bool _processing = false;
  final Random _random = Random();
  StreamSubscription<NetworkConditions>? _networkSubscription;
  StreamSubscription<PowerStatus>? _powerSubscription;
  Timer? _recheckTimer;
  NetworkConditions? _latestNetworkConditions;
  PowerStatus? _latestPowerStatus;
  UploadPreferences? _lastKnownPreferences;
  String? _blockedReason;

  List<UploadJob> get jobs {
    final items = _jobs.values.toList()
      ..sort(
        (a, b) => b.enqueuedAt.compareTo(a.enqueuedAt),
      );
    return List.unmodifiable(items);
  }

  String? get blockedReason => _blockedReason;

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
    _lastKnownPreferences = prefs;
    await _refreshEnvironmentBlock();
    int enqueued = 0;
    int duplicates = 0;
    int alreadyUploaded = 0;
    final Set<String> encounteredHashes = <String>{};

    for (final asset in assets) {
      final assetId = asset.id;

      final existing = _jobs[assetId];
      if (existing != null && existing.isActive) {
        duplicates += 1;
        continue;
      }

      final metadata = await _metadataStore.metadataFor(assetId);
      if (metadata?.isUploaded == true) {
        alreadyUploaded += 1;
        continue;
      }

      final preparation = await _prepareAssetForUpload(asset, metadata);
      if (preparation == null) {
        continue;
      }

      final hash = preparation.contentHash;
      if (hash != null && hash.isNotEmpty) {
        final uploaded = await _metadataStore.isContentHashUploaded(hash);
        if (uploaded) {
          alreadyUploaded += 1;
          await _metadataStore.markCompleted(
            assetId: assetId,
            contentHash: hash,
          );
          continue;
        }

        if (!encounteredHashes.add(hash)) {
          duplicates += 1;
          continue;
        }
      }

      final fileName = await _resolveFileName(asset);
      final folder = _resolveFolder(asset, fallbackAlbumName);

      final job = UploadJob(
        asset: asset,
        assetId: assetId,
        fileName: fileName,
        folder: folder,
        preferences: prefs,
        contentHash: hash,
        totalBytes: preparation.totalBytes,
      );

      if (metadata != null) {
        job.uploadedBytes = metadata.uploadedBytes;
        job.etag = metadata.etag;
      }

      _jobs[assetId] = job;
      _queue.add(job);
      enqueued += 1;

      await _metadataStore.ensureMetadata(
        assetId,
        totalBytes: preparation.totalBytes,
      );
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

  @override
  void dispose() {
    _networkSubscription?.cancel();
    _powerSubscription?.cancel();
    _recheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _primeEnvironment() async {
    try {
      _latestNetworkConditions = await _networkService.currentConditions();
    } catch (_) {
      _latestNetworkConditions = null;
    }

    try {
      _latestPowerStatus = await _powerService.currentStatus();
    } catch (_) {
      _latestPowerStatus = null;
    }

    try {
      final prefs = await _preferencesStore.load();
      _lastKnownPreferences = prefs;
      final reason = await _environmentBlockReason(prefs);
      _setEnvironmentBlock(reason);
    } catch (_) {
      // Ignore preference load errors during startup.
    }
  }

  Future<void> refreshEnvironmentConstraints() async {
    try {
      final prefs = await _preferencesStore.load();
      _lastKnownPreferences = prefs;
      await _refreshEnvironmentBlock();
    } catch (_) {
      // Ignore refresh errors triggered by preference updates.
    }
  }

  void _handleEnvironmentUpdate() {
    _recheckTimer?.cancel();
    _recheckTimer = null;

    if (_lastKnownPreferences != null) {
      unawaited(_refreshEnvironmentBlock());
    }

    if (_queue.isNotEmpty && !_processing) {
      unawaited(_processQueue());
    }
  }

  Future<void> _refreshEnvironmentBlock() async {
    final prefs = _lastKnownPreferences;
    if (prefs == null) {
      return;
    }
    final reason = await _environmentBlockReason(prefs);
    _setEnvironmentBlock(reason);
  }

  Future<String?> _environmentBlockReason(UploadPreferences prefs) async {
    var network = _latestNetworkConditions;
    if (network == null) {
      network = await _networkService.currentConditions();
      _latestNetworkConditions = network;
    }

    if (!network.hasNetwork) {
      return 'Waiting for a network connection';
    }
    if (!network.isOnline) {
      return 'No internet connection detected';
    }
    if (prefs.wifiOnly && !network.isWifi) {
      return 'Uploads require a Wi-Fi connection';
    }
    if (prefs.blockOnRoaming && network.isMobile) {
      final roaming = network.isRoaming;
      if (roaming == true) {
        return 'Uploads paused while roaming';
      }
    }

    var power = _latestPowerStatus;
    if (power == null) {
      power = await _powerService.currentStatus();
      _latestPowerStatus = power;
    }

    if (prefs.whileCharging && !power.isCharging) {
      return 'Waiting until the device is charging';
    }

    final level = power.level;
    if (prefs.batteryThreshold > 0 && !power.isCharging) {
      if (level != null && level < prefs.batteryThreshold) {
        return 'Battery must be at least ${prefs.batteryThreshold}% to upload';
      }
    }

    return null;
  }

  void _scheduleRecheck() {
    _recheckTimer?.cancel();
    _recheckTimer = Timer(const Duration(seconds: 20), () {
      _recheckTimer = null;
      if (_queue.isNotEmpty && !_processing) {
        unawaited(_processQueue());
      }
    });
  }

  void _setEnvironmentBlock(String? reason) {
    if (_blockedReason == reason) {
      return;
    }
    _blockedReason = reason;
    notifyListeners();
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

      _lastKnownPreferences = job.preferences;
      final blockReason = await _environmentBlockReason(job.preferences);
      if (blockReason != null) {
        _queue.addFirst(job);
        _setEnvironmentBlock(blockReason);
        _scheduleRecheck();
        _processing = false;
        return;
      }

      _setEnvironmentBlock(null);
      _recheckTimer?.cancel();
      _recheckTimer = null;

      job.status = UploadJobStatus.uploading;
      notifyListeners();

      try {
        final resultStatus = await _performUpload(job);
        job.status = resultStatus;
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
    if (_queue.isEmpty) {
      _setEnvironmentBlock(null);
      _recheckTimer?.cancel();
      _recheckTimer = null;
    }
  }

  Future<UploadJobStatus> _performUpload(UploadJob job) async {
    final metadata = await _metadataStore.metadataFor(job.assetId);
    final file = await _resolveAssetFile(job.asset);

    final int totalBytes = job.totalBytes ?? await file.length();
    job.totalBytes = totalBytes;

    final String? contentHash =
        await _ensureContentHash(job, existingFile: file, metadata: metadata);

    if (metadata?.isUploaded == true &&
        metadata!.contentHash != null &&
        metadata.contentHash!.isNotEmpty &&
        contentHash != null &&
        metadata.contentHash == contentHash) {
      job.error = 'Already in cloud';
      await _metadataStore.markCompleted(
        assetId: job.assetId,
        contentHash: metadata.contentHash!,
        etag: metadata.etag,
      );
      return UploadJobStatus.skipped;
    }

    final resumablePlan = await _startResumablePlan(
      job,
      metadata: metadata,
      totalBytes: totalBytes,
      contentHash: contentHash,
    );

    if (resumablePlan != null) {
      await _uploadWithResumable(
        job,
        file,
        resumablePlan,
        totalBytes,
        contentHash,
      );
      return UploadJobStatus.completed;
    }

    await _uploadWithSingleRequest(
      job,
      file,
      totalBytes,
      contentHash,
    );
    return UploadJobStatus.completed;
  }

  Future<_AssetPreparation?> _prepareAssetForUpload(
    AssetEntity asset,
    UploadMetadata? metadata,
  ) async {
    try {
      final file = await _resolveAssetFile(asset);
      final totalBytes = await file.length();
      String? hash = metadata?.contentHash;
      if (hash == null || hash.isEmpty) {
        hash = await _computeFileHash(file);
      }
      return _AssetPreparation(
        totalBytes: totalBytes,
        contentHash: hash,
      );
    } catch (_) {
      return null;
    }
  }

  Future<File> _resolveAssetFile(AssetEntity asset) async {
    File? file;
    try {
      file = await asset.originFile;
    } catch (_) {
      // Ignore origin lookup errors and fall back to the cached file path.
    }
    file ??= await asset.file;
    if (file == null || !(await file.exists())) {
      throw ApiException(message: 'Unable to read photo data');
    }
    return file;
  }

  Future<String?> _ensureContentHash(
    UploadJob job, {
    File? existingFile,
    UploadMetadata? metadata,
  }) async {
    final current = job.contentHash;
    if (current != null && current.isNotEmpty) {
      return current;
    }

    final stored = metadata?.contentHash;
    if (stored != null && stored.isNotEmpty) {
      job.contentHash = stored;
      return stored;
    }

    final file = existingFile ?? await _resolveAssetFile(job.asset);
    final hash = await _computeFileHash(file);
    job.contentHash = hash;
    return hash;
  }

  Future<_ResumablePlan?> _startResumablePlan(
    UploadJob job, {
    required UploadMetadata? metadata,
    required int totalBytes,
    required String? contentHash,
  }) async {
    try {
      final session = await _authService.startResumableUpload(
        fileName: job.fileName,
        isPrivate: job.preferences.isPrivate,
        folder: job.folder,
        optimize: job.preferences.optimize,
        totalBytes: totalBytes,
        contentHash: contentHash,
        resumeSessionId: metadata?.sessionId,
        resumeOffset: metadata?.uploadedBytes,
      );

      if (session == null) {
        return null;
      }

      final resumeOffset = metadata?.uploadedBytes ?? 0;
      if (resumeOffset > 0) {
        job.uploadedBytes = resumeOffset;
      }

      await _metadataStore.saveProgress(
        assetId: job.assetId,
        uploadedBytes: resumeOffset,
        totalBytes: totalBytes,
        sessionId: session.sessionId,
      );

      return _ResumablePlan(session: session, resumeOffset: resumeOffset);
    } on ApiException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 400) {
        return null;
      }
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<void> _uploadWithResumable(
    UploadJob job,
    File file,
    _ResumablePlan plan,
    int totalBytes,
    String? contentHash,
  ) async {
    final session = plan.session;
    final chunkSize = session.effectiveChunkSize;
    final raf = await file.open();
    try {
      if (plan.resumeOffset > 0) {
        await raf.setPosition(plan.resumeOffset);
      }

      var offset = plan.resumeOffset;
      while (offset < totalBytes) {
        final remaining = totalBytes - offset;
        final readSize = min(chunkSize, remaining);
        final chunk = await raf.read(readSize);
        if (chunk.isEmpty) {
          throw ApiException(message: 'Unexpected end of file while reading');
        }

        final ack = await _retryWithBackoff(
          () => _authService.uploadChunk(
            session: session,
            bytes: chunk,
            start: offset,
            total: totalBytes,
            isLast: offset + chunk.length >= totalBytes,
            contentHash: contentHash,
          ),
        );

        offset = ack.confirmedBytes;
        job.uploadedBytes = offset;
        job.totalBytes = totalBytes;

        if (ack.contentHash != null && ack.contentHash!.isNotEmpty) {
          job.contentHash = ack.contentHash;
        }
        if (ack.etag != null && ack.etag!.isNotEmpty) {
          job.etag = ack.etag;
        }

        await _metadataStore.saveProgress(
          assetId: job.assetId,
          uploadedBytes: offset,
          totalBytes: totalBytes,
          sessionId: session.sessionId,
        );

        notifyListeners();
      }
    } finally {
      await raf.close();
    }

    final completion = await _authService.completeResumableUpload(
      sessionId: session.sessionId,
      contentHash: job.contentHash ?? contentHash,
    );

    final finalHash =
        completion.contentHash ?? job.contentHash ?? contentHash ?? '';
    final finalEtag = completion.etag ?? job.etag;

    if (finalHash.isNotEmpty) {
      await _metadataStore.markCompleted(
        assetId: job.assetId,
        contentHash: finalHash,
        etag: finalEtag,
      );
      job.contentHash = finalHash;
      job.etag = finalEtag;
    } else {
      await _metadataStore.clearProgress(job.assetId);
    }

    job.uploadedBytes = totalBytes;
  }

  Future<void> _uploadWithSingleRequest(
    UploadJob job,
    File file,
    int totalBytes,
    String? contentHash,
  ) async {
    final bytes = await file.readAsBytes();
    final response = await _authService.uploadFile(
      fileName: job.fileName,
      bytes: bytes,
      isPrivate: job.preferences.isPrivate,
      folder: job.folder,
      optimize: job.preferences.optimize,
      contentHash: contentHash,
    );

    final returnedHash = _findContentHash(response) ?? contentHash;
    final etag = _findEtag(response);

    if (returnedHash != null && returnedHash.isNotEmpty) {
      await _metadataStore.markCompleted(
        assetId: job.assetId,
        contentHash: returnedHash,
        etag: etag,
      );
      job.contentHash = returnedHash;
    } else {
      await _metadataStore.ensureMetadata(
        job.assetId,
        totalBytes: totalBytes,
      );
    }

    if (etag != null && etag.isNotEmpty) {
      job.etag = etag;
    }

    job.uploadedBytes = totalBytes;
  }

  Future<T> _retryWithBackoff<T>(Future<T> Function() action) async {
    const int maxAttempts = 5;
    var attempt = 0;
    var delay = const Duration(milliseconds: 400);

    while (true) {
      attempt += 1;
      try {
        return await action();
      } on ApiException catch (error) {
        if (attempt >= maxAttempts || !_shouldRetry(error.statusCode)) {
          rethrow;
        }
        final jitter = Duration(milliseconds: _random.nextInt(250));
        await Future<void>.delayed(delay + jitter);
        delay *= 2;
      }
    }
  }

  bool _shouldRetry(int? statusCode) {
    if (statusCode == null) {
      return false;
    }
    if (statusCode == 429) {
      return true;
    }
    return statusCode >= 500 && statusCode < 600;
  }

  Future<String?> _computeFileHash(File file) async {
    try {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString();
    } catch (_) {
      return null;
    }
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
          return _folderPathResolver(last);
        }
      }
      return _folderPathResolver(sanitized);
    }

    if (fallbackAlbumName != null && fallbackAlbumName.trim().isNotEmpty) {
      return _folderPathResolver(fallbackAlbumName);
    }

    return _folderPathResolver(null);
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

  String? _findEtag(Map<String, dynamic> response) {
    for (final entry in response.entries) {
      final dynamic value = entry.value;
      if (entry.key.toLowerCase() == 'etag' && value is String) {
        return value;
      }
      if (value is Map<String, dynamic>) {
        final nested = _findEtag(value);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
    }
    return null;
  }
}

final GalleryUploadQueue galleryUploadQueue = GalleryUploadQueue();

class _AssetPreparation {
  const _AssetPreparation({required this.totalBytes, this.contentHash});

  final int totalBytes;
  final String? contentHash;
}

class _ResumablePlan {
  const _ResumablePlan({required this.session, required this.resumeOffset});

  final ResumableUploadSession session;
  final int resumeOffset;
}
