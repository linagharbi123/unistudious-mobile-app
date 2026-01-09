
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FirebaseNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Gets the FCM token for the current device
  /// Returns null if token cannot be retrieved
  static Future<String?> getToken() async {
    try {
      // Request permission for notifications (iOS)
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (kDebugMode) {
        print('🔔 Statut de permission: ${settings.authorizationStatus}');
      }

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        if (kDebugMode) {
          print('✅ Permissions accordées');
        }
      } else {
        if (kDebugMode) {
          print('⚠️ Permissions refusées: ${settings.authorizationStatus}');
        }
        return null;
      }

      // Get the FCM token
      final token = await _messaging.getToken();

      if (kDebugMode && token != null) {
        print('📱 Token FCM: $token');
        print('💡 Enregistre ce token sur ton serveur pour envoyer des notifications ciblées');
      }

      return token;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors de la récupération du token FCM: $e');
      }
      return null;
    }
  }

  /// Deletes the FCM token
  static Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
      if (kDebugMode) {
        print('🗑️ Token FCM supprimé');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors de la suppression du token FCM: $e');
      }
    }
  }

  /// Refreshes the FCM token
  static Future<String?> refreshToken() async {
    try {
      await _messaging.deleteToken();
      return await getToken();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors du rafraîchissement du token FCM: $e');
      }
      return null;
    }
  }
}
