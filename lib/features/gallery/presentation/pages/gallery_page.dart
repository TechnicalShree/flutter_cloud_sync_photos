import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_cloud_sync_photos/core/network/network_service.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../data/services/upload_metadata_store.dart';
import '../../data/services/gallery_upload_queue.dart';
import '../pages/photo_detail_page.dart';
import '../widgets/gallery_empty_state.dart';
import '../widgets/gallery_loading_state.dart';
import '../widgets/gallery_permission_prompt.dart';
import '../widgets/gallery_refresh_indicator.dart';
import '../widgets/gallery_section_list.dart';

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  static const int _pageSize = 60;

  bool _isLoading = true;
  bool _hasPermission = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _selectionMode = false;

  final UploadMetadataStore _metadataStore = UploadMetadataStore();
  final Set<String> _selectedAssetIds = <String>{};
  late final GalleryUploadQueue _uploadQueue;
  late final NetworkService _networkService;
  Set<String> _uploadingAssetIds = const <String>{};
  bool _hasActiveUploads = false;
  VoidCallback? _uploadQueueListener;
  StreamSubscription<NetworkConditions>? _networkSubscription;
  bool _hasNetworkConnection = true;
  bool _isOnline = true;
  String? _uploadBlockReason;

  List<AssetEntity> _assets = const <AssetEntity>[];
  List<GallerySection> _sections = const <GallerySection>[];
  PermissionState? _permissionState;
  AssetPathEntity? _assetPath;
  int _nextPage = 0;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _uploadQueue = galleryUploadQueue;
    _uploadQueueListener = _handleUploadQueueChange;
    _uploadQueue.addListener(_uploadQueueListener!);
    _syncUploadState();
    _networkService = NetworkService();
    _networkSubscription =
        _networkService.onConditionsChanged.listen(_handleNetworkConditions);
    unawaited(_primeNetworkStatus());
    _scrollController = ScrollController()..addListener(_onScroll);
    _initializeGallery(reset: true);
  }

  @override
  void dispose() {
    if (_uploadQueueListener != null) {
      _uploadQueue.removeListener(_uploadQueueListener!);
      _uploadQueueListener = null;
    }
    _networkSubscription?.cancel();
    _networkSubscription = null;
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeGallery({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
      });
    }

    final permission = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    final isAuthorized = permission.isAuth || permission.hasAccess;
    if (!isAuthorized) {
      setState(() {
        _permissionState = permission;
        _isLoading = false;
        _hasPermission = false;
        _assets = const [];
        _sections = const [];
        _hasMore = false;
        _isLoadingMore = false;
      });
      return;
    }

    _permissionState = permission;
    _hasPermission = true;

    if (_assetPath == null || reset) {
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: true,
        filterOption: FilterOptionGroup(
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        ),
      );
      _assetPath = paths.isNotEmpty ? paths.first : null;
    }

    if (_assetPath == null) {
      setState(() {
        _assets = const [];
        _sections = const [];
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
      });
      return;
    }

    await _fetchAssets(reset: reset);
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
    final blockReason = _uploadQueue.blockedReason;

    if (notify) {
      setState(() {
        _uploadingAssetIds = uploadingIds;
        _hasActiveUploads = hasActive;
        _uploadBlockReason = blockReason;
      });
    } else {
      _uploadingAssetIds = uploadingIds;
      _hasActiveUploads = hasActive;
      _uploadBlockReason = blockReason;
    }
  }

  Future<void> _primeNetworkStatus() async {
    final conditions = await _networkService.currentConditions();
    if (!mounted) {
      return;
    }
    setState(() {
      _hasNetworkConnection = conditions.hasNetwork;
      _isOnline = conditions.isOnline;
    });
  }

  void _handleNetworkConditions(NetworkConditions conditions) {
    if (!mounted) {
      return;
    }
    setState(() {
      _hasNetworkConnection = conditions.hasNetwork;
      _isOnline = conditions.isOnline;
    });
  }

  Future<void> _fetchAssets({required bool reset}) async {
    final path = _assetPath;
    if (path == null) {
      return;
    }

    if (reset) {
      _nextPage = 0;
      _assets = const [];
      _sections = const [];
      _hasMore = true;
    }

    final page = _nextPage;
    final result = await path.getAssetListPaged(page: page, size: _pageSize);

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
        _nextPage = page + 1;
      }

      _hasMore = result.length == _pageSize;
      _isLoading = false;
      _isLoadingMore = false;

      final availableIds = _assets.map((asset) => asset.id).toSet();
      _selectedAssetIds.removeWhere((id) => !availableIds.contains(id));
      if (_selectedAssetIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  Future<void> _handleRefresh() async {
    _clearSelection();
    await _initializeGallery(reset: true);
  }

  Future<void> _requestPermission() async {
    await _initializeGallery(reset: true);
  }

  void _onScroll() {
    if (!_hasPermission || !_hasMore || _isLoadingMore || _isLoading) {
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
    if (_isLoadingMore || !_hasMore || !_hasPermission) {
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

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PhotoDetailPage(asset: asset)));
  }

  void _handleAssetLongPress(AssetEntity asset) {
    unawaited(_toggleSelection(asset));
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
      fallbackAlbumName: _assetPath?.name,
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
      fallbackAlbumName: _assetPath?.name,
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

  List<_StatusBannerData> _statusBannerData() {
    final banners = <_StatusBannerData>[];

    if (!_isOnline) {
      final message = _hasNetworkConnection
          ? 'No internet connection detected. Uploads will resume automatically.'
          : 'No network connection. Connect to Wi-Fi or cellular to resume uploads.';
      banners.add(
        _StatusBannerData(icon: Icons.wifi_off, message: message),
      );
    }

    final reason = _uploadBlockReason?.trim();
    if (reason != null && reason.isNotEmpty) {
      const offlineReasons = {
        'No internet connection detected',
        'Waiting for a network connection',
      };
      if (_isOnline || !offlineReasons.contains(reason)) {
        banners.add(
          _StatusBannerData(
            icon: _iconForBlockReason(reason),
            message: reason,
          ),
        );
      }
    }

    return banners;
  }

  IconData _iconForBlockReason(String reason) {
    final lower = reason.toLowerCase();
    if (lower.contains('wi-fi')) {
      return Icons.wifi_tethering_off;
    }
    if (lower.contains('roaming')) {
      return Icons.public_off;
    }
    if (lower.contains('charging')) {
      return Icons.ev_station;
    }
    if (lower.contains('battery')) {
      return Icons.battery_alert;
    }
    if (lower.contains('network')) {
      return Icons.wifi_off;
    }
    return Icons.cloud_off;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bannerData = _statusBannerData();

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (_selectionMode) {
          _clearSelection();
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.06),
                theme.colorScheme.surfaceContainerHigh,
                theme.colorScheme.surface,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                GalleryRefreshIndicator(
                  onRefresh: _handleRefresh,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverAppBar(
                        expandedHeight: 240,
                        pinned: true,
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    automaticallyImplyLeading: false,
                    flexibleSpace: LayoutBuilder(
                      builder: (context, constraints) {
                        final highlight = _assets.isNotEmpty
                            ? _assets.first
                            : null;
                        final title = _selectionMode
                            ? '${_selectedAssetIds.length} selected'
                            : 'Gallery';
                        final subtitle = _selectionMode
                            ? '${_assets.length} total photos'
                            : '${_assets.length} photos';

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            _GalleryGlassHeader(
                              asset: highlight,
                              title: title,
                              subtitle: subtitle,
                            ),
                            SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    const Spacer(),
                                    if (_hasActiveUploads) ...[
                                      const _GalleryGlassProgressIndicator(),
                                      const SizedBox(width: 12),
                                    ],
                                    if (_selectionMode) ...[
                                      _GalleryGlassIconButton(
                                        icon: Icons.cloud_upload,
                                        tooltip: 'Upload selected',
                                        onPressed: _selectedAssetIds.isEmpty || !_isOnline
                                            ? null
                                            : () => _uploadSelectedAssets(),
                                      ),
                                      const SizedBox(width: 12),
                                      _GalleryGlassIconButton(
                                        icon: Icons.close,
                                        tooltip: 'Clear selection',
                                        onPressed: _clearSelection,
                                      ),
                                    ] else
                                      _GalleryGlassIconButton(
                                        icon: Icons.refresh,
                                        tooltip: 'Refresh',
                                        onPressed: _isLoading
                                            ? null
                                            : () => _handleRefresh(),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
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
                        )
                      else if (!_isLoading && !_hasMore && _assets.isNotEmpty)
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                ),
                if (bannerData.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 8),
                          for (final data in bannerData)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: _GalleryStatusBanner(
                                icon: data.icon,
                                message: data.message,
                              ),
                            ),
                        ],
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

  Widget _buildContent(ThemeData theme) {
    if (_isLoading) {
      return const GalleryLoadingState();
    }

    if (!_hasPermission) {
      return GalleryPermissionPrompt(
        permissionState: _permissionState,
        onRequestPermission: () => _requestPermission(),
        onRetry: () => _handleRefresh(),
      );
    }

    if (_assets.isEmpty) {
      return const GalleryEmptyState();
    }

    return GallerySectionList(
      sections: _sections,
      metadataStore: _metadataStore,
      selectionMode: _selectionMode,
      selectedAssetIds: _selectedAssetIds,
      uploadingAssetIds: _uploadingAssetIds,
      hideSelectionIndicatorAssetIds: _selectionMode && _assets.isNotEmpty
          ? {_assets.first.id}
          : const <String>{},
      onAssetTap: _handleAssetTap,
      onAssetLongPress: _handleAssetLongPress,
      onAssetUpload: _isOnline ? _uploadAsset : null,
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

class _GalleryGlassHeader extends StatelessWidget {
  const _GalleryGlassHeader({
    required this.asset,
    required this.title,
    required this.subtitle,
  });

  final AssetEntity? asset;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSubtitle = subtitle.trim().isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        _GalleryHeaderBackground(asset: asset),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.20),
                  Colors.black.withValues(alpha: 0.05),
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
                  color: Colors.white.withValues(alpha: 0.12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (hasSubtitle) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
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

class _GalleryHeaderBackground extends StatelessWidget {
  const _GalleryHeaderBackground({this.asset});

  final AssetEntity? asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (asset == null) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
          ),
        ),
      );
    }

    return Image(
      image: AssetEntityImageProvider(
        asset!,
        thumbnailSize: const ThumbnailSize.square(1200),
        isOriginal: false,
      ),
      fit: BoxFit.cover,
    );
  }
}

class _GalleryGlassIconButton extends StatelessWidget {
  const _GalleryGlassIconButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withValues(alpha: enabled ? 0.18 : 0.08),
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                icon,
                color: Colors.white.withValues(alpha: enabled ? 1 : 0.4),
              ),
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

class _GalleryGlassProgressIndicator extends StatelessWidget {
  const _GalleryGlassProgressIndicator();

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
            color: Colors.white.withValues(alpha: 0.18),
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

class _StatusBannerData {
  const _StatusBannerData({required this.icon, required this.message});

  final IconData icon;
  final String message;
}

class _GalleryStatusBanner extends StatelessWidget {
  const _GalleryStatusBanner({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colorScheme.primary),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
