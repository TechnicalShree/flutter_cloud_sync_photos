import 'package:flutter/material.dart';

import '../../../albums/presentation/pages/album_page.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../gallery/presentation/pages/gallery_page.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../synced/presentation/pages/synced_photos_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static const String routeName = '/home';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthService _authService = globalAuthService;
  _HomeDestinationKey _selectedDestination = _HomeDestinationKey.gallery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ValueListenableBuilder<AuthStatus>(
      valueListenable: _authService.authStatusNotifier,
      builder: (context, status, _) {
        final destinations = _buildDestinations(status);
        final pages = destinations.map((item) => item.page).toList();

        int selectedIndex =
            destinations.indexWhere((item) => item.key == _selectedDestination);
        if (selectedIndex == -1 && destinations.isNotEmpty) {
          final fallbackKey = destinations.first.key;
          if (_selectedDestination != fallbackKey) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              setState(() {
                _selectedDestination = fallbackKey;
              });
            });
          }
          selectedIndex = 0;
        }

        return PopScope(
          canPop: _selectedDestination == _HomeDestinationKey.gallery,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              return;
            }
            if (_selectedDestination != _HomeDestinationKey.gallery) {
              setState(() {
                _selectedDestination = _HomeDestinationKey.gallery;
              });
            }
          },
          child: Scaffold(
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: pages[selectedIndex],
            ),
            bottomNavigationBar: NavigationBar(
              destinations:
                  destinations.map((item) => item.destination).toList(),
              selectedIndex: selectedIndex,
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              backgroundColor: colorScheme.surface,
              elevation: 12,
              onDestinationSelected: (index) {
                final target = destinations[index];
                if (target.key == _selectedDestination) {
                  return;
                }
                setState(() {
                  _selectedDestination = target.key;
                });
              },
            ),
          ),
        );
      },
    );
  }
}

enum _HomeDestinationKey { gallery, albums, synced, settings }

class _HomeDestination {
  const _HomeDestination({
    required this.key,
    required this.destination,
    required this.page,
  });

  final _HomeDestinationKey key;
  final NavigationDestination destination;
  final Widget page;
}

List<_HomeDestination> _buildDestinations(AuthStatus status) {
  final isAuthenticated =
      status == AuthStatus.authenticated || status == AuthStatus.offline;

  final destinations = <_HomeDestination>[
    _HomeDestination(
      key: _HomeDestinationKey.gallery,
      destination: const NavigationDestination(
        icon: Icon(Icons.photo_library_outlined),
        selectedIcon: Icon(Icons.photo_library),
        label: 'Gallery',
      ),
      page: const GalleryPage(),
    ),
    _HomeDestination(
      key: _HomeDestinationKey.albums,
      destination: const NavigationDestination(
        icon: Icon(Icons.photo_album_outlined),
        selectedIcon: Icon(Icons.photo_album),
        label: 'Albums',
      ),
      page: const AlbumPage(),
    ),
  ];

  if (isAuthenticated) {
    destinations.add(
      _HomeDestination(
        key: _HomeDestinationKey.synced,
        destination: const NavigationDestination(
          icon: Icon(Icons.cloud_done_outlined),
          selectedIcon: Icon(Icons.cloud_done),
          label: 'Synced',
        ),
        page: const SyncedPhotosPage(),
      ),
    );
  }

  destinations.add(
    _HomeDestination(
      key: _HomeDestinationKey.settings,
      destination: const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Settings',
      ),
      page: const SettingsPage(),
    ),
  );

  return destinations;
}
