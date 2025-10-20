import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../data/services/upload_metadata_store.dart';
import 'gallery_sliver_grid.dart';

class GallerySection {
  const GallerySection({required this.title, required this.assets});

  final String title;
  final List<AssetEntity> assets;
}

class GallerySectionList extends StatelessWidget {
  const GallerySectionList({
    super.key,
    required this.sections,
    required this.metadataStore,
    this.selectionMode = false,
    this.selectedAssetIds = const <String>{},
    this.hideSelectionIndicatorAssetIds = const <String>{},
    this.onAssetTap,
    this.onAssetLongPress,
    this.onAssetUpload,
  });

  final List<GallerySection> sections;
  final UploadMetadataStore metadataStore;
  final bool selectionMode;
  final Set<String> selectedAssetIds;
  final Set<String> hideSelectionIndicatorAssetIds;
  final ValueChanged<AssetEntity>? onAssetTap;
  final ValueChanged<AssetEntity>? onAssetLongPress;
  final ValueChanged<AssetEntity>? onAssetUpload;

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final section = sections[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: _GallerySectionView(
            section: section,
            metadataStore: metadataStore,
            selectionMode: selectionMode,
            selectedAssetIds: selectedAssetIds,
            hideSelectionIndicatorAssetIds: hideSelectionIndicatorAssetIds,
            onAssetTap: onAssetTap,
            onAssetLongPress: onAssetLongPress,
            onAssetUpload: onAssetUpload,
          ),
        );
      }, childCount: sections.length),
    );
  }
}

class _GallerySectionView extends StatelessWidget {
  const _GallerySectionView({
    required this.section,
    required this.metadataStore,
    required this.selectionMode,
    required this.selectedAssetIds,
    required this.hideSelectionIndicatorAssetIds,
    this.onAssetTap,
    this.onAssetLongPress,
    this.onAssetUpload,
  });

  final GallerySection section;
  final UploadMetadataStore metadataStore;
  final bool selectionMode;
  final Set<String> selectedAssetIds;
  final Set<String> hideSelectionIndicatorAssetIds;
  final ValueChanged<AssetEntity>? onAssetTap;
  final ValueChanged<AssetEntity>? onAssetLongPress;
  final ValueChanged<AssetEntity>? onAssetUpload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            section.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: section.assets.length,
          itemBuilder: (context, index) {
            final asset = section.assets[index];
            return GalleryTile(
              asset: asset,
              theme: theme,
              metadataStore: metadataStore,
              selectionMode: selectionMode,
              isSelected: selectedAssetIds.contains(asset.id),
              showSelectionIndicator:
                  !hideSelectionIndicatorAssetIds.contains(asset.id),
              onTap: () => onAssetTap?.call(asset),
              onLongPress: () => onAssetLongPress?.call(asset),
              onUpload: onAssetUpload != null
                  ? () => onAssetUpload?.call(asset)
                  : null,
            );
          },
        ),
      ],
    );
  }
}
