import 'package:flutter/material.dart';

class AppBarConfig {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;

  AppBarConfig({
    required this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.centerTitle = false,
  });
}

class AppBarProvider with ChangeNotifier {
  final Map<int, AppBarConfig> _configs = {};
  
  // Configuration par défaut pour chaque page
  final Map<int, AppBarConfig> _defaultConfigs = {
    0: AppBarConfig(title: 'Tableau de bord'),
    1: AppBarConfig(title: 'Groupes'),
    2: AppBarConfig(title: 'Fil Social'),
    3: AppBarConfig(title: 'Ressources'),
    4: AppBarConfig(title: 'Profil'),
  };

  AppBarConfig getConfig(int index) {
    return _configs[index] ?? _defaultConfigs[index] ?? AppBarConfig(title: '');
  }

  void updateConfig(int index, AppBarConfig config) {
    _configs[index] = config;
    notifyListeners();
  }

  void resetConfig(int index) {
    _configs.remove(index);
    notifyListeners();
  }

  void clearAll() {
    _configs.clear();
    notifyListeners();
  }
}


