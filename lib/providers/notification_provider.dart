import 'package:flutter/foundation.dart';

/// Provider pour gérer l'affichage des notifications en foreground
class NotificationProvider extends ChangeNotifier {
  String? _currentTitle;
  String? _currentBody;
  bool _isVisible = false;

  String? get currentTitle => _currentTitle;
  String? get currentBody => _currentBody;
  bool get isVisible => _isVisible;

  /// Affiche une notification
  void showNotification(String title, String body) {
    _currentTitle = title;
    _currentBody = body;
    _isVisible = true;
    notifyListeners();

    // Masquer automatiquement après 4 secondes
    Future.delayed(const Duration(seconds: 4), () {
      hideNotification();
    });
  }

  /// Masque la notification
  void hideNotification() {
    _isVisible = false;
    notifyListeners();
  }
}



