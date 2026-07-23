import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

/// Cache du statut « session active » pour afficher immédiatement les entrées sidebar.
class SessionStatusCache {
  static const _key = 'cached_has_active_session';

  static Future<bool?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key);
  }

  static Future<void> save(bool hasSession) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, hasSession);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> updateUserModel(BuildContext context, bool hasSession) async {
    if (!context.mounted) return;
    Provider.of<UserModel>(context, listen: false).hasActiveSession = hasSession;
    await save(hasSession);
  }
}
