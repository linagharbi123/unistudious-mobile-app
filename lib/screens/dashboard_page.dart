import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/loading_wrapper.dart';
import 'dart:developer' as developer;
import 'dart:async';
import 'dart:typed_data';
import '../widgets/sidebar.dart';
import '../models/app_bar_provider.dart';
import 'package:provider/provider.dart';
import 'join_session_page.dart';
import '../utils/connection_checker.dart';
import '../services/page_cache_service.dart';
import '../utils/session_status_cache.dart';
import '../services/tutorial_service.dart';

final double spacing = 8.0;

class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  List<dynamic> accounts = [];
  List<dynamic> sessions = [];
  int totalSessions = 0;
  int totalUsers = 0;
  int totalInstructors = 0;
  int totalAccounts = 0;
  int totalFormations = 0;

  Map<String, Uint8List> _imageCache = {};

  late AnimationController _controller;
  late Animation<double> _summaryFade;
  late Animation<Offset> _summarySlide;

  final ScrollController _accountsScrollController = ScrollController();
  int _currentAccountIndex = 0;
  bool isConnectionError = false;
  bool isLoading = true;
  Timer? _connectionCheckTimer;

  @override
  void initState() {
    super.initState();
    developer.log('Initializing DashboardPage', name: 'DashboardPage');
    _startConnectionMonitoring();

    // Configurer l'AppBar via le provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final appBarProvider = Provider.of<AppBarProvider>(context, listen: false);
        appBarProvider.updateConfig(0, AppBarConfig(
          title: 'Tableau de bord',
        ));
      }
    });

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _summaryFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.25, curve: Curves.easeOut),
    );
    _summarySlide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.25, curve: Curves.easeOut),
      ),
    );

    _accountsScrollController.addListener(() {
      _updateScrollIndex(
        controller: _accountsScrollController,
        itemCount: accounts.length,
        currentIndex: _currentAccountIndex,
        onIndexChanged: (index) => _currentAccountIndex = index,
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndFetchData();
    });
  }

  @override
  void dispose() {
    _connectionCheckTimer?.cancel();
    _accountsScrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _startConnectionMonitoring() {
    // Vérifier la connexion toutes les 3 secondes si isConnectionError est true
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (isConnectionError && mounted) {
        ConnectionChecker().hasConnection().then((hasConnection) {
          if (hasConnection && mounted) {
            // La connexion est revenue, recharger les données automatiquement
            setState(() {
              isConnectionError = false;
            });
            fetchDashboardData();
          }
        });
      }
    });
  }

  // ... tout le reste du code (fetch, _statCard, _centerCard, etc.) reste IDENTIQUE ...

  void _updateScrollIndex({
    required ScrollController controller,
    required int itemCount,
    required int currentIndex,
    required ValueChanged<int> onIndexChanged,
  }) {
    if (itemCount == 0) return;
    final index = (controller.offset / 336).round();
    if (index != currentIndex && index >= 0 && index < itemCount) {
      setState(() => onIndexChanged(index));
    }
  }

  List<dynamic> _filterAccountsData(List<dynamic> accountsData) {
    final filtered = <dynamic>[];

    for (final account in accountsData) {
      if (account is! Map) continue;
      final name = (account['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      filtered.add(account);
    }

    return filtered;
  }

  Future<void> _loadFromCache() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final cached = await PageCacheService.load(
      'dashboard',
      userToken: authProvider.currentToken,
    );
    if (cached == null || !mounted) return;

    setState(() {
      final cachedAdmin = List<dynamic>.from(cached['adminAccounts'] ?? []);
      final cachedTeacher = List<dynamic>.from(cached['teacherAccounts'] ?? []);
      accounts = List<dynamic>.from(
        cached['accounts'] ??
            (cachedAdmin.isNotEmpty || cachedTeacher.isNotEmpty
                ? [...cachedAdmin, ...cachedTeacher]
                : cached['centers'] ?? []),
      );
      sessions = List<dynamic>.from(cached['sessions'] ?? []);
      totalSessions = (cached['totalSessions'] as num?)?.toInt() ?? 0;
      totalUsers = (cached['totalUsers'] as num?)?.toInt() ?? 0;
      totalInstructors = (cached['totalInstructors'] as num?)?.toInt() ?? 0;
      totalAccounts = (cached['totalAccounts'] as num?)?.toInt() ?? 0;
      totalFormations = (cached['totalFormations'] as num?)?.toInt() ?? 0;
      _currentAccountIndex = 0;
      isLoading = false;
    });
    if (mounted) {
      SessionStatusCache.updateUserModel(context, sessions.isNotEmpty);
    }
    _controller.forward();
  }

  Future<void> _checkAuthAndFetchData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Veuillez vous connecter pour continuer.')),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
      });
      return;
    }

    await _loadFromCache();
    if (mounted && accounts.isEmpty) {
      setState(() => isLoading = true);
    }
    await fetchDashboardData();
  }

  Future<void> fetchDashboardData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    const endpoint = '/index-mobile';

    developer.log('Fetching dashboard data...', name: 'DashboardPage');

    try {
      final response = await authProvider
          .authenticatedRequest('GET', endpoint)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        developer.log('Dashboard data: $data', name: 'DashboardPage');

        final accountsData = _filterAccountsData(data['accountsData'] ?? []);
        final sessionsData = data['sessionData'] ?? [];
        final totalSessionsData = (data['allSession'] as num?)?.toInt() ?? 0;
        final totalUsersData = (data['users'] as num?)?.toInt() ?? 0;
        final totalInstructorsData = (data['allInstructor'] as num?)?.toInt() ?? 0;
        final totalAccountsData = (data['allAccounts'] as num?)?.toInt() ?? 0;
        final totalFormationsData = (data['allFormations'] as num?)?.toInt() ?? 0;

        // Afficher les données tout de suite, précharger les images en arrière-plan
        setState(() {
          accounts = accountsData;
          sessions = sessionsData;
          totalSessions = totalSessionsData;
          totalUsers = totalUsersData;
          totalInstructors = totalInstructorsData;
          totalAccounts = totalAccountsData;
          totalFormations = totalFormationsData;
          _currentAccountIndex = 0;
          isLoading = false;
        });

        if (mounted) {
          SessionStatusCache.updateUserModel(context, sessionsData.isNotEmpty);
        }

        _controller.forward();
        _preloadImages(accountsData).then((_) {
          if (mounted) setState(() {});
        });

        await PageCacheService.save(
          'dashboard',
          {
            'accounts': accountsData,
            'sessions': sessionsData,
            'totalSessions': totalSessionsData,
            'totalUsers': totalUsersData,
            'totalInstructors': totalInstructorsData,
            'totalAccounts': totalAccountsData,
            'totalFormations': totalFormationsData,
          },
          userToken: authProvider.currentToken,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur ${response.statusCode} lors du chargement.')),
          );
        }
      }
    } catch (e) {
      developer.log('Error: $e', name: 'DashboardPage');
      
      // Détecter les erreurs de connexion et ne pas afficher de snackbar
      final isNetworkError = e is SocketException || 
                             e is TimeoutException ||
                             e.toString().contains('SocketException') ||
                             e.toString().contains('Failed host lookup') ||
                             e.toString().contains('Network is unreachable') ||
                             e.toString().contains('Connection refused') ||
                             e.toString().contains('Connection timed out') ||
                             e.toString().contains('No Internet connection') ||
                             e.toString().contains('ClientException') ||
                             e.toString().contains('OS Error');
      
      if (mounted) {
        setState(() {
          if (isNetworkError) {
            isConnectionError = true;
          } else {
            isConnectionError = false;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur : $e')),
            );
          }
        });
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String formatNumber(int number) {
    if (number >= 1000000) {
      return "${(number / 1000000).toStringAsFixed(0)}M+";
    } else if (number >= 1000) {
      return "${(number / 1000).toStringAsFixed(0)}K+";
    } else {
      return "$number+";
    }
  }

  Widget _statCard(String label, int value, double width) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedCounter(
            value: value,
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterImage(Map<String, dynamic> center) {
    final theme = Theme.of(context);

    if (center['image'] == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Image.asset(
          'assets/centre.png',
          height: 200,
          fit: BoxFit.contain,
        ),
      );
    }

    if (_imageCache.containsKey(center['image'])) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Image.memory(
          _imageCache[center['image']]!,
          height: 200,
          fit: BoxFit.contain,
        ),
      );
    }

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Image.asset(
        'assets/centre.png',
        height: 200,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _accountCard(Map<String, dynamic> account, {required bool isTeacher}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final description = (account['frontEndDescription'] as String?)?.trim();
    final subtitle = description?.isNotEmpty == true
        ? description!
        : (isTeacher
            ? 'Enseignant indépendant'
            : 'Centre de formation');

    return Container(
      width: 320,
      height: 420,
      margin: const EdgeInsets.all(8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black45 : Colors.grey.shade400).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildCenterImage(account),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isTeacher
                  ? (isDark ? Colors.orange.withOpacity(0.2) : Colors.orange.shade50)
                  : (isDark ? Colors.deepPurple.withOpacity(0.2) : Colors.deepPurple.shade50),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isTeacher ? 'Compte enseignant' : 'Compte admin',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isTeacher
                    ? (isDark ? Colors.orange.shade300 : Colors.orange.shade800)
                    : (isDark ? Colors.deepPurple.shade200 : Colors.deepPurple.shade700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            account['name'] ?? 'Compte inconnu',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Flexible(
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [Color(0xFF1A003D), Color(0xFF3C0D73)]
                    : const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: ElevatedButton(
              onPressed: () {
                final accountSessions =
                    sessions.where((session) => session['accountId'] == account['id']).toList();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CenterSessionsPage(
                      center: account,
                      sessions: accountSessions,
                      isTeacher: isTeacher,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: Text(
                'En savoir plus',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountsCarouselSection({
    required String title,
    required String subtitle,
    required List<dynamic> accounts,
    required ScrollController scrollController,
    required int currentIndex,
    required String emptyMessage,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [Colors.purple.shade900.withOpacity(0.4), Colors.blue.shade900.withOpacity(0.3)]
              : [Colors.purple.shade50, Colors.blue.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.4 : 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.orange.shade400 : Colors.deepPurple.shade800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 15,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 480,
            child: accounts.isEmpty
                ? Center(
                    child: Text(
                      emptyMessage,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: isDark ? Colors.white70 : Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    itemCount: accounts.length,
                    itemBuilder: (context, index) {
                      final account = accounts[index];
                      final isTeacher = account['isTeacher'] == true;
                      return _accountCard(account, isTeacher: isTeacher);
                    },
                  ),
          ),
          const SizedBox(height: 10),
          if (accounts.isNotEmpty)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  accounts.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 9,
                    width: index == currentIndex ? 24 : 9,
                    decoration: BoxDecoration(
                      color: index == currentIndex
                          ? (isDark ? Colors.orange.shade400 : Colors.deepPurple)
                          : Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _preloadImages(List<dynamic> centersData) async {
    final futures = <Future<void>>[];

    for (final center in centersData) {
      if (center['image'] != null && !_imageCache.containsKey(center['image'])) {
        futures.add(_fetchImageWithAuth(center['image']).then((imageData) {
          if (imageData != null) {
            _imageCache[center['image']] = imageData;
          }
        }));
      }
    }

    await Future.wait(futures);
  }

  Future<Uint8List?> _fetchImageWithAuth(String filename) async {
    if (_imageCache.containsKey(filename)) {
      return _imageCache[filename];
    }

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.currentToken;
      if (token == null) return null;

      final url = 'https://www.unistudious.com/api/public-image-server/$filename';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'image/*',
        },
      );

      if (response.statusCode == 200) {
        _imageCache[filename] = response.bodyBytes;
        developer.log('Image ${filename} chargée avec succès', name: 'DashboardPage');
        return response.bodyBytes;
      } else {
        developer.log('Erreur image ${filename}: ${response.statusCode}', name: 'DashboardPage');
        return null;
      }
    } catch (e) {
      developer.log('Erreur fetch image $filename: $e', name: 'DashboardPage');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LoadingWrapper(
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: isDark ? Colors.deepPurple : theme.primaryColor,
                ),
              )
            : isConnectionError
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.wifi_off,
                      size: 80,
                      color: theme.iconTheme.color?.withOpacity(0.6) ?? Colors.grey[400],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Vérifiez votre connexion',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: GoogleFonts.poppins().fontFamily,
                        color: theme.textTheme.bodyLarge?.color,
                      ) ??
                          TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                            color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Text(
                        'Assurez-vous que votre connexion internet est active et réessayez',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                          fontFamily: GoogleFonts.poppins().fontFamily,
                        ) ??
                            TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          isConnectionError = false;
                        });
                        fetchDashboardData();
                      },
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        'Réessayer',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: GoogleFonts.poppins().fontFamily,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFF1A003D) : theme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        textStyle: TextStyle(
                          fontSize: 16,
                          fontFamily: GoogleFonts.poppins().fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
          onRefresh: fetchDashboardData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // SECTION HERO + ACCÈS RAPIDE AUX FONCTIONNALITÉS
                    Center(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Image.asset('assets/student.png', height: 180),
                          const SizedBox(height: 8),
                          Text(
                            'Votre espace d\'apprentissage',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.orange : Colors.deepPurple.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Rejoignez vos sessions en un clic et suivez votre progression.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: isDark ? Colors.white70 : Colors.grey.shade700,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // CARTE PRINCIPALE "REJOINDRE UNE SESSION"
                          KeyedSubtree(
                            key: TutorialKeys.joinSession,
                            child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isDark
                                    ? const [Color(0xFF1A003D), Color(0xFF3C0D73)]
                                    : const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: (isDark ? Colors.purple.shade900 : Colors.deepPurple.shade300).withOpacity(0.4),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(28),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => JoinSessionPage()),
                                  );
                                },
                                splashColor: Colors.white.withOpacity(0.2),
                                highlightColor: Colors.white.withOpacity(0.1),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  'Rejoindre une session', 
                                                  style: GoogleFonts.poppins(
                                                    color: Colors.white,
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Accédez rapidement à vos cours en direct et vos réunions.',
                                              style: GoogleFonts.poppins(
                                                color: Colors.white.withOpacity(0.92),
                                                fontSize: 14,
                                                height: 1.4,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.3),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.arrow_forward_rounded,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          ),

                          const SizedBox(height: 20),

                          // Raccourcis rapides du dashboard
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _QuickActionCard(
                                icon: Icons.calendar_today_rounded,
                                label: 'Calendrier',
                                onTap: () => Navigator.pushNamed(context, '/calendrier'),
                                isDark: isDark,
                              ),
                              _QuickActionCard(
                                icon: Icons.list_alt_rounded,
                                label: 'Cours en ligne',
                                onTap: () => Navigator.pushNamed(context, '/list-meet'),
                                isDark: isDark,
                              ),
                              _QuickActionCard(
                                icon: Icons.menu_book_rounded,
                                label: 'Ressources',
                                onTap: () => Navigator.pushNamed(context, '/ressources'),
                                isDark: isDark,
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // Petit bouton secondaire "À propos de nous"
                          Container(
                            width: 220,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isDark
                                    ? const [Colors.orangeAccent, Colors.orange]
                                    : const [Colors.orange, Colors.red],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Center(
                              child: Text(
                                'À propos de nous',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),

                    SlideTransition(
                      position: _summarySlide,
                      child: FadeTransition(
                        opacity: _summaryFade,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const spacing = 12.0;
                            const columns = 2;
                            final tileWidth =
                                (constraints.maxWidth - spacing * (columns - 1)) / columns * 0.8;

                            return Center(
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: spacing,
                                runSpacing: spacing,
                                children: [
                                  _statCard("Sessions", totalSessions, tileWidth),
                                  _statCard("Formations", totalFormations, tileWidth),
                                  _statCard("Étudiants", totalUsers, tileWidth),
                                  _statCard("Instructeurs", totalInstructors, tileWidth),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _accountsCarouselSection(
                      title: 'Centres & enseignants',
                      subtitle: 'Découvrez les comptes admin et les profils enseignants',
                      accounts: accounts,
                      scrollController: _accountsScrollController,
                      currentIndex: _currentAccountIndex,
                      emptyMessage: 'Aucun compte disponible pour le moment',
                    ),
                    const SizedBox(height: 40),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _QuickActionCard({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: isDark ? Colors.orangeAccent : Colors.deepPurple,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// AnimatedCounter et CenterSessionsPage inchangés (identiques à ton code original)
class AnimatedCounter extends StatelessWidget {
  final int value;
  final TextStyle style;
  final Duration duration;

  const AnimatedCounter({
    Key? key,
    required this.value,
    required this.style,
    this.duration = const Duration(milliseconds: 600),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      builder: (context, val, child) {
        return Text(
          _format(val),
          style: style,
        );
      },
    );
  }

  String _format(int number) {
    if (number >= 1000000) {
      return "${(number / 1000000).toStringAsFixed(0)}M+";
    } else if (number >= 1000) {
      return "${(number / 1000).toStringAsFixed(0)}K+";
    } else {
      return "$number+";
    }
  }
}

class CenterSessionsPage extends StatelessWidget {
  final Map<String, dynamic> center;
  final List<dynamic> sessions;
  final bool isTeacher;

  const CenterSessionsPage({
    Key? key,
    required this.center,
    required this.sessions,
    this.isTeacher = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LoadingWrapper(
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 16, bottom: 16, left: 0, right: 0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? const [Color(0xFF1A003D), Color(0xFF3C0D73)]
                      : const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: theme.appBarTheme.iconTheme?.color ?? Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isTeacher ? Icons.person : Icons.school,
                      color: theme.appBarTheme.iconTheme?.color ?? Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        center['name'] ?? (isTeacher ? 'Enseignant' : 'Centre'),
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.appBarTheme.foregroundColor ?? Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: sessions.isEmpty
                  ? Center(
                child: Text(
                  'Aucune session pour le moment.',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                    shadowColor: theme.shadowColor.withOpacity(0.2),
                    color: theme.cardColor,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.event_note, color: isDark ? Colors.white : Colors.deepPurple),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  session['name'] ?? 'Session sans nom',
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.deepPurple.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 16, color: isDark ? Colors.white70 : Colors.grey),
                              const SizedBox(width: 6),
                              Text(
                                "Début: ${session['startDate'] ?? 'N/A'}",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: isDark ? Colors.white70 : Colors.grey[700],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "Fin: ${session['endDate'] ?? 'N/A'}",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: isDark ? Colors.white70 : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                avatar: Icon(Icons.people, size: 16, color: Colors.white),
                                label: Text(
                                  "Capacité: ${session['capacity'] ?? 'N/A'}",
                                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
                                ),
                                backgroundColor: const Color(0xFF4C0680),
                              ),
                              Chip(
                                avatar: Icon(Icons.attach_money, size: 16, color: Colors.white),
                                label: Text(
                                  "Prix: ${session['price'] ?? 'N/A'} ${session['currency'] ?? ''}",
                                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
                                ),
                                backgroundColor: const Color(0xFF0526EF),
                              ),
                              if (session['paymentMethode'] != null)
                                Chip(
                                  avatar: Icon(Icons.payment, size: 16, color: Colors.white),
                                  label: Text(
                                    session['paymentMethode'],
                                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
                                  ),
                                  backgroundColor: const Color(0xFF482669),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
