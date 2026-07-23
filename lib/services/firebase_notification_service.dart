import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';

class FirebaseNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static String? _lastSavedToken;
  static const _iosNotificationChannel = MethodChannel('com.unistudious.projet1v2/notifications');

  /// Sur iOS : force l'enregistrement pour les notifications à distance (APNs).
  /// À appeler après que l'utilisateur ait accordé la permission.
  static Future<void> _registerForRemoteNotificationsIOS() async {
    if (!Platform.isIOS) return;
    try {
      await _iosNotificationChannel.invokeMethod('registerForRemoteNotifications');
      if (kDebugMode) {
        print('✅ registerForRemoteNotifications invoqué côté natif iOS');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Erreur registerForRemoteNotifications iOS: $e');
      }
    }
  }

  /// Gets the FCM token for the current device
  /// Returns null if token cannot be retrieved
  static Future<String?> getToken() async {
    try {
      // Sur iOS, demander les permissions explicitement
      if (Platform.isIOS) {
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
          print('🔔 Statut de permission iOS: ${settings.authorizationStatus}');
        }

        if (settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional) {
          if (kDebugMode) {
            print('✅ Permissions iOS accordées');
          }
          await _registerForRemoteNotificationsIOS();
          // Petit délai pour laisser iOS transmettre le token APNs à Firebase
          await Future.delayed(const Duration(milliseconds: 500));
        } else {
          if (kDebugMode) {
            print('⚠️ Permissions iOS refusées: ${settings.authorizationStatus}');
          }
          return null;
        }
      } else if (Platform.isAndroid) {
        // Sur Android, les permissions sont gérées par le système
        // Le token peut être récupéré même si les notifications ne sont pas encore autorisées
        if (kDebugMode) {
          print('📱 Plateforme Android détectée');
        }
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

  /// Vérifie si les notifications sont activées sur l'appareil.
  /// Sur Android < 13, les notifications sont activées par défaut.
  static Future<bool> isNotificationPermissionGranted() async {
    try {
      if (Platform.isIOS) {
        final settings = await _messaging.getNotificationSettings();
        return settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      } else if (Platform.isAndroid) {
        // Android 13+ (API 33) requiert la permission POST_NOTIFICATIONS
        final status = await Permission.notification.status;
        return status.isGranted;
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur vérification permission notifications: $e');
      }
      return false;
    }
  }

  /// Demande la permission d'afficher les notifications.
  /// Sur iOS : dialogue natif de l'OS.
  /// Sur Android 13+ : dialogue natif POST_NOTIFICATIONS.
  /// Sur Android < 13 : retourne true car pas de permission requise.
  static Future<bool> requestNotificationPermission() async {
    try {
      if (Platform.isIOS) {
        final settings = await _messaging.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );
        final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
        if (kDebugMode) {
          print('🔔 Permission iOS: ${settings.authorizationStatus}');
        }
        if (granted) {
          await _registerForRemoteNotificationsIOS();
        }
        return granted;
      } else if (Platform.isAndroid) {
        final status = await Permission.notification.request();
        if (kDebugMode) {
          print('🔔 Permission Android: $status');
        }
        return status.isGranted;
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur demande permission notifications: $e');
      }
      return false;
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

  /// Saves the FCM token to the server
  /// Requires an authentication token from AuthProvider
  static Future<bool> saveTokenToServer(String fcmToken, String authToken) async {
    // Éviter de sauvegarder le même token plusieurs fois
    if (_lastSavedToken == fcmToken) {
      if (kDebugMode) {
        print('ℹ️ Token FCM déjà sauvegardé, skip');
      }
      return true;
    }

    try {
      final uri = Uri.parse('https://www.unistudious.com/api/save-fcm-token');
      
      // Déterminer le type de plateforme
      final platformType = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown');
      
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $authToken'
        ..fields['token'] = fcmToken
        ..fields['type'] = platformType;

      if (kDebugMode) {
        print('📤 Envoi du token FCM au serveur');
        print('  Token: ${fcmToken.substring(0, 20)}...');
        print('  Type: $platformType');
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = json.decode(responseBody);

      if (response.statusCode == 200 && responseData['success'] == true) {
        _lastSavedToken = fcmToken; // Mémoriser le token sauvegardé
        if (kDebugMode) {
          print('✅ Token FCM sauvegardé avec succès: ${responseData['message']}');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('❌ Erreur lors de la sauvegarde du token FCM: ${responseData['message'] ?? 'Erreur inconnue'}');
          print('  Status Code: ${response.statusCode}');
          print('  Response: $responseBody');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors de la sauvegarde du token FCM: $e');
      }
      return false;
    }
  }

  /// Removes the FCM token from the server
  /// Requires an authentication token from AuthProvider
  static Future<bool> removeTokenFromServer(String authToken) async {
    try {
      final uri = Uri.parse('https://www.unistudious.com/api/remove-fcm-token');
      
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $authToken';

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = json.decode(responseBody);

      if (response.statusCode == 200 && responseData['success'] == true) {
        _lastSavedToken = null; // Réinitialiser le token sauvegardé
        if (kDebugMode) {
          print('✅ Token FCM supprimé du serveur avec succès: ${responseData['message']}');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('❌ Erreur lors de la suppression du token FCM: ${responseData['message'] ?? 'Erreur inconnue'}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors de la suppression du token FCM: $e');
      }
      return false;
    }
  }
}
