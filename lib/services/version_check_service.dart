import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../models/version_check_response.dart';

class VersionCheckService {
  static const String _baseUrl = 'https://www.unistudious.com';
  
  // Singleton pattern
  static final VersionCheckService _instance = VersionCheckService._internal();
  factory VersionCheckService() => _instance;
  VersionCheckService._internal();

  /// Vérifie la version de l'application auprès de l'API
  /// Retourne null en cas d'erreur réseau ou si aucune mise à jour n'est disponible
  Future<VersionCheckResponse?> checkVersion() async {
    try {
      // S'assurer que AppConfig est initialisé
      try {
        // Tenter d'accéder aux valeurs pour vérifier si initialisé
        final _platform = AppConfig.platform;
        final _version = AppConfig.version;
        // Utiliser les variables pour éviter l'avertissement
        if (_platform.isEmpty || _version.isEmpty) {
          await AppConfig.initialize();
        }
      } catch (e) {
        // Si non initialisé, l'initialiser
        await AppConfig.initialize();
      }

      final platform = AppConfig.platform;
      final version = AppConfig.version;

      if (kDebugMode) {
        print('📡 Envoi requête API: $_baseUrl/platform/check-version');
        print('📤 Paramètres: platform=$platform, version=$version');
      }

      // Créer une requête multipart avec form-data
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/platform/check-version'),
      );

      // Ajouter les champs form-data
      request.fields['platform'] = platform;
      request.fields['version'] = version;

      // Envoyer la requête
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (kDebugMode) {
            print('⏱️ Timeout lors de la requête API');
          }
          throw Exception('Timeout: La vérification de version a pris trop de temps');
        },
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (kDebugMode) {
        print('📥 Réponse API - Status Code: ${response.statusCode}');
        print('📥 Réponse Body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return VersionCheckResponse.fromJson(data);
      } else {
        if (kDebugMode) {
          print('❌ Erreur API - Status Code: ${response.statusCode}');
        }
        // Si l'API retourne une erreur, on considère qu'il n'y a pas de mise à jour
        // pour ne pas bloquer l'application
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Exception lors de la vérification de version: $e');
      }
      // En cas d'erreur réseau ou autre, on retourne null
      // pour ne pas bloquer l'application
      return null;
    }
  }
}

