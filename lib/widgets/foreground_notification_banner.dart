import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notification_provider.dart';
import '../providers/theme_provider.dart';

/// Widget qui affiche une bannière de notification en haut de l'écran quand l'app est en foreground
class ForegroundNotificationBanner extends StatelessWidget {
  const ForegroundNotificationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, notificationProvider, child) {
        if (!notificationProvider.isVisible) {
          return const SizedBox.shrink();
        }

        final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
        final isDark = themeProvider.themeMode == ThemeMode.dark;

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: -100.0, end: 0.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, value),
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                            width: 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: () {
                            notificationProvider.hideNotification();
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.notifications_active,
                                    color: Colors.deepPurple,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        notificationProvider.currentTitle ?? 'Notification',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        notificationProvider.currentBody ?? '',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                  onPressed: () {
                                    notificationProvider.hideNotification();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}



