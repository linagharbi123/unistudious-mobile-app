import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../models/version_check_response.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';

class VersionCheckPage extends StatelessWidget {
  final VersionUpdate update;
  final String? appStoreUrl;
  final String? playStoreUrl;

  const VersionCheckPage({
    super.key,
    required this.update,
    this.appStoreUrl,
    this.playStoreUrl,
  });

  // Package name de l'application Android
  static const String androidPackageName = 'com.unistudious.projet1v2';
  
  // MethodChannel pour ouvrir le Play Store nativement
  static const MethodChannel _playStoreChannel = MethodChannel('com.unistudious.projet1v2/playstore');
  
  // URLs par défaut
  // Format market:// pour ouvrir directement l'app Play Store (meilleure expérience)
  static const String defaultPlayStoreUrl = 'market://details?id=$androidPackageName';
  // Format web en fallback si l'app Play Store n'est pas disponible
  static const String defaultPlayStoreWebUrl = 'https://play.google.com/store/apps/details?id=$androidPackageName';
  static const String defaultAppStoreUrl = 'https://apps.apple.com/app/idYOUR_APP_ID';

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
      final marketUri = Uri.parse(playStoreUrl ?? defaultPlayStoreUrl);
      
      try {
        await launchUrl(
          marketUri,
          mode: LaunchMode.externalApplication,
        );
        return; // Succès, on sort
      } catch (e) {
        // Si market:// échoue, essayer le format web
        if (playStoreUrl == null || playStoreUrl == defaultPlayStoreUrl) {
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
    try {
      final uri = Uri.parse(appStoreUrl ?? defaultAppStoreUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir l\'App Store')),
        );
      }
    }
  }

  Future<void> _skipUpdate(BuildContext context) async {
    // Ne pas enregistrer dans le cache - utiliser uniquement les données de l'API
    // Si cette version n'est plus dans l'API la prochaine fois, elle ne s'affichera pas
    
    if (!context.mounted) return;
    
    // Déterminer la route normale selon l'état de connexion
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isLoggedIn = authProvider.isLoggedIn;
    final route = isLoggedIn ? '/dashboard' : '/login';
    
    // Naviguer vers la route normale
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark;
    final isRequired = update.required;

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
                  
                  // Message
                  Text(
                    update.message.isNotEmpty 
                        ? update.message 
                        : (isRequired 
                            ? 'Une nouvelle version est disponible. Veuillez mettre à jour pour continuer.'
                            : 'Une nouvelle version est disponible. Souhaitez-vous la télécharger maintenant ?'),
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  
                  // Version
                  Text(
                    'Version ${update.version}',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Bouton Update
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _launchUpdateUrl(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeProvider.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Mettre à jour',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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
                        onPressed: () => _skipUpdate(context),
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

