import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class GalleryPermissionPrompt extends StatelessWidget {
  const GalleryPermissionPrompt({
    super.key,
    required this.permissionState,
    required this.onRequestPermission,
    required this.onRetry,
  });

  final PermissionState? permissionState;
  final VoidCallback onRequestPermission;
  final VoidCallback onRetry;

  bool get _isLimited => permissionState == PermissionState.limited;
  bool get _canPresentLimited =>
      _isLimited && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  void _handlePrimaryPressed() {
    if (_canPresentLimited) {
      unawaited(_presentLimitedAndRefresh());
    } else {
      onRequestPermission();
    }
  }

  Future<void> _presentLimitedAndRefresh() async {
    await PhotoManager.presentLimited();
    onRetry();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final title = _isLimited
        ? 'Limited access to photos'
        : 'Allow photo access';
    final message = _isLimited
        ? 'Grant additional access so we can show more of your gallery.'
        : 'Tap below to grant photo access and load your gallery.';
    final primaryLabel = _isLimited ? 'Select more photos' : 'Grant access';

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                blurRadius: 24,
                offset: const Offset(0, 12),
                color: colorScheme.shadow.withValues(alpha: 0.12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 64, color: colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _handlePrimaryPressed,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(primaryLabel),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onRetry,
                child: const Text('Refresh status'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
