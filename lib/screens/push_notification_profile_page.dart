import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/firebase_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

class PushNotificationProfilePage extends StatefulWidget {
  const PushNotificationProfilePage({super.key});

  @override
  State<PushNotificationProfilePage> createState() =>
      _PushNotificationProfilePageState();
}

class _PushNotificationProfilePageState
    extends State<PushNotificationProfilePage> {
  bool _generalNotification = false;
  bool _messageNotification = false;
  bool _calendarNotification = false;
  bool _pushNotification = false;
  bool _smsNotification = false;
  bool _loginNotification = false;

  @override
  void initState() {
    super.initState();
    // Charger immédiatement les préférences locales avant le premier build
    _loadLocalPreferencesImmediately().then((_) {
      // Une fois les valeurs locales chargées, synchroniser avec le serveur en arrière-plan
      _loadNotificationData();
      _loadFCMToken();
    });
  }

  /// Charge immédiatement les préférences locales pour afficher l'état correct sans délai
  Future<void> _loadLocalPreferencesImmediately() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _generalNotification = prefs.getBool('generalNotification') ?? false;
        _messageNotification = prefs.getBool('messageNotification') ?? false;
        _calendarNotification = prefs.getBool('calendarNotification') ?? false;
        _pushNotification = prefs.getBool('pushNotification') ?? false;
        _smsNotification = prefs.getBool('smsNotification') ?? false;
        _loginNotification = prefs.getBool('loginNotification') ?? false;
      });
      debugPrint("📱 Local preferences loaded immediately");
    }
  }

  Future<void> _loadFCMToken() async {
    // Sauvegarder automatiquement le token FCM sur le serveur en arrière-plan
    try {
      final token = await FirebaseNotificationService.getToken();
      if (token != null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final authToken = authProvider.currentToken;
        if (authToken != null) {
          await FirebaseNotificationService.saveTokenToServer(token, authToken);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors de la sauvegarde du token FCM: $e');
      }
    }
  }

  /// Charge les données depuis l'API en arrière-plan pour synchroniser avec le serveur
  Future<void> _loadNotificationData({String? updatedKey, bool? updatedValue}) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;
    const url = 'https://www.unistudious.com/api/my-profile';

    final prefs = await SharedPreferences.getInstance();
    final localPrefs = {
      'generalNotification': prefs.getBool('generalNotification') ?? false,
      'messageNotification': prefs.getBool('messageNotification') ?? false,
      'calendarNotification': prefs.getBool('calendarNotification') ?? false,
      'pushNotification': prefs.getBool('pushNotification') ?? false,
      'smsNotification': prefs.getBool('smsNotification') ?? false,
      'loginNotification': prefs.getBool('loginNotification') ?? false,
    };

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final notificationData = data['notification_data'];

        // Mettre à jour les valeurs depuis l'API seulement si elles sont différentes
        // et seulement si aucune clé n'a été mise à jour manuellement
        if (updatedKey == null && notificationData != null) {
          // Les clés de l'API sont: general, message, calendar, push, sms, login
          // Convertir les valeurs (peuvent être bool, int, ou string)
          bool _parseBoolValue(dynamic value) {
            if (value == null) return false;
            if (value is bool) return value;
            if (value is int) return value == 1;
            if (value is String) return value == "1" || value.toLowerCase() == "true";
            return false;
          }

          final apiValues = {
            'generalNotification': _parseBoolValue(notificationData['general']),
            'messageNotification': _parseBoolValue(notificationData['message']),
            'calendarNotification': _parseBoolValue(notificationData['calendar']),
            'pushNotification': _parseBoolValue(notificationData['push']),
            'smsNotification': _parseBoolValue(notificationData['sms']),
            'loginNotification': _parseBoolValue(notificationData['login']),
          };

          debugPrint("📊 API values parsed: $apiValues");
          debugPrint("📊 Local values: $localPrefs");

          // Vérifier si les valeurs de l'API sont différentes des valeurs locales
          bool needsUpdate = 
              apiValues['generalNotification'] != localPrefs['generalNotification'] ||
              apiValues['messageNotification'] != localPrefs['messageNotification'] ||
              apiValues['calendarNotification'] != localPrefs['calendarNotification'] ||
              apiValues['pushNotification'] != localPrefs['pushNotification'] ||
              apiValues['smsNotification'] != localPrefs['smsNotification'] ||
              apiValues['loginNotification'] != localPrefs['loginNotification'];

          debugPrint("🔄 Needs update: $needsUpdate");

          // Toujours mettre à jour avec les valeurs de l'API si elles existent
          if (mounted) {
            setState(() {
              _generalNotification = apiValues['generalNotification']!;
              _messageNotification = apiValues['messageNotification']!;
              _calendarNotification = apiValues['calendarNotification']!;
              _pushNotification = apiValues['pushNotification']!;
              _smsNotification = apiValues['smsNotification']!;
              _loginNotification = apiValues['loginNotification']!;
            });
            await _saveAllPreferences();
            debugPrint("✅ Notification data synced from API and saved locally");
          }
        } else if (updatedKey != null && updatedValue != null) {
          // Si une clé a été mise à jour manuellement, utiliser cette valeur
          setState(() {
            switch (updatedKey) {
              case 'generalNotification':
                _generalNotification = updatedValue;
                break;
              case 'messageNotification':
                _messageNotification = updatedValue;
                break;
              case 'calendarNotification':
                _calendarNotification = updatedValue;
                break;
              case 'pushNotification':
                _pushNotification = updatedValue;
                break;
              case 'smsNotification':
                _smsNotification = updatedValue;
                break;
              case 'loginNotification':
                _loginNotification = updatedValue;
                break;
            }
          });
          await _saveAllPreferences();
        }
      }
    } catch (e) {
      debugPrint("🔥 Exception fetching /api/my-profile: $e");
      // En cas d'erreur, garder les valeurs locales déjà chargées
      // Pas besoin de mettre à jour l'état car les valeurs locales sont déjà affichées
    }
  }

  Future<bool> _syncAllPreferencesToApi() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;
    bool allSynced = true;

    final preferences = [
      {
        'endpoint': '/api/update-general-notification-profile-user',
        'key': 'generalNotification',
        'value': _generalNotification,
        'responseKey': 'general_notification'
      },
      {
        'endpoint': '/api/update-message-notification-profile-user',
        'key': 'messageNotification',
        'value': _messageNotification,
        'responseKey': 'message_notification'
      },
      {
        'endpoint': '/api/update-calendar-notification-profile-user',
        'key': 'calendarNotification',
        'value': _calendarNotification,
        'responseKey': 'calendar_notification'
      },
      {
        'endpoint': '/api/update-push-notification-profile-user',
        'key': 'pushNotification',
        'value': _pushNotification,
        'responseKey': 'push_notification'
      },
      {
        'endpoint': '/api/update-sms-notification-profile-user',
        'key': 'smsNotification',
        'value': _smsNotification,
        'responseKey': 'sms_notification'
      },
      {
        'endpoint': '/api/update-login-notification-profile-user',
        'key': 'loginNotification',
        'value': _loginNotification,
        'responseKey': 'login_notification'
      },
    ];

    for (var pref in preferences) {
      bool synced = false;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          final url = Uri.parse('https://www.unistudious.com${pref['endpoint']}');
          final body = {
            pref['responseKey']!: (pref['value'] as bool) ? "1" : "0",
          };

          debugPrint(
              "📡 Syncing API [${pref['endpoint']}] (Attempt $attempt): "
                  "${pref['responseKey']} = ${body[pref['responseKey']]}");

          final response = await http.post(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: body,
          );

          debugPrint("📥 API Response (${response.statusCode}) : ${response.body}");

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['success'] == true &&
                data[pref['responseKey']] == ((pref['value'] as bool) ? true : false)) {
              debugPrint("✅ Successfully synced ${pref['key']}");
              synced = true;
              break;
            } else {
              debugPrint("⚠️ Sync failed for ${pref['key']}: "
                  "API returned ${data[pref['responseKey']]} instead of ${pref['value']}");
            }
          }
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          debugPrint("🔥 Exception syncing ${pref['key']} (Attempt $attempt): $e");
          if (attempt < 3) await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      if (!synced) {
        debugPrint("❌ Failed to sync ${pref['key']} after 3 attempts");
        allSynced = false;
      }
    }
    return allSynced;
  }

  Future<void> _saveAllPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('generalNotification', _generalNotification);
    await prefs.setBool('messageNotification', _messageNotification);
    await prefs.setBool('calendarNotification', _calendarNotification);
    await prefs.setBool('pushNotification', _pushNotification);
    await prefs.setBool('smsNotification', _smsNotification);
    await prefs.setBool('loginNotification', _loginNotification);
    debugPrint("💾 All preferences saved locally");
  }

  Future<void> _savePreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    debugPrint("💾 Preference saved locally -> $key = $value");
  }

  Future<bool> _updateNotificationProfile(
      String endpoint, String key, String responseKey, bool value) async {
    // Sauvegarder immédiatement localement pour un feedback instantané
    await _savePreference(key, value);
    
    final url = Uri.parse('https://www.unistudious.com$endpoint');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;

    final body = {responseKey: value ? "1" : "0"};

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );

      debugPrint("📥 API Response (${response.statusCode}) : ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          debugPrint("✅ Update successful for $key");
          return true;
        }
      }
      // Même en cas d'échec, la valeur est déjà sauvegardée localement
      return false;
    } catch (e) {
      debugPrint("🔥 API Exception: $e");
      // Même en cas d'erreur, la valeur est déjà sauvegardée localement
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () {
            Navigator.pushNamed(context, '/parametres');
          },
        ),
        title: Text(
          'Push Notification Profile',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ) ?? const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: theme.iconTheme,
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
      ),
      body: Container(
        color: theme.scaffoldBackgroundColor,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildSwitchTile(
              icon: Icons.notifications,
              title: "General Notifications",
              subtitle: "Receive general alerts.",
              value: _generalNotification,
              onChanged: (value) async {
                setState(() => _generalNotification = value);
                await _updateNotificationProfile(
                  '/api/update-general-notification-profile-user',
                  'generalNotification',
                  'general_notification',
                  value,
                );
              },
            ),
            _buildSwitchTile(
              icon: Icons.mail,
              title: "Messages",
              subtitle: "Receive private messages.",
              value: _messageNotification,
              onChanged: (value) async {
                setState(() => _messageNotification = value);
                await _updateNotificationProfile(
                  '/api/update-message-notification-profile-user',
                  'messageNotification',
                  'message_notification',
                  value,
                );
              },
            ),
            _buildSwitchTile(
              icon: Icons.calendar_today,
              title: "Calendar",
              subtitle: "Receive calendar reminders.",
              value: _calendarNotification,
              onChanged: (value) async {
                setState(() => _calendarNotification = value);
                await _updateNotificationProfile(
                  '/api/update-calendar-notification-profile-user',
                  'calendarNotification',
                  'calendar_notification',
                  value,
                );
              },
            ),
            _buildSwitchTile(
              icon: Icons.push_pin,
              title: "Push Notifications",
              subtitle: "Receive alerts on your device.",
              value: _pushNotification,
              onChanged: (value) async {
                setState(() => _pushNotification = value);
                await _updateNotificationProfile(
                  '/api/update-push-notification-profile-user',
                  'pushNotification',
                  'push_notification',
                  value,
                );
              },
            ),
            _buildSwitchTile(
              icon: Icons.sms,
              title: "SMS",
              subtitle: "Receive alerts via SMS.",
              value: _smsNotification,
              onChanged: (value) async {
                setState(() => _smsNotification = value);
                await _updateNotificationProfile(
                  '/api/update-sms-notification-profile-user',
                  'smsNotification',
                  'sms_notification',
                  value,
                );
              },
            ),
            _buildSwitchTile(
              icon: Icons.login,
              title: "Login",
              subtitle: "Get alerted when you log in.",
              value: _loginNotification,
              onChanged: (value) async {
                setState(() => _loginNotification = value);
                await _updateNotificationProfile(
                  '/api/update-login-notification-profile-user',
                  'loginNotification',
                  'login_notification',
                  value,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    final theme = Theme.of(context);
    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        title: Row(
          children: [
            Icon(icon, color: Colors.deepPurple),
            const SizedBox(width: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ) ?? const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodyMedium,
        ),
        value: value,
        onChanged: (val) {
          debugPrint("🔘 Switch [$title] changed -> $val");
          onChanged(val);
        },
        activeColor: Colors.deepPurple,
        inactiveThumbColor: Colors.grey,
        inactiveTrackColor: theme.brightness == Brightness.dark ? Colors.grey[600] : Colors.grey[300],
      ),
    );
  }
}