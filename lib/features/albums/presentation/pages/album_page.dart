import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../gallery/presentation/util/cached_thumbnail_image_provider.dart';

import '../../../gallery/presentation/widgets/gallery_permission_prompt.dart';
import '../widgets/album_empty_state.dart';
import 'album_detail_page.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key});

  static const String routeName = '/albums';

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 8;
  static const Duration _microAnimationDuration = Duration(milliseconds: 220);
  static const Curve _microAnimationCurve = Curves.easeOutCubic;
  static const Duration _tileStaggerDelay = Duration(milliseconds: 45);

  late final AnimationController _backgroundController;

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
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
    _scrollController = ScrollController()..addListener(_onScroll);
    _loadAlbums(reset: true);
  }

  @override
  void dispose() {
    _backgroundController.dispose();
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
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
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
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            sliver: SliverToBoxAdapter(
              child: _AlbumsHeader(
                personalCount: _allPersonalAlbums.length,
                sharedCount: _allSharedAlbums.length,
                isSyncEnabled: _cloudSyncEnabled,
                isEmpty: _personalAlbums.isEmpty && _sharedAlbums.isEmpty,
                animationDuration: _microAnimationDuration,
                animationCurve: _microAnimationCurve,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
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
                    highlight: false,
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
                      highlight: true,
                    ),
                  ),
                if (_personalAlbums.isEmpty && _sharedAlbums.isEmpty)
                  _SectionContainer(
                    animationDuration: _microAnimationDuration,
                    animationCurve: _microAnimationCurve,
                    highlight: true,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: AlbumEmptyState(),
                    ),
                  ),
                const SizedBox(height: 28),
                _SectionContainer(
                  animationDuration: _microAnimationDuration,
                  animationCurve: _microAnimationCurve,
                  highlight: _cloudSyncEnabled,
                  child: _CloudSyncToggle(
                    value: _cloudSyncEnabled,
                    onChanged: _toggleCloudSync,
                    animationDuration: _microAnimationDuration,
                    animationCurve: _microAnimationCurve,
                  ),
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
                  : !_hasMoreAlbums &&
                          (_personalAlbums.isNotEmpty ||
                              _sharedAlbums.isNotEmpty)
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: _EndOfListMessage(),
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
    required this.highlight,
    this.onAlbumTap,
  });

  final String title;
  final List<_AlbumInfo> albums;
  final ValueChanged<_AlbumInfo>? onAlbumTap;
  final Duration animationDuration;
  final Curve animationCurve;
  final Duration tileStaggerDelay;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return AnimatedSize(
      duration: animationDuration,
      curve: animationCurve,
      child: _SectionContainer(
        animationDuration: animationDuration,
        animationCurve: animationCurve,
        highlight: highlight,
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
                  crossAxisSpacing: 18,
                  mainAxisSpacing: 18,
                  childAspectRatio: 3 / 3.55,
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
        image: CachedThumbnailImageProvider(
          widget.album.cover!,
          size: const ThumbnailSize.square(600),
        ),
        fit: BoxFit.cover,
      );
    }

    final metadataBadge = _AlbumCountBadge(
      count: widget.album.assetCount,
      animationDuration: widget.animationDuration,
      animationCurve: widget.animationCurve,
    );

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
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: widget.animationDuration,
              switchInCurve: widget.animationCurve,
              switchOutCurve: Curves.easeInCubic,
              child: coverContent,
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.35),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: metadataBadge,
            ),
          ],
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

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: cover),
        const SizedBox(height: 14),
        AnimatedDefaultTextStyle(
          duration: widget.animationDuration,
          curve: widget.animationCurve,
          style: titleStyle ?? const TextStyle(),
          child: Text(widget.album.name),
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
        ? theme.colorScheme.primaryContainer.withOpacity(0.9)
        : theme.colorScheme.surfaceContainerHighest.withOpacity(0.9);
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

class _AlbumsHeader extends StatelessWidget {
  const _AlbumsHeader({
    required this.personalCount,
    required this.sharedCount,
    required this.isSyncEnabled,
    required this.isEmpty,
    required this.animationDuration,
    required this.animationCurve,
  });

  final int personalCount;
  final int sharedCount;
  final bool isSyncEnabled;
  final bool isEmpty;
  final Duration animationDuration;
  final Curve animationCurve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalAlbums = personalCount + sharedCount;

    final headlineStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    );

    final description = totalAlbums == 0
        ? 'Curate vibrant collections by grouping the memories you love.'
        : 'Browse ${totalAlbums == 1 ? 'your album' : 'your $totalAlbums albums'} and relive the highlights.';

    final chips = [
      _AlbumsMetricChip(
        icon: Icons.person_outline,
        label: 'Personal',
        value: personalCount,
        animationDuration: animationDuration,
        animationCurve: animationCurve,
        highlight: personalCount > 0,
      ),
      _AlbumsMetricChip(
        icon: Icons.groups_outlined,
        label: 'Shared',
        value: sharedCount,
        animationDuration: animationDuration,
        animationCurve: animationCurve,
        highlight: sharedCount > 0,
      ),
      _AlbumsMetricChip(
        icon: isSyncEnabled
            ? Icons.cloud_done_rounded
            : Icons.cloud_off_outlined,
        label: isSyncEnabled ? 'Sync on' : 'Sync paused',
        value: null,
        animationDuration: animationDuration,
        animationCurve: animationCurve,
        highlight: isSyncEnabled,
      ),
    ];

    return _SectionContainer(
      animationDuration: animationDuration,
      animationCurve: animationCurve,
      highlight: !isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedDefaultTextStyle(
            duration: animationDuration,
            curve: animationCurve,
            style: headlineStyle ?? const TextStyle(),
            child: const Text('Albums'),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: animationDuration,
            switchInCurve: animationCurve,
            switchOutCurve: Curves.easeInCubic,
            child: Text(
              description,
              key: ValueKey(description),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: chips,
          ),
        ],
      ),
    );
  }
}

class _AlbumsMetricChip extends StatelessWidget {
  const _AlbumsMetricChip({
    required this.icon,
    required this.label,
    required this.animationDuration,
    required this.animationCurve,
    this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final int? value;
  final Duration animationDuration;
  final Curve animationCurve;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayValue = value == null
        ? label
        : value == 0
            ? 'None yet'
            : '$value';

    final backgroundColor = highlight
        ? theme.colorScheme.primaryContainer.withOpacity(0.9)
        : theme.colorScheme.surfaceContainerHighest.withOpacity(0.85);
    final foregroundColor = highlight
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.94, end: 1),
      duration: animationDuration,
      curve: animationCurve,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: AnimatedContainer(
        duration: animationDuration,
        curve: animationCurve,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: foregroundColor.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: foregroundColor,
            ),
            const SizedBox(width: 8),
            AnimatedDefaultTextStyle(
              duration: animationDuration,
              curve: animationCurve,
              style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: foregroundColor,
                  ) ??
                  TextStyle(color: foregroundColor),
              child: Text(displayValue),
            ),
            if (value != null && value! > 0) ...[
              const SizedBox(width: 8),
              AnimatedDefaultTextStyle(
                duration: animationDuration,
                curve: animationCurve,
                style: theme.textTheme.labelSmall?.copyWith(
                      color: foregroundColor.withOpacity(0.8),
                    ) ??
                    TextStyle(color: foregroundColor.withOpacity(0.8)),
                child: Text(label),
              ),
            ] else ...[
              const SizedBox(width: 8),
              AnimatedDefaultTextStyle(
                duration: animationDuration,
                curve: animationCurve,
                style: theme.textTheme.labelSmall?.copyWith(
                      color: foregroundColor.withOpacity(0.65),
                    ) ??
                    TextStyle(color: foregroundColor.withOpacity(0.65)),
                child: Text(label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionContainer extends StatelessWidget {
  const _SectionContainer({
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
    final highlightColor = theme.colorScheme.primaryContainer.withOpacity(0.72);
    final backgroundColor = highlight
        ? Color.lerp(baseColor, highlightColor, 0.35) ?? highlightColor
        : baseColor;

    final borderColor = highlight
        ? theme.colorScheme.primary.withOpacity(0.22)
        : theme.colorScheme.outlineVariant.withOpacity(0.22);

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

class _AlbumCountBadge extends StatelessWidget {
  const _AlbumCountBadge({
    required this.count,
    required this.animationDuration,
    required this.animationCurve,
  });

  final int? count;
  final Duration animationDuration;
  final Curve animationCurve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = count == null
        ? 'Loading…'
        : '${count!} ${count == 1 ? 'photo' : 'photos'}';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1),
      duration: animationDuration,
      curve: animationCurve,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: AnimatedContainer(
        duration: animationDuration,
        curve: animationCurve,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_rounded,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            AnimatedDefaultTextStyle(
              duration: animationDuration,
              curve: animationCurve,
              style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ) ??
                  theme.textTheme.labelLarge ?? const TextStyle(),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

class _EndOfListMessage extends StatelessWidget {
  const _EndOfListMessage();

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
          'You’re all caught up',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Keep capturing memories to see them appear here.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
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
