import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:developer' as developer;
import '../providers/auth_provider.dart';

class ChatDetailsPage extends StatefulWidget {
  final String contactName;
  final String? avatarUrl;
  final String roomId;

  const ChatDetailsPage({
    super.key,
    required this.contactName,
    this.avatarUrl,
    required this.roomId,
  });

  @override
  _ChatDetailsPageState createState() => _ChatDetailsPageState();
}

class _ChatDetailsPageState extends State<ChatDetailsPage> {
  bool _notificationsEnabled = false; // État pour Mute
  bool _isFavorite = false; // État pour Favoris
  final _jitsiMeet = JitsiMeet();
  String? currentUser;
  
  // Cache des avatars SVG parsés (username/url → Map avec color et initial)
  final Map<String, Map<String, dynamic>> _avatarSvgCache = {};
  final Map<String, Future<Map<String, dynamic>>> _avatarFutures = {};

  // --------------------------------------------------------------------------
  // Helpers pour avatars (même logique que dans MessageriePage / ChatPage)
  // --------------------------------------------------------------------------

  Future<String?> _fetchAndSanitizeSvg(String url, String username) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('image/svg')) {
        // Pas un SVG : on ne traite pas ici
        return null;
      }

      var svg = response.body;

      // Tenter de récupérer la taille du viewBox (ex: viewBox="0 0 200 200")
      double? vbWidth;
      double? vbHeight;
      final viewBoxMatch = RegExp(
        r'viewBox="\s*([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*"',
      ).firstMatch(svg);

      if (viewBoxMatch != null && viewBoxMatch.groupCount == 4) {
        try {
          vbWidth = double.parse(viewBoxMatch.group(3)!);
          vbHeight = double.parse(viewBoxMatch.group(4)!);
        } catch (_) {
          vbWidth = null;
          vbHeight = null;
        }
      }

      // Remplacer width/height en pourcentage par des valeurs numériques
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

      return svg;
    } catch (_) {
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

  // Méthode helper pour construire un avatar avec cache
  Widget _buildAvatarWidget(String? url, String username, {double size = 90, bool isDark = false}) {
    if (url == null || url.isEmpty) {
      return Icon(
        Icons.person,
        size: size * 0.55,
        color: isDark ? Colors.white70 : Colors.grey,
      );
    }

    // Avatar encodé en base64 (PNG inline)
    if (url.startsWith('data:image/png;base64,')) {
      try {
        final bytes = base64Decode(url.split(',').last);
        return ClipOval(
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: size,
            height: size,
          ),
        );
      } catch (_) {
        return Icon(
          Icons.person,
          size: size * 0.55,
          color: isDark ? Colors.white70 : Colors.grey,
        );
      }
    }

    // SVG avatar
    final isSvg = url.endsWith('.svg') ||
        url.contains('message.unistudious.com/avatar/');

    if (isSvg) {
      // Vérifier le cache
      final cacheKey = username.isNotEmpty ? username : url;
      if (_avatarSvgCache.containsKey(cacheKey)) {
        final cached = _avatarSvgCache[cacheKey]!;
        return CircleAvatar(
          radius: size / 2,
          backgroundColor: cached['color'] as Color,
          child: Text(
            cached['initial'] as String,
            style: TextStyle(
              fontSize: size * 0.38,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      }

      // Charger et mettre en cache
      if (!_avatarFutures.containsKey(cacheKey)) {
        _avatarFutures[cacheKey] = _loadAndCacheSvg(url, cacheKey);
      }

      return FutureBuilder<Map<String, dynamic>>(
        future: _avatarFutures[cacheKey],
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: SizedBox(
                width: size * 0.3,
                height: size * 0.3,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          if (snapshot.hasData) {
            final avatarStyle = snapshot.data!;
            return CircleAvatar(
              radius: size / 2,
              backgroundColor: avatarStyle['color'] as Color,
              child: Text(
                avatarStyle['initial'] as String,
                style: TextStyle(
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            );
          }

          return Icon(
            Icons.person,
            size: size * 0.55,
            color: isDark ? Colors.white70 : Colors.grey,
          );
        },
      );
    }

    // Image réseau - utiliser CachedNetworkImage
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => Center(
          child: SizedBox(
            width: size * 0.3,
            height: size * 0.3,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, url, error) => Icon(
          Icons.person,
          size: size * 0.55,
          color: isDark ? Colors.white70 : Colors.grey,
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _loadAndCacheSvg(String avatarUrl, String cacheKey) async {
    try {
      final svgData = await _fetchAndSanitizeSvg(avatarUrl, cacheKey);
      if (svgData == null || svgData.isEmpty) {
        return {'color': Colors.purple, 'initial': '?'};
      }

      final avatarStyle = _extractAvatarStyleFromSvg(svgData);
      
      // Mettre en cache
      _avatarSvgCache[cacheKey] = avatarStyle;
      
      return avatarStyle;
    } catch (e) {
      return {'color': Colors.purple, 'initial': '?'};
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadFavoriteState();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    String? cachedCurrentUser = prefs.getString('current_user');
    if (cachedCurrentUser != null) {
      setState(() {
        currentUser = cachedCurrentUser;
      });
    } else {
      await fetchCurrentUser();
    }
  }

  Future<void> _loadFavoriteState() async {
    final prefs = await SharedPreferences.getInstance();
    final isFavorite = prefs.getBool('favorite_room_${widget.roomId}') ?? false;
    if (mounted) {
      setState(() {
        _isFavorite = isFavorite;
      });
    }
  }

  Future<void> fetchCurrentUser() async {
    const endpoint = 'https://www.unistudious.com/api/chat-message';
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final response = await authProvider.authenticatedRequest('GET', endpoint).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['currentUser'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('current_user', data['currentUser']);
          if (mounted) {
            setState(() {
              currentUser = data['currentUser'];
            });
          }
        } else {
          throw Exception('Échec de la récupération de l\'utilisateur actuel.');
        }
      } else {
        throw Exception('Erreur ${response.statusCode} lors de la récupération de l\'utilisateur actuel.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la récupération de l\'utilisateur actuel : $e')),
        );
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final endpoint = _isFavorite
        ? 'https://www.unistudious.com/api/chat/not-favorite-room'
        : 'https://www.unistudious.com/api/chat/favorite-room';
    try {
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))..fields['roomId'] = widget.roomId;
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');
      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final newFavoriteState = !_isFavorite;
          setState(() {
            _isFavorite = newFavoriteState;
          });
          await prefs.setBool('favorite_room_${widget.roomId}', newFavoriteState);
        } else {
          throw Exception('Échec de la mise à jour du statut favori.');
        }
      } else {
        throw Exception('Erreur ${response.statusCode} lors de la mise à jour du statut favori.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la mise à jour du statut favori : $e')),
        );
      }
    }
  }

  Future<void> _launchCall({required bool isVideoCall}) async {
    Map<String, dynamic>? meetingData = await _startCall(isVideoCall: isVideoCall);
    if (meetingData == null || meetingData['roomName'] == null || meetingData['jwt'] == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de récupérer les données de réunion.')),
        );
      }
      return;
    }

    final String roomName = meetingData['roomName'];
    final String jwt = meetingData['jwt'];
    const String domain = 'https://meet.unistudious.com';

    try {
      final options = JitsiMeetConferenceOptions(
        serverURL: domain,
        room: roomName,
        token: jwt,
        configOverrides: {
          'startWithAudioMuted': false,
          'startWithVideoMuted': !isVideoCall,
        },
        featureFlags: {
          'welcomepage.enabled': false,
          'chat.enabled': false,
          'invite.enabled': false,
          'live-streaming.enabled': false,
          'recording.enabled': false,
          'add-people.enabled': false,
          'kick-out.enabled': false,
          'raise-hand.enabled': false,
          'tile-view.enabled': false,
          'video-share.enabled': false,
          'settings.enabled': false,
          'car-mode.enabled': false,
          'breakout-rooms.enabled': false,
          'security-options.enabled': false,
          'participants-stats.enabled': false,
          'enable-low-bandwidth-mode.enabled': false,
        },
        userInfo: JitsiMeetUserInfo(displayName: currentUser ?? 'Utilisateur', email: 'utilisateur@example.com'),
      );

      await _jitsiMeet.join(options);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la connexion à la réunion : $e')),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _startCall({required bool isVideoCall}) async {
    if (!mounted) return null;

    const endpoint = 'https://www.unistudious.com/api/chat/start-call';
    try {
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))..fields['roomId'] = widget.roomId;
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');
      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));

      if (!mounted) return null;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final message = data['data']['message'];
          
          // Déterminer le roomName
          String? roomName;
          if (data['roomId'] != null) {
            roomName = data['roomId'].toString();
            // Nettoyer le roomId (enlever "Message+" si présent)
            if (roomName.startsWith('Message+')) {
              roomName = roomName.substring(8);
            }
          } else if (message['rid'] != null) {
            roomName = message['rid'].toString();
            // Nettoyer le roomId (enlever "Message+" si présent)
            if (roomName.startsWith('Message+')) {
              roomName = roomName.substring(8);
            }
          }

          // Générer l'URL de meeting avec baseUrl + roomId + ?jwt= + jwtToken si disponible
          String? meetingUrl;
          String? jwt;
          
          if (data['baseUrl'] != null && data['jwt'] != null && roomName != null) {
            // Nouveau format: générer l'URL directement
            final baseUrl = data['baseUrl'].toString();
            jwt = data['jwt'].toString();
            // S'assurer que baseUrl se termine par /
            final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
            meetingUrl = '$cleanBaseUrl$roomName?jwt=$jwt';
          } else {
            // Ancien format: utiliser meetingUrl de la réponse
            meetingUrl = data['meetingUrl'];
            jwt = data['jwt'] ?? (meetingUrl != null && meetingUrl.contains('jwt=') ? meetingUrl.split('jwt=')[1].split('&')[0] : null);
          }

          return {'roomName': roomName, 'jwt': jwt, 'meetingUrl': meetingUrl};
        } else {
          throw Exception('Échec du lancement de l\'appel.');
        }
      } else {
        throw Exception('Erreur ${response.statusCode} lors du lancement de l\'appel.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du lancement de l\'appel : $e')),
        );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Contenu principal
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  CircleAvatar(
                    radius: 45,
                    backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                    child: _buildAvatarWidget(
                      widget.avatarUrl,
                      widget.contactName,
                      size: 90,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.contactName,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Boutons d’action (Audio, Video, Mute, Favoris)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildAction(Icons.call, "Audio", isDark, onTap: () => _launchCall(isVideoCall: false)),
                        _buildAction(Icons.videocam, "Video", isDark, onTap: () => _launchCall(isVideoCall: true)),
                        _buildAction(
                          _notificationsEnabled ? Icons.volume_up : Icons.volume_off,
                          "Mute",
                          isDark,
                          onTap: () {
                            setState(() {
                              _notificationsEnabled = !_notificationsEnabled;
                            });
                          },
                        ),
                        _buildAction(
                          _isFavorite ? Icons.favorite : Icons.favorite_border,
                          _isFavorite ? "Favori" : "Ajouter",
                          isDark,
                          color: _isFavorite ? Colors.red : (isDark ? Colors.white70 : Colors.black87),
                          onTap: _toggleFavorite, // Call the API to toggle favorite
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  _buildSectionTitle("Plus d'actions", isDark),
                  ListTile(
                    leading: Icon(Icons.file_copy, color: isDark ? Colors.white70 : Colors.black87),
                    title: Text(
                      "Afficher le fichier multimédia",
                      style: GoogleFonts.poppins(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.white70 : Colors.grey[600]),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MediaFilesPage(
                            roomId: widget.roomId,
                            contactName: widget.contactName,
                          ),
                        ),
                      );
                    },
                  ),

                  _buildSectionTitle("Confidentialité", isDark),
                  ListTile(
                    leading: Icon(Icons.notifications, color: isDark ? Colors.white70 : Colors.black87),
                    title: Text(
                      "Notifications",
                      style: GoogleFonts.poppins(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    trailing: Switch(
                      value: _notificationsEnabled,
                      onChanged: (value) {
                        setState(() {
                          _notificationsEnabled = value;
                        });
                      },
                      activeColor: Colors.deepPurple,
                      activeTrackColor: isDark ? Colors.grey[700] : Colors.grey[300],
                    ),
                    onTap: () {
                      setState(() {
                        _notificationsEnabled = !_notificationsEnabled;
                      });
                    },
                  ),
                ],
              ),
            ),

            // Bouton retour flottant
            Positioned(
              top: 10,
              left: 10,
              child: CircleAvatar(
                radius: 22,
                backgroundColor: isDark ? Colors.grey[800] : Colors.white,
                child: IconButton(
                  icon: Icon(Icons.arrow_back, color: isDark ? Colors.white70 : Colors.black87),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(IconData icon, String label, bool isDark,
      {VoidCallback? onTap, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
            child: Icon(
              icon,
              color: color ?? (isDark ? Colors.white70 : Colors.black87),
              size: 28,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 5),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.grey[600],
          ),
        ),
      ),
    );
  }
}

// ===== Page des notifications =====

class NotificationSettingsPage extends StatefulWidget {
  final bool notificationsEnabled;
  const NotificationSettingsPage({
    super.key,
    this.notificationsEnabled = false,
  });

  @override
  _NotificationSettingsPageState createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  late bool _allowNotifications;

  @override
  void initState() {
    super.initState();
    _allowNotifications = widget.notificationsEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      appBar: AppBar(
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context, _allowNotifications);
          },
        ),
        title: Text(
          "Notifications",
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: Column(
        children: [
          ListTile(
            title: Text(
              "Autoriser toutes les notifications",
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            trailing: Switch(
              value: _allowNotifications,
              onChanged: (value) {
                setState(() {
                  _allowNotifications = value;
                });
              },
              activeColor: isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0),
              activeTrackColor: isDark ? Colors.grey[700] : Colors.grey[300],
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Page des fichiers multimédias =====

class MediaFilesPage extends StatefulWidget {
  final String roomId;
  final String contactName;

  const MediaFilesPage({
    super.key,
    required this.roomId,
    required this.contactName,
  });

  @override
  _MediaFilesPageState createState() => _MediaFilesPageState();
}

class _MediaFilesPageState extends State<MediaFilesPage> {
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  Future<void> _fetchFiles() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    const endpoint = 'https://www.unistudious.com/api/chat/list-files';
    try {
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.roomId;

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');
      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            // Le format peut être data['files'] ou directement une liste
            _files = List<Map<String, dynamic>>.from(data['files'] ?? data ?? []);
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Erreur ${response.statusCode} lors du chargement des fichiers.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du chargement des fichiers : $e')),
        );
      }
    }
  }

  String _getFileType(Map<String, dynamic> file) {
    final category = file['category']?.toString().toLowerCase() ?? '';
    final type = file['type']?.toString().toLowerCase() ?? '';
    final name = file['name']?.toString().toLowerCase() ?? '';
    final url = file['url']?.toString().toLowerCase() ?? '';

    if (category == 'image' || type.contains('image') || name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') || name.endsWith('.gif') || url.contains('image')) {
      return 'image';
    } else if (category == 'video' || type.contains('video') || name.endsWith('.mp4') || name.endsWith('.mov') || name.endsWith('.avi') || url.contains('video')) {
      return 'video';
    } else if (category == 'audio' || type.contains('audio') || name.endsWith('.mp3') || name.endsWith('.wav') || name.endsWith('.m4a') || url.contains('audio')) {
      return 'audio';
    }
    return 'other';
  }

  Widget _buildFileItem(Map<String, dynamic> file, bool isDark) {
    final fileType = _getFileType(file);
    final fileName = file['name']?.toString() ?? 'Fichier sans nom';
    final fileUrl = file['url']?.toString() ?? '';
    final fileSize = file['size'] ?? 0;
    final timestamp = file['timestamp'] ?? file['uploadedAt'] ?? '';

    String formatFileSize(int bytes) {
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? Colors.grey[800] : Colors.grey[100],
      child: ListTile(
        leading: _buildFileIcon(fileType, isDark),
        title: Text(
          fileName,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fileSize > 0)
              Text(
                formatFileSize(fileSize),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
              ),
            if (timestamp.isNotEmpty)
              Text(
                timestamp,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.grey[500],
                ),
              ),
          ],
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.white70 : Colors.grey[600]),
        onTap: () => _openFile(file, fileType),
      ),
    );
  }

  Widget _buildFileIcon(String fileType, bool isDark) {
    IconData iconData;
    Color iconColor;

    switch (fileType) {
      case 'image':
        iconData = Icons.image;
        iconColor = Colors.blue;
        break;
      case 'video':
        iconData = Icons.videocam;
        iconColor = Colors.red;
        break;
      case 'audio':
        iconData = Icons.audiotrack;
        iconColor = Colors.purple;
        break;
      default:
        iconData = Icons.insert_drive_file;
        iconColor = isDark ? Colors.white70 : (Colors.grey[600] ?? Colors.grey);
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(iconData, color: iconColor, size: 24),
    );
  }

  // Helper pour obtenir l'URL complète
  String _getFullUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    return 'https://message.unistudious.com$url';
  }

  // Fonction pour télécharger les bytes d'une image via l'API
  Future<Uint8List?> _getImageBytesFromApi({
    required String fileId,
    required String fileName,
  }) async {
    const endpoint = 'https://www.unistudious.com/api/chat/read/file';

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) return null;

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['fileId'] = fileId
        ..fields['fileName'] = fileName
        ..headers['Authorization'] = 'Bearer $token';

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        final errorBody = response.body;
        developer.log('Erreur read/file pour image : ${response.statusCode} $errorBody', name: 'MediaFilesPage');
        return null;
      }
    } catch (e, s) {
      developer.log('Exception dans _getImageBytesFromApi: $e', name: 'MediaFilesPage', error: e, stackTrace: s);
      return null;
    }
  }

  // Fonction pour télécharger un fichier protégé via l'API
  Future<String?> _getPlayableFileUrl({
    required String fileId,
    required String fileName,
  }) async {
    const endpoint = 'https://www.unistudious.com/api/chat/read/file';

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) return null;

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['fileId'] = fileId
        ..fields['fileName'] = fileName
        ..headers['Authorization'] = 'Bearer $token';

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final tempDir = await getTemporaryDirectory();
        
        // Extraire l'extension du nom de fichier
        String extension = '';
        if (fileName.contains('.')) {
          extension = '.${fileName.split('.').last}';
        } else {
          // Déterminer l'extension depuis le type MIME si disponible
          final contentType = response.headers['content-type'];
          if (contentType != null) {
            if (contentType.contains('audio/mpeg') || contentType.contains('audio/mp3')) {
              extension = '.mp3';
            } else if (contentType.contains('audio')) {
              extension = '.mp3';
            } else if (contentType.contains('video/mp4')) {
              extension = '.mp4';
            } else if (contentType.contains('video')) {
              extension = '.mp4';
            } else if (contentType.contains('application/pdf')) {
              extension = '.pdf';
            } else if (contentType.contains('pdf')) {
              extension = '.pdf';
            } else if (contentType.contains('image')) {
              extension = '.jpg';
            }
          }
        }
        
        final tempFile = io.File('${tempDir.path}/chat_media_${fileId}_${DateTime.now().millisecondsSinceEpoch}$extension');
        await tempFile.writeAsBytes(bytes);
        developer.log('Fichier temporaire créé : ${tempFile.path}', name: 'MediaFilesPage');
        return tempFile.path;
      } else {
        final errorBody = response.body;
        developer.log('Erreur read/file : ${response.statusCode} $errorBody', name: 'MediaFilesPage');
        return null;
      }
    } catch (e, s) {
      developer.log('Exception dans _getPlayableFileUrl: $e', name: 'MediaFilesPage', error: e, stackTrace: s);
      return null;
    }
  }

  // Fonction pour télécharger une image protégée
  Future<Uint8List?> fetchProtectedImage(String url) async {
    try {
      final uri = Uri.parse(url);
      final hasRcToken = uri.queryParameters.containsKey('rc_token');
      final hasRcUid = uri.queryParameters.containsKey('rc_uid');

      final headers = <String, String>{};

      // Pour les URLs Rocket.Chat avec rc_token/rc_uid, ne pas ajouter de header Authorization
      if (!hasRcToken || !hasRcUid) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token') ?? '';
        if (token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      }

      final response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        return null;
      }
    } catch (e) {
      developer.log('fetchProtectedImage: exception: $e', name: 'MediaFilesPage');
      return null;
    }
  }

  Future<void> _openFile(Map<String, dynamic> file, String type) async {
    final url = file['url']?.toString() ?? '';
    final name = file['name']?.toString() ?? 'Fichier';
    final fileId = file['_id']?.toString();
    final fileType = file['type']?.toString() ?? '';
    
    developer.log('_openFile: type=$type, name=$name, fileId=$fileId, fileType=$fileType', name: 'MediaFilesPage');

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL du fichier non disponible')),
      );
      return;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (type == 'image') {
      // Pour les images, utiliser l'API /api/chat/read/file avec fileId si disponible
      if (fileId != null) {
        try {
          final bytes = await _getImageBytesFromApi(fileId: fileId, fileName: name);
          if (bytes != null && mounted) {
            final tempDir = await getTemporaryDirectory();
            final extension = name.contains('.') ? '.${name.split('.').last}' : '.jpg';
            final tempFile = io.File('${tempDir.path}/image_${DateTime.now().millisecondsSinceEpoch}$extension');
            await tempFile.writeAsBytes(bytes);
            
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _ImageViewerScreen(imageUrl: tempFile.path, isLocalFile: true),
              ),
            );
            return;
          }
        } catch (e) {
          developer.log('Error downloading image via API: $e', name: 'MediaFilesPage');
        }
      }
      
      // Fallback: essayer avec l'URL directe
      String imageUrl = url;
      if (!imageUrl.startsWith('http')) {
        imageUrl = _getFullUrl(url);
      }
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _ImageViewerScreen(imageUrl: imageUrl, isLocalFile: false),
        ),
      );
    } else if (type == 'video') {
      String? localPath;
      if (fileId != null) {
        String videoFileName = name;
        if (!videoFileName.contains('.')) {
          final fileType = file['type']?.toString() ?? '';
          if (fileType.contains('video/mp4')) {
            videoFileName = '$videoFileName.mp4';
          } else if (fileType.contains('video')) {
            videoFileName = '$videoFileName.mp4';
          } else {
            videoFileName = '$videoFileName.mp4';
          }
        }
        localPath = await _getPlayableFileUrl(fileId: fileId, fileName: videoFileName);
      } else {
        try {
          final bytes = await fetchProtectedImage(_getFullUrl(url));
          if (bytes != null && mounted) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = io.File('${tempDir.path}/video_${DateTime.now().millisecondsSinceEpoch}.mp4');
            await tempFile.writeAsBytes(bytes);
            localPath = tempFile.path;
          }
        } catch (e) {
          developer.log('Error downloading video: $e', name: 'MediaFilesPage');
        }
      }

      if (localPath != null && mounted) {
        final path = localPath;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _VideoPlayerScreen(filePath: path, isNetwork: false),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impossible de charger la vidéo')),
          );
        }
      }
    } else if (type == 'audio') {
      String? localPath;
      if (fileId != null) {
        String audioFileName = name;
        if (!audioFileName.contains('.')) {
          final fileType = file['type']?.toString() ?? '';
          if (fileType.contains('audio/mpeg') || fileType.contains('audio/mp3')) {
            audioFileName = '$audioFileName.mp3';
          } else if (fileType.contains('audio')) {
            audioFileName = '$audioFileName.mp3';
          } else {
            audioFileName = '$audioFileName.mp3';
          }
        }
        localPath = await _getPlayableFileUrl(fileId: fileId, fileName: audioFileName);
      } else {
        try {
          final bytes = await fetchProtectedImage(_getFullUrl(url));
          if (bytes != null && mounted) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = io.File('${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.mp3');
            await tempFile.writeAsBytes(bytes);
            localPath = tempFile.path;
          }
        } catch (e) {
          developer.log('Error downloading audio: $e', name: 'MediaFilesPage');
        }
      }

      if (localPath != null && mounted) {
        final path = localPath;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _AudioPlayerScreen(audioUrl: path, fileName: name, isDark: isDark),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impossible de charger l\'audio')),
          );
        }
      }
    } else {
      // Ouvrir le document (PDF)
      String? localPath;
      if (fileId != null) {
        localPath = await _getPlayableFileUrl(fileId: fileId, fileName: name);
      } else {
        try {
          final bytes = await fetchProtectedImage(_getFullUrl(url));
          if (bytes != null && mounted) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = io.File('${tempDir.path}/pdf_${DateTime.now().millisecondsSinceEpoch}.pdf');
            await tempFile.writeAsBytes(bytes);
            localPath = tempFile.path;
          }
        } catch (e) {
          developer.log('Error downloading PDF: $e', name: 'MediaFilesPage');
        }
      }

      if (localPath != null && mounted) {
        final path = localPath;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _PdfViewerScreen(filePath: path, fileName: name),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impossible de charger le PDF')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      appBar: AppBar(
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Fichiers multimédias",
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: isDark ? Colors.white70 : Colors.purple,
              ),
            )
          : _files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 64,
                        color: isDark ? Colors.white70 : Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucun fichier multimédia',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: isDark ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchFiles,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      return _buildFileItem(_files[index], isDark);
                    },
                  ),
                ),
    );
  }
}

// ==== ÉCRANS DE VISUALISATION ====
// (Copiés depuis group_info_page.dart pour la cohérence)

class _ImageViewerScreen extends StatelessWidget {
  final String imageUrl;
  final bool isLocalFile;

  const _ImageViewerScreen({required this.imageUrl, this.isLocalFile = false});

  @override
  Widget build(BuildContext context) {
    developer.log('_ImageViewerScreen.build: imageUrl = "$imageUrl"', name: 'MediaFilesPage');
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Image',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
      ),
      body: Center(
        child: _buildImageViewerContent(imageUrl, isLocalFile: isLocalFile),
      ),
    );
  }

  Widget _buildImageViewerContent(String url, {bool isLocalFile = false}) {
    // Si c'est un fichier local, l'afficher directement
    if (isLocalFile) {
      return InteractiveViewer(
        child: Image.file(
          io.File(url),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            developer.log('Error loading local image: $error', name: 'MediaFilesPage');
            return SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.white, size: 48),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Erreur lors du chargement de l\'image',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }
    
    final uri = Uri.parse(url);
    final hasRcToken = uri.queryParameters.containsKey('rc_token');
    final hasRcUid = uri.queryParameters.containsKey('rc_uid');

    // Pour les URLs avec tokens Rocket.Chat, utiliser _fetchImageBytes
    if (hasRcToken && hasRcUid) {
      return FutureBuilder<Uint8List?>(
        future: _fetchImageBytesStatic(url),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (context, url, error) {
                  developer.log(
                    '_ImageViewerScreen: Erreur lors du chargement de l\'image avec CachedNetworkImage: $error',
                    name: 'MediaFilesPage',
                  );
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.white, size: 48),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'Erreur lors du chargement de l\'image',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          }

          return InteractiveViewer(
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
            ),
          );
        },
      );
    } else {
      return FutureBuilder<Uint8List?>(
        future: _fetchImageBytesStatic(url),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.white, size: 48),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Erreur lors du chargement de l\'image',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }

          return InteractiveViewer(
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
            ),
          );
        },
      );
    }
  }

  static Future<Uint8List?> _fetchImageBytesStatic(String url) async {
    try {
      developer.log('_fetchImageBytes: URL = "$url"', name: 'MediaFilesPage');
      final uri = Uri.parse(url);
      final hasRcToken = uri.queryParameters.containsKey('rc_token');
      final hasRcUid = uri.queryParameters.containsKey('rc_uid');

      final headers = <String, String>{};

      if (!hasRcToken || !hasRcUid) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token') ?? '';
        if (token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      }

      final response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        if (response.statusCode == 403 && hasRcToken && hasRcUid) {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('auth_token') ?? '';
          if (token.isNotEmpty) {
            headers['Authorization'] = 'Bearer $token';
            final retryResponse = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 30));
            if (retryResponse.statusCode == 200) {
              return retryResponse.bodyBytes;
            }
          }
        }
      }
      return null;
    } catch (e, s) {
      developer.log('Error fetching image bytes: $e', name: 'MediaFilesPage', error: e, stackTrace: s);
      return null;
    }
  }
}

class _VideoPlayerScreen extends StatefulWidget {
  final String filePath;
  final bool isNetwork;

  const _VideoPlayerScreen({
    required this.filePath,
    this.isNetwork = false,
  });

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = widget.isNetwork
        ? VideoPlayerController.networkUrl(Uri.parse(widget.filePath))
        : VideoPlayerController.file(io.File(widget.filePath))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          _controller.play();
        }
      }).catchError((e) {
        if (mounted) {
          setState(() => _errorMessage = 'Erreur lors du chargement de la vidéo: $e');
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: _errorMessage != null
          ? Center(child: Text(_errorMessage!, style: GoogleFonts.poppins(color: Colors.white)))
          : _isInitialized
              ? Center(child: AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)))
              : const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}

class _AudioPlayerScreen extends StatefulWidget {
  final String audioUrl;
  final String fileName;
  final bool isDark;

  const _AudioPlayerScreen({
    required this.audioUrl,
    required this.fileName,
    required this.isDark,
  });

  @override
  State<_AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<_AudioPlayerScreen> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  bool _isInitialized = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initializeAudio();
  }

  Future<void> _initializeAudio() async {
    try {
      final isLocalFile = !widget.audioUrl.startsWith('http');
      
      if (isLocalFile) {
        await _audioPlayer.setSource(DeviceFileSource(widget.audioUrl));
      } else {
        // Sur iOS, AVPlayer peut avoir des problèmes avec certains formats M4A/MP3 depuis des URLs distantes.
        // On télécharge toujours le fichier sur iOS avant de le lire pour garantir la compatibilité.
        if (io.Platform.isIOS) {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('auth_token') ?? '';
          
          final uri = Uri.parse(widget.audioUrl);
          final headers = <String, String>{};
          if (token.isNotEmpty) {
            headers['Authorization'] = 'Bearer $token';
          }
          
          final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
          if (response.statusCode != 200) {
            throw Exception('HTTP ${response.statusCode} lors du chargement de l\'audio');
          }

          final tempDir = await getTemporaryDirectory();
          final fileNameFromUrl = uri.pathSegments.isNotEmpty
              ? uri.pathSegments.last
              : '${DateTime.now().millisecondsSinceEpoch}.m4a';
          final sanitizedName = fileNameFromUrl.replaceAll('/', '_').replaceAll('\\', '_');
          final tempFile = io.File(
            '${tempDir.path}/chat_audio_${DateTime.now().millisecondsSinceEpoch}_$sanitizedName',
          );
          await tempFile.writeAsBytes(response.bodyBytes);

          await _audioPlayer.setSource(DeviceFileSource(tempFile.path));
        } else {
          await _audioPlayer.setSourceUrl(widget.audioUrl);
        }
      }

      _audioPlayer.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
          });
        }
      });
      _audioPlayer.onDurationChanged.listen((duration) {
        if (mounted) {
          setState(() {
            _duration = duration;
          });
        }
      });
      _audioPlayer.onPositionChanged.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      });
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du chargement de l\'audio : $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.resume();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isDark ? Colors.grey[900] : Colors.white,
      appBar: AppBar(
        backgroundColor: widget.isDark ? Colors.grey[900] : Colors.white,
        iconTheme: IconThemeData(color: widget.isDark ? Colors.white70 : Colors.black87),
        title: Text(
          widget.fileName,
          style: GoogleFonts.poppins(color: widget.isDark ? Colors.white : Colors.black87),
        ),
      ),
      body: Center(
        child: _isInitialized
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.music_note,
                    size: 80,
                    color: widget.isDark ? Colors.white70 : Colors.grey[600],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.fileName,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: widget.isDark ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Slider(
                    value: _duration.inMilliseconds > 0 ? _position.inMilliseconds.toDouble() : 0.0,
                    max: _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                    onChanged: (value) {
                      _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_position),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: widget.isDark ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: widget.isDark ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  IconButton(
                    iconSize: 64,
                    icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                    color: Colors.deepPurple,
                    onPressed: _togglePlayPause,
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class _PdfViewerScreen extends StatelessWidget {
  final String filePath;
  final String fileName;

  const _PdfViewerScreen({
    required this.filePath,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[100],
      appBar: AppBar(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        title: Text(
          fileName,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: PDFView(
        filePath: filePath,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: true,
        pageFling: true,
        onError: (error) {
          developer.log('Error loading PDF: $error', name: 'MediaFilesPage.PDF');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Erreur lors du chargement du PDF: $error',
                style: GoogleFonts.poppins(fontSize: 14),
              ),
              backgroundColor: Colors.red.shade100,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        },
        onRender: (pages) {
          developer.log('PDF rendered with $pages pages', name: 'MediaFilesPage.PDF');
        },
        onPageError: (page, error) {
          developer.log('Error on page $page: $error', name: 'MediaFilesPage.PDF');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Erreur sur la page $page: $error',
                style: GoogleFonts.poppins(fontSize: 14),
              ),
              backgroundColor: Colors.red.shade100,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        },
      ),
    );
  }
}