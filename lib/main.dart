import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // Added for localization
import 'package:responsive_framework/responsive_framework.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io' show Platform;
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

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
import 'screens/qr_scanner_page.dart';
import 'screens/parent_invitations_page.dart';
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

// Instance de flutter_local_notifications pour afficher les notifications sur Android
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Variable globale pour recharger les notifications lorsqu'une notification Firebase arrive
Function()? _reloadNotificationsCallback;

// Référence globale à AuthProvider pour recharger les notifications
AuthProvider? _globalAuthProvider;

// Clé globale pour le NavigatorState afin de naviguer depuis n'importe où
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Fonction pour mapper les valeurs de redirect vers les vraies routes de l'application
String _mapRedirectToRoute(String redirectPath) {
  // Normaliser en minuscules pour la comparaison
  String normalized = redirectPath.toLowerCase().trim();
  
  // Mapping des valeurs de redirect (texte envoyé par Firebase) vers les routes réelles
  final Map<String, String> redirectMap = {
    // Messagerie / messages privés
    'message': '/messagerie',
    'messages': '/messagerie',
    'messagerie': '/messagerie',
    'inbox': '/messagerie',
    'private message': '/messagerie',

    // Chat direct
    'chat': '/chat',

    // Dashboard / accueil
    'dashboard': '/dashboard',
    'home': '/dashboard',
    'accueil': '/dashboard',

    // Cours / cours en ligne
    'cours': '/mes-cours',
    'mes-cours': '/mes-cours',
    'course': '/mes-cours',
    'courses': '/mes-cours',
    'online course': '/mes-cours',
    'cours en ligne': '/mes-cours',
    'meet': '/mes-cours',               // ton choix: meet -> cours en ligne

    // Social / fil social
    'social': '/fil-social',
    'fil-social': '/fil-social',
    'feed': '/fil-social',
    'social feed': '/fil-social',

    // Ressources
    'ressources': '/ressources',
    'resources': '/ressources',

    // Profil
    'profile': '/profile',
    'profil': '/profile',

    // Paramètres
    'settings': '/parametres',
    'parametres': '/parametres',

    // Calendrier / rappels
    'calendar': '/calendrier',
    'calendrier': '/calendrier',
    'reminder calendar': '/calendrier',
    'calendar reminder': '/calendrier',

    // Groupes
    'group': '/groups',
    'groups': '/groups',
    'groupes': '/groups',
    'group join': '/groups',
    'join group': '/groups',
    'group invitation': '/groups',

    // Factures / paiements
    'invoice': '/invoices',
    'invoices': '/invoices',
    'payment': '/invoices',
    'payment successful': '/invoices',
    'successful payment': '/invoices',
    'paiement': '/invoices',

    // Présences / attendance
    'attendance': '/presences',
    'presences': '/presences',
    'presence': '/presences',

    // Session / rejoindre une session
    'session': '/join-session',
    'session invitation': '/join-session',
    'join session': '/join-session',
    'rejoindre une session': '/join-session',
    
    // Cas spéciaux techniques (valeurs par défaut de Firebase pour Flutter)
    // On les redirige vers la messagerie pour les notifications de message
    'flutter_notification_click': '/messagerie',
  };
  
  // Vérifier si c'est déjà une route complète (commence par /)
  if (redirectPath.startsWith('/')) {
    // Vérifier si la route existe dans le mapping (sans le /)
    final routeWithoutSlash = redirectPath.substring(1).toLowerCase();
    return redirectMap[routeWithoutSlash] ?? redirectPath;
  }
  
  // Mapper la valeur normalisée
  return redirectMap[normalized] ?? '/$redirectPath';
}

// Fonction pour naviguer vers une route spécifique basée sur le paramètre redirect
void _navigateToRoute(String? redirectPath) {
  if (redirectPath == null || redirectPath.isEmpty) {
    if (kDebugMode) {
      print('⚠️ Aucun chemin de redirection fourni');
    }
    return;
  }

  // Mapper le redirect vers la vraie route
  String route = _mapRedirectToRoute(redirectPath);

  if (kDebugMode) {
    print('📍 Redirect original: $redirectPath');
    print('📍 Route mappée: $route');
  }

  final navigator = navigatorKey.currentState;
  if (navigator == null) {
    if (kDebugMode) {
      print('⚠️ NavigatorState non disponible, attente...');
    }
    // Attendre que le Navigator soit disponible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToRoute(redirectPath);
    });
    return;
  }

  try {
    // Vérifier si la route est une route de la bottom bar
    if (route == '/dashboard' || route == '/mes-cours' || route == '/fil-social' ||
        route == '/ressources' || route == '/profile') {
      final context = navigator.context;
      final provider = Provider.of<BottomNavigationProvider>(context, listen: false);
      const routeToIndexMap = {
        '/dashboard': 0,
        '/mes-cours': 1,
        '/fil-social': 2,
        '/ressources': 3,
        '/profile': 4,
      };
      provider.updateIndex(routeToIndexMap[route] ?? 0);
      navigator.pushNamedAndRemoveUntil(
        route,
        (route) => false,
      );
    } else {
      // Pour les autres routes, navigation normale
      navigator.pushNamedAndRemoveUntil(
        route,
        (route) => false,
      );
    }
    if (kDebugMode) {
      print('✅ Navigation réussie vers: $route');
    }
  } catch (e) {
    if (kDebugMode) {
      print('❌ Erreur lors de la navigation vers $route: $e');
    }
  }
}

// Initialiser flutter_local_notifications pour Android
Future<void> _initializeLocalNotifications() async {
  if (!Platform.isAndroid) return;

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (kDebugMode) {
        print('📱 Notification cliquée: ${response.payload}');
      }
    },
  );

  // Créer le canal de notification pour Android
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'unistudious_notifications', // id
    'Notifications', // name
    description: 'Notifications pour Unistudious',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  if (kDebugMode) {
    print('✅ flutter_local_notifications initialisé pour Android');
  }
}

// Handler pour les messages en background (quand l'app est fermée ou en background)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (kDebugMode) {
    final platform = Platform.isIOS ? '🍎 iOS' : (Platform.isAndroid ? '🤖 Android' : '❓ Unknown');
    print('═══════════════════════════════════════════════════════');
    print('📨 MESSAGE REÇU EN BACKGROUND (Flutter)');
    print('   Plateforme: $platform');
    print('═══════════════════════════════════════════════════════');
    print('Message ID: ${message.messageId}');
    print('From: ${message.from}');
    print('Sent Time: ${message.sentTime}');
    print('');
    print('--- NOTIFICATION ---');
    if (message.notification != null) {
      print('  Title: ${message.notification?.title}');
      print('  Body: ${message.notification?.body}');
    } else {
      print('  ⚠️ Aucune notification');
    }
    print('');
    print('--- DATA ---');
    if (message.data.isNotEmpty) {
      print('  Nombre de données: ${message.data.length}');
      message.data.forEach((key, value) {
        print('  $key: $value');
      });
    } else {
      print('  ⚠️ Aucune donnée');
    }
    print('═══════════════════════════════════════════════════════');
  }
}

// Afficher une notification locale sur Android
Future<void> _showLocalNotification(String title, String body) async {
  if (!Platform.isAndroid) return;

  try {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'unistudious_notifications',
      'Notifications',
      channelDescription: 'Notifications pour Unistudious',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      platformChannelSpecifics,
    );

    if (kDebugMode) {
      print('✅ Notification locale affichée sur Android');
      print('   Title: $title');
      print('   Body: $body');
    }
  } catch (e) {
    if (kDebugMode) {
      print('❌ Erreur lors de l\'affichage de la notification locale: $e');
    }
  }
}

// Fonction pour recharger les notifications immédiatement
void _reloadNotifications() {
  final notificationsProvider = NotificationsListProvider.instance;
  if (notificationsProvider != null && _globalAuthProvider != null) {
    if (_globalAuthProvider!.isLoggedIn && _globalAuthProvider!.currentToken != null) {
      if (kDebugMode) {
        print('🔄 Mise à jour IMMÉDIATE du nombre de notifications depuis Firebase...');
      }
      // Utiliser la nouvelle API de comptage qui est plus efficace
      // Ne pas attendre le résultat pour être plus rapide
      notificationsProvider.updateNotificationCount(_globalAuthProvider).catchError((error) {
        if (kDebugMode) {
          print('❌ Erreur lors de la mise à jour immédiate: $error');
        }
      });
    }
  } else if (_reloadNotificationsCallback != null) {
    // Fallback vers le callback si disponible
    _reloadNotificationsCallback!();
  } else {
    if (kDebugMode) {
      print('⚠️ Impossible de recharger les notifications: provider=${notificationsProvider != null}, authProvider=${_globalAuthProvider != null}');
    }
  }
}

// Configuration des handlers Firebase Messaging
void _setupFirebaseMessaging() {
  final messaging = FirebaseMessaging.instance;
  
  // Handler pour les messages en foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    // Recharger les notifications IMMÉDIATEMENT lorsqu'une notification arrive
    // Appeler plusieurs fois pour s'assurer que ça fonctionne
    _reloadNotifications();
    // Attendre un court délai et recharger à nouveau pour être sûr
    Future.delayed(const Duration(milliseconds: 500), () {
      _reloadNotifications();
    });
    
    if (kDebugMode) {
      final platform = Platform.isIOS ? '🍎 iOS' : (Platform.isAndroid ? '🤖 Android' : '❓ Unknown');
      print('═══════════════════════════════════════════════════════');
      print('📨 NOTIFICATION REÇUE EN FOREGROUND (Flutter)');
      print('   Plateforme: $platform');
      print('═══════════════════════════════════════════════════════');
      print('Message ID: ${message.messageId}');
      print('From: ${message.from}');
      print('Sent Time: ${message.sentTime}');
      print('Message Type: ${message.messageType}');
      print('Collapse Key: ${message.collapseKey}');
      print('Ttl: ${message.ttl}');
      print('');
      print('--- NOTIFICATION ---');
      if (message.notification != null) {
        print('  ✅ Notification présente');
        print('  Title: ${message.notification?.title}');
        print('  Body: ${message.notification?.body}');
        if (Platform.isIOS) {
          print('  🍎 iOS: La notification sera affichée par iOS');
        } else if (Platform.isAndroid) {
          print('  🤖 Android: La notification sera affichée par le service Android');
        }
      } else {
        print('  ⚠️ Aucune notification dans le message');
      }
      print('');
      print('--- DATA ---');
      if (message.data.isNotEmpty) {
        print('  ✅ Données présentes: ${message.data.length} élément(s)');
        message.data.forEach((key, value) {
          print('  $key: $value');
        });
      } else {
        print('  ⚠️ Aucune donnée dans le message');
      }
      print('');
      print('--- DIAGNOSTIC ---');
      print('  Plateforme: $platform');
      print('  Notification null: ${message.notification == null}');
      print('  Data empty: ${message.data.isEmpty}');
      print('  Message complet: ${message.toString()}');
      
      if (message.notification == null && message.data.isEmpty) {
        print('');
        print('⚠️ PROBLÈME DÉTECTÉ: Message reçu mais vide!');
        print('   Cela signifie que le message depuis le web est mal formaté.');
        print('   Le message doit contenir soit:');
        print('   - Un champ "notification" avec "title" et "body"');
        print('   - Ou un champ "data" avec au moins "title" et "body"');
        print('');
        print('⚠️ Sur Android, le service natif devrait être appelé mais ne l\'est pas.');
        print('   Cela indique que Flutter intercepte le message avant le service natif.');
      } else if (message.notification != null) {
        print('');
        print('✅ Message valide avec notification');
        if (Platform.isIOS) {
          print('   Sur iOS, la notification sera affichée automatiquement');
        } else if (Platform.isAndroid) {
          print('   🤖 Android: Affichage manuel de la notification avec flutter_local_notifications');
          // Afficher la notification manuellement sur Android
          _showLocalNotification(
            message.notification!.title ?? 'Notification',
            message.notification!.body ?? '',
          );
        }
      } else if (message.data.isNotEmpty) {
        print('');
        print('✅ Message data-only détecté');
        print('   Le service Android/iOS devrait créer une notification');
        // Essayer d'extraire title et body des données
        if (Platform.isAndroid) {
          final title = message.data['title'] ?? 
                       message.data['notification.title'] ?? 
                       message.data['notification_title'] ?? 
                       'Notification';
          final body = message.data['body'] ?? 
                      message.data['message'] ?? 
                      message.data['notification.body'] ?? 
                      message.data['notification_body'] ?? 
                      message.data['text'] ?? 
                      'Nouvelle notification';
          _showLocalNotification(title, body);
        }
      }
      print('═══════════════════════════════════════════════════════');
      print('');
    }
  });
  
  // Handler pour les messages en background
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // Handler pour les notifications ouvertes (quand l'utilisateur clique dessus)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    // Recharger immédiatement les notifications quand l'utilisateur ouvre une notification
    _reloadNotifications();
    if (kDebugMode) {
      final platform = Platform.isIOS ? '🍎 iOS' : (Platform.isAndroid ? '🤖 Android' : '❓ Unknown');
      print('═══════════════════════════════════════════════════════');
      print('📱 NOTIFICATION OUVERTE PAR L\'UTILISATEUR');
      print('   Plateforme: $platform');
      print('═══════════════════════════════════════════════════════');
      print('Message ID: ${message.messageId}');
      print('From: ${message.from}');
      print('--- NOTIFICATION ---');
      print('  Title: ${message.notification?.title}');
      print('  Body: ${message.notification?.body}');
      print('--- DATA ---');
      if (message.data.isNotEmpty) {
        message.data.forEach((key, value) {
          print('  $key: $value');
        });
      } else {
        print('  Aucune donnée');
      }
      print('═══════════════════════════════════════════════════════');
    }
    
    // Extraire le paramètre redirect/location et naviguer vers la page spécifique
    // Vérifier d'abord dans les données, puis dans l'action (pour iOS)
    final redirectPath = message.data['redirect'] 
        ?? message.data['location'] 
        ?? message.data['route']
        ?? message.data['action'];  // Certains services utilisent 'action' au lieu de 'click_action'
    if (redirectPath != null) {
      if (kDebugMode) {
        print('📍 Paramètre redirect trouvé dans les données: $redirectPath');
      }
      _navigateToRoute(redirectPath);
    } else {
      if (kDebugMode) {
        print('⚠️ Aucun paramètre redirect/location trouvé dans les données');
        print('   Note: Sur Android, le clickAction est géré via le canal de méthode native');
      }
    }
  });
  
  // Vérifier si l'app a été ouverte depuis une notification
  messaging.getInitialMessage().then((RemoteMessage? message) {
    // Recharger les notifications si l'app a été ouverte depuis une notification
    if (message != null) {
      _reloadNotifications();
      if (kDebugMode) {
        final platform = Platform.isIOS ? '🍎 iOS' : (Platform.isAndroid ? '🤖 Android' : '❓ Unknown');
        print('═══════════════════════════════════════════════════════');
        print('📱 APP OUVERTE DEPUIS UNE NOTIFICATION');
        print('   Plateforme: $platform');
        print('═══════════════════════════════════════════════════════');
        print('Message ID: ${message.messageId}');
        print('From: ${message.from}');
      print('--- NOTIFICATION ---');
      print('  Title: ${message.notification?.title}');
      print('  Body: ${message.notification?.body}');
      print('--- DATA ---');
      if (message.data.isNotEmpty) {
        message.data.forEach((key, value) {
          print('  $key: $value');
        });
      } else {
        print('  Aucune donnée');
      }
      print('═══════════════════════════════════════════════════════');
      }
      
      // Extraire le paramètre redirect/location et naviguer vers la page spécifique
      // Vérifier d'abord dans les données, puis dans l'action
      final redirectPath = message.data['redirect'] 
          ?? message.data['location'] 
          ?? message.data['route']
          ?? message.data['action'];  // Certains services utilisent 'action'
      if (redirectPath != null) {
        if (kDebugMode) {
          print('📍 Paramètre redirect trouvé dans les données: $redirectPath');
        }
        // Attendre que l'app soit complètement initialisée avant de naviguer
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 500), () {
            _navigateToRoute(redirectPath);
          });
        });
      } else {
        if (kDebugMode) {
          print('⚠️ Aucun paramètre redirect/location trouvé dans les données');
          print('   Note: Sur Android, le clickAction est géré via le canal de méthode native');
        }
      }
    }
  });
  
  if (kDebugMode) {
    print('✅ Handlers Firebase Messaging configurés');
  }
  
  // Configurer le canal de méthode pour recevoir les notifications depuis les plateformes natives
  _setupNotificationChannel();
}

// Configurer le canal de méthode pour recevoir les notifications depuis Android/iOS
void _setupNotificationChannel() {
  const MethodChannel channel = MethodChannel('com.unistudious.projet1v2/notification');
  
  channel.setMethodCallHandler((call) async {
    if (call.method == 'onNotificationOpened') {
      final Map<dynamic, dynamic>? arguments = call.arguments as Map<dynamic, dynamic>?;
      if (arguments != null) {
        final redirectPath = arguments['redirect'] as String?;
        if (kDebugMode) {
          print('📱 Notification ouverte depuis plateforme native');
          print('📍 Paramètre redirect reçu: $redirectPath');
        }
        if (redirectPath != null) {
          // Attendre que l'app soit complètement initialisée
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future.delayed(const Duration(milliseconds: 500), () {
              _navigateToRoute(redirectPath);
            });
          });
        }
      }
    }
  });
  
  if (kDebugMode) {
    print('✅ Canal de méthode pour notifications configuré');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Utiliser le Photo Picker Android (sans READ_MEDIA_IMAGES/VIDEO) pour conformité Google Play
  if (Platform.isAndroid) {
    final imagePickerImplementation = ImagePickerPlatform.instance;
    if (imagePickerImplementation is ImagePickerAndroid) {
      imagePickerImplementation.useAndroidPhotoPicker = true;
    }
  }

  // Initialiser Firebase
  try {
    await Firebase.initializeApp();
    if (kDebugMode) {
      print('✅ Firebase initialisé avec succès');
    }
    
    // Initialiser flutter_local_notifications pour Android
    await _initializeLocalNotifications();
    
    // Configurer les handlers pour les notifications Firebase
    _setupFirebaseMessaging();
  } catch (e) {
    if (kDebugMode) {
      print('❌ Erreur lors de l\'initialisation de Firebase: $e');
    }
  }

  // Initialiser AppConfig pour récupérer la plateforme et la version
  await AppConfig.initialize();

  final themeProvider = ThemeProvider();
  await themeProvider.loadTheme();

  final authProvider = AuthProvider();
  _globalAuthProvider = authProvider;
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserModel()),
        ChangeNotifierProvider(create: (_) => BottomNavigationProvider()),
        ChangeNotifierProvider(create: (_) => AppBarProvider()),
        ChangeNotifierProvider(create: (_) => authProvider),
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
        // Afficher toutes les mises à jour reçues
        for (var i = 0; i < response.updates.length; i++) {
          final u = response.updates[i];
          print('  📋 Update $i: Version=${u.version}, Required=${u.required}, Status=${u.status}');
        }
      }

      if (!response.hasUpdate) {
        if (kDebugMode) {
          print('ℹ️ Aucune mise à jour disponible');
        }
        return null;
      }

      // Sélectionner la mise à jour à afficher (uniquement parmi celles dans l'API)
      // Ne pas utiliser de cache - utiliser uniquement les données de l'API
      final update = response.firstUpdate;
      if (update == null) {
        if (kDebugMode) {
          print('❌ Aucune mise à jour trouvée dans la réponse');
        }
        return null;
      }

      if (kDebugMode) {
        print('📦 Mise à jour sélectionnée - Version: ${update.version}, Required: ${update.required}, Status: ${update.status}');
      }

      // Si la mise à jour est obligatoire, toujours l'afficher
      if (update.required) {
        if (kDebugMode) {
          print('🔒 Mise à jour obligatoire détectée - Affichage obligatoire');
        }
        return update;
      }

      // Si la mise à jour n'est pas obligatoire, l'afficher quand même
      // L'utilisateur pourra la skip, mais on ne l'enregistre pas dans le cache
      // Si elle n'est plus dans l'API la prochaine fois, elle ne s'affichera pas
      if (kDebugMode) {
        print('✅ Affichage de la mise à jour optionnelle (pas de cache utilisé)');
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
          navigatorKey: navigatorKey,
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
            // Mettre à jour la référence globale à AuthProvider si nécessaire
            final authProvider = Provider.of<AuthProvider>(context, listen: false);
            if (_globalAuthProvider != authProvider) {
              _globalAuthProvider = authProvider;
            }
            
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
            '/qr-scanner': (context) => NavigationWrapper(child: const QRScannerPage(), currentRoute: '/qr-scanner'),
            '/parent-invitations': (context) => NavigationWrapper(child: const ParentInvitationsPage(), currentRoute: '/parent-invitations'),
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