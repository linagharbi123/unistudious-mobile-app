import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;

import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';

import 'package:intl/intl.dart';

import 'dart:convert';

import 'dart:developer' as developer;

import 'package:flutter_svg/flutter_svg.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../providers/auth_provider.dart';
import '../providers/loading_provider.dart';
import '../utils/snackbar_helper.dart';


import '../widgets/loading_wrapper.dart';

import '../widgets/sidebar.dart';
import '../widgets/notification_icon_button.dart';

import '../screens/groupes_page.dart';

import 'dart:async';
import 'dart:io';
import '../utils/connection_checker.dart';

class MessageriePage extends StatefulWidget {

  const MessageriePage({super.key});

  @override

  _MessageriePageState createState() => _MessageriePageState();

}

String _formatConversationTime(String? isoTimestamp) {

  // Si timestamp est null, vide ou invalide → on ne retourne RIEN

  if (isoTimestamp == null || isoTimestamp.trim().isEmpty) {

    return '';

  }

  try {

    final DateTime utcTime = DateTime.parse(isoTimestamp).toUtc();

    final DateTime localTime = utcTime.toLocal(); // Gère automatiquement +1h/+2h

    return DateFormat('dd/MM/yyyy HH:mm').format(localTime);

  } catch (e) {

    // En cas d'erreur de parsing → on cache l'heure (pas de "date d'aujourd'hui" forcée)

    return '';

  }

}

class _MessageriePageState extends State<MessageriePage>

    with SingleTickerProviderStateMixin {

  final TextEditingController _searchController = TextEditingController();

  final FocusNode _searchFocusNode = FocusNode();

  late TabController _tabController;

  // Permet de contrôler la page Groupes depuis la barre de recherche
  // (non typé pour éviter de dépendre d'une classe d'état privée)
  final GlobalKey _groupesPageKey = GlobalKey();

  List<Map<String, dynamic>> conversations = [];

  List<Map<String, dynamic>> filteredConversations = [];

  List<Map<String, dynamic>> activeContacts = [];

  List<Map<String, dynamic>> searchResults = [];

  bool isSearching = false;

  String? currentUser;

  // Cache des statuts réels (username → status)

  final Map<String, String> _userStatusMap = {};

  // Cache des avatars PNG convertis (username → URL PNG)

  final Map<String, String> _avatarPngCache = {};

  // Cache des avatars SVG parsés (username → Map avec color et initial)

  final Map<String, Map<String, dynamic>> _avatarSvgCache = {};

  // Cache des futures pour éviter de recharger les SVG à chaque rebuild
  final Map<String, Future<Map<String, dynamic>>> _avatarFutures = {};

  bool isConnectionError = false;

  Timer? _connectionCheckTimer;
  
  Timer? _refreshTimer; // Timer pour rafraîchir périodiquement la liste

  @override

  void initState() {

    super.initState();

    developer.log('Initializing MessageriePage', name: 'MessageriePage');

    _tabController = TabController(length: 2, vsync: this);
    // Éviter que la barre de recherche soit automatiquement focusée
    // quand on change d'onglet (Chat Privé / Groupes)
    _tabController.addListener(() {
      if (!mounted) return;
      if (_tabController.indexIsChanging) {
        _searchFocusNode.unfocus();
        FocusScope.of(context).unfocus();
      }
    });

    _searchController.addListener(_filterConversations);

    _startConnectionMonitoring();

    WidgetsBinding.instance.addPostFrameCallback((_) {

      if (mounted) {

        _checkAuthAndFetchData();

        // Démarrer le polling pour les mises à jour en temps réel (sans WebSocket)
        _startRefreshTimer();

      }

    });

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
            final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);
            loadingProvider.showLoading();
            _checkAuthAndFetchData();
          }
        });
      }
    });
  }



  @override

  void dispose() {

    _searchController.removeListener(_filterConversations);

    _searchController.dispose();

    _tabController.dispose();

    _connectionCheckTimer?.cancel();
    
    _refreshTimer?.cancel();

    developer.log('Disposing MessageriePage', name: 'MessageriePage');

    _searchFocusNode.dispose();

    super.dispose();

  }
  
  /// Démarre un timer pour rafraîchir périodiquement la liste des conversations
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    developer.log('🔄 Démarrage du polling pour les mises à jour en temps réel (toutes les 2 secondes)', name: 'MessageriePage');
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        developer.log('⏹️ Arrêt du polling (widget non monté)', name: 'MessageriePage');
        return;
      }
      // Rafraîchir silencieusement la liste des conversations pour s'assurer que les mises à jour sont visibles
      developer.log('🔄 Polling: Rafraîchissement de la liste des conversations...', name: 'MessageriePage');
      fetchConversations().then((_) {
        developer.log('✅ Polling: Liste des conversations rafraîchie (${conversations.length} conversations)', name: 'MessageriePage');
      }).catchError((error) {
        developer.log('❌ Polling: Erreur lors du rafraîchissement: $error', name: 'MessageriePage');
      });
    });
  }

  Future<void> _checkAuthAndFetchData() async {

    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);

    if (!authProvider.isLoggedIn) {

      WidgetsBinding.instance.addPostFrameCallback((_) {

        if (mounted) {

          SnackBarHelper.showWarning(context, 'Veuillez vous connecter pour continuer.');

          Navigator.pushReplacementNamed(context, '/login');

        }

      });

      return;

    }

    loadingProvider.showLoading();

    try {

      await Future.wait([

        fetchCurrentUser(),

        fetchConversations(),

        fetchActiveContacts(),

      ]);

      _updateActiveContactsWithRealStatus();

    } catch (e, s) {
      developer.log('Error during data fetch: $e', error: e, stackTrace: s);

      // Détecter les erreurs de connexion
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
          }
        });
      }
    } finally {

      if (mounted) loadingProvider.hideLoading();

    }

  }

  // --------------------------------------------------------------------

  // 1. Récupération de l'utilisateur courant

  // --------------------------------------------------------------------

  Future<void> fetchCurrentUser() async {

    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    const endpoint = '/api/chat-message';

    try {

      final response = await authProvider

          .authenticatedRequest('GET', endpoint)

          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      final data = jsonDecode(response.body);

      final user = data['currentUser']?.toString();

      setState(() => currentUser = user);

    } catch (e, s) {

      developer.log('fetchCurrentUser error: $e', error: e, stackTrace: s);

    }

  }

  // --------------------------------------------------------------------

  // 2. Liste des conversations + statuts réels

  // --------------------------------------------------------------------

  Future<void> fetchConversations() async {

    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    const endpoint = '/api/chat/list-users';

    try {

      final response = await authProvider

          .authenticatedRequest('GET', endpoint)

          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      final List<dynamic> data = jsonDecode(response.body);

      developer.log(

        '📥 fetchConversations: reçu ${data.length} utilisateurs depuis /api/chat/list-users (currentUser=$currentUser)',

        name: 'MessageriePage',

      );

      // Stocker l'ancien état pour détecter les changements
      final oldConversations = Map<String, Map<String, dynamic>>.fromEntries(
        conversations.map((c) => MapEntry(c['room_id']?.toString() ?? '', c))
      );
      
      final List<Map<String, dynamic>> users = data.map((user) {

        final date = DateTime.tryParse(user['last_date'] ?? '') ?? DateTime.now();

        final username = user['username']?.toString() ?? '';

        final status = user['status']?.toString() ?? 'offline';
        
        final roomId = user['room_id']?.toString() ?? '';
        final lastMessage = user['last_message']?.toString() ?? '';
        final lastDate = user['last_date']?.toString() ?? '';

        if (username.isNotEmpty) {

          _userStatusMap[username] = status;

        }
        
        // Détecter si c'est un nouveau message (comparer avec l'ancien état)
        final oldConversation = oldConversations[roomId];
        final oldLastDate = oldConversation?['last_date']?.toString() ?? '';
        final oldLastMessage = oldConversation?['message']?.toString() ?? '';
        final isNewMessage = oldConversation != null && 
                            (oldLastDate != lastDate || oldLastMessage != lastMessage);
        final wasUnread = oldConversation?['unread'] == true;
        
        // Marquer comme non lu si :
        // 1. C'est un nouveau message ET l'auteur n'est pas l'utilisateur actuel
        // 2. OU c'était déjà marqué comme non lu
        final shouldBeUnread = (isNewMessage && username != currentUser) || wasUnread;
        
        if (isNewMessage) {
          developer.log(
            '📨 Nouveau message détecté pour roomId=$roomId, username=$username (currentUser=$currentUser), lastMessage=${lastMessage.length > 30 ? "${lastMessage.substring(0, 30)}..." : lastMessage}, oldDate=$oldLastDate, newDate=$lastDate, unread=$shouldBeUnread',
            name: 'MessageriePage',
          );
        }

        return {

          'id': user['id']?.toString() ?? '',

          'username': username,

          'name': user['name']?.toString() ?? 'Sans nom',

          // D'après les logs, /api/chat/list-users renvoie l'URL dans "avatar_url"

          // (ex: https://message.unistudious.com/avatar/<username>).

          'avatar_url': user['avatar_url']?.toString() ?? '',

          'status': status,

          'message': lastMessage,

          'time': _formatConversationTime(lastDate),

          'last_date': lastDate,

          'room_id': roomId,

          'type': 'private',

          'unread': shouldBeUnread,

        };

      }).toList();

      // Trier les conversations par last_date (plus récent en premier)

      _sortConversationsByLastDate(users);
      
      final unreadCount = users.where((u) => u['unread'] == true).length;
      developer.log(
        '✅ fetchConversations terminé: ${users.length} conversations, $unreadCount non lues',
        name: 'MessageriePage',
      );

      setState(() {

        conversations = users;

        filteredConversations = List.from(conversations);

      });

    } catch (e, s) {

      developer.log('fetchConversations error: $e', error: e, stackTrace: s);

      // Détecter les erreurs de connexion
      final isNetworkError = e is SocketException || 
                             e is TimeoutException ||
                             e.toString().contains('SocketException') ||
                             e.toString().contains('Failed host lookup') ||
                             e.toString().contains('Network is unreachable') ||
                             e.toString().contains('Connection refused') ||
                             e.toString().contains('Connection timed out') ||
                             e.toString().contains('No Internet connection') ||
                             e.toString().contains('ClientException') ||
                             e.toString().contains('OS Error') ||
                             e.toString().contains('nodename nor servname');

      if (mounted) {
        setState(() {
          if (isNetworkError) {
            isConnectionError = true;
          }
        });
        // Erreur silencieuse
      }

    }

  }

  // --------------------------------------------------------------------

  // 3. Contacts les plus actifs + conversion SVG → PNG

  // --------------------------------------------------------------------

  Future<void> fetchActiveContacts() async {

    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    const endpoint = '/api/chat/most_active_users';

    try {

      final dummyGet = await authProvider.authenticatedRequest('GET', endpoint);

      final fullUrl = dummyGet.request!.url.toString();

      final request = http.MultipartRequest('POST', Uri.parse(fullUrl));

      final token = authProvider.token;

      if (token != null && token.isNotEmpty) {

        request.headers['Authorization'] = 'Bearer $token';

      }

      request.headers['Accept'] = 'application/json';

      request.fields['length'] = '9';

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));

      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      final List<dynamic> data = jsonDecode(response.body);

      final List<Map<String, dynamic>> contacts = [];

      // Créer un map des contacts existants par username pour préserver les avatars

      final Map<String, Map<String, dynamic>> existingContactsByUsername = {};

      for (var contact in activeContacts) {

        final username = contact['username']?.toString() ?? '';

        if (username.isNotEmpty) {

          existingContactsByUsername[username] = contact;

        }

      }

      developer.log('Most active users raw response: $data', name: 'MessageriePage');

      for (var item in data) {

        final username = item['username']?.toString() ?? 'Inconnu';

        final rawAvatarUrl = item['avatar']?.toString();

        developer.log('Processing active user: $username | avatar: $rawAvatarUrl', name: 'MessageriePage');

        String finalAvatarUrl = '';

        // Vérifier si le contact existe déjà avec un avatar chargé

        final existingContact = existingContactsByUsername[username];

        if (existingContact != null &&

            existingContact['avatar_url'] != null &&

            existingContact['avatar_url'].toString().isNotEmpty) {

          // Préserver l'avatar existant pour éviter le rechargement

          finalAvatarUrl = existingContact['avatar_url'].toString();

          developer.log('→ Preserving existing avatar for $username', name: 'MessageriePage');

        } else if (rawAvatarUrl != null && rawAvatarUrl.isNotEmpty) {

          // Certains avatars reviennent sous la forme

          // https://message.unistudious.com/avatar/<username>

          // sans extension, mais en réalité ce sont des SVG côté serveur.

          final bool isLikelySvg =

              rawAvatarUrl.endsWith('.svg') ||

                  rawAvatarUrl.contains('message.unistudious.com/avatar/');

          if (isLikelySvg) {

            // Si l'avatar SVG est déjà dans le cache, utiliser l'URL originale

            // Le widget _ActiveContactsList gérera le cache

            if (_avatarSvgCache.containsKey(username)) {

              developer.log('→ SVG avatar already cached for $username, using original URL', name: 'MessageriePage');

              finalAvatarUrl = rawAvatarUrl;

            } else {

              developer.log('→ Likely SVG (or avatar endpoint) for $username, will be cached by widget', name: 'MessageriePage');

              finalAvatarUrl = rawAvatarUrl;

            }

          } else {

            developer.log('→ Already PNG/JPG, using directly: $rawAvatarUrl', name: 'MessageriePage');

            finalAvatarUrl = rawAvatarUrl;

          }

        } else {

          developer.log('→ No avatar for $username', name: 'MessageriePage');

        }

        contacts.add({

          'id': item['roomId']?.toString() ?? '',

          'username': username,

          'name': username,

          'avatar_url': finalAvatarUrl,

          'count': (item['count'] as num?)?.toInt() ?? 0,

          'status': existingContact?['status'] ?? 'unknown',

        });

      }

      setState(() {

        activeContacts = contacts;

      });

      developer.log('Active contacts loaded: ${activeContacts.length}', name: 'MessageriePage');

    } catch (e, s) {

      developer.log('fetchActiveContacts error: $e', error: e, stackTrace: s, name: 'MessageriePage');

      // Détecter les erreurs de connexion
      final isNetworkError = e is SocketException || 
                             e is TimeoutException ||
                             e.toString().contains('SocketException') ||
                             e.toString().contains('Failed host lookup') ||
                             e.toString().contains('Network is unreachable') ||
                             e.toString().contains('Connection refused') ||
                             e.toString().contains('Connection timed out') ||
                             e.toString().contains('No Internet connection') ||
                             e.toString().contains('ClientException') ||
                             e.toString().contains('OS Error') ||
                             e.toString().contains('nodename nor servname');

      if (mounted) {
        setState(() {
          activeContacts = [];
          if (isNetworkError) {
            isConnectionError = true;
          }
        });
      }

    }

  }

  Future<String> _convertSvgToPng(String svgUrl, String username) async {

    developer.log(

      'convertSvgToPng stub: returning original SVG URL for $username -> $svgUrl',

      name: 'MessageriePage',

    );

    return svgUrl;

  }

  Future<String?> _fetchAndSanitizeSvg(String url, String username) async {

    try {

      final response = await http

          .get(Uri.parse(url))

          .timeout(const Duration(seconds: 15));

      developer.log(

        'fetchAndSanitizeSvg for $username: ${response.statusCode} | ${response.headers['content-type']}',

        name: 'MessageriePage',

      );

      if (response.statusCode != 200) return null;

      final contentType = response.headers['content-type'] ?? '';

      if (!contentType.contains('image/svg')) {

        // Pas un SVG : on ne traite pas ici

        return null;

      }

      var svg = response.body;

      double? vbWidth;

      double? vbHeight;

      final viewBoxMatch = RegExp(r'viewBox="\s*([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*"')

          .firstMatch(svg);

      if (viewBoxMatch != null && viewBoxMatch.groupCount == 4) {

        try {

          vbWidth = double.parse(viewBoxMatch.group(3)!);

          vbHeight = double.parse(viewBoxMatch.group(4)!);

        } catch (_) {

          vbWidth = null;

          vbHeight = null;

        }

      }

      // Remplacer width/height en pourcentage par des valeurs numériques basées sur le viewBox

      // ex: viewBox 0 0 200 200 + width="100%" -> width="200"

      if (vbWidth != null || vbHeight != null) {

        svg = svg.replaceAllMapped(

          RegExp(r'(width|height)="([\d.]+)%"'),

              (m) {

            final attr = m.group(1);

            final percentStr = m.group(2);

            if (attr == null || percentStr == null) return m.group(0) ?? '';

            final p = double.tryParse(percentStr);

            if (p == null) return m.group(0) ?? '';

            if (attr == 'width' && vbWidth != null) {

              final v = vbWidth * p / 100.0;

              return 'width="$v"';

            }

            if (attr == 'height' && vbHeight != null) {

              final v = vbHeight * p / 100.0;

              return 'height="$v"';

            }

            return m.group(0) ?? '';

          },

        );

      }

      developer.log(

        'Sanitized SVG for $username (length: ${svg.length})',

        name: 'MessageriePage',

      );

      return svg;

    } catch (e, s) {

      developer.log(

        'fetchAndSanitizeSvg FAILED for $username: $e',

        error: e,

        stackTrace: s,

        name: 'MessageriePage',

      );

      return null;

    }

  }

  Map<String, dynamic> _extractAvatarStyleFromSvg(String svg) {

    // Couleur de fond : on cherche le premier <rect ... fill="...">

    final rectMatch =

    RegExp(r'<rect[^>]*fill="([^"]+)"', caseSensitive: false).firstMatch(svg);

    final bgFill = rectMatch?.group(1) ?? '#6200EE';

    // Texte (initiale) : contenu du premier <text>...</text>

    final textMatch =

    RegExp(r'<text[^>]*>([^<]+)</text>', caseSensitive: false).firstMatch(svg);

    final rawText = (textMatch?.group(1) ?? '').trim();

    final initial = rawText.isNotEmpty ? rawText[0].toUpperCase() : '?';

    return {

      'color': _colorFromHex(bgFill),

      'initial': initial,

    };

  }

  Color _colorFromHex(String hex) {

    var value = hex.replaceAll('#', '').trim();

    if (value.length == 6) {

      value = 'FF$value';

    }

    if (value.length != 8) {

      return const Color(0xFF6200EE);

    }

    return Color(int.parse(value, radix: 16));

  }

  void _updateActiveContactsWithRealStatus() {

    if (!mounted) return;

    setState(() {

      for (var contact in activeContacts) {

        final username = contact['username'] as String?;

        if (username != null && _userStatusMap.containsKey(username)) {

          contact['status'] = _userStatusMap[username];

        } else {

          contact['status'] = 'offline';

        }

      }

    });

  }

  Future<void> fetchUsers() async {

    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    const endpoint = '/api/chat/fetch-users';

    try {

      final response = await authProvider

          .authenticatedRequest('GET', endpoint)

          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      final data = jsonDecode(response.body);

      if (data['success'] == true && data['users'] != null) {

        final List<dynamic> usersData = data['users'];

        final List<Map<String, dynamic>> users = usersData.map((user) {

          return {

            'id': user['id']?.toString() ?? '',

            'username': user['username']?.toString() ?? '',

            'name': user['name']?.toString() ?? 'Sans nom',

            'avatar': user['avatar']?.toString() ?? '',

            'room_id': user['room_id']?.toString() ?? '',

          };

        }).toList();

        if (mounted) {

          setState(() {

            searchResults = users;

            isSearching = true;

          });

        }

      }

    } catch (e, s) {

      developer.log('fetchUsers error: $e', error: e, stackTrace: s);

      if (mounted) {

        setState(() {

          searchResults = [];

          isSearching = false;

        });

      }

    }

  }

  // Fonction helper pour trier les conversations par last_date (plus récent en premier)

  void _sortConversationsByLastDate(List<Map<String, dynamic>> conversationsList) {

    conversationsList.sort((a, b) {

      final aDate = DateTime.tryParse(a['last_date'] ?? '') ?? DateTime(1970);

      final bDate = DateTime.tryParse(b['last_date'] ?? '') ?? DateTime(1970);

      return bDate.compareTo(aDate);

    });

  }

  void _filterConversations() {

    if (!mounted) return;

    final query = _searchController.text.trim();

    // Propager la recherche vers l'onglet "Groupes" (appel dynamique)
    final groupesState = _groupesPageKey.currentState;
    if (groupesState != null) {
      (groupesState as dynamic).applySearch(query);
    }

    if (query.isEmpty) {

      setState(() {

        // S'assurer que les conversations sont triées par last_date (plus récent en premier)

        final sortedConversations = List<Map<String, dynamic>>.from(conversations);

        _sortConversationsByLastDate(sortedConversations);

        filteredConversations = sortedConversations;

        searchResults = [];

        isSearching = false;

      });

      return;

    }

    if (isSearching && searchResults.isNotEmpty) {

      setState(() {

        searchResults = searchResults.where((user) {

          final name = (user['name']?.toString() ?? '').toLowerCase();

          final username = (user['username']?.toString() ?? '').toLowerCase();

          final queryLower = query.toLowerCase();

          return name.contains(queryLower) || username.contains(queryLower);

        }).toList();

      });

      return;

    }

    fetchUsers();

  }

  int getUnreadCount(String type) =>

      filteredConversations.where((c) => c['type'] == type && c['unread'] == true).length;

  List<Map<String, dynamic>> getFilteredConversations(String type) =>

      filteredConversations.where((c) => c['type'] == type).toList();

  @override

  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    return LoadingWrapper(

      child: GestureDetector(

        behavior: HitTestBehavior.translucent,

        onTap: () {

          FocusScope.of(context).unfocus();

        },

        child: Scaffold(

          backgroundColor: theme.scaffoldBackgroundColor,

          drawer: const AppSidebar(),

          appBar: AppBar(

            leading: Builder(

              builder: (ctx) => IconButton(

                icon: Icon(Icons.menu,

                    color: theme.appBarTheme.iconTheme?.color ?? Colors.white),

                onPressed: () => Scaffold.of(ctx).openDrawer(),

              ),

            ),
            title: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text('Messagerie',

                style: GoogleFonts.poppins(

                    color: theme.appBarTheme.foregroundColor ?? Colors.white,

                    fontWeight: FontWeight.w400,
                ),
                  ),
              ],
            ),

            backgroundColor: Colors.transparent,

            elevation: 0,

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

            actions: [
              const NotificationIconButton(),
            ],

            bottom: TabBar(

              controller: _tabController,

              tabs: [

                Tab(text: 'Chat Privé', icon: const Icon(Icons.person)),

                Tab(text: 'Groupes', icon: const Icon(Icons.group)),

              ],

              labelColor: Colors.white,

              unselectedLabelColor: Colors.white70,

              indicatorColor: Colors.white,

            ),

          ),

          body: Consumer<LoadingProvider>(
            builder: (context, loadingProvider, child) {
              if (loadingProvider.isLoading) {
                return const SizedBox.shrink();
              }
              if (isConnectionError) {
                return Center(
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
                          final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);
                          loadingProvider.showLoading();
                          _checkAuthAndFetchData();
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
                );
              }
              return NestedScrollView(

            physics: const AlwaysScrollableScrollPhysics(),

            headerSliverBuilder: (_, __) => [

              SliverToBoxAdapter(

                child: Column(

                  children: [

                    // Search bar

                    Padding(

                      padding: const EdgeInsets.all(12.0),

                      child: ValueListenableBuilder<TextEditingValue>(

                        valueListenable: _searchController,

                        builder: (context, value, child) {

                          return TextField(

                            controller: _searchController,

                            focusNode: _searchFocusNode,

                            decoration: InputDecoration(

                              hintText: 'Rechercher...',

                              prefixIcon: Icon(Icons.search,

                                  color: isDark ? Colors.white70 : Colors.grey[600]),

                              suffixIcon: value.text.isNotEmpty

                                  ? IconButton(

                                icon: Icon(Icons.clear,

                                    color: isDark ? Colors.white70 : Colors.grey[600]),

                                onPressed: () {

                                  _searchController.clear();

                                  _filterConversations();

                                },

                              )

                                  : null,

                              filled: true,

                              fillColor: isDark ? Colors.grey[800] : Colors.grey[200],

                              border: OutlineInputBorder(

                                borderRadius: BorderRadius.circular(12),

                                borderSide: BorderSide.none,

                              ),

                            ),

                            style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black87),

                            onChanged: (_) => _filterConversations(),

                          );

                        },

                        child: const SizedBox.shrink(), // Widget enfant qui ne sera jamais reconstruit

                      ),

                    ),

                    if (activeContacts.isNotEmpty)

                      _ActiveContactsList(

                        key: const ValueKey('active_contacts_list'),

                        contacts: activeContacts,

                        isDark: isDark,

                        avatarSvgCache: _avatarSvgCache,

                        onContactTap: (contact) async {
                          // Marquer la conversation comme lue avant d'ouvrir le chat
                          final roomId = contact['id']?.toString();
                          if (roomId != null) {
                            setState(() {
                              final conversationIndex = conversations.indexWhere(
                                (conv) => conv['room_id']?.toString() == roomId,
                              );
                              if (conversationIndex >= 0 && conversations[conversationIndex]['unread'] == true) {
                                conversations[conversationIndex]['unread'] = false;
                                filteredConversations = List.from(conversations);
                              }
                            });
                          }
                          
                          await Navigator.pushNamed(
                          context,
                          '/chat',
                          arguments: {
                            'room_id': contact['id'],
                            'name': contact['name'],
                            'avatar_url': contact['avatar_url'],
                            },
                          );

                          // Rafraîchir la liste après le retour
                          if (mounted) {
                            fetchConversations();
                          }
                          },

                      ),

                  ],

                ),

              ),

            ],

            body: RefreshIndicator(

              onRefresh: _checkAuthAndFetchData,

              child: ConstrainedBox(

                constraints: BoxConstraints(

                  minHeight: MediaQuery.of(context).size.height - kToolbarHeight - 100,

                ),

                child: TabBarView(

                  controller: _tabController,

                  children: [

                    _buildConversationList('private'),

                    GroupesPage(key: _groupesPageKey),

                  ],

                ),

              ),

            ),

              );
            },
          ),

        ),

      ),

    );

  }

  Widget _buildConversationList(String type) {

    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    // Si on est en mode recherche, afficher les résultats de recherche

    if (isSearching && type == 'private') {

      return _buildSearchResults(isDark, theme);

    }

    final convos = getFilteredConversations(type);

    if (convos.isEmpty) {

      return SingleChildScrollView(

        physics: const AlwaysScrollableScrollPhysics(),

        child: ConstrainedBox(

          constraints: BoxConstraints(

            minHeight: MediaQuery.of(context).size.height - kToolbarHeight - 200,

          ),

          child: Center(

            child: Text(

              type == 'private' ? 'Aucun message privé' : 'Aucun groupe',

              style: GoogleFonts.poppins(

                color: isDark ? Colors.white70 : Colors.grey[600],

                fontSize: 16,

              ),

            ),

          ),

        ),

      );

    }

    return ListView.builder(

      physics: const NeverScrollableScrollPhysics(),

      shrinkWrap: true,

      itemCount: convos.length,

      itemBuilder: (_, i) {

        final c = convos[i];

        return Card(

          key: ValueKey(c['id']),

          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),

          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

          color: isDark ? theme.cardColor : Colors.white,

          elevation: isDark ? 0 : 2,

          child: ListTile(

            onTap: () async {
              // Marquer la conversation comme lue avant d'ouvrir le chat
              final roomId = c['room_id']?.toString();
              if (roomId != null && c['unread'] == true) {
                setState(() {
                  final conversationIndex = conversations.indexWhere(
                    (conv) => conv['room_id']?.toString() == roomId,
                  );
                  if (conversationIndex >= 0) {
                    conversations[conversationIndex]['unread'] = false;
                    filteredConversations = List.from(conversations);
                  }
                });
              }
              
              // Ouvrir le chat et attendre le retour
              await Navigator.pushNamed(
              context,
              '/chat',
              arguments: {
                'room_id': c['room_id'],
                'name': c['name'],
                'avatar_url': c['avatar_url'],
                },
              );

              // Rafraîchir la liste après le retour pour s'assurer que tout est à jour
              if (mounted) {
                fetchConversations();
              }
              },

            leading: Stack(

              children: [

                CircleAvatar(

                  radius: 24,

                  backgroundColor: c['unread']

                      ? Colors.deepPurple

                      : (isDark ? Colors.grey[700] : Colors.grey[300]),

                  child: () {

                    final avatarUrl = c['avatar_url']?.toString() ?? '';

                    final username = c['username']?.toString() ?? 'inconnu';

                    developer.log(

                      'Conversation avatar: user=$username | avatar_url="$avatarUrl"',

                      name: 'MessageriePage',

                    );

                    // Même logique que pour les avatars de /api/chat/most_active_users

                    if (avatarUrl.isEmpty) {

                      developer.log(

                        'Conversation avatar: AUCUNE URL pour $username, fallback icône.',

                        name: 'MessageriePage',

                      );

                      return Icon(

                        c['type'] == 'private' ? Icons.person : Icons.group,

                        color: Colors.white,

                      );

                    }

                    if (avatarUrl.startsWith('data:image/png;base64,')) {

                      developer.log(

                        'Conversation avatar: avatar base64 pour $username',

                        name: 'MessageriePage',

                      );

                      try {

                        final bytes = base64Decode(avatarUrl.split(',').last);

                        return ClipOval(

                          child: Image.memory(

                            bytes,

                            fit: BoxFit.cover,

                            width: 48,

                            height: 48,

                          ),

                        );

                      } catch (e, s) {

                        developer.log(

                          'Conversation avatar: erreur décodage base64 pour $username -> $e',

                          error: e,

                          stackTrace: s,

                          name: 'MessageriePage',

                        );

                        return Icon(

                          c['type'] == 'private' ? Icons.person : Icons.group,

                          color: Colors.white,

                        );

                      }

                    }

                    final isSvg = avatarUrl.endsWith('.svg') ||

                        avatarUrl.contains('message.unistudious.com/avatar/');

                    if (isSvg) {

                      // Utiliser le cache directement si disponible
                      final cacheKey = username.isNotEmpty ? username : avatarUrl;
                      if (_avatarSvgCache.containsKey(cacheKey)) {
                        final cached = _avatarSvgCache[cacheKey]!;
                        return CircleAvatar(

                          backgroundColor: cached['color'] as Color,

                          child: Text(

                            cached['initial'] as String,

                            style: const TextStyle(

                              fontSize: 22,

                              fontWeight: FontWeight.bold,

                              color: Colors.white,

                            ),

                          ),

                        );
                      }
                      
                      // Si pas dans le cache, utiliser le future cache pour éviter les rechargements
                      if (!_avatarFutures.containsKey(cacheKey)) {
                        _avatarFutures[cacheKey] = _loadAndCacheSvg(avatarUrl, cacheKey);
                      }
                      
                      return FutureBuilder<Map<String, dynamic>>(

                        future: _avatarFutures[cacheKey],

                        builder: (context, snapshot) {

                          if (snapshot.connectionState == ConnectionState.waiting) {

                            // Ne pas afficher de loader, juste un placeholder discret
                            return Container(

                              width: 48,

                              height: 48,

                              color: isDark ? Colors.grey[800] : Colors.grey[300],

                            );

                          }

                          if (snapshot.hasError || !snapshot.hasData) {

                            return Icon(

                              c['type'] == 'private' ? Icons.person : Icons.group,

                              color: Colors.white,

                            );

                          }

                          final avatarStyle = snapshot.data!;

                          final bgColor = avatarStyle['color'] as Color;

                          final initial = avatarStyle['initial'] as String;

                          return CircleAvatar(

                            backgroundColor: bgColor,

                            child: Text(

                              initial,

                              style: const TextStyle(

                                fontSize: 22,

                                fontWeight: FontWeight.bold,

                                color: Colors.white,

                              ),

                            ),

                          );

                        },

                      );

                    }

                    developer.log(

                      'Conversation avatar: image réseau classique pour $username -> $avatarUrl',

                      name: 'MessageriePage',

                    );

                    // PNG/JPG classique - Utiliser CachedNetworkImage avec cache agressif
                    return ClipOval(

                      child: CachedNetworkImage(

                        imageUrl: avatarUrl,

                        fit: BoxFit.cover,

                        width: 48,

                        height: 48,

                        memCacheWidth: 96, // Optimisation mémoire

                        memCacheHeight: 96,

                        maxWidthDiskCache: 200, // Cache disque plus large

                        maxHeightDiskCache: 200,

                        cacheKey: avatarUrl, // Utiliser l'URL comme clé de cache

                        useOldImageOnUrlChange: true, // Garder l'ancienne image si l'URL change

                        fadeInDuration: const Duration(milliseconds: 0), // Pas d'animation de fade-in

                        fadeOutDuration: const Duration(milliseconds: 0), // Pas d'animation de fade-out

                        placeholder: (context, url) => Container(

                          width: 48,

                          height: 48,

                          color: isDark ? Colors.grey[800] : Colors.grey[300],

                          // Ne pas afficher de loader, juste un placeholder discret

                        ),

                        errorWidget: (context, url, error) {

                          developer.log(

                            'Conversation avatar: ERREUR CachedNetworkImage pour $username -> $avatarUrl',

                            name: 'MessageriePage',

                          );

                          return Icon(

                            c['type'] == 'private' ? Icons.person : Icons.group,

                            color: Colors.white,

                          );

                        },

                      ),

                    );

                  }(),

                ),

                if (c['status'] == 'online')

                  Positioned(

                    right: 0,

                    bottom: 0,

                    child: Container(

                      width: 12,

                      height: 12,

                      decoration: BoxDecoration(

                        color: Colors.green,

                        shape: BoxShape.circle,

                        border: Border.all(

                          color: isDark ? Colors.grey[800]! : Colors.white,

                          width: 2,

                        ),

                      ),

                    ),

                  ),

              ],

            ),

            title: Text(

              c['name'] ?? 'Sans nom',

              style: GoogleFonts.poppins(

                fontWeight: c['unread'] ? FontWeight.bold : FontWeight.normal,

                color: isDark ? Colors.white : Colors.black87,

                fontSize: 16,

              ),

            ),

            subtitle: Text(

              c['message'] ?? 'Aucun message',

              style: GoogleFonts.poppins(

                fontWeight: c['unread'] == true ? FontWeight.bold : FontWeight.normal,

                color: isDark ? Colors.white70 : Colors.grey[600],

                fontSize: 14,

              ),

              overflow: TextOverflow.ellipsis,

            ),

            trailing: Text(

              c['time'] ?? '',

              style: GoogleFonts.poppins(

                color: isDark ? Colors.white70 : Colors.grey[500],

                fontSize: 12,

              ),

            ),

          ),

        );

      },

    );

  }

  // --------------------------------------------------------------------

  // Affichage des résultats de recherche

  // --------------------------------------------------------------------

  Widget _buildSearchResults(bool isDark, ThemeData theme) {

    if (searchResults.isEmpty) {

      return SingleChildScrollView(

        physics: const AlwaysScrollableScrollPhysics(),

        child: ConstrainedBox(

          constraints: BoxConstraints(

            minHeight: MediaQuery.of(context).size.height - kToolbarHeight - 200,

          ),

          child: Center(

            child: Text(

              'Aucun résultat trouvé',

              style: GoogleFonts.poppins(

                color: isDark ? Colors.white70 : Colors.grey[600],

                fontSize: 16,

              ),

            ),

          ),

        ),

      );

    }

    return ListView.builder(

      physics: const NeverScrollableScrollPhysics(),

      shrinkWrap: true,

      itemCount: searchResults.length,

      itemBuilder: (_, i) {

        final user = searchResults[i];

        return Card(

          key: ValueKey(user['id']),

          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),

          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

          color: isDark ? theme.cardColor : Colors.white,

          elevation: isDark ? 0 : 2,

          child: ListTile(

            onTap: () => _onSearchResultTap(user),

            leading: CircleAvatar(

              radius: 24,

              backgroundColor: isDark ? Colors.grey[700] : Colors.grey[300],

              backgroundImage: user['avatar']?.toString().isNotEmpty == true

                  ? NetworkImage(user['avatar']?.toString() ?? '')

                  : null,

              child: user['avatar']?.toString().isEmpty == true

                  ? Icon(Icons.person, color: Colors.white)

                  : null,

            ),

            title: Text(

              user['name'] ?? 'Sans nom',

              style: GoogleFonts.poppins(

                fontWeight: FontWeight.w600,

                color: isDark ? Colors.white : Colors.black87,

              ),

            ),

            subtitle: Text(

              user['username'] ?? '',

              style: GoogleFonts.poppins(

                color: isDark ? Colors.white70 : Colors.grey[600],

                fontSize: 12,

              ),

            ),

            trailing: user['room_id']?.toString().isEmpty == true

                ? Icon(Icons.add_circle_outline, color: isDark ? Colors.white70 : Colors.grey[600])

                : Icon(Icons.chat_bubble_outline, color: isDark ? Colors.white70 : Colors.grey[600]),

          ),

        );

      },

    );

  }

  Future<void> _onSearchResultTap(Map<String, dynamic> user) async {

    if (!mounted) return;

    final String name = user['name']?.toString() ?? 'Sans nom';

    final String avatar = user['avatar']?.toString() ?? '';

    String roomId = user['room_id']?.toString() ?? '';

    // 1) S'il y a déjà une room, on ouvre directement le chat

    if (roomId.isNotEmpty) {

      // Vider la barre de recherche et revenir à l'état normal

      setState(() {

        _searchController.clear();

        isSearching = false;

        searchResults = [];

        filteredConversations = List.from(conversations);

      });

      // Forcer l'unfocus pour que le curseur disparaisse quand on revient

      _searchFocusNode.unfocus();

      Navigator.pushNamed(

        context,

        '/chat',

        arguments: {

          'room_id': roomId,

          'name': name,

          'avatar_url': avatar,

        },

      );

      return;

    }

    // 2) Aucune room : on la crée via /api/chat/create-room

    final String username = user['username']?.toString() ?? '';

    if (username.isEmpty) {

      SnackBarHelper.showError(context, 'Utilisateur invalide pour la création de la conversation.');

      return;

    }

    try {

      final uri = Uri.parse('https://www.unistudious.com/api/chat/create-room');

      final request = http.MultipartRequest('POST', uri)

        ..fields['username'] = username;

      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token') ?? '';

      request.headers['Authorization'] = 'Bearer $token';

      final streamedResponse =

      await request.send().timeout(const Duration(seconds: 30));

      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {

        final data = jsonDecode(response.body);

        if (data['success'] == true && data['room'] != null) {

          final room = data['room'] as Map<String, dynamic>;

          roomId = (room['_id'] ?? room['rid'] ?? '').toString();

          // Mise à jour locale de l'utilisateur pour refléter la nouvelle room

          setState(() {

            user['room_id'] = roomId;

            _searchController.clear();

            isSearching = false;

            searchResults = [];

            filteredConversations = List.from(conversations);

          });

          // Forcer l'unfocus pour que le curseur disparaisse quand on revient

          _searchFocusNode.unfocus();

          // Marquer la conversation comme lue avant d'ouvrir le chat
          if (roomId.isNotEmpty) {
            setState(() {
              final conversationIndex = conversations.indexWhere(
                (conv) => conv['room_id']?.toString() == roomId,
              );
              if (conversationIndex >= 0 && conversations[conversationIndex]['unread'] == true) {
                conversations[conversationIndex]['unread'] = false;
                filteredConversations = List.from(conversations);
              }
            });
          }
          
          await Navigator.pushNamed(
            context,
            '/chat',
            arguments: {
              'room_id': roomId,
              'name': name,
              'avatar_url': avatar,
            },
          );
          
          // Rafraîchir la liste après le retour
          if (mounted) {
            fetchConversations();
          }

        } else {

          SnackBarHelper.showError(context, 'Impossible de créer la conversation.');

        }

      } else {

        SnackBarHelper.showError(context, 'Erreur ${response.statusCode} lors de la création de la conversation.');

      }

    } catch (e, s) {

      developer.log('create-room error: $e',

          error: e, stackTrace: s, name: 'MessageriePage');

      if (!mounted) return;

      // Détecter les erreurs de connexion
      final isNetworkError = e is SocketException || 
                             e is TimeoutException ||
                             e.toString().contains('SocketException') ||
                             e.toString().contains('Failed host lookup') ||
                             e.toString().contains('Network is unreachable') ||
                             e.toString().contains('Connection refused') ||
                             e.toString().contains('Connection timed out') ||
                             e.toString().contains('No Internet connection') ||
                             e.toString().contains('ClientException') ||
                             e.toString().contains('OS Error') ||
                             e.toString().contains('nodename nor servname');

      if (isNetworkError) {
        setState(() {
          isConnectionError = true;
        });
        // Ne pas afficher de snackbar pour les erreurs de connexion
      } else {
        SnackBarHelper.showError(context, 'Erreur : $e');
      }

    }

  }
  
  /// Charge et met en cache un SVG avatar
  Future<Map<String, dynamic>> _loadAndCacheSvg(
      String avatarUrl, String username) async {
    try {
      // Vérifier d'abord le cache pour éviter les rechargements
      final cacheKey = username.isNotEmpty ? username : avatarUrl;
      if (_avatarSvgCache.containsKey(cacheKey)) {
        return _avatarSvgCache[cacheKey]!;
      }

      // Utiliser la fonction existante pour récupérer et nettoyer le SVG
      final svgData = await _fetchAndSanitizeSvg(avatarUrl, username);
      
      if (svgData == null || svgData.isEmpty) {
        return {'color': Colors.purple, 'initial': '?'};
      }

      // Extraire le style du SVG
      final avatarStyle = _extractAvatarStyleFromSvg(svgData);
      
      // Mettre en cache pour éviter les rechargements
      _avatarSvgCache[cacheKey] = avatarStyle;
      
      return avatarStyle;
    } catch (e) {
      developer.log('Error loading SVG avatar: $e', name: 'MessageriePage');
      return {'color': Colors.purple, 'initial': '?'};
    }
  }

}

// Widget séparé pour la liste des contacts actifs pour éviter les rebuilds

class _ActiveContactsList extends StatefulWidget {

  final List<Map<String, dynamic>> contacts;

  final bool isDark;

  final Map<String, Map<String, dynamic>> avatarSvgCache;

  final Function(Map<String, dynamic>) onContactTap;

  const _ActiveContactsList({

    Key? key,

    required this.contacts,

    required this.isDark,

    required this.avatarSvgCache,

    required this.onContactTap,

  }) : super(key: key);

  @override

  State<_ActiveContactsList> createState() => _ActiveContactsListState();

}

class _ActiveContactsListState extends State<_ActiveContactsList>

    with AutomaticKeepAliveClientMixin {

  final Map<String, Future<Map<String, dynamic>>> _avatarFutures = {};

  @override

  bool get wantKeepAlive => true;

  @override

  Widget build(BuildContext context) {

    super.build(context); // Nécessaire pour AutomaticKeepAliveClientMixin

    return Container(

      height: 110,

      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

      child: ListView.builder(

        scrollDirection: Axis.horizontal,

        physics: const BouncingScrollPhysics(),

        itemCount: widget.contacts.length,

        itemBuilder: (_, i) {

          final c = widget.contacts[i];

          final username = c['username']?.toString() ?? '';

          final avatarUrl = c['avatar_url']?.toString() ?? '';

          final isOnline = c['status'] == 'online';

          return Padding(

            padding: const EdgeInsets.symmetric(horizontal: 6),

            child: GestureDetector(

              onTap: () => widget.onContactTap(c),

              child: Column(

                mainAxisSize: MainAxisSize.min,

                children: [

                  Stack(

                    children: [

                      CircleAvatar(

                        radius: 26,

                        backgroundColor: Colors.purple.withOpacity(0.2),

                        child: ClipOval(

                          child: SizedBox(

                            width: 52,

                            height: 52,

                            child: _buildAvatar(avatarUrl, username),

                          ),

                        ),

                      ),

                      if (isOnline)

                        Positioned(

                          right: 0,

                          bottom: 0,

                          child: Container(

                            width: 14,

                            height: 14,

                            decoration: BoxDecoration(

                              color: Colors.green,

                              shape: BoxShape.circle,

                              border: Border.all(

                                color: widget.isDark ? Colors.grey[800]! : Colors.white,

                                width: 2.5,

                              ),

                            ),

                          ),

                        ),

                    ],

                  ),

                  const SizedBox(height: 8),

                  SizedBox(

                    width: 70,

                    child: Text(

                      c['name'] ?? 'Inconnu',

                      style: GoogleFonts.poppins(

                        fontSize: 11,

                        color: widget.isDark ? Colors.white70 : Colors.black87,

                        fontWeight: FontWeight.w500,

                      ),

                      overflow: TextOverflow.ellipsis,

                      textAlign: TextAlign.center,

                    ),

                  ),

                ],

              ),

            ),

          );

        },

      ),

    );

  }

  Widget _buildAvatar(String avatarUrl, String username) {

    if (avatarUrl.isEmpty) {

      return const Icon(Icons.person, size: 32, color: Colors.white);

    }

    // Base64 image

    if (avatarUrl.startsWith('data:image/png;base64,')) {

      try {

        final bytes = base64Decode(avatarUrl.split(',').last);

        return Image.memory(bytes, fit: BoxFit.cover);

      } catch (e) {

        return const Icon(Icons.person, size: 28, color: Colors.white);

      }

    }

    // SVG avatar

    final isSvg = avatarUrl.endsWith('.svg') ||

        avatarUrl.contains('message.unistudious.com/avatar/');

    if (isSvg) {

      // Vérifier le cache

      if (widget.avatarSvgCache.containsKey(username)) {

        final cached = widget.avatarSvgCache[username]!;

        return CircleAvatar(

          backgroundColor: cached['color'] as Color,

          child: Text(

            cached['initial'] as String,

            style: const TextStyle(

              fontSize: 26,

              fontWeight: FontWeight.bold,

              color: Colors.white,

            ),

          ),

        );

      }

      // Vérifier d'abord le cache partagé pour éviter les rechargements
      if (widget.avatarSvgCache.containsKey(username)) {
        final cached = widget.avatarSvgCache[username]!;
        return CircleAvatar(

          backgroundColor: cached['color'] as Color,

          child: Text(

            cached['initial'] as String,

            style: const TextStyle(

              fontSize: 26,

              fontWeight: FontWeight.bold,

              color: Colors.white,

            ),

          ),

        );
      }

      // Charger et mettre en cache
      if (!_avatarFutures.containsKey(username)) {
        _avatarFutures[username] = _loadAndCacheSvgForActiveContacts(avatarUrl, username);
      }

      return FutureBuilder<Map<String, dynamic>>(

        future: _avatarFutures[username],

        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {

            // Ne pas afficher de loader, juste un placeholder discret
            return Container(

              width: 70,

              height: 70,

              color: widget.isDark ? Colors.grey[800] : Colors.grey[300],

            );

          }

          if (snapshot.hasData) {

            final avatarStyle = snapshot.data!;

            return CircleAvatar(

              backgroundColor: avatarStyle['color'] as Color,

              child: Text(

                avatarStyle['initial'] as String,

                style: const TextStyle(

                  fontSize: 26,

                  fontWeight: FontWeight.bold,

                  color: Colors.white,

                ),

              ),

            );

          }

          return const Icon(Icons.person, size: 32, color: Colors.white);

        },

      );

    }

    return CachedNetworkImage(

      imageUrl: avatarUrl,

      fit: BoxFit.cover,

      memCacheWidth: 200,

      memCacheHeight: 200,

      maxWidthDiskCache: 200,

      maxHeightDiskCache: 200,

      cacheKey: avatarUrl,

      useOldImageOnUrlChange: true,

      fadeInDuration: const Duration(milliseconds: 0),

      fadeOutDuration: const Duration(milliseconds: 0),

      placeholder: (context, url) => Container(

        width: 70,

        height: 70,

        color: widget.isDark ? Colors.grey[800] : Colors.grey[300],

      ),

      errorWidget: (context, url, error) => const Icon(

        Icons.person,

        size: 28,

        color: Colors.white,

      ),

    );

  }
  
  /// Charge et met en cache un SVG avatar pour les contacts actifs
  Future<Map<String, dynamic>> _loadAndCacheSvgForActiveContacts(
      String avatarUrl, String username) async {
    try {
      // Vérifier d'abord le cache partagé
      if (widget.avatarSvgCache.containsKey(username)) {
        return widget.avatarSvgCache[username]!;
      }

      // Charger le SVG
      final response = await http
          .get(Uri.parse(avatarUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return {'color': Colors.purple, 'initial': '?'};
      }

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('image/svg')) {
        return {'color': Colors.purple, 'initial': '?'};
      }

      var svg = response.body;
      
      // Extraire couleur et initiale
      final rectMatch = RegExp(r'<rect[^>]*fill="([^"]+)"', caseSensitive: false).firstMatch(svg);
      final bgFill = rectMatch?.group(1) ?? '#6200EE';
      final textMatch = RegExp(r'<text[^>]*>([^<]+)</text>', caseSensitive: false).firstMatch(svg);
      final rawText = (textMatch?.group(1) ?? '').trim();
      final initial = rawText.isNotEmpty ? rawText[0].toUpperCase() : '?';

      // Convertir couleur hex en Color
      var value = bgFill.replaceAll('#', '').trim();
      if (value.length == 6) {
        value = 'FF$value';
      }
      Color bgColor = const Color(0xFF6200EE);
      if (value.length == 8) {
        bgColor = Color(int.parse(value, radix: 16));
      }

      final result = {
        'color': bgColor,
        'initial': initial,
      };

      // Mettre en cache partagé
      widget.avatarSvgCache[username] = result;

      return result;
    } catch (e) {
      developer.log('Error loading SVG avatar for active contact: $e', name: 'MessageriePage');
      return {'color': Colors.purple, 'initial': '?'};
    }
  }

}

