import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../models/bottom_navigation_provider.dart';
import '../screens/main_navigation_page.dart';

class AppSidebar extends StatefulWidget {
  const AppSidebar({super.key});

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Charger immédiatement les données en cache et afficher le sidebar
    _loadCachedDataAndShow();
    // Charger les données à jour en arrière-plan
    _checkAuthAndFetchData();
  }

  // Charger les données en cache immédiatement pour afficher le sidebar rapidement
  Future<void> _loadCachedDataAndShow() async {
    if (!mounted) return;
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (!authProvider.isLoggedIn) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.')),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      // Appliquer les données en cache immédiatement (sans attendre)
      unawaited(_applyCachedUser());
      
      // Afficher le sidebar immédiatement sans attendre les appels API
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erreur lors de la récupération du token : $e';
          _isLoading = false;
        });
      }
    }
  }

  // Charger les données à jour en arrière-plan (sans bloquer l'affichage)
  Future<void> _checkAuthAndFetchData() async {
    if (!mounted) return;
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (!authProvider.isLoggedIn) {
        return;
      }

      // Charger les données à jour en arrière-plan sans bloquer l'UI
      unawaited(_fetchProfileData());
      unawaited(_checkSessionStatus());
    } catch (e) {
      // Erreurs silencieuses en arrière-plan
      developer.log('Error in background data fetch: $e', name: 'AppSidebar');
    }
  }

  Future<void> _applyCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedName = prefs.getString('cached_user_name') ?? '';
    final cachedImageUrl = prefs.getString('cached_user_image_url') ?? '';
    if ((cachedName.isNotEmpty || cachedImageUrl.isNotEmpty) && mounted) {
      final userModel = Provider.of<UserModel>(context, listen: false);
      userModel.updateUser(name: cachedName, imageUrl: cachedImageUrl);
    }
  }

  Future<void> _checkSessionStatus() async {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      final response = await authProvider.authenticatedRequest(
        'GET',
        '/api/user/get-session',
      );

      if (!mounted) return;
      final userModel = Provider.of<UserModel>(context, listen: false);
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final sessions = jsonResponse['sessions'] as List<dynamic>? ?? [];
        userModel.hasActiveSession = sessions.isNotEmpty;
      } else {
        userModel.hasActiveSession = false;
        if (response.statusCode == 401 || response.statusCode == 403) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.')),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } catch (e) {
      if (!mounted) return;
      final userModel = Provider.of<UserModel>(context, listen: false);
      userModel.hasActiveSession = false;
      
      // Détecter les erreurs de connexion et ne pas afficher de snackbar
      final isNetworkError = e is SocketException || 
                             e.toString().contains('SocketException') ||
                             e.toString().contains('Failed host lookup') ||
                             e.toString().contains('Network is unreachable') ||
                             e.toString().contains('Connection refused') ||
                             e.toString().contains('Connection timed out') ||
                             e.toString().contains('No Internet connection');
      
      // Ne pas afficher de snackbar pour les erreurs de connexion
      if (!isNetworkError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la vérification de la session : $e')),
        );
      }
    }
  }

  Future<String?> _fetchProfileImage(String filename) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.isLoggedIn || filename.isEmpty) return null;

    try {
      final response = await authProvider.authenticatedRequest(
        'POST',
        '/api/private-image-server/$filename',
      );

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.startsWith('image/')) {
          final base64Image = base64Encode(response.bodyBytes);
          return 'data:$contentType;base64,$base64Image';
        } else {
          final jsonResponse = jsonDecode(response.body);
          return jsonResponse['url'] as String? ?? '';
        }
      } else {
        if (response.statusCode == 401 || response.statusCode == 403) {
          if (!mounted) return null;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.')),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
        // Ne pas afficher de snackbar pour les autres erreurs (404, etc.)
        return null;
      }
    } catch (e) {
      if (!mounted) return null;
      // Ne pas afficher de snackbar pour les erreurs de chargement d'image
      return null;
    }
  }

  Future<void> _fetchProfileData() async {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final _token = authProvider.token;

    if (_token == null) {
      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }

    try {
      final response = await authProvider.authenticatedRequest(
        'GET',
        '/api/my-profile',
      );

      if (!mounted) return;
      
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final data = jsonResponse['data_profile'] as Map<String, dynamic>? ?? {};
        final filename = data['url_image'] as String? ?? '';
        String? imageUrl;
        if (filename.isNotEmpty) {
          imageUrl = await _fetchProfileImage(filename);
        }

        if (!mounted) return;
        final userModel = Provider.of<UserModel>(context, listen: false);
        userModel.updateUser(
          name: data['full_name'] as String? ?? '',
          imageUrl: imageUrl ?? '',
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_user_name', userModel.name);
        await prefs.setString('cached_user_image_url', userModel.imageUrl);

        final newToken = jsonResponse['token'] ??
            jsonResponse['new_token'] ??
            jsonResponse['access_token'] ??
            response.headers['authorization']?.replaceFirst('Bearer ', '') ??
            '';
        if (newToken.isNotEmpty) {
          await authProvider.saveToken(newToken);
        }
      } else {
        if (!mounted) return;
        final isAuth = response.statusCode == 401 || response.statusCode == 403;
        // Ne pas afficher de snackbar pour les erreurs de chargement du profil
        // Seulement rediriger vers login si session expirée
        if (isAuth && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.')),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } catch (e) {
      if (!mounted) return;
      // Ne pas afficher de snackbar pour les erreurs de récupération du profil
      // Les erreurs sont silencieuses pour ne pas perturber l'utilisateur
    }
  }

  void _retryProfile() {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _fetchProfileData().whenComplete(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _go(String routeName) {
    if (!mounted) return;
    final provider = Provider.of<BottomNavigationProvider>(context, listen: false);
    // Map of sidebar routes to bottom navigation indices
    const routeToIndexMap = {
      '/dashboard': 0,
      '/mes-cours': 1,
      '/fil-social': 2,
      '/ressources': 3,
      '/profile': 4,
    };

    Navigator.pop(context); // Close the sidebar

    // Update the bottom navigation index if the route is mapped
    final newIndex = routeToIndexMap[routeName];
    if (newIndex != null) {
      // Pour les routes de la bottom bar, utiliser MainNavigationPage
      provider.updateIndex(newIndex);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigationPage()),
      );
    } else {
      // Pour les autres routes, utiliser la navigation normale
      Navigator.pushReplacementNamed(context, routeName);
    }
  }

  void _showLogoutConfirmation(BuildContext context) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () {
              if (!mounted) return;
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              if (!mounted) return;
              Navigator.of(context).pop();
              _performLogout(context);
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  void _performLogout(BuildContext context) {
    try {
      Provider.of<UserModel>(context, listen: false).updateUser(
        name: '',
        email: '',
        imageUrl: '',
        hasActiveSession: false,
      );
      Provider.of<AuthProvider>(context, listen: false).logout();
      Provider.of<BottomNavigationProvider>(context, listen: false).updateIndex(0); // Reset bottom nav index
      Navigator.pushReplacementNamed(context, '/welcome');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la déconnexion : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = isDark ? Colors.deepPurple : Colors.deepPurple;
    final currentRoute = ModalRoute.of(context)?.settings.name;

    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      child: Container(
        color: theme.scaffoldBackgroundColor,
        child: Consumer<UserModel>(
          builder: (context, userModel, _) {
            return Column(
              children: [
                _HeaderCard(
                  color: color,
                  name: userModel.name,
                  imageUrl: userModel.imageUrl,
                  theme: theme,
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
                      else if (Provider.of<AuthProvider>(context).isLoggedIn) ...[
                        _UserProfileCard(
                          name: userModel.name,
                          imageUrl: userModel.imageUrl,
                          theme: theme,
                        ),
                        _SectionHeader('Principal', theme),
                        _SidebarTile(
                          icon: Icons.home_outlined,
                          label: 'Tableau de bord',
                          color: color,
                          onTap: () => _go('/dashboard'),
                          theme: theme,
                          isActive: currentRoute == '/dashboard',
                        ),
                        _SidebarTile(
                          icon: Icons.book_outlined,
                          label: 'Mes cours',
                          color: color,
                          onTap: () => _go('/mes-cours'),
                          theme: theme,
                          isActive: currentRoute == '/mes-cours',
                        ),
                        _SidebarTile(
                          icon: Icons.add_circle_outlined,
                          label: 'Rejoindre une session',
                          color: color,
                          onTap: () => _go('/join-session'),
                          theme: theme,
                          isActive: currentRoute == '/join-session',
                        ),
                        _SectionHeader('Ressources', theme),
                        _SidebarTile(
                          icon: Icons.folder_copy_outlined,
                          label: 'Ressources',
                          color: color,
                          onTap: () => _go('/ressources'),
                          theme: theme,
                          isActive: currentRoute == '/ressources',
                        ),
                        _SidebarTile(
                          icon: Icons.menu_book_outlined,
                          label: 'Cours gratuits',
                          color: color,
                          onTap: () => _go('/free-resource'),
                          theme: theme,
                          isActive: currentRoute == '/free-resource',
                        ),
                        _SectionHeader('Communication', theme),
                        _SidebarTile(
                          icon: Icons.message_outlined,
                          label: 'Messagerie',
                          color: color,
                          onTap: () => _go('/messagerie'),
                          theme: theme,
                          isActive: currentRoute == '/messagerie',
                        ),
                        _SidebarTile(
                          icon: Icons.people_outline,
                          label: 'Fil Social',
                          color: color,
                          onTap: () => _go('/fil-social'),
                          theme: theme,
                          isActive: currentRoute == '/fil-social',
                        ),
                        _SidebarTile(
                          icon: Icons.family_restroom_outlined,
                          label: 'Invitations Parents',
                          color: color,
                          onTap: () => _go('/parent-invitations'),
                          theme: theme,
                          isActive: currentRoute == '/parent-invitations',
                        ),
                        if (userModel.hasActiveSession) ...[
                          _SectionHeader('Sessions', theme),
                          _SidebarTile(
                            icon: Icons.calendar_today_outlined,
                            label: 'Calendrier',
                            color: color,
                            onTap: () => _go('/calendrier'),
                            theme: theme,
                            isActive: currentRoute == '/calendrier',
                          ),
                          _SidebarTile(
                            icon: Icons.checklist_outlined,
                            label: 'Présences',
                            color: color,
                            onTap: () => _go('/presences'),
                            theme: theme,
                            isActive: currentRoute == '/presences',
                          ),
                          _SidebarTile(
                            icon: Icons.group_outlined,
                            label: 'Groupes',
                            color: color,
                            onTap: () => _go('/groups'),
                            theme: theme,
                            isActive: currentRoute == '/groups',
                          ),
                          _SidebarTile(
                            icon: Icons.video_call_outlined,
                            label: 'Cours en ligne',
                            color: color,
                            onTap: () => _go('/list-meet'),
                            theme: theme,
                            isActive: currentRoute == '/list-meet',
                          ),
                          _SidebarTile(
                            icon: Icons.receipt_long_outlined,
                            label: 'Factures',
                            color: color,
                            onTap: () => _go('/invoices'),
                            theme: theme,
                            isActive: currentRoute == '/invoices',
                          ),
                        ],
                        _SectionHeader('Paramètres', theme),
                        _SidebarTile(
                          icon: Icons.qr_code_scanner_outlined,
                          label: 'Scanner QR Code',
                          color: color,
                          onTap: () => _go('/qr-scanner'),
                          theme: theme,
                          isActive: currentRoute == '/qr-scanner',
                        ),
                        _SidebarTile(
                          icon: Icons.settings_outlined,
                          label: 'Paramètres',
                          color: color,
                          onTap: () => _go('/parametres'),
                          theme: theme,
                          isActive: currentRoute == '/parametres',
                        ),
                        _SidebarTile(
                          icon: Icons.logout_outlined,
                          label: 'Déconnexion',
                          color: Colors.red,
                          iconColor: const Color(0xFFFF0631),
                          onTap: () => _showLogoutConfirmation(context),
                          theme: theme,
                          isActive: false,
                        ),
                      ] else ...[
                        _SectionHeader('Session', theme),
                        _SidebarTile(
                          icon: Icons.add_circle_rounded,
                          label: 'Rejoindre une nouvelle session',
                          color: color,
                          onTap: () => _go('/join-session'),
                          theme: theme,
                          isActive: currentRoute == '/join-session',
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Color color;
  final String name;
  final String imageUrl;
  final ThemeData theme;

  const _HeaderCard({
    required this.color,
    required this.name,
    required this.imageUrl,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final avatarProvider = _resolveAvatar(imageUrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          height: 110,
          padding: const EdgeInsets.only(left: 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF1A003D), Color(0xFF3C0D73)]
                  : const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OverflowBox(
              maxHeight: 200,
              child: Image.asset(
                'assets/log.png',
                height: 300,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ],
    );
  }

  ImageProvider<Object>? _resolveAvatar(String url) {
    if (url.isEmpty) return null;
    try {
      if (url.startsWith('data:image/')) {
        final base64Part = url.split(',').last;
        return MemoryImage(base64Decode(base64Part));
      }
      return NetworkImage(url);
    } catch (_) {
      return null;
    }
  }
}

class _UserProfileCard extends StatelessWidget {
  final String name;
  final String imageUrl;
  final ThemeData theme;

  const _UserProfileCard({
    required this.name,
    required this.imageUrl,
    required this.theme,
  });

  ImageProvider<Object>? _resolveAvatar(String url) {
    if (url.isEmpty) return null;
    try {
      if (url.startsWith('data:image/')) {
        final base64Part = url.split(',').last;
        return MemoryImage(base64Decode(base64Part));
      }
      return NetworkImage(url);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final avatarProvider = _resolveAvatar(imageUrl);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? Colors.deepPurple.shade400 : Colors.deepPurple,
                width: 2,
              ),
            ),
            child: ClipOval(
              child: avatarProvider != null
                  ? Image(
                      image: avatarProvider,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                          child: Icon(
                            Icons.person,
                            size: 32,
                            color: isDark ? Colors.white70 : Colors.grey.shade600,
                          ),
                        );
                      },
                    )
                  : Container(
                      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                      child: Icon(
                        Icons.person,
                        size: 32,
                        color: isDark ? Colors.white70 : Colors.grey.shade600,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : 'Utilisateur',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Bienvenue',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader(this.title, this.theme);

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white70 : Colors.grey.shade700,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color? iconColor;
  final VoidCallback onTap;
  final bool isActive;
  final ThemeData theme;

  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isActive = false,
    this.iconColor,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? color.withOpacity(0.25) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: iconColor ?? (isActive ? color : (isDark ? Colors.white70 : Colors.black87)),
          size: 22,
        ),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            color: isActive ? color : (isDark ? Colors.white : Colors.black87),
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        onTap: onTap,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
    );
  }
}