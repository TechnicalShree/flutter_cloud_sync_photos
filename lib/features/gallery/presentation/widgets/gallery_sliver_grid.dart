import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../data/services/upload_metadata_store.dart';

const double _gridSpacing = 8.0;
const double _tileRadius = 12.0;

class GallerySliverGrid extends StatelessWidget {
  const GallerySliverGrid({
    super.key,
    required this.assets,
    required this.metadataStore,
    this.selectionMode = false,
    this.selectedAssetIds = const <String>{},
    this.uploadingAssetIds = const <String>{},
    this.hideSelectionIndicatorAssetIds = const <String>{},
    this.onAssetTap,
    this.onAssetLongPress,
    this.onAssetUpload,
  });

  final List<AssetEntity> assets;
  final UploadMetadataStore metadataStore;
  final bool selectionMode;
  final Set<String> selectedAssetIds;
  final Set<String> uploadingAssetIds;
  final Set<String> hideSelectionIndicatorAssetIds;
  final ValueChanged<AssetEntity>? onAssetTap;
  final ValueChanged<AssetEntity>? onAssetLongPress;
  final ValueChanged<AssetEntity>? onAssetUpload;

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
          metadataStore: metadataStore,
          selectionMode: selectionMode,
          isSelected: selectedAssetIds.contains(asset.id),
          isUploading: uploadingAssetIds.contains(asset.id),
          showSelectionIndicator: !hideSelectionIndicatorAssetIds.contains(
            asset.id,
          ),
          onTap: () => onAssetTap?.call(asset),
          onLongPress: () => onAssetLongPress?.call(asset),
          onUpload: onAssetUpload != null
              ? () => onAssetUpload?.call(asset)
              : null,
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
    required this.metadataStore,
    this.selectionMode = false,
    this.isSelected = false,
    this.isUploading = false,
    this.showSelectionIndicator = true,
    this.onTap,
    this.onLongPress,
    this.onUpload,
  });

  final AssetEntity asset;
  final ThemeData theme;
  final UploadMetadataStore metadataStore;
  final bool selectionMode;
  final bool isSelected;
  final bool isUploading;
  final bool showSelectionIndicator;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: metadataStore.isUploaded(asset.id),
      builder: (context, snapshot) {
        final isUploaded = snapshot.data ?? false;
        final uploading = isUploading;
        final isSelectable = !isUploaded && !uploading;
        final effectiveOnTap = selectionMode && !isSelectable ? null : onTap;
        final effectiveOnLongPress = isSelectable ? onLongPress : null;
        final showSelection = selectionMode &&
            showSelectionIndicator &&
            !isUploaded &&
            !uploading;

        return GestureDetector(
          onTap: effectiveOnTap,
          onLongPress: effectiveOnLongPress,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_tileRadius + 4),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.7),
                  theme.colorScheme.surface,
                ],
              ),
              border: Border.all(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_tileRadius),
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
                if (isSelected)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.26),
                      ),
                    ),
                  ),
                if (asset.isFavorite)
                  const Positioned(
                    top: 8,
                    left: 8,
                    child: Icon(Icons.favorite, size: 20, color: Colors.white),
                  ),
                if (uploading)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: _UploadProgressDot(),
                  )
                else if (showSelection)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _SelectionIndicator(selected: isSelected),
                  ),
                if (isUploaded)
                  const Positioned(bottom: 10, left: 10, child: _SyncedBadge()),
                if (!isUploaded && !selectionMode && onUpload != null && !uploading)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _GlassCircleButton(
                      icon: Icons.cloud_upload_outlined,
                      onPressed: onUpload!,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
              theme.colorScheme.scrim.withValues(alpha: 0.32),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

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
              width: 36,
              height: 36,
              child: Icon(icon, size: 18, color: Colors.white),
            ),
          ),
        ),
      ),
    );
    return Tooltip(message: 'Upload', child: button);
  }
}

class _UploadProgressDot extends StatelessWidget {
  const _UploadProgressDot();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 26,
      height: 26,
      child: CircularProgressIndicator(
        strokeWidth: 2.4,
        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
        backgroundColor: Colors.white.withValues(alpha: 0.4),
      ),
    );
  }
}

class _SyncedBadge extends StatelessWidget {
  const _SyncedBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Already synced',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.check_circle, size: 14, color: Colors.white),
              SizedBox(width: 4),
              Text(
                'Synced',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? colorScheme.primary
            : Colors.white.withValues(alpha: 0.2),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: selected
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : const SizedBox(width: 14, height: 14),
      ),
    );
  }
}
