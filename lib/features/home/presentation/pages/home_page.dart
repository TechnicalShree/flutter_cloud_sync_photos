import 'package:flutter/material.dart';

import '../../../gallery/presentation/pages/gallery_page.dart';
import '../../../counter/presentation/pages/counter_page.dart';

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
      icon: Icon(Icons.dashboard_customize_outlined),
      selectedIcon: Icon(Icons.dashboard_customize),
      label: 'Dashboard',
    ),
  ];

  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final pages = [const GalleryPage(), const CounterPage()];

    return Scaffold(
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
    );
  }
}
