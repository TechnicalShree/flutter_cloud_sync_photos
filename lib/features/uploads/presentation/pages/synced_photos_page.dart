import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../gallery/data/services/gallery_upload_queue.dart';
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
  bool _loadingSyncedPhotos = true;
  bool _showAllSyncedPhotos = false;
  bool _resettingMetadata = false;
  VoidCallback? _uploadQueueListener;
  int _completedJobCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSyncedPhotos(showSpinner: true, resetExpanded: true);
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

  Future<void> _loadSyncedPhotos({bool showSpinner = false, bool resetExpanded = false}) async {
    if (!mounted) {
      return;
    }
    if (showSpinner) {
      setState(() {
        _loadingSyncedPhotos = true;
        if (resetExpanded) {
          _showAllSyncedPhotos = false;
        }
      });
    } else if (resetExpanded) {
      setState(() {
        _showAllSyncedPhotos = false;
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

    setState(() {
      _syncedPhotos = entries;
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
      await _loadSyncedPhotos(showSpinner: true, resetExpanded: true);
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
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            if (_loadingSyncedPhotos)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              ..._buildSyncedContent(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSyncedContent(ThemeData theme) {
    final entries = _syncedPhotos;
    const maxVisible = 40;
    final hasEntries = entries.isNotEmpty;
    final displayAll = _showAllSyncedPhotos || entries.length <= maxVisible;
    final displayed = displayAll ? entries : entries.take(maxVisible).toList();
    final hasMore = entries.length > maxVisible && !_showAllSyncedPhotos;
    final showLess = entries.length > maxVisible && _showAllSyncedPhotos;

    return [
      Text(
        'Synced photos recorded: ${entries.length}',
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 16),
      if (!hasEntries)
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
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
        )
      else ...[
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayed.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final entry = displayed[index];
            return _SyncedPhotoRow(entry: entry);
          },
        ),
        if (hasMore || showLess)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (hasMore)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showAllSyncedPhotos = true;
                      });
                    },
                    icon: const Icon(Icons.expand_more),
                    label: Text('Show all (${entries.length})'),
                  ),
                if (showLess)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showAllSyncedPhotos = false;
                      });
                    },
                    icon: const Icon(Icons.expand_less),
                    label: const Text('Show less'),
                  ),
              ],
            ),
          ),
      ],
    ];
  }
}

class _SyncedPhotoEntry {
  const _SyncedPhotoEntry({required this.assetId, required this.contentHash});

  final String assetId;
  final String contentHash;

  String get shortHash {
    if (contentHash.length <= 12) {
      return contentHash;
    }
    return '${contentHash.substring(0, 12)}…';
  }
}

class _SyncedPhotoRow extends StatelessWidget {
  const _SyncedPhotoRow({super.key, required this.entry});

  final _SyncedPhotoEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assetSegments = entry.assetId.split('/');
    final folderSegments = assetSegments.length <= 1
        ? <String>[]
        : assetSegments.sublist(0, assetSegments.length - 1);
    final fileName = assetSegments.isEmpty ? entry.assetId : assetSegments.last;
    final folderPreview = folderSegments.isEmpty
        ? null
        : folderSegments
            .map(
              (segment) => segment.length <= 16
                  ? segment
                  : '${segment.substring(0, math.min(16, segment.length))}…',
            )
            .join(' / ');

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (folderPreview != null) ...[
              const SizedBox(height: 6),
              Text(
                folderPreview,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Hash: ${entry.shortHash}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
