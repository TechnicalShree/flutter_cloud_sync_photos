import 'dart:math' as math;

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

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutSine,
    );
    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.04).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutBack),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.55, 1.0, curve: Curves.easeInCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _AnimatedGradientBackground(animation: _curve),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.onPrimary
                                  .withOpacity(0.25),
                              blurRadius: 28,
                              spreadRadius: 1,
                            ),
                          ],
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withOpacity(0.25),
                              Colors.white.withOpacity(0.05),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Icon(
                            Icons.cloud_sync,
                            size: 68,
                            color: theme.colorScheme.onPrimary
                                .withOpacity(0.9),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: SizedBox(
                        height: 40,
                        width: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final shimmerValue =
                            (math.sin(_controller.value * math.pi * 2) + 1) / 2;
                        return Opacity(
                          opacity: 0.7 + (shimmerValue * 0.3),
                          child: child,
                        );
                      },
                      child: Text(
                        'Verifying your account…',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color:
                              theme.colorScheme.onPrimary.withOpacity(0.92),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final dots = 1 + ((_controller.value * 3).floor() % 3);
                        final message = 'Hang tight' + '.' * dots;
                        return Text(
                          message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimary
                                .withOpacity(0.7),
                          ),
                        );
                      },
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
}

class _AnimatedGradientBackground extends StatelessWidget {
  const _AnimatedGradientBackground({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        final accentShift = (math.sin((t + 0.3) * math.pi * 2) + 1) / 2;
        final glowShift = (math.cos((t - 0.15) * math.pi * 2) + 1) / 2;
        final primary = Color.lerp(
          const Color(0xFF342EAD),
          const Color(0xFF1B1464),
          glowShift,
        )!;
        final secondary = Color.lerp(
          const Color(0xFF6D28D9),
          const Color(0xFF4CC9F0),
          accentShift,
        )!;
        final tertiary = Color.lerp(
          const Color(0xFF3B82F6),
          const Color(0xFF9333EA),
          1 - accentShift,
        )!;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(
                _lerp(-1.0, 0.8, t),
                _lerp(-0.8, -0.2, t),
              ),
              end: Alignment(
                _lerp(0.9, -0.6, t),
                _lerp(1.0, 0.4, t),
              ),
              colors: [primary, secondary, tertiary],
            ),
          ),
          child: Stack(
            children: [
              _GlowingOrb(
                left: _lerp(32, 96, glowShift),
                top: _lerp(120, 200, accentShift),
                size: _lerp(140, 190, accentShift),
                color: secondary.withOpacity(0.18),
              ),
              _GlowingOrb(
                right: _lerp(48, 16, accentShift),
                bottom: _lerp(60, 140, glowShift),
                size: _lerp(120, 160, glowShift),
                color: tertiary.withOpacity(0.15),
              ),
              _GlowingOrb(
                left: _lerp(140, 60, accentShift),
                bottom: _lerp(240, 180, glowShift),
                size: _lerp(80, 110, accentShift),
                color: Colors.white.withOpacity(0.12),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GlowingOrb extends StatelessWidget {
  const _GlowingOrb({
    this.left,
    this.right,
    this.top,
    this.bottom,
    required this.size,
    required this.color,
  });

  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.55),
              blurRadius: size * 0.45,
              spreadRadius: size * 0.12,
            ),
          ],
        ),
      ),
    );
  }
}

double _lerp(double start, double end, double t) {
  return start + (end - start) * t;
}
