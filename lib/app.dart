import 'package:flutter/material.dart';

import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/widgets/auth_gate.dart';
import 'features/counter/presentation/pages/counter_page.dart';

class CloudSyncPhotosApp extends StatelessWidget {
  const CloudSyncPhotosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appTitle,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
      routes: {
        LoginPage.routeName: (_) => const LoginPage(),
        CounterPage.routeName: (_) => const CounterPage(),
      },
    );
  }
}
