import 'package:flutter/material.dart';

import '../../../albums/presentation/pages/album_page.dart';
import '../../../gallery/presentation/pages/gallery_page.dart';
import '../../../synced/presentation/pages/synced_photos_page.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../uploads/presentation/pages/synced_photos_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  static const String routeName = '/home';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.photo_library_outlined),
      selectedIcon: Icon(Icons.photo_library),
      label: 'Gallery',
    ),
    NavigationDestination(
      icon: Icon(Icons.photo_album_outlined),
      selectedIcon: Icon(Icons.photo_album),
      label: 'Albums',
    ),
    NavigationDestination(
      icon: Icon(Icons.cloud_done_outlined),
      selectedIcon: Icon(Icons.cloud_done),
      label: 'Synced',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final pages = [
      const GalleryPage(),
      const AlbumPage(),
      const SyncedPhotosPage(),
      const SettingsPage(),
    ];

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
        }
      },
      child: Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: pages[_currentIndex],
        ),
        bottomNavigationBar: NavigationBar(
          destinations: _destinations,
          selectedIndex: _currentIndex,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          backgroundColor: colorScheme.surface,
          elevation: 12,
          onDestinationSelected: (index) {
            if (_currentIndex == index) {
              return;
            }
            setState(() {
              _currentIndex = index;
            });
          },
        ),
      ),
    );
  }
}
