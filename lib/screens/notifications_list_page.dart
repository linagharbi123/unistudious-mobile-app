
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/notifications_list_provider.dart';
import '../providers/auth_provider.dart';
import '../models/notification_model.dart';
import '../providers/theme_provider.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toutes les notifications ont été marquées comme lues'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    final provider = Provider.of<NotificationsListProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await provider.deleteNotification(notificationId, authProvider);
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
      appBar: AppBar(
        title: const Text(
          'Mes notifications',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
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
              if (provider.unreadCount > 0) {
                return IconButton(
                  icon: const Icon(Icons.done_all),
                  tooltip: 'Marquer tout comme lu',
                  onPressed: _markAllAsRead,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<NotificationsListProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return Center(
              child: CircularProgressIndicator(
                color: theme.primaryColor,
              ),
            );
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Erreur: ${provider.error}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadNotifications,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }

          if (provider.notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Aucune notification',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadNotifications,
            color: theme.primaryColor,
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: provider.notifications.length,
              itemBuilder: (context, index) {
                final notification = provider.notifications[index];
                return _buildNotificationCard(notification, theme, isDark);
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
      ) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: notification.isRead
          ? theme.cardColor
          : (isDark ? const Color(0xFF2A1A4D) : const Color(0xFFF3E5F5)),
      elevation: notification.isRead ? 1 : 3,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 8.0,
        ),
        leading: CircleAvatar(
          backgroundColor: notification.isRead
              ? Colors.grey[300]
              : theme.primaryColor,
          child: Icon(
            _getNotificationIcon(notification.type),
            color: notification.isRead ? Colors.grey[600] : Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          notification.name,
          style: TextStyle(
            fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              notification.message,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey[700],
                fontSize: 14,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              _formatDate(notification.createdAt),
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) => [
            if (!notification.isRead)
              PopupMenuItem(
                value: 'read',
                child: const Row(
                  children: [
                    Icon(Icons.check, size: 20),
                    SizedBox(width: 8),
                    Text('Marquer comme lu'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Supprimer', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'read') {
              _markAsRead(notification.id);
            } else if (value == 'delete') {
              _deleteNotification(notification.id);
            }
          },
        ),
        onTap: () {
          if (!notification.isRead) {
            _markAsRead(notification.id);
          }
          // Ici, tu peux ajouter la navigation vers une page spécifique
          // basée sur notification.type et notification.idType
        },
      ),
    );
  }

  IconData _getNotificationIcon(String type) {
    switch (type.toLowerCase()) {
      case 'payment':
        return Icons.payment;
      case 'session':
      case 'validation session':
        return Icons.event;
      case 'poll':
        return Icons.poll;
      case 'message':
        return Icons.message;
      case 'social':
        return Icons.people;
      default:
        return Icons.notifications;
    }
  }
}
