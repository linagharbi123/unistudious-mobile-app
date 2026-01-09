import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/firebase_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  String? _fcmToken;
  bool _isLoadingToken = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationData();
    _loadFCMToken();
  }

  Future<void> _loadFCMToken() async {
    setState(() => _isLoadingToken = true);
    try {
      final token = await FirebaseNotificationService.getToken();
      setState(() {
        _fcmToken = token;
        _isLoadingToken = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors du chargement du token FCM: $e');
      }
      setState(() => _isLoadingToken = false);
    }
  }

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

        setState(() {
          _generalNotification =
          updatedKey == 'generalNotification'
              ? updatedValue ?? localPrefs['generalNotification']!
              : localPrefs['generalNotification']!;
          _messageNotification =
          updatedKey == 'messageNotification'
              ? updatedValue ?? localPrefs['messageNotification']!
              : localPrefs['messageNotification']!;
          _calendarNotification =
          updatedKey == 'calendarNotification'
              ? updatedValue ?? localPrefs['calendarNotification']!
              : localPrefs['calendarNotification']!;
          _pushNotification =
          updatedKey == 'pushNotification'
              ? updatedValue ?? localPrefs['pushNotification']!
              : localPrefs['pushNotification']!;
          _smsNotification =
          updatedKey == 'smsNotification'
              ? updatedValue ?? localPrefs['smsNotification']!
              : localPrefs['smsNotification']!;
          _loginNotification =
          updatedKey == 'loginNotification'
              ? updatedValue ?? localPrefs['loginNotification']!
              : localPrefs['loginNotification']!;
        });

        await _saveAllPreferences();
        debugPrint("🔄 Notification data loaded from API: $notificationData");

        final syncSuccess = await _syncAllPreferencesToApi();
        if (!syncSuccess && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Changes saved locally, but server sync failed.'),
              backgroundColor: Colors.red[600],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("🔥 Exception fetching /api/my-profile: $e");
      setState(() {
        _generalNotification = localPrefs['generalNotification']!;
        _messageNotification = localPrefs['messageNotification']!;
        _calendarNotification = localPrefs['calendarNotification']!;
        _pushNotification = localPrefs['pushNotification']!;
        _smsNotification = localPrefs['smsNotification']!;
        _loginNotification = localPrefs['loginNotification']!;
      });
      await _syncAllPreferencesToApi();
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
          await _savePreference(key, value);
          debugPrint("✅ Update successful for $key");
          return true;
        }
      }
      await _savePreference(key, value);
      return false;
    } catch (e) {
      debugPrint("🔥 API Exception: $e");
      await _savePreference(key, value);
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
            // Section Token FCM pour les tests
            if (kDebugMode) _buildFCMTokenCard(theme),
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

  Widget _buildFCMTokenCard(ThemeData theme) {
    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.only(bottom: 16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.vpn_key, color: Colors.deepPurple),
                const SizedBox(width: 12),
                Text(
                  'Token FCM (Debug)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ) ?? const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoadingToken)
              const Center(child: CircularProgressIndicator())
            else if (_fcmToken != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _fcmToken!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (_fcmToken != null) {
                              await Clipboard.setData(ClipboardData(text: _fcmToken!));
                              if (kDebugMode) {
                                print('📋 Token FCM copié: $_fcmToken');
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Token copié dans le presse-papier'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copier'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _loadFCMToken,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Actualiser'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[600],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else
              Text(
                'Token non disponible',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
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