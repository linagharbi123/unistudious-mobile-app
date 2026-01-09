
import 'package:flutter/foundation.dart';
import '../models/notification_model.dart';
import 'auth_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class NotificationsListProvider extends ChangeNotifier {
  List<NotificationModel> _notifications = [];
  bool _isLoading = false;
  String? _error;
  AuthProvider? _authProvider;

  List<NotificationModel> get notifications => _notifications;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Compte le nombre de notifications non lues
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Définit le AuthProvider (appelé depuis main.dart ou depuis un widget)
  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
  }

  /// Charge les notifications depuis l'API
  Future<void> loadNotifications([AuthProvider? authProvider]) async {
    final provider = authProvider ?? _authProvider;
    if (provider == null) {
      _error = 'AuthProvider non disponible';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Utiliser authenticatedRequest comme les autres parties de l'app
      final response = await provider.authenticatedRequest('GET', '/api/get-notification');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Le format de réponse est : { "notifications": [...] }
        if (data is Map && data['notifications'] is List) {
          _notifications = (data['notifications'] as List)
              .map((json) => NotificationModel.fromJson(json))
              .toList();
        } else if (data is List) {
          // Fallback si la réponse est directement une liste
          _notifications = data
              .map((json) => NotificationModel.fromJson(json))
              .toList();
        } else {
          _notifications = [];
        }

        _error = null;
      } else {
        _error = 'Erreur ${response.statusCode}';
        _notifications = [];
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors du chargement des notifications: $e');
      }
      _error = 'Erreur de connexion: ${e.toString()}';
      _notifications = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Marque une notification comme lue
  Future<void> markAsRead(String notificationId, [AuthProvider? authProvider]) async {
    final provider = authProvider ?? _authProvider;
    if (provider == null) return;

    try {
      final response = await provider.authenticatedRequest(
        'POST',
        '/api/notifications/$notificationId/read',
      );

      if (response.statusCode == 200) {
        final index = _notifications.indexWhere((n) => n.id == notificationId);
        if (index != -1) {
          _notifications[index] = _notifications[index].copyWith(isRead: true);
          notifyListeners();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors du marquage de la notification comme lue: $e');
      }
    }
  }

  /// Marque toutes les notifications comme lues
  Future<void> markAllAsRead([AuthProvider? authProvider]) async {
    final provider = authProvider ?? _authProvider;
    if (provider == null) return;

    try {
      final response = await provider.authenticatedRequest(
        'POST',
        '/api/notifications/read-all',
      );

      if (response.statusCode == 200) {
        _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors du marquage de toutes les notifications comme lues: $e');
      }
    }
  }

  /// Supprime une notification
  Future<void> deleteNotification(String notificationId, [AuthProvider? authProvider]) async {
    final provider = authProvider ?? _authProvider;
    if (provider == null) return;

    try {
      final response = await provider.authenticatedRequest(
        'DELETE',
        '/api/notifications/$notificationId',
      );

      if (response.statusCode == 200) {
        _notifications.removeWhere((n) => n.id == notificationId);
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors de la suppression de la notification: $e');
      }
    }
  }

  /// Ajoute une notification (pour les nouvelles notifications reçues)
  void addNotification(NotificationModel notification) {
    _notifications.insert(0, notification);
    notifyListeners();
  }

  /// Réinitialise la liste
  void clear() {
    _notifications = [];
    _error = null;
    notifyListeners();
  }
}
