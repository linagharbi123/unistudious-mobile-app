import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache local des données de pages (pattern stale-while-revalidate).
/// Affiche le cache immédiatement, puis rafraîchit depuis l'API en arrière-plan.
class PageCacheService {
  static String _userScope(String? token) {
    if (token == null || token.isEmpty) return 'guest';
    return token.length > 16 ? token.substring(0, 16) : token;
  }

  static String _storageKey(String page, String? userToken) =>
      'page_cache_${_userScope(userToken)}_$page';

  /// Lit le cache si présent et pas expiré.
  static Future<Map<String, dynamic>?> load(
    String page, {
    String? userToken,
    Duration maxAge = const Duration(hours: 24),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(page, userToken));
    if (raw == null) return null;

    try {
      final wrapper = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.parse(wrapper['savedAt'] as String);
      if (DateTime.now().difference(savedAt) > maxAge) {
        await prefs.remove(_storageKey(page, userToken));
        return null;
      }
      final data = wrapper['data'];
      if (data is! Map) return null;
      return Map<String, dynamic>.from(data);
    } catch (_) {
      return null;
    }
  }

  /// Enregistre les données en cache.
  static Future<void> save(
    String page,
    Map<String, dynamic> data, {
    String? userToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey(page, userToken),
      jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'data': data,
      }),
    );
  }

  /// Supprime tout le cache de l'utilisateur (à la déconnexion).
  static Future<void> clearAllForUser(String? userToken) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'page_cache_${_userScope(userToken)}_';
    for (final key in prefs.getKeys()) {
      if (key.startsWith(prefix)) {
        await prefs.remove(key);
      }
    }
  }
}
