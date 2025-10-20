import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_cloud_sync_photos/core/network/api_exception.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../auth/data/models/photo_media.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../data/services/upload_metadata_store.dart';
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
  bool _isUploading = false;
  bool _selectionMode = false;

  final UploadMetadataStore _metadataStore = UploadMetadataStore();
  final Set<String> _selectedAssetIds = <String>{};

  List<AssetEntity> _assets = const <AssetEntity>[];
  List<GallerySection> _sections = const <GallerySection>[];
  PermissionState? _permissionState;
  AssetPathEntity? _assetPath;
  int _nextPage = 0;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _initializeGallery(reset: true);
  }

  @override
  void dispose() {
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
    if (_isUploading) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isUploading = true;
    });

    try {
      final alreadyUploaded = await _metadataStore.isUploaded(asset.id);
      if (alreadyUploaded) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text('Photo already uploaded')),
        );
        return;
      }

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Uploading photo...')),
      );

      await _performUpload(asset);

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Upload complete')));
    } on ApiException catch (error) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Upload failed')));
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _uploadSelectedAssets() async {
    if (_selectedAssetIds.isEmpty || _isUploading) {
      return;
    }

    final assets = _getSelectedAssets();
    if (assets.isEmpty) {
      _clearSelection();
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isUploading = true;
    });

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          assets.length == 1
              ? 'Uploading 1 photo...'
              : 'Uploading ${assets.length} photos...',
        ),
      ),
    );

    int uploadedCount = 0;
    int skippedCount = 0;
    int failedCount = 0;
    String? firstErrorMessage;

    try {
      for (final asset in assets) {
        final alreadyUploaded = await _metadataStore.isUploaded(asset.id);
        if (alreadyUploaded) {
          skippedCount += 1;
          continue;
        }

        try {
          await _performUpload(asset);
          uploadedCount += 1;
        } on ApiException catch (error) {
          failedCount += 1;
          firstErrorMessage ??= error.message;
        } catch (_) {
          failedCount += 1;
          firstErrorMessage ??= 'Upload failed';
        }
      }

      messenger.hideCurrentSnackBar();
      final message = _buildBulkResultMessage(
        total: assets.length,
        uploaded: uploadedCount,
        skipped: skippedCount,
        failed: failedCount,
      );
      messenger.showSnackBar(SnackBar(content: Text(message)));

      if (firstErrorMessage != null && failedCount > 0) {
        messenger.showSnackBar(SnackBar(content: Text(firstErrorMessage)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _selectedAssetIds.clear();
          _selectionMode = false;
        });
      }
    }
  }

  Future<void> _performUpload(AssetEntity asset) async {
    final bytes = await _loadAssetBytes(asset);

    final rawTitle = await asset.titleAsync;
    final trimmed = rawTitle.trim();
    final sanitizedName = trimmed.isEmpty ? 'photo_${asset.id}.jpg' : trimmed;

    final folder = globalAuthService.buildFolderPath(
      PhotoMedia(bucketDisplayName: _deriveBucketName(asset)),
    );

    final response = await globalAuthService.uploadFile(
      fileName: sanitizedName,
      bytes: bytes,
      isPrivate: true,
      folder: folder,
      optimize: false,
    );

    final contentHash = _findContentHash(response);
    if (contentHash != null) {
      await _metadataStore.saveContentHash(asset.id, contentHash);
    }
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

  String _buildBulkResultMessage({
    required int total,
    required int uploaded,
    required int skipped,
    required int failed,
  }) {
    final parts = <String>[];

    if (uploaded > 0) {
      parts.add('Uploaded $uploaded ${uploaded == 1 ? 'photo' : 'photos'}');
    }
    if (skipped > 0) {
      parts.add('$skipped already synced');
    }
    if (failed > 0) {
      parts.add('$failed failed');
    }

    if (parts.isEmpty) {
      return total == 0
          ? 'No photos selected for upload'
          : 'No photos were uploaded';
    }

    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
        backgroundColor: theme.colorScheme.surface,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.08),
                theme.colorScheme.surface,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: GalleryRefreshIndicator(
              onRefresh: _handleRefresh,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    titleSpacing: 24,
                    pinned: true,
                    title: Text(
                      _selectionMode
                          ? '${_selectedAssetIds.length} selected'
                          : 'Gallery',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    actions: [
                      if (_selectionMode) ...[
                        IconButton(
                          tooltip: 'Upload selected',
                          onPressed: _selectedAssetIds.isEmpty || _isUploading
                              ? null
                              : () => _uploadSelectedAssets(),
                          icon: const Icon(Icons.cloud_upload),
                        ),
                        IconButton(
                          tooltip: 'Clear selection',
                          onPressed: _isUploading ? null : _clearSelection,
                          icon: const Icon(Icons.close),
                        ),
                      ] else ...[
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: _isLoading ? null : () => _handleRefresh(),
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                      const SizedBox(width: 12),
                    ],
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
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
      hideSelectionIndicatorAssetIds: _selectionMode && _assets.isNotEmpty
          ? {_assets.first.id}
          : const <String>{},
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

  String? _deriveBucketName(AssetEntity asset) {
    final relativePath = asset.relativePath?.trim();
    if (relativePath != null && relativePath.isNotEmpty) {
      final sanitized = relativePath.replaceAll(RegExp(r'[\\/]+$'), '');
      final segments = sanitized.split(RegExp(r'[\\/]'));
      if (segments.isNotEmpty) {
        final last = segments.last.trim();
        if (last.isNotEmpty) {
          return last;
        }
      }
      return sanitized;
    }

    final pathName = _assetPath?.name;
    if (pathName != null && pathName.trim().isNotEmpty) {
      return pathName.trim();
    }

    return null;
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
