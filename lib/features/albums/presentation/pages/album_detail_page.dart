import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../gallery/presentation/util/cached_thumbnail_image_provider.dart';

import '../../../gallery/data/services/upload_metadata_store.dart';
import '../../../gallery/data/services/gallery_upload_queue.dart';
import '../../../gallery/presentation/pages/photo_detail_page.dart';
import '../../../gallery/presentation/widgets/gallery_section_list.dart';

class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({
    super.key,
    required this.path,
    required this.title,
    this.cover,
    this.heroTag,
    this.initialCount,
  });

  final AssetPathEntity path;
  final String title;
  final AssetEntity? cover;
  final String? heroTag;
  final int? initialCount;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  static const int _pageSize = 60;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _selectionMode = false;

  int _nextPage = 0;

  final ScrollController _scrollController = ScrollController();
  final UploadMetadataStore _metadataStore = UploadMetadataStore();
  late final GalleryUploadQueue _uploadQueue;
  final Set<String> _selectedAssetIds = <String>{};
  Set<String> _uploadingAssetIds = const <String>{};
  bool _hasActiveUploads = false;
  VoidCallback? _uploadQueueListener;

  List<AssetEntity> _assets = const [];
  List<GallerySection> _sections = const [];
  int? _assetCount;

  @override
  void initState() {
    super.initState();
    _uploadQueue = galleryUploadQueue;
    _uploadQueueListener = _handleUploadQueueChange;
    _uploadQueue.addListener(_uploadQueueListener!);
    _syncUploadState();
    _scrollController.addListener(_onScroll);
    _assetCount = widget.initialCount;
    _loadAssets(reset: true);
  }

  @override
  void dispose() {
    if (_uploadQueueListener != null) {
      _uploadQueue.removeListener(_uploadQueueListener!);
      _uploadQueueListener = null;
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAssets({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
      });
    }

    await _fetchAssets(reset: reset);
  }

  Future<void> _fetchAssets({required bool reset}) async {
    if (reset) {
      _nextPage = 0;
      _assets = const [];
      _sections = const [];
      _hasMore = true;
    }

    try {
      final result = await widget.path.getAssetListPaged(
        page: _nextPage,
        size: _pageSize,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        if (reset) {
          _assets = result;
        } else {
          final existingIds = _assets.map((asset) => asset.id).toSet();
          final filtered = result
              .where((asset) => !existingIds.contains(asset.id))
              .toList();
          _assets = [..._assets, ...filtered];
        }

        _sections = _groupAssetsByDay(_assets);
        if (result.isNotEmpty) {
          _nextPage += 1;
        }
        _hasMore = result.length == _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
        _assetCount = _assets.length;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  void _handleUploadQueueChange() {
    if (!mounted) {
      return;
    }
    _syncUploadState(notify: true);
  }

  void _syncUploadState({bool notify = false}) {
    final uploadingIds = _uploadQueue.activeAssetIds.toSet();
    final hasActive = _uploadQueue.hasActiveUploads;

    if (notify) {
      setState(() {
        _uploadingAssetIds = uploadingIds;
        _hasActiveUploads = hasActive;
      });
    } else {
      _uploadingAssetIds = uploadingIds;
      _hasActiveUploads = hasActive;
    }
  }

  Future<void> _handleRefresh() async {
    _clearSelection();
    await _loadAssets(reset: true);
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading) {
      return;
    }
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _fetchMore();
    }
  }

  Future<void> _fetchMore() async {
    if (_isLoadingMore || !_hasMore) {
      return;
    }
    setState(() {
      _isLoadingMore = true;
    });
    await _fetchAssets(reset: false);
  }

  void _handleAssetTap(AssetEntity asset) {
    if (_selectionMode) {
      unawaited(_toggleSelection(asset));
      return;
    }
    _openAsset(asset);
  }

  void _handleAssetLongPress(AssetEntity asset) {
    unawaited(_toggleSelection(asset));
  }

  void _openAsset(AssetEntity asset) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PhotoDetailPage(asset: asset)));
  }

  Future<void> _toggleSelection(AssetEntity asset) async {
    final id = asset.id;

    if (_uploadingAssetIds.contains(id)) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Upload in progress')),
      );
      return;
    }

    final isAlreadySelected = _selectedAssetIds.contains(id);
    if (!isAlreadySelected) {
      final alreadyUploaded = await _metadataStore.isUploaded(id);
      if (!mounted) {
        return;
      }
      if (alreadyUploaded) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text('Photo already synced')),
        );
        return;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      if (isAlreadySelected) {
        _selectedAssetIds.remove(id);
        if (_selectedAssetIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedAssetIds.add(id);
        _selectionMode = true;
      }
    });
  }

  void _clearSelection() {
    if (_selectedAssetIds.isEmpty && !_selectionMode) {
      return;
    }
    setState(() {
      _selectedAssetIds.clear();
      _selectionMode = false;
    });
  }

  List<AssetEntity> _getSelectedAssets() {
    if (_selectedAssetIds.isEmpty) {
      return const [];
    }

    final byId = <String, AssetEntity>{};
    for (final section in _sections) {
      for (final asset in section.assets) {
        byId[asset.id] = asset;
      }
    }

    return _selectedAssetIds
        .map((id) => byId[id])
        .whereType<AssetEntity>()
        .toList();
  }

  Future<void> _uploadAsset(AssetEntity asset) async {
    final messenger = ScaffoldMessenger.of(context);
    final summary = await _uploadQueue.enqueueAssets(
      [asset],
      fallbackAlbumName: widget.title,
    );

    if (!mounted) {
      return;
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(_buildEnqueueMessage(summary))),
    );
  }

  Future<void> _uploadSelectedAssets() async {
    if (_selectedAssetIds.isEmpty) {
      return;
    }

    final assets = _getSelectedAssets();
    if (assets.isEmpty) {
      _clearSelection();
      return;
    }

    final summary = await _uploadQueue.enqueueAssets(
      assets,
      fallbackAlbumName: widget.title,
    );

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(_buildEnqueueMessage(summary))),
    );

    setState(() {
      _selectedAssetIds.clear();
      _selectionMode = false;
    });
  }

  String _buildEnqueueMessage(UploadEnqueueSummary summary) {
    if (summary.totalRequested <= 1) {
      if (summary.enqueued == 1) {
        return 'Upload started in background';
      }
      if (summary.duplicates > 0) {
        return 'Upload already in progress';
      }
      if (summary.alreadyUploaded > 0) {
        return 'Photo already uploaded';
      }
      return 'Nothing to upload';
    }

    final parts = <String>[];

    if (summary.enqueued > 0) {
      final label = summary.enqueued == 1 ? 'upload' : 'uploads';
      parts.add('Queued ${summary.enqueued} $label');
    }
    if (summary.duplicates > 0) {
      final label = summary.duplicates == 1 ? 'item' : 'items';
      parts.add('${summary.duplicates} $label already uploading');
    }
    if (summary.alreadyUploaded > 0) {
      final label = summary.alreadyUploaded == 1 ? 'item' : 'items';
      parts.add('${summary.alreadyUploaded} $label already synced');
    }

    return parts.isEmpty ? 'No photos queued' : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: RefreshIndicator(
        color: theme.colorScheme.primary,
        onRefresh: _handleRefresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 260,
              pinned: true,
              elevation: 0,
              automaticallyImplyLeading: false,
              backgroundColor: Colors.transparent,
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _GlassHeader(
                        cover: widget.cover,
                        heroTag: widget.heroTag,
                        title: widget.title,
                        photoCount: _assetCount ?? 0,
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              _GlassIconButton(
                                icon: Icons.arrow_back,
                                onPressed: () {
                                  if (_selectionMode) {
                                    _clearSelection();
                                    return;
                                  }
                                  Navigator.of(context).maybePop();
                                },
                                tooltip: _selectionMode ? 'Cancel selection' : 'Back',
                              ),
                              const Spacer(),
                              if (_hasActiveUploads) ...[
                                const _GlassProgressIndicator(),
                                const SizedBox(width: 12),
                              ],
                              if (_selectionMode) ...[
                                _GlassIconButton(
                                  icon: Icons.cloud_upload,
                                  tooltip: 'Upload selected',
                                  onPressed: _selectedAssetIds.isEmpty
                                      ? null
                                      : () => _uploadSelectedAssets(),
                                ),
                                const SizedBox(width: 12),
                                _GlassIconButton(
                                  icon: Icons.close,
                                  tooltip: 'Clear selection',
                                  onPressed: _clearSelection,
                                ),
                              ] else
                                _GlassIconButton(
                                  icon: Icons.info_outline,
                                  tooltip: 'How uploads work',
                                  onPressed: _showUploadHint,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              sliver: _buildContent(theme),
            ),
            if (_isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_isLoading) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 120),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(
                height: 48,
                width: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 16),
              Text('Loading photos...'),
            ],
          ),
        ),
      );
    }

    if (_assets.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(child: Text('No photos yet.')),
        ),
      );
    }

    return GallerySectionList(
      sections: _sections,
      metadataStore: _metadataStore,
      selectionMode: _selectionMode,
      selectedAssetIds: _selectedAssetIds,
      uploadingAssetIds: _uploadingAssetIds,
      hideSelectionIndicatorAssetIds: const <String>{},
      onAssetTap: _handleAssetTap,
      onAssetLongPress: _handleAssetLongPress,
      onAssetUpload: _uploadAsset,
    );
  }

  List<GallerySection> _groupAssetsByDay(List<AssetEntity> assets) {
    if (assets.isEmpty) {
      return const [];
    }

    final now = DateTime.now().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final sections = <GallerySection>[];
    List<AssetEntity> currentGroup = [];
    DateTime? currentDate;

    void emitSection(DateTime? date, List<AssetEntity> group) {
      if (date == null || group.isEmpty) {
        return;
      }

      late final String title;
      if (_isSameDay(date, today)) {
        title = 'Today';
      } else if (_isSameDay(date, yesterday)) {
        title = 'Yesterday';
      } else {
        title = _formatDate(date);
      }

      sections.add(
        GallerySection(title: title, assets: List.unmodifiable(group)),
      );
    }

    for (final asset in assets) {
      final date = asset.createDateTime.toLocal();
      final day = DateTime(date.year, date.month, date.day);

      if (currentDate == null || !_isSameDay(day, currentDate)) {
        emitSection(currentDate, currentGroup);
        currentDate = day;
        currentGroup = [];
      }

      currentGroup.add(asset);
    }

    emitSection(currentDate, currentGroup);
    return sections;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDate(DateTime date) {
    return '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _showUploadHint() {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Tap the cloud icon on any photo to upload it.'),
      ),
    );
  }

  static const List<String> _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

class _AlbumCover extends StatelessWidget {
  const _AlbumCover({this.cover, this.heroTag});

  final AssetEntity? cover;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget child;
    if (cover == null) {
      child = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
          ),
        ),
      );
    } else {
      child = Image(
        image: CachedThumbnailImageProvider(
          cover!,
          size: const ThumbnailSize.square(1200),
        ),
        fit: BoxFit.cover,
      );
    }

    if (heroTag != null) {
      child = Hero(tag: heroTag!, child: child);
    }

    return child;
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withOpacity(0.18),
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, color: Colors.white),
            ),
          ),
        ),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }
}

class _GlassProgressIndicator extends StatelessWidget {
  const _GlassProgressIndicator();

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            shape: BoxShape.circle,
          ),
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassHeader extends StatelessWidget {
  const _GlassHeader({
    required this.cover,
    required this.heroTag,
    required this.title,
    required this.photoCount,
  });

  final AssetEntity? cover;
  final String? heroTag;
  final String title;
  final int photoCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayCount = photoCount < 0 ? 0 : photoCount;
    final countLabel = displayCount == 1 ? '1 photo' : '$displayCount photos';

    return Stack(
      fit: StackFit.expand,
      children: [
        _AlbumCover(cover: cover, heroTag: heroTag),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.55),
                  Colors.black.withOpacity(0.20),
                  Colors.black.withOpacity(0.05),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 28,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.18),
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      countLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
