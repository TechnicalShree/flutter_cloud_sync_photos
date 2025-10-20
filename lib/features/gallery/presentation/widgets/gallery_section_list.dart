import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

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
    this.onAssetTap,
  });

  final List<GallerySection> sections;
  final ValueChanged<AssetEntity>? onAssetTap;

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final section = sections[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: _GallerySectionView(section: section, onAssetTap: onAssetTap),
        );
      }, childCount: sections.length),
    );
  }
}

class _GallerySectionView extends StatelessWidget {
  const _GallerySectionView({required this.section, this.onAssetTap});

  final GallerySection section;
  final ValueChanged<AssetEntity>? onAssetTap;

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
              onTap: () => onAssetTap?.call(asset),
            );
          },
        ),
      ],
    );
  }
}
