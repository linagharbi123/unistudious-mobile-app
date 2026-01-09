import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';

class AppConfig {
  static String? _platform;
  static String? _version;
  static String? _buildNumber;
  static PackageInfo? _packageInfo;
  static bool _initialized = false;
  
  // TEMPORAIRE POUR TEST: Mettre à true pour tester la page de mise à jour avec une version ancienne
  static const bool _testMode = false;  // Changez à true pour tester
  static const String _testVersion = '1.0.0';  // Version ancienne pour test

  // Initialiser les variables globales
  static Future<void> initialize() async {
    // TEMPORAIRE POUR TEST: Si testMode est activé, utiliser la version de test
    if (_testMode) {
      _version = _testVersion;
      _buildNumber = '1';
    } else {
      try {
        _packageInfo = await PackageInfo.fromPlatform();
        _version = _packageInfo!.version;
        _buildNumber = _packageInfo!.buildNumber;
      } catch (e) {
        // Si le plugin ne fonctionne pas, utiliser les valeurs par défaut depuis pubspec.yaml
        // Version actuelle dans pubspec.yaml: 1.0.2+3
        _version = '1.0.2';
        _buildNumber = '3';
      }
    }
    
    if (Platform.isAndroid) {
      _platform = 'Android';
    } else if (Platform.isIOS) {
      _platform = 'Ios';
    } else {
      _platform = 'Unknown';
    }
    
    _initialized = true;
  }

  // Getter pour la plateforme
  static String get platform {
    if (!_initialized || _platform == null) {
      // Valeur par défaut si non initialisé
      if (Platform.isAndroid) {
        return 'Android';
      } else if (Platform.isIOS) {
        return 'Ios';
      }
      return 'Unknown';
    }
    return _platform!;
  }

  // Getter pour la version
  static String get version {
    // TEMPORAIRE POUR TEST: Si testMode est activé, retourner la version de test
    if (_testMode) {
      return _testVersion;
    }
    if (!_initialized || _version == null) {
      // Valeur par défaut depuis pubspec.yaml si non initialisé
      return '1.0.2';
    }
    return _version!;
  }

  // Getter pour le build number
  static String get buildNumber {
    if (!_initialized || _buildNumber == null) {
      // Valeur par défaut depuis pubspec.yaml si non initialisé
      return '3';
    }
    return _buildNumber!;
  }

  // Getter pour la version complète (version+buildNumber)
  static String get fullVersion => '$version+$buildNumber';
}

