import 'package:flutter/foundation.dart';

class BottomNavigationProvider with ChangeNotifier {
  int _selectedIndex = 0;
  final List<int> _navigationStack = <int>[];
  static const int _maxStackSize = 10; // Limit the stack size to avoid memory issues

  int get selectedIndex => _selectedIndex;

  void updateIndex(int index) {
    if (index >= 0 && index < _getTotalPages()) {
      // Save the current index before updating
      if (_selectedIndex != index && _navigationStack.length < _maxStackSize) {
        _navigationStack.add(_selectedIndex);
      }
      _selectedIndex = index;
      notifyListeners();
    } else {
      print('Invalid index: $index. Please use a valid page index.');
    }
  }

  // Go back to the previous page
  void goBack() {
    if (_navigationStack.isNotEmpty) {
      _selectedIndex = _navigationStack.removeLast();
      notifyListeners();
    } else {
      print('No previous page to return to.');
    }
  }

  // Helper method to define the total number of pages
  int _getTotalPages() {
    return 4; // Adjust based on your app's navigation items
  }

  // Reset navigation stack if needed
  void resetNavigation() {
    _navigationStack.clear();
    _selectedIndex = 0;
    notifyListeners();
  }
}