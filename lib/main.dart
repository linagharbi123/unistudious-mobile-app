import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // Added for localization
import 'package:responsive_framework/responsive_framework.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/welcome_page.dart';
import 'screens/login_page.dart';
import 'screens/sign_up_page.dart';
import 'screens/forget_password_page.dart';
import 'screens/dashboard_page.dart';
import 'screens/settings_page.dart';
import 'screens/profile_page_bottom_nav.dart';
import 'screens/favorites_page.dart';
import 'screens/push_notification_profile_page.dart';
import 'screens/password_auth_page.dart';
import 'screens/terms_of_use.dart';
import 'screens/cookie_policy.dart';
import 'screens/payment_policy.dart';
import 'screens/refund_policy.dart';
import 'screens/course_details_page.dart';
import 'screens/calendar_page.dart';
import 'screens/social_feed_page.dart';
import 'screens/resources_page.dart';
import 'screens/join_session_page.dart';
import 'screens/groups_page.dart';
import 'screens/invoice_page.dart';
import 'screens/list_meet_page.dart';
import 'screens/attendance_page.dart';
import 'screens/google_login_page.dart';
import 'screens/facebook_login_page.dart';
import 'screens/messagerie_page.dart';
import 'screens/apple_login_page.dart';
import 'screens/ressources_gratuites_page.dart';
import 'screens/theme_customization_page.dart';
import 'screens/chat_page.dart';
import 'screens/groupes_page.dart';
import 'screens/main_navigation_page.dart';
import 'providers/theme_provider.dart';
import 'models/user_model.dart';
import 'models/bottom_navigation_provider.dart';
import 'models/app_bar_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/loading_provider.dart';
import 'providers/notifications_list_provider.dart';
import 'widgets/sidebar.dart';
import 'widgets/loading_wrapper.dart';
import 'config/app_config.dart';
import 'services/version_check_service.dart';
import 'screens/version_check_page.dart';
import 'models/version_check_response.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialiser AppConfig pour récupérer la plateforme et la version
  await AppConfig.initialize();

  final themeProvider = ThemeProvider();
  await themeProvider.loadTheme();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserModel()),
        ChangeNotifierProvider(create: (_) => BottomNavigationProvider()),
        ChangeNotifierProvider(create: (_) => AppBarProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => LoadingProvider()),
        ChangeNotifierProvider(create: (_) => themeProvider),
        ChangeNotifierProvider(create: (_) => NotificationsListProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class NavigationWrapper extends StatelessWidget {
  final Widget child;
  final String currentRoute;

  NavigationWrapper({required this.child, required this.currentRoute});

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
  static const List<String> _routes = [
    '/dashboard',
    '/mes-cours',
    '/fil-social',
    '/ressources',
    '/profile',
  ];

  // Map sidebar routes to bottom navigation indices
  static const Map<String, int> _routeToIndexMap = {
    '/dashboard': 0,
    '/mes-cours': 1,
    '/fil-social': 2,
    '/ressources': 3,
    '/profile': 4,
  };

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
        canPop: true,
        onPopInvoked: (didPop) async {
          if (didPop) return;

          // Gérer le bouton retour système
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            // Si on ne peut pas revenir en arrière, rediriger vers le dashboard
            final provider = Provider.of<BottomNavigationProvider>(context, listen: false);
            provider.updateIndex(0);
            if (context.mounted) {
              Navigator.pushReplacementNamed(context, '/dashboard');
            }
          }
        },
        child: Consumer<BottomNavigationProvider>(
          builder: (context, provider, child) {
            // Determine the current index based on the route
            final int index = _routeToIndexMap[currentRoute] ?? 0;
            final bool isBottomNavPage = _routeToIndexMap.containsKey(currentRoute);

            // Si c'est une page de la bottom bar, rediriger vers MainNavigationPage
            if (isBottomNavPage) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  provider.updateIndex(index);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const MainNavigationPage()),
                  );
                }
              });
              return LoadingWrapper(child: child!);
            }

            return LoadingWrapper(
              child: Scaffold(
                body: child,
                drawer: const AppSidebar(),
              ),
            );
          },
          child: child,
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<String> _getInitialRoute(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.initialize();
    return authProvider.isLoggedIn ? '/dashboard' : '/login';
  }

  // MODE TEST: Mettre à true pour forcer l'affichage de la page de test
  static const bool _forceTestPage = false;  // Changez à true pour tester l'UI

  Future<VersionUpdate?> _checkVersionAndGetUpdate() async {
    // MODE TEST: Forcer l'affichage de la page de test
    if (_forceTestPage) {
      if (kDebugMode) {
        print('🧪 MODE TEST: Affichage forcé de la page de vérification');
      }
      return VersionUpdate(
        version: '2.0.0',
        required: true,  // Changez à false pour tester le mode optionnel
        message: 'Nouvelle version disponible pour test',
        status: 'force_update',
      );
    }

    try {
      final versionCheckService = VersionCheckService();
      final platform = AppConfig.platform;
      final version = AppConfig.version;

      if (kDebugMode) {
        print('🔍 Vérification de version - Platform: $platform, Version: $version');
      }

      final response = await versionCheckService.checkVersion();

      if (response == null) {
        if (kDebugMode) {
          print('❌ Réponse API null ou erreur');
        }
        return null;
      }

      if (kDebugMode) {
        print('✅ Réponse API reçue - Status: ${response.status}, Updates: ${response.updates.length}');
      }

      if (!response.hasUpdate) {
        if (kDebugMode) {
          print('ℹ️ Aucune mise à jour disponible');
        }
        return null;
      }

      final update = response.firstUpdate;
      if (update == null) {
        if (kDebugMode) {
          print('❌ Aucune mise à jour trouvée dans la réponse');
        }
        return null;
      }

      if (kDebugMode) {
        print('📦 Mise à jour trouvée - Version: ${update.version}, Required: ${update.required}');
      }

      // Si la mise à jour est obligatoire, toujours l'afficher
      if (update.required) {
        if (kDebugMode) {
          print('🔒 Mise à jour obligatoire détectée');
        }
        return update;
      }

      // Si la mise à jour n'est pas obligatoire, vérifier si l'utilisateur l'a déjà skip
      final prefs = await SharedPreferences.getInstance();
      final skipped = prefs.getBool('skipped_version_${update.version}') ?? false;

      if (skipped) {
        if (kDebugMode) {
          print('⏭️ Version ${update.version} déjà skip par l\'utilisateur');
        }
        return null;
      }

      if (kDebugMode) {
        print('✅ Affichage de la mise à jour optionnelle');
      }
      return update;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Erreur lors de la vérification de version: $e');
      }
      // En cas d'erreur, ne pas bloquer l'application
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Unistudious',
          themeMode: themeProvider.themeMode,
          locale: const Locale('fr', 'FR'), // Set French locale
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate, // Added for MaterialLocalizations
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('fr', 'FR'),
            Locale('en', 'US'), // Optional fallback
          ],
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: themeProvider.primaryColor,
            scaffoldBackgroundColor: Colors.white,
            cardColor: Colors.white,
            textTheme: const TextTheme(
              headlineSmall: TextStyle(fontSize: 22),
              titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: themeProvider.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[400]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[400]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.deepPurpleAccent, width: 2),
              ),
              filled: true,
              fillColor: Colors.white,
              labelStyle: TextStyle(color: Colors.grey[600]),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: themeProvider.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            radioTheme: RadioThemeData(
              fillColor: MaterialStateProperty.all(themeProvider.primaryColor),
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: themeProvider.primaryColor,
            scaffoldBackgroundColor: const Color(0xFF121212),
            cardColor: const Color(0xFF1E1E2C),
            textTheme: const TextTheme(
              headlineSmall: TextStyle(fontSize: 22, color: Colors.white),
              titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: const Color(0xFF1A003D),
              foregroundColor: Colors.white,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[700]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[700]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.deepPurpleAccent, width: 2),
              ),
              filled: true,
              fillColor: Colors.grey[800],
              labelStyle: TextStyle(color: Colors.grey[400]),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: themeProvider.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            radioTheme: RadioThemeData(
              fillColor: MaterialStateProperty.all(themeProvider.primaryColor),
            ),
          ),
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final clamped = mq.copyWith(textScaler: const TextScaler.linear(1.0));
            final wrappedChild = MediaQuery(data: clamped, child: child!);
            return ResponsiveBreakpoints.builder(
              child: BouncingScrollWrapper.builder(context, wrappedChild),
              breakpoints: const [
                Breakpoint(start: 0, end: 389, name: MOBILE),
                Breakpoint(start: 390, end: 599, name: 'MOBILE_L'),
                Breakpoint(start: 600, end: 899, name: TABLET),
                Breakpoint(start: 900, end: double.infinity, name: DESKTOP),
              ],
            );
          },
          home: LoadingWrapper(
            child: FutureBuilder<String>(
              future: _getInitialRoute(context),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  // Vérifier la version avant de naviguer
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    if (!context.mounted) return;

                    final update = await _checkVersionAndGetUpdate();
                    if (update != null && context.mounted) {
                      if (kDebugMode) {
                        print('🚀 Affichage de la page de vérification de version');
                      }
                      // Afficher la page de vérification de version
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => VersionCheckPage(update: update),
                        ),
                      );
                      return;
                    }

                    // Continuer vers la route normale si pas de mise à jour
                    if (context.mounted) {
                      if (kDebugMode) {
                        print('➡️ Navigation vers la route normale: ${snapshot.data ?? '/welcome'}');
                      }
                      final route = snapshot.data ?? '/welcome';
                      // Si c'est une route de la bottom bar, utiliser MainNavigationPage
                      if (route == '/dashboard' || route == '/mes-cours' || route == '/fil-social' ||
                          route == '/ressources' || route == '/profile') {
                        final provider = Provider.of<BottomNavigationProvider>(context, listen: false);
                        const routeToIndexMap = {
                          '/dashboard': 0,
                          '/mes-cours': 1,
                          '/fil-social': 2,
                          '/ressources': 3,
                          '/profile': 4,
                        };
                        provider.updateIndex(routeToIndexMap[route] ?? 0);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const MainNavigationPage()),
                        );
                      } else {
                        Navigator.pushReplacementNamed(context, route);
                      }
                    }
                  });
                }
                return Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: themeProvider.primaryColor),
                  ),
                );
              },
            ),
          ),
          routes: {
            '/welcome': (context) => LoadingWrapper(child: WelcomePage()),
            '/login': (context) => LoadingWrapper(child: LoginPage()),
            '/signup': (context) => LoadingWrapper(child: SignUpPage()),
            '/forget-password': (context) => LoadingWrapper(child: ForgetPasswordPage()),
            '/dashboard': (context) {
              final provider = Provider.of<BottomNavigationProvider>(context, listen: false);
              provider.updateIndex(0);
              return const MainNavigationPage();
            },
            '/mes-cours': (context) {
              final provider = Provider.of<BottomNavigationProvider>(context, listen: false);
              provider.updateIndex(1);
              return const MainNavigationPage();
            },
            '/fil-social': (context) {
              final provider = Provider.of<BottomNavigationProvider>(context, listen: false);
              provider.updateIndex(2);
              return const MainNavigationPage();
            },
            '/ressources': (context) {
              final provider = Provider.of<BottomNavigationProvider>(context, listen: false);
              provider.updateIndex(3);
              return const MainNavigationPage();
            },
            '/profile': (context) {
              final provider = Provider.of<BottomNavigationProvider>(context, listen: false);
              provider.updateIndex(4);
              return const MainNavigationPage();
            },
            '/parametres': (context) => NavigationWrapper(child: SettingsPage(), currentRoute: '/parametres'),
            '/favorites': (context) => NavigationWrapper(child: FavoritesPage(), currentRoute: '/favorites'),
            '/push_notifications': (context) => NavigationWrapper(child: PushNotificationProfilePage(), currentRoute: '/push_notifications'),
            '/password-auth': (context) => NavigationWrapper(child: PasswordAuthPage(), currentRoute: '/password-auth'),
            '/terms-of-use': (context) => NavigationWrapper(child: TermsOfUsePage(), currentRoute: '/terms-of-use'),
            '/cookie-policy': (context) => NavigationWrapper(child: CookiePolicyPage(), currentRoute: '/cookie-policy'),
            '/payment-policy': (context) => NavigationWrapper(child: PaymentPolicyPage(), currentRoute: '/payment-policy'),
            '/refund-policy': (context) => NavigationWrapper(child: RefundPolicyPage(), currentRoute: '/refund-policy'),
            '/calendrier': (context) => NavigationWrapper(child: CalendarPage(), currentRoute: '/calendrier'),
            '/groups': (context) => NavigationWrapper(child: GroupsPage(), currentRoute: '/groups'),
            '/join-session': (context) => NavigationWrapper(child: JoinSessionPage(), currentRoute: '/join-session'),
            '/invoices': (context) => NavigationWrapper(child: InvoicePage(), currentRoute: '/invoices'),
            '/list-meet': (context) => NavigationWrapper(child: ListMeetPage(), currentRoute: '/list-meet'),
            '/presences': (context) => NavigationWrapper(child: AttendancePage(), currentRoute: '/presences'),
            '/google-login-page': (context) => NavigationWrapper(child: GoogleLoginPage(), currentRoute: '/google-login-page'),
            '/facebook-login': (context) => NavigationWrapper(child: FacebookLoginPage(), currentRoute: '/facebook-login'),
            '/apple_login': (context) => NavigationWrapper(child: AppleLoginPage(), currentRoute: '/apple_login'),
            '/messagerie': (context) => NavigationWrapper(child: MessageriePage(), currentRoute: '/messagerie'),
            '/groupes': (context) => NavigationWrapper(child: GroupesPage(), currentRoute: '/groupes'),
            '/chat': (context) => ChatPage(),
            '/free-resource': (context) => NavigationWrapper(child: RessourcesGratuitesPage(), currentRoute: '/free-resource'),
            '/theme-customization': (context) => NavigationWrapper(child: ThemeCustomizationPage(), currentRoute: '/theme-customization'),
          },
        );
      },
    );
  }
}