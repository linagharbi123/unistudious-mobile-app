import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class BottomNavigationProvider with ChangeNotifier {
  int _selectedIndex = 0;

  int get selectedIndex => _selectedIndex;

  void updateIndex(int index) {
    if (_selectedIndex != index && index >= 0 && index < 5) {
      _selectedIndex = index;
      // Mise à jour synchrone pour une navigation fluide
      notifyListeners();
    }
  }

  void resetIndex() {
    if (_selectedIndex != 0) {
      _selectedIndex = 0;
      // Mise à jour synchrone pour une navigation fluide
      notifyListeners();
    }
  }
}