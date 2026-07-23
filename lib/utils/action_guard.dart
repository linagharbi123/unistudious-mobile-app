import 'package:flutter/foundation.dart';

/// Empêche les actions en double : clics multiples, requêtes dupliquées, navigations répétées.
class ActionGuard extends ChangeNotifier {
  ActionGuard._();

  static final ActionGuard instance = ActionGuard._();

  final Set<Object> _locks = {};
  int _activeAsyncCount = 0;

  bool get isBusy => _locks.isNotEmpty || _activeAsyncCount > 0;

  bool isLocked(Object key) => _locks.contains(key);

  /// Exécute une action async une seule fois par clé jusqu'à sa fin.
  Future<T?> run<T>(Object key, Future<T?> Function() action) async {
    if (_locks.contains(key)) return null;
    _locks.add(key);
    _activeAsyncCount++;
    notifyListeners();
    try {
      return await action();
    } finally {
      _locks.remove(key);
      _activeAsyncCount--;
      notifyListeners();
    }
  }

  /// Exécute une action synchrone avec verrouillage temporaire.
  void runSync(
    Object key,
    VoidCallback action, {
    Duration hold = const Duration(milliseconds: 600),
  }) {
    if (_locks.contains(key)) return;
    _locks.add(key);
    notifyListeners();
    try {
      action();
    } finally {
      Future<void>.delayed(hold, () {
        _locks.remove(key);
        notifyListeners();
      });
    }
  }

  /// Enveloppe un callback (sync ou async) pour éviter les doubles exécutions.
  VoidCallback? wrap(Object key, VoidCallback? callback) {
    if (callback == null) return null;
    return () => run(key, () async {
      callback();
    });
  }
}

extension GuardedCallbackExt on VoidCallback {
  VoidCallback guarded([Object? key]) =>
      ActionGuard.instance.wrap(key ?? this, this)!;
}

extension GuardedNullableCallbackExt on VoidCallback? {
  VoidCallback? guarded([Object? key]) {
    if (this == null) return null;
    return ActionGuard.instance.wrap(key ?? this!, this);
  }
}

extension GuardedAsyncCallbackExt on Future<void> Function() {
  VoidCallback get guarded =>
      () => ActionGuard.instance.run(this, this);
}
