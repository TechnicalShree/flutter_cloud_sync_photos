import 'dart:async';

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

class _SettingsPageState extends State<SettingsPage> {
  final AuthService _authService = globalAuthService;
  final UploadPreferencesStore _preferencesStore = uploadPreferencesStore;
  final SettingsActions _actions = settingsActions;
  final GalleryUploadQueue _uploadQueue = galleryUploadQueue;

  UserDetails? _userDetails;
  bool _loadingUser = true;
  bool _loadingPreferences = true;
  bool _isPrivateUploads = true;
  bool _optimizeUploads = false;
  bool _wifiOnly = false;
  bool _whileCharging = false;
  bool _blockOnRoaming = false;
  int _batteryThreshold = 0;
  bool _processingLogout = false;
  bool _resettingMetadata = false;
  List<UploadJob> _uploadJobs = const [];
  VoidCallback? _uploadQueueListener;
  bool _showAllUploads = false;

  @override
  void initState() {
    super.initState();
    _uploadJobs = _uploadQueue.jobs;
    _uploadQueueListener = _handleUploadQueueUpdate;
    _uploadQueue.addListener(_uploadQueueListener!);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([_loadUserDetails(), _loadUploadPreferences()]);
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
      _wifiOnly = prefs.wifiOnly;
      _whileCharging = prefs.whileCharging;
      _blockOnRoaming = prefs.blockOnRoaming;
      _batteryThreshold = prefs.batteryThreshold;
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

  Future<void> _handleWifiOnlyToggle(bool value) async {
    setState(() {
      _wifiOnly = value;
    });
    await _preferencesStore.setWifiOnly(value);
    unawaited(_uploadQueue.refreshEnvironmentConstraints());
  }

  Future<void> _handleWhileChargingToggle(bool value) async {
    setState(() {
      _whileCharging = value;
    });
    await _preferencesStore.setWhileCharging(value);
    unawaited(_uploadQueue.refreshEnvironmentConstraints());
  }

  Future<void> _handleBlockOnRoamingToggle(bool value) async {
    setState(() {
      _blockOnRoaming = value;
    });
    await _preferencesStore.setBlockOnRoaming(value);
    unawaited(_uploadQueue.refreshEnvironmentConstraints());
  }

  void _handleBatterySliderChanged(double value) {
    setState(() {
      _batteryThreshold = value.round();
    });
  }

  void _handleBatterySliderChangeEnd(double value) {
    final threshold = value.round();
    unawaited(_preferencesStore.setBatteryThreshold(threshold));
    unawaited(_uploadQueue.refreshEnvironmentConstraints());
  }

  Future<void> _handleLogout() async {
    if (_processingLogout) {
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
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildUserSection(theme),
            const SizedBox(height: 24),
            _buildUploadConfigSection(theme),
            const SizedBox(height: 24),
            _buildUploadProgressSection(theme),
            const SizedBox(height: 24),
            _buildLogoutSection(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildUserSection(ThemeData theme) {
    if (_loadingUser) {
      return const _SectionCard(
        title: 'Account',
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final details = _userDetails;
    return _SectionCard(
      title: 'Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
            label: 'Full name',
            value:
                _safeDisplay(details?.fullName) ??
                _safeDisplay(details?.name) ??
                'Unknown user',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Email / User',
            value: _safeDisplay(details?.user) ?? 'Not available',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Gender',
            value: _safeDisplay(details?.gender) ?? 'Not specified',
          ),
        ],
      ),
    );
  }

  Widget _buildUploadConfigSection(ThemeData theme) {
    if (_loadingPreferences) {
      return const _SectionCard(
        title: 'Upload Preferences',
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    return _SectionCard(
      title: 'Upload Preferences',
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: _isPrivateUploads,
            onChanged: _handlePrivateToggle,
            title: const Text('Upload as private'),
            subtitle: const Text(
              'Store uploaded photos in a private workspace',
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 1),
          SwitchListTile.adaptive(
            value: _optimizeUploads,
            onChanged: _handleOptimizeToggle,
            title: const Text('Optimize images'),
            subtitle: const Text('Compress images before upload to save space'),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 1),
          SwitchListTile.adaptive(
            value: _wifiOnly,
            onChanged: _handleWifiOnlyToggle,
            title: const Text('Wi-Fi only'),
            subtitle: const Text('Upload when connected to Wi-Fi'),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 1),
          SwitchListTile.adaptive(
            value: _whileCharging,
            onChanged: _handleWhileChargingToggle,
            title: const Text('Only while charging'),
            subtitle: const Text('Pause uploads when the device is on battery power'),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 1),
          SwitchListTile.adaptive(
            value: _blockOnRoaming,
            onChanged: _handleBlockOnRoamingToggle,
            title: const Text('Block on roaming'),
            subtitle: const Text('Avoid cellular data charges while travelling'),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Battery threshold'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(
                  _batteryThreshold <= 0
                      ? 'Uploads run at any battery level unless charging is required.'
                      : 'Pause uploads below $_batteryThreshold% unless the device is charging.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Slider(
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: _batteryThreshold == 0
                      ? 'Off'
                      : '$_batteryThreshold%',
                  value: _batteryThreshold.toDouble(),
                  onChanged: _handleBatterySliderChanged,
                  onChangeEnd: _handleBatterySliderChangeEnd,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Upload folder preview'),
            subtitle: Text(
              _describeDefaultFolder(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reset upload metadata'),
            subtitle: const Text(
              'Clears synced photo markers so uploads can run again',
            ),
            trailing: ElevatedButton.icon(
              onPressed: _resettingMetadata ? null : _handleResetMetadata,
              icon: _resettingMetadata
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restart_alt),
              label: Text(_resettingMetadata ? 'Resetting...' : 'Reset'),
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

    return _SectionCard(
      title: 'Background Uploads',
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
            for (final job in displayedJobs)
              _UploadJobRow(
                job: job,
                onCancel: job.status == UploadJobStatus.queued
                    ? () => _uploadQueue.cancelJob(job.assetId)
                    : null,
              ),
            if (hasMore)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _showAllUploads = true;
                    });
                  },
                  child: Text('Show all (${jobs.length})'),
                ),
              ),
            if (showLess)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _showAllUploads = false;
                    });
                  },
                  child: const Text('Show less'),
                ),
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
          ),
          icon: _processingLogout
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.logout),
          label: Text(_processingLogout ? 'Signing out...' : 'Sign out'),
        ),
      ),
    );
  }
}

class _UploadJobRow extends StatelessWidget {
  const _UploadJobRow({required this.job, this.onCancel});

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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
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
          return TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
          );
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
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
