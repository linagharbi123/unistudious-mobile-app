import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:html/parser.dart' show parse;
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import '../providers/auth_provider.dart';
import '../providers/loading_provider.dart';
import '../models/app_bar_provider.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/loading_wrapper.dart';
import '../widgets/sidebar.dart';
import 'profile_page.dart';
import 'favorites_page.dart';
import 'statistics_page.dart';
import 'profile_posts_pins_page.dart';
import 'settings_page.dart';
import '../utils/connection_checker.dart';
import '../services/page_cache_service.dart';


class ProfilePageBottomNav extends StatefulWidget {
  const ProfilePageBottomNav({super.key});

  @override
  _ProfilPageBottomNavState createState() => _ProfilPageBottomNavState();
}

class _ProfilPageBottomNavState extends State<ProfilePageBottomNav> {
  String? _fullName;
  String? _email;
  String? _aboutMe;
  int? _coursesFollowed;
  double? _progress;
  int? _badgesEarned;
  int? _studyHours;
  String? _imageUrl;
  Map<String, Map<String, dynamic>> _badges = {};
  List<Map<String, dynamic>> _sessions = [];
  String? _errorMessage;
  bool isConnectionError = false;
  bool isLoading = true;
  Timer? _connectionCheckTimer;

  final List<Color> themeColors = [
    Colors.deepPurple,
    Colors.blueAccent,
    Colors.amber,
    Colors.teal,
    Colors.redAccent,
    Colors.indigo,
  ];

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _startConnectionMonitoring();
    
    // Configurer l'AppBar via le provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final appBarProvider = Provider.of<AppBarProvider>(context, listen: false);
        appBarProvider.updateConfig(4, AppBarConfig(
          title: 'Mon Profil',
        ));
      }
      _checkAuthAndFetchData();
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
            _fetchProfileData();
          }
        });
      }
    });
  }

  Future<void> _loadFromCache() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final cached = await PageCacheService.load(
      'profile',
      userToken: authProvider.currentToken,
    );
    if (cached == null || !mounted) return;

    setState(() {
      _fullName = cached['fullName'] as String?;
      _email = cached['email'] as String?;
      _aboutMe = cached['aboutMe'] as String?;
      _coursesFollowed = (cached['coursesFollowed'] as num?)?.toInt();
      _progress = (cached['progress'] as num?)?.toDouble();
      _badgesEarned = (cached['badgesEarned'] as num?)?.toInt();
      _studyHours = (cached['studyHours'] as num?)?.toInt();
      _badges = (cached['badges'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)),
          ) ??
          {};
      _sessions = (cached['sessions'] as List?)
              ?.map((s) => Map<String, dynamic>.from(s as Map))
              .toList() ??
          [];
      _imageUrl = cached['imageUrl'] as String?;
      _errorMessage = null;
      isLoading = false;
    });
  }

  Future<void> _checkAuthAndFetchData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      setState(() {
        isConnectionError = false;
        isLoading = true;
      });

      if (!authProvider.isLoggedIn) {
        SnackBarHelper.showWarning(context, 'Veuillez vous connecter pour continuer.');
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      await _loadFromCache();
      if (mounted && _fullName == null) {
        setState(() => isLoading = true);
      }
      await _fetchProfileData();
    } catch (e) {
      if (mounted) {
        // Détecter les erreurs de connexion
        final isNetworkError = e is SocketException || 
                               e.toString().contains('SocketException') ||
                               e.toString().contains('Failed host lookup') ||
                               e.toString().contains('Network is unreachable') ||
                               e.toString().contains('Connection refused') ||
                               e.toString().contains('Connection timed out') ||
                               e.toString().contains('No Internet connection') ||
                               e.toString().contains('ClientException') ||
                               e.toString().contains('OS Error');
        
        setState(() {
          if (isNetworkError) {
            isConnectionError = true;
            _errorMessage = null;
          } else {
            isConnectionError = false;
            _errorMessage = 'Erreur lors du chargement des données : $e';
          }
        });
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
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
          return jsonResponse['url'] as String?;
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        if (mounted) {
          SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
          Navigator.pushReplacementNamed(context, '/login');
        }
        return null;
      } else {
        if (mounted) {
          SnackBarHelper.showError(context, 'Erreur lors du chargement de l\'image : ${response.statusCode}');
        }
        return null;
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur image de profil : $e');
      }
      return null;
    }
  }

  Future<String?> _fetchBadgeImage(String filename) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isLoggedIn || filename.isEmpty) return null;

    try {
      final response = await authProvider.authenticatedRequest(
        'POST',
        '/api/public-image-server/$filename',
      );

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.startsWith('image/')) {
          final base64Image = base64Encode(response.bodyBytes);
          return 'data:$contentType;base64,$base64Image';
        } else {
          final jsonResponse = jsonDecode(response.body);
          return jsonResponse['url'] as String?;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String?> _fetchSessionImage(String filename) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isLoggedIn || filename.isEmpty) return null;

    try {
      final response = await authProvider.authenticatedRequest(
        'POST',
        '/api/public-image-server/$filename',
      );

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.startsWith('image/')) {
          final base64Image = base64Encode(response.bodyBytes);
          return 'data:$contentType;base64,$base64Image';
        } else {
          final jsonResponse = jsonDecode(response.body);
          return jsonResponse['url'] as String?;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _fetchProfileData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    setState(() {
      isConnectionError = false;
    });

    if (!authProvider.isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    try {
      final responses = await Future.wait([
        authProvider.authenticatedRequest('GET', '/api/my-profile'),
        authProvider.authenticatedRequest('GET', '/api/profile-social-media'),
      ]);
      final profileResponse = responses[0];
      final socialMediaResponse = responses[1];

      if (profileResponse.statusCode == 200) {
        final jsonResponse = jsonDecode(profileResponse.body);
        final data = jsonResponse['data_profile'] ?? {};

        final badgeList = data['badge'] as List<dynamic>? ?? [];
        final badges = <String, Map<String, dynamic>>{};
        for (var badge in badgeList) {
          final name = badge['name'] as String? ?? '';
          badges[name] = {
            'count': badge['count'] as int? ?? 0,
            'image': null,
            '_imageFile': badge['image'] as String? ?? '',
          };
        }

        final sessionList = data['sessions'] as List<dynamic>? ?? [];
        final sessions = sessionList.map<Map<String, dynamic>>((session) => {
          'name': session['name'] as String? ?? '',
          'accountName': session['accountName'] as String? ?? '',
          'image': null,
          '_imageFile': session['imgLink'] as String? ?? '',
        }).toList();

        String? socialMediaAboutMe;
        if (socialMediaResponse.statusCode == 200) {
          final socialMediaJson = jsonDecode(socialMediaResponse.body);
          final socialMediaData = socialMediaJson['data'] ?? {};
          final rawAboutMe = socialMediaData['aboutMe'] as String? ?? '';
          final document = parse(rawAboutMe);
          socialMediaAboutMe = document.body?.text.trim() ?? 'Aucune description disponible';
        } else {
          socialMediaAboutMe = 'Aucune description disponible';
        }

        final profileImageFilename = data['url_image'] as String? ?? '';

        if (mounted) {
          setState(() {
            _fullName = data['full_name'] as String? ?? 'Utilisateur non défini';
            _email = data['email'] as String? ?? 'Email non défini';
            _aboutMe = socialMediaAboutMe;
            _coursesFollowed = data['total_course'] as int? ?? 0;
            _progress = (data['statistics']?['personAttendancePercentage'] as num?)?.toDouble() ?? 0.0;
            _badgesEarned = data['total_tag_assignments'] as int? ?? 0;
            _studyHours = (data['courses'] as List<dynamic>?)?.fold<int>(
              0,
                  (sum, course) => sum + ((course['nbHours'] as num?)?.toInt() ?? 0),
            ) ?? 0;
            _badges = badges;
            _sessions = sessions;
            _imageUrl = null;
            _errorMessage = null;
            isConnectionError = false;
            isLoading = false;
          });
        }

        // Images en parallèle en arrière-plan
        _loadProfileImagesInBackground(
          profileImageFilename: profileImageFilename,
          badges: badges,
          sessions: sessions,
        );

        await PageCacheService.save(
          'profile',
          {
            'fullName': _fullName,
            'email': _email,
            'aboutMe': socialMediaAboutMe,
            'coursesFollowed': data['total_course'] as int? ?? 0,
            'progress': (data['statistics']?['personAttendancePercentage'] as num?)?.toDouble() ?? 0.0,
            'badgesEarned': data['total_tag_assignments'] as int? ?? 0,
            'studyHours': (data['courses'] as List<dynamic>?)?.fold<int>(
                  0, (sum, course) => sum + ((course['nbHours'] as num?)?.toInt() ?? 0),
                ) ??
                0,
            'badges': badges.map((k, v) => MapEntry(k, {
                  'count': v['count'],
                  'image': v['image'],
                })),
            'sessions': sessions.map((s) => {
                  'name': s['name'],
                  'accountName': s['accountName'],
                  'image': s['image'],
                }).toList(),
            'imageUrl': _imageUrl,
          },
          userToken: authProvider.currentToken,
        );
      } else {
        String errorMessage;
        if (profileResponse.statusCode == 405) {
          errorMessage = 'Méthode HTTP non autorisée. Veuillez vérifier l\'API.';
        } else if (profileResponse.statusCode == 401 || profileResponse.statusCode == 403) {
          errorMessage = 'Session expirée. Veuillez vous reconnecter.';
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/login');
          }
        } else {
          errorMessage = 'Erreur : ${profileResponse.statusCode}';
        }
        if (mounted) {
          setState(() {
            _errorMessage = errorMessage;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        // Détecter les erreurs de connexion
        final isNetworkError = e is SocketException || 
                               e.toString().contains('SocketException') ||
                               e.toString().contains('Failed host lookup') ||
                               e.toString().contains('Network is unreachable') ||
                               e.toString().contains('Connection refused') ||
                               e.toString().contains('Connection timed out') ||
                               e.toString().contains('No Internet connection') ||
                               e.toString().contains('ClientException') ||
                               e.toString().contains('OS Error');
        
        setState(() {
          if (isNetworkError) {
            isConnectionError = true;
            _errorMessage = null;
          } else {
            isConnectionError = false;
            _errorMessage = 'Erreur récupération données : $e';
          }
        });
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadProfileImagesInBackground({
    required String profileImageFilename,
    required Map<String, Map<String, dynamic>> badges,
    required List<Map<String, dynamic>> sessions,
  }) async {
    final futures = <Future<void>>[];

    if (profileImageFilename.isNotEmpty) {
      futures.add(_fetchProfileImage(profileImageFilename).then((url) {
        if (mounted && url != null) setState(() => _imageUrl = url);
      }));
    }

    for (final entry in badges.entries) {
      final filename = entry.value['_imageFile'] as String? ?? '';
      if (filename.isEmpty) continue;
      final name = entry.key;
      futures.add(_fetchBadgeImage(filename).then((url) {
        if (!mounted || url == null) return;
        setState(() {
          _badges[name] = {..._badges[name]!, 'image': url};
        });
      }));
    }

    for (int i = 0; i < sessions.length; i++) {
      final filename = sessions[i]['_imageFile'] as String? ?? '';
      if (filename.isEmpty) continue;
      futures.add(_fetchSessionImage(filename).then((url) {
        if (!mounted || url == null) return;
        setState(() {
          if (i < _sessions.length) {
            final updated = Map<String, dynamic>.from(_sessions[i]);
            updated['image'] = url;
            _sessions[i] = updated;
          }
        });
      }));
    }

    await Future.wait(futures);
  }

  Future<void> _pickAndUploadProfileImage() async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;

      if (token == null || !authProvider.isLoggedIn) {
        if (!mounted) return;
        SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      final uri = Uri.parse('https://www.unistudious.com/api/update-profile-image');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token';

      request.files.add(
        await http.MultipartFile.fromPath(
          'url_image',
          pickedFile.path,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        String? message;
        try {
          final jsonResponse = jsonDecode(response.body);
          message = jsonResponse['message'] as String?;
        } catch (_) {
          message = null;
        }

        SnackBarHelper.showSuccess(context, message ?? 'Image de profil mise à jour avec succès.');

        await _fetchProfileData();
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
        Navigator.pushReplacementNamed(context, '/login');
      } else {
        SnackBarHelper.showError(context, 'Erreur lors de la mise à jour de l\'image : ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, 'Erreur lors de la mise à jour de l\'image : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LoadingWrapper(
      child: Scaffold(
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : isConnectionError
                ? _buildConnectionErrorWidget(theme)
                : _errorMessage != null
                    ? _buildErrorWidget(theme)
                    : RefreshIndicator(
                        onRefresh: _fetchProfileData,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildProfileCard(theme, isDark),
                                const SizedBox(height: 24),
                                _buildStatsCard(theme),
                                const SizedBox(height: 24),
                                _buildSectionTitle('Mes Badges', theme),
                                const SizedBox(height: 16),
                                _buildBadgesSection(theme),
                                const SizedBox(height: 24),
                                _buildSectionTitle('Mes Sessions', theme),
                                const SizedBox(height: 16),
                                _buildSessionsSection(theme),
                                const SizedBox(height: 24),
                                _buildActionTiles(theme),
                              ],
                            ),
                          ),
                        ),
                      ),
      ),
    );
  }

  Widget _buildConnectionErrorWidget(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
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
              _fetchProfileData();
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

  Widget _buildErrorWidget(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Une erreur est survenue',
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _fetchProfileData,
            child: const Text('Réessayer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(ThemeData theme, bool isDark) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: themeColors[0].withOpacity(0.8),
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark ? Colors.black54 : Colors.grey.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 70,
                    backgroundImage: _imageUrl != null && _imageUrl!.isNotEmpty
                        ? (_imageUrl!.startsWith('data:image/')
                            ? MemoryImage(base64Decode(_imageUrl!.split(',').last))
                            : NetworkImage(_imageUrl!)) as ImageProvider<Object>?
                        : null,
                    backgroundColor: theme.unselectedWidgetColor,
                    child: _imageUrl == null || _imageUrl!.isEmpty
                        ? Icon(Icons.person, size: 70, color: theme.iconTheme.color)
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Material(
                    color: theme.primaryColor,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _pickAndUploadProfileImage,
                      child: const Padding(
                        padding: EdgeInsets.all(6.0),
                        child: Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _fullName ?? 'Utilisateur non défini',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.email_outlined, size: 20, color: themeColors[1]),
                const SizedBox(width: 8),
                Text(
                  _email ?? 'Email non défini',
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _aboutMe ?? 'Aucune description disponible',
              style: TextStyle(
                fontSize: 14,
                color: theme.textTheme.bodyMedium?.color ?? Colors.grey[700],
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(ThemeData theme) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(Icons.book, '${_coursesFollowed ?? 0}', 'Cours suivis', themeColors[0], theme),
                _buildStatItem(Icons.star, '${_badgesEarned ?? 0}', 'Badges gagnés', themeColors[2], theme),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(Icons.percent, '${(_progress ?? 0.0).toStringAsFixed(0)}%', 'Progression', themeColors[5], theme),
                _buildStatItem(Icons.access_time, '${_studyHours ?? 0}h', 'Temps d\'étude', themeColors[1], theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, Color color, ThemeData theme) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: _progress != null && label == 'Progression' ? _progress! / 100 : 1.0,
              strokeWidth: 4,
              backgroundColor: color.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color, size: 28),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, ThemeData theme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
      ),
    );
  }

  Widget _buildBadgesSection(ThemeData theme) {
    return SizedBox(
      height: 120,
      child: _badges.isEmpty
          ? Center(
        child: Text(
          'Aucun badge disponible',
          style: TextStyle(
            fontSize: 16,
            color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
          ),
        ),
      )
          : ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _badges.length,
        itemBuilder: (context, index) {
          final entry = _badges.entries.elementAt(index);
          return Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: BadgeItem(
              imageUrl: entry.value['image'] as String?,
              count: entry.value['count'] as int,
              name: entry.key,
              backgroundColor: themeColors[index % themeColors.length],
              theme: theme,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionsSection(ThemeData theme) {
    return SizedBox(
      height: 140,
      child: _sessions.isEmpty
          ? Center(
        child: Text(
          'Aucune session disponible',
          style: TextStyle(
            fontSize: 16,
            color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
          ),
        ),
      )
          : ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _sessions.length,
        itemBuilder: (context, index) {
          final session = _sessions[index];
          return Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: SessionItem(
              imageUrl: session['image'] as String?,
              name: session['name'] as String,
              accountName: session['accountName'] as String,
              backgroundColor: themeColors[index % themeColors.length],
              theme: theme,
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionTiles(ThemeData theme) {
    return Column(
      children: [
        _buildActionTile(
          Icons.edit,
          'Modifier mon profil',
              () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ProfilePage()),
            );
            if (result == true && mounted) {
              final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);
              loadingProvider.showLoading();
              await _fetchProfileData();
              loadingProvider.hideLoading();
            }
          },
          themeColors[0],
          theme,
        ),
        _buildActionTile(
          Icons.article,
          'Mes publications',
              () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ProfilePostsPinsPage()),
          ),
          themeColors[0],
          theme,
        ),
        _buildActionTile(
          Icons.show_chart,
          'Mes statistiques',
              () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const StatisticsPage()),
          ),
          themeColors[0],
          theme,
        ),
        _buildActionTile(
          Icons.favorite,
          'Mes favoris',
              () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => FavoritesPage()),
          ),
          themeColors[0],
          theme,
        ),
        _buildActionTile(
          Icons.logout,
          'Déconnexion',
              () => _showLogoutConfirmation(context),
          Colors.red,
          theme,
        ),
      ],
    );
  }

  Widget _buildActionTile(IconData icon, String title, VoidCallback onTap, Color iconColor, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
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
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600]),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Déconnexion'),
          content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
          actions: [
            TextButton(
              child: const Text('Annuler'),
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: theme.colorScheme.onError,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            TextButton(
              child: const Text('Confirmer'),
              onPressed: () {
                Navigator.of(context).pop();
                _performLogout(context);
              },
              style: TextButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        );
      },
    );
  }

  void _performLogout(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.logout();
    Navigator.pushReplacementNamed(context, '/welcome');
  }
}

class BadgeItem extends StatelessWidget {
  final String? imageUrl;
  final int count;
  final String name;
  final Color backgroundColor;
  final ThemeData theme;

  const BadgeItem({
    super.key,
    required this.imageUrl,
    required this.count,
    required this.name,
    required this.backgroundColor,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: backgroundColor.withOpacity(0.1),
            boxShadow: [
              BoxShadow(
                color: backgroundColor.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 36,
            backgroundColor: Colors.transparent,
            backgroundImage: imageUrl != null && imageUrl!.isNotEmpty
                ? (imageUrl!.startsWith('data:image/')
                ? MemoryImage(base64Decode(imageUrl!.split(',').last))
                : NetworkImage(imageUrl!)) as ImageProvider<Object>?
                : null,
            child: imageUrl == null || imageUrl!.isEmpty
                ? Icon(Icons.star_border, color: theme.colorScheme.onPrimary, size: 32)
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        if (count > 1)
          Text(
            'x$count',
            style: TextStyle(
              fontSize: 12,
              color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
            ),
          ),
      ],
    );
  }
}

class SessionItem extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final String accountName;
  final Color backgroundColor;
  final ThemeData theme;

  const SessionItem({
    super.key,
    required this.imageUrl,
    required this.name,
    required this.accountName,
    required this.backgroundColor,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: backgroundColor.withOpacity(0.1),
            boxShadow: [
              BoxShadow(
                color: backgroundColor.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 36,
            backgroundColor: Colors.transparent,
            backgroundImage: imageUrl != null && imageUrl!.isNotEmpty
                ? (imageUrl!.startsWith('data:image/')
                ? MemoryImage(base64Decode(imageUrl!.split(',').last))
                : NetworkImage(imageUrl!)) as ImageProvider<Object>?
                : const AssetImage('assets/session.png'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 100,
          child: Text(
            name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        SizedBox(
          width: 100,
          child: Text(
            accountName,
            style: TextStyle(
              fontSize: 12,
              color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

extension IterableExtension<T> on Iterable<T> {
  Iterable<E> mapIndexed<E>(E Function(int index, T element) f) {
    var index = 0;
    return map((element) => f(index++, element));
  }
}