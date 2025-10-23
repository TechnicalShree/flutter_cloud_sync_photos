import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

class SharedAxisPageRoute<T> extends PageRouteBuilder<T> {
  SharedAxisPageRoute({
    required WidgetBuilder builder,
    SharedAxisTransitionType transitionType =
        SharedAxisTransitionType.scaled,
    RouteSettings? settings,
    Duration transitionDuration = const Duration(milliseconds: 320),
    Duration reverseTransitionDuration = const Duration(milliseconds: 260),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            return SharedAxisTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              transitionType: transitionType,
              fillColor: Colors.transparent,
              child: child,
            );
          },
          settings: settings,
          transitionDuration: transitionDuration,
          reverseTransitionDuration: reverseTransitionDuration,
        );
}
