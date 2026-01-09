import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:async';
import '../utils/snackbar_helper.dart';
import '../utils/connection_checker.dart';
import 'user_posts_page.dart';

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool isConnectionError = false;
  Timer? _connectionCheckTimer;

  @override
  void initState() {
    super.initState();
    _startConnectionMonitoring();
    _fetchBlockedUsers();
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
            _fetchBlockedUsers();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _connectionCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchBlockedUsers() async {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Session expirée. Veuillez vous reconnecter.';
      });
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      isConnectionError = false;
    });

    try {
      final uri = Uri.parse('https://www.unistudious.com/api/list/blocks');
      developer.log('Fetching blocked users from: $uri', name: 'BlockedUsersPage');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${authProvider.currentToken}',
          'Content-Type': 'application/json',
        },
      );

      developer.log(
        'Blocked users API response: ${response.body}, status: ${response.statusCode}',
        name: 'BlockedUsersPage',
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        final List<dynamic> users = responseData['data'] ?? [];
        setState(() {
          _blockedUsers = users.cast<Map<String, dynamic>>();
          _isLoading = false;
          isConnectionError = false;
        });
        developer.log(
          'Successfully loaded ${_blockedUsers.length} blocked users',
          name: 'BlockedUsersPage',
        );
      } else {
        throw Exception(responseData['message'] ?? 'Erreur lors du chargement des utilisateurs bloqués');
      }
    } catch (e, stackTrace) {
      developer.log(
        'Error fetching blocked users: $e',
        name: 'BlockedUsersPage',
        error: e,
        stackTrace: stackTrace,
      );
      
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
          _isLoading = false;
          if (isNetworkError) {
            isConnectionError = true;
            _errorMessage = null;
          } else {
            isConnectionError = false;
            _errorMessage = 'Erreur lors du chargement: ${e.toString()}';
          }
        });
      }
    }
  }

  Future<void> _unblockUser(String accountId, String username) async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? theme.cardColor : Colors.white,
          title: Text(
            'Débloquer $username ?',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            'Cette personne pourra à nouveau voir vos publications et vous contacter.',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Annuler',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Débloquer',
                style: TextStyle(color: Colors.green),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }

    try {
      // Note: Assuming there's an unblock API endpoint
      // If not available, you may need to use the same block endpoint with different logic
      final uri = Uri.parse('https://www.unistudious.com/api/unblock/account');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['accountId'] = accountId;

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body);

      if (response.statusCode == 200 && data['success'] == true && mounted) {
        SnackBarHelper.showSuccess(context, 'Utilisateur débloqué avec succès');
        // Refresh the list
        await _fetchBlockedUsers();
      } else {
        throw Exception(data['message'] ?? 'Erreur lors du déblocage');
      }
    } catch (e) {
      developer.log('Error unblocking user: $e', name: 'BlockedUsersPage');
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors du déblocage: ${e.toString()}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Utilisateurs bloqués',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
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
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: theme.primaryColor),
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
                          _fetchBlockedUsers();
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
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _fetchBlockedUsers,
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    )
                  : _blockedUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.block,
                            size: 64,
                            color: isDark ? Colors.white54 : Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Aucun utilisateur bloqué',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Les utilisateurs que vous bloquez apparaîtront ici',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDark ? Colors.white54 : Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchBlockedUsers,
                      color: theme.primaryColor,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _blockedUsers.length,
                        itemBuilder: (context, index) {
                          final user = _blockedUsers[index];
                          final displayName = user['display_name']?.toString().trim().isNotEmpty ?? false
                              ? user['display_name']
                              : user['username'] ?? 'Utilisateur inconnu';
                          final username = user['username'] ?? '';
                          final userId = user['id']?.toString() ?? '';
                          final avatar = user['avatar']?.toString() ?? '';
                          final followersCount = user['followers_count'] ?? 0;
                          final followingCount = user['following_count'] ?? 0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            color: theme.cardColor,
                            elevation: 2,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                radius: 28,
                                backgroundImage: avatar.isNotEmpty
                                    ? NetworkImage(avatar)
                                    : null,
                                backgroundColor: theme.colorScheme.surface,
                                child: avatar.isEmpty
                                    ? Icon(
                                        Icons.person,
                                        color: theme.iconTheme.color,
                                      )
                                    : null,
                              ),
                              title: Text(
                                displayName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    '@$username',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: isDark ? Colors.white70 : Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        '$followersCount abonnés',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: isDark ? Colors.white54 : Colors.grey[500],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        '$followingCount abonnements',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: isDark ? Colors.white54 : Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert,
                                  color: theme.iconTheme.color,
                                ),
                                color: isDark ? theme.cardColor : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onSelected: (value) async {
                                  if (value == 'view_profile') {
                                    // Navigate to user profile
                                    final profileDetails = await _fetchProfileDetails(userId);
                                    if (profileDetails != null && mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => UserPostsPage(
                                            userId: userId,
                                            username: username,
                                            profileDetails: profileDetails,
                                          ),
                                        ),
                                      );
                                    } else if (mounted) {
                                      SnackBarHelper.showError(
                                        context,
                                        'Impossible de charger les détails du profil.',
                                      );
                                    }
                                  } else if (value == 'unblock') {
                                    await _unblockUser(userId, displayName);
                                  }
                                },
                                itemBuilder: (BuildContext context) => [
                                  PopupMenuItem<String>(
                                    value: 'view_profile',
                                    child: Row(
                                      children: [
                                        Icon(Icons.person, color: theme.primaryColor),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Voir le profil',
                                          style: TextStyle(
                                            fontFamily: GoogleFonts.poppins().fontFamily,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'unblock',
                                    child: Row(
                                      children: [
                                        Icon(Icons.block, color: Colors.green),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Débloquer',
                                          style: TextStyle(
                                            fontFamily: GoogleFonts.poppins().fontFamily,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  Future<Map<String, dynamic>?> _fetchProfileDetails(String userId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      return null;
    }

    final uri = Uri.parse(
        'https://www.unistudious.com/api/profile-details-social-media/$userId');
    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${authProvider.currentToken}',
          'Content-Type': 'application/json',
        },
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['data'] != null) {
        return responseData['data'];
      } else {
        return null;
      }
    } catch (e) {
      developer.log('Error fetching profile details: $e', name: 'BlockedUsersPage');
      return null;
    }
  }
}

