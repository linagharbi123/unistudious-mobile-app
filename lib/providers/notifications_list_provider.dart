
import 'package:flutter/foundation.dart';
import '../models/notification_model.dart';
import 'auth_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class NotificationsListProvider extends ChangeNotifier {
  List<NotificationModel> _notifications = [];
  bool _isLoading = false;
  String? _error;
  AuthProvider? _authProvider;
  bool _hasNewNotification = false;
  int? _notificationCount; // Nombre de notifications depuis l'API de comptage
  bool _isUpdatingCount = false; // Flag pour éviter les appels multiples simultanés
  DateTime? _lastUpdateAttempt; // Dernière tentative de mise à jour
  int _consecutiveErrors = 0; // Nombre d'erreurs consécutives pour backoff exponentiel
  
  // Référence statique pour accéder au provider depuis n'importe où
  static NotificationsListProvider? _instance;
  
  NotificationsListProvider() {
    _instance = this;
  }
  
  static NotificationsListProvider? get instance => _instance;

  List<NotificationModel> get notifications => _notifications;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasNewNotification => _hasNewNotification;

  /// Compte le nombre de notifications non lues
  /// Utilise le nombre depuis l'API de comptage si disponible, sinon calcule depuis la liste
  int get unreadCount {
    if (_notificationCount != null) {
      return _notificationCount!;
    }
    return _notifications.where((n) => !n.isRead).length;
  }
  
  /// Réinitialise le flag de nouvelle notification
  void resetNewNotificationFlag() {
    _hasNewNotification = false;
    notifyListeners();
  }

  /// Définit le AuthProvider (appelé depuis main.dart ou depuis un widget)
  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
  }

  /// Met à jour le nombre de notifications depuis l'API de comptage
  /// Plus efficace que de charger toutes les notifications
  /// Évite les appels multiples simultanés avec debouncing et timeout
  Future<void> updateNotificationCount([AuthProvider? authProvider]) async {
    // Éviter les appels multiples simultanés
    if (_isUpdatingCount) {
      if (kDebugMode) {
        print('⏳ Mise à jour déjà en cours, skip...');
      }
      return;
    }
    
    final provider = authProvider ?? _authProvider;
    if (provider == null) {
      if (kDebugMode) {
        print('⚠️ AuthProvider non disponible pour mettre à jour le nombre de notifications');
      }
      return;
    }

    // Debouncing: éviter les appels trop fréquents (minimum 2 secondes entre les appels)
    final now = DateTime.now();
    if (_lastUpdateAttempt != null) {
      final timeSinceLastAttempt = now.difference(_lastUpdateAttempt!);
      const minInterval = Duration(seconds: 2);
      
      if (timeSinceLastAttempt < minInterval) {
        if (kDebugMode) {
          print('⏳ Appel trop récent (${timeSinceLastAttempt.inMilliseconds}ms), skip...');
        }
        return;
      }
    }

    // Backoff exponentiel: si on a eu des erreurs consécutives, attendre plus longtemps
    if (_consecutiveErrors > 0) {
      final backoffDuration = Duration(seconds: 2 * (1 << (_consecutiveErrors - 1).clamp(0, 4)));
      if (_lastUpdateAttempt != null) {
        final timeSinceLastAttempt = now.difference(_lastUpdateAttempt!);
        if (timeSinceLastAttempt < backoffDuration) {
          if (kDebugMode) {
            print('⏳ Backoff exponentiel: attendre ${backoffDuration.inSeconds}s (erreurs: $_consecutiveErrors)');
          }
          return;
        }
      }
    }

    _isUpdatingCount = true;
    _lastUpdateAttempt = now;
    
    try {
      // Ajouter un timeout de 10 secondes pour éviter les attentes infinies
      final response = await provider.authenticatedRequest('GET', '/api/count/all/notification')
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('La requête a expiré après 10 secondes', const Duration(seconds: 10));
            },
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Sauvegarder l'ancien nombre pour détecter les nouvelles notifications
        final oldCount = _notificationCount ?? 0;
        
        if (data is Map && data['notificationCount'] != null) {
          final newCount = data['notificationCount'] as int;
          
          // Vérifier si une nouvelle notification est arrivée
          if (newCount > oldCount && oldCount >= 0) {
            _hasNewNotification = true;
            if (kDebugMode) {
              print('🔔 Nouvelle notification détectée: $oldCount -> $newCount');
            }
          }
          
          _notificationCount = newCount;
          
          // Réinitialiser le compteur d'erreurs en cas de succès
          _consecutiveErrors = 0;
          
          // Notifier immédiatement pour mettre à jour l'UI
          notifyListeners();
          
          if (kDebugMode) {
            print('✅ Nombre de notifications mis à jour en temps réel: $_notificationCount');
          }
        } else {
          if (kDebugMode) {
            print('⚠️ Format de réponse inattendu pour /api/count/all/notification: $data');
          }
          _consecutiveErrors++;
        }
      } else {
        if (kDebugMode) {
          print('❌ Erreur ${response.statusCode} lors de la récupération du nombre de notifications');
        }
        _consecutiveErrors++;
      }
    } on TimeoutException catch (e) {
      _consecutiveErrors++;
      if (kDebugMode) {
        print('⏱️ Timeout lors de la mise à jour du nombre de notifications: $e');
      }
    } catch (e) {
      _consecutiveErrors++;
      if (kDebugMode) {
        print('❌ Erreur lors de la mise à jour du nombre de notifications: $e');
      }
    } finally {
      _isUpdatingCount = false;
    }
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

        // Sauvegarder l'ancien nombre de notifications non lues
        final oldUnreadCount = unreadCount;
        
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

        // Vérifier si une nouvelle notification non lue est arrivée
        final newUnreadCount = unreadCount;
        if (newUnreadCount > oldUnreadCount) {
          _hasNewNotification = true;
          if (kDebugMode) {
            print('🔔 Nouvelle notification détectée: $oldUnreadCount -> $newUnreadCount');
          }
        }
        
        // Mettre à jour le compteur depuis la liste chargée
        _notificationCount = newUnreadCount;

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
      // Requête POST sans body, sans Content-Type
      final token = provider.currentToken;
      if (token == null) return;
      
      final uri = Uri.parse('https://www.unistudious.com/api/mark-as-read-notification/$notificationId');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          // Pas de Content-Type car pas de body
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Vérifier si la réponse contient le message de succès
        if (responseData['success'] != null || response.statusCode == 200) {
          final index = _notifications.indexWhere((n) => n.id == notificationId);
          if (index != -1) {
            _notifications[index] = _notifications[index].copyWith(isRead: true);
          }
          // Mettre à jour le compteur depuis l'API
          await updateNotificationCount(provider);
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
      // Requête POST sans body, sans Content-Type
      final token = provider.currentToken;
      if (token == null) return;
      
      final uri = Uri.parse('https://www.unistudious.com/api/mark-as-read-all-notification');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          // Pas de Content-Type car pas de body
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Vérifier si la réponse contient le message de succès
        if (responseData['success'] != null || response.statusCode == 200) {
          _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
          // Mettre à jour le compteur depuis l'API
          await updateNotificationCount(provider);
        }
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

  /// Supprime toutes les notifications
  Future<void> deleteAllNotifications([AuthProvider? authProvider]) async {
    final provider = authProvider ?? _authProvider;
    if (provider == null) return;

    try {
      // Requête POST sans body, sans Content-Type
      final token = provider.currentToken;
      if (token == null) return;
      
      final uri = Uri.parse('https://www.unistudious.com/api/delete-all-notification');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          // Pas de Content-Type car pas de body
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // Vérifier si la réponse contient le message de succès
        if (responseData['success'] != null || response.statusCode == 200) {
          _notifications.clear();
          notifyListeners();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors de la suppression de toutes les notifications: $e');
      }
      // Fallback: supprimer localement même si l'API échoue
      _notifications.clear();
      notifyListeners();
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
