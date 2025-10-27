import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cloud_sync_photos/core/network/api_exception.dart';
import 'package:flutter_cloud_sync_photos/features/auth/data/services/auth_service.dart';
import 'package:flutter_cloud_sync_photos/features/gallery/data/services/upload_metadata_store.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

class PhotoDetailPage extends StatefulWidget {
  const PhotoDetailPage({super.key, required this.asset});

  final AssetEntity asset;

  @override
  State<PhotoDetailPage> createState() => _PhotoDetailPageState();
}

class _PhotoDetailPageState extends State<PhotoDetailPage>
    with SingleTickerProviderStateMixin {
  late final Future<_PhotoMetadata> _metadataFuture;
  final UploadMetadataStore _uploadMetadataStore = UploadMetadataStore();
  final AuthService _authService = globalAuthService;
  String? _contentHash;
  bool _loadingContentHash = true;
  bool _isUnsyncing = false;
  late final AnimationController _detailsController;
  late final Animation<double> _detailsOpacity;
  late final Animation<Offset> _detailsOffset;
  bool _showTapHint = true;
  double _dragToDismissExtent = 0;
  late final ValueNotifier<AuthStatus> _authStatusNotifier;
  late AuthStatus _authStatus;

  @override
  void initState() {
    super.initState();
    _detailsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _detailsOpacity = CurvedAnimation(
      parent: _detailsController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _detailsOffset = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(_detailsOpacity);
    _metadataFuture = _PhotoMetadata.fromAsset(widget.asset);
    _loadContentHash();
    _scheduleTapHintDismissal();
    _authStatusNotifier = _authService.authStatusNotifier;
    _authStatus = _authStatusNotifier.value;
    _authStatusNotifier.addListener(_handleAuthStatusChange);
  }

  @override
  void dispose() {
    _detailsController.dispose();
    _authStatusNotifier.removeListener(_handleAuthStatusChange);
    super.dispose();
  }

  void _scheduleTapHintDismissal() {
    Future<void>.delayed(const Duration(seconds: 5)).then((_) {
      if (!mounted || !_showTapHint) {
        return;
      }
      setState(() {
        _showTapHint = false;
      });
    });
  }

  bool get _canManageSync =>
      _authStatus == AuthStatus.authenticated ||
      _authStatus == AuthStatus.offline;

  void _handleAuthStatusChange() {
    final status = _authStatusNotifier.value;
    if (!mounted) {
      _authStatus = status;
      return;
    }
    setState(() {
      _authStatus = status;
    });
  }

  void _handleImageTap() {
    _toggleDetails();
  }

  void _toggleDetails() {
    final shouldOpen = _detailsController.value < 0.5;
    if (shouldOpen) {
      _detailsController.forward();
    } else {
      _detailsController.reverse();
    }
    _dragToDismissExtent = 0;
    if (_showTapHint) {
      setState(() {
        _showTapHint = false;
      });
    }
  }

  void _handleDetailsDragUpdate(DragUpdateDetails details, double height) {
    if (height <= 0) {
      return;
    }
    final primaryDelta = details.primaryDelta ?? details.delta.dy;
    if (_detailsController.value <= 0.001 && primaryDelta > 0) {
      _dragToDismissExtent += primaryDelta;
      if (_dragToDismissExtent > height * 0.18) {
        _dismissPage();
      }
      return;
    }
    if (primaryDelta < 0) {
      _dragToDismissExtent = 0;
    }
    final fraction = primaryDelta / height;
    final newValue = (_detailsController.value - fraction).clamp(0.0, 1.0);
    _detailsController.value = newValue;
    if (_showTapHint) {
      setState(() {
        _showTapHint = false;
      });
    }
  }

  void _handleDetailsDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? details.velocity.pixelsPerSecond.dy;
    if (_detailsController.value <= 0.001) {
      if (velocity != null && velocity > 550) {
        _dismissPage();
        return;
      }
      if (_dragToDismissExtent > 72) {
        _dismissPage();
        return;
      }
      _dragToDismissExtent = 0;
    }
    if (velocity != null) {
      if (velocity > 400) {
        _dragToDismissExtent = 0;
        _detailsController.reverse();
        return;
      }
      if (velocity < -400) {
        _dragToDismissExtent = 0;
        _detailsController.forward();
        return;
      }
    }
    if (_detailsController.value < 0.5) {
      _detailsController.reverse();
    } else {
      _detailsController.forward();
    }
    _dragToDismissExtent = 0;
  }

  void _dismissPage() {
    if (!mounted) {
      return;
    }
    _dragToDismissExtent = 0;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Photo details'),
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AnimatedBuilder(
              animation: _detailsController,
              builder: (context, child) {
                final isOpen = _detailsController.value > 0.05;
                return IconButton(
                  tooltip: isOpen ? 'Hide details' : 'Show details',
                  onPressed: _toggleDetails,
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: Icon(
                      isOpen ? Icons.close : Icons.info_outline,
                      key: ValueKey<bool>(isOpen),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Hero(
              tag: widget.asset.id,
              transitionOnUserGestures: true,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _handleImageTap,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return ClipRect(
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 6,
                          boundaryMargin: EdgeInsets.zero,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            child: DecoratedBox(
                              decoration:
                                  const BoxDecoration(color: Colors.black),
                              child: FittedBox(
                                fit: BoxFit.contain,
                                clipBehavior: Clip.hardEdge,
                                child: Image(
                                  image: AssetEntityImageProvider(
                                    widget.asset,
                                    isOriginal: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.35),
                      Colors.transparent,
                      Colors.black.withOpacity(0.45),
                    ],
                    stops: const [0.0, 0.3, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: _detailsController,
              builder: (context, child) {
                final shouldShowHint =
                    _showTapHint && _detailsController.value < 0.05;
                return IgnorePointer(
                  ignoring: true,
                  child: AnimatedOpacity(
                    opacity: shouldShowHint ? 1 : 0,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Tap photo for details',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: _detailsController,
              builder: (context, child) {
                final ignore = _detailsController.value <= 0.001;
                return IgnorePointer(
                  ignoring: ignore,
                  child: FadeTransition(
                    opacity: _detailsOpacity,
                    child: SlideTransition(
                      position: _detailsOffset,
                      child: _buildDetailsSheet(context),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSheet(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.hasBoundedHeight &&
                    constraints.maxHeight.isFinite &&
                    constraints.maxHeight > 0
                ? constraints.maxHeight
                : MediaQuery.of(context).size.height * 0.6;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) =>
                  _handleDetailsDragUpdate(details, availableHeight),
              onVerticalDragEnd: _handleDetailsDragEnd,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(26),
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 24,
                      offset: const Offset(0, -10),
                      color: Colors.black.withOpacity(0.35),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: FutureBuilder<_PhotoMetadata>(
                    future: _metadataFuture,
                    builder: (context, snapshot) {
                      final metadata = snapshot.data;
                      final isLoading =
                          snapshot.connectionState == ConnectionState.waiting;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withOpacity(0.25),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: isLoading
                                ? const SizedBox(
                                    key: ValueKey('details-loading'),
                                    height: 112,
                                    child: Center(
                                      child: SizedBox(
                                        height: 28,
                                        width: 28,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                                    ),
                                  )
                                : Column(
                                    key: const ValueKey('details-ready'),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Details',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      _MetadataRow(
                                        label: 'Captured',
                                        value: metadata?.formattedDate ??
                                            'Unknown',
                                      ),
                                      const SizedBox(height: 12),
                                      _MetadataRow(
                                        label: 'Resolution',
                                        value: metadata?.resolution ?? '—',
                                      ),
                                      const SizedBox(height: 12),
                                      _MetadataRow(
                                        label: 'File name',
                                        value: metadata?.fileName ?? '—',
                                      ),
                                      const SizedBox(height: 12),
                                      _MetadataRow(
                                        label: 'File size',
                                        value: metadata?.fileSize ?? '—',
                                      ),
                                      if (metadata?.location != null) ...[
                                        const SizedBox(height: 12),
                                        _MetadataRow(
                                          label: 'Location',
                                          value: metadata!.location!,
                                        ),
                                      ],
                                      _buildUnsyncSection(),
                                    ],
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _loadContentHash() async {
    final hash = await _uploadMetadataStore.getContentHash(widget.asset.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _contentHash = hash;
      _loadingContentHash = false;
    });
  }

  Future<void> _handleUnsync() async {
    if (!_canManageSync) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Sign in to unsync photos.')),
      );
      return;
    }

    final hash = _contentHash;
    if (hash == null || hash.isEmpty || _isUnsyncing) {
      return;
    }

    setState(() {
      _isUnsyncing = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    try {
      await globalAuthService.unsyncFile(contentHash: hash);
      await _uploadMetadataStore.remove(widget.asset.id);
      if (!mounted) {
        _isUnsyncing = false;
        return;
      }
      setState(() {
        _contentHash = null;
        _isUnsyncing = false;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Photo unsynced')),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        _isUnsyncing = false;
        return;
      }
      setState(() {
        _isUnsyncing = false;
      });
      messenger.showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) {
        _isUnsyncing = false;
        return;
      }
      setState(() {
        _isUnsyncing = false;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to unsync photo')),
      );
    }
  }

  Widget _buildUnsyncSection() {
    if (_loadingContentHash) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          SizedBox(height: 24),
          Center(
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
              ),
            ),
          ),
        ],
      );
    }

    final theme = Theme.of(context);
    final isSynced = _contentHash != null && _contentHash!.isNotEmpty;
    final isBusy = _isUnsyncing;

    final canManageSync = _canManageSync;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed:
                (!isSynced || isBusy || !canManageSync) ? null : _handleUnsync,
            child: isBusy
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.onPrimary,
                      ),
                    ),
                  )
                : const Text('Unsync photo'),
          ),
        ),
        if (!canManageSync)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Sign in to manage synced photos.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else if (!isSynced)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Photo not synced yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoMetadata {
  const _PhotoMetadata({
    required this.takenAt,
    required this.width,
    required this.height,
    required this.bytes,
    required this.fileName,
    this.latLng,
  });

  final DateTime takenAt;
  final int width;
  final int height;
  final int? bytes;
  final String fileName;
  final LatLng? latLng;

  String get formattedDate {
    final month = _monthNames[takenAt.month - 1];
    final hour = takenAt.hour % 12 == 0 ? 12 : takenAt.hour % 12;
    final minute = takenAt.minute.toString().padLeft(2, '0');
    final period = takenAt.hour >= 12 ? 'PM' : 'AM';
    return '$month ${takenAt.day}, ${takenAt.year} • $hour:$minute $period';
  }

  String get resolution => '$width × $height';

  String get fileSize => _formatBytes(bytes);

  String? get location {
    final lat = latLng?.latitude;
    final lng = latLng?.longitude;
    if (lat == null || lng == null) {
      return null;
    }
    if (lat == 0 && lng == 0) {
      return null;
    }
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }

  static Future<_PhotoMetadata> fromAsset(AssetEntity asset) async {
    File? file = await asset.originFile;
    file ??= await asset.file;
    String? rawTitle;
    try {
      rawTitle = await asset.titleAsync;
    } catch (_) {
      rawTitle = null;
    }
    final trimmedTitle = rawTitle?.trim() ?? '';
    final path = file?.path ?? '';
    final separatorPattern = RegExp(r'[\\/]');
    final segments = path.isEmpty ? const <String>[] : path.split(separatorPattern);
    final fallbackName = segments.isNotEmpty ? segments.last.trim() : '';
    final resolvedFileName = trimmedTitle.isNotEmpty
        ? trimmedTitle
        : (fallbackName.isNotEmpty ? fallbackName : 'Unknown');

    final bytes = await file?.length();
    LatLng? latLng;
    try {
      latLng = await asset.latlngAsync();
    } catch (_) {
      latLng = null;
    }

    return _PhotoMetadata(
      takenAt: asset.createDateTime.toLocal(),
      width: asset.width,
      height: asset.height,
      bytes: bytes,
      fileName: resolvedFileName,
      latLng: latLng,
    );
  }

  static String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) {
      return 'Unknown';
    }

    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    return '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${suffixes[suffixIndex]}';
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
