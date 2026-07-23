import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../config/app_config.dart';
import '../models/version_check_response.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import '../services/version_check_service.dart';

const String _kDismissedUpdateVersionKey = 'version_update_dismissed';

class VersionCheckPage extends StatefulWidget {
  final VersionUpdate update;
  final String? appStoreUrl;
  final String? playStoreUrl;

  const VersionCheckPage({
    super.key,
    required this.update,
    this.appStoreUrl,
    this.playStoreUrl,
  });

  /// Vérifie si l'utilisateur a déjà cliqué sur "J'ai déjà mis à jour" pour cette version
  static Future<bool> shouldSkipUpdateDisplay(String updateVersion) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getString(_kDismissedUpdateVersionKey);
    return dismissed == updateVersion;
  }

  @override
  State<VersionCheckPage> createState() => _VersionCheckPageState();
}

class _VersionCheckPageState extends State<VersionCheckPage> with WidgetsBindingObserver {
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _recheckVersionAndNavigateIfUpdated();
    }
  }

  Future<void> _recheckVersionAndNavigateIfUpdated() async {
    if (_isChecking || !mounted) return;
    setState(() => _isChecking = true);
    try {
      await AppConfig.reinitialize();
      final response = await VersionCheckService().checkVersion();
      if (!mounted) return;
      if (response == null || !response.hasUpdate) {
        if (kDebugMode) {
          print('✅ Version à jour après retour du store - navigation vers l\'app');
        }
        _navigateToApp();
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors de la revérification: $e');
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  /// L'utilisateur déclare avoir mis à jour : on navigue immédiatement et on ne réaffichera pas cette mise à jour
  Future<void> _onAlreadyUpdated() async {
    if (_isChecking || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDismissedUpdateVersionKey, widget.update.version);
    if (!mounted) return;
    _navigateToApp();
  }

  void _navigateToApp() {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final route = authProvider.isLoggedIn ? '/dashboard' : '/login';
    Navigator.of(context).pushReplacementNamed(route);
  }

  // Package name de l'application Android
  static const String androidPackageName = 'com.unistudious.projet1v2';
  
  // MethodChannel pour ouvrir le Play Store (Android) et l'App Store (iOS) nativement
  static const MethodChannel _playStoreChannel = MethodChannel('com.unistudious.projet1v2/playstore');
  static const MethodChannel _appStoreChannel = MethodChannel('com.unistudious.projet1v2/appstore');
  
  // URLs par défaut
  // Format market:// pour ouvrir directement l'app Play Store (meilleure expérience)
  static const String defaultPlayStoreUrl = 'market://details?id=$androidPackageName';
  // Format web en fallback si l'app Play Store n'est pas disponible
  static const String defaultPlayStoreWebUrl = 'https://play.google.com/store/apps/details?id=$androidPackageName';
  // URL App Store (depuis AppConfig - configurer appStoreId dans config/app_config.dart)
  static String get defaultAppStoreUrl => AppConfig.appStoreUrl;

  Future<void> _launchUpdateUrl(BuildContext context) async {
    if (Platform.isAndroid) {
      await _launchPlayStore(context);
    } else if (Platform.isIOS) {
      await _launchAppStore(context);
    }
  }

  Future<void> _launchPlayStore(BuildContext context) async {
    // Essayer d'abord avec le MethodChannel natif (plus fiable)
    try {
      final result = await _playStoreChannel.invokeMethod<bool>(
        'openPlayStore',
        {'packageName': androidPackageName},
      );
      if (result == true) {
        return; // Succès avec le MethodChannel natif
      }
    } catch (e) {
      // Le MethodChannel a échoué, continuer avec url_launcher
    }
    
    // Fallback : utiliser url_launcher
    try {
      // Essayer d'abord le format market:// (ouvre directement l'app Play Store)
      final marketUri = Uri.parse(widget.playStoreUrl ?? defaultPlayStoreUrl);
      
      try {
        await launchUrl(
          marketUri,
          mode: LaunchMode.externalApplication,
        );
        return; // Succès, on sort
      } catch (e) {
        // Si market:// échoue, essayer le format web
        if (widget.playStoreUrl == null || widget.playStoreUrl == defaultPlayStoreUrl) {
          final webUri = Uri.parse(defaultPlayStoreWebUrl);
          try {
            await launchUrl(
              webUri,
              mode: LaunchMode.externalApplication,
            );
            return; // Succès avec le format web
          } catch (e2) {
            // Les deux formats ont échoué, essayer avec platformDefault
            try {
              await launchUrl(webUri, mode: LaunchMode.platformDefault);
              return;
            } catch (e3) {
              // Tous les essais ont échoué
            }
          }
        }
      }
    } catch (e) {
      // Erreur générale
    }
    
    // Si tout échoue, afficher un message d'erreur
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'ouvrir Google Play Store. Veuillez mettre à jour manuellement depuis le Play Store.'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _launchAppStore(BuildContext context) async {
    final appStoreId = AppConfig.appStoreId;

    // 1. Utiliser le MethodChannel natif (ouvre directement l'app App Store, évite Safari)
    try {
      final result = await _appStoreChannel.invokeMethod<bool>(
        'openAppStore',
        {'appStoreId': appStoreId},
      );
      if (result == true) return;
    } catch (e) {
      if (kDebugMode) {
        print('❌ MethodChannel App Store échoué: $e');
      }
    }

    // 2. Fallback : url_launcher avec lien https
    try {
      final webUri = Uri.parse('https://apps.apple.com/app/id$appStoreId');
      final launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      if (launched) return;
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir l\'App Store')),
      );
    }
  }

  Future<void> _skipUpdate(BuildContext context) async {
    if (!context.mounted) return;
    _navigateToApp();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark;
    final isRequired = widget.update.required;

    return PopScope(
      canPop: !isRequired,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icône de mise à jour
                  Icon(
                    Icons.system_update,
                    size: 80,
                    color: themeProvider.primaryColor,
                  ),
                  const SizedBox(height: 24),
                  
                  // Titre
                  Text(
                    isRequired ? 'Mise à jour requise' : 'Mise à jour disponible',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  
                  // Version
                  Text(
                    'Version ${widget.update.version}',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Bouton Mettre à jour
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isChecking ? null : () => _launchUpdateUrl(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeProvider.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _isChecking ? 'Vérification...' : 'Mettre à jour',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  
                  // Bouton J'ai déjà mis à jour (navigue immédiatement, ne réaffiche pas la page)
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isChecking ? null : () => _onAlreadyUpdated(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: themeProvider.primaryColor,
                        side: BorderSide(color: themeProvider.primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "J'ai déjà mis à jour",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  
                  // Bouton Skip (seulement si la mise à jour n'est pas obligatoire)
                  if (!isRequired) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _isChecking ? null : () => _skipUpdate(context),
                        style: TextButton.styleFrom(
                          foregroundColor: isDark ? Colors.grey[400] : Colors.grey[600],
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Passer',
                          style: TextStyle(
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

