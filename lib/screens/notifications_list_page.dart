
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/notifications_list_provider.dart';
import '../providers/auth_provider.dart';
import '../models/notification_model.dart';
import '../providers/theme_provider.dart';
import '../utils/snackbar_helper.dart';

class NotificationsListPage extends StatefulWidget {
  const NotificationsListPage({super.key});

  @override
  State<NotificationsListPage> createState() => _NotificationsListPageState();
}

class _NotificationsListPageState extends State<NotificationsListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNotifications();
    });
  }

  Future<void> _loadNotifications() async {
    final provider = Provider.of<NotificationsListProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await provider.loadNotifications(authProvider);
  }

  Future<void> _markAsRead(String notificationId) async {
    final provider = Provider.of<NotificationsListProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await provider.markAsRead(notificationId, authProvider);
  }

  Future<void> _markAllAsRead() async {
    final provider = Provider.of<NotificationsListProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await provider.markAllAsRead(authProvider);
    if (mounted) {
      SnackBarHelper.showSuccess(
        context,
        'Toutes les notifications ont été marquées comme lues',
      );
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    final provider = Provider.of<NotificationsListProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await provider.deleteNotification(notificationId, authProvider);
  }

  Future<void> _deleteAllNotifications() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer toutes les notifications'),
        content: const Text(
          'Êtes-vous sûr de vouloir supprimer toutes les notifications ? Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer tout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final provider = Provider.of<NotificationsListProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await provider.deleteAllNotifications(authProvider);
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          'Toutes les notifications ont été supprimées',
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'À l\'instant';
        }
        return 'Il y a ${difference.inMinutes} min';
      }
      return 'Il y a ${difference.inHours} h';
    } else if (difference.inDays == 1) {
      return 'Hier';
    } else if (difference.inDays < 7) {
      return 'Il y a ${difference.inDays} jours';
    } else {
      return DateFormat('dd/MM/yyyy').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Consumer<NotificationsListProvider>(
          builder: (context, provider, child) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
          'Mes notifications',
          style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
            color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                if (provider.unreadCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      '${provider.unreadCount} non lue${provider.unreadCount > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF1A003D), Color(0xFF3C0D73)]
                  : const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          Consumer<NotificationsListProvider>(
            builder: (context, provider, child) {
              if (provider.notifications.isEmpty) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bouton Marquer tout comme lu
                  if (provider.unreadCount > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: _markAllAsRead,
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Icon(
                              Icons.done_all,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Bouton Supprimer tout
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _deleteAllNotifications,
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Icon(
                            Icons.delete_sweep,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<NotificationsListProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                color: theme.primaryColor,
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Chargement...',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }

          if (provider.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                    Icons.error_outline,
                    size: 64,
                        color: Colors.red[400],
                      ),
                  ),
                    const SizedBox(height: 24),
                  Text(
                      'Erreur',
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      provider.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                    onPressed: _loadNotifications,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (provider.notifications.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.grey[800] : Colors.grey[200]),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                    Icons.notifications_none,
                    size: 64,
                        color: isDark ? Colors.grey[500] : Colors.grey[400],
                      ),
                  ),
                    const SizedBox(height: 24),
                  Text(
                    'Aucune notification',
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Vous n\'avez pas encore de notifications',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 14,
                    ),
                  ),
                ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadNotifications,
            color: theme.primaryColor,
            backgroundColor: isDark ? Colors.grey[800] : Colors.white,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              itemCount: provider.notifications.length,
              itemBuilder: (context, index) {
                final notification = provider.notifications[index];
                return _buildNotificationCard(notification, theme, isDark, index);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationCard(
      NotificationModel notification,
      ThemeData theme,
      bool isDark,
      int index,
      ) {
    final isUnread = !notification.isRead;
    
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12.0),
        decoration: BoxDecoration(
          color: isUnread
              ? (isDark 
                  ? const Color(0xFF1E1E2E) 
                  : Colors.white)
              : (isDark 
                  ? const Color(0xFF151515) 
                  : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: isUnread
              ? Border.all(
                  color: isDark 
                      ? _getNotificationColor(notification.type, isDark).withOpacity(0.4)
                      : _getNotificationColor(notification.type, isDark).withOpacity(0.3),
                  width: 1.5,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: isDark 
                  ? Colors.black.withOpacity(0.3)
                  : Colors.black.withOpacity(0.05),
              blurRadius: isUnread ? 12 : 4,
              offset: Offset(0, isUnread ? 4 : 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              if (!notification.isRead) {
                _markAsRead(notification.id);
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Indicateur de notification non lue
                  if (isUnread)
                    Container(
                      width: 4,
                      height: 60,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _getNotificationGradient(notification.type, isDark),
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    )
                  else
                    const SizedBox(width: 4),
                  // Icône
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: isUnread
                          ? LinearGradient(
                              colors: _getNotificationGradient(notification.type, isDark),
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isUnread ? null : (isDark ? Colors.grey[800] : Colors.grey[200]),
                      shape: BoxShape.circle,
                      boxShadow: isUnread
                          ? [
                              BoxShadow(
                                color: _getNotificationColor(notification.type, isDark).withOpacity(0.4),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      _getNotificationIcon(notification.type),
                      color: isUnread 
                          ? Colors.white 
                          : _getNotificationColor(notification.type, isDark).withOpacity(0.7),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Contenu
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
          notification.name,
          style: TextStyle(
                                  fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                                  fontSize: 16,
            color: isDark ? Colors.white : Colors.black87,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            PopupMenuButton(
                              icon: Icon(
                                Icons.more_vert,
                                size: 20,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'read',
                                  child: Row(
          children: [
                                      Icon(
                                        Icons.check,
                                        size: 20,
                                        color: notification.isRead 
                                            ? (isDark ? Colors.grey[400] : Colors.grey[600])
                                            : Colors.green,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Marquer comme lu',
                                        style: TextStyle(
                                          color: notification.isRead
                                              ? (isDark ? Colors.grey[300] : Colors.grey[600])
                                              : (isDark ? Colors.white : Colors.black87),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'read') {
                                  _markAsRead(notification.id);
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
            Text(
              notification.message,
              style: TextStyle(
                            color: isDark 
                                ? Colors.grey[300] 
                                : Colors.grey[700],
                fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: isDark ? Colors.grey[600] : Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
            Text(
              _formatDate(notification.createdAt),
              style: TextStyle(
                                color: isDark ? Colors.grey[600] : Colors.grey[500],
                fontSize: 12,
                                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
                  ],
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getNotificationIcon(String type) {
    switch (type.toLowerCase()) {
      case 'payment':
        return Icons.account_balance_wallet_rounded;
      case 'session':
      case 'validation session':
        return Icons.calendar_today_rounded;
      case 'poll':
        return Icons.poll_rounded;
      case 'message':
        return Icons.chat_bubble_rounded;
      case 'social':
        return Icons.people_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getNotificationColor(String type, bool isDark) {
    switch (type.toLowerCase()) {
      case 'payment':
        return isDark ? const Color(0xFF4CAF50) : const Color(0xFF2E7D32);
      case 'session':
      case 'validation session':
        return isDark ? const Color(0xFF2196F3) : const Color(0xFF1976D2);
      case 'poll':
        return isDark ? const Color(0xFFFF9800) : const Color(0xFFF57C00);
      case 'message':
        return isDark ? const Color(0xFF9C27B0) : const Color(0xFF7B1FA2);
      case 'social':
        return isDark ? const Color(0xFFE91E63) : const Color(0xFFC2185B);
      default:
        return isDark ? const Color(0xFF607D8B) : const Color(0xFF455A64);
    }
  }

  List<Color> _getNotificationGradient(String type, bool isDark) {
    final baseColor = _getNotificationColor(type, isDark);
    return [
      baseColor,
      baseColor.withOpacity(0.7),
    ];
  }
}
