import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../providers/notifications_list_provider.dart';
import '../screens/notifications_list_page.dart';

/// Widget réutilisable pour afficher une icône de notification avec badge
/// Affiche le nombre de notifications non lues et navigue vers la page de notifications au clic
/// Inclut une animation lumineuse lorsqu'une nouvelle notification arrive
class NotificationIconButton extends StatefulWidget {
  const NotificationIconButton({super.key});

  @override
  State<NotificationIconButton> createState() => _NotificationIconButtonState();
}

class _NotificationIconButtonState extends State<NotificationIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;
  bool _hasTriggeredAnimation = false;
  int _lastUnreadCount = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _triggerAnimation() {
    if (_animationController.isAnimating) {
      _animationController.reset();
    }
    _animationController.forward().then((_) {
      if (mounted) {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationsListProvider>(
      builder: (context, provider, child) {
        final unreadCount = provider.unreadCount;
        final hasNewNotification = provider.hasNewNotification;

        // Déclencher l'animation si une nouvelle notification arrive
        if (hasNewNotification && !_hasTriggeredAnimation) {
          if (kDebugMode) {
            print('✨ Animation déclenchée: nouvelle notification détectée');
          }
          _hasTriggeredAnimation = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _triggerAnimation();
              provider.resetNewNotificationFlag();
              // Réinitialiser le flag après un délai
              Future.delayed(const Duration(milliseconds: 2000), () {
                if (mounted) {
                  setState(() {
                    _hasTriggeredAnimation = false;
                  });
                }
              });
            }
          });
        }
        
        // Détecter aussi les changements de nombre directement (fallback)
        if (unreadCount > _lastUnreadCount && _lastUnreadCount > 0) {
          if (kDebugMode) {
            print('✨ Animation déclenchée: changement de nombre ($_lastUnreadCount -> $unreadCount)');
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_hasTriggeredAnimation) {
              _hasTriggeredAnimation = true;
              _triggerAnimation();
              Future.delayed(const Duration(milliseconds: 2000), () {
                if (mounted) {
                  setState(() {
                    _hasTriggeredAnimation = false;
                  });
                }
              });
            }
          });
        }
        
        _lastUnreadCount = unreadCount;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: _glowAnimation.value > 0
                        ? [
                            BoxShadow(
                              color: Colors.orange.withOpacity(_glowAnimation.value * 0.8),
                              blurRadius: 15 * _glowAnimation.value,
                              spreadRadius: 5 * _glowAnimation.value,
                            ),
                            BoxShadow(
                              color: Colors.red.withOpacity(_glowAnimation.value * 0.6),
                              blurRadius: 20 * _glowAnimation.value,
                              spreadRadius: 8 * _glowAnimation.value,
                            ),
                          ]
                        : [],
                  ),
                  child: Transform.scale(
                    scale: _pulseAnimation.value,
                    child: IconButton(
                      icon: const Icon(
                        Icons.notifications_outlined,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NotificationsListPage(),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            if (unreadCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: unreadCount > 99 ? 20 : 18,
                  height: unreadCount > 99 ? 20 : 18,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      unreadCount > 99 ? '99+' : unreadCount.toString(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: unreadCount > 99 ? 8 : 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
