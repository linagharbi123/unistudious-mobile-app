import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../screens/dashboard_page.dart';
import '../screens/groups_page.dart';
import '../screens/social_feed_page.dart';
import '../screens/resources_page.dart';
import '../screens/profile_page_bottom_nav.dart';

class BottomNavigationProvider with ChangeNotifier {
  int _selectedIndex = 0;
  final Set<int> _loadedTabIndices = {0};
  final Map<int, Widget> _pageCache = {};

  static const Map<String, int> routeToIndexMap = {
    '/dashboard': 0,
    '/groups': 1,
    '/fil-social': 2,
    '/ressources': 3,
    '/profile': 4,
  };

  int get selectedIndex => _selectedIndex;
  Set<int> get loadedTabIndices => _loadedTabIndices;

  void updateIndex(int index) {
    if (index >= 0 && index < 5 && _selectedIndex != index) {
      _selectedIndex = index;
      notifyListeners();
    }
  }

  void ensureTabLoaded(int index) {
    if (index >= 0 && index < 5) {
      _loadedTabIndices.add(index);
      _pageCache.putIfAbsent(index, () => _createPage(index));
    }
  }

  Widget buildPage(int index) {
    ensureTabLoaded(index);
    return _pageCache[index]!;
  }

  Widget _createPage(int index) {
    switch (index) {
      case 0:
        return const DashboardPage();
      case 1:
        return const GroupsPage();
      case 2:
        return const SocialFeedPage();
      case 3:
        return const ResourcesPage();
      case 4:
        return const ProfilePageBottomNav();
      default:
        return const SizedBox.shrink();
    }
  }

  void clearPageCache() {
    _pageCache.clear();
    _loadedTabIndices
      ..clear()
      ..add(0);
    _selectedIndex = 0;
    notifyListeners();
  }

  void resetIndex() {
    if (_selectedIndex != 0) {
      _selectedIndex = 0;
      notifyListeners();
    }
  }
}
