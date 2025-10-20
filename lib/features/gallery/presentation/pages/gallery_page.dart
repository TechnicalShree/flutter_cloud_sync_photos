import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

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
    });
  }

  Future<void> _handleRefresh() async {
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PhotoDetailPage(asset: asset)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
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
                    'Gallery',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _isLoading ? null : () => _handleRefresh(),
                      icon: const Icon(Icons.refresh),
                    ),
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

    return GallerySectionList(sections: _sections, onAssetTap: _handleAssetTap);
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
