// lib/screens/group_info_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:provider/provider.dart';
import '../services/rocketchat_websocket_service.dart';
import '../providers/auth_provider.dart';
import '../utils/snackbar_helper.dart';

// ==== PAGE POUR GÉRER LES MEMBRES (utilisateurs non dans le groupe) ====
// (inchangée – conservée telle quelle)
class ManageMembersPage extends StatefulWidget {
  final String roomId;
  final String groupName;
  final bool isDark;

  const ManageMembersPage({
    super.key,
    required this.roomId,
    required this.groupName,
    required this.isDark,
  });

  @override
  State<ManageMembersPage> createState() => _ManageMembersPageState();
}

class _ManageMembersPageState extends State<ManageMembersPage> {
  List<Map<String, dynamic>> _usersNotInChannel = [];
  bool _isLoading = true;
  final Set<String> _addingUserIds = {};

  @override
  void initState() {
    super.initState();
    _fetchUsersNotInChannel();
  }

  Future<void> _fetchUsersNotInChannel() async {
    setState(() => _isLoading = true);
    const endpoint = 'https://www.unistudious.com/api/chat/channel-users-not-in';
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) throw Exception('Token manquant');

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.roomId
        ..headers['Authorization'] = 'Bearer $token';

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> rawList = data['users'] ?? data['data'] ?? data['channels'] ?? [];

        setState(() {
          _usersNotInChannel = rawList.map((u) => u as Map<String, dynamic>).toList();
          _isLoading = false;
        });
      } else {
        throw Exception('Erreur ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        SnackBarHelper.showError(context, 'Erreur de chargement : $e');
      }
    }
  }

  Future<void> _addMemberToChannel(String userId, String name) async {
    if (userId.isEmpty) return;

    setState(() => _addingUserIds.add(userId));

    const endpoint = 'https://www.unistudious.com/api/chat/channel-member-add';
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) throw Exception('Token manquant');

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.roomId
        ..fields['userId'] = userId
        ..headers['Authorization'] = 'Bearer $token';

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final success = data['status'] == 'success' || (data['data']?['success'] == true);

        if (success) {
          setState(() {
            _usersNotInChannel.removeWhere((u) => u['_id']?.toString() == userId || u['id']?.toString() == userId);
            _addingUserIds.remove(userId);
          });
          SnackBarHelper.showSuccess(context, '$name ajouté au groupe');
        } else {
          throw Exception('Réponse inattendue');
        }
      } else {
        throw Exception('Erreur ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _addingUserIds.remove(userId));
        SnackBarHelper.showError(context, 'Erreur lors de l\'ajout de $name');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isDark ? Colors.grey[900] : Colors.white,
      appBar: AppBar(
        backgroundColor: widget.isDark ? Colors.grey[900] : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: widget.isDark ? Colors.white70 : Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Ajouter des membres",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: widget.isDark ? Colors.white : Colors.black87),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _usersNotInChannel.isEmpty
          ? Center(
        child: Text(
          'Tous les utilisateurs sont déjà dans le groupe',
          style: GoogleFonts.poppins(color: widget.isDark ? Colors.white70 : Colors.grey[600], fontSize: 16),
        ),
      )
          : ListView.builder(
        itemCount: _usersNotInChannel.length,
        itemBuilder: (context, index) {
          final user = _usersNotInChannel[index];
          final name = user['name']?.toString() ?? user['username']?.toString() ?? 'Inconnu';
          final username = user['username']?.toString() ?? '';
          final avatarUrl = user['avatar']?.toString();
          final userId = user['_id']?.toString() ?? user['id']?.toString() ?? '';
          final isAdding = _addingUserIds.contains(userId);

          return ListTile(
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: widget.isDark ? Colors.grey[800] : Colors.grey[200],
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              )
                  : ClipOval(
                child: CachedNetworkImage(
                  imageUrl: avatarUrl,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const CircularProgressIndicator(strokeWidth: 2),
                  errorWidget: (_, __, ___) => Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ),
            title: Text(
              name,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: widget.isDark ? Colors.white : Colors.black87),
            ),
            subtitle: username.isNotEmpty
                ? Text(
              '@$username',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]),
            )
                : null,
            trailing: isAdding
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
              icon: const Icon(Icons.person_add, color: Colors.deepPurple),
              onPressed: () => _addMemberToChannel(userId, name),
            ),
          );
        },
      ),
    );
  }
}

// ==== PAGE DES MEMBRES EXISTANTS – AVEC SUPPRESSION PAR APPUI LONG (LEADER UNIQUEMENT) ====
// (inchangée)
class MembersPage extends StatefulWidget {
  final List<Map<String, dynamic>> members;
  final String groupName;
  final bool isDark;
  final bool isLeader;
  final String roomId;

  const MembersPage({
    super.key,
    required this.members,
    required this.groupName,
    required this.isDark,
    required this.isLeader,
    required this.roomId,
  });

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  final Set<String> _removingUserIds = {};

  Future<void> _removeMemberFromChannel(String userId, String name) async {
    if (userId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? Colors.grey[900] : Colors.white,
        title: Text("Supprimer $name ?"),
        content: const Text("Cette personne ne fera plus partie du groupe."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _removingUserIds.add(userId));

    const endpoint = 'https://www.unistudious.com/api/chat/channel-member-remove';
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) throw Exception('Token manquant');

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.roomId
        ..fields['userId'] = userId
        ..headers['Authorization'] = 'Bearer $token';

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final success = data['status'] == 'success' || (data['data']?['success'] == true);

        if (success) {
          setState(() {
            widget.members.removeWhere((m) => m['_id']?.toString() == userId);
            _removingUserIds.remove(userId);
          });
          SnackBarHelper.showSuccess(context, '$name a été retiré du groupe');
        } else {
          throw Exception('Réponse inattendue');
        }
      } else {
        throw Exception('Erreur ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _removingUserIds.remove(userId));
        SnackBarHelper.showError(context, 'Erreur lors de la suppression de $name');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isDark ? Colors.grey[900] : Colors.white,
      appBar: AppBar(
        backgroundColor: widget.isDark ? Colors.grey[900] : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: widget.isDark ? Colors.white70 : Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Membres • ${widget.members.length}",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: widget.isDark ? Colors.white : Colors.black87),
        ),
      ),
      body: widget.members.isEmpty
          ? Center(
        child: Text(
          'Aucun membre trouvé',
          style: GoogleFonts.poppins(color: widget.isDark ? Colors.white70 : Colors.grey[600], fontSize: 16),
        ),
      )
          : ListView.builder(
        itemCount: widget.members.length,
        itemBuilder: (context, index) {
          final member = widget.members[index];
          final name = member['name']?.toString() ?? 'Inconnu';
          final status = member['status']?.toString() ?? 'offline';
          final avatarUrl = member['avatar']?.toString();
          final userId = member['_id']?.toString() ?? '';
          final isRemoving = _removingUserIds.contains(userId);

          return InkWell(
            onLongPress: widget.isLeader && userId.isNotEmpty ? () => _removeMemberFromChannel(userId, name) : null,
            child: ListTile(
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: widget.isDark ? Colors.grey[800] : Colors.grey[200],
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                )
                    : ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: avatarUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const CircularProgressIndicator(strokeWidth: 2),
                    errorWidget: (_, __, ___) => Text(
                      name[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ),
              title: Text(
                name,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: widget.isDark ? Colors.white : Colors.black87),
              ),
              subtitle: Text(
                status == 'online' ? 'En ligne' : 'Hors ligne',
                style: GoogleFonts.poppins(fontSize: 13, color: status == 'online' ? Colors.green : Colors.grey[500]),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status == 'online')
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                    ),
                  if (isRemoving) ...[
                    const SizedBox(width: 16),
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==== PAGE PRINCIPALE ====
class GroupInfoPage extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String? avatarUrl;
  final List<Map<String, dynamic>>? members;
  final bool isLeader;

  const GroupInfoPage({
    super.key,
    required this.groupId,
    required this.groupName,
    this.avatarUrl,
    this.members,
    this.isLeader = false,
  });

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  bool _notificationsEnabled = false;
  bool _isFavorite = false;
  bool _isLeaving = false;
  bool _isDeleting = false;
  bool _isRenaming = false;
  bool _isSettingAnnouncement = false;
  bool _readOnly = false;
  bool _isUpdatingReadOnly = false;
  String? _currentAnnouncement; // <-- Nouvelle variable pour stocker l'annonce actuelle
  String? _rcToken;
  String? _rcUid;
  final RocketChatWebSocketService _rcService = RocketChatWebSocketService();
  final Map<String, Map<String, dynamic>> _avatarSvgCache = {};
  final Map<String, Future<Map<String, dynamic>>> _avatarFutures = {};
  List<Map<String, dynamic>> _members = [];
  bool _isLoadingMembers = false;

  @override
  void initState() {
    super.initState();
    _members = widget.members ?? [];
    _loadRcCredentials();
    if (widget.members == null || widget.members!.isEmpty) {
      _fetchChannelMembers();
    }
    _fetchCurrentAnnouncement(); // <-- Charger l'annonce existante au démarrage
    _fetchReadOnlyStatus(); // <-- Charger l'état read-only au démarrage
    _loadFavoriteState(); // <-- Charger l'état favori au démarrage
  }

  // === NOUVELLE FONCTION : Récupérer l'annonce actuelle ===
  Future<void> _fetchCurrentAnnouncement() async {
    const endpoint = 'https://www.unistudious.com/api/chat/get-channel-messages';
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) return;

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId
        ..headers['Authorization'] = 'Bearer $token';

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final channel = data['channel'];
        final announcement = channel?['announcement']?.toString().trim();

        if (mounted) {
          setState(() {
            _currentAnnouncement = (announcement != null && announcement.isNotEmpty) ? announcement : null;
          });
        }
      }
    } catch (e) {
      // Silencieux : si erreur, on garde null
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final showLeaderOptions = widget.isLeader;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 70),
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                    child: _buildAvatarWidget(
                      widget.avatarUrl,
                      widget.groupName,
                      size: 100,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.groupName,
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_members.length} membre${_members.length > 1 ? 's' : ''}',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: isDark ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Boutons d'action rapides
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildAction(Icons.call, "Audio", isDark, onTap: () {
                          SnackBarHelper.showInfo(context, "Appel vocal bientôt disponible");
                        }),
                        _buildAction(Icons.videocam, "Vidéo", isDark, onTap: () {
                          SnackBarHelper.showInfo(context, "Appel vidéo bientôt disponible");
                        }),
                        _buildAction(
                          _notificationsEnabled ? Icons.notifications : Icons.notifications_off,
                          _notificationsEnabled ? "Muet" : "Actif",
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
                  const SizedBox(height: 10),

                  // ==================== 1. PLUS D'ACTIONS ====================
                  _buildSectionTitle("PLUS D'ACTIONS", isDark),
                  _buildOptionTile(
                    icon: Icons.image,
                    title: "Afficher le fichier multimédia",
                    isDark: isDark,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChannelFilesPage(
                            roomId: widget.groupId,
                            groupName: widget.groupName,
                            isDark: isDark,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 5),

                  // ==================== 2. MEMBRES ====================
                  _buildSectionTitle("MEMBRES", isDark),
                  _buildOptionTile(
                    icon: Icons.people,
                    title: "Membres",
                    isDark: isDark,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MembersPage(
                            members: _members,
                            groupName: widget.groupName,
                            isDark: isDark,
                            isLeader: widget.isLeader,
                            roomId: widget.groupId,
                          ),
                        ),
                      );
                    },
                  ),
                  if (showLeaderOptions)
                    _buildOptionTile(
                      icon: Icons.supervisor_account,
                      title: "Gérer les membres",
                      isDark: isDark,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ManageMembersPage(
                              roomId: widget.groupId,
                              groupName: widget.groupName,
                              isDark: isDark,
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 16),

                  // ==================== 3. CONFIDENTIALITÉ ====================
                  _buildSectionTitle("CONFIDENTIALITÉ", isDark),
                  if (showLeaderOptions)
                    _buildOptionTile(
                      icon: Icons.volume_up,
                      title: "Annonces",
                      isDark: isDark,
                      onTap: _isSettingAnnouncement ? null : () => _showAnnouncementDialog(isDark),
                    ),
                  if (showLeaderOptions)
                    _buildOptionTile(
                      icon: Icons.lock_outline,
                      title: "Canal en lecture seule",
                      isDark: isDark,
                      trailing: Switch(
                        value: _readOnly,
                        onChanged: (val) {
                          _updateReadOnly(val);
                        },
                        activeColor: Colors.deepPurple,
                      ),
                      onTap: () {
                        _updateReadOnly(!_readOnly);
                      },
                    ),
                  if (showLeaderOptions)
                    _buildOptionTile(
                      icon: Icons.edit,
                      title: "Renommer le canal",
                      isDark: isDark,
                      onTap: _isRenaming ? null : () => _showRenameDialog(isDark),
                    ),

                  // SUPPRIMER LE CANAL
                  if (showLeaderOptions)
                    _buildOptionTile(
                      icon: Icons.delete,
                      title: "Supprimer le canal",
                      isDark: isDark,
                      color: Colors.redAccent,
                      onTap: _isDeleting ? null : () => _confirmDeleteChannel(isDark),
                    ),

                  // QUITTER LE CANAL
                  _buildOptionTile(
                    icon: Icons.exit_to_app,
                    title: "Quitter le canal",
                    isDark: isDark,
                    color: Colors.redAccent,
                    onTap: () {
                      if (_isLeaving) return;
                      _confirmLeaveChannel(isDark);
                    },
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),

            // Bouton retour
            Positioned(
              top: 10,
              left: 10,
              child: CircleAvatar(
                radius: 22,
                backgroundColor: isDark ? Colors.grey[800] : Colors.white.withOpacity(0.9),
                child: IconButton(
                  icon: Icon(Icons.arrow_back, color: isDark ? Colors.white70 : Colors.black87, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== WIDGETS HELPER (inchangés) ====================
  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required bool isDark,
    Color? color,
    Widget? trailing,
    required VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(icon, color: color ?? (isDark ? Colors.white70 : Colors.black87)),
      title: Text(
        title,
        style: GoogleFonts.poppins(fontSize: 16, color: isDark ? Colors.white : Colors.black87),
      ),
      trailing: trailing ??
          Icon(Icons.chevron_right, color: isDark ? Colors.white54 : Colors.grey[600]),
      onTap: onTap,
    );
  }

  Widget _buildAction(IconData icon, String label, bool isDark, {VoidCallback? onTap, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
            child: Icon(icon, size: 30, color: color ?? (isDark ? Colors.white70 : Colors.black87)),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
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

  // === FONCTIONS RESTANTES (inchangées + annonce mise à jour) ===
  Future<void> _loadRcCredentials() async {
    final creds = await _rcService.fetchRocketChatCredentials();
    if (!mounted || creds == null) return;
    setState(() {
      _rcToken = creds['token'];
      _rcUid = creds['userId'];
    });
  }

  Future<void> _fetchChannelMembers() async {
    if (_isLoadingMembers || widget.groupId.isEmpty) return;

    setState(() {
      _isLoadingMembers = true;
    });
    const endpoint = 'https://www.unistudious.com/api/chat/channel-members';
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) {
        throw Exception('Aucun token d\'authentification trouvé.');
      }
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId;
      request.headers.addAll({'Authorization': 'Bearer $token'});
      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> membersData = data['data'] ?? [];

        final List<Map<String, dynamic>> loadedMembers = membersData.map((member) {
          return {
            '_id': member['_id']?.toString() ?? '',
            'username': member['username']?.toString() ?? '',
            'status': member['status']?.toString() ?? 'offline',
            'name': member['name']?.toString() ?? member['username']?.toString() ?? 'Inconnu',
            '_updatedAt': member['_updatedAt']?.toString() ?? '',
            'avatar': member['avatar']?.toString(),
          };
        }).toList();
        if (mounted) {
          setState(() {
            _members = loadedMembers;
            _isLoadingMembers = false;
          });
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        if (mounted) {
          setState(() {
            _isLoadingMembers = false;
          });
          SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
        }
      } else {
        throw Exception('Erreur ${response.statusCode} lors du chargement des membres.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMembers = false;
        });
        SnackBarHelper.showError(context, 'Erreur lors du chargement des membres : $e');
      }
    }
  }

  // === DIALOGUE D'ANNONCE AMÉLIORÉ ===
  void _showAnnouncementDialog(bool isDark) {
    final controller = TextEditingController(text: _currentAnnouncement ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(_currentAnnouncement != null ? "Modifier l'annonce" : "Définir une annonce"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_currentAnnouncement != null)
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Annonce actuelle :\n$_currentAnnouncement",
                  style: GoogleFonts.poppins(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "Message d'annonce (visible en haut du groupe)",
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
              maxLength: 200,
            ),
          ],
        ),
        actions: [
          // Conteneur scrollable horizontalement pour éviter l'overflow
          SizedBox(
            height: 56, // Hauteur fixe pour les actions
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Bouton Annuler
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      "Annuler",
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Bouton Supprimer (si annonce existe)
                  if (_currentAnnouncement != null)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _setAnnouncement(""); // Supprime l'annonce
                      },
                      child: const Text(
                        "Supprimer",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  if (_currentAnnouncement != null) const SizedBox(width: 8),
                  // Bouton principal (Mettre à jour / Publier)
                  ElevatedButton(
                    onPressed: () {
                      final newText = controller.text.trim();
                      Navigator.pop(ctx);
                      _setAnnouncement(newText);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: Text(_currentAnnouncement != null ? "Mettre à jour" : "Publier"),
                  ),
                  const SizedBox(width: 8), // Petit espace final pour le scroll
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setAnnouncement(String announcement) async {
    setState(() => _isSettingAnnouncement = true);

    const endpoint = 'https://www.unistudious.com/api/chat/channel-announcement';
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) throw Exception('Token manquant');

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId
        ..fields['announcement'] = announcement // vide = suppression
        ..headers['Authorization'] = 'Bearer $token';

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _currentAnnouncement = announcement.isNotEmpty ? announcement : null;
          });
          SnackBarHelper.showSuccess(context, announcement.isEmpty ? "Annonce supprimée" : "Annonce mise à jour");
        } else {
          throw Exception('Réponse inattendue');
        }
      } else {
        throw Exception('Erreur ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur : $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSettingAnnouncement = false);
      }
    }
  }

  // === Les autres fonctions (leave, delete, rename, etc.) restent inchangées ===

  Future<void> _confirmLeaveChannel(bool isDark) async {
    if (_isLeaving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: const Text("Quitter le canal ?"),
        content: const Text("Vous ne recevrez plus de messages de ce canal."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Quitter", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _leaveChannel();
    }
  }

  Future<void> _leaveChannel() async {
    if (_isLeaving || widget.groupId.isEmpty) return;
    setState(() => _isLeaving = true);
    const endpoint = 'https://www.unistudious.com/api/chat/channel-leave';
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) {
        throw Exception('Aucun token d\'authentification trouvé.');
      }
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId;
      request.headers.addAll({'Authorization': 'Bearer $token'});
      final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 20)));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final success = data['data']?['success'] == true || data['success'] == true;
        if (success) {
          SnackBarHelper.showSuccess(context, "Vous avez quitté le canal");
          Navigator.pop(context, {'left': true, 'roomId': widget.groupId});
        } else {
          throw Exception('Réponse inattendue du serveur.');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      } else {
        throw Exception('Erreur ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors de la sortie du canal : $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLeaving = false);
      }
    }
  }

  Future<void> _confirmDeleteChannel(bool isDark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: const Text("Supprimer le canal ?"),
        content: const Text("Cette action est irréversible. Tous les messages seront perdus."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteChannel();
    }
  }

  Future<void> _deleteChannel() async {
    if (_isDeleting || widget.groupId.isEmpty) return;
    setState(() => _isDeleting = true);

    const endpoint = 'https://www.unistudious.com/api/chat/channel-delete';
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) throw Exception('Token manquant');

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId
        ..headers['Authorization'] = 'Bearer $token';

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          SnackBarHelper.showSuccess(context, "Groupe supprimé avec succès");
          Navigator.pop(context, {'deleted': true, 'roomId': widget.groupId});
        } else {
          throw Exception('Réponse inattendue');
        }
      } else {
        throw Exception('Erreur ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors de la suppression du groupe : $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  void _showRenameDialog(bool isDark) {
    final controller = TextEditingController(text: widget.groupName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: const Text("Renommer le canal"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Nouveau nom du groupe",
            border: OutlineInputBorder(),
          ),
          maxLength: 50,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != widget.groupName) {
                Navigator.pop(ctx);
                _renameChannel(newName);
              } else {
                Navigator.pop(ctx);
              }
            },
            child: const Text("Valider"),
          ),
        ],
      ),
    );
  }

  Future<void> _renameChannel(String newName) async {
    setState(() => _isRenaming = true);

    const endpoint = 'https://www.unistudious.com/api/chat/channel-rename';
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) throw Exception('Token manquant');

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId
        ..fields['name'] = newName
        ..headers['Authorization'] = 'Bearer $token';

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          SnackBarHelper.showSuccess(context, "Groupe renommé en \"$newName\"");
          Navigator.pop(context, {'renamed': true, 'newName': newName, 'roomId': widget.groupId});
        } else {
          throw Exception('Réponse inattendue');
        }
      } else {
        throw Exception('Erreur ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors du renommage : $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isRenaming = false);
      }
    }
  }

  // === FONCTION : Récupérer l'état read-only actuel depuis les APIs list-channels/my-channels ===
  Future<void> _fetchReadOnlyStatus() async {
    if (widget.groupId.isEmpty) return;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // Essayer d'abord my-channels (canaux privés)
      final endpoints = ['/api/chat/my-channels', '/api/chat/list-channels'];
      
      for (final endpoint in endpoints) {
        try {
          final response = await authProvider
              .authenticatedRequest('GET', endpoint)
              .timeout(const Duration(seconds: 30));

          if (!mounted) return;

          if (response.statusCode == 200) {
            final Map<String, dynamic> jsonResponse = jsonDecode(response.body);

            if (jsonResponse['success'] == true) {
              final List<dynamic> channels = jsonResponse['channels'] ?? [];

              // Chercher le canal actuel dans la liste
              for (var channel in channels) {
                final channelId = channel['id']?.toString() ?? channel['_id']?.toString() ?? '';
                final roomId = channel['room_id']?.toString() ?? channelId;

                if (roomId == widget.groupId || channelId == widget.groupId) {
                  // Récupérer readonly depuis l'API
                  final readOnlyValue = channel['readonly'] ?? channel['readOnly'] ?? false;
                  
                  if (mounted) {
                    setState(() {
                      _readOnly = readOnlyValue == true || readOnlyValue == 'true' || readOnlyValue == 1;
                    });
                    developer.log('Read-only status fetched from $endpoint: readonly=$readOnlyValue, _readOnly=$_readOnly', name: 'GroupInfoPage');
                  }
                  return; // Canal trouvé, on sort
                }
              }
            }
          }
        } catch (e) {
          // Continuer avec l'autre endpoint si celui-ci échoue
          developer.log('Error fetching from $endpoint: $e', name: 'GroupInfoPage');
          continue;
        }
      }
      
      // Si aucun canal n'a été trouvé dans les deux APIs, on garde l'état actuel
      developer.log('Channel ${widget.groupId} not found in my-channels or list-channels', name: 'GroupInfoPage');
    } catch (e, s) {
      developer.log('Error fetching read-only status: $e', error: e, stackTrace: s, name: 'GroupInfoPage');
      // En cas d'erreur, on laisse _readOnly à son état actuel
    }
  }

  // === FONCTION : Charger l'état favori depuis le cache ===
  Future<void> _loadFavoriteState() async {
    final prefs = await SharedPreferences.getInstance();
    final isFavorite = prefs.getBool('favorite_room_${widget.groupId}') ?? false;
    if (mounted) {
      setState(() {
        _isFavorite = isFavorite;
      });
    }
  }

  // === FONCTION : Basculer l'état favori via l'API ===
  Future<void> _toggleFavorite() async {
    final endpoint = _isFavorite
        ? 'https://www.unistudious.com/api/chat/not-favorite-room'
        : 'https://www.unistudious.com/api/chat/favorite-room';
    try {
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId;
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
          await prefs.setBool('favorite_room_${widget.groupId}', newFavoriteState);
          SnackBarHelper.showSuccess(
            context,
            newFavoriteState ? "Groupe ajouté aux favoris" : "Groupe retiré des favoris",
          );
        } else {
          throw Exception('Échec de la mise à jour du statut favori.');
        }
      } else {
        throw Exception('Erreur ${response.statusCode} lors de la mise à jour du statut favori.');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          'Erreur lors de la mise à jour du statut favori : $e',
        );
      }
    }
  }

  // === FONCTION : Mettre à jour l'état read-only ===
  Future<void> _updateReadOnly(bool readOnly) async {
    if (_isUpdatingReadOnly || widget.groupId.isEmpty) return;

    final previousReadOnly = _readOnly; // Sauvegarder l'état précédent
    setState(() {
      _isUpdatingReadOnly = true; // Utilisé uniquement pour éviter les appels multiples
      _readOnly = readOnly; // Mise à jour optimiste immédiate
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.authenticatedRequest(
        'POST',
        '/api/chat/channel-update-read-only',
        headers: {
          // On force le form-data (x-www-form-urlencoded)
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'roomId=${widget.groupId}&readOnly=${readOnly ? 'true' : 'false'}',
      );

      if (!mounted) return;

      if (mounted) {
        setState(() => _isUpdatingReadOnly = false);
        SnackBarHelper.showSuccess(context, readOnly
                ? 'Canal mis en lecture seule'
                : 'Canal mis en mode normal');
      }

      // Recharger l'état depuis les APIs en arrière-plan pour s'assurer qu'il est synchronisé
      // (sans await pour ne pas bloquer l'UI)
      _fetchReadOnlyStatus();
    } catch (e, s) {
      developer.log(
        'Error channel-update-read-only: $e',
        error: e,
        stackTrace: s,
      );
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors de la mise à jour : $e');
        // Revenir à l'état précédent en cas d'erreur
        setState(() {
          _readOnly = previousReadOnly;
          _isUpdatingReadOnly = false;
        });
      }
    }
  }

  // === Fonctions d'avatar (inchangées) ===
  String _withRcTokens(String? url) {
    if (url == null || url.isEmpty) return url ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.queryParameters.containsKey('rc_token') &&
        uri.queryParameters.containsKey('rc_uid')) {
      return url;
    }
    if (_rcToken != null && _rcUid != null) {
      final enriched = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'rc_token': _rcToken!,
        'rc_uid': _rcUid!,
      });
      return enriched.toString();
    }
    return url;
  }

  Widget _buildAvatarWidget(String? url, String username, {double size = 90, bool isDark = false}) {
    if (url == null || url.isEmpty) {
      return _fallbackAvatar(username, size);
    }
    final effectiveUrl = _withRcTokens(url);

    if (effectiveUrl.startsWith('data:image/png;base64,')) {
      try {
        final bytes = base64Decode(effectiveUrl.split(',').last);
        return ClipOval(
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {
        return _fallbackAvatar(username, size);
      }
    }

    final isSvg = effectiveUrl.endsWith('.svg') || effectiveUrl.contains('message.unistudious.com/avatar/');
    if (isSvg) {
      final cacheKey = username.isNotEmpty ? username : effectiveUrl;
      if (_avatarSvgCache.containsKey(cacheKey)) {
        final cached = _avatarSvgCache[cacheKey]!;
        return CircleAvatar(
          backgroundColor: cached['color'] as Color,
          radius: size / 2,
          child: Text(
            cached['initial'] as String,
            style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        );
      }
      if (!_avatarFutures.containsKey(cacheKey)) {
        _avatarFutures[cacheKey] = _loadAndCacheSvg(effectiveUrl, cacheKey);
      }
      return SizedBox(
        width: size,
        height: size,
        child: FutureBuilder<Map<String, dynamic>>(
          key: ValueKey('avatar_$cacheKey'),
          future: _avatarFutures[cacheKey],
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                ),
              );
            }
            if (snapshot.hasData) {
              final avatarStyle = snapshot.data!;
              return CircleAvatar(
                backgroundColor: avatarStyle['color'] as Color,
                radius: size / 2,
                child: Text(
                  avatarStyle['initial'] as String,
                  style: TextStyle(
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              );
            }
            return _fallbackAvatar(username, size);
          },
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: effectiveUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => Center(
            child: SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => _fallbackAvatar(username, size),
        ),
      ),
    );
  }

  Widget _fallbackAvatar(String username, double size) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Colors.deepPurple.withOpacity(0.2),
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }

  Future<Map<String, dynamic>> _loadAndCacheSvg(String avatarUrl, String cacheKey) async {
    try {
      final svgData = await _fetchAndSanitizeSvg(avatarUrl, cacheKey);
      if (svgData == null || svgData.isEmpty) {
        return {'color': Colors.deepPurple, 'initial': '?'};
      }
      final avatarStyle = _extractAvatarStyleFromSvg(svgData);
      _avatarSvgCache[cacheKey] = avatarStyle;
      return avatarStyle;
    } catch (e) {
      return {'color': Colors.deepPurple, 'initial': '?'};
    }
  }

  Future<String?> _fetchAndSanitizeSvg(String url, String username) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('image/svg')) {
        return null;
      }
      var svg = response.body;
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
    final rectMatch = RegExp(r'<rect[^>]*fill="([^"]+)"', caseSensitive: false).firstMatch(svg);
    final bgFill = rectMatch?.group(1) ?? '#6200EE';
    final textMatch = RegExp(r'<text[^>]*>([^<]+)</text>', caseSensitive: false).firstMatch(svg);
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
      return Colors.deepPurple;
    }
    return Color(int.parse(value, radix: 16));
  }
}

// ==== PAGE POUR AFFICHER LES FICHIERS MULTIMÉDIA ====
class ChannelFilesPage extends StatefulWidget {
  final String roomId;
  final String groupName;
  final bool isDark;

  const ChannelFilesPage({
    super.key,
    required this.roomId,
    required this.groupName,
    required this.isDark,
  });

  @override
  State<ChannelFilesPage> createState() => _ChannelFilesPageState();
}

class _ChannelFilesPageState extends State<ChannelFilesPage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _allFiles = [];
  bool _isLoading = true;
  String? _errorMessage;
  late TabController _tabController;

  // Organiser les fichiers par type
  List<Map<String, dynamic>> get _imageFiles => _allFiles.where((f) => f['typeGroup'] == 'image').toList();
  List<Map<String, dynamic>> get _videoFiles => _allFiles.where((f) => f['typeGroup'] == 'video').toList();
  List<Map<String, dynamic>> get _audioFiles => _allFiles.where((f) => f['typeGroup'] == 'audio').toList();
  List<Map<String, dynamic>> get _documentFiles => _allFiles.where((f) => f['typeGroup'] == 'application' || (f['type']?.toString().contains('pdf') ?? false)).toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchChannelFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchChannelFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    const endpoint = 'https://www.unistudious.com/api/chat/channel-files';
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) throw Exception('Token manquant');

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.roomId
        ..headers['Authorization'] = 'Bearer $token';

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['files'] != null) {
          setState(() {
            _allFiles = List<Map<String, dynamic>>.from(data['files']);
            _isLoading = false;
          });
        } else {
          throw Exception('Réponse inattendue');
        }
      } else {
        throw Exception('Erreur ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
        SnackBarHelper.showError(context, 'Erreur lors du chargement des fichiers : $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isDark ? Colors.grey[900] : Colors.white,
      appBar: AppBar(
        backgroundColor: widget.isDark ? Colors.grey[900] : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: widget.isDark ? Colors.white70 : Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Fichiers multimédia",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: widget.isDark ? Colors.white : Colors.black87),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: widget.isDark ? Colors.white54 : Colors.grey[600],
          indicatorColor: Colors.deepPurple,
          tabs: [
            Tab(text: 'Images (${_imageFiles.length})'),
            Tab(text: 'Vidéos (${_videoFiles.length})'),
            Tab(text: 'Audio (${_audioFiles.length})'),
            Tab(text: 'Documents (${_documentFiles.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: widget.isDark ? Colors.white70 : Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: GoogleFonts.poppins(color: widget.isDark ? Colors.white70 : Colors.grey[600], fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchChannelFiles,
              child: const Text('Réessayer'),
            ),
          ],
        ),
      )
          : TabBarView(
        controller: _tabController,
        children: [
          _buildFilesGrid(_imageFiles, 'image'),
          _buildFilesGrid(_videoFiles, 'video'),
          _buildFilesGrid(_audioFiles, 'audio'),
          _buildFilesGrid(_documentFiles, 'document'),
        ],
      ),
    );
  }

  Widget _buildFilesGrid(List<Map<String, dynamic>> files, String type) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == 'image' ? Icons.image_outlined :
              type == 'video' ? Icons.videocam_outlined :
              type == 'audio' ? Icons.audiotrack_outlined :
              Icons.description_outlined,
              size: 64,
              color: widget.isDark ? Colors.white30 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Aucun fichier ${type == 'image' ? 'image' : type == 'video' ? 'vidéo' : type == 'audio' ? 'audio' : 'document'}',
              style: GoogleFonts.poppins(
                color: widget.isDark ? Colors.white70 : Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          return _buildFileItem(file, type);
        },
      ),
    );
  }

  Widget _buildFileItem(Map<String, dynamic> file, String type) {
    final url = file['url']?.toString() ?? '';
    final name = file['name']?.toString() ?? 'Fichier';
    final user = file['user'] as Map<String, dynamic>?;
    final userName = user?['name']?.toString() ?? user?['username']?.toString() ?? 'Inconnu';
    final size = file['size'] as int? ?? 0;
    final sizeInMB = (size / (1024 * 1024)).toStringAsFixed(2);

    // Pour les images, utiliser l'URL complète avec tokens si disponible
    String imageUrl = url;
    if (type == 'image' && url.isNotEmpty) {
      if (!url.startsWith('http')) {
        imageUrl = _getFullUrl(url);
      }
      // Vérifier si l'URL du fichier a les tokens Rocket.Chat
      final fileUri = Uri.tryParse(url);
      if (fileUri != null && fileUri.queryParameters.containsKey('rc_token')) {
        final imageUri = Uri.tryParse(imageUrl);
        if (imageUri != null && !imageUri.queryParameters.containsKey('rc_token')) {
          imageUrl = imageUri.replace(queryParameters: {
            ...imageUri.queryParameters,
            'rc_token': fileUri.queryParameters['rc_token']!,
            'rc_uid': fileUri.queryParameters['rc_uid']!,
          }).toString();
        }
      }
    }

    // Couleurs selon le type de fichier
    Color typeColor;
    IconData typeIcon;
    if (type == 'image') {
      typeColor = Colors.blue;
      typeIcon = Icons.image;
    } else if (type == 'video') {
      typeColor = Colors.red;
      typeIcon = Icons.videocam;
    } else if (type == 'audio') {
      typeColor = Colors.purple;
      typeIcon = Icons.audiotrack;
    } else {
      typeColor = Colors.orange;
      typeIcon = Icons.description;
    }

    return GestureDetector(
      onTap: () => _openFile(file, type),
      child: Container(
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.grey[850] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Zone principale avec image ou icône
              Expanded(
                flex: 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.isDark ? Colors.grey[800] : Colors.grey[100],
                    border: type == 'image' && imageUrl.isNotEmpty
                        ? Border.all(
                      color: typeColor.withOpacity(0.3),
                      width: 2,
                    )
                        : null,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: type == 'image' && imageUrl.isNotEmpty
                      ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(10),
                          topRight: Radius.circular(10),
                        ),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  typeColor.withOpacity(0.8),
                                  typeColor.withOpacity(0.6),
                                ],
                              ),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  typeColor.withOpacity(0.8),
                                  typeColor.withOpacity(0.6),
                                ],
                              ),
                            ),
                            child: Icon(
                              Icons.broken_image,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                      // Overlay dégradé en bas pour améliorer la lisibilité
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.6),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Badge avec icône du type en haut à droite
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            typeIcon,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  )
                      : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          typeColor.withOpacity(0.8),
                          typeColor.withOpacity(0.6),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            typeIcon,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          type == 'video' ? 'Vidéo' :
                          type == 'audio' ? 'Audio' : 'PDF',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Zone d'information en bas
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.isDark ? Colors.grey[800] : Colors.grey[50],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nom du fichier
                    Text(
                      name,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Informations supplémentaires
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 12,
                          color: widget.isDark ? Colors.white60 : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            userName,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: widget.isDark ? Colors.white60 : Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
        developer.log('Erreur read/file pour image : ${response.statusCode} $errorBody', name: 'ChannelFilesPage');
        return null;
      }
    } catch (e, s) {
      developer.log('Exception dans _getImageBytesFromApi: $e', name: 'ChannelFilesPage', error: e, stackTrace: s);
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
          developer.log('Extension extraite depuis fileName: $extension', name: 'ChannelFilesPage');
        } else {
          // Déterminer l'extension depuis le type MIME si disponible
          final contentType = response.headers['content-type'];
          developer.log('Content-Type: $contentType', name: 'ChannelFilesPage');
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
            developer.log('Extension déterminée depuis content-type: $extension', name: 'ChannelFilesPage');
          }
        }

        // Si toujours pas d'extension, essayer de la déterminer depuis le type du fichier dans les données
        if (extension.isEmpty) {
          developer.log('Aucune extension trouvée, fileName: $fileName', name: 'ChannelFilesPage');
        }

        final tempFile = io.File('${tempDir.path}/chat_media_${fileId}_${DateTime.now().millisecondsSinceEpoch}$extension');
        await tempFile.writeAsBytes(bytes);
        developer.log('Fichier temporaire créé : ${tempFile.path}', name: 'ChannelFilesPage');
        return tempFile.path;
      } else {
        final errorBody = response.body;
        developer.log('Erreur read/file : ${response.statusCode} $errorBody', name: 'ChannelFilesPage');
        return null;
      }
    } catch (e, s) {
      developer.log('Exception dans _getPlayableFileUrl: $e', name: 'ChannelFilesPage', error: e, stackTrace: s);
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
      developer.log('fetchProtectedImage: exception: $e', name: 'ChannelFilesPage');
      return null;
    }
  }

  Future<void> _openFile(Map<String, dynamic> file, String type) async {
    final url = file['url']?.toString() ?? '';
    final name = file['name']?.toString() ?? 'Fichier';
    final fileId = file['_id']?.toString();
    final fileType = file['type']?.toString() ?? '';

    developer.log('_openFile: type=$type, name=$name, fileId=$fileId, fileType=$fileType', name: 'ChannelFilesPage');

    if (url.isEmpty) {
      SnackBarHelper.showError(context, 'URL du fichier non disponible');
      return;
    }

    if (type == 'image') {
      // Pour les images, utiliser l'API /api/chat/read/file avec fileId si disponible
      // Cela garantit un accès authentifié même si l'URL directe échoue
      if (fileId != null) {
        // Télécharger l'image via l'API
        try {
          final bytes = await _getImageBytesFromApi(fileId: fileId, fileName: name);
          if (bytes != null && mounted) {
            // Créer un fichier temporaire pour l'image
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
          developer.log('Error downloading image via API: $e', name: 'ChannelFilesPage');
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
      // Télécharger la vidéo si on a un fileId
      String? localPath;
      if (fileId != null) {
        // S'assurer que le nom de fichier a une extension
        String videoFileName = name;
        if (!videoFileName.contains('.')) {
          // Ajouter l'extension depuis le type MIME si disponible
          final fileType = file['type']?.toString() ?? '';
          if (fileType.contains('video/mp4')) {
            videoFileName = '$videoFileName.mp4';
          } else if (fileType.contains('video')) {
            videoFileName = '$videoFileName.mp4';
          } else {
            videoFileName = '$videoFileName.mp4'; // Par défaut
          }
        }
        localPath = await _getPlayableFileUrl(fileId: fileId, fileName: videoFileName);
      } else {
        // Sinon télécharger directement depuis l'URL
        try {
          final bytes = await fetchProtectedImage(_getFullUrl(url));
          if (bytes != null && mounted) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = io.File('${tempDir.path}/video_${DateTime.now().millisecondsSinceEpoch}.mp4');
            await tempFile.writeAsBytes(bytes);
            localPath = tempFile.path;
          }
        } catch (e) {
          developer.log('Error downloading video: $e', name: 'ChannelFilesPage');
        }
      }

      if (localPath != null && mounted) {
        final path = localPath; // Assurer que c'est non-nullable
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _VideoPlayerScreen(filePath: path, isNetwork: false),
          ),
        );
      } else {
        if (mounted) {
          SnackBarHelper.showError(context, 'Impossible de charger la vidéo');
        }
      }
    } else if (type == 'audio') {
      // Télécharger l'audio si on a un fileId
      String? localPath;
      if (fileId != null) {
        // S'assurer que le nom de fichier a une extension
        String audioFileName = name;
        if (!audioFileName.contains('.')) {
          // Ajouter l'extension depuis le type MIME si disponible
          final fileType = file['type']?.toString() ?? '';
          if (fileType.contains('audio/mpeg') || fileType.contains('audio/mp3')) {
            audioFileName = '$audioFileName.mp3';
          } else if (fileType.contains('audio')) {
            audioFileName = '$audioFileName.mp3';
          } else {
            audioFileName = '$audioFileName.mp3'; // Par défaut
          }
        }
        localPath = await _getPlayableFileUrl(fileId: fileId, fileName: audioFileName);
      } else {
        // Sinon télécharger directement depuis l'URL
        try {
          final bytes = await fetchProtectedImage(_getFullUrl(url));
          if (bytes != null && mounted) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = io.File('${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.mp3');
            await tempFile.writeAsBytes(bytes);
            localPath = tempFile.path;
          }
        } catch (e) {
          developer.log('Error downloading audio: $e', name: 'ChannelFilesPage');
        }
      }

      if (localPath != null && mounted) {
        final path = localPath; // Assurer que c'est non-nullable
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _AudioPlayerScreen(audioUrl: path, fileName: name, isDark: widget.isDark),
          ),
        );
      } else {
        if (mounted) {
          SnackBarHelper.showError(context, 'Impossible de charger l\'audio');
        }
      }
    } else {
      // Ouvrir le document (PDF)
      String? localPath;
      if (fileId != null) {
        localPath = await _getPlayableFileUrl(fileId: fileId, fileName: name);
      } else {
        // Sinon télécharger directement depuis l'URL
        try {
          final bytes = await fetchProtectedImage(_getFullUrl(url));
          if (bytes != null && mounted) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = io.File('${tempDir.path}/pdf_${DateTime.now().millisecondsSinceEpoch}.pdf');
            await tempFile.writeAsBytes(bytes);
            localPath = tempFile.path;
          }
        } catch (e) {
          developer.log('Error downloading PDF: $e', name: 'ChannelFilesPage');
        }
      }

      if (localPath != null && mounted) {
        final path = localPath; // Assurer que c'est non-nullable
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _PdfViewerScreen(filePath: path, fileName: name),
          ),
        );
      } else {
        if (mounted) {
          SnackBarHelper.showError(context, 'Impossible de charger le PDF');
        }
      }
    }
  }
}

// ==== ÉCRANS DE VISUALISATION ====
class _ImageViewerScreen extends StatelessWidget {
  final String imageUrl;
  final bool isLocalFile;

  const _ImageViewerScreen({required this.imageUrl, this.isLocalFile = false});

  @override
  Widget build(BuildContext context) {
    developer.log('_ImageViewerScreen.build: imageUrl = "$imageUrl"', name: 'ChannelFilesPage');
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
            developer.log('Error loading local image: $error', name: 'ChannelFilesPage');
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

    // Pour les URLs avec tokens Rocket.Chat, essayer d'abord CachedNetworkImage
    // mais utiliser _fetchImageBytes comme fallback si ça échoue
    if (hasRcToken && hasRcUid) {
      return FutureBuilder<Uint8List?>(
        future: _fetchImageBytes(url),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          if (!snapshot.hasData || snapshot.data == null) {
            // Si le téléchargement échoue, essayer avec CachedNetworkImage comme dernier recours
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
                    name: 'ChannelFilesPage',
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
      // Utiliser FutureBuilder avec fetchProtectedImage pour les autres URLs
      return FutureBuilder<Uint8List?>(
        future: _fetchImageBytes(url),
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

  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      developer.log('_fetchImageBytes: URL = "$url"', name: 'ChannelFilesPage');
      final uri = Uri.parse(url);
      final hasRcToken = uri.queryParameters.containsKey('rc_token');
      final hasRcUid = uri.queryParameters.containsKey('rc_uid');

      final headers = <String, String>{};

      // Pour les URLs avec tokens Rocket.Chat, ne pas ajouter de header Authorization
      // Les tokens sont déjà dans l'URL
      if (!hasRcToken || !hasRcUid) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token') ?? '';
        if (token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
          developer.log('_fetchImageBytes: Ajout du header Authorization', name: 'ChannelFilesPage');
        } else {
          developer.log('_fetchImageBytes: Pas de token disponible', name: 'ChannelFilesPage');
        }
      } else {
        developer.log('_fetchImageBytes: URL a déjà les tokens Rocket.Chat (rc_token=${uri.queryParameters['rc_token']}, rc_uid=${uri.queryParameters['rc_uid']})', name: 'ChannelFilesPage');
        // Pour les URLs avec tokens Rocket.Chat, ne pas ajouter de header Authorization
        // Les tokens dans l'URL devraient suffire
      }

      developer.log('_fetchImageBytes: Headers = $headers', name: 'ChannelFilesPage');
      final response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 30));

      developer.log('_fetchImageBytes: Status code = ${response.statusCode}', name: 'ChannelFilesPage');
      if (response.statusCode == 200) {
        developer.log('_fetchImageBytes: Succès, ${response.bodyBytes.length} bytes', name: 'ChannelFilesPage');
        return response.bodyBytes;
      } else {
        developer.log('_fetchImageBytes: Échec HTTP ${response.statusCode}, body = ${response.body.length > 0 ? response.body.substring(0, response.body.length > 200 ? 200 : response.body.length) : "(vide)"}', name: 'ChannelFilesPage');
        // Si erreur 403 avec tokens, essayer avec le header Authorization aussi
        if (response.statusCode == 403 && hasRcToken && hasRcUid) {
          developer.log('_fetchImageBytes: Erreur 403 avec tokens, essai avec header Authorization', name: 'ChannelFilesPage');
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('auth_token') ?? '';
          if (token.isNotEmpty) {
            headers['Authorization'] = 'Bearer $token';
            final retryResponse = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 30));
            if (retryResponse.statusCode == 200) {
              developer.log('_fetchImageBytes: Succès avec header Authorization, ${retryResponse.bodyBytes.length} bytes', name: 'ChannelFilesPage');
              return retryResponse.bodyBytes;
            }
          }
        }
      }
      return null;
    } catch (e, s) {
      developer.log('Error fetching image bytes: $e', name: 'ChannelFilesPage', error: e, stackTrace: s);
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
      // Vérifier si c'est un fichier local ou une URL
      final isLocalFile = !widget.audioUrl.startsWith('http');

      if (isLocalFile) {
        // Pour les fichiers locaux, utiliser DeviceFileSource
        await _audioPlayer.setSource(DeviceFileSource(widget.audioUrl));
      } else {
        // Pour les URLs, utiliser setSourceUrl
        await _audioPlayer.setSourceUrl(widget.audioUrl);
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
        SnackBarHelper.showError(context, 'Erreur lors du chargement de l\'audio : $e');
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

// Screen pour afficher un PDF en plein écran
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
          developer.log('Error loading PDF: $error', name: 'ChannelFilesPage.PDF');
          SnackBarHelper.showError(context, 'Erreur lors du chargement du PDF: $error');
        },
        onRender: (pages) {
          developer.log('PDF rendered with $pages pages', name: 'ChannelFilesPage.PDF');
        },
        onPageError: (page, error) {
          developer.log('Error on page $page: $error', name: 'ChannelFilesPage.PDF');
          SnackBarHelper.showError(context, 'Erreur sur la page $page: $error');
        },
      ),
    );
  }
}