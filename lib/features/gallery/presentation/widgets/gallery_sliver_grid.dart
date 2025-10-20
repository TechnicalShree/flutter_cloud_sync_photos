import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

class GallerySliverGrid extends StatelessWidget {
  const GallerySliverGrid({super.key, required this.assets, this.onAssetTap});

  final List<AssetEntity> assets;
  final ValueChanged<AssetEntity>? onAssetTap;

  static const _gridSpacing = 12.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: _gridSpacing,
        crossAxisSpacing: _gridSpacing,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final asset = assets[index];
        return GalleryTile(
          asset: asset,
          theme: theme,
          onTap: () => onAssetTap?.call(asset),
        );
      }, childCount: assets.length),
    );
  }
}

class GalleryTile extends StatelessWidget {
  const GalleryTile({
    super.key,
    required this.asset,
    required this.theme,
    this.onTap,
  });

  final AssetEntity asset;
  final ThemeData theme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: asset.id,
              child: Image(
                image: AssetEntityImageProvider(
                  asset,
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize.square(400),
                ),
                fit: BoxFit.cover,
              ),
            ),
            _GradientOverlay(theme: theme),
            if (asset.isFavorite)
              const Positioned(
                top: 8,
                right: 8,
                child: Icon(Icons.favorite, size: 20, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

class _GradientOverlay extends StatelessWidget {
  const _GradientOverlay({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              theme.colorScheme.scrim.withValues(alpha: 0.4),
            ],
          ),
        ),
      ),
    );
  }
}
