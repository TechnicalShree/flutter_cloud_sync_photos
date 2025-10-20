import 'dart:async';

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
  bool _isLoading = true;
  bool _hasPermission = false;
  bool _isLoadingMore = false;
  bool _cloudSyncEnabled = false;

  PermissionState? _permissionState;
  List<_AlbumInfo> _personalAlbums = const [];
  List<_AlbumInfo> _sharedAlbums = const [];

  @override
  void initState() {
    super.initState();
    _loadAlbums(reset: true);
  }

  Future<void> _loadAlbums({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
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

      final limited = populated.take(8).toList();
      final personalPaths = limited.take(4).toList();
      final sharedPaths = limited.skip(4).take(4).toList();

      final personalAlbums = await Future.wait(
        personalPaths.map(_buildAlbumInfo),
      );
      final sharedAlbums = await Future.wait(sharedPaths.map(_buildAlbumInfo));

      if (!mounted) {
        return;
      }

      setState(() {
        _personalAlbums = personalAlbums;
        _sharedAlbums = sharedAlbums;
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
          child: _buildContent(theme),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_isLoading) {
      return const _AlbumsLoading();
    }

    if (!_hasPermission) {
      return GalleryPermissionPrompt(
        permissionState: _permissionState,
        onRequestPermission: () => _loadAlbums(reset: true),
        onRetry: () => _loadAlbums(reset: true),
      );
    }

    return CustomScrollView(
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
                  ),
                ),
              const SizedBox(height: 28),
              _CloudSyncToggle(
                value: _cloudSyncEnabled,
                onChanged: _toggleCloudSync,
              ),
            ],
          ),
        ),
        if (_isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
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
    );
  }
}

class _AlbumsLoading extends StatelessWidget {
  const _AlbumsLoading();

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
    this.onAlbumTap,
  });

  final String title;
  final List<_AlbumInfo> albums;
  final ValueChanged<_AlbumInfo>? onAlbumTap;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
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
            return _AlbumTile(album: album, onTap: onAlbumTap);
          },
        ),
      ],
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.album, this.onTap});

  final _AlbumInfo album;
  final ValueChanged<_AlbumInfo>? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canTap = album.path != null;
    final heroTag = canTap ? 'album-${album.id}' : null;

    Widget cover = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: album.cover == null
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.secondaryContainer,
                  ],
                )
              : null,
        ),
        child: album.cover == null
            ? Icon(
                Icons.photo_library_outlined,
                size: 48,
                color: theme.colorScheme.onPrimaryContainer,
              )
            : Image(
                image: AssetEntityImageProvider(
                  album.cover!,
                  thumbnailSize: const ThumbnailSize.square(600),
                  isOriginal: false,
                ),
                fit: BoxFit.cover,
              ),
      ),
    );

    if (heroTag != null) {
      cover = Hero(tag: heroTag, child: cover);
    }

    return GestureDetector(
      onTap: canTap ? () => onTap?.call(album) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: cover),
          const SizedBox(height: 12),
          Text(
            album.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            album.assetCount == null
                ? '—'
                : '${album.assetCount} ${album.assetCount == 1 ? "photo" : "photos"}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudSyncToggle extends StatelessWidget {
  const _CloudSyncToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enable Cloud Sync',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sync all albums automatically.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
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
