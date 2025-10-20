import 'package:flutter/material.dart';

import '../../../auth/data/services/auth_service.dart';
import '../../../auth/domain/models/user_details.dart';
import '../../../auth/presentation/pages/login_page.dart';
import '../../data/upload_preferences_store.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static const String routeName = '/settings';

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AuthService _authService = globalAuthService;
  final UploadPreferencesStore _preferencesStore = uploadPreferencesStore;

  UserDetails? _userDetails;
  bool _loadingUser = true;
  bool _loadingPreferences = true;
  bool _isPrivateUploads = true;
  bool _optimizeUploads = false;
  bool _processingLogout = false;

  @override
  void initState() {
    super.initState();
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
      _loadingPreferences = false;
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
          Text(
            details?.fullName?.trim().isNotEmpty == true
                ? details!.fullName!.trim()
                : (details?.user ?? 'Unknown user'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (details?.user != null)
            Text(
              details!.user!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (details?.mobileNumber != null &&
              details!.mobileNumber!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                details.mobileNumber!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (details?.address != null && details!.address!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                details.address!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
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
