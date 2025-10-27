import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cloud_sync_photos/core/navigation/shared_axis_page_route.dart';
import 'package:flutter_cloud_sync_photos/core/network/api_exception.dart';
import 'package:flutter_cloud_sync_photos/features/auth/data/services/auth_service.dart';
import 'package:flutter_cloud_sync_photos/features/auth/presentation/pages/login_page.dart';
import 'package:photo_manager/photo_manager.dart';
import '../util/cached_thumbnail_image_provider.dart';

import '../../data/services/upload_metadata_store.dart';
import '../../data/services/gallery_upload_queue.dart';
import '../pages/photo_detail_page.dart';
import '../widgets/gallery_empty_state.dart';
import '../widgets/gallery_loading_state.dart';
import '../widgets/gallery_permission_prompt.dart';
import '../widgets/gallery_refresh_indicator.dart';
import '../widgets/gallery_section_list.dart';
import '../widgets/gallery_selection_hit_target.dart';

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 60;
  static const Duration _microAnimationDuration = Duration(milliseconds: 220);
  static const Curve _microAnimationCurve = Curves.easeOutCubic;
  static const Duration _sectionStaggerDelay = Duration(milliseconds: 45);
  static final List<_BulkSelectPreset> _bulkPresets = [
    _BulkSelectPreset(
      label: 'Today',
      description: 'Photos captured today',
      computeRange: _computeTodayRange,
    ),
    _BulkSelectPreset(
      label: 'Yesterday',
      description: 'Photos captured yesterday',
      computeRange: _computeYesterdayRange,
    ),
    _BulkSelectPreset(
      label: 'Last 7 days',
      description: 'Photos from the last week',
      computeRange: _computeLast7DaysRange,
    ),
    _BulkSelectPreset(
      label: 'This month',
      description: 'All photos from this month',
      computeRange: _computeThisMonthRange,
    ),
    _BulkSelectPreset(
      label: 'Last month',
      description: 'Photos from the previous month',
      computeRange: _computeLastMonthRange,
    ),
  ];

  bool _isLoading = true;
  bool _hasPermission = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _selectionMode = false;

  final UploadMetadataStore _metadataStore = UploadMetadataStore();
  final AuthService _authService = globalAuthService;
  final Set<String> _selectedAssetIds = <String>{};
  final Map<String, AssetEntity> _selectedAssets = <String, AssetEntity>{};
  late final GalleryUploadQueue _uploadQueue;
  Set<String> _uploadingAssetIds = const <String>{};
  Set<String> _failedUploadAssetIds = const <String>{};
  bool _hasActiveUploads = false;
  bool _isProcessingSelectionAction = false;
  bool _dragSelecting = false;
  VoidCallback? _uploadQueueListener;
  late final ValueNotifier<AuthStatus> _authStatusNotifier;
  late AuthStatus _authStatus;

  List<AssetEntity> _assets = const <AssetEntity>[];
  List<GallerySection> _sections = const <GallerySection>[];
  PermissionState? _permissionState;
  AssetPathEntity? _assetPath;
  int _nextPage = 0;

  late final ScrollController _scrollController;
  late final AnimationController _backgroundController;

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
    _uploadQueue = galleryUploadQueue;
    _uploadQueueListener = _handleUploadQueueChange;
    _uploadQueue.addListener(_uploadQueueListener!);
    _syncUploadState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _initializeGallery(reset: true);
    _authStatusNotifier = _authService.authStatusNotifier;
    _authStatus = _authStatusNotifier.value;
    _authStatusNotifier.addListener(_handleAuthStatusChange);
  }

  @override
  void dispose() {
    if (_uploadQueueListener != null) {
      _uploadQueue.removeListener(_uploadQueueListener!);
      _uploadQueueListener = null;
    }
    _authStatusNotifier.removeListener(_handleAuthStatusChange);
    _backgroundController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isAuthenticated =>
      _authStatus == AuthStatus.authenticated ||
      _authStatus == AuthStatus.offline;

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
    final failedIds = _uploadQueue.jobs
        .where((job) => job.status == UploadJobStatus.failed)
        .map((job) => job.assetId)
        .toSet();

    if (notify) {
      setState(() {
        _uploadingAssetIds = uploadingIds;
        _hasActiveUploads = hasActive;
        _failedUploadAssetIds = failedIds;
      });
    } else {
      _uploadingAssetIds = uploadingIds;
      _hasActiveUploads = hasActive;
      _failedUploadAssetIds = failedIds;
    }
  }

  void _handleAuthStatusChange() {
    final status = _authStatusNotifier.value;
    if (!mounted) {
      _authStatus = status;
      return;
    }
    setState(() {
      _authStatus = status;
    });
  }

  void _showLoginRequiredMessage() {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Sign in to sync your photos.')),
    );
  }

  void _openLoginPage() {
    Navigator.of(context).pushNamed(LoginPage.routeName);
  }

  Widget _buildLoginReminderBanner(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final foreground = colorScheme.onSecondaryContainer;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: colorScheme.secondaryContainer.withOpacity(0.24),
        border: Border.all(color: colorScheme.secondary.withOpacity(0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, color: foreground),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sign in to sync your photos',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Upload, retry, and unsync actions unlock once you sign in.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: _openLoginPage,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSecondaryContainer,
              ),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
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

      final availableById = <String, AssetEntity>{
        for (final asset in _assets) asset.id: asset,
      };
      for (final id in _selectedAssetIds) {
        final asset = availableById[id];
        if (asset != null) {
          _selectedAssets[id] = asset;
        }
      }
      _selectedAssets.removeWhere((id, _) => !_selectedAssetIds.contains(id));
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
    ).push(SharedAxisPageRoute(builder: (_) => PhotoDetailPage(asset: asset)));
  }

  void _handleAssetLongPress(AssetEntity asset) {
    if (_dragSelecting) {
      return;
    }
    unawaited(_toggleSelection(asset));
  }

  void _handleAssetLongPressStart(
    AssetEntity asset,
    LongPressStartDetails details,
  ) {
    if (_isProcessingSelectionAction) {
      return;
    }
    _dragSelecting = true;
    unawaited(_toggleSelection(asset));
  }

  void _handleAssetLongPressMoveUpdate(
    AssetEntity asset,
    LongPressMoveUpdateDetails details,
  ) {
    if (!_dragSelecting) {
      return;
    }
    _updateDragSelection(details.globalPosition);
  }

  void _handleAssetLongPressEnd(
    AssetEntity asset,
    LongPressEndDetails details,
  ) {
    if (!_dragSelecting) {
      return;
    }
    _dragSelecting = false;
  }

  void _updateDragSelection(Offset globalPosition) {
    final binding = WidgetsBinding.instance;
    final result = HitTestResult();
    binding.hitTest(result, globalPosition);

    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderGallerySelectionHitTarget) {
        final assetId = target.assetId;
        if (_selectedAssetIds.contains(assetId)) {
          return;
        }
        final asset = _findAssetInSections(assetId);
        if (asset != null) {
          unawaited(_toggleSelection(asset));
        }
        return;
      }
    }
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

    if (!mounted) {
      return;
    }

    setState(() {
      if (isAlreadySelected) {
        _selectedAssetIds.remove(id);
        _selectedAssets.remove(id);
        if (_selectedAssetIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedAssetIds.add(id);
        _selectedAssets[id] = asset;
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
      _selectedAssets.clear();
      _selectionMode = false;
    });
  }

  Future<List<AssetEntity>> _resolveSelectedAssets() async {
    if (_selectedAssetIds.isEmpty) {
      return const [];
    }

    final assets = <AssetEntity>[];
    for (final id in _selectedAssetIds) {
      final cached = _selectedAssets[id];
      if (cached != null) {
        assets.add(cached);
        continue;
      }
      final inSections = _findAssetInSections(id);
      if (inSections != null) {
        _selectedAssets[id] = inSections;
        assets.add(inSections);
        continue;
      }
      final fetched = await AssetEntity.fromId(id);
      if (fetched != null) {
        _selectedAssets[id] = fetched;
        assets.add(fetched);
      }
    }
    return assets;
  }

  AssetEntity? _findAssetInSections(String id) {
    for (final section in _sections) {
      for (final asset in section.assets) {
        if (asset.id == id) {
          return asset;
        }
      }
    }
    return null;
  }

  Future<void> _uploadAsset(AssetEntity asset) async {
    if (!_isAuthenticated) {
      _showLoginRequiredMessage();
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final summary = await _uploadQueue.enqueueAssets([
      asset,
    ], fallbackAlbumName: _assetPath?.name);

    if (!mounted) {
      return;
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(_buildEnqueueMessage(summary))),
    );
  }

  Future<void> _uploadSelectedAssets() async {
    if (!_isAuthenticated) {
      _showLoginRequiredMessage();
      return;
    }

    if (_selectedAssetIds.isEmpty) {
      return;
    }

    final assets = await _resolveSelectedAssets();
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
      _selectedAssets.clear();
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

  Future<void> _selectAssetsByPreset(_BulkSelectPreset preset) async {
    if (_isProcessingSelectionAction) {
      return;
    }

    setState(() {
      _isProcessingSelectionAction = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    final range = preset.computeRange(DateTime.now());

    try {
      final assets = await _loadAssetsInRange(range.start, range.end);

      if (!mounted) {
        return;
      }

      if (assets.isEmpty) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('No photos found for ${preset.label.toLowerCase()}'),
          ),
        );
        return;
      }

      int newlyAdded = 0;
      setState(() {
        for (final asset in assets) {
          final id = asset.id;
          final wasNew = _selectedAssetIds.add(id);
          if (wasNew) {
            newlyAdded += 1;
          }
          _selectedAssets[id] = asset;
        }
        if (_selectedAssetIds.isNotEmpty) {
          _selectionMode = true;
        }
      });

      messenger.hideCurrentSnackBar();
      final countLabel = newlyAdded == assets.length
          ? '${assets.length}'
          : '${assets.length} (+$newlyAdded new)';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Selected $countLabel from ${preset.label.toLowerCase()}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to select ${preset.label.toLowerCase()}'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSelectionAction = false;
        });
      }
    }
  }

  Future<List<AssetEntity>> _loadAssetsInRange(
    DateTime start,
    DateTime end,
  ) async {
    final filter = FilterOptionGroup(
      createTimeCond: DateTimeCond(min: start, max: end),
      orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
    );

    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
      filterOption: filter,
    );

    if (paths.isEmpty) {
      return const [];
    }

    final path = paths.first;
    final total = await path.assetCountAsync;
    if (total == 0) {
      return const [];
    }

    const int pageSize = 120;
    final assets = <AssetEntity>[];
    for (int offset = 0; offset < total; offset += pageSize) {
      final page = await path.getAssetListPaged(
        page: offset ~/ pageSize,
        size: pageSize,
      );
      assets.addAll(page);
    }
    return assets;
  }

  Future<void> _removeSelectedFromSync() async {
    if (!_isAuthenticated) {
      _showLoginRequiredMessage();
      return;
    }

    if (_selectedAssetIds.isEmpty || _isProcessingSelectionAction) {
      return;
    }

    setState(() {
      _isProcessingSelectionAction = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final entries = <MapEntry<String, String>>[];
      for (final id in _selectedAssetIds) {
        final hash = await _metadataStore.getContentHash(id);
        if (hash != null && hash.isNotEmpty) {
          entries.add(MapEntry(id, hash));
        }
      }

      if (entries.isEmpty) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text('No synced photos in selection')),
        );
        return;
      }

      for (final entry in entries) {
        await globalAuthService.unsyncFile(contentHash: entry.value);
        await _metadataStore.remove(entry.key);
      }

      if (!mounted) {
        return;
      }

      messenger.hideCurrentSnackBar();
      final count = entries.length;
      final label = count == 1 ? 'photo' : 'photos';
      messenger.showSnackBar(
        SnackBar(content: Text('Removed $count $label from sync')),
      );

      setState(() {
        for (final entry in entries) {
          _selectedAssetIds.remove(entry.key);
          _selectedAssets.remove(entry.key);
        }
        if (_selectedAssetIds.isEmpty) {
          _selectionMode = false;
        }
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(error.message ?? 'Failed to unsync photos')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to unsync photos')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSelectionAction = false;
        });
      }
    }
  }

  Future<void> _retryFailedUploads() async {
    if (!_isAuthenticated) {
      _showLoginRequiredMessage();
      return;
    }

    if (_isProcessingSelectionAction) {
      return;
    }

    final targetIds = _selectedAssetIds
        .where((id) => _failedUploadAssetIds.contains(id))
        .toSet();

    if (targetIds.isEmpty) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('No failed uploads selected')),
      );
      return;
    }

    setState(() {
      _isProcessingSelectionAction = true;
    });

    try {
      final retried = await _uploadQueue.retryFailedJobs(
        assetIds: targetIds,
        onlyApiFailures: true,
      );

      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();

      if (retried > 0) {
        final label = retried == 1 ? 'upload' : 'uploads';
        messenger.showSnackBar(
          SnackBar(content: Text('Retrying $retried $label')),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('No retryable uploads found')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSelectionAction = false;
        });
      }
    }
  }

  Future<void> _showBulkSelectSheet() async {
    if (!_selectionMode) {
      setState(() {
        _selectionMode = true;
      });
    }

    final hasRetryTargets = _selectedAssetIds.any(
      _failedUploadAssetIds.contains,
    );

    final action = await showModalBottomSheet<_SelectionAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Text(
                  'Bulk actions',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ..._bulkPresets.map(
                (preset) => ListTile(
                  leading: const Icon(Icons.event_available),
                  title: Text(preset.label),
                  subtitle: Text(preset.description),
                  enabled: !_isProcessingSelectionAction,
                  onTap: () => Navigator.of(
                    context,
                  ).pop(_SelectionActionSelectPreset(preset)),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.cloud_off),
                title: const Text('Remove from sync'),
                enabled: !_isProcessingSelectionAction,
                onTap: () => Navigator.of(
                  context,
                ).pop(const _SelectionActionRemoveFromSync()),
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Retry failed uploads'),
                enabled: !_isProcessingSelectionAction && hasRetryTargets,
                onTap: () => Navigator.of(
                  context,
                ).pop(const _SelectionActionRetryFailed()),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    if (action is _SelectionActionSelectPreset) {
      await _selectAssetsByPreset(action.preset);
    } else if (action is _SelectionActionRemoveFromSync) {
      await _removeSelectedFromSync();
    } else if (action is _SelectionActionRetryFailed) {
      await _retryFailedUploads();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectionPanel = _buildSelectionActions(theme);
    final queuedCount = _uploadQueue.jobs.length;

    return AnimatedBuilder(
      animation: _backgroundController,
      builder: (context, child) {
        final curvedProgress = CurvedAnimation(
          parent: _backgroundController,
          curve: Curves.easeInOut,
        ).value;

        final gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(
              theme.colorScheme.surface,
              theme.colorScheme.primaryContainer.withOpacity(0.85),
              curvedProgress * 0.6,
            )!,
            Color.lerp(
              theme.colorScheme.surface,
              theme.colorScheme.secondaryContainer.withOpacity(0.8),
              0.35 + (curvedProgress * 0.65),
            )!,
          ],
        );

        return DecoratedBox(
          decoration: BoxDecoration(gradient: gradient),
          child: child,
        );
      },
      child: PopScope(
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
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: SafeArea(
            child: GalleryRefreshIndicator(
              onRefresh: _handleRefresh,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
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
                                        icon: Icons.event,
                                        tooltip: 'Bulk select by date',
                                        onPressed: _isProcessingSelectionAction
                                            ? null
                                            : () => _showBulkSelectSheet(),
                                      ),
                                      const SizedBox(width: 12),
                                      _GalleryGlassIconButton(
                                        icon: Icons.cloud_upload,
                                        tooltip: 'Upload selected',
                                        onPressed: !_isAuthenticated ||
                                                _selectedAssetIds.isEmpty ||
                                                _isProcessingSelectionAction
                                            ? null
                                            : () => _uploadSelectedAssets(),
                                      ),
                                      const SizedBox(width: 12),
                                      _GalleryGlassIconButton(
                                        icon: Icons.close,
                                        tooltip: 'Clear selection',
                                        onPressed: _isProcessingSelectionAction
                                            ? null
                                            : _clearSelection,
                                      ),
                                    ] else ...[
                                      _GalleryGlassIconButton(
                                        icon: Icons.refresh,
                                        tooltip: 'Refresh',
                                        onPressed: _isLoading
                                            ? null
                                            : () => _handleRefresh(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  // if (_hasPermission)
                  //   SliverPadding(
                  //     padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  //     sliver: SliverToBoxAdapter(
                  //       child: _GalleryMetricsChips(
                  //         totalCount: _assets.length,
                  //         uploadingCount: _uploadingAssetIds.length,
                  //         failedCount: _failedUploadAssetIds.length,
                  //         selectionCount: _selectedAssetIds.length,
                  //         queuedCount: queuedCount,
                  //         selectionMode: _selectionMode,
                  //         animationDuration: _microAnimationDuration,
                  //         animationCurve: _microAnimationCurve,
                  //       ),
                  //     ),
                  //   ),
                  if (_hasPermission)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                      sliver: SliverToBoxAdapter(
                        child: AnimatedSwitcher(
                          duration: _microAnimationDuration,
                          switchInCurve: _microAnimationCurve,
                          switchOutCurve: Curves.easeInCubic,
                          child:
                              selectionPanel ??
                              const SizedBox.shrink(
                                key: ValueKey('no-actions'),
                              ),
                        ),
                      ),
                    ),
                  if (!_isAuthenticated)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      sliver: SliverToBoxAdapter(
                        child: _buildLoginReminderBanner(theme),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    sliver: _buildContent(theme),
                  ),
                  if (_hasPermission)
                    SliverToBoxAdapter(
                      child: AnimatedSwitcher(
                        duration: _microAnimationDuration,
                        switchInCurve: _microAnimationCurve,
                        switchOutCurve: Curves.easeInCubic,
                        child: _buildLoadMoreIndicator(),
                      ),
                    ),
                ],
              ),
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
      showSyncStatus: _isAuthenticated,
      selectionMode: _selectionMode,
      selectedAssetIds: _selectedAssetIds,
      uploadingAssetIds: _uploadingAssetIds,
      hideSelectionIndicatorAssetIds: const <String>{},
      animationDuration: _microAnimationDuration,
      animationCurve: _microAnimationCurve,
      sectionStaggerDelay: _sectionStaggerDelay,
      onAssetTap: _handleAssetTap,
      onAssetLongPress: _handleAssetLongPress,
      onAssetLongPressStart: _handleAssetLongPressStart,
      onAssetLongPressMoveUpdate: _handleAssetLongPressMoveUpdate,
      onAssetLongPressEnd: _handleAssetLongPressEnd,
      onAssetUpload: _isAuthenticated ? _uploadAsset : null,
    );
  }

  Widget? _buildSelectionActions(ThemeData theme) {
    if (!_selectionMode) {
      return null;
    }

    if (!_isAuthenticated) {
      return KeyedSubtree(
        key: const ValueKey('selection-actions'),
        child: _GallerySectionContainer(
          animationDuration: _microAnimationDuration,
          animationCurve: _microAnimationCurve,
          highlight: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sign in to manage synced photos',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Upload, unsync, and retry tools become available after you sign in from the Settings tab.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final canRetry = _selectedAssetIds.any(
      (id) => _failedUploadAssetIds.contains(id),
    );

    return KeyedSubtree(
      key: const ValueKey('selection-actions'),
      child: _GallerySectionContainer(
        animationDuration: _microAnimationDuration,
        animationCurve: _microAnimationCurve,
        highlight: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bulk tools',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _bulkPresets
                  .map(
                    (preset) => Tooltip(
                      message: preset.description,
                      child: ActionChip(
                        label: Text(preset.label),
                        onPressed: _isProcessingSelectionAction
                            ? null
                            : () => _selectAssetsByPreset(preset),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _isProcessingSelectionAction
                      ? null
                      : () => _removeSelectedFromSync(),
                  icon: const Icon(Icons.cloud_off),
                  label: const Text('Remove from sync'),
                ),
                FilledButton.tonalIcon(
                  onPressed: !_isProcessingSelectionAction && canRetry
                      ? () => _retryFailedUploads()
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry failed'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadMoreIndicator() {
    if (_isLoadingMore) {
      return const Padding(
        key: ValueKey('loading-more'),
        padding: EdgeInsets.only(bottom: 32),
        child: Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final showEndOfList = !_isLoading && !_hasMore && _assets.isNotEmpty;
    if (showEndOfList) {
      return const Padding(
        key: ValueKey('end-of-list'),
        padding: EdgeInsets.only(bottom: 32),
        child: _GalleryEndOfListMessage(),
      );
    }

    return const SizedBox.shrink(key: ValueKey('idle-load-state'));
  }

  static _DateRange _computeTodayRange(DateTime now) {
    final localNow = now.toLocal();
    return _DateRange(_startOfDay(localNow), _endOfDay(localNow));
  }

  static _DateRange _computeYesterdayRange(DateTime now) {
    final localNow = now.toLocal();
    final yesterday = localNow.subtract(const Duration(days: 1));
    return _DateRange(_startOfDay(yesterday), _endOfDay(yesterday));
  }

  static _DateRange _computeLast7DaysRange(DateTime now) {
    final localNow = now.toLocal();
    final start = localNow.subtract(const Duration(days: 6));
    return _DateRange(_startOfDay(start), _endOfDay(localNow));
  }

  static _DateRange _computeThisMonthRange(DateTime now) {
    final localNow = now.toLocal();
    final start = DateTime(localNow.year, localNow.month, 1);
    return _DateRange(_startOfDay(start), _endOfDay(_endOfMonth(localNow)));
  }

  static _DateRange _computeLastMonthRange(DateTime now) {
    final localNow = now.toLocal();
    final firstDayThisMonth = DateTime(localNow.year, localNow.month, 1);
    final lastMonthEnd = firstDayThisMonth.subtract(const Duration(days: 1));
    final start = DateTime(lastMonthEnd.year, lastMonthEnd.month, 1);
    return _DateRange(_startOfDay(start), _endOfDay(_endOfMonth(lastMonthEnd)));
  }

  static DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  static DateTime _endOfMonth(DateTime date) {
    final firstNextMonth = date.month == 12
        ? DateTime(date.year + 1, 1, 1)
        : DateTime(date.year, date.month + 1, 1);
    final lastDay = firstNextMonth.subtract(const Duration(days: 1));
    return DateTime(lastDay.year, lastDay.month, lastDay.day);
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

class _GalleryMetricsChips extends StatelessWidget {
  const _GalleryMetricsChips({
    required this.totalCount,
    required this.selectionCount,
    required this.uploadingCount,
    required this.failedCount,
    required this.queuedCount,
    required this.selectionMode,
    required this.animationDuration,
    required this.animationCurve,
  });

  final int totalCount;
  final int selectionCount;
  final int uploadingCount;
  final int failedCount;
  final int queuedCount;
  final bool selectionMode;
  final Duration animationDuration;
  final Curve animationCurve;

  @override
  Widget build(BuildContext context) {
    return _GallerySectionContainer(
      animationDuration: animationDuration,
      animationCurve: animationCurve,
      highlight: selectionMode,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _GalleryMetricChip(
            icon: Icons.photo_library_outlined,
            label: 'Total photos',
            value: totalCount,
            animationDuration: animationDuration,
            animationCurve: animationCurve,
            emphasize: true,
          ),
          _GalleryMetricChip(
            icon: Icons.check_circle_outline,
            label: 'Selected',
            value: selectionCount,
            animationDuration: animationDuration,
            animationCurve: animationCurve,
            highlightWhenActive: true,
          ),
          _GalleryMetricChip(
            icon: Icons.cloud_upload_outlined,
            label: 'Uploading',
            value: uploadingCount,
            animationDuration: animationDuration,
            animationCurve: animationCurve,
            highlightWhenActive: true,
          ),
          _GalleryMetricChip(
            icon: Icons.error_outline,
            label: 'Failed',
            value: failedCount,
            animationDuration: animationDuration,
            animationCurve: animationCurve,
            highlightWhenActive: true,
          ),
          _GalleryMetricChip(
            icon: Icons.queue_outlined,
            label: 'Queued',
            value: queuedCount,
            animationDuration: animationDuration,
            animationCurve: animationCurve,
            highlightWhenActive: true,
          ),
        ],
      ),
    );
  }
}

class _GalleryMetricChip extends StatelessWidget {
  const _GalleryMetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.animationDuration,
    required this.animationCurve,
    this.emphasize = false,
    this.highlightWhenActive = false,
  });

  final IconData icon;
  final String label;
  final int value;
  final Duration animationDuration;
  final Curve animationCurve;
  final bool emphasize;
  final bool highlightWhenActive;

  String get _formattedValue {
    if (value >= 1000) {
      final double inThousands = value / 1000.0;
      if (value >= 10000) {
        return '${inThousands.toStringAsFixed(0)}K';
      }
      return '${inThousands.toStringAsFixed(1)}K';
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isActive = highlightWhenActive && value > 0;

    final baseColor = colorScheme.surfaceVariant.withOpacity(0.38);
    final highlightColor = colorScheme.primaryContainer.withOpacity(0.78);
    final background = emphasize
        ? Color.lerp(baseColor, highlightColor, 0.35) ?? highlightColor
        : isActive
        ? Color.lerp(baseColor, highlightColor, 0.45) ?? highlightColor
        : baseColor;

    final borderColor = isActive || emphasize
        ? colorScheme.primary.withOpacity(0.28)
        : colorScheme.outlineVariant.withOpacity(0.22);
    final foreground = isActive || emphasize
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant.withOpacity(0.9);

    return AnimatedContainer(
      duration: animationDuration,
      curve: animationCurve,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: background,
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(
              isActive || emphasize ? 0.12 : 0.06,
            ),
            blurRadius: isActive || emphasize ? 22 : 14,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: animationDuration,
                curve: animationCurve,
                style:
                    theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ) ??
                    TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                child: Text(_formattedValue),
              ),
              AnimatedDefaultTextStyle(
                duration: animationDuration,
                curve: animationCurve,
                style:
                    theme.textTheme.labelMedium?.copyWith(
                      color: foreground.withOpacity(0.8),
                      letterSpacing: 0.1,
                    ) ??
                    TextStyle(color: foreground.withOpacity(0.8), fontSize: 12),
                child: Text(label),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GallerySectionContainer extends StatelessWidget {
  const _GallerySectionContainer({
    required this.child,
    required this.animationDuration,
    required this.animationCurve,
    this.highlight = false,
  });

  final Widget child;
  final Duration animationDuration;
  final Curve animationCurve;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surface.withOpacity(0.82);
    final highlightColor = theme.colorScheme.primaryContainer.withOpacity(0.74);
    final backgroundColor = highlight
        ? Color.lerp(baseColor, highlightColor, 0.35) ?? highlightColor
        : baseColor;

    final borderColor = highlight
        ? theme.colorScheme.primary.withOpacity(0.24)
        : theme.colorScheme.outlineVariant.withOpacity(0.24);

    return AnimatedContainer(
      duration: animationDuration,
      curve: animationCurve,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: backgroundColor,
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.08),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _GalleryEndOfListMessage extends StatelessWidget {
  const _GalleryEndOfListMessage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.auto_awesome_outlined,
          size: 28,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 8),
        Text(
          'You’ve reached the end',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Add more memories or pull to refresh to keep things in sync.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
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
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
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
                          color: Colors.white.withOpacity(0.85),
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
      image: CachedThumbnailImageProvider(
        asset!,
        size: const ThumbnailSize.square(1200),
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
          color: Colors.white.withOpacity(enabled ? 0.18 : 0.08),
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                icon,
                color: Colors.white.withOpacity(enabled ? 1 : 0.4),
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

class _DateRange {
  const _DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

class _BulkSelectPreset {
  const _BulkSelectPreset({
    required this.label,
    required this.description,
    required this.computeRange,
  });

  final String label;
  final String description;
  final _DateRange Function(DateTime now) computeRange;
}

abstract class _SelectionAction {
  const _SelectionAction();
}

class _SelectionActionSelectPreset extends _SelectionAction {
  const _SelectionActionSelectPreset(this.preset);

  final _BulkSelectPreset preset;
}

class _SelectionActionRemoveFromSync extends _SelectionAction {
  const _SelectionActionRemoveFromSync();
}

class _SelectionActionRetryFailed extends _SelectionAction {
  const _SelectionActionRetryFailed();
}
