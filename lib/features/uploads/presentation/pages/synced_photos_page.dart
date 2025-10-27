import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../gallery/data/services/gallery_upload_queue.dart';
import '../../../gallery/presentation/pages/photo_detail_page.dart';
import '../../../gallery/presentation/util/cached_thumbnail_image_provider.dart';
import '../../../settings/data/settings_actions.dart';

class SyncedPhotosPage extends StatefulWidget {
  const SyncedPhotosPage({super.key});

  @override
  State<SyncedPhotosPage> createState() => _SyncedPhotosPageState();
}

class _SyncedPhotosPageState extends State<SyncedPhotosPage> {
  final SettingsActions _actions = settingsActions;
  final GalleryUploadQueue _uploadQueue = galleryUploadQueue;

  List<_SyncedPhotoEntry> _syncedPhotos = const [];
  List<_SyncedPhotoEntry> _missingSyncedPhotos = const [];
  bool _loadingSyncedPhotos = true;
  bool _resettingMetadata = false;
  VoidCallback? _uploadQueueListener;
  int _completedJobCount = 0;
  int _recordedPhotoCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSyncedPhotos(showSpinner: true);
    _completedJobCount =
        _uploadQueue.jobs.where((job) => job.status == UploadJobStatus.completed).length;
    _uploadQueueListener = _handleUploadQueueUpdate;
    _uploadQueue.addListener(_uploadQueueListener!);
  }

  void _handleUploadQueueUpdate() {
    final jobs = _uploadQueue.jobs;
    final completedCount =
        jobs.where((job) => job.status == UploadJobStatus.completed).length;
    if (completedCount == _completedJobCount) {
      return;
    }
    _completedJobCount = completedCount;
    _loadSyncedPhotos();
  }

  Future<void> _loadSyncedPhotos({bool showSpinner = false}) async {
    if (!mounted) {
      return;
    }
    if (showSpinner) {
      setState(() {
        _loadingSyncedPhotos = true;
      });
    }

    final records = await _actions.loadSyncedPhotos();
    if (!mounted) {
      return;
    }

    final entries = records.entries
        .map(
          (entry) => _SyncedPhotoEntry(
            assetId: entry.key,
            contentHash: entry.value,
          ),
        )
        .where((entry) => entry.assetId.isNotEmpty && entry.contentHash.isNotEmpty)
        .toList()
      ..sort((a, b) => a.assetId.compareTo(b.assetId));

    final resolvedEntries = await Future.wait(
      entries.map((entry) async {
        try {
          final asset = await AssetEntity.fromId(entry.assetId);
          return entry.copyWith(asset: asset);
        } catch (_) {
          return entry;
        }
      }),
    );

    if (!mounted) {
      return;
    }

    final available = <_SyncedPhotoEntry>[];
    final missing = <_SyncedPhotoEntry>[];
    for (final entry in resolvedEntries) {
      if (entry.asset != null) {
        available.add(entry);
      } else {
        missing.add(entry);
      }
    }

    available.sort((a, b) {
      final aDate = a.asset?.createDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.asset?.createDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    setState(() {
      _recordedPhotoCount = entries.length;
      _syncedPhotos = available;
      _missingSyncedPhotos = missing;
      _loadingSyncedPhotos = false;
    });
  }

  Future<void> _handleResetMetadata() async {
    if (_resettingMetadata) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Reset upload metadata?'),
          content: const Text(
            'This clears the list of photos marked as synced. You can re-upload any photo afterwards.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _resettingMetadata = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Clearing synced photo records...')),
    );

    try {
      await _actions.resetUploadMetadata();
      if (!mounted) {
        return;
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Upload metadata cleared')),
      );
      await _loadSyncedPhotos(showSpinner: true);
    } finally {
      if (mounted) {
        setState(() {
          _resettingMetadata = false;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_uploadQueueListener != null) {
      _uploadQueue.removeListener(_uploadQueueListener!);
      _uploadQueueListener = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synced Photos'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: IconButton(
              tooltip: 'Reset upload metadata',
              onPressed: _resettingMetadata ? null : _handleResetMetadata,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: _resettingMetadata
                    ? const SizedBox(
                        key: ValueKey('reset-progress'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restart_alt, key: ValueKey('reset-icon')),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadSyncedPhotos(showSpinner: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Synced photos recorded: $_recordedPhotoCount',
                      style: theme.textTheme.titleMedium,
                    ),
                    if (!_loadingSyncedPhotos)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Available on device: ${_syncedPhotos.length}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_loadingSyncedPhotos)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_recordedPhotoCount == 0)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
                    child: _SyncedPhotosEmptyState(),
                  ),
                ),
              )
            else ...[
              if (_syncedPhotos.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final entry = _syncedPhotos[index];
                        return _SyncedPhotoTile(
                          entry: entry,
                          onTap: () => _openSyncedPhoto(entry),
                        );
                      },
                      childCount: _syncedPhotos.length,
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: _SyncedPhotosMissingState(message: 'No synced photos available on this device.'),
                  ),
                ),
              if (_missingSyncedPhotos.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  sliver: SliverToBoxAdapter(
                    child: _SyncedPhotosMissingState(
                      message:
                          '${_missingSyncedPhotos.length} synced ${_missingSyncedPhotos.length == 1 ? 'photo is' : 'photos are'} no longer available on this device. They may have been removed from local storage.',
                    ),
                  ),
                ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 40),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openSyncedPhoto(_SyncedPhotoEntry entry) {
    final asset = entry.asset;
    if (asset == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PhotoDetailPage(asset: asset),
      ),
    );
  }
}

class _SyncedPhotoEntry {
  const _SyncedPhotoEntry({
    required this.assetId,
    required this.contentHash,
    this.asset,
  });

  final String assetId;
  final String contentHash;
  final AssetEntity? asset;

  _SyncedPhotoEntry copyWith({AssetEntity? asset}) {
    return _SyncedPhotoEntry(
      assetId: assetId,
      contentHash: contentHash,
      asset: asset ?? this.asset,
    );
  }
}

class _SyncedPhotoTile extends StatelessWidget {
  const _SyncedPhotoTile({
    super.key,
    required this.entry,
    required this.onTap,
  });

  final _SyncedPhotoEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final asset = entry.asset;
    final theme = Theme.of(context);
    if (asset == null) {
      return _MissingSyncedPhotoTile(assetId: entry.assetId);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.12),
        child: Tooltip(
          message: 'Content hash: ${entry.contentHash}',
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: asset.id,
                  transitionOnUserGestures: true,
                  child: Image(
                    image: CachedThumbnailImageProvider(
                      asset,
                      size: const ThumbnailSize.square(600),
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 0.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        'Synced',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MissingSyncedPhotoTile extends StatelessWidget {
  const _MissingSyncedPhotoTile({required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                'Missing asset',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                assetId,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncedPhotosEmptyState extends StatelessWidget {
  const _SyncedPhotosEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              Icons.photo_library_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'No synced photos recorded yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncedPhotosMissingState extends StatelessWidget {
  const _SyncedPhotosMissingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
