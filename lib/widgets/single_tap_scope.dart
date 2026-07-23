import 'package:flutter/material.dart';

import '../utils/action_guard.dart';

/// Bloque les taps rapides en double dans toute l'application.
class SingleTapScope extends StatefulWidget {
  final Widget child;
  final Duration tapCooldown;
  final bool externalLock;

  const SingleTapScope({
    super.key,
    required this.child,
    this.tapCooldown = const Duration(milliseconds: 500),
    this.externalLock = false,
  });

  @override
  State<SingleTapScope> createState() => _SingleTapScopeState();
}

class _SingleTapScopeState extends State<SingleTapScope> {
  bool _tapLocked = false;
  Offset? _pointerDownPosition;

  bool get _shouldAbsorb =>
      _tapLocked || widget.externalLock || ActionGuard.instance.isBusy;

  void _onActionGuardChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ActionGuard.instance.addListener(_onActionGuardChanged);
  }

  @override
  void dispose() {
    ActionGuard.instance.removeListener(_onActionGuardChanged);
    super.dispose();
  }

  void _scheduleUnlock() {
    Future<void>.delayed(widget.tapCooldown, () async {
      while (ActionGuard.instance.isBusy && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (mounted) setState(() => _tapLocked = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _pointerDownPosition = event.position;
      },
      onPointerUp: (event) {
        if (_tapLocked || widget.externalLock || ActionGuard.instance.isBusy) {
          return;
        }
        final down = _pointerDownPosition;
        _pointerDownPosition = null;
        if (down != null && (event.position - down).distance > 18) return;

        setState(() => _tapLocked = true);
        _scheduleUnlock();
      },
      onPointerCancel: (_) => _pointerDownPosition = null,
      child: AbsorbPointer(
        absorbing: _shouldAbsorb,
        child: widget.child,
      ),
    );
  }
}
