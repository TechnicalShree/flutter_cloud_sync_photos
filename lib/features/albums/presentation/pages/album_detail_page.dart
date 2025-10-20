import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

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

  int _nextPage = 0;

  final ScrollController _scrollController = ScrollController();

  List<AssetEntity> _assets = const [];
  List<GallerySection> _sections = const [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadAssets(reset: true);
  }

  @override
  void dispose() {
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

  Future<void> _handleRefresh() async {
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

  void _openAsset(AssetEntity asset) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PhotoDetailPage(asset: asset)));
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
              expandedHeight: 240,
              pinned: true,
              backgroundColor: Colors.black,
              title: Text(widget.title),
              flexibleSpace: FlexibleSpaceBar(
                background: _AlbumCover(
                  cover: widget.cover,
                  heroTag: widget.heroTag,
                ),
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

    return GallerySectionList(sections: _sections, onAssetTap: _openAsset);
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
        image: AssetEntityImageProvider(
          cover!,
          thumbnailSize: const ThumbnailSize.square(1200),
          isOriginal: false,
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
