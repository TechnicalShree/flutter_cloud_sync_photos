import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/widgets/auth_gate.dart';
import 'features/albums/presentation/pages/album_page.dart';
import 'features/home/presentation/pages/home_page.dart';
import 'features/settings/presentation/pages/settings_page.dart';

class CloudSyncPhotosApp extends StatelessWidget {
  const CloudSyncPhotosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final lightTheme = AppTheme.light(lightDynamic);
        final darkTheme = AppTheme.dark(darkDynamic);

        return MaterialApp(
          title: AppStrings.appTitle,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: ThemeMode.system,
          debugShowCheckedModeBanner: false,
          home: const AuthGate(),
          routes: {
            LoginPage.routeName: (_) => const LoginPage(),
            HomePage.routeName: (_) => const HomePage(),
            AlbumPage.routeName: (_) => const AlbumPage(),
            SettingsPage.routeName: (_) => const SettingsPage(),
          },
        );
      },
    );
  }
}
