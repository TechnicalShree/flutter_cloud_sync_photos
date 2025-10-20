import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../home/presentation/pages/home_page.dart';
import '../../data/services/auth_service.dart';

class LoginView extends StatefulWidget {
  LoginView({super.key, AuthService? authService})
    : authService = authService ?? globalAuthService;

  final AuthService authService;

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  late final AuthService _authService;

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6750A4), Color(0xFF312E81)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _LoginCard(
                    formKey: _formKey,
                    usernameController: _usernameController,
                    passwordController: _passwordController,
                    passwordFocusNode: _passwordFocusNode,
                    isLoading: _isLoading,
                    obscurePassword: _obscurePassword,
                    errorMessage: _errorMessage,
                    onTogglePasswordVisibility: _togglePasswordVisibility,
                    onSubmit: _handleSubmit,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  Future<void> _handleSubmit() async {
    if (_isLoading) {
      return;
    }

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Welcome back!')));

      Navigator.of(context).pushReplacementNamed(HomePage.routeName);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = _resolveErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _resolveErrorMessage(Object error) {
    if (error is Exception) {
      return error.toString().replaceFirst('Exception: ', '');
    }
    return 'Something went wrong. Please try again.';
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.passwordFocusNode,
    required this.onSubmit,
    required this.onTogglePasswordVisibility,
    required this.isLoading,
    required this.obscurePassword,
    this.errorMessage,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final FocusNode passwordFocusNode;
  final VoidCallback onSubmit;
  final VoidCallback onTogglePasswordVisibility;
  final bool isLoading;
  final bool obscurePassword;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LoginHeader(theme: theme),
              const SizedBox(height: 24),
              _UsernameField(controller: usernameController),
              const SizedBox(height: 16),
              _PasswordField(
                controller: passwordController,
                focusNode: passwordFocusNode,
                obscureText: obscurePassword,
                onToggleVisibility: onTogglePasswordVisibility,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: isLoading ? null : () {},
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: errorMessage == null
                    ? const SizedBox.shrink()
                    : _ErrorBanner(message: errorMessage!),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isLoading ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('Sign in'),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    Text(
                      "Don't have an account?",
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: isLoading ? null : () {},
                      child: const Text('Create account'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.cloud_sync,
            color: theme.colorScheme.onPrimaryContainer,
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.appTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sign in to sync your memories securely across devices.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _UsernameField extends StatelessWidget {
  const _UsernameField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.username],
      decoration: const InputDecoration(
        labelText: 'Email or username',
        prefixIcon: Icon(Icons.person_outline),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter your email or username';
        }
        return null;
      },
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.focusNode,
    required this.obscureText,
    required this.onToggleVisibility,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscureText;
  final VoidCallback onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      autofillHints: const [AutofillHints.password],
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          onPressed: onToggleVisibility,
          icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your password';
        }
        if (value.length < 6) {
          return 'Password must be at least 6 characters';
        }
        return null;
      },
      onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey(message),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
