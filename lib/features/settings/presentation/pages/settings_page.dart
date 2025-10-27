import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../auth/data/services/auth_service.dart';
import '../../../auth/domain/models/user_details.dart';
import '../../../auth/presentation/pages/login_page.dart';
import '../../data/upload_preferences_store.dart';
import '../../data/settings_actions.dart';
import '../../../gallery/data/services/gallery_upload_queue.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static const String routeName = '/settings';

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with TickerProviderStateMixin {
  final AuthService _authService = globalAuthService;
  final UploadPreferencesStore _preferencesStore = uploadPreferencesStore;
  final SettingsActions _actions = settingsActions;
  final GalleryUploadQueue _uploadQueue = galleryUploadQueue;

  late final AnimationController _backgroundController;
  UserDetails? _userDetails;
  bool _loadingUser = true;
  bool _loadingPreferences = true;
  bool _isPrivateUploads = true;
  bool _optimizeUploads = false;
  bool _processingLogout = false;
  bool _resettingMetadata = false;
  List<UploadJob> _uploadJobs = const [];
  VoidCallback? _uploadQueueListener;
  bool _showAllUploads = false;
  final List<bool> _sectionVisible = List<bool>.filled(4, false);

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);
    _uploadJobs = _uploadQueue.jobs;
    _uploadQueueListener = _handleUploadQueueUpdate;
    _uploadQueue.addListener(_uploadQueueListener!);
    _loadInitialData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      for (var i = 0; i < _sectionVisible.length; i++) {
        Future.delayed(Duration(milliseconds: 120 * i), () {
          if (!mounted) {
            return;
          }
          setState(() {
            _sectionVisible[i] = true;
          });
        });
      }
    });
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadUserDetails(),
      _loadUploadPreferences(),
    ]);
  }

  Future<void> _loadUserDetails() async {
    try {
      final cached = _authService.currentUser;
      if (cached != null) {
        setState(() {
          _userDetails = cached;
          _loadingUser = false;
        });
        return;
      }

      final fetched = await _authService.fetchUserDetails();
      if (!mounted) {
        return;
      }
      setState(() {
        _userDetails = fetched;
        _loadingUser = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingUser = false;
      });
    }
  }

  Future<void> _loadUploadPreferences() async {
    final prefs = await _preferencesStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _isPrivateUploads = prefs.isPrivate;
      _optimizeUploads = prefs.optimize;
      _loadingPreferences = false;
    });
  }

  void _handleUploadQueueUpdate() {
    if (!mounted) {
      return;
    }
    setState(() {
      _uploadJobs = _uploadQueue.jobs;
      if (_uploadJobs.length <= 10 && _showAllUploads) {
        _showAllUploads = false;
      }
    });
  }

  Future<void> _handlePrivateToggle(bool value) async {
    setState(() {
      _isPrivateUploads = value;
    });
    await _preferencesStore.setIsPrivate(value);
  }

  Future<void> _handleOptimizeToggle(bool value) async {
    setState(() {
      _optimizeUploads = value;
    });
    await _preferencesStore.setOptimize(value);
  }

  Future<void> _handleLogout() async {
    if (_processingLogout) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Sign out?'),
          content: const Text(
            'You will be signed out from this device and will need to log in again to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sign out'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _processingLogout = true;
    });

    await _authService.logout();
    if (!mounted) {
      return;
    }

    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(LoginPage.routeName, (_) => false);
  }

  Future<void> _handleResetMetadata() async {
    if (_resettingMetadata) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Reset upload metadata?'),
          content: const Text(
            'This clears the list of photos marked as synced. You can re-upload any photo afterwards.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _resettingMetadata = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Clearing synced photo records...')),
    );

    try {
      await _actions.resetUploadMetadata();
      if (!mounted) {
        return;
      }

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Upload metadata cleared')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _resettingMetadata = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    if (_uploadQueueListener != null) {
      _uploadQueue.removeListener(_uploadQueueListener!);
      _uploadQueueListener = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Settings'),
        centerTitle: true,
        elevation: 0,
      ),
      body: AnimatedBuilder(
        animation: _backgroundController,
        builder: (context, child) {
          final curvedProgress = CurvedAnimation(
            parent: _backgroundController,
            curve: Curves.easeInOut,
          ).value;
          final gradient = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(
                theme.colorScheme.primaryContainer.withOpacity(0.6),
                theme.colorScheme.surface,
                curvedProgress,
              )!,
              Color.lerp(
                theme.colorScheme.surface,
                theme.colorScheme.secondaryContainer.withOpacity(0.7),
                curvedProgress,
              )!,
            ],
          );
          return DecoratedBox(
            decoration: BoxDecoration(gradient: gradient),
            child: child,
          );
        },
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    [
                      _animatedSection(
                        index: 0,
                        child: _buildUserSection(theme),
                      ),
                      const SizedBox(height: 24),
                      _animatedSection(
                        index: 1,
                        child: _buildUploadConfigSection(theme),
                      ),
                      const SizedBox(height: 24),
                      _animatedSection(
                        index: 2,
                        child: _buildUploadProgressSection(theme),
                      ),
                      const SizedBox(height: 24),
                      _animatedSection(
                        index: 3,
                        child: _buildLogoutSection(theme),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _animatedSection({required int index, required Widget child}) {
    final visible = index < _sectionVisible.length && _sectionVisible[index];
    final duration = Duration(milliseconds: 420 + (index * 40));
    return AnimatedOpacity(
      duration: duration,
      curve: Curves.easeOutCubic,
      opacity: visible ? 1 : 0,
      child: AnimatedSlide(
        duration: duration,
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, 0.08),
        child: child,
      ),
    );
  }

  Widget _buildUserSection(ThemeData theme) {
    if (_loadingUser) {
      return const _SectionCard(
        title: 'Account',
        child: _LoadingIndicator(),
      );
    }

    final details = _userDetails;
    final prettyDetails = _prettyPrintUserDetails(details);
    return _SectionCard(
      title: 'Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AnimatedAvatar(name: details?.fullName ?? details?.name ?? details?.user),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _safeDisplay(details?.fullName) ??
                          _safeDisplay(details?.name) ??
                          'Unknown user',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _safeDisplay(details?.user) ?? 'No username available',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _InfoRow(
            label: 'Gender',
            value: _safeDisplay(details?.gender) ?? 'Not specified',
          ),
          if (prettyDetails != null) ...[
            const SizedBox(height: 20),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'API response',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      prettyDetails,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUploadConfigSection(ThemeData theme) {
    if (_loadingPreferences) {
      return const _SectionCard(
        title: 'Upload Preferences',
        child: _LoadingIndicator(),
      );
    }

    return _SectionCard(
      title: 'Upload Preferences',
      child: Column(
        children: [
          _AnimatedPreferenceTile(
            isActive: _isPrivateUploads,
            child: SwitchListTile.adaptive(
              value: _isPrivateUploads,
              onChanged: _handlePrivateToggle,
              title: const Text('Upload as private'),
              subtitle: const Text(
                'Store uploaded photos in a private workspace',
              ),
              contentPadding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _AnimatedPreferenceTile(
            isActive: _optimizeUploads,
            child: SwitchListTile.adaptive(
              value: _optimizeUploads,
              onChanged: _handleOptimizeToggle,
              title: const Text('Optimize images'),
              subtitle:
                  const Text('Compress images before upload to save space'),
              contentPadding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 20),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: theme.colorScheme.surfaceVariant.withOpacity(0.16),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: const Text('Upload folder preview'),
              subtitle: Text(
                _describeDefaultFolder(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: _resettingMetadata ? null : _handleResetMetadata,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                  AnimatedRotation(
                    turns: _resettingMetadata ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      Icons.restart_alt,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reset upload metadata',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Clears synced photo markers so uploads can run again',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _resettingMetadata
                        ? const SizedBox(
                            key: ValueKey('progress'),
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.keyboard_arrow_right,
                            key: ValueKey('arrow'),
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                  ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _describeDefaultFolder() {
    final details = _userDetails;
    final userSegment = _resolveUserSegment(details);
    final albumSegment = _sanitizeAlbumName('Gallery');
    return 'Home/$userSegment/$albumSegment';
  }

  Widget _buildUploadProgressSection(ThemeData theme) {
    return _SectionCard(
      title: 'Background Uploads',
      child: _buildUploadQueueTab(theme),
    );
  }

  Widget _buildUploadQueueTab(ThemeData theme) {
    const maxVisible = 10;
    final jobs = _uploadJobs;
    final reversedJobs = jobs.reversed.toList();
    final hasJobs = reversedJobs.isNotEmpty;
    final showAll = _showAllUploads && jobs.length > maxVisible;
    final displayedJobs =
        showAll ? reversedJobs : reversedJobs.take(maxVisible).toList();
    final hasMore = !showAll && jobs.length > maxVisible;
    final showLess = showAll && jobs.length > maxVisible;
    final hasFinished = jobs.any((job) => job.isFinished);
    final preparing = _uploadQueue.hasActiveUploads && !hasJobs;

    return KeyedSubtree(
      key: const ValueKey('upload-queue-tab'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasJobs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_sync_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      preparing
                          ? 'Preparing uploads...'
                          : 'No uploads in progress.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              child: Column(
                children: [
                  for (final job in displayedJobs)
                    _UploadJobRow(
                      key: ValueKey(job.assetId),
                      job: job,
                      onCancel: job.status == UploadJobStatus.queued
                          ? () => _uploadQueue.cancelJob(job.assetId)
                          : null,
                    ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (hasMore)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showAllUploads = true;
                      });
                    },
                    icon: const Icon(Icons.expand_more),
                    label: Text('Show all (${jobs.length})'),
                  ),
                if (showLess)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showAllUploads = false;
                      });
                    },
                    icon: const Icon(Icons.expand_less),
                    label: const Text('Show less'),
                  ),
              ],
            ),
          ],
          if (hasFinished)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _uploadQueue.clearFinished,
                child: const Text('Clear completed'),
              ),
            ),
        ],
      ),
    );
  }

  String _resolveUserSegment(UserDetails? details) {
    final explicitName = details?.name?.trim();
    if (explicitName != null && explicitName.isNotEmpty) {
      return explicitName;
    }

    final user = details?.user?.trim();
    if (user != null && user.isNotEmpty) {
      return user;
    }

    return 'anonymous';
  }

  String _sanitizeAlbumName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'Unsorted';
    }
    final sanitized = trimmed.replaceAll('/', '_').replaceAll('\\', '_').trim();
    return sanitized.isEmpty ? 'Unsorted' : sanitized;
  }

  String? _safeDisplay(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _prettyPrintUserDetails(UserDetails? details) {
    if (details == null) {
      return null;
    }
    final rawJson = details.toJson()
      ..removeWhere((key, value) {
        if (value == null) {
          return true;
        }
        if (value is String) {
          return value.trim().isEmpty;
        }
        return false;
      });
    if (rawJson.isEmpty) {
      return null;
    }
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(rawJson);
  }

  Widget _buildLogoutSection(ThemeData theme) {
    return _SectionCard(
      title: 'Session',
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _processingLogout ? null : _handleLogout,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _processingLogout
                ? const SizedBox(
                    key: ValueKey('logout-progress'),
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.logout, key: ValueKey('logout-icon')),
          ),
          label: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: Text(
              _processingLogout ? 'Signing out...' : 'Sign out',
              key: ValueKey(_processingLogout),
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadJobRow extends StatelessWidget {
  const _UploadJobRow({super.key, required this.job, this.onCancel});

  final UploadJob job;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusText(job);
    final statusColor = _statusColor(job.status, theme);
    final trailing = _buildTrailing(theme);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 280),
                scale: job.status == UploadJobStatus.uploading ? 1.05 : 1,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: IconTheme(
                    key: ValueKey(job.status),
                    data: IconThemeData(color: statusColor, size: 28),
                    child: trailing,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (onCancel != null)
                FilledButton.tonalIcon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrailing(ThemeData theme) {
    switch (job.status) {
      case UploadJobStatus.uploading:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
          ),
        );
      case UploadJobStatus.queued:
        if (onCancel != null) {
          return const Icon(Icons.schedule_outlined);
        }
        return Icon(
          Icons.schedule,
          color: theme.colorScheme.onSurfaceVariant,
        );
      case UploadJobStatus.completed:
        return Icon(
          Icons.check_circle,
          color: theme.colorScheme.primary,
        );
      case UploadJobStatus.failed:
        return Icon(
          Icons.error_outline,
          color: theme.colorScheme.error,
        );
      case UploadJobStatus.skipped:
        return Icon(
          Icons.cloud_done_outlined,
          color: theme.colorScheme.tertiary,
        );
      case UploadJobStatus.cancelled:
        return Icon(
          Icons.do_not_disturb_alt_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        );
    }
  }

  String _statusText(UploadJob job) {
    switch (job.status) {
      case UploadJobStatus.queued:
        return 'Queued';
      case UploadJobStatus.uploading:
        return 'Uploading...';
      case UploadJobStatus.completed:
        return 'Uploaded';
      case UploadJobStatus.failed:
        final message = job.error?.trim();
        return message?.isNotEmpty == true ? message! : 'Upload failed';
      case UploadJobStatus.skipped:
        return 'Already synced';
      case UploadJobStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color _statusColor(UploadJobStatus status, ThemeData theme) {
    switch (status) {
      case UploadJobStatus.uploading:
        return theme.colorScheme.primary;
      case UploadJobStatus.completed:
        return theme.colorScheme.primary;
      case UploadJobStatus.failed:
        return theme.colorScheme.error;
      case UploadJobStatus.skipped:
        return theme.colorScheme.tertiary;
      case UploadJobStatus.queued:
        return theme.colorScheme.onSurfaceVariant;
      case UploadJobStatus.cancelled:
        return theme.colorScheme.onSurfaceVariant;
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: theme.colorScheme.surface.withOpacity(0.82),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedPreferenceTile extends StatelessWidget {
  const _AnimatedPreferenceTile({required this.child, required this.isActive});

  final Widget child;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary.withOpacity(0.12);
    final inactiveColor = theme.colorScheme.surfaceVariant.withOpacity(0.2);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isActive ? activeColor : inactiveColor,
        border: Border.all(
          color: isActive
              ? theme.colorScheme.primary.withOpacity(0.45)
              : Colors.transparent,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: child,
    );
  }
}

class _AnimatedAvatar extends StatelessWidget {
  const _AnimatedAvatar({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = _initialsFromName(name);
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      tween: Tween(begin: 0.8, end: 1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.secondary,
            ],
          ),
        ),
        child: CircleAvatar(
          backgroundColor: Colors.transparent,
          radius: 28,
          child: Text(
            initials,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
      builder: (context, value, child) => Transform.scale(
        scale: value,
        child: child,
      ),
    );
  }

  String _initialsFromName(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return '👤';
    }
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final segment = parts.first;
      final length = math.min(2, segment.length);
      return segment.substring(0, length).toUpperCase();
    }
    final first = parts.first;
    final last = parts.last;
    final firstChar = first.isNotEmpty ? first[0] : '';
    final lastChar = last.isNotEmpty ? last[0] : '';
    final combined = (firstChar + lastChar).trim();
    return combined.isEmpty ? parts.first.substring(0, 1).toUpperCase() : combined.toUpperCase();
  }
}
