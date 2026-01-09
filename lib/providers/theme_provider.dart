// lib/providers/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  Color _primaryColor = Colors.deepPurple;

  ThemeMode get themeMode => _themeMode;
  Color get primaryColor => _primaryColor;

  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    // Save theme mode in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('isDarkMode', mode == ThemeMode.dark);
  }

  void setPrimaryColor(Color color) {
    _primaryColor = color;
    notifyListeners();
  }

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? true;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void toggleTheme() {
    setThemeMode(_themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);
  }
}