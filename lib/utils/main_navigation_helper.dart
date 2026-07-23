import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bottom_navigation_provider.dart';
import '../screens/main_navigation_page.dart';
import 'action_guard.dart';

/// Navigation vers un onglet de la bottom bar sans recharger les pages déjà en mémoire.
class MainNavigationHelper {
  static int? indexForRoute(String route) =>
      BottomNavigationProvider.routeToIndexMap[route];

  static bool isBottomNavRoute(String route) =>
      BottomNavigationProvider.routeToIndexMap.containsKey(route);

  static bool isInsideMainNavigation(BuildContext context) {
    return context.findAncestorWidgetOfExactType<MainNavigationPage>() != null;
  }

  static void _switchToTabImpl(BuildContext context, int index) {
    final provider = Provider.of<BottomNavigationProvider>(context, listen: false);
    provider.ensureTabLoaded(index);
    provider.updateIndex(index);
  }

  /// Change d'onglet sans recréer MainNavigationPage si déjà affiché.
  static void switchToTab(BuildContext context, int index) {
    ActionGuard.instance.runSync('switch_tab_$index', () {
      _switchToTabImpl(context, index);
    });
  }

  /// Ouvre un onglet bottom bar (depuis sidebar ou notification).
  static void navigateToTab(BuildContext context, int index) {
    ActionGuard.instance.runSync('navigate_tab_$index', () {
      _switchToTabImpl(context, index);
      if (!isInsideMainNavigation(context)) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainNavigationPage()),
        );
      }
    });
  }

  /// Ouvre une route : onglet bottom bar instantané, sinon navigation classique.
  static void navigateToRoute(BuildContext context, String routeName) {
    ActionGuard.instance.runSync('navigate_route_$routeName', () {
      final index = indexForRoute(routeName);
      if (index != null) {
        Navigator.pop(context); // fermer drawer si ouvert
        navigateToTab(context, index);
      } else {
        Navigator.pop(context);
        Navigator.pushReplacementNamed(context, routeName);
      }
    });
  }
}
