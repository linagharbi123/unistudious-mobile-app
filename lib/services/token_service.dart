import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TokenService {
  static const String _baseUrl = 'https://www.unistudious.com';
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  
  // Singleton pattern
  static final TokenService _instance = TokenService._internal();
  factory TokenService() => _instance;
  TokenService._internal();

  String? _currentToken;
  String? _refreshToken;

  // Getter pour le token actuel
  String? get currentToken => _currentToken;

  // Initialiser le service
  Future<void> initialize() async {
    await _loadTokensFromStorage();
  }

  // Charger les tokens depuis le stockage
  Future<void> _loadTokensFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    _currentToken = prefs.getString(_tokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
  }

  // Sauvegarder les tokens
  Future<void> _saveTokens(String token, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_refreshTokenKey, refreshToken);
    _currentToken = token;
    _refreshToken = refreshToken;
  }

  // Sauvegarder un token (et éventuellement un refresh token)
  Future<void> saveToken(String token, {String? refreshToken}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    _currentToken = token;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await prefs.setString(_refreshTokenKey, refreshToken);
      _refreshToken = refreshToken;
    }
  }

  // Login et récupération des tokens
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/login_check'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['token'];
        final refreshToken = data['refresh_token'];
        
        await _saveTokens(token, refreshToken);
        
        return {
          'success': true,
          'token': token,
          'refresh_token': refreshToken,
        };
      } else {
        return {
          'success': false,
          'error': 'Login failed: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  // Rafraîchir le token
  Future<Map<String, dynamic>> refreshToken() async {
    if (_refreshToken == null) {
      return {
        'success': false,
        'error': 'No refresh token available',
      };
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/token/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'refresh_token': _refreshToken,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newToken = data['token'];
        final newRefreshToken = data['refresh_token'];
        
        await _saveTokens(newToken, newRefreshToken);
        
        return {
          'success': true,
          'token': newToken,
          'refresh_token': newRefreshToken,
        };
      } else {
        // Token expiré, déconnexion nécessaire
        await logout();
        return {
          'success': false,
          'error': 'Token expired',
          'logout_required': true,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  // Obtenir un token valide (avec refresh automatique si nécessaire)
  Future<String?> getValidToken() async {
    if (_currentToken == null) {
      return null;
    }

    // Ici vous pourriez ajouter une logique pour vérifier si le token est expiré
    // Pour l'instant, on retourne le token actuel
    return _currentToken;
  }

  // Faire une requête avec gestion automatique du token
  Future<http.Response> authenticatedRequest(
    String method,
    String endpoint, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final token = await getValidToken();
    if (token == null) {
      throw Exception('No valid token available');
    }

    final requestHeaders = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      ...?headers,
    };

    final uri = endpoint.startsWith('http')
        ? Uri.parse(endpoint)
        : Uri.parse('$_baseUrl$endpoint');
    http.Response response;

    switch (method.toUpperCase()) {
      case 'GET':
        response = await http.get(uri, headers: requestHeaders);
        break;
      case 'POST':
        response = await http.post(uri, headers: requestHeaders, body: body);
        break;
      case 'PUT':
        response = await http.put(uri, headers: requestHeaders, body: body);
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: requestHeaders);
        break;
      default:
        throw Exception('Unsupported HTTP method: $method');
    }

    // Si le token a expiré, essayer de le rafraîchir
    if (response.statusCode == 401) {
      final refreshResult = await refreshToken();
      if (refreshResult['success']) {
        // Réessayer la requête avec le nouveau token
        final newToken = refreshResult['token'];
        requestHeaders['Authorization'] = 'Bearer $newToken';
        
        switch (method.toUpperCase()) {
          case 'GET':
            response = await http.get(uri, headers: requestHeaders);
            break;
          case 'POST':
            response = await http.post(uri, headers: requestHeaders, body: body);
            break;
          case 'PUT':
            response = await http.put(uri, headers: requestHeaders, body: body);
            break;
          case 'DELETE':
            response = await http.delete(uri, headers: requestHeaders);
            break;
        }
      } else if (refreshResult['logout_required'] == true) {
        // Déconnexion forcée
        await logout();
        throw Exception('Session expired. Please login again.');
      }
    }

    return response;
  }

  // Déconnexion
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    _currentToken = null;
    _refreshToken = null;
  }

  // Vérifier si l'utilisateur est connecté
  Future<bool> isLoggedIn() async {
    await _loadTokensFromStorage();
    return _currentToken != null;
  }
}
