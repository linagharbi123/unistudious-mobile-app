import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/bottom_navigation_provider.dart';
import '../models/app_bar_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/sidebar.dart';
import '../widgets/loading_wrapper.dart';
import 'dashboard_page.dart';
import 'course_details_page.dart';
import 'social_feed_page.dart';
import 'resources_page.dart';
import 'profile_page_bottom_nav.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  // Liste des pages - elles seront conservées en mémoire
  late final List<Widget> _pages;

  static const List<String> _titles = [
    'Accueil',
    'Cours',
    'Social',
    'Ressources',
    'Profil',
  ];

  static const List<IconData> _icons = [
    Icons.home,
    Icons.book,
    Icons.people,
    Icons.library_books,
    Icons.person,
  ];

  @override
  void initState() {
    super.initState();
    // Initialiser toutes les pages une seule fois
    _pages = [
      const DashboardPage(),
      const CourseDetailsPage(),
      const SocialFeedPage(),
      const ResourcesPage(),
      const ProfilePageBottomNav(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDark = themeProvider.themeMode == ThemeMode.dark;

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        textTheme: Theme.of(context).textTheme.apply(
          bodyColor: isDark ? Colors.white : Colors.black87,
          displayColor: isDark ? Colors.white : Colors.black87,
        ),
        iconTheme: Theme.of(context).iconTheme.copyWith(
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      child: PopScope(
        canPop: false, // Intercepter tous les retours pour gérer selon la plateforme
        onPopInvoked: (didPop) async {
          if (didPop) return;
          
          // Gérer le bouton retour système / geste de balayage iOS
          final navProvider = Provider.of<BottomNavigationProvider>(context, listen: false);
          final isIOS = Platform.isIOS;
          
          // Si on est sur la page d'accueil (index 0)
          if (navProvider.selectedIndex == 0) {
            if (isIOS) {
              // Sur iOS, si on peut revenir en arrière, on revient
              // Sinon, on ne fait rien (l'app reste ouverte, comportement iOS standard)
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
              // Si on ne peut pas revenir, on ne fait rien (l'app reste ouverte)
              // C'est le comportement standard iOS où le geste de balayage ne fait rien
            } else {
              // Sur Android, demander confirmation avant de quitter
              final shouldExit = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Quitter l\'application'),
                  content: const Text('Voulez-vous vraiment quitter l\'application ?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Annuler'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Quitter'),
                    ),
                  ],
                ),
              );
              
              if (shouldExit == true && context.mounted) {
                // Quitter l'application sur Android
                SystemNavigator.pop();
              }
            }
          } else {
            // Si on n'est pas sur la page d'accueil, retourner à la page d'accueil
            navProvider.updateIndex(0);
          }
        },
        child: Consumer2<BottomNavigationProvider, AppBarProvider>(
          builder: (context, navProvider, appBarProvider, _) {
            final Color unselectedColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
            final Color selectedColor = themeProvider.primaryColor;
            final appBarConfig = appBarProvider.getConfig(navProvider.selectedIndex);

            return LoadingWrapper(
              child: Scaffold(
                appBar: _buildAppBar(context, appBarConfig, isDark),
                body: IndexedStack(
                  index: navProvider.selectedIndex,
                  children: _pages,
                ),
                drawer: const AppSidebar(),
                bottomNavigationBar: BottomNavigationBar(
                  currentIndex: navProvider.selectedIndex,
                  onTap: (index) {
                    // Mise à jour synchrone de l'index pour une navigation fluide
                    navProvider.updateIndex(index);
                  },
                  items: List.generate(
                    _titles.length,
                    (index) => BottomNavigationBarItem(
                      icon: Icon(
                        _icons[index],
                        color: navProvider.selectedIndex == index
                            ? selectedColor
                            : unselectedColor,
                      ),
                      label: _titles[index],
                    ),
                  ),
                  selectedItemColor: selectedColor,
                  unselectedItemColor: unselectedColor,
                  backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  elevation: 8,
                  type: BottomNavigationBarType.fixed,
                  showSelectedLabels: true,
                  showUnselectedLabels: true,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    AppBarConfig config,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    
    return AppBar(
      leading: config.leading ??
          Builder(
            builder: (context) => IconButton(
              icon: Icon(
                Icons.menu,
                color: theme.appBarTheme.iconTheme?.color ?? Colors.white,
              ),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
      title: Text(
        config.title,
        style: theme.appBarTheme.titleTextStyle?.copyWith(
          color: theme.appBarTheme.foregroundColor ?? Colors.white,
        ) ??
            TextStyle(
              fontSize: 22,
              color: theme.appBarTheme.foregroundColor ?? Colors.white,
            ),
      ),
      centerTitle: config.centerTitle,
      backgroundColor: Colors.transparent,
      elevation: 0,
      actions: config.actions,
      bottom: config.bottom,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF1A003D), Color(0xFF3C0D73)]
                : const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
    );
  }
}

