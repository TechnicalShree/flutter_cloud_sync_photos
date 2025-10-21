import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../../gallery/presentation/widgets/gallery_permission_prompt.dart';
import 'album_detail_page.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key});

  static const String routeName = '/albums';

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  static const int _pageSize = 8;
  static const Duration _microAnimationDuration = Duration(milliseconds: 220);
  static const Curve _microAnimationCurve = Curves.easeOutCubic;
  static const Duration _tileStaggerDelay = Duration(milliseconds: 45);

  bool _isLoading = true;
  bool _hasPermission = false;
  bool _isLoadingMore = false;
  bool _cloudSyncEnabled = false;
  bool _hasMoreAlbums = false;

  PermissionState? _permissionState;
  List<_AlbumInfo> _personalAlbums = const [];
  List<_AlbumInfo> _sharedAlbums = const [];
  List<_AlbumInfo> _allPersonalAlbums = const [];
  List<_AlbumInfo> _allSharedAlbums = const [];
  int _personalDisplayCount = 0;
  int _sharedDisplayCount = 0;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _loadAlbums(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAlbums({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _allPersonalAlbums = const [];
        _allSharedAlbums = const [];
        _personalDisplayCount = 0;
        _sharedDisplayCount = 0;
        _hasMoreAlbums = false;
      });
    }

    final permission = await PhotoManager.requestPermissionExtend();
    if (!mounted) {
      return;
    }

    final isAuthorized = permission.isAuth || permission.hasAccess;
    if (!isAuthorized) {
      setState(() {
        _permissionState = permission;
        _isLoading = false;
        _hasPermission = false;
        _personalAlbums = const [];
        _sharedAlbums = const [];
        _allPersonalAlbums = const [];
        _allSharedAlbums = const [];
        _hasMoreAlbums = false;
      });
      return;
    }

    _permissionState = permission;
    _hasPermission = true;

    try {
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        filterOption: FilterOptionGroup(
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        ),
      );

      final populated = <AssetPathEntity>[];
      for (final path in paths) {
        final count = await path.assetCountAsync;
        if (count > 0) {
          populated.add(path);
        }
      }

      final personalPaths = <AssetPathEntity>[];
      final sharedPaths = <AssetPathEntity>[];

      for (final path in populated) {
        if (_isSharedAlbum(path)) {
          sharedPaths.add(path);
        } else {
          personalPaths.add(path);
        }
      }

      final personalAlbums = await Future.wait(
        personalPaths.map(_buildAlbumInfo),
      );
      final sharedAlbums = await Future.wait(
        sharedPaths.map(_buildAlbumInfo),
      );

      final personalDisplayCount =
          math.min(_pageSize, personalAlbums.length);
      final sharedDisplayCount = math.min(_pageSize, sharedAlbums.length);

      if (!mounted) {
        return;
      }

      setState(() {
        _allPersonalAlbums = personalAlbums;
        _allSharedAlbums = sharedAlbums;
        _personalDisplayCount = personalDisplayCount;
        _sharedDisplayCount = sharedDisplayCount;
        _personalAlbums =
            personalAlbums.take(personalDisplayCount).toList(growable: false);
        _sharedAlbums =
            sharedAlbums.take(sharedDisplayCount).toList(growable: false);
        _isLoading = false;
        _isLoadingMore = false;
        _hasMoreAlbums = personalDisplayCount < personalAlbums.length ||
            sharedDisplayCount < sharedAlbums.length;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _hasMoreAlbums = false;
      });
    }
  }

  Future<_AlbumInfo> _buildAlbumInfo(AssetPathEntity path) async {
    final count = await path.assetCountAsync;
    final coverAssets = await path.getAssetListRange(start: 0, end: 1);
    final cover = coverAssets.isNotEmpty ? coverAssets.first : null;

    return _AlbumInfo(
      id: path.id,
      name: path.name,
      assetCount: count,
      cover: cover,
      path: path,
    );
  }

  Future<void> _handleRefresh() => _loadAlbums(reset: true);

  void _onScroll() {
    if (!_hasMoreAlbums || _isLoadingMore || _isLoading) {
      return;
    }
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMoreAlbums();
    }
  }

  void _loadMoreAlbums() {
    if (!_hasMoreAlbums || _isLoadingMore) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    Future<void>.microtask(() {
      if (!mounted) {
        return;
      }

      final nextPersonalCount = math.min(
        _personalDisplayCount + _pageSize,
        _allPersonalAlbums.length,
      );
      final nextSharedCount = math.min(
        _sharedDisplayCount + _pageSize,
        _allSharedAlbums.length,
      );

      setState(() {
        _personalDisplayCount = nextPersonalCount;
        _sharedDisplayCount = nextSharedCount;
        _personalAlbums = _allPersonalAlbums
            .take(_personalDisplayCount)
            .toList(growable: false);
        _sharedAlbums = _allSharedAlbums
            .take(_sharedDisplayCount)
            .toList(growable: false);
        _isLoadingMore = false;
        _hasMoreAlbums =
            _personalDisplayCount < _allPersonalAlbums.length ||
                _sharedDisplayCount < _allSharedAlbums.length;
      });
    });
  }

  bool _isSharedAlbum(AssetPathEntity path) {
    final subtype = path.albumTypeEx?.darwin?.subtype;
    if (subtype == PMDarwinAssetCollectionSubtype.albumCloudShared ||
        subtype == PMDarwinAssetCollectionSubtype.albumMyPhotoStream) {
      return true;
    }

    final name = path.name.toLowerCase();
    if (name.contains('shared')) {
      return true;
    }

    return false;
  }

  void _toggleCloudSync(bool value) {
    setState(() {
      _cloudSyncEnabled = value;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Cloud sync enabled. Albums will stay up to date.'
              : 'Cloud sync disabled.',
        ),
      ),
    );
  }

  void _openAlbum(_AlbumInfo album) {
    final path = album.path;
    if (path == null) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailPage(
          path: path,
          title: album.name,
          cover: album.cover,
          heroTag: 'album-${album.id}',
          initialCount: album.assetCount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          color: theme.colorScheme.primary,
          onRefresh: _handleRefresh,
          child: AnimatedSwitcher(
            duration: _microAnimationDuration,
            switchInCurve: _microAnimationCurve,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offsetAnimation = Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ));
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: offsetAnimation,
                  child: child,
                ),
              );
            },
            child: _buildContent(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_isLoading) {
      return const _AlbumsLoading(key: ValueKey('loading'));
    }

    if (!_hasPermission) {
      return KeyedSubtree(
        key: const ValueKey('permission'),
        child: GalleryPermissionPrompt(
          permissionState: _permissionState,
          onRequestPermission: () => _loadAlbums(reset: true),
          onRetry: () => _loadAlbums(reset: true),
        ),
      );
    }

    return KeyedSubtree(
      key: ValueKey('${_personalAlbums.length}-${_sharedAlbums.length}'),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            sliver: SliverList.list(
              children: [
                if (_personalAlbums.isNotEmpty)
                  _AlbumSection(
                    title: 'My Albums',
                    albums: _personalAlbums,
                    onAlbumTap: _openAlbum,
                    animationDuration: _microAnimationDuration,
                    animationCurve: _microAnimationCurve,
                    tileStaggerDelay: _tileStaggerDelay,
                  ),
                if (_sharedAlbums.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      top: _personalAlbums.isNotEmpty ? 24 : 0,
                    ),
                    child: _AlbumSection(
                      title: 'Shared Albums',
                      albums: _sharedAlbums,
                      onAlbumTap: _openAlbum,
                      animationDuration: _microAnimationDuration,
                      animationCurve: _microAnimationCurve,
                      tileStaggerDelay: _tileStaggerDelay,
                    ),
                  ),
                const SizedBox(height: 28),
                _CloudSyncToggle(
                  value: _cloudSyncEnabled,
                  onChanged: _toggleCloudSync,
                  animationDuration: _microAnimationDuration,
                  animationCurve: _microAnimationCurve,
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: _microAnimationDuration,
              switchInCurve: _microAnimationCurve,
              switchOutCurve: Curves.easeInCubic,
              child: _isLoadingMore
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumsLoading extends StatelessWidget {
  const _AlbumsLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Column(
            children: [
              SizedBox(
                height: 48,
                width: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading albums...',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlbumSection extends StatelessWidget {
  const _AlbumSection({
    required this.title,
    required this.albums,
    required this.animationDuration,
    required this.animationCurve,
    required this.tileStaggerDelay,
    this.onAlbumTap,
  });

  final String title;
  final List<_AlbumInfo> albums;
  final ValueChanged<_AlbumInfo>? onAlbumTap;
  final Duration animationDuration;
  final Curve animationCurve;
  final Duration tileStaggerDelay;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return AnimatedSize(
      duration: animationDuration,
      curve: animationCurve,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedDefaultTextStyle(
            duration: animationDuration,
            curve: animationCurve,
            style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ) ??
                const TextStyle(),
            child: Text(title),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: animationDuration,
            switchInCurve: animationCurve,
            switchOutCurve: Curves.easeInCubic,
            child: GridView.builder(
              key: ValueKey('$title-${albums.length}'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: albums.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 3 / 3.6,
              ),
              itemBuilder: (context, index) {
                final album = albums[index];
                final cappedIndex = math.min(index, 6);
                final delay = Duration(
                  milliseconds:
                      tileStaggerDelay.inMilliseconds * cappedIndex,
                );
                return _AlbumTile(
                  key: ValueKey(album.id),
                  album: album,
                  onTap: onAlbumTap,
                  animationDuration: animationDuration,
                  animationCurve: animationCurve,
                  entryDelay: delay,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumTile extends StatefulWidget {
  const _AlbumTile({
    super.key,
    required this.album,
    required this.animationDuration,
    required this.animationCurve,
    required this.entryDelay,
    this.onTap,
  });

  final _AlbumInfo album;
  final ValueChanged<_AlbumInfo>? onTap;
  final Duration animationDuration;
  final Curve animationCurve;
  final Duration entryDelay;

  @override
  State<_AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<_AlbumTile> {
  bool _hovering = false;
  bool _pressed = false;
  bool _animateIn = false;
  Timer? _entryTimer;

  @override
  void initState() {
    super.initState();
    _entryTimer = Timer(widget.entryDelay, _triggerEntryAnimation);
  }

  @override
  void didUpdateWidget(covariant _AlbumTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.album.id != oldWidget.album.id) {
      _entryTimer?.cancel();
      _animateIn = false;
      _entryTimer = Timer(widget.entryDelay, _triggerEntryAnimation);
      return;
    }

    if (widget.entryDelay != oldWidget.entryDelay && !_animateIn) {
      _entryTimer?.cancel();
      _entryTimer = Timer(widget.entryDelay, _triggerEntryAnimation);
    }
  }

  @override
  void dispose() {
    _entryTimer?.cancel();
    super.dispose();
  }

  void _triggerEntryAnimation() {
    if (!mounted) {
      return;
    }
    setState(() {
      _animateIn = true;
    });
  }

  void _setHovering(bool hovering) {
    if (_hovering == hovering) {
      return;
    }
    setState(() => _hovering = hovering);
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canTap = widget.album.path != null;
    final heroTag = canTap ? 'album-${widget.album.id}' : null;

    final entryOffset = _animateIn ? Offset.zero : const Offset(0, 0.06);
    final entryOpacity = _animateIn ? 1.0 : 0.0;

    final currentScale = _pressed
        ? 0.96
        : _hovering
            ? 0.98
            : 1.0;

    Widget coverContent;
    if (widget.album.cover == null) {
      coverContent = DecoratedBox(
        key: const ValueKey('placeholder'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.secondaryContainer,
            ],
          ),
        ),
        child: Icon(
          Icons.photo_library_outlined,
          size: 48,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      );
    } else {
      coverContent = Image(
        key: ValueKey(widget.album.cover?.id ?? widget.album.id),
        image: AssetEntityImageProvider(
          widget.album.cover!,
          thumbnailSize: const ThumbnailSize.square(600),
          isOriginal: false,
        ),
        fit: BoxFit.cover,
      );
    }

    Widget cover = AnimatedContainer(
      duration: widget.animationDuration,
      curve: widget.animationCurve,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: _hovering || _pressed
            ? [
                BoxShadow(
                  color: theme.colorScheme.shadow.withOpacity(0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AnimatedSwitcher(
          duration: widget.animationDuration,
          switchInCurve: widget.animationCurve,
          switchOutCurve: Curves.easeInCubic,
          child: coverContent,
        ),
      ),
    );

    if (heroTag != null) {
      cover = Hero(tag: heroTag, child: cover);
    }

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: _hovering
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurface,
    );

    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: cover),
        const SizedBox(height: 12),
        AnimatedDefaultTextStyle(
          duration: widget.animationDuration,
          curve: widget.animationCurve,
          style: titleStyle ?? const TextStyle(),
          child: Text(widget.album.name),
        ),
        AnimatedDefaultTextStyle(
          duration: widget.animationDuration,
          curve: widget.animationCurve,
          style: subtitleStyle ?? const TextStyle(),
          child: Text(
            widget.album.assetCount == null
                ? '—'
                : '${widget.album.assetCount} ${widget.album.assetCount == 1 ? "photo" : "photos"}',
          ),
        ),
      ],
    );

    content = AnimatedPadding(
      duration: widget.animationDuration,
      curve: widget.animationCurve,
      padding: EdgeInsets.only(top: _hovering ? 4 : 0),
      child: content,
    );

    final interactiveTile = MouseRegion(
      onEnter: (_) => _setHovering(true),
      onExit: (_) {
        _setHovering(false);
        _setPressed(false);
      },
      child: GestureDetector(
        onTapDown: canTap ? (_) => _setPressed(true) : null,
        onTapUp: canTap
            ? (_) {
                _setPressed(false);
                widget.onTap?.call(widget.album);
              }
            : null,
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: currentScale,
          duration: widget.animationDuration,
          curve: widget.animationCurve,
          child: content,
        ),
      ),
    );

    return AnimatedOpacity(
      opacity: entryOpacity,
      duration: widget.animationDuration,
      curve: widget.animationCurve,
      child: AnimatedSlide(
        offset: entryOffset,
        duration: widget.animationDuration,
        curve: widget.animationCurve,
        child: interactiveTile,
      ),
    );
  }
}

class _CloudSyncToggle extends StatelessWidget {
  const _CloudSyncToggle({
    required this.value,
    required this.onChanged,
    required this.animationDuration,
    required this.animationCurve,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Duration animationDuration;
  final Curve animationCurve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = value
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final iconColor = value
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: animationDuration,
      curve: animationCurve,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: value
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
              ]
            : const [],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: animationDuration,
                  curve: animationCurve,
                  style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: value
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      ) ??
                      const TextStyle(),
                  child: const Text('Enable Cloud Sync'),
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: animationDuration,
                  curve: animationCurve,
                  style: theme.textTheme.bodyMedium?.copyWith(
                        color: value
                            ? theme.colorScheme.onPrimaryContainer
                                .withOpacity(0.8)
                            : theme.colorScheme.onSurfaceVariant,
                      ) ??
                      const TextStyle(),
                  child: const Text('Sync all albums automatically.'),
                ),
              ],
            ),
          ),
          AnimatedScale(
            scale: value ? 1.05 : 1,
            duration: animationDuration,
            curve: animationCurve,
            child: Switch.adaptive(
              value: value,
              activeColor: iconColor,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumInfo {
  const _AlbumInfo({
    required this.id,
    required this.name,
    required this.assetCount,
    required this.cover,
    required this.path,
  });

  final String id;
  final String name;
  final int? assetCount;
  final AssetEntity? cover;
  final AssetPathEntity? path;
}
