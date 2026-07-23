import 'package:flutter/material.dart';

import 'action_guard.dart';

extension GuardedNavigation on BuildContext {
  Future<T?> pushNamedGuarded<T extends Object?>(
    String routeName, {
    Object? arguments,
  }) {
    final key = 'push_$routeName';
    return ActionGuard.instance.run<T?>(
      key,
      () => Navigator.of(this).pushNamed<T>(routeName, arguments: arguments),
    );
  }

  Future<T?> pushReplacementNamedGuarded<T extends Object?, TO extends Object?>(
    String routeName, {
    TO? result,
    Object? arguments,
  }) {
    final key = 'pushReplacement_$routeName';
    return ActionGuard.instance.run<T?>(
      key,
      () => Navigator.of(this).pushReplacementNamed<T, TO>(
            routeName,
            result: result,
            arguments: arguments,
          ),
    );
  }

  Future<T?> pushGuarded<T extends Object?>(Route<T> route) {
    final key = 'push_${route.settings.name ?? route.hashCode}';
    return ActionGuard.instance.run<T?>(
      key,
      () => Navigator.of(this).push<T>(route),
    );
  }

  void popGuarded<T extends Object?>([T? result]) {
    ActionGuard.instance.runSync(
      'pop_${ModalRoute.of(this)?.settings.name ?? hashCode}',
      () => Navigator.of(this).pop<T>(result),
    );
  }
}
