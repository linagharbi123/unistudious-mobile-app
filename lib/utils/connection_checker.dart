import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Utilitaire pour vérifier la disponibilité de la connexion internet
class ConnectionChecker {
  static final ConnectionChecker _instance = ConnectionChecker._internal();
  factory ConnectionChecker() => _instance;
  ConnectionChecker._internal();

  /// Vérifie si une connexion internet est disponible
  /// en tentant de se connecter à une URL connue
  Future<bool> hasConnection() async {
    try {
      // Tentative de connexion à Google DNS (8.8.8.8) ou à un serveur fiable
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        // Vérification supplémentaire avec une requête HTTP
        try {
          final response = await http
              .get(Uri.parse('https://www.google.com'))
              .timeout(const Duration(seconds: 5));
          return response.statusCode == 200;
        } catch (e) {
          // Si la requête HTTP échoue mais que le lookup DNS a réussi,
          // on considère qu'il y a une connexion (peut-être limitée)
          return true;
        }
      }
      return false;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Crée un stream qui émet périodiquement l'état de la connexion
  /// quand isConnectionError est true
  Stream<bool> watchConnection({Duration interval = const Duration(seconds: 3)}) async* {
    while (true) {
      final hasConn = await hasConnection();
      yield hasConn;
      await Future.delayed(interval);
    }
  }
}


