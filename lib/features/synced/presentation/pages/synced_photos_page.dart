import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_cloud_sync_photos/core/navigation/shared_axis_page_route.dart';
import 'package:flutter_cloud_sync_photos/features/gallery/data/services/upload_metadata_store.dart';
import 'package:flutter_cloud_sync_photos/features/gallery/presentation/pages/photo_detail_page.dart';
import 'package:flutter_cloud_sync_photos/features/gallery/presentation/widgets/gallery_permission_prompt.dart';
import 'package:flutter_cloud_sync_photos/features/gallery/presentation/widgets/gallery_refresh_indicator.dart';
import 'package:flutter_cloud_sync_photos/features/gallery/presentation/widgets/gallery_sliver_grid.dart';
import 'package:photo_manager/photo_manager.dart';

class SyncedPhotosPage extends StatefulWidget {
  const SyncedPhotosPage({super.key});

  @override
  State<SyncedPhotosPage> createState() => _SyncedPhotosPageState();
}

class _SyncedPhotosPageState extends State<SyncedPhotosPage> {
  final UploadMetadataStore _metadataStore = UploadMetadataStore();
  List<AssetEntity> _assets = const <AssetEntity>[];
  bool _isLoading = true;
  bool _hasPermission = false;
  PermissionState? _permissionState;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSyncedAssets(showLoadingIndicator: true));
  }

  Future<void> _loadSyncedAssets({bool showLoadingIndicator = false}) async {
    if (showLoadingIndicator) {
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
        _hasPermission = false;
        _assets = const <AssetEntity>[];
        _isLoading = false;
      });
      return;
    }

    final ids = await _metadataStore.getUploadedAssetIds();
    final assets = <AssetEntity>[];
    for (final id in ids) {
      final asset = await AssetEntity.fromId(id);
      if (asset != null) {
        assets.add(asset);
      }
    }

    assets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

    if (!mounted) {
      return;
    }

    setState(() {
      _permissionState = permission;
      _hasPermission = true;
      _assets = assets;
      _isLoading = false;
    });
  }

  Future<void> _handleRefresh() async {
    await _loadSyncedAssets();
  }

  Future<void> _requestPermission() async {
    await _loadSyncedAssets(showLoadingIndicator: true);
  }

  void _openAsset(AssetEntity asset) {
    Navigator.of(context).push(
      SharedAxisPageRoute(builder: (_) => PhotoDetailPage(asset: asset)),
    );
  }

  List<Widget> _buildSlivers(BuildContext context) {
    if (_isLoading) {
      return const <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (!_hasPermission) {
      return <Widget>[
        GalleryPermissionPrompt(
          permissionState: _permissionState,
          onRequestPermission: _requestPermission,
          onRetry: _requestPermission,
        ),
      ];
    }

    if (_assets.isEmpty) {
      return const <Widget>[
        _SyncedPhotosEmptyState(),
      ];
    }

    final theme = Theme.of(context);

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
        sliver: SliverToBoxAdapter(
          child: Text(
            'Synced photos',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      GallerySliverGrid(
        assets: _assets,
        metadataStore: _metadataStore,
        onAssetTap: _openAsset,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GalleryRefreshIndicator(
        onRefresh: _handleRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: _buildSlivers(context),
        ),
      ),
    );
  }
}

class _SyncedPhotosEmptyState extends StatelessWidget {
  const _SyncedPhotosEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_done_outlined,
              size: 72,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No synced photos yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Photos you upload will appear in this gallery.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
