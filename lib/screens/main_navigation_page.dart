import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/bottom_navigation_provider.dart';
import '../models/app_bar_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_list_provider.dart';
import '../widgets/sidebar.dart';
import '../widgets/loading_wrapper.dart';
import '../widgets/notification_icon_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firebase_notification_service.dart';
import '../utils/snackbar_helper.dart';
import '../utils/session_status_cache.dart';
import '../models/user_model.dart';
import '../services/tutorial_service.dart';
import '../widgets/app_tutorial_overlay.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  bool _authChecked = false;
  bool _isAuthenticated = false;
  Timer? _notificationPollingTimer;

  final GlobalKey _menuKey = GlobalKey();
  final GlobalKey _notificationKey = GlobalKey();
  final List<GlobalKey> _tabKeys = List.generate(5, (_) => GlobalKey());

  bool _showTutorial = false;
  int _tutorialStep = 0;
  late final List<TutorialStepData> _tutorialSteps;

  static const List<String> _titles = [
    'Accueil',
    'Groupe',
    'Social',
    'Ressources',
    'Profil',
  ];

  static const List<IconData> _icons = [
    Icons.home,
    Icons.groups,      // Groupe : icône groupe de personnes
    Icons.forum,       // Social : icône discussion/fil social
    Icons.library_books,
    Icons.person,
  ];

  @override
  void initState() {
    super.initState();
    _tutorialSteps = [
      TutorialStepData(
        id: 'menu',
        title: 'Menu principal',
        description:
            'Ouvrez le menu pour accéder à vos cours, la messagerie, le calendrier, les paramètres et bien plus.',
        targetKey: _menuKey,
        tabIndexBeforeShow: 0,
      ),
      TutorialStepData(
        id: 'notifications',
        title: 'Notifications',
        description:
            'Consultez ici vos alertes : messages, rappels de cours, invitations et actualités.',
        targetKey: _notificationKey,
        tabIndexBeforeShow: 0,
      ),
      TutorialStepData(
        id: 'home',
        title: 'Accueil',
        description:
            'Votre tableau de bord : statistiques, centres de formation et accès rapide à vos sessions.',
        targetKey: _tabKeys[0],
        tabIndexBeforeShow: 0,
      ),
      TutorialStepData(
        id: 'join_session',
        title: 'Rejoindre une session',
        description:
            'Appuyez ici pour rejoindre une session de formation. Recherchez une session disponible ou acceptez une invitation, puis accédez à vos cours, groupes et ressources.',
        targetKey: TutorialKeys.joinSession,
        tabIndexBeforeShow: 0,
        scrollIntoView: true,
      ),
      TutorialStepData(
        id: 'groups',
        title: 'Groupes',
        description:
            'Retrouvez vos groupes de révision, calendriers et activités par session.',
        targetKey: _tabKeys[1],
        tabIndexBeforeShow: 1,
      ),
      TutorialStepData(
        id: 'social',
        title: 'Fil social',
        description:
            'Échangez avec la communauté : publications, commentaires et réactions.',
        targetKey: _tabKeys[2],
        tabIndexBeforeShow: 2,
      ),
      TutorialStepData(
        id: 'resources',
        title: 'Ressources',
        description:
            'Accédez aux documents partagés : dossiers, PDF, vidéos et supports de cours.',
        targetKey: _tabKeys[3],
        tabIndexBeforeShow: 3,
      ),
      TutorialStepData(
        id: 'profile',
        title: 'Profil',
        description:
            'Gérez votre profil, vos badges, statistiques et paramètres personnels.',
        targetKey: _tabKeys[4],
        tabIndexBeforeShow: 4,
      ),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndInit();
    });
  }

  Future<void> _checkAuthAndInit() async {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isLoggedIn) {
      _authChecked = true;
      _isAuthenticated = false;
      if (mounted) {
        SnackBarHelper.showWarning(context, 'Veuillez vous connecter pour continuer.');
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }
    _authChecked = true;
    _isAuthenticated = true;

    final cachedSession = await SessionStatusCache.load();
    if (cachedSession != null && mounted) {
      Provider.of<UserModel>(context, listen: false).hasActiveSession = cachedSession;
    }

    _loadNotificationsIfAuthenticated();
    _startNotificationPolling();
    _requestNotificationPermissionIfNeeded();
    if (mounted) setState(() {});
    _maybeStartTutorial();
  }

  Future<void> _maybeStartTutorial() async {
    final autoShow = await TutorialService.shouldShowAutomatically();
    final replay = await TutorialService.consumePendingReplay();
    if (!mounted || (!autoShow && !replay)) return;

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    setState(() {
      _tutorialStep = 0;
      _showTutorial = true;
    });
    await _applyTabForTutorialStep();
  }

  Future<void> _applyTabForTutorialStep() async {
    if (_tutorialStep >= _tutorialSteps.length) return;
    final step = _tutorialSteps[_tutorialStep];
    final tabIndex = step.tabIndexBeforeShow;
    if (tabIndex != null) {
      final navProvider = Provider.of<BottomNavigationProvider>(context, listen: false);
      navProvider.ensureTabLoaded(tabIndex);
      navProvider.updateIndex(tabIndex);
    }
    await Future.delayed(const Duration(milliseconds: 250));
    if (step.scrollIntoView) {
      await _waitForTutorialTarget(step.targetKey);
      await _scrollToTutorialTarget(step.targetKey);
    }
    if (mounted) setState(() {});
  }

  Future<void> _waitForTutorialTarget(GlobalKey key) async {
    for (var i = 0; i < 30; i++) {
      if (!mounted) return;
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) return;
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<void> _scrollToTutorialTarget(GlobalKey key) async {
    if (!mounted) return;
    final targetContext = key.currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.35,
    );
  }

  Future<void> _onTutorialNext() async {
    if (_tutorialStep >= _tutorialSteps.length - 1) {
      await TutorialService.markCompleted();
      if (mounted) setState(() => _showTutorial = false);
      return;
    }
    setState(() => _tutorialStep++);
    await _applyTabForTutorialStep();
  }

  Future<void> _onTutorialSkip() async {
    await TutorialService.markCompleted();
    if (mounted) setState(() => _showTutorial = false);
  }
  
  @override
  void dispose() {
    _notificationPollingTimer?.cancel();
    super.dispose();
  }
  
  Future<void> _loadNotificationsIfAuthenticated() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final notificationsProvider = Provider.of<NotificationsListProvider>(context, listen: false);
    
    // Charger le nombre de notifications seulement si l'utilisateur est connecté
    // Utiliser la nouvelle API de comptage qui est plus efficace
    if (authProvider.isLoggedIn && authProvider.currentToken != null) {
      await notificationsProvider.updateNotificationCount(authProvider);
    }
  }
  
  /// Demande la permission de notifications (popup système natif) si non accordée.
  /// Ne redemande pas pendant 7 jours pour éviter d'être intrusif.
  Future<void> _requestNotificationPermissionIfNeeded() async {
    await Future.delayed(const Duration(seconds: 1)); // Laisser l'utilisateur voir l'écran d'abord
    if (!mounted) return;

    final granted = await FirebaseNotificationService.isNotificationPermissionGranted();
    if (granted) return;

    final prefs = await SharedPreferences.getInstance();
    const key = 'notification_permission_last_requested';
    final lastRequested = prefs.getInt(key);
    if (lastRequested != null) {
      final diff = DateTime.now().millisecondsSinceEpoch - lastRequested;
      if (diff < 7 * 24 * 60 * 60 * 1000) return; // Déjà demandé dans les 7 derniers jours
    }

    await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
    await FirebaseNotificationService.requestNotificationPermission();

    if (!mounted) return;
    final nowGranted = await FirebaseNotificationService.isNotificationPermissionGranted();
    if (nowGranted) {
      final token = await FirebaseNotificationService.getToken();
      if (token != null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final authToken = authProvider.currentToken;
        if (authToken != null) {
          await FirebaseNotificationService.saveTokenToServer(token, authToken);
        }
      }
    }
  }

  void _onTabTapped(int index) {
    final navProvider = Provider.of<BottomNavigationProvider>(context, listen: false);
    navProvider.ensureTabLoaded(index);
    navProvider.updateIndex(index);
  }

  /// Démarre le polling périodique pour vérifier les nouvelles notifications
  void _startNotificationPolling() {
    // Annuler le timer existant s'il y en a un
    _notificationPollingTimer?.cancel();
    
    // Vérifier les notifications toutes les 30 secondes (réduit de 10s pour éviter la surcharge)
    // Le debouncing dans updateNotificationCount empêchera les appels trop fréquents
    _notificationPollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final notificationsProvider = Provider.of<NotificationsListProvider>(context, listen: false);
      
      // Vérifier seulement si l'utilisateur est connecté
      if (authProvider.isLoggedIn && authProvider.currentToken != null) {
        notificationsProvider.updateNotificationCount(authProvider);
      } else {
        // Arrêter le polling si l'utilisateur n'est plus connecté
        timer.cancel();
      }
    });
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
            final loadedTabs = navProvider.loadedTabIndices;

            return LoadingWrapper(
              child: Stack(
                children: [
                  Scaffold(
                appBar: _buildAppBar(context, appBarConfig, isDark),
                body: _authChecked && _isAuthenticated
                    ? IndexedStack(
                        index: navProvider.selectedIndex,
                        children: List.generate(
                          _titles.length,
                          (index) => loadedTabs.contains(index)
                              ? navProvider.buildPage(index)
                              : const SizedBox.shrink(),
                        ),
                      )
                    : Center(child: CircularProgressIndicator(color: themeProvider.primaryColor)),
                drawer: const AppSidebar(),
                bottomNavigationBar: _buildBottomNavigationBar(
                  navProvider: navProvider,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  isDark: isDark,
                ),
              ),
                  if (_showTutorial)
                    Positioned.fill(
                      child: AppTutorialOverlay(
                        steps: _tutorialSteps,
                        currentStep: _tutorialStep,
                        primaryColor: selectedColor,
                        onNext: _onTutorialNext,
                        onSkip: _onTutorialSkip,
                      ),
                    ),
                ],
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
    
    // Construire la liste des actions : actions personnalisées + icône de notification
    final List<Widget> actions = [];
    if (config.actions != null) {
      actions.addAll(config.actions!);
    }
    // Ajouter l'icône de notification à la fin
    actions.add(NotificationIconButton(tutorialKey: _notificationKey));
    
    return AppBar(
      leading: config.leading ??
          Builder(
            builder: (context) => IconButton(
              key: _menuKey,
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
      actions: actions,
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

  Widget _buildBottomNavigationBar({
    required BottomNavigationProvider navProvider,
    required Color selectedColor,
    required Color unselectedColor,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(_titles.length, (index) {
            final selected = navProvider.selectedIndex == index;
            final color = selected ? selectedColor : unselectedColor;
            return Expanded(
              child: InkWell(
                onTap: _showTutorial ? null : () => _onTabTapped(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        key: _tabKeys[index],
                        _icons[index],
                        color: color,
                        size: 26,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _titles[index],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

