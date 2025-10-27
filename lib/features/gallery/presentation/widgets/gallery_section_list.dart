import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../data/services/upload_metadata_store.dart';
import 'gallery_selection_hit_target.dart';
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
    this.showSyncStatus = true,
    this.selectionMode = false,
    this.selectedAssetIds = const <String>{},
    this.uploadingAssetIds = const <String>{},
    this.hideSelectionIndicatorAssetIds = const <String>{},
    this.onAssetTap,
    this.onAssetLongPress,
    this.onAssetLongPressStart,
    this.onAssetLongPressMoveUpdate,
    this.onAssetLongPressEnd,
    this.onAssetUpload,
    this.animationDuration = const Duration(milliseconds: 220),
    this.animationCurve = Curves.easeOutCubic,
    this.sectionStaggerDelay = const Duration(milliseconds: 45),
  });

  final List<GallerySection> sections;
  final UploadMetadataStore metadataStore;
  final bool showSyncStatus;
  final bool selectionMode;
  final Set<String> selectedAssetIds;
  final Set<String> uploadingAssetIds;
  final Set<String> hideSelectionIndicatorAssetIds;
  final ValueChanged<AssetEntity>? onAssetTap;
  final ValueChanged<AssetEntity>? onAssetLongPress;
  final AssetLongPressStartCallback? onAssetLongPressStart;
  final AssetLongPressMoveUpdateCallback? onAssetLongPressMoveUpdate;
  final AssetLongPressEndCallback? onAssetLongPressEnd;
  final ValueChanged<AssetEntity>? onAssetUpload;
  final Duration animationDuration;
  final Curve animationCurve;
  final Duration sectionStaggerDelay;

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final section = sections[index];
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == sections.length - 1 ? 0 : 24,
          ),
          child: _GallerySectionView(
            section: section,
            metadataStore: metadataStore,
            showSyncStatus: showSyncStatus,
            selectionMode: selectionMode,
            selectedAssetIds: selectedAssetIds,
            uploadingAssetIds: uploadingAssetIds,
            hideSelectionIndicatorAssetIds: hideSelectionIndicatorAssetIds,
            onAssetTap: onAssetTap,
            onAssetLongPress: onAssetLongPress,
            onAssetLongPressStart: onAssetLongPressStart,
            onAssetLongPressMoveUpdate: onAssetLongPressMoveUpdate,
            onAssetLongPressEnd: onAssetLongPressEnd,
            onAssetUpload: onAssetUpload,
            animationDuration: animationDuration,
            animationCurve: animationCurve,
            staggerDelay: sectionStaggerDelay,
            index: index,
            highlight: selectionMode && index == 0,
          ),
        );
      }, childCount: sections.length),
    );
  }
}

class _GallerySectionView extends StatefulWidget {
  const _GallerySectionView({
    required this.section,
    required this.metadataStore,
    required this.showSyncStatus,
    required this.selectionMode,
    required this.selectedAssetIds,
    required this.uploadingAssetIds,
    required this.hideSelectionIndicatorAssetIds,
    this.onAssetTap,
    this.onAssetLongPress,
    this.onAssetLongPressStart,
    this.onAssetLongPressMoveUpdate,
    this.onAssetLongPressEnd,
    this.onAssetUpload,
    required this.animationDuration,
    required this.animationCurve,
    required this.staggerDelay,
    required this.index,
    required this.highlight,
  });

  final GallerySection section;
  final UploadMetadataStore metadataStore;
  final bool showSyncStatus;
  final bool selectionMode;
  final Set<String> selectedAssetIds;
  final Set<String> uploadingAssetIds;
  final Set<String> hideSelectionIndicatorAssetIds;
  final ValueChanged<AssetEntity>? onAssetTap;
  final ValueChanged<AssetEntity>? onAssetLongPress;
  final AssetLongPressStartCallback? onAssetLongPressStart;
  final AssetLongPressMoveUpdateCallback? onAssetLongPressMoveUpdate;
  final AssetLongPressEndCallback? onAssetLongPressEnd;
  final ValueChanged<AssetEntity>? onAssetUpload;
  final Duration animationDuration;
  final Curve animationCurve;
  final Duration staggerDelay;
  final int index;
  final bool highlight;

  @override
  State<_GallerySectionView> createState() => _GallerySectionViewState();
}

class _GallerySectionViewState extends State<_GallerySectionView> {
  bool _animateIn = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.staggerDelay * widget.index, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _animateIn = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.15,
      color: widget.highlight
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurface,
    );

    final content = _GallerySectionShell(
      highlight: widget.highlight,
      animationDuration: widget.animationDuration,
      animationCurve: widget.animationCurve,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: widget.animationDuration,
                  curve: widget.animationCurve,
                  style: headerStyle ??
                      (theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ) ??
                          const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          )),
                  child: Text(widget.section.title),
                ),
              ),
              const SizedBox(width: 12),
              _GallerySectionBadge(
                count: widget.section.assets.length,
                animationDuration: widget.animationDuration,
                animationCurve: widget.animationCurve,
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: widget.section.assets.length,
            itemBuilder: (context, index) {
              final asset = widget.section.assets[index];
              return GallerySelectionHitTarget(
                assetId: asset.id,
                child: GalleryTile(
                  asset: asset,
                  theme: theme,
                  metadataStore: widget.metadataStore,
                  showSyncStatus: widget.showSyncStatus,
                  selectionMode: widget.selectionMode,
                  isSelected: widget.selectedAssetIds.contains(asset.id),
                  isUploading: widget.uploadingAssetIds.contains(asset.id),
                  showSelectionIndicator:
                      !widget.hideSelectionIndicatorAssetIds
                          .contains(asset.id),
                  onTap: () => widget.onAssetTap?.call(asset),
                  onLongPress: () => widget.onAssetLongPress?.call(asset),
                  onLongPressStart: widget.onAssetLongPressStart != null
                      ? (details) =>
                          widget.onAssetLongPressStart!(asset, details)
                      : null,
                  onLongPressMoveUpdate:
                      widget.onAssetLongPressMoveUpdate != null
                          ? (details) => widget.onAssetLongPressMoveUpdate!(
                              asset, details)
                          : null,
                  onLongPressEnd: widget.onAssetLongPressEnd != null
                      ? (details) => widget.onAssetLongPressEnd!(asset, details)
                      : null,
                  onUpload: widget.onAssetUpload != null
                      ? () => widget.onAssetUpload?.call(asset)
                      : null,
                ),
              );
            },
          ),
        ],
      ),
    );

    return AnimatedOpacity(
      duration: widget.animationDuration,
      curve: widget.animationCurve,
      opacity: _animateIn ? 1 : 0,
      child: AnimatedSlide(
        duration: widget.animationDuration,
        curve: widget.animationCurve,
        offset: _animateIn ? Offset.zero : const Offset(0, 0.06),
        child: content,
      ),
    );
  }
}

class _GallerySectionShell extends StatelessWidget {
  const _GallerySectionShell({
    required this.child,
    required this.highlight,
    required this.animationDuration,
    required this.animationCurve,
  });

  final Widget child;
  final bool highlight;
  final Duration animationDuration;
  final Curve animationCurve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surface.withOpacity(0.82);
    final highlightColor =
        theme.colorScheme.secondaryContainer.withOpacity(0.74);
    final backgroundColor = highlight
        ? Color.lerp(baseColor, highlightColor, 0.4) ?? highlightColor
        : baseColor;

    final borderColor = highlight
        ? theme.colorScheme.primary.withOpacity(0.24)
        : theme.colorScheme.outlineVariant.withOpacity(0.18);

    return AnimatedContainer(
      duration: animationDuration,
      curve: animationCurve,
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: child,
      ),
    );
  }
}

class _GallerySectionBadge extends StatelessWidget {
  const _GallerySectionBadge({
    required this.count,
    required this.animationDuration,
    required this.animationCurve,
  });

  final int count;
  final Duration animationDuration;
  final Curve animationCurve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = count == 1 ? 'item' : 'items';

    return AnimatedContainer(
      duration: animationDuration,
      curve: animationCurve,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surfaceVariant.withOpacity(0.6),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.24),
        ),
      ),
      child: AnimatedDefaultTextStyle(
        duration: animationDuration,
        curve: animationCurve,
        style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withOpacity(0.8),
              letterSpacing: 0.1,
            ) ??
            TextStyle(
              color: colorScheme.onSurfaceVariant.withOpacity(0.8),
              fontSize: 12,
            ),
        child: Text('$count $label'),
      ),
    );
  }
}
