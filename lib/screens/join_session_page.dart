import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import 'dart:developer' as developer;
import 'dart:ui' as ui;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/sidebar.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../utils/connection_checker.dart';
import '../utils/snackbar_helper.dart';

class AuthenticatedNetworkImageProvider extends ImageProvider<AuthenticatedNetworkImageProvider> {
  final String url;
  final String? token;

  AuthenticatedNetworkImageProvider(this.url, {this.token});

  @override
  Future<AuthenticatedNetworkImageProvider> obtainKey(ImageConfiguration configuration) {
    return Future.value(this);
  }

  @override
  ImageStreamCompleter loadImage(AuthenticatedNetworkImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(AuthenticatedNetworkImageProvider key, ImageDecoderCallback decode) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Accept': 'image/*',
        },
      );

      developer.log('Image fetch response: ${response.statusCode} for $url', name: 'AuthenticatedNetworkImageProvider');

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.startsWith('image/')) {
          final buffer = await ui.ImmutableBuffer.fromUint8List(response.bodyBytes);
          return await decode(buffer);
        } else {
          final jsonResponse = jsonDecode(response.body);
          final imageUrl = jsonResponse['url'] as String?;
          if (imageUrl != null && imageUrl.isNotEmpty) {
            final publicResponse = await http.get(Uri.parse(imageUrl));
            if (publicResponse.statusCode == 200) {
              final buffer = await ui.ImmutableBuffer.fromUint8List(publicResponse.bodyBytes);
              return await decode(buffer);
            } else {
              throw Exception('Failed to load public image: ${publicResponse.statusCode}');
            }
          } else {
            throw Exception('No image url in json response');
          }
        }
      } else {
        throw Exception('Failed to load image: ${response.statusCode}');
      }
    } catch (e) {
      developer.log('Error fetching image: $e', name: 'AuthenticatedNetworkImageProvider');
      rethrow;
    }
  }
}

class JoinSessionPage extends StatefulWidget {
  const JoinSessionPage({super.key});

  @override
  _JoinSessionPageState createState() => _JoinSessionPageState();
}

class _JoinSessionPageState extends State<JoinSessionPage> {
  List<Map<String, dynamic>> sessions = [];
  List<Map<String, dynamic>> filteredSessions = [];
  List<Map<String, dynamic>> invitations = []; // ← Nouvelle liste pour les invitations
  bool isLoading = true;
  String? errorMessage;
  bool isConnectionError = false;
  bool _isInvitationsExpanded = false; // État pour l'expansion des invitations
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  StreamSubscription<bool>? _connectionSubscription;
  Timer? _connectionCheckTimer;

  @override
  void initState() {
    super.initState();
    _checkAuthAndFetchData();
    _searchController.addListener(_filterSessions);
    _startConnectionMonitoring();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _connectionCheckTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _startConnectionMonitoring() {
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (isConnectionError && mounted) {
        ConnectionChecker().hasConnection().then((hasConnection) {
          if (hasConnection && mounted) {
            setState(() {
              isConnectionError = false;
            });
            fetchSessions();
          }
        });
      }
    });
  }

  Future<void> _checkAuthAndFetchData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.isLoggedIn) {
      setState(() {
        errorMessage = 'Veuillez vous connecter pour continuer.';
        isLoading = false;
      });
      return;
    }

    developer.log('Token disponible : ${authProvider.currentToken}', name: 'JoinSessionPage');
    fetchSessions();
  }

  Future<void> fetchSessions() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      if (!mounted) return;
      setState(() {
        isConnectionError = false;
        errorMessage = null;
      });

      // Charger les invitations en parallèle
      await _fetchInvitations();

      final response = await authProvider.authenticatedRequest(
        'GET',
        '/api/get-account',
      );

      if (response.statusCode == 200) {
        final dynamic decodedData = jsonDecode(response.body);

        if (decodedData is Map<String, dynamic> && decodedData['accountData'] is List<dynamic>) {
          List<Map<String, dynamic>> allSessions = [];

          for (var account in decodedData['accountData']) {
            if (account['sessions'] != null && account['sessions'] is List<dynamic>) {
              for (var session in account['sessions']) {
                final sessionMap = {
                  'id': session['id']?.toString() ?? 'No ID',
                  'name': account['name']?.toString() ?? 'Unnamed Account',
                  'sessionName': session['name']?.toString() ?? 'Unnamed Session',
                  'startDate': session['startDate']?.toString() ?? 'No Date',
                  'accountId': account['id']?.toString() ?? 'No Account ID',
                  'accountName': account['name']?.toString() ?? 'No Account Name',
                  'address': account['settings']?['location']?.toString() ?? 'No Address',
                  'email': account['settings']?['mail']?.toString() ?? 'No Email',
                  'phone': account['settings']?['phone']?.toString() ?? 'No Phone',
                  'website': account['settings']?['webSite']?.toString() ?? 'No Website',
                  'image': account['image']?.toString(),
                  'formationName': session['formationName'] ?? 'N/A',
                  'endDate': session['endDate'] ?? 'N/A',
                  'typePay': session['typePay'] ?? 'N/A',
                  'typeSession': session['typeSession'] ?? 'N/A',
                  'capacity': session['capacity'] ?? 'N/A',
                  'nbrRegister': session['nbrRegister'] ?? 'N/A',
                  'local': session['local'] ?? [],
                };
                allSessions.add(sessionMap);
              }
            }
          }

          Map<String, List<Map<String, dynamic>>> groupedSessions = {};
          for (var session in allSessions) {
            String accountName = session['accountName'];
            if (!groupedSessions.containsKey(accountName)) {
              groupedSessions[accountName] = [];
            }
            groupedSessions[accountName]!.add(session);
          }

          sessions = groupedSessions.entries.map((entry) {
            return {
              'name': entry.key,
              'sessions': entry.value,
              'address': entry.value[0]['address'],
              'email': entry.value[0]['email'],
              'phone': entry.value[0]['phone'],
              'website': entry.value[0]['website'],
              'image': entry.value[0]['image'],
            };
          }).toList();
          filteredSessions = List.from(sessions);

          if (!mounted) return;
          setState(() {
            isLoading = false;
            isConnectionError = false;
            errorMessage = null;
          });
        } else {
          throw Exception('Unexpected response format');
        }
      } else {
        if (!mounted) return;
        setState(() {
          errorMessage = 'Échec du chargement des sessions : ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      developer.log('Error fetching sessions: $e', name: 'JoinSessionPage');

      final isNetworkError = e is SocketException ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Network is unreachable') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('Connection timed out') ||
          e.toString().contains('No Internet connection');

      if (!mounted) return;
      setState(() {
        if (isNetworkError) {
          isConnectionError = true;
          errorMessage = null;
        } else {
          isConnectionError = false;
          errorMessage = 'Erreur lors de la récupération des sessions : $e';
        }
        isLoading = false;
      });
    }
  }

  void _filterSessions() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredSessions = sessions.where((session) {
        return session['name']?.toLowerCase().contains(query) ?? false ||
            session['address']?.toLowerCase().contains(query) ?? false ||
            session['email']?.toLowerCase().contains(query) ?? false ||
            session['phone']?.toLowerCase().contains(query) ?? false ||
            session['website']?.toLowerCase().contains(query) ?? false ||
            (session['sessions'] as List<Map<String, dynamic>>).any((s) =>
            s['sessionName']?.toLowerCase().contains(query) ?? false ||
                s['formationName']?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  // ──────────────────────────────────────────────────────────────
  // Méthodes pour gérer les invitations
  // ──────────────────────────────────────────────────────────────
  Future<void> _fetchInvitations() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      final response = await authProvider.authenticatedRequest(
        'GET',
        '/api/get-invitation-session',
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final dynamic decodedData = jsonDecode(response.body);

        if (decodedData is Map<String, dynamic> && decodedData['invitationData'] is List<dynamic>) {
          final List<dynamic> invitationDataList = decodedData['invitationData'];
          
          // Filtrer les valeurs null et mapper les données
          final List<Map<String, dynamic>> fetchedInvitations = invitationDataList
              .where((item) => item != null)
              .map<Map<String, dynamic>>((item) {
                final Map<String, dynamic> invitation = item as Map<String, dynamic>;
                return {
                  'sessionId': invitation['sessionId']?.toString(),
                  'sessionName': invitation['sessionName']?.toString() ?? 'Session sans nom',
                  'notificationId': invitation['notificationId']?.toString(),
                  // Champs optionnels pour l'affichage (peuvent être remplis plus tard si nécessaire)
                  'accountName': invitation['accountName']?.toString(),
                  'formationName': invitation['formationName']?.toString(),
                  'startDate': invitation['startDate']?.toString(),
                  'image': invitation['image']?.toString(),
                };
              })
              .toList();

          if (!mounted) return;
          setState(() {
            invitations = fetchedInvitations;
          });
        } else {
          developer.log('Unexpected invitation response format', name: 'JoinSessionPage');
          if (!mounted) return;
          setState(() {
            invitations = [];
          });
        }
      } else {
        developer.log('Failed to fetch invitations: ${response.statusCode}', name: 'JoinSessionPage');
        if (!mounted) return;
        setState(() {
          invitations = [];
        });
      }
    } catch (e) {
      developer.log('Error fetching invitations: $e', name: 'JoinSessionPage');
      if (!mounted) return;
      setState(() {
        invitations = [];
      });
    }
  }

  Future<void> _acceptInvitation(Map<String, dynamic> invitation) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final String? sessionId = invitation['sessionId']?.toString();
    final String? notificationId = invitation['notificationId']?.toString();

    if (sessionId == null || notificationId == null) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        'Impossible d\'accepter cette invitation (données manquantes).',
      );
      return;
    }

    try {
      final response = await authProvider.authenticatedRequest(
        'POST',
        '/api/accept-invitation-session/$sessionId/$notificationId',
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        final String successMessage =
            (decoded is Map && decoded['success'] is String) ? decoded['success'] as String : 'Invitation acceptée avec succès';

        setState(() {
          invitations.remove(invitation);
        });

        SnackBarHelper.showSuccess(
          context,
          successMessage,
        );

        // Recharger les sessions pour refléter l'acceptation
        fetchSessions();
      } else {
        SnackBarHelper.showError(
          context,
          'Erreur lors de l\'acceptation de l\'invitation (${response.statusCode}).',
        );
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        'Erreur lors de l\'acceptation de l\'invitation : $e',
      );
    }
  }

  Future<void> _declineInvitation(Map<String, dynamic> invitation) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final String? sessionId = invitation['sessionId']?.toString();
    final String? notificationId = invitation['notificationId']?.toString();

    if (sessionId == null || notificationId == null) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        'Impossible de refuser cette invitation (données manquantes).',
      );
      return;
    }

    try {
      final response = await authProvider.authenticatedRequest(
        'POST',
        '/api/delete-invitation-session/$sessionId/$notificationId',
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        final String successMessage =
            (decoded is Map && decoded['success'] is String) ? decoded['success'] as String : 'Invitation refusée avec succès';

        setState(() {
          invitations.remove(invitation);
        });

        SnackBarHelper.showSuccess(
          context,
          successMessage,
        );
      } else {
        SnackBarHelper.showError(
          context,
          'Erreur lors du refus de l\'invitation (${response.statusCode}).',
        );
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        'Erreur lors du refus de l\'invitation : $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            );
          },
        ),
        title: Text(
          'Rejoindre une session',
          style: theme.textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontFamily: GoogleFonts.poppins().fontFamily,
          ) ??
              TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
        ),
        centerTitle: false,
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
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: fetchSessions,
        child: GestureDetector(
          onTap: () {
            _searchFocusNode.unfocus();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Container(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Rechercher une session...',
                    filled: true,
                    fillColor: theme.inputDecorationTheme.fillColor ?? theme.cardColor,
                    prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                      fontFamily: GoogleFonts.poppins().fontFamily,
                    ) ??
                        TextStyle(
                          color: Colors.grey[600],
                          fontFamily: GoogleFonts.poppins().fontFamily,
                        ),
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: GoogleFonts.poppins().fontFamily,
                  ) ??
                      TextStyle(
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                ),
                const SizedBox(height: 24),

                // ────────────────────────────────
                // Section Invitations (Expansible)
                // ────────────────────────────────
                if (!isLoading && invitations.isNotEmpty) ...[
                  // Bouton d'invitation avec badge
                  InkWell(
                    onTap: () {
                      if (!mounted) return;
                      setState(() {
                        _isInvitationsExpanded = !_isInvitationsExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  const Color(0xFF002C49), // Bleu foncé pour dark
                                  const Color(0xFF015698), // Bleu moyen pour dark
                                ]
                              : [
                                  const Color(0xFF42A5F5), // Bleu clair pour light
                                  const Color(0xFF64B5F6), // Bleu très clair pour light
                                ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? const Color(0xFF0362B2).withOpacity(0.4)
                                : const Color(0xFF42A5F5).withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.mail_outlined,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Invitation',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: GoogleFonts.poppins().fontFamily,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${invitations.length} invitation${invitations.length > 1 ? 's' : ''} reçue${invitations.length > 1 ? 's' : ''}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 14,
                                    fontFamily: GoogleFonts.poppins().fontFamily,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Badge de compteur
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${invitations.length}',
                              style: TextStyle(
                                color: isDark
                                    ? const Color(0xFF002C49)
                                    : const Color(0xFF42A5F5),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Flèche animée
                          AnimatedRotation(
                            duration: const Duration(milliseconds: 300),
                            turns: _isInvitationsExpanded ? 0.5 : 0,
                            child: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Contenu expansible des invitations avec animation depuis le haut
                  ClipRect(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: _isInvitationsExpanded
                          ? TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 300),
                              tween: Tween<double>(begin: -1.0, end: 0.0),
                              curve: Curves.easeOut,
                              builder: (context, value, child) {
                                return Transform.translate(
                                  offset: Offset(0, value * 100),
                                  child: Opacity(
                                    opacity: 1.0 + value,
                                    child: Column(
                                      children: [
                        ...invitations.map((invitation) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Card(
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  color: isDark
                                      ? theme.cardColor
                                      : Colors.white,
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF015698).withOpacity(0.5)
                                        : const Color(0xFF42A5F5).withOpacity(0.3),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isDark
                                          ? Colors.black.withOpacity(0.3)
                                          : const Color(0xFF42A5F5).withOpacity(0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Nom de la session
                                      Text(
                                        invitation['sessionName'] ?? 'Session sans nom',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF42A5F5),
                                          fontFamily: GoogleFonts.poppins().fontFamily,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 20),
                                      // Boutons d'action
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: () => _acceptInvitation(invitation),
                                              icon: const Icon(Icons.check_circle_outline, size: 20),
                                              label: const Text(
                                                'Accepter',
                                                style: TextStyle(fontSize: 15),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green[600],
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 12,
                                                ),
                                                elevation: 4,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => _declineInvitation(invitation),
                                              icon: const Icon(Icons.cancel_outlined, size: 20),
                                              label: const Text(
                                                'Refuser',
                                                style: TextStyle(fontSize: 15),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.red[700],
                                                side: BorderSide(
                                                  color: Colors.red[700]!,
                                                  width: 2,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                                    ),
                                  ),
                                );
                              },
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // ────────────────────────────────
                // Contenu existant (sessions publiques)
                // ────────────────────────────────
                if (isLoading)
                  Center(child: CircularProgressIndicator(color: theme.primaryColor))
                else if (isConnectionError)
                  Center(
                    // ... (inchangé)
                  )
                else if (errorMessage != null)
                  Center(
                    child: Text(
                      errorMessage!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.red[700],
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else if (filteredSessions.isEmpty && invitations.isEmpty)
                  Center(
                    child: Text(
                      'Aucune session ni invitation disponible',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.textTheme.bodyLarge?.color?.withOpacity(0.7),
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredSessions.length,
                    itemBuilder: (context, index) {
                      final account = filteredSessions[index];
                      return Card(
                              // ... (tout le code existant de la carte session reste identique)
                              color: theme.cardColor,
                              elevation: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          height: 100,
                                          width: 100,
                                          decoration: BoxDecoration(
                                            color: theme.dividerColor.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: account['image'] != null && account['image'] != ''
                                              ? ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Image(
                                              image: AuthenticatedNetworkImageProvider(
                                                'https://www.unistudious.com/api/public-image-server/${account['image']}',
                                                token: authProvider.currentToken,
                                              ),
                                              height: 100,
                                              width: 100,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) => Center(
                                                child: Image.asset(
                                                  'assets/account.png',
                                                  height: 100,
                                                  width: 100,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                          )
                                              : Center(
                                            child: Image.asset(
                                              'assets/account.png',
                                              height: 100,
                                              width: 100,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                account['name'] ?? 'Unnamed Account',
                                                style: theme.textTheme.titleLarge?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                                  color: isDark ? Colors.blue : theme.primaryColor,
                                                ) ??
                                                    TextStyle(
                                                      fontSize: 20,
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark ? Colors.blue : theme.primaryColor,
                                                      fontFamily: GoogleFonts.poppins().fontFamily,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Icon(Icons.location_on, color: theme.iconTheme.color, size: 18),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            account['address'] ?? 'No Address',
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              fontFamily: GoogleFonts.poppins().fontFamily,
                                            ) ??
                                                TextStyle(
                                                  color: theme.textTheme.bodyMedium?.color,
                                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.email, color: theme.iconTheme.color, size: 18),
                                        const SizedBox(width: 6),
                                        Text(
                                          account['email'] ?? 'No Email',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontFamily: GoogleFonts.poppins().fontFamily,
                                          ) ??
                                              TextStyle(
                                                color: theme.textTheme.bodyMedium?.color,
                                                fontFamily: GoogleFonts.poppins().fontFamily,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.phone, color: theme.iconTheme.color, size: 18),
                                        const SizedBox(width: 6),
                                        Text(
                                          account['phone'] ?? 'No Phone',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontFamily: GoogleFonts.poppins().fontFamily,
                                          ) ??
                                              TextStyle(
                                                color: theme.textTheme.bodyMedium?.color,
                                                fontFamily: GoogleFonts.poppins().fontFamily,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.language, color: theme.iconTheme.color, size: 18),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () {
                                              final website = account['website'] ?? 'https://www.unistudious.com/piumaacademy';
                                              launchUrl(Uri.parse(website));
                                            },
                                            child: Text(
                                              account['website'] ?? 'https://www.unistudious.com/piumaacademy',
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: Colors.blue,
                                                fontFamily: GoogleFonts.poppins().fontFamily,
                                              ) ??
                                                  TextStyle(
                                                    color: Colors.blue,
                                                    fontFamily: GoogleFonts.poppins().fontFamily,
                                                  ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          if (authProvider.currentToken != null) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => SessionDetailPage(
                                                  accountId: account['sessions'][0]['accountId']!,
                                                  token: authProvider.currentToken!,
                                                  sessions: account['sessions'],
                                                ),
                                              ),
                                            );
                                          } else {
                                            SnackBarHelper.showError(
                                              context,
                                              'Token non disponible',
                                            );
                                          }
                                        },
                                        icon: const Icon(Icons.add),
                                        label: Text(
                                          "S'inscrire maintenant",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontFamily: GoogleFonts.poppins().fontFamily,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isDark ? const Color(0xFF1A003D) : theme.primaryColor,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class SessionDetailPage extends StatefulWidget {
  final String accountId;
  final String token;
  final List<Map<String, dynamic>> sessions;
  final String apiUrl = 'https://www.unistudious.com';

  const SessionDetailPage({
    super.key,
    required this.accountId,
    required this.token,
    required this.sessions,
  });

  @override
  _SessionDetailPageState createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  bool isLoading = true;
  String? errorMessage;
  Map<String, String?> selectedLocales = {};
  Map<String, bool> hasRegistered = {};
  bool isDark = false;
  final ImagePicker _picker = ImagePicker();
  late PageController _pageController;
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    developer.log(
        'Initializing SessionDetailPage with accountId: ${widget.accountId}, token: ${widget.token}',
        name: 'SessionDetailPage');
    _loadRegistrationStatus();
    fetchSessionDetails();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadRegistrationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final registeredSessions = prefs.getStringList('registeredSessions') ?? [];
    setState(() {
      for (var session in widget.sessions) {
        hasRegistered[session['id']] = registeredSessions.contains(session['id']);
        selectedLocales[session['id']] = (session['local'] as List<dynamic>?)?.isNotEmpty == true
            ? session['local'][0]['localName']?.toString()
            : null;
        developer.log('Session name for id ${session['id']}: ${session['sessionName']}, Registered: ${hasRegistered[session['id']]}', name: 'SessionDetailPage');
      }
    });
  }

  Future<void> _saveRegistrationStatus(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final registeredSessions = prefs.getStringList('registeredSessions') ?? [];
    if (!registeredSessions.contains(sessionId)) {
      registeredSessions.add(sessionId);
      await prefs.setStringList('registeredSessions', registeredSessions);
      developer.log('Saved registration status for sessionId: $sessionId', name: 'SessionDetailPage');
    }
  }

  Future<void> _removeRegistrationStatus(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final registeredSessions = prefs.getStringList('registeredSessions') ?? [];
    if (registeredSessions.contains(sessionId)) {
      registeredSessions.remove(sessionId);
      await prefs.setStringList('registeredSessions', registeredSessions);
      developer.log('Removed registration status for sessionId: $sessionId', name: 'SessionDetailPage');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    isDark = Theme.of(context).brightness == Brightness.dark;
  }

  Future<void> fetchSessionDetails() async {
    final String apiUrl = 'https://www.unistudious.com/api/get-session-by-account/${widget.accountId}';
    developer.log('Fetching session details for accountId: ${widget.accountId}', name: 'SessionDetailPage');
    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      developer.log('API Response (get-session-by-account): ${response.statusCode} - ${response.body}', name: 'SessionDetailPage');
      if (response.statusCode == 200) {
        final dynamic decodedData = jsonDecode(response.body);
        if (decodedData is Map<String, dynamic> && decodedData['sessionData'] is List<dynamic>) {
          final List<Map<String, dynamic>> sessionList =
          (decodedData['sessionData'] as List).map((item) => item as Map<String, dynamic>).toList();
          if (sessionList.isNotEmpty) {
            widget.sessions.clear();
            for (var session in sessionList) {
              final sessionMap = {
                'id': session['id']?.toString() ?? 'No ID',
                'name': session['name']?.toString() ?? 'Unnamed Session',
                'sessionName': session['name']?.toString() ?? 'Unnamed Session',
                'startDate': session['startDate']?.toString() ?? 'No Date',
                'endDate': session['endDate']?.toString() ?? 'N/A',
                'capacity': session['capacity']?.toString() ?? 'N/A',
                'price': session['price']?.toString() ?? 'N/A',
                'currency': session['currency']?.toString() ?? 'N/A',
                'typePay': session['typePay']?.toString() ?? 'N/A',
                'image': session['image']?.toString(),
                'accountId': session['accountId']?.toString() ?? 'No Account ID',
                'accountName': session['accountName']?.toString() ?? 'Piuma Academy',
                'formationId': session['formationId']?.toString() ?? 'No Formation ID',
                'formationName': session['formationName']?.toString() ?? 'N/A',
                'isRegister': session['isRegister'] ?? false,
                'local': session['local'] ?? [],
                'extraSession': session['extraSession'] ?? false,
                'extraData': session['extraData'] ?? [],
              };
              developer.log('Session added to widget.sessions: $sessionMap', name: 'SessionDetailPage');
              widget.sessions.add(sessionMap);
              hasRegistered[sessionMap['id']] = sessionMap['isRegister'] as bool;
            }
            setState(() {
              isLoading = false;
              for (var session in widget.sessions) {
                selectedLocales[session['id']] = (session['local'] as List<dynamic>?)?.isNotEmpty == true
                    ? session['local'][0]['localName']?.toString()
                    : null;
                developer.log('Updated selectedLocales for id ${session['id']}: ${selectedLocales[session['id']]}', name: 'SessionDetailPage');
              }
            });
          } else {
            developer.log('No sessions found for accountId: ${widget.accountId}', name: 'SessionDetailPage');
            setState(() {
              errorMessage = 'Aucune session disponible';
              isLoading = false;
            });
          }
        } else {
          throw Exception('Unexpected response format');
        }
      } else {
        setState(() {
          errorMessage = 'Erreur ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      developer.log('Error fetching session details: $e', name: 'SessionDetailPage');
      setState(() {
        errorMessage = 'Erreur de chargement : $e';
        isLoading = false;
      });
    }
  }

  Widget _infoRow(IconData icon, String label, String? value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.iconTheme.color),
          const SizedBox(width: 8),
                RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: "$label: ",
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFamily: GoogleFonts.poppins().fontFamily,
                  ) ??
                      TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontWeight: FontWeight.bold,
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                ),
                TextSpan(
                  text: value ?? 'N/A',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: GoogleFonts.poppins().fontFamily,
                  ) ??
                      TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showJoinConfirmation(String sessionId) {
    final theme = Theme.of(context);
    final selectedSession = widget.sessions.firstWhere((session) => session['id'] == sessionId, orElse: () => {});
    String? note;
    Map<String, String> extraFieldValues = {};
    Map<String, TextEditingController> extraFieldControllers = {};
    Map<String, XFile?> extraFieldFiles = {};
    Map<String, String?> extraFieldErrors = {};

    final urlPattern = RegExp(
      r'^(https?:\/\/)?([\w\-]+(\.[\w\-]+)+)(\/[\w\-._~:/?#[\]@!$&()*+,;=]*)?$',
      caseSensitive: false,
    );

    final integerPattern = RegExp(r'^-?\d+$');
    final floatPattern = RegExp(r'^-?\d*\.?\d*$');

    if (selectedSession['extraSession'] == true && selectedSession['extraData'] != null) {
      for (var field in selectedSession['extraData'] as List<dynamic>) {
        final fieldName = field['name']?.toString() ?? '';
        extraFieldControllers[fieldName] = TextEditingController();
        extraFieldFiles[fieldName] = null;
        extraFieldErrors[fieldName] = null;
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter dialogSetState) {
            return GestureDetector(
              onTap: () {
                FocusScope.of(context).unfocus();
              },
              child: AlertDialog(
                title: Text(
                  'Inscription',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFamily: GoogleFonts.poppins().fontFamily,
                    color: theme.primaryColor,
                  ) ??
                      TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.primaryColor,
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Local :${((selectedSession['local'] as List<dynamic>?)?.isNotEmpty ?? false) ? ' *' : ''}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontFamily: GoogleFonts.poppins().fontFamily,
                          color: ((selectedSession['local'] as List<dynamic>?)?.isNotEmpty ?? false) ? Colors.red[900] : null,
                        ) ??
                            TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: GoogleFonts.poppins().fontFamily,
                              color: ((selectedSession['local'] as List<dynamic>?)?.isNotEmpty ?? false) ? Colors.red[900] : null,
                            ),
                      ),
                      if ((selectedSession['local'] as List<dynamic>?)?.isNotEmpty ?? false)
                        DropdownButton<String>(
                          value: selectedLocales[sessionId],
                          hint: Text(
                            'Sélectionnez un local',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ) ??
                                TextStyle(
                                  color: Colors.grey[600],
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                ),
                          ),
                          items: (selectedSession['local'] as List<dynamic>?)?.map((local) {
                            return DropdownMenuItem<String>(
                              value: local['localName']?.toString(),
                              child: Text(
                                local['localName']?.toString() ?? 'Non défini',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                ) ??
                                    TextStyle(
                                      fontSize: 14,
                                      fontFamily: GoogleFonts.poppins().fontFamily,
                                    ),
                              ),
                            );
                          }).toList() ?? [],
                          onChanged: (String? newValue) {
                            dialogSetState(() {
                              selectedLocales[sessionId] = newValue;
                              extraFieldErrors['local'] = null;
                            });
                            setState(() {
                              selectedLocales[sessionId] = newValue;
                            });
                            developer.log('Selected local updated to: $newValue for sessionId: $sessionId', name: 'SessionDetailPage');
                          },
                          isExpanded: true,
                          underline: Container(
                            height: 1,
                            color: theme.dividerColor,
                          ),
                          dropdownColor: theme.dialogBackgroundColor,
                        )
                      else
                        Text(
                          'Aucun local disponible',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                            fontFamily: GoogleFonts.poppins().fontFamily,
                            fontStyle: FontStyle.italic,
                          ) ??
                              TextStyle(
                                color: Colors.grey[600],
                                fontFamily: GoogleFonts.poppins().fontFamily,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      if (extraFieldErrors['local'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            extraFieldErrors['local']!,
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      if (selectedSession['extraSession'] == true && selectedSession['extraData'] != null) ...[
                        Text(
                          'Champs supplémentaires :',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ) ??
                              TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                        ),
                        const SizedBox(height: 10),
                        ...((selectedSession['extraData'] as List<dynamic>?)?.map((field) {
                          final fieldName = field['name']?.toString() ?? '';
                          final fieldType = field['type']?.toString() ?? 'string';
                          final fieldDescription = field['description']?.toString() ?? '';
                          final isRequired = field['required'] == true;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${fieldName.capitalize()} ${isRequired ? '*' : ''}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontFamily: GoogleFonts.poppins().fontFamily,
                                    color: isRequired ? Colors.red[900] : null,
                                  ) ??
                                      TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontFamily: GoogleFonts.poppins().fontFamily,
                                        color: isRequired ? Colors.red[900] : null,
                                      ),
                                ),
                                if (fieldType == 'Boolean') ...[
                                  DropdownButton<String>(
                                    value: extraFieldValues[fieldName]?.isNotEmpty == true ? extraFieldValues[fieldName] : null,
                                    hint: Text(
                                      fieldDescription.isNotEmpty ? fieldDescription : 'Sélectionnez une option',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                                        fontFamily: GoogleFonts.poppins().fontFamily,
                                      ) ??
                                          TextStyle(
                                            color: Colors.grey[600],
                                            fontFamily: GoogleFonts.poppins().fontFamily,
                                          ),
                                    ),
                                    items: [
                                      DropdownMenuItem<String>(
                                        value: 'Oui',
                                        child: Text(
                                          'Oui',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontFamily: GoogleFonts.poppins().fontFamily,
                                          ) ??
                                              TextStyle(
                                                fontSize: 14,
                                                fontFamily: GoogleFonts.poppins().fontFamily,
                                              ),
                                        ),
                                      ),
                                      DropdownMenuItem<String>(
                                        value: 'Non',
                                        child: Text(
                                          'Non',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontFamily: GoogleFonts.poppins().fontFamily,
                                          ) ??
                                              TextStyle(
                                                fontSize: 14,
                                                fontFamily: GoogleFonts.poppins().fontFamily,
                                              ),
                                        ),
                                      ),
                                    ],
                                    onChanged: (String? newValue) {
                                      dialogSetState(() {
                                        extraFieldValues[fieldName] = newValue ?? '';
                                        extraFieldErrors[fieldName] = isRequired && (newValue?.isEmpty ?? true)
                                            ? 'Ce champ est requis'
                                            : null;
                                      });
                                      developer.log(
                                        'Selected Boolean value for $fieldName: $newValue',
                                        name: 'SessionDetailPage',
                                      );
                                    },
                                    isExpanded: true,
                                    underline: Container(
                                      height: 1,
                                      color: theme.dividerColor,
                                    ),
                                    dropdownColor: theme.dialogBackgroundColor,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontFamily: GoogleFonts.poppins().fontFamily,
                                    ) ??
                                        TextStyle(
                                          fontFamily: GoogleFonts.poppins().fontFamily,
                                        ),
                                  ),
                                ] else if (fieldType == 'date') ...[
                                  TextField(
                                    controller: extraFieldControllers[fieldName],
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      hintText: fieldDescription.isNotEmpty ? fieldDescription : 'Sélectionnez une date',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      filled: true,
                                      fillColor: theme.inputDecorationTheme.fillColor ?? theme.cardColor,
                                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                                        fontFamily: GoogleFonts.poppins().fontFamily,
                                      ) ??
                                          TextStyle(
                                            color: Colors.grey[600],
                                            fontFamily: GoogleFonts.poppins().fontFamily,
                                          ),
                                      errorText: extraFieldErrors[fieldName],
                                    ),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontFamily: GoogleFonts.poppins().fontFamily,
                                    ) ??
                                        TextStyle(
                                          fontFamily: GoogleFonts.poppins().fontFamily,
                                        ),
                                    onTap: () async {
                                      final DateTime? pickedDate = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime(1900),
                                        lastDate: DateTime.now(),
                                        builder: (context, child) {
                                          return Theme(
                                            data: Theme.of(context).copyWith(
                                              colorScheme: ColorScheme.light(
                                                primary: theme.primaryColor,
                                                onPrimary: Colors.white,
                                                surface: theme.dialogBackgroundColor,
                                                onSurface: theme.textTheme.bodyMedium?.color ?? Colors.black,
                                              ),
                                              textButtonTheme: TextButtonThemeData(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: theme.primaryColor,
                                                  textStyle: TextStyle(
                                                    fontFamily: GoogleFonts.poppins().fontFamily,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            child: child!,
                                          );
                                        },
                                      );
                                      if (pickedDate != null) {
                                        final displayDate = DateFormat('dd/MM/yyyy').format(pickedDate);
                                        final isoDate = DateFormat('yyyy-MM-dd').format(pickedDate);
                                        dialogSetState(() {
                                          extraFieldControllers[fieldName]!.text = displayDate;
                                          extraFieldValues[fieldName] = isoDate;
                                          extraFieldErrors[fieldName] = null;
                                        });
                                        developer.log(
                                          'Selected date for $fieldName: $displayDate (ISO: $isoDate)',
                                          name: 'SessionDetailPage',
                                        );
                                      }
                                    },
                                  ),
                                ] else if (fieldType == 'Link') ...[
                                  TextField(
                                    controller: extraFieldControllers[fieldName],
                                    keyboardType: TextInputType.url,
                                    decoration: InputDecoration(
                                      hintText: fieldDescription.isNotEmpty
                                          ? fieldDescription
                                          : 'Entrez un lien (ex: https://example.com)',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      filled: true,
                                      fillColor: theme.inputDecorationTheme.fillColor ?? theme.cardColor,
                                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                                        fontFamily: GoogleFonts.poppins().fontFamily,
                                      ) ??
                                          TextStyle(
                                            color: Colors.grey[600],
                                            fontFamily: GoogleFonts.poppins().fontFamily,
                                          ),
                                      errorText: extraFieldErrors[fieldName],
                                    ),
                                    onChanged: (value) {
                                      dialogSetState(() {
                                        extraFieldValues[fieldName] = value;
                                        if (value.isNotEmpty && !urlPattern.hasMatch(value)) {
                                          extraFieldErrors[fieldName] = 'Veuillez entrer un lien valide';
                                        } else if (isRequired && value.isEmpty) {
                                          extraFieldErrors[fieldName] = 'Ce champ est requis';
                                        } else {
                                          extraFieldErrors[fieldName] = null;
                                        }
                                      });
                                      developer.log('Link value for $fieldName: $value', name: 'SessionDetailPage');
                                    },
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontFamily: GoogleFonts.poppins().fontFamily,
                                    ) ??
                                        TextStyle(
                                          fontFamily: GoogleFonts.poppins().fontFamily,
                                        ),
                                  ),
                                ] else ...[
                                  TextField(
                                    controller: extraFieldControllers[fieldName],
                                    readOnly: fieldType == 'image' || fieldType == 'file',
                                    decoration: InputDecoration(
                                      hintText: fieldType == 'image' || fieldType == 'file'
                                          ? (extraFieldFiles[fieldName] != null
                                          ? extraFieldFiles[fieldName]!.name
                                          : fieldDescription.isNotEmpty
                                          ? fieldDescription
                                          : 'Sélectionnez un ${fieldType == 'image' ? 'image' : 'fichier'}')
                                          : fieldDescription.isNotEmpty
                                          ? fieldDescription
                                          : 'Entrez ${fieldName}',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      filled: true,
                                      fillColor: theme.inputDecorationTheme.fillColor ?? theme.cardColor,
                                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                                        fontFamily: GoogleFonts.poppins().fontFamily,
                                      ) ??
                                          TextStyle(
                                            color: Colors.grey[600],
                                            fontFamily: GoogleFonts.poppins().fontFamily,
                                          ),
                                      errorText: extraFieldErrors[fieldName],
                                      suffixIcon: fieldType == 'image' || fieldType == 'file'
                                          ? IconButton(
                                        icon: Icon(
                                          fieldType == 'image' ? Icons.image : Icons.upload_file,
                                          color: theme.iconTheme.color,
                                        ),
                                        onPressed: () async {
                                          final XFile? file = fieldType == 'image'
                                              ? await _picker.pickImage(source: ImageSource.gallery)
                                              : await _picker.pickMedia();
                                          if (file != null) {
                                            dialogSetState(() {
                                              extraFieldFiles[fieldName] = file;
                                              extraFieldValues[fieldName] = file.path;
                                              extraFieldControllers[fieldName]!.text = file.name;
                                              extraFieldErrors[fieldName] = null;
                                            });
                                          }
                                        },
                                      )
                                          : null,
                                    ),
                                    keyboardType: fieldType == 'integer' || fieldType == 'float'
                                        ? TextInputType.number
                                        : TextInputType.text,
                                    inputFormatters: fieldType == 'integer'
                                        ? [FilteringTextInputFormatter.allow(integerPattern)]
                                        : fieldType == 'float'
                                        ? [FilteringTextInputFormatter.allow(floatPattern)]
                                        : null,
                                    onChanged: fieldType != 'image' && fieldType != 'file' && fieldType != 'date'
                                        ? (value) {
                                      dialogSetState(() {
                                        extraFieldValues[fieldName] = value;
                                        if (isRequired && value.isEmpty) {
                                          extraFieldErrors[fieldName] = 'Ce champ est requis';
                                        } else if (fieldType == 'integer' &&
                                            value.isNotEmpty &&
                                            !integerPattern.hasMatch(value)) {
                                          extraFieldErrors[fieldName] = 'Veuillez entrer un nombre entier valide';
                                        } else if (fieldType == 'float' &&
                                            value.isNotEmpty &&
                                            !floatPattern.hasMatch(value)) {
                                          extraFieldErrors[fieldName] = 'Veuillez entrer un nombre décimal valide';
                                        } else {
                                          extraFieldErrors[fieldName] = null;
                                        }
                                      });
                                    }
                                        : null,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontFamily: GoogleFonts.poppins().fontFamily,
                                    ) ??
                                        TextStyle(
                                          fontFamily: GoogleFonts.poppins().fontFamily,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList() ?? []),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        'Note (optionnelle) :',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontFamily: GoogleFonts.poppins().fontFamily,
                        ) ??
                            TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ),
                      ),
                      TextField(
                        onChanged: (value) {
                          note = value;
                        },
                        decoration: InputDecoration(
                          hintText: 'Ajoutez une note (facultatif)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: theme.inputDecorationTheme.fillColor ?? theme.cardColor,
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ) ??
                              TextStyle(
                                color: Colors.grey[600],
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                        ),
                        maxLines: 3,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: GoogleFonts.poppins().fontFamily,
                        ) ??
                            TextStyle(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      extraFieldControllers.forEach((key, controller) => controller.dispose());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF1A003D) : theme.dividerColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      elevation: 2,
                    ),
                    child: Text(
                      'Annuler',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: GoogleFonts.poppins().fontFamily,
                        color: Colors.white,
                      ) ??
                          TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                            color: Colors.white,
                          ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      bool allRequiredFieldsFilled = true;
                      bool allNumericFieldsValid = true;

// Vérifier si le champ local est required (seulement s'il y a au moins un local)
                      final hasLocals = (selectedSession['local'] as List<dynamic>?)?.isNotEmpty ?? false;
                      if (hasLocals && selectedLocales[sessionId] == null) {
                        dialogSetState(() {
                          extraFieldErrors['local'] = 'Veuillez sélectionner un local';
                        });
                        allRequiredFieldsFilled = false;
                      } else {
                        dialogSetState(() {
                          extraFieldErrors['local'] = null;
                        });
                      }

                      if (selectedSession['extraSession'] == true && selectedSession['extraData'] != null) {
                        for (var field in selectedSession['extraData'] as List<dynamic>) {
                          final fieldName = field['name']?.toString() ?? '';
                          final fieldType = field['type']?.toString() ?? 'string';
                          final isRequired = field['required'] == true;

                          if (isRequired) {
                            if (fieldType == 'image' || fieldType == 'file') {
                              if (extraFieldFiles[fieldName] == null) {
                                dialogSetState(() {
                                  extraFieldErrors[fieldName] = 'Ce champ est requis';
                                });
                                allRequiredFieldsFilled = false;
                              } else {
                                dialogSetState(() {
                                  extraFieldErrors[fieldName] = null;
                                });
                              }
                            } else if (extraFieldValues[fieldName]?.isEmpty ?? true) {
                              dialogSetState(() {
                                extraFieldErrors[fieldName] = 'Ce champ est requis';
                              });
                              allRequiredFieldsFilled = false;
                            } else {
                              dialogSetState(() {
                                extraFieldErrors[fieldName] = null;
                              });
                            }
                          }

                          if (fieldType == 'integer' && extraFieldValues[fieldName]?.isNotEmpty == true) {
                            if (!integerPattern.hasMatch(extraFieldValues[fieldName]!)) {
                              dialogSetState(() {
                                extraFieldErrors[fieldName] = 'Veuillez entrer un nombre entier valide';
                              });
                              allNumericFieldsValid = false;
                            } else {
                              dialogSetState(() {
                                extraFieldErrors[fieldName] = null;
                              });
                            }
                          } else if (fieldType == 'float' && extraFieldValues[fieldName]?.isNotEmpty == true) {
                            if (!floatPattern.hasMatch(extraFieldValues[fieldName]!)) {
                              dialogSetState(() {
                                extraFieldErrors[fieldName] = 'Veuillez entrer un nombre décimal valide';
                              });
                              allNumericFieldsValid = false;
                            } else {
                              dialogSetState(() {
                                extraFieldErrors[fieldName] = null;
                              });
                            }
                          } else if (fieldType == 'Link' && extraFieldValues[fieldName]?.isNotEmpty == true) {
                            if (!urlPattern.hasMatch(extraFieldValues[fieldName]!)) {
                              dialogSetState(() {
                                extraFieldErrors[fieldName] = 'Veuillez entrer un lien valide';
                              });
                              allNumericFieldsValid = false;
                            } else {
                              dialogSetState(() {
                                extraFieldErrors[fieldName] = null;
                              });
                            }
                          }
                        }
                      }

                      if (allRequiredFieldsFilled && allNumericFieldsValid) {
                        Navigator.of(context).pop();
                        await _joinSession(sessionId, selectedLocales[sessionId] ?? '', note, extraFieldValues, extraFieldFiles);
                        extraFieldControllers.forEach((key, controller) => controller.dispose());
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF1A003D) : theme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      elevation: 4,
                    ),
                    child: Text(
                      'Rejoindre la session',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: GoogleFonts.poppins().fontFamily,
                        color: Colors.white,
                      ) ??
                          TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                            color: Colors.white,
                          ),
                    ),
                  ),
                ],
                actionsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: isDark ? theme.dialogBackgroundColor : Colors.white,
                elevation: 6,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _joinSession(
      String sessionId, String selectedLocal, String? note, Map<String, String> extraFieldValues, Map<String, XFile?> extraFieldFiles) async {
    if (hasRegistered[sessionId] == true) {
      return;
    }

    setState(() {
      hasRegistered[sessionId] = true;
    });

    final selectedSession = widget.sessions.firstWhere((session) => session['id'] == sessionId, orElse: () => {});
    final dynamic selectedLocalData = (selectedSession['local'] as List<dynamic>?)?.firstWhere(
          (local) => local['localName']?.toString() == selectedLocal,
      orElse: () => null,
    );
    final String localId = selectedLocalData?['localId']?.toString() ?? '0';
    developer.log(
        'Sending registration: sessionId=$sessionId, selectedLocal=$selectedLocal, localId=$localId, note=$note, extraFields=$extraFieldValues, files=$extraFieldFiles',
        name: 'SessionDetailPage');

    var registerRequest = http.MultipartRequest('POST', Uri.parse('${widget.apiUrl}/api/register-session'))
      ..headers['Authorization'] = 'Bearer ${widget.token}'
      ..headers['Accept'] = 'application/json';

    registerRequest.fields['sessionId'] = sessionId;
    registerRequest.fields['localId'] = localId;
    registerRequest.fields['localName'] = selectedLocal;
    if (note != null && note.isNotEmpty) {
      registerRequest.fields['note'] = note;
    }
    extraFieldValues.forEach((key, value) {
      if (value.isNotEmpty && extraFieldFiles[key] == null) {
        registerRequest.fields[key] = value;
      }
    });

    try {
      final registerResponse = await registerRequest.send();
      final registerRespStr = await registerResponse.stream.bytesToString();
      developer.log('API Response (register-session): ${registerResponse.statusCode} - $registerRespStr', name: 'SessionDetailPage');

      if (registerResponse.statusCode == 200) {
        await _saveRegistrationStatus(sessionId);

        if (selectedSession['extraSession'] == true && selectedSession['extraData'] != null) {
          var extraDataRequest = http.MultipartRequest('POST', Uri.parse('${widget.apiUrl}/api/save-extra-data-session'))
            ..headers['Authorization'] = 'Bearer ${widget.token}'
            ..headers['Accept'] = 'application/json';

          extraDataRequest.fields['sessionId'] = sessionId;

          (selectedSession['extraData'] as List<dynamic>).asMap().forEach((index, field) {
            final fieldName = field['name']?.toString() ?? '';
            final fieldType = field['type']?.toString() ?? 'string';
            if (extraFieldFiles[fieldName] != null && (fieldType == 'image' || fieldType == 'file')) {
              extraDataRequest.files.add(
                http.MultipartFile.fromBytes(
                  'extraData[$index][value]',
                  File(extraFieldFiles[fieldName]!.path).readAsBytesSync(),
                  filename: extraFieldFiles[fieldName]!.name,
                ),
              );
              extraDataRequest.fields['extraData[$index][name]'] = fieldName;
              extraDataRequest.fields['extraData[$index][type]'] = fieldType;
            } else if (extraFieldValues[fieldName]?.isNotEmpty ?? false) {
              extraDataRequest.fields['extraData[$index][name]'] = fieldName;
              extraDataRequest.fields['extraData[$index][type]'] = fieldType;
              extraDataRequest.fields['extraData[$index][value]'] = extraFieldValues[fieldName]!;
            }
          });

          final extraDataResponse = await extraDataRequest.send();
          final extraDataRespStr = await extraDataResponse.stream.bytesToString();
          developer.log('API Response (save-extra-data-session): ${extraDataResponse.statusCode} - $extraDataRespStr', name: 'SessionDetailPage');

          if (extraDataResponse.statusCode != 200) {
            final decodedError = jsonDecode(extraDataRespStr);
            setState(() {
              hasRegistered[sessionId] = false;
            });
            await _removeRegistrationStatus(sessionId);
            SnackBarHelper.showError(
              context,
              'Échec de l\'enregistrement des données supplémentaires: ${decodedError['message'] ?? extraDataRespStr}',
            );
            return;
          }
        }

        final decodedResponse = jsonDecode(registerRespStr);
        showDialog(
          context: context,
          builder: (BuildContext context) {
            final theme = Theme.of(context);
            return AlertDialog(
              title: Text(
                'Succès',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  color: Colors.green[700],
                ) ??
                    TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                      fontFamily: GoogleFonts.poppins().fontFamily,
                    ),
              ),
              content: Text(
                'Votre demande d\'inscription pour cette session a été envoyée avec succès.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ) ??
                    TextStyle(
                      fontSize: 16,
                      fontFamily: GoogleFonts.poppins().fontFamily,
                    ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF1A003D) : Colors.green[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    elevation: 2,
                  ),
                  child: Text(
                    'Fermer',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: GoogleFonts.poppins().fontFamily,
                    ) ??
                        TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: GoogleFonts.poppins().fontFamily,
                        ),
                  ),
                ),
              ],
              actionsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: theme.dialogBackgroundColor,
              elevation: 6,
            );
          },
        );
      } else {
        final decodedError = jsonDecode(registerRespStr);
        setState(() {
          hasRegistered[sessionId] = false;
        });
        await _removeRegistrationStatus(sessionId);
        SnackBarHelper.showError(
          context,
          'Échec de l\'inscription: ${decodedError['message'] ?? registerRespStr}',
        );
      }
    } catch (e) {
      developer.log('Error during registration: $e', name: 'SessionDetailPage');
      setState(() {
        hasRegistered[sessionId] = false;
      });
      await _removeRegistrationStatus(sessionId);
      SnackBarHelper.showError(
        context,
        'Erreur lors de l\'inscription: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "Détails des sessions",
          style: theme.textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontFamily: GoogleFonts.poppins().fontFamily,
          ) ??
              TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
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
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
          : errorMessage != null
          ? Center(
        child: Text(
          errorMessage!,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.red[700],
            fontFamily: GoogleFonts.poppins().fontFamily,
          ) ??
              TextStyle(
                color: Colors.red[700],
                fontSize: 16,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
        ),
      )
          : Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                PageView.builder(
              controller: _pageController,
              itemCount: widget.sessions.length,
              onPageChanged: (index) => setState(() => _currentPageIndex = index),
              itemBuilder: (context, index) {
                final session = widget.sessions[index];
                developer.log('Rendering card for session: ${session['sessionName']}', name: 'SessionDetailPage');
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              margin: const EdgeInsets.only(bottom: 16),
              color: theme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: theme.shadowColor.withOpacity(0.3),
                              spreadRadius: 2,
                              blurRadius: 5,
                            ),
                          ],
                        ),
                        child: session['image'] != null && session['image'].isNotEmpty
                            ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image(
                            image: AuthenticatedNetworkImageProvider(
                              'https://www.unistudious.com/api/public-image-server/${session['image']}',
                              token: widget.token,
                            ),
                            height: 200,
                            width: 300,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Center(
                              child: Image.asset(
                                'assets/session.png',
                                height: 200,
                                width: 300,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        )
                            : Center(
                          child: Image.asset(
                            'assets/session.png',
                            height: 200,
                            width: 300,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  const Color(0xFF2D1B4E).withOpacity(0.9),
                                  const Color(0xFF1A003D).withOpacity(0.7),
                                ]
                              : [
                                  theme.primaryColor.withOpacity(0.15),
                                  theme.primaryColor.withOpacity(0.06),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: theme.primaryColor.withOpacity(0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        session['sessionName']?.isNotEmpty == true ? session['sessionName'] : 'Unnamed Session',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontFamily: GoogleFonts.poppins().fontFamily,
                          color: isDark ? Colors.white : theme.primaryColor,
                          letterSpacing: 0.3,
                        ) ??
                            TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : theme.primaryColor,
                              fontFamily: GoogleFonts.poppins().fontFamily,
                              letterSpacing: 0.3,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _infoRow(Icons.menu_book, "Formation", session['formationName']),
                        _infoRow(Icons.event, "Début", session['startDate']),
                        _infoRow(Icons.event, "Fin", session['endDate']),
                        _infoRow(Icons.account_balance, "Compte", session['accountName'] ?? 'Piuma Academy'),
                        _infoRow(Icons.payment, "Méthode de paiement", session['typePay']),
                        _infoRow(Icons.group, "Capacité", session['capacity']?.toString()),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDark
                                ? [
                                    Colors.white.withOpacity(0.1),
                                    Colors.white.withOpacity(0.04),
                                  ]
                                : [
                                    Colors.white,
                                    Colors.grey.shade50,
                                  ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: theme.primaryColor.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.location_on_rounded,
                                size: 18,
                                color: isDark ? Colors.white : theme.primaryColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Local: ${selectedLocales[session['id']]?.toString() ?? 'Non sélectionné'}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontFamily: GoogleFonts.poppins().fontFamily,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : theme.textTheme.bodyLarge?.color,
                                letterSpacing: 0.2,
                              ) ??
                                  TextStyle(
                                    fontSize: 14,
                                    fontFamily: GoogleFonts.poppins().fontFamily,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black87,
                                    letterSpacing: 0.2,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Divider(color: theme.dividerColor, thickness: 1),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: hasRegistered[session['id']] == true
                              ? null
                              : () {
                            if (!isLoading && session.isNotEmpty) {
                              _showJoinConfirmation(session['id']);
                            }
                          },
                          icon: const Icon(Icons.add, size: 20),
                          label: Text(
                            hasRegistered[session['id']] == true
                                ? "Attendre d'acceptation"
                                : "S'inscrire maintenant",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: hasRegistered[session['id']] == true
                                ? Colors.orange
                                : isDark
                                ? const Color(0xFF1A003D)
                                : theme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            elevation: 6,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
                );
              },
            ),
                if (widget.sessions.length > 1) ...[
                  if (_currentPageIndex > 0)
                    Positioned(
                      left: 4,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () => _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: theme.cardColor.withOpacity(0.9),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.chevron_left,
                              size: 20,
                              color: theme.primaryColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_currentPageIndex < widget.sessions.length - 1)
                    Positioned(
                      right: 4,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () => _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: theme.cardColor.withOpacity(0.9),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: theme.primaryColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (widget.sessions.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.sessions.length, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPageIndex == index ? 10 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPageIndex == index
                          ? theme.primaryColor
                          : theme.primaryColor.withOpacity(0.3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
