import 'package:flutter/material.dart';
import '../services/token_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/scheduler.dart';

class AuthProvider extends ChangeNotifier {
  final TokenService _tokenService = TokenService();
  bool _isLoggedIn = false;
  bool _isLoading = false;
  String? _error;
  String? _finalUsername; // Nouvelle variable pour finalUsername

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get finalUsername => _finalUsername; // Getter pour finalUsername

  // Initialiser le provider
  Future<void> initialize() async {
    _isLoading = true;
    // Déférer le notifyListeners pour éviter l'appel pendant le build
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });

    try {
      await _tokenService.initialize();
      _isLoggedIn = await _tokenService.isLoggedIn();
      _error = null;
      // Optionnel : Charger finalUsername depuis une source persistante si nécessaire
      _finalUsername = await _loadFinalUsername();
    } catch (e) {
      _error = e.toString();
      _isLoggedIn = false;
    } finally {
      _isLoading = false;
      // Déférer le notifyListeners final également pour cohérence
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  // Méthode pour charger finalUsername depuis SharedPreferences (optionnel)
  Future<String?> _loadFinalUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('finalUsername');
  }

  // Méthode pour sauvegarder finalUsername dans SharedPreferences (optionnel)
  Future<void> _saveFinalUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('finalUsername', username);
  }

  // Définir finalUsername
  void setFinalUsername(String username) {
    _finalUsername = username;
    _saveFinalUsername(username); // Sauvegarder dans SharedPreferences si nécessaire
    notifyListeners();
  }

  // Effacer finalUsername
  void clearFinalUsername() {
    _finalUsername = null;
    _removeFinalUsername(); // Supprimer de SharedPreferences si utilisé
    notifyListeners();
  }

  // Supprimer finalUsername de SharedPreferences (optionnel)
  Future<void> _removeFinalUsername() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('finalUsername');
  }

  // Login
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _tokenService.login(username, password);

      if (result['success']) {
        _isLoggedIn = true;
        _error = null;
        // Si l'API de login renvoie finalUsername, le définir ici
        // Exemple : _finalUsername = result['finalUsername'];
        // Sinon, il sera défini lors de l'appel à l'API /api/dashboard-social-media
        notifyListeners();
        return true;
      } else {
        _error = result['error'];
        _isLoggedIn = false;
        return false;
      }
    } catch (e) {
      _error = e.toString();
      _isLoggedIn = false;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Logout
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _tokenService.logout();
      _isLoggedIn = false;
      _error = null;
      _finalUsername = null; // Effacer finalUsername lors de la déconnexion
      await _removeFinalUsername(); // Supprimer de SharedPreferences
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Rafraîchir le token
  Future<bool> refreshToken() async {
    try {
      final result = await _tokenService.refreshToken();

      if (result['success']) {
        _isLoggedIn = true;
        _error = null;
        notifyListeners();
        return true;
      } else if (result['logout_required'] == true) {
        await logout();
        return false;
      } else {
        _error = result['error'];
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Obtenir le token actuel
  String? get currentToken => _tokenService.currentToken;

  // Obtenir le token (alias pour currentToken)
  String? get token => _tokenService.currentToken;

  // Effacer le token
  Future<void> clearToken() async {
    await _tokenService.logout();
    _isLoggedIn = false;
    _error = null;
    _finalUsername = null; // Effacer finalUsername
    await _removeFinalUsername(); // Supprimer de SharedPreferences
    notifyListeners();
  }

  // Faire une requête authentifiée
  Future<http.Response> authenticatedRequest(String method, String endpoint, {Map<String, String>? headers, String? body}) async {
    return await _tokenService.authenticatedRequest(method, endpoint, headers: headers, body: body);
  }

  // Sauvegarder un nouveau token
  Future<void> saveToken(String newToken) async {
    await _tokenService.saveToken(newToken);
    _isLoggedIn = true;
    notifyListeners();
  }

  // Mettre à jour le token
  Future<void> updateToken(String newToken) async {
    await _tokenService.saveToken(newToken);
    _isLoggedIn = true;
    notifyListeners();
  }

  // Définir un token (pour les connexions sociales)
  Future<void> setToken(String token) async {
    await _tokenService.saveToken(token);
    _isLoggedIn = true;
    _error = null;
    notifyListeners();
  }

  // Méthodes pour gérer les changements de groupe en attente
  Future<bool?> getPendingChange(int sessionId, int groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final changeKey = 'pending_change_${sessionId}_$groupId';
    return prefs.getBool(changeKey);
  }

  Future<void> setPendingChange(int sessionId, int groupId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final changeKey = 'pending_change_${sessionId}_$groupId';
    await prefs.setBool(changeKey, value);
  }

  Future<void> removePendingChange(int sessionId, int groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final changeKey = 'pending_change_${sessionId}_$groupId';
    await prefs.remove(changeKey);
  }

  // Méthodes pour gérer les jointures de groupe en attente
  Future<bool?> getPendingJoin(int sessionId, int groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final joinKey = 'pending_join_${sessionId}_$groupId';
    return prefs.getBool(joinKey);
  }

  Future<void> setPendingJoin(int sessionId, int groupId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final joinKey = 'pending_join_${sessionId}_$groupId';
    await prefs.setBool(joinKey, value);
  }

  Future<void> removePendingJoin(int sessionId, int groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final joinKey = 'pending_join_${sessionId}_$groupId';
    await prefs.remove(joinKey);
  }

  // Effacer les erreurs
  void clearError() {
    _error = null;
    notifyListeners();
  }
}