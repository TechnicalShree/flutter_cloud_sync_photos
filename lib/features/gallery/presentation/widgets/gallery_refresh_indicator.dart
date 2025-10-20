import 'package:flutter/material.dart';

class GalleryRefreshIndicator extends StatelessWidget {
  const GalleryRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      displacement: 40,
      strokeWidth: 2.5,
      onRefresh: onRefresh,
      child: child,
    );
  }
}
