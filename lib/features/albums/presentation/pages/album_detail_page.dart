import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../../auth/data/models/photo_media.dart';
import '../../../auth/data/services/auth_service.dart';
import 'package:flutter_cloud_sync_photos/core/network/api_exception.dart';
import '../../../gallery/data/services/upload_metadata_store.dart';
import '../../../gallery/presentation/pages/photo_detail_page.dart';
import '../../../gallery/presentation/widgets/gallery_section_list.dart';
import '../../../settings/data/upload_preferences_store.dart';

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
  bool _isUploading = false;

  int _nextPage = 0;

  final ScrollController _scrollController = ScrollController();
  final UploadMetadataStore _metadataStore = UploadMetadataStore();
  final UploadPreferencesStore _uploadPreferences = uploadPreferencesStore;

  List<AssetEntity> _assets = const [];
  List<GallerySection> _sections = const [];
  int? _assetCount;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _assetCount = widget.initialCount;
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

  Future<void> _uploadAsset(AssetEntity asset) async {
    if (_isUploading) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    final alreadyUploaded = await _metadataStore.isUploaded(asset.id);
    if (!mounted) {
      return;
    }
    if (alreadyUploaded) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Photo already uploaded')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    final preferences = await _uploadPreferences.load();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(content: Text('Uploading photo...')));

    try {
      Uint8List? bytes = await asset.originBytes;
      bytes ??= await asset.thumbnailDataWithSize(
        const ThumbnailSize.square(1200),
      );

      if (bytes == null) {
        throw ApiException(message: 'Unable to read photo data');
      }

      final Uint8List uploadBytes = bytes;

      final rawTitle = await asset.titleAsync;
      final trimmed = rawTitle.trim();
      final sanitizedName = trimmed.isEmpty ? 'photo_${asset.id}.jpg' : trimmed;

      final folder = globalAuthService.buildFolderPath(
        PhotoMedia(bucketDisplayName: widget.title),
      );

      final response = await globalAuthService.uploadFile(
        fileName: sanitizedName,
        bytes: uploadBytes,
        isPrivate: preferences.isPrivate,
        folder: folder,
        optimize: preferences.optimize,
      );
      final contentHash = _findContentHash(response);
      if (contentHash != null) {
        await _metadataStore.saveContentHash(asset.id, contentHash);
      }

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
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                tooltip: 'Back',
                              ),
                              const Spacer(),
                              if (_isUploading)
                                const _GlassProgressIndicator()
                              else
                                _GlassIconButton(
                                  icon: Icons.cloud_upload_outlined,
                                  tooltip: 'How do uploads work?',
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
      onAssetTap: _openAsset,
      onAssetLongPress: _uploadAsset,
      onAssetUpload: _uploadAsset,
    );
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
          color: Colors.white.withValues(alpha: 0.18),
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
                        color: Colors.white.withValues(alpha: 0.85),
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
