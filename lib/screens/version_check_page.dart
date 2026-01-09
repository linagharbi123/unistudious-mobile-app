import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // URLs par défaut (à remplacer par vos vraies URLs)
  static const String defaultPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.unistudious.projet1v2';
  static const String defaultAppStoreUrl = 'https://apps.apple.com/app/idYOUR_APP_ID';

  Future<void> _launchUpdateUrl(BuildContext context) async {
    String? url;
    
    // Déterminer l'URL selon la plateforme
    if (Platform.isAndroid) {
      url = playStoreUrl ?? defaultPlayStoreUrl;
    } else if (Platform.isIOS) {
      url = appStoreUrl ?? defaultAppStoreUrl;
    }

    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impossible d\'ouvrir le lien de mise à jour')),
          );
        }
      }
    }
  }

  Future<void> _skipUpdate(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('skipped_version_${update.version}', true);
    
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

