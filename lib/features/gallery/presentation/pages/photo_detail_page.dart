import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

class PhotoDetailPage extends StatefulWidget {
  const PhotoDetailPage({super.key, required this.asset});

  final AssetEntity asset;

  @override
  State<PhotoDetailPage> createState() => _PhotoDetailPageState();
}

class _PhotoDetailPageState extends State<PhotoDetailPage> {
  late final Future<_PhotoMetadata> _metadataFuture;

  @override
  void initState() {
    super.initState();
    _metadataFuture = _PhotoMetadata.fromAsset(widget.asset);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Photo details'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Hero(
                tag: widget.asset.id,
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Image(
                    image: AssetEntityImageProvider(
                      widget.asset,
                      isOriginal: true,
                    ),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          FutureBuilder<_PhotoMetadata>(
            future: _metadataFuture,
            builder: (context, snapshot) {
              final metadata = snapshot.data;
              return Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 24,
                      offset: const Offset(0, -8),
                      color: Colors.black.withValues(alpha: 0.35),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(
                        child: SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Details',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _MetadataRow(
                            label: 'Captured',
                            value: metadata?.formattedDate ?? 'Unknown',
                          ),
                          const SizedBox(height: 12),
                          _MetadataRow(
                            label: 'Resolution',
                            value: metadata?.resolution ?? '—',
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
                        ],
                      ),
              );
            },
          ),
        ],
      ),
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
    this.latLng,
  });

  final DateTime takenAt;
  final int width;
  final int height;
  final int? bytes;
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
