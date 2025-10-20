import 'package:flutter/material.dart';

import '../../data/services/auth_service.dart';
import '../pages/login_page.dart';
import '../../../home/presentation/pages/home_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.authService});

  final AuthService? authService;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _authService;
  late final Future<AuthStatus> _statusFuture;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? globalAuthService;
    _statusFuture = _authService.resolveInitialAuth();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthStatus>(
      future: _statusFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }

        final status = snapshot.data ?? AuthStatus.unauthenticated;

        if (status == AuthStatus.authenticated ||
            status == AuthStatus.offline) {
          return const HomePage();
        }

        return LoginPage(authService: _authService);
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6750A4), Color(0xFF312E81)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_sync,
                size: 64,
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.9),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                height: 32,
                width: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Checking your session...',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
