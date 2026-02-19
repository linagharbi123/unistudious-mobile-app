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
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/groupe_chat_page.dart';
import '../providers/auth_provider.dart';
import '../providers/loading_provider.dart';
import 'dart:async';

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
  
  String? currentUser;
  Timer? _refreshTimer; // Timer pour rafraîchir périodiquement la liste
  // Mémoriser les groupes marqués comme lus localement (pour éviter qu'ils soient re-marqués comme non lus lors du polling)
  final Set<String> _locallyMarkedAsRead = {};

  @override
  void initState() {
    super.initState();
    // S'assurer que le loadingProvider n'est pas actif au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);
        loadingProvider.hideLoading(); // S'assurer qu'il n'est pas actif
        _checkAuthAndFetchData();
        // Démarrer le polling pour les mises à jour en temps réel (sans WebSocket)
        _startRefreshTimer();
      }
    });
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
  
  /// Démarre un timer pour rafraîchir périodiquement la liste des groupes
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    developer.log('🔄 Démarrage du polling pour les mises à jour en temps réel (toutes les 2 secondes)', name: 'GroupesPage');
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        developer.log('⏹️ Arrêt du polling (widget non monté)', name: 'GroupesPage');
        return;
      }
      // Rafraîchir silencieusement la liste des groupes SANS afficher le loader
      developer.log('🔄 Polling: Rafraîchissement de la liste des groupes...', name: 'GroupesPage');
      _refreshGroupsSilently().then((_) {
        developer.log('✅ Polling: Liste des groupes rafraîchie (${mesGroupes.length} groupes privés, ${canauxGeneraux.length} canaux généraux)', name: 'GroupesPage');
      }).catchError((error) {
        developer.log('❌ Polling: Erreur lors du rafraîchissement: $error', name: 'GroupesPage');
      });
    });
  }
  
  /// Rafraîchit les groupes sans afficher de loader (pour le polling)
  Future<void> _refreshGroupsSilently() async {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (!authProvider.isLoggedIn) {
      return;
    }
    
    // Ne pas définir isLoading à true pour éviter d'afficher le loader
    List<String> errors = [];
    try {
      // Exécuter les deux appels en parallèle, même si l'un échoue
      await Future.wait([
        _loadMyGroupes().catchError((e) {
          developer.log('Error _loadMyGroupes (silent): $e');
          errors.add('Erreur lors du chargement des groupes privés');
          return null;
        }),
        _loadCanauxGeneraux().catchError((e) {
          developer.log('Error _loadCanauxGeneraux (silent): $e');
          errors.add('Erreur lors du chargement des canaux généraux');
          return null;
        }),
      ], eagerError: false).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          developer.log('Timeout lors du chargement silencieux des données');
          return [];
        },
      );
    } catch (e, s) {
      developer.log('Error during silent data fetch: $e', error: e, stackTrace: s);
      // Ne pas afficher d'erreur lors du polling silencieux
    }
    // Ne pas définir isLoading à false car on ne l'a pas mis à true
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
    
    // Ne définir isLoading à true QUE si on n'a pas encore de données (premier chargement)
    final isFirstLoad = mesGroupes.isEmpty && canauxGeneraux.isEmpty;
    if (mounted && isFirstLoad) {
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
      // TOUJOURS définir isLoading à false dans le finally (seulement si on l'avait mis à true)
      if (mounted && isFirstLoad) {
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
        developer.log('📥 _loadMyGroupes: reçu ${channels.length} groupes depuis /api/chat/my-channels', name: 'GroupesPage');
        
        // Stocker l'ancien état pour détecter les changements
        final oldGroupes = Map<String, Map<String, dynamic>>.fromEntries(
          mesGroupes.map((g) => MapEntry(g['room_id']?.toString() ?? '', g))
        );
        
        final List<Map<String, dynamic>> loaded = channels.map((channel) {
          final String lastDateStr = channel['last_date'] ?? '';
          final DateTime lastDate = lastDateStr.isNotEmpty
              ? DateTime.parse(lastDateStr).toLocal()
              : DateTime.now();
          final roomId = channel['room_id']?.toString() ?? channel['id']?.toString() ?? '';
          final lastMessage = channel['last_message']?.toString() ?? 'Aucun message';
          
          // Détecter si c'est un nouveau message
          final oldGroupe = oldGroupes[roomId];
          final oldLastDate = oldGroupe?['last_date']?.toString() ?? '';
          final oldLastMessage = oldGroupe?['last_message']?.toString() ?? '';
          final isNewMessage = oldGroupe != null && 
                              (oldLastDate != lastDateStr || oldLastMessage != lastMessage);
          // Vérifier si l'ancien groupe avait déjà des messages non lus
          final int oldUnreadCount = (oldGroupe?['unread'] ?? 0) as int;
          final wasUnread = oldUnreadCount > 0;
          
          // Utiliser la valeur de l'API si elle indique des messages non lus
          final apiUnread = (channel['unread'] ?? 0) as int;
          

          final wasLocallyMarkedAsRead = _locallyMarkedAsRead.contains(roomId);
          
          // Si l'API indique des messages non lus, retirer de la liste des groupes marqués comme lus
          if (apiUnread > 0 && wasLocallyMarkedAsRead) {
            _locallyMarkedAsRead.remove(roomId);
          }
          
          final unreadCount = apiUnread > 0 
              ? apiUnread 
              : (isNewMessage && !wasUnread && !wasLocallyMarkedAsRead
                  ? 1 
                  : (wasUnread && !wasLocallyMarkedAsRead ? oldUnreadCount : 0));
          
          if (isNewMessage || unreadCount > 0) {
            developer.log(
              '📨 Groupe roomId=$roomId, name=${channel['name']}, lastMessage=${lastMessage.length > 30 ? "${lastMessage.substring(0, 30)}..." : lastMessage}, oldDate=$oldLastDate, newDate=$lastDateStr, apiUnread=$apiUnread, oldUnread=$oldUnreadCount, finalUnread=$unreadCount',
              name: 'GroupesPage',
            );
          }
          
          return {
            'id': channel['id']?.toString() ?? '',
            'room_id': roomId,
            'name': channel['name']?.toString() ?? 'Groupe sans nom',
            'avatar_url': channel['avatar_url']?.toString() ?? '',
            'last_message': lastMessage,
            'time': DateFormat('HH:mm').format(lastDate),
            'last_date': lastDateStr,
            'members': channel['members'] ?? 0,
            'unread': unreadCount,
            'type': channel['type'] ?? 'private',
            'isLeader': channel['isLeader'] == true,
          };
        }).toList();
        
        // Trier les groupes par date du dernier message (les plus récents en haut)
        loaded.sort((a, b) {
          final dateA = a['last_date']?.toString() ?? '';
          final dateB = b['last_date']?.toString() ?? '';
          if (dateA.isEmpty && dateB.isEmpty) return 0;
          if (dateA.isEmpty) return 1; // Les groupes sans date en bas
          if (dateB.isEmpty) return -1; // Les groupes sans date en bas
          try {
            final dateTimeA = DateTime.parse(dateA);
            final dateTimeB = DateTime.parse(dateB);
            return dateTimeB.compareTo(dateTimeA); // Ordre décroissant (plus récent en haut)
          } catch (e) {
            return 0;
          }
        });
        
        final unreadCount = loaded.where((g) => (g['unread'] as int) > 0).length;
        developer.log(
          '✅ _loadMyGroupes terminé: ${loaded.length} groupes, $unreadCount avec messages non lus',
          name: 'GroupesPage',
        );
        
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
        developer.log('📥 _loadCanauxGeneraux: reçu ${channels.length} canaux depuis /api/chat/list-channels', name: 'GroupesPage');
        
        // Stocker l'ancien état pour détecter les changements
        final oldCanaux = Map<String, Map<String, dynamic>>.fromEntries(
          canauxGeneraux.map((c) => MapEntry(c['room_id']?.toString() ?? '', c))
        );
        
        final List<Map<String, dynamic>> loaded = channels.map((channel) {
          final String lastDateStr = channel['last_date'] ?? '';
          final DateTime lastDate = lastDateStr.isNotEmpty
              ? DateTime.parse(lastDateStr).toLocal()
              : DateTime.now();
          final roomId = channel['room_id']?.toString() ?? channel['id']?.toString() ?? '';
          final lastMessage = channel['last_message']?.toString() ?? 'Aucun message';
          
          // Détecter si c'est un nouveau message
          final oldCanal = oldCanaux[roomId];
          final oldLastDate = oldCanal?['last_date']?.toString() ?? '';
          final oldLastMessage = oldCanal?['last_message']?.toString() ?? '';
          final isNewMessage = oldCanal != null && 
                              (oldLastDate != lastDateStr || oldLastMessage != lastMessage);
          // Vérifier si l'ancien canal avait déjà des messages non lus
          final int oldUnreadCount = (oldCanal?['unread'] ?? 0) as int;
          final wasUnread = oldUnreadCount > 0;
          
          // Utiliser la valeur de l'API si elle indique des messages non lus
          final apiUnread = (channel['unread'] ?? 0) as int;
          
          // Marquer comme non lu si :
          // 1. L'API indique des messages non lus (apiUnread > 0) - toujours prioritaire
          //    Si l'API indique des messages non lus, on retire le canal de la liste des canaux marqués comme lus localement
          // 2. OU c'est un nouveau message ET ce n'était pas déjà marqué comme lu ET n'a pas été marqué comme lu localement
          // 3. OU c'était déjà marqué comme non lu ET le canal n'a pas été marqué comme lu localement
          //    (même si l'API retourne 0, on garde l'état local si le canal avait des messages non lus)
          final wasLocallyMarkedAsRead = _locallyMarkedAsRead.contains(roomId);
          
          // Si l'API indique des messages non lus, retirer de la liste des canaux marqués comme lus
          if (apiUnread > 0 && wasLocallyMarkedAsRead) {
            _locallyMarkedAsRead.remove(roomId);
          }
          
          final unreadCount = apiUnread > 0 
              ? apiUnread 
              : (isNewMessage && !wasUnread && !wasLocallyMarkedAsRead
                  ? 1 
                  : (wasUnread && !wasLocallyMarkedAsRead ? oldUnreadCount : 0));
          
          if (isNewMessage) {
            developer.log(
              '📨 Nouveau message détecté pour canal roomId=$roomId, name=${channel['name']}, lastMessage=${lastMessage.length > 30 ? "${lastMessage.substring(0, 30)}..." : lastMessage}, oldDate=$oldLastDate, newDate=$lastDateStr, unread=$unreadCount',
              name: 'GroupesPage',
            );
          }
          
          return {
            'id': channel['id']?.toString() ?? channel['_id']?.toString() ?? '',
            'room_id': roomId,
            'name': channel['name']?.toString() ?? channel['username']?.toString() ?? 'Canal sans nom',
            'avatar_url': channel['avatar_url']?.toString() ?? '',
            'last_message': lastMessage,
            'time': DateFormat('HH:mm').format(lastDate),
            'last_date': lastDateStr,
            'members': channel['members'] ?? 0,
            'unread': unreadCount,
            'type': channel['type'] ?? 'public',
            'isLeader': channel['isLeader'] == true,
          };
        }).toList();
        
        // Trier les canaux par date du dernier message (les plus récents en haut)
        loaded.sort((a, b) {
          final dateA = a['last_date']?.toString() ?? '';
          final dateB = b['last_date']?.toString() ?? '';
          if (dateA.isEmpty && dateB.isEmpty) return 0;
          if (dateA.isEmpty) return 1; // Les canaux sans date en bas
          if (dateB.isEmpty) return -1; // Les canaux sans date en bas
          try {
            final dateTimeA = DateTime.parse(dateA);
            final dateTimeB = DateTime.parse(dateB);
            return dateTimeB.compareTo(dateTimeA); // Ordre décroissant (plus récent en haut)
          } catch (e) {
            return 0;
          }
        });
        
        final unreadCount = loaded.where((c) => (c['unread'] as int) > 0).length;
        developer.log(
          '✅ _loadCanauxGeneraux terminé: ${loaded.length} canaux, $unreadCount avec messages non lus',
          name: 'GroupesPage',
        );
        
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
                        }
                      } catch (e) {
                        // Erreur silencieuse
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
            // Vérifier si le groupe a des messages non lus
            final unreadValue = item['unread'];
            // Convertir en int pour la comparaison
            int unreadInt = 0;
            if (unreadValue != null) {
              if (unreadValue is int) {
                unreadInt = unreadValue;
              } else if (unreadValue is num) {
                unreadInt = unreadValue.toInt();
              } else if (unreadValue == true) {
                unreadInt = 1;
              }
            }
            final isUnread = unreadInt > 0;
            
            // Log pour déboguer seulement si isUnread est true
            if (isUnread) {
              developer.log(
                '🔴 Widget build avec BOLD: name=${item['name']}, unreadValue=$unreadValue, unreadInt=$unreadInt, isUnread=$isUnread',
                name: 'GroupesPage',
              );
            }
            
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: isDark ? theme.cardColor : Colors.white,
              child: ListTile(
                leading: _buildAvatarWidget(item['avatar_url'], item['name'], size: 48),
                title: Text(
                  item['name'] ?? 'Sans nom',
                  style: GoogleFonts.poppins(
                    fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                subtitle: Text(
                  item['last_message'] ?? 'Aucun message',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                    color: isDark ? Colors.white70 : Colors.grey[600],
                  ),
                ),
                trailing: Text(
                  item['time'] ?? '',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                ),
                onTap: () async {
                  // Marquer le groupe comme lu avant d'ouvrir le chat
                  final roomId = item['room_id']?.toString();
                  if (roomId != null && item['unread'] != null && (item['unread'] as int) > 0) {
                    setState(() {
                      // Mémoriser que ce groupe a été marqué comme lu localement
                      _locallyMarkedAsRead.add(roomId);
                      
                      // Trouver et mettre à jour dans mesGroupes
                      final groupeIndex = mesGroupes.indexWhere(
                        (g) => g['room_id']?.toString() == roomId,
                      );
                      if (groupeIndex >= 0) {
                        mesGroupes[groupeIndex]['unread'] = 0;
                      }
                      
                      // Trouver et mettre à jour dans canauxGeneraux
                      final canalIndex = canauxGeneraux.indexWhere(
                        (c) => c['room_id']?.toString() == roomId,
                      );
                      if (canalIndex >= 0) {
                        canauxGeneraux[canalIndex]['unread'] = 0;
                      }
                    });
                  }
                  
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
                  
                  // Ne pas rafraîchir automatiquement pour éviter de perdre l'état unread des autres groupes
                  // Le polling se chargera de mettre à jour la liste périodiquement
                  
                  if (result != null && result is Map && (result['left'] == true || result['deleted'] == true)) {
                    final resultRoomId = result['roomId']?.toString();
                    if (resultRoomId != null && mounted) {
                      setState(() {
                        mesGroupes.removeWhere((g) =>
                        g['room_id']?.toString() == resultRoomId || g['id']?.toString() == resultRoomId);
                        canauxGeneraux.removeWhere((c) =>
                        c['room_id']?.toString() == resultRoomId || c['id']?.toString() == resultRoomId);
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