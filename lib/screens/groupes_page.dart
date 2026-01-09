// lib/pages/groupes_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../screens/groupe_chat_page.dart';
import '../providers/auth_provider.dart';
import '../providers/loading_provider.dart';

class GroupesPage extends StatefulWidget {
  const GroupesPage({super.key});
  @override
  State<GroupesPage> createState() => _GroupesPageState();
}

class _GroupesPageState extends State<GroupesPage> {
  // Mes groupes privés (nouvelle API)
  List<Map<String, dynamic>> mesGroupes = [];
  // Canaux généraux (ancienne API publique)
  List<Map<String, dynamic>> canauxGeneraux = [];
  // Texte de recherche propagé depuis MessageriePage
  String _searchQuery = '';
  bool isLoading = true;
  String? errorMessage;
  // Cache des avatars SVG
  final Map<String, Map<String, dynamic>> _avatarSvgCache = {};
  final Map<String, Future<Map<String, dynamic>>> _avatarFutures = {};

  @override
  void initState() {
    super.initState();
    // S'assurer que le loadingProvider n'est pas actif au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);
        loadingProvider.hideLoading(); // S'assurer qu'il n'est pas actif
        _checkAuthAndFetchData();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // S'assurer que le loadingProvider n'est pas actif quand la page est affichée
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);
        if (loadingProvider.isLoading && !isLoading) {
          // Si le loadingProvider global est actif mais pas notre état local, le désactiver
          loadingProvider.hideLoading();
        }
      }
    });
  }

  Future<void> _checkAuthAndFetchData() async {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (!authProvider.isLoggedIn) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Veuillez vous connecter pour continuer.')),
            );
            Navigator.pushReplacementNamed(context, '/login');
          }
        });
      }
      return;
    }
    
    // Toujours définir isLoading à true au début
    if (mounted) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }
    
    List<String> errors = [];
    try {
      // Exécuter les deux appels en parallèle, même si l'un échoue, avec un timeout global
      await Future.wait([
        _loadMyGroupes().catchError((e) {
          developer.log('Error _loadMyGroupes: $e');
          errors.add('Erreur lors du chargement des groupes privés');
          return null;
        }),
        _loadCanauxGeneraux().catchError((e) {
          developer.log('Error _loadCanauxGeneraux: $e');
          errors.add('Erreur lors du chargement des canaux généraux');
          return null;
        }),
      ], eagerError: false).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          developer.log('Timeout lors du chargement des données');
          if (mounted) {
            setState(() {
              errorMessage = 'Le chargement a pris trop de temps. Veuillez réessayer.';
            });
          }
          return [];
        },
      );
      
      // Si les deux ont échoué et qu'aucune donnée n'a été chargée, afficher un message d'erreur
      if (mounted) {
        if (errors.isNotEmpty && mesGroupes.isEmpty && canauxGeneraux.isEmpty) {
          setState(() {
            errorMessage = errors.join('\n');
          });
        } else if (errors.isNotEmpty) {
          // Si au moins une partie a réussi, effacer le message d'erreur précédent
          setState(() {
            errorMessage = null;
          });
        }
      }
    } catch (e, s) {
      developer.log('Error during data fetch: $e', error: e, stackTrace: s);
      if (mounted) {
        setState(() {
          errorMessage = 'Erreur lors du chargement: $e';
        });
      }
    } finally {
      // TOUJOURS définir isLoading à false dans le finally
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // CHARGEMENT DES GROUPES PRIVÉS (nouvelle API)
  Future<void> _loadMyGroupes() async {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      final response = await authProvider
          .authenticatedRequest('GET', '/api/chat/my-channels')
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] != true) {
          developer.log('API my-channels: success = false');
          if (mounted) {
            setState(() {
              mesGroupes = [];
            });
          }
          return;
        }
        final List<dynamic> channels = jsonResponse['channels'] ?? [];
        final List<Map<String, dynamic>> loaded = channels.map((channel) {
          final String lastDateStr = channel['last_date'] ?? '';
          final DateTime lastDate = lastDateStr.isNotEmpty
              ? DateTime.parse(lastDateStr).toLocal()
              : DateTime.now();
          return {
            'id': channel['id']?.toString() ?? '',
            'room_id': channel['room_id']?.toString() ?? channel['id']?.toString() ?? '',
            'name': channel['name']?.toString() ?? 'Groupe sans nom',
            'avatar_url': channel['avatar_url']?.toString() ?? '',
            'last_message': channel['last_message']?.toString() ?? 'Aucun message',
            'time': DateFormat('HH:mm').format(lastDate),
            'members': channel['members'] ?? 0,
            'unread': channel['unread'] ?? 0,
            'type': channel['type'] ?? 'private',
            'isLeader': channel['isLeader'] == true,
          };
        }).toList();
        if (mounted) {
          setState(() {
            mesGroupes = loaded;
          });
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        if (mounted) {
          _handleUnauthenticated();
        }
        if (mounted) {
          setState(() {
            mesGroupes = [];
          });
        }
      } else {
        developer.log('Erreur HTTP ${response.statusCode} pour my-channels');
        if (mounted) {
          setState(() {
            mesGroupes = [];
          });
        }
      }
    } catch (e, s) {
      developer.log('Error _loadMyGroupes: $e', error: e, stackTrace: s);
      // Réinitialiser la liste en cas d'erreur pour éviter un état incohérent
      if (mounted) {
        setState(() {
          mesGroupes = [];
        });
      }
      // Propager l'erreur pour que _checkAuthAndFetchData puisse la gérer
      rethrow;
    }
  }

  // CHARGEMENT DES CANAUX GÉNÉRAUX (ancienne API)
  Future<void> _loadCanauxGeneraux() async {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      final response = await authProvider
          .authenticatedRequest('GET', '/api/chat/list-channels')
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
        if (jsonResponse['success'] != true) {
          developer.log('API list-channels: success = false');
          if (mounted) {
            setState(() {
              canauxGeneraux = [];
            });
          }
          return;
        }
        final List<dynamic> channels = jsonResponse['channels'] ?? [];
        final List<Map<String, dynamic>> loaded = channels.map((channel) {
          final String lastDateStr = channel['last_date'] ?? '';
          final DateTime lastDate = lastDateStr.isNotEmpty
              ? DateTime.parse(lastDateStr).toLocal()
              : DateTime.now();
          return {
            'id': channel['id']?.toString() ?? channel['_id']?.toString() ?? '',
            'room_id': channel['room_id']?.toString() ?? channel['id']?.toString() ?? '',
            'name': channel['name']?.toString() ?? channel['username']?.toString() ?? 'Canal sans nom',
            'avatar_url': channel['avatar_url']?.toString() ?? '',
            'last_message': channel['last_message']?.toString() ?? 'Aucun message',
            'time': DateFormat('HH:mm').format(lastDate),
            'members': channel['members'] ?? 0,
            'unread': channel['unread'] ?? 0,
            'type': channel['type'] ?? 'public',
            'isLeader': channel['isLeader'] == true,
          };
        }).toList();
        if (mounted) {
          setState(() {
            canauxGeneraux = loaded;
          });
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        if (mounted) {
          _handleUnauthenticated();
        }
        if (mounted) {
          setState(() {
            canauxGeneraux = [];
          });
        }
      } else {
        developer.log('Erreur HTTP ${response.statusCode} pour list-channels');
        if (mounted) {
          setState(() {
            canauxGeneraux = [];
          });
        }
      }
    } catch (e, s) {
      developer.log('Error _loadCanauxGeneraux: $e', error: e, stackTrace: s);
      // Réinitialiser la liste en cas d'erreur pour éviter un état incohérent
      if (mounted) {
        setState(() {
          canauxGeneraux = [];
        });
      }
      // Propager l'erreur pour que _checkAuthAndFetchData puisse la gérer
      rethrow;
    }
  }

  void _handleUnauthenticated() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.')),
      );
      Navigator.pushReplacementNamed(context, '/login');
    }
    Provider.of<AuthProvider>(context, listen: false).logout();
  }

  // ==================== NOUVELLE BOÎTE DE DIALOGUE ====================
  Future<void> _createNewChannel() async {
    final TextEditingController nameController = TextEditingController();
    final List<String> selectedMembers = [];
    bool readOnly = false;

    final BuildContext pageContext = context;
    final theme = Theme.of(pageContext);
    final isDark = theme.brightness == Brightness.dark;

    final Color dialogBg = isDark ? theme.dialogBackgroundColor : Colors.white;
    final Color cardBg = isDark ? theme.cardColor : const Color(0xFFF3F4F6);
    final Color textColor = isDark ? theme.colorScheme.onSurface : Colors.black87;
    final Color hintColor = isDark ? theme.colorScheme.onSurface.withOpacity(0.7) : Colors.grey[700]!;
    final Color primary = theme.colorScheme.primary;
    const Color tickBackground = Colors.deepPurple;

    // Chargement des utilisateurs depuis l'API
    List<Map<String, dynamic>> allUsers = [];
    bool usersLoading = true;
    String? usersError;

    final authProvider = Provider.of<AuthProvider>(pageContext, listen: false);

    try {
      final response = await authProvider
          .authenticatedRequest('GET', '/api/chat/fetch-users')
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        if (json['success'] == true && json['users'] is List) {
          allUsers = List<Map<String, dynamic>>.from(json['users']);
        }
      }
    } catch (e) {
      usersError = 'Impossible de charger les membres';
      developer.log('Error fetching users: $e');
    } finally {
      usersLoading = false;
    }

    if (!mounted) return;

    await showDialog(
      context: pageContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => GestureDetector(
          onTap: () {
            // Retire le focus du TextField quand on tape ailleurs
            FocusScope.of(dialogContext).unfocus();
          },
          child: AlertDialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Créer un groupe',
                  style: GoogleFonts.poppins(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: hintColor),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nom du groupe',
                      style: GoogleFonts.poppins(color: hintColor, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: textColor),
                      onChanged: (_) {
                        // Rebuild le dialogue pour mettre à jour l'état du bouton "Créer"
                        setStateDialog(() {});
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: cardBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: primary),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Ajouter des membres',
                      style: GoogleFonts.poppins(color: hintColor, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: usersLoading
                          ? const Center(child: CircularProgressIndicator())
                          : usersError != null
                          ? Center(
                        child: Text(
                          usersError!,
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      )
                          : allUsers.isEmpty
                          ? const Center(child: Text('Aucun membre disponible'))
                          : ListView.builder(
                        shrinkWrap: true,
                        itemCount: allUsers.length,
                        itemBuilder: (context, index) {
                          final user = allUsers[index];
                          final String userId = user['id']?.toString() ?? '';
                          final String userName = user['name']?.toString() ?? 'Sans nom';
                          final String avatarUrl = user['avatar']?.toString() ?? '';
                          final String username = user['username']?.toString() ?? '';

                          final bool isSelected = selectedMembers.contains(userId);

                          return CheckboxListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            secondary: _buildAvatarWidget(avatarUrl, username, size: 36),
                            title: Text(
                              userName,
                              style: TextStyle(color: textColor, fontSize: 14),
                            ),
                            value: isSelected,
                            activeColor: tickBackground,
                            checkColor: Colors.white,
                            side: BorderSide(color: hintColor),
                            onChanged: (val) {
                              setStateDialog(() {
                                if (val == true) {
                                  selectedMembers.add(userId);
                                } else {
                                  selectedMembers.remove(userId);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Checkbox(
                          value: readOnly,
                          activeColor: tickBackground,
                          checkColor: Colors.white,
                          side: BorderSide(color: hintColor),
                          onChanged: (val) => setStateDialog(() => readOnly = val ?? false),
                        ),
                        Text(
                          'Canal en lecture seule',
                          style: GoogleFonts.poppins(color: hintColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              SizedBox(
                width: double.maxFinite,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: nameController.text.trim().isEmpty || selectedMembers.isEmpty
                        ? null
                        : () async {
                      Navigator.pop(dialogContext);
                      final loadingProvider = Provider.of<LoadingProvider>(pageContext, listen: false);
                      loadingProvider.showLoading();
                      try {
                        final response = await authProvider.authenticatedRequest(
                          'POST',
                          '/api/channel-create',
                          body: jsonEncode({
                            "name": nameController.text.trim(),
                            "readOnly": readOnly,
                            "members": selectedMembers,
                          }),
                        );
                        if (!mounted) return;
                        if (response.statusCode == 200) {
                          final jsonResponse = jsonDecode(response.body);
                          if (jsonResponse['status'] == 'success' && jsonResponse['data']?['channel'] != null) {
                            final channel = jsonResponse['data']['channel'];

                            // Met à jour le canal Rocket.Chat en lecture seule si nécessaire
                            final String? roomId = channel['_id']?.toString();
                            if (roomId != null && roomId.isNotEmpty) {
                              try {
                                await authProvider.authenticatedRequest(
                                  'POST',
                                  '/api/chat/channel-update-read-only',
                                  headers: {
                                    // On force le form-data (x-www-form-urlencoded)
                                    'Content-Type': 'application/x-www-form-urlencoded',
                                  },
                                  body:
                                      'roomId=$roomId&readOnly=${readOnly ? 'true' : 'false'}',
                                );
                              } catch (e, s) {
                                developer.log(
                                  'Error channel-update-read-only: $e',
                                  error: e,
                                  stackTrace: s,
                                );
                              }
                            }

                            final newChannelMap = {
                              'id': channel['_id']?.toString() ?? '',
                              'room_id': channel['_id']?.toString() ?? '',
                              'name': channel['name']?.toString() ?? nameController.text.trim(),
                              'avatar_url': '',
                              'last_message': 'Aucun message',
                              'time': DateFormat('HH:mm').format(DateTime.now()),
                              'members': channel['usersCount'] ?? 1,
                              'unread': 0,
                              'type': 'private',
                              'isLeader': true,
                            };
                            setState(() {
                              mesGroupes.insert(0, newChannelMap);
                            });
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              SnackBar(content: Text('Canal "${nameController.text.trim()}" créé !')),
                            );
                          }
                        } else {
                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            const SnackBar(content: Text('Échec de la création du canal.')),
                          );
                        }
                      } catch (e) {
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
                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            const SnackBar(content: Text('Erreur réseau ou serveur.')),
                          );
                        }
                      } finally {
                        if (mounted) loadingProvider.hideLoading();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      disabledBackgroundColor: Colors.deepPurple.withOpacity(0.6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      'Créer',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  // ====================================================================

  // === TOUT LE CODE AVATAR RESTE IDENTIQUE ===
  Widget _buildAvatarWidget(String? url, String username, {double size = 40}) {
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.deepPurple,
        child: Icon(Icons.group, size: size * 0.6, color: Colors.white),
      );
    }
    if (url.startsWith('data:image/png;base64,')) {
      try {
        final bytes = base64Decode(url.split(',').last);
        return ClipOval(
          child: Image.memory(bytes, fit: BoxFit.cover, width: size, height: size),
        );
      } catch (_) {
        return CircleAvatar(
          radius: size / 2,
          backgroundColor: Colors.deepPurple,
          child: Icon(Icons.group, size: size * 0.6, color: Colors.white),
        );
      }
    }
    final isSvg = url.endsWith('.svg') || url.contains('message.unistudious.com/avatar/');
    if (isSvg) {
      final cacheKey = username.isNotEmpty ? username : url;
      if (_avatarSvgCache.containsKey(cacheKey)) {
        final cached = _avatarSvgCache[cacheKey]!;
        return CircleAvatar(
          backgroundColor: cached['color'] as Color,
          radius: size / 2,
          child: Text(
            cached['initial'] as String,
            style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        );
      }
      if (!_avatarFutures.containsKey(cacheKey)) {
        _avatarFutures[cacheKey] = _loadAndCacheSvg(url, cacheKey);
      }
      return SizedBox(
        width: size,
        height: size,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _avatarFutures[cacheKey],
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (snapshot.hasData) {
              final style = snapshot.data!;
              return CircleAvatar(
                backgroundColor: style['color'] as Color,
                radius: size / 2,
                child: Text(
                  style['initial'] as String,
                  style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              );
            }
            return CircleAvatar(
              radius: size / 2,
              backgroundColor: Colors.deepPurple,
              child: Icon(Icons.group, size: size * 0.6, color: Colors.white),
            );
          },
        ),
      );
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorWidget: (_, __, ___) => CircleAvatar(
          radius: size / 2,
          backgroundColor: Colors.deepPurple,
          child: Icon(Icons.group, size: size * 0.6, color: Colors.white),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _loadAndCacheSvg(String avatarUrl, String cacheKey) async {
    try {
      final svgData = await _fetchAndSanitizeSvg(avatarUrl, cacheKey);
      if (svgData == null || svgData.isEmpty) {
        return {'color': Colors.deepPurple, 'initial': '?'};
      }
      final style = _extractAvatarStyleFromSvg(svgData);
      _avatarSvgCache[cacheKey] = style;
      return style;
    } catch (e) {
      return {'color': Colors.deepPurple, 'initial': '?'};
    }
  }

  Future<String?> _fetchAndSanitizeSvg(String url, String username) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      if (!(response.headers['content-type'] ?? '').contains('svg')) return null;
      return response.body;
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic> _extractAvatarStyleFromSvg(String svg) {
    final rectMatch = RegExp(r'<rect[^>]*fill="([^"]+)"', caseSensitive: false).firstMatch(svg);
    final bgFill = rectMatch?.group(1) ?? '#6200EE';
    final textMatch = RegExp(r'<text[^>]*>([^<]+)</text>', caseSensitive: false).firstMatch(svg);
    final rawText = (textMatch?.group(1) ?? '').trim();
    final initial = rawText.isNotEmpty ? rawText[0].toUpperCase() : '?';
    return {'color': _colorFromHex(bgFill), 'initial': initial};
  }

  Color _colorFromHex(String hex) {
    var value = hex.replaceAll('#', '');
    if (value.length == 6) value = 'FF$value';
    return value.length == 8 ? Color(int.parse(value, radix: 16)) : Colors.deepPurple;
  }

  // Appelé par MessageriePage via GlobalKey pour appliquer la recherche
  void applySearch(String query) {
    if (!mounted) return;
    setState(() {
      _searchQuery = query.trim().toLowerCase();
    });
  }

  Widget _buildSection(String title, List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const SizedBox.shrink();

    // Appliquer le filtre de recherche sur le nom du groupe/canal
    final List<Map<String, dynamic>> filteredItems;
    if (_searchQuery.isEmpty) {
      filteredItems = items;
    } else {
      filteredItems = items.where((item) {
        final name = (item['name']?.toString() ?? '').toLowerCase();
        return name.contains(_searchQuery);
      }).toList();
    }

    if (filteredItems.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredItems.length,
          itemBuilder: (context, index) {
            final item = filteredItems[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: isDark ? theme.cardColor : Colors.white,
              child: ListTile(
                leading: _buildAvatarWidget(item['avatar_url'], item['name'], size: 48),
                title: Text(
                  item['name'],
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  item['last_message'],
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                trailing: Text(
                  item['time'] ?? '',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                ),
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GroupeChatPage(
                        groupId: item['room_id'],
                        groupName: item['name'],
                        avatarUrl: item['avatar_url'],
                        isPublicChannel: (item['type']?.toString().toLowerCase() == 'public'),
                        isLeader: item['isLeader'] == true,
                      ),
                    ),
                  );
                  if (result != null && result is Map && (result['left'] == true || result['deleted'] == true)) {
                    final roomId = result['roomId']?.toString();
                    if (roomId != null && mounted) {
                      setState(() {
                        mesGroupes.removeWhere((g) =>
                        g['room_id']?.toString() == roomId || g['id']?.toString() == roomId);
                        canauxGeneraux.removeWhere((c) =>
                        c['room_id']?.toString() == roomId || c['id']?.toString() == roomId);
                      });
                    }
                  }
                },
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // S'assurer que le loadingProvider global n'est pas actif quand on affiche notre propre indicateur
    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);
    if (loadingProvider.isLoading && !isLoading) {
      // Si le loadingProvider global est actif mais pas notre état local, le désactiver
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          loadingProvider.hideLoading();
        }
      });
    }
    
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null && mesGroupes.isEmpty && canauxGeneraux.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64),
            const SizedBox(height: 16),
            Text(errorMessage!, textAlign: TextAlign.center),
            ElevatedButton(onPressed: _checkAuthAndFetchData, child: const Text('Réessayer')),
          ],
        ),
      );
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewChannel,
        backgroundColor: Colors.deepPurple,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => isLoading = true);
          await _checkAuthAndFetchData();
        },
        child: ListView(
          children: [
            _buildSection("Groupes", mesGroupes),
            _buildSection("Canaux généraux", canauxGeneraux),
            if (mesGroupes.isEmpty && canauxGeneraux.isEmpty)
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: Center(
                  child: Text(
                    'Aucun groupe ni canal pour le moment',
                    style: GoogleFonts.poppins(color: isDark ? Colors.white70 : Colors.grey[600]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}