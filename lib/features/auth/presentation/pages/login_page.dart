import 'package:flutter/material.dart';

import '../../data/services/auth_service.dart';
import '../widgets/login_view.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, this.authService});

  static const String routeName = '/login';
  final AuthService? authService;

  @override
  Widget build(BuildContext context) {
    return LoginView(authService: authService);
  }
}
