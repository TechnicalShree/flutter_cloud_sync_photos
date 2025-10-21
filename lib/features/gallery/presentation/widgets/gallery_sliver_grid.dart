import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../data/services/upload_metadata_store.dart';

const double _gridSpacing = 8.0;
const double _tileRadius = 12.0;
const Duration _tileAnimationDuration = Duration(milliseconds: 220);

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

class GalleryTile extends StatefulWidget {
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
  State<GalleryTile> createState() => _GalleryTileState();
}

class _GalleryTileState extends State<GalleryTile> {
  bool _isPressed = false;
  bool _isHovered = false;

  void _handleHighlight(bool value) {
    if (_isPressed != value) {
      setState(() {
        _isPressed = value;
      });
    }
  }

  void _handleHover(bool value) {
    if (_isHovered != value) {
      setState(() {
        _isHovered = value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: widget.metadataStore.isUploaded(widget.asset.id),
      builder: (context, snapshot) {
        final theme = widget.theme;
        final isUploaded = snapshot.data ?? false;
        final uploading = widget.isUploading;
        final isSelectable = !isUploaded && !uploading;
        final effectiveOnTap =
            widget.selectionMode && !isSelectable ? null : widget.onTap;
        final effectiveOnLongPress =
            isSelectable ? widget.onLongPress : null;
        final showSelection = widget.selectionMode &&
            widget.showSelectionIndicator &&
            !isUploaded &&
            !uploading;

        final bool hasInteraction =
            effectiveOnTap != null || effectiveOnLongPress != null;
        final double scale = _isPressed
            ? 0.95
            : widget.isSelected
                ? 0.97
                : _isHovered
                    ? 1.02
                    : 1.0;
        final Color borderColor = theme.colorScheme.onSurface.withValues(
          alpha: (widget.isSelected || _isHovered) ? 0.16 : 0.08,
        );

        final Widget topRightChild;
        if (uploading) {
          topRightChild = const _UploadProgressDot(key: ValueKey('uploading'));
        } else if (showSelection) {
          topRightChild = _SelectionIndicator(
            key: ValueKey<bool>(widget.isSelected),
            selected: widget.isSelected,
          );
        } else if (!isUploaded && !widget.selectionMode && widget.onUpload != null) {
          topRightChild = _GlassCircleButton(
            key: const ValueKey('upload'),
            icon: Icons.cloud_upload_outlined,
            onPressed: widget.onUpload!,
          );
        } else {
          topRightChild = const SizedBox.shrink(key: ValueKey('empty'));
        }

        final double overlayOpacity = uploading
            ? 0.45
            : widget.isSelected
                ? 0.35
                : showSelection
                    ? 0.18
                    : 0.0;

        return MouseRegion(
          onEnter: (_) => _handleHover(true),
          onExit: (_) => _handleHover(false),
          child: AnimatedScale(
            scale: scale,
            duration: _tileAnimationDuration,
            curve: Curves.easeOutBack,
            child: AnimatedContainer(
              duration: _tileAnimationDuration,
              curve: Curves.easeInOut,
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
                  color: borderColor,
                  width: 1,
                ),
                boxShadow: [
                  if (widget.isSelected || _isHovered)
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.18),
                      blurRadius: 16,
                      spreadRadius: 1,
                      offset: const Offset(0, 6),
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_tileRadius),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    splashColor:
                        theme.colorScheme.primary.withValues(alpha: 0.18),
                    highlightColor: Colors.white.withValues(alpha: 0.05),
                    onTap: effectiveOnTap,
                    onLongPress: effectiveOnLongPress,
                    onHighlightChanged:
                        hasInteraction ? _handleHighlight : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Hero(
                          tag: widget.asset.id,
                          child: Image(
                            image: AssetEntityImageProvider(
                              widget.asset,
                              isOriginal: false,
                              thumbnailSize: const ThumbnailSize.square(400),
                            ),
                            fit: BoxFit.cover,
                          ),
                        ),
                        _GradientOverlay(
                          theme: theme,
                          opacity: widget.selectionMode || widget.isSelected
                              ? 1
                              : 0.9,
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: true,
                            child: AnimatedOpacity(
                              duration: _tileAnimationDuration,
                              curve: Curves.easeInOut,
                              opacity: overlayOpacity,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: AnimatedSwitcher(
                            duration: _tileAnimationDuration,
                            switchInCurve: Curves.easeOutBack,
                            switchOutCurve: Curves.easeInBack,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(begin: 0.7, end: 1)
                                      .animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: widget.asset.isFavorite
                                ? const Icon(
                                    Icons.favorite,
                                    key: ValueKey('favorite'),
                                    size: 20,
                                    color: Colors.white,
                                  )
                                : const SizedBox(
                                    key: ValueKey('favorite-empty'),
                                    width: 20,
                                    height: 20,
                                  ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: AnimatedSwitcher(
                            duration: _tileAnimationDuration,
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            layoutBuilder: (currentChild, previousChildren) {
                              return Stack(
                                alignment: Alignment.center,
                                children: <Widget>[
                                  ...previousChildren,
                                  if (currentChild != null) currentChild,
                                ],
                              );
                            },
                            transitionBuilder: (child, animation) {
                              final fadeAnimation = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOut,
                                reverseCurve: Curves.easeIn,
                              );
                              return FadeTransition(
                                opacity: fadeAnimation,
                                child: ScaleTransition(
                                  scale: Tween<double>(begin: 0.85, end: 1)
                                      .animate(fadeAnimation),
                                  child: child,
                                ),
                              );
                            },
                            child: topRightChild,
                          ),
                        ),
                        Positioned(
                          bottom: 10,
                          left: 10,
                          child: AnimatedSwitcher(
                            duration: _tileAnimationDuration,
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) {
                              final curved = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOut,
                                reverseCurve: Curves.easeIn,
                              );
                              return FadeTransition(
                                opacity: curved,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(-0.1, 0.1),
                                    end: Offset.zero,
                                  ).animate(curved),
                                  child: child,
                                ),
                              );
                            },
                            child: isUploaded
                                ? const _SyncedBadge(key: ValueKey('synced'))
                                : const SizedBox(
                                    key: ValueKey('synced-empty'),
                                    width: 0,
                                    height: 0,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GradientOverlay extends StatelessWidget {
  const _GradientOverlay({required this.theme, required this.opacity});

  final ThemeData theme;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: _tileAnimationDuration,
        curve: Curves.easeInOut,
        opacity: opacity,
        child: Align(
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
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatefulWidget {
  const _GlassCircleButton({super.key, required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_GlassCircleButton> createState() => _GlassCircleButtonState();
}

class _GlassCircleButtonState extends State<_GlassCircleButton> {
  bool _isPressed = false;

  void _handleHighlight(bool value) {
    if (_isPressed != value) {
      setState(() {
        _isPressed = value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = AnimatedScale(
      scale: _isPressed ? 0.9 : 1,
      duration: _tileAnimationDuration,
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: _tileAnimationDuration,
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isPressed ? 0.12 : 0.18),
              blurRadius: _isPressed ? 8 : 14,
              spreadRadius: _isPressed ? 0 : 1,
            ),
          ],
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Material(
              color: Colors.white.withValues(alpha: 0.18),
              child: InkWell(
                onTap: widget.onPressed,
                customBorder: const CircleBorder(),
                onHighlightChanged: _handleHighlight,
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: AnimatedSwitcher(
                    duration: _tileAnimationDuration,
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    child: Icon(
                      widget.icon,
                      key: ValueKey(widget.icon.codePoint),
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Tooltip(message: 'Upload', child: button);
  }
}

class _UploadProgressDot extends StatelessWidget {
  const _UploadProgressDot({super.key});

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
  const _SyncedBadge({super.key});

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
  const _SelectionIndicator({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: _tileAnimationDuration,
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? colorScheme.primary
            : Colors.white.withValues(alpha: 0.2),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: AnimatedSwitcher(
        duration: _tileAnimationDuration,
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeIn,
          );
          return FadeTransition(
            opacity: curvedAnimation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1).animate(curvedAnimation),
              child: child,
            ),
          );
        },
        child: selected
            ? const SizedBox(
                key: ValueKey('selected'),
                width: 14,
                height: 14,
                child: Icon(Icons.check, size: 14, color: Colors.white),
              )
            : const SizedBox(
                key: ValueKey('unselected'),
                width: 14,
                height: 14,
              ),
      ),
    );
  }
}
