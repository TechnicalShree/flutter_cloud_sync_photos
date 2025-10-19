import 'package:flutter/material.dart';

import '../widgets/counter_view.dart';

class CounterPage extends StatelessWidget {
  const CounterPage({super.key});

  static const String routeName = '/';

  @override
  Widget build(BuildContext context) {
    return const CounterView();
  }
}
