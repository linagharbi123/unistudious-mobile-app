import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:developer' as developer;
import '../providers/auth_provider.dart';
import '../models/app_bar_provider.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/sidebar.dart';
import 'user_posts_page.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import 'dart:async';
import '../utils/connection_checker.dart';

class ReactionButton extends StatefulWidget {
  final String postId;
  final String? userReaction;
  final String currentUserId;
  final Function(String, String?, String) onReactionSelected;

  const ReactionButton({
    super.key,
    required this.postId,
    required this.userReaction,
    required this.currentUserId,
    required this.onReactionSelected,
  });

  @override
  State<ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<ReactionButton> {
  OverlayEntry? _overlayEntry;
  String? _selectedReaction;

  final List<String> reactions = ["👍", "❤️", "😂", "😮", "😢", "😡", "🔥", "💯"];
  final Map<String, String> reactionLabels = {
    "👍": "J'aime",
    "❤️": "Love",
    "😂": "Haha",
    "😮": "Wow",
    "😢": "Triste",
    "😡": "Grr",
    "🔥": "Génial",
    "💯": "Parfait",
  };

  @override
  void initState() {
    super.initState();
    _selectedReaction = widget.userReaction;
    developer.log(
      'ReactionButton initialized with userReaction: ${widget.userReaction}',
      name: 'ReactionButton',
    );
  }

  @override
  void didUpdateWidget(covariant ReactionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userReaction != widget.userReaction) {
      developer.log(
        'ReactionButton updated with new userReaction: ${widget.userReaction}',
        name: 'ReactionButton',
      );
      setState(() {
        _selectedReaction = widget.userReaction;
      });
    }
  }

  void _showReactions(BuildContext context) {
    final theme = Theme.of(context);
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => GestureDetector(
        onTap: _removeOverlay,
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned(
                left: offset.dx - 20,
                top: offset.dy - 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: [
                      BoxShadow(
                        color: theme.shadowColor.withOpacity(0.2),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: reactions.map((emoji) {
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedReaction = emoji;
                          });
                          widget.onReactionSelected(
                              widget.postId, emoji, widget.currentUserId);
                          _removeOverlay();
                          developer.log(
                            'Reaction selected: $emoji for post: ${widget.postId}',
                            name: 'ReactionButton',
                          );
                          // Debug log for reactions
                          final parentState =
                          context.findAncestorStateOfType<_SocialFeedPageState>();
                          if (parentState != null) {
                            final postIndex = parentState.posts
                                .indexWhere((post) => post['id'] == widget.postId);
                            if (postIndex != -1) {
                              final reactionList =
                              parentState.posts[postIndex]['reactions'];
                              developer.log(
                                'Current reaction list for post ${widget.postId}: $reactionList',
                                name: 'ReactionButton',
                              );
                            }
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 26),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
    developer.log('Reactions overlay shown for post: ${widget.postId}',
        name: 'ReactionButton');
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    developer.log('Reactions overlay removed', name: 'ReactionButton');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onLongPress: () => _showReactions(context),
      onTap: () {
        if (_selectedReaction != null) {
          setState(() {
            _selectedReaction = null;
          });
          widget.onReactionSelected(widget.postId, null, widget.currentUserId);
          developer.log(
            'Reaction removed for post: ${widget.postId}',
            name: 'ReactionButton',
          );
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selectedReaction == null) ...[
            Icon(
              Icons.thumb_up_alt_outlined,
              size: 20,
              color: theme.hintColor,
            ),
            const SizedBox(width: 6),
          ] else ...[
            Text(
              _selectedReaction!,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            _selectedReaction != null
                ? reactionLabels[_selectedReaction] ?? "Réagir"
                : "Réagir",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _selectedReaction != null
                  ? theme.textTheme.bodyMedium?.color
                  : theme.hintColor,
              fontFamily: GoogleFonts.poppins().fontFamily,
              fontSize: 14,
            ) ??
                TextStyle(
                  color: _selectedReaction != null
                      ? theme.textTheme.bodyMedium?.color
                      : theme.hintColor,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  fontSize: 14,
                ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
    developer.log('ReactionButton disposed', name: 'ReactionButton');
  }
}

class ReactionSheet extends StatelessWidget {
  final Map<String, dynamic> apiReactions;

  const ReactionSheet({super.key, required this.apiReactions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dynamic byEmojiData = apiReactions['byEmoji'];
    final Map<String, dynamic> byEmoji;
    
    if (byEmojiData is Map) {
      byEmoji = Map<String, dynamic>.from(byEmojiData);
    } else if (byEmojiData is List) {
      // Si c'est une liste, convertir en Map vide ou gérer selon la structure
      byEmoji = <String, dynamic>{};
    } else {
      byEmoji = <String, dynamic>{};
    }
    
    final int totalReactions = apiReactions['total'] ?? 0;
    final List<MapEntry<String, dynamic>> emojiList = byEmoji.entries.toList();

    developer.log(
      'ReactionSheet data for post: byEmoji: $byEmoji, total: $totalReactions',
      name: 'ReactionSheet',
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Réactions ($totalReactions)',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ) ??
                    TextStyle(
                      fontFamily: GoogleFonts.poppins().fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.titleLarge?.color,
                    ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  color: theme.iconTheme.color,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  developer.log('Reaction sheet closed', name: 'ReactionSheet');
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (emojiList.isEmpty && totalReactions == 0)
            Center(
              child: Text(
                'Aucune réaction pour le moment.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 16,
                  color: theme.hintColor,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ) ??
                    TextStyle(
                      fontSize: 16,
                      color: theme.hintColor,
                      fontFamily: GoogleFonts.poppins().fontFamily,
                    ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: emojiList.length,
                itemBuilder: (context, index) {
                  final emoji = emojiList[index].key;
                  final count = emojiList[index].value;
                  return ListTile(
                    leading: Text(
                      emoji,
                      style: const TextStyle(fontSize: 24),
                    ),
                    title: Text(
                      '$count réaction${count > 1 ? 's' : ''}',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontFamily: GoogleFonts.poppins().fontFamily,
                        fontSize: 16,
                      ) ??
                          TextStyle(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                            fontSize: 16,
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class SocialFeedPage extends StatefulWidget {
  const SocialFeedPage({Key? key}) : super(key: key);

  @override
  _SocialFeedPageState createState() => _SocialFeedPageState();
}

class _SocialFeedPageState extends State<SocialFeedPage> {
  final TextEditingController _statusController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool isLoading = true;
  bool isLoadingMore = false;
  bool isPosting = false;
  String? errorMessage;
  bool isConnectionError = false;
  String? _finalUsername;
  String? targetUserId;
  String? _currentUserId;
  List<Map<String, dynamic>> posts = [];
  XFile? _selectedImage;
  int currentPage = 1;
  int totalPages = 1;
  final ScrollController _scrollController = ScrollController();
  String? _statusLengthError;
  Timer? _connectionCheckTimer;

  @override
  void initState() {
    super.initState();
    developer.log('Initializing SocialFeedPage', name: 'SocialFeedPage');
    _startConnectionMonitoring();
    
    // Configurer l'AppBar via le provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final appBarProvider = Provider.of<AppBarProvider>(context, listen: false);
        appBarProvider.updateConfig(2, AppBarConfig(
          title: 'Fil Social',
        ));
      }
    });
    
    _focusNode.addListener(() {
      setState(() {});
      developer.log('Focus changed, hasFocus: ${_focusNode.hasFocus}',
          name: 'SocialFeedPage');
    });
    
    // Defer auth check until after the widget tree is built
    // to avoid accessing Theme.of() before initState completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkAuthAndFetchData();
      }
    });
    
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200 &&
          !isLoading &&
          !isLoadingMore &&
          currentPage < totalPages) {
        _fetchMorePosts();
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
            _checkAuthAndFetchData();
          }
        });
      }
    });
  }

  Future<String?> _fetchUserIdByUsername(String username) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for fetching user ID',
          name: 'SocialFeedPage');
      return null;
    }

    final uri = Uri.parse(
        'https://www.unistudious.com/api/social-media-get-userid-by-username');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['username'] = username;

      developer.log('Fetching user ID for username: $username',
          name: 'SocialFeedPage');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      developer.log(
          'User ID API response: $responseBody, status: ${response.statusCode}',
          name: 'SocialFeedPage');

      final responseData = jsonDecode(responseBody);
      if (response.statusCode == 200 && responseData['id'] != null) {
        return responseData['id']?.toString();
      } else {
        developer.log(
          'Failed to fetch user ID: ${response.statusCode}, response: $responseBody',
          name: 'SocialFeedPage',
        );
        return null;
      }
    } catch (e, stackTrace) {
      developer.log('Error fetching user ID: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<String?> _ensureCurrentUserId() async {
    if (_currentUserId != null &&
        _currentUserId!.isNotEmpty &&
        _currentUserId != 'current_user') {
      return _currentUserId;
    }
    if (_finalUsername != null && _finalUsername != 'Unknown User') {
      final resolvedId = await _fetchUserIdByUsername(_finalUsername!);
      if (resolvedId != null && mounted) {
        setState(() {
          _currentUserId = resolvedId;
          targetUserId = resolvedId;
        });
      }
      return resolvedId;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _fetchProfileDetails(String userId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for fetching profile details',
          name: 'SocialFeedPage');
      return null;
    }

    final uri = Uri.parse(
        'https://www.unistudious.com/api/profile-details-social-media/$userId');
    try {
      developer.log('Fetching profile details for userId: $userId',
          name: 'SocialFeedPage');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${authProvider.currentToken}',
          'Content-Type': 'application/json',
        },
      );

      developer.log(
          'Profile details API response: ${response.body}, status: ${response.statusCode}',
          name: 'SocialFeedPage');
      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['data'] != null) {
        return responseData['data'];
      } else {
        developer.log(
          'Failed to fetch profile details: ${response.statusCode}, response: ${response.body}',
          name: 'SocialFeedPage',
        );
        return null;
      }
    } catch (e, stackTrace) {
      developer.log('Error fetching profile details: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> _reportStatus({
    required BuildContext context,
    required String accountId,
    required String statusId,
  }) async {
    if (!mounted) return;
    final commentController = TextEditingController();
    bool forwardValue = false;

    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              backgroundColor: theme.brightness == Brightness.dark
                  ? theme.cardColor
                  : Colors.white,
              title: Text(
                'Signaler le statut',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Commentaire',
                      hintText: 'Décrivez le problème...',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: theme.brightness == Brightness.dark
                          ? theme.cardColor
                          : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(
                      'Transférer le signalement',
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      'Transmettre aux autorités si nécessaire',
                      style: theme.textTheme.bodySmall,
                    ),
                    value: forwardValue,
                    onChanged: (val) {
                      setStateDialog(() {
                        forwardValue = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(
                    'Annuler',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (commentController.text.trim().isEmpty) {
                      // Ne ferme pas le dialogue, juste avertir
                      SnackBarHelper.showWarning(context, 'Veuillez saisir un commentaire.');
                      return;
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: Text(
                    'Envoyer',
                    style: theme.textTheme.labelLarge?.copyWith(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || confirmed != true) {
      commentController.dispose();
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      commentController.dispose();
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/report/status');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['accountId'] = accountId
        ..fields['statusId'] = statusId
        ..fields['comment'] = commentController.text.trim()
        ..fields['forward'] = forwardValue.toString();

      developer.log(
        'Reporting status $statusId for account $accountId with forward=$forwardValue',
        name: 'SocialFeedPage',
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body);

      if (response.statusCode == 200 && data['success'] == true) {
        SnackBarHelper.showSuccess(context, 'Statut signalé avec succès.');
      } else {
        throw Exception(data['message'] ?? 'Échec du signalement');
      }
    } catch (e) {
      developer.log('Error reporting status: $e', name: 'SocialFeedPage');
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors du signalement : $e');
      }
    } finally {
      commentController.dispose();
    }
  }

  Future<void> _checkAuthAndFetchData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    developer.log('Checking authentication status', name: 'SocialFeedPage');
    developer.log(
      'Token available: ${authProvider.currentToken != null ? "${authProvider.currentToken!.substring(0, 5)}..." : "null"}',
      name: 'SocialFeedPage',
    );

    if (!authProvider.isLoggedIn) {
      developer.log('No token found, redirecting to login',
          name: 'SocialFeedPage');
      SnackBarHelper.showWarning(context, 'Veuillez vous connecter pour continuer.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    await _fetchSocialFeed(page: 1);
  }

  Future<List<Map<String, dynamic>>> _fetchComments(String postId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      final uri =
      Uri.parse('https://www.unistudious.com/api/social-media-get-comment');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      developer.log('Fetching comments for post: $postId', name: 'SocialFeedPage');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      developer.log(
          'Comment API response: $responseBody, status: ${response.statusCode}',
          name: 'SocialFeedPage');

      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 &&
          responseData['status'] == 'success' &&
          responseData['data'] != null) {
        final List<dynamic> comments = responseData['data'] ?? [];
        developer.log('Number of comments received: ${comments.length}',
            name: 'SocialFeedPage');

        return comments.map((comment) {
          developer.log('Processing comment: $comment', name: 'SocialFeedPage');

          final account = comment['account'];
          String username = 'Unknown User';
          String userId = '';
          String profileUrl = '';

          if (account != null) {
            developer.log('Account data: $account', name: 'SocialFeedPage');
            username = (account['display_name']?.toString().trim().isNotEmpty ??
                false)
                ? account['display_name']
                : account['username']?.toString() ?? 'Unknown User';
            userId = account['id']?.toString() ?? '';
            profileUrl = account['avatar']?.toString() ?? '';
          } else {
            developer.log('Warning: comment.account is null',
                name: 'SocialFeedPage');
          }

          String text = _stripHtml(comment['content'] ?? '');
          String timeAgo = _timeAgo(DateTime.parse(
              comment['created_at'] ?? DateTime.now().toIso8601String()));

          return {
            "id": comment['id']?.toString() ?? '',
            "username": username,
            "userId": userId,
            "text": text,
            "timeAgo": timeAgo,
            "profileUrl": profileUrl,
          };
        }).toList();
      } else {
        developer.log(
          'Failed to fetch comments: ${response.statusCode}, response: $responseBody',
          name: 'SocialFeedPage',
        );
        return [];
      }
    } catch (e, stackTrace) {
      developer.log('Error fetching comments: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchReactions(String postId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for fetching reactions',
          name: 'SocialFeedPage');
      return [];
    }

    final uri =
    Uri.parse('https://www.unistudious.com/api/social-media-get-reaction');
    try {
      developer.log('Fetching reactions for post: $postId',
          name: 'SocialFeedPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      developer.log(
          'Reaction API response: $responseBody, status: ${response.statusCode}',
          name: 'SocialFeedPage');
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 &&
          responseData['status'] == 'success' &&
          responseData['reactions'] != null) {
        final List<dynamic> reactions = responseData['reactions'] ?? [];
        developer.log('Number of reactions received: ${reactions.length}',
            name: 'SocialFeedPage');
        return reactions.map((reaction) {
          final user = reaction['user'];
          String username = 'Unknown User';
          String userId = '';
          if (user != null) {
            developer.log('User data: $user', name: 'SocialFeedPage');
            username = (user['display_name']?.toString().trim().isNotEmpty ??
                false)
                ? user['display_name']
                : user['username']?.toString() ?? 'Unknown User';
            userId = user['id']?.toString() ?? '';
          } else {
            developer.log('Warning: reaction.user is null',
                name: 'SocialFeedPage');
          }
          return {
            'emoji': reaction['emoji']?.toString() ?? '',
            'user': {
              'id': userId,
              'username': username,
            },
          };
        }).toList();
      } else {
        developer.log(
          'Failed to fetch reactions: ${response.statusCode}, response: $responseBody',
          name: 'SocialFeedPage',
        );
        return [];
      }
    } catch (e, stackTrace) {
      developer.log('Error fetching reactions: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  Future<void> _fetchSocialFeed({required int page}) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    String? fetchedTargetUserId;
    try {
      setState(() {
        if (page == 1) {
          isLoading = true;
          isConnectionError = false;
        } else {
          isLoadingMore = true;
        }
      });

      developer.log('Fetching social feed for page: $page',
          name: 'SocialFeedPage');
      final response = await http.get(
        Uri.parse(
            'https://www.unistudious.com/api/dashboard-social-media?page=$page'),
        headers: {
          'Authorization': 'Bearer ${authProvider.currentToken}',
          'Content-Type': 'application/json',
        },
      );

      developer.log(
          'Social feed API response: ${response.body}, status: ${response.statusCode}',
          name: 'SocialFeedPage');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> statuses = data['statuses'] ?? [];
        final String resolvedFinalUsername =
            data['finalUsername']?.toString() ?? 'Unknown User';
        developer.log('Number of statuses received: ${statuses.length}',
            name: 'SocialFeedPage');

        setState(() {
          _finalUsername = resolvedFinalUsername;
          developer.log('Set _finalUsername: $_finalUsername',
              name: 'SocialFeedPage');
        });

        if (resolvedFinalUsername != 'Unknown User') {
          fetchedTargetUserId =
              await _fetchUserIdByUsername(resolvedFinalUsername);
          developer.log(
              'Fetched targetUserId: $fetchedTargetUserId for username: $resolvedFinalUsername',
              name: 'SocialFeedPage');
        } else {
          developer.log('No valid _finalUsername to fetch targetUserId',
              name: 'SocialFeedPage');
        }

        final String currentUserIdForSession =
            fetchedTargetUserId ?? _currentUserId ?? 'current_user';

        final Map<String, String> userReactions = {};
        if (data['userReactions'] is Map) {
          final Map<String, dynamic> userReactionsMap =
              data['userReactions'] ?? {};
          userReactions.addAll(userReactionsMap
              .map((key, value) => MapEntry(key.toString(), value.toString())));
        } else if (data['userReactions'] is List) {
          final List<dynamic>? userReactionsList = data['userReactions'];
          if (userReactionsList != null) {
            for (var reaction in userReactionsList) {
              final postId = reaction['postId']?.toString();
              final emoji = reaction['emoji']?.toString();
              final userId = reaction['userId']?.toString();
              if (postId != null &&
                  emoji != null &&
                  userId == currentUserIdForSession) {
                userReactions[postId] = emoji;
              }
            }
          }
        }

        final mappedPosts = <Map<String, dynamic>>[];
        for (var status in statuses) {
          developer.log('Processing status: $status', name: 'SocialFeedPage');
          final statusData = status['status'];
          if (statusData == null) {
            developer.log('Skipping status due to null statusData',
                name: 'SocialFeedPage');
            continue;
          }

          final account = statusData['account'];
          String username = 'Unknown User';
          String profileUrl = '';
          String userId = '';

          if (account == null) {
            developer.log(
                'Error: status.account is null for status id: ${statusData['id']}',
                name: 'SocialFeedPage');
          } else {
            developer.log('Account data: $account', name: 'SocialFeedPage');
            username = (account['display_name']?.toString().trim().isNotEmpty ??
                false)
                ? account['display_name']
                : account['username']?.toString() ?? 'Unknown User';
            profileUrl = account['avatar']?.toString() ?? '';
            userId = account['id']?.toString() ?? '';
            if (userId.isEmpty && account['username'] != null) {
              userId = await _fetchUserIdByUsername(account['username']) ?? '';
            }
          }

          String text = _stripHtml(statusData['content'] ?? '');
          String imageUrl = '';
          if ((statusData['media_attachments']?.isNotEmpty ?? false) &&
              statusData['media_attachments'][0]['type'] == 'image') {
            imageUrl = statusData['media_attachments'][0]['url']?.toString() ?? '';
          }
          String timeAgo = _timeAgo(DateTime.parse(
              statusData['created_at'] ?? DateTime.now().toIso8601String()));
          int likes = statusData['favourites_count'] ?? 0;
          int commentCount = statusData['replies_count'] ?? 0;
          int shares = statusData['reblogs_count'] ?? 0;
          dynamic poll = statusData['poll'];
          bool favourited = statusData['favourited'] ?? false;
          bool pinned = statusData['pinned'] ?? false;

          final commentList = await _fetchComments(statusData['id'] ?? '');
          final reactionList = await _fetchReactions(statusData['id'] ?? '');

          final postReactions = <String, String>{};
          for (var reaction in reactionList) {
            final userId = reaction['user']['id'];
            final emoji = reaction['emoji'];
            postReactions[userId] = emoji;
          }
          final userReaction = status['userReaction'] ??
              userReactions[statusData['id']] ??
              null;

          if (userReaction != null && currentUserIdForSession.isNotEmpty) {
            postReactions[currentUserIdForSession] = userReaction;
          }

          mappedPosts.add({
            "id": statusData['id']?.toString() ?? '',
            "username": username,
            "userId": userId,
            "timeAgo": timeAgo,
            "text": text,
            "imageUrl": imageUrl,
            "likes": likes,
            "comments": commentList,
            "commentCount": commentList.length,
            "shares": shares,
            "profileUrl": profileUrl,
            "poll": poll,
            "favourited": favourited,
            "userReactions": postReactions,
            "reactions": reactionList,
            "apiReactions": status['reactions'] ?? {"total": 0, "byEmoji": {}},
            "userReaction": userReaction,
            "pinned": pinned,
          });
        }

        setState(() {
          if (page == 1) {
            posts = List<Map<String, dynamic>>.from(mappedPosts);
          } else {
            posts.addAll(mappedPosts);
          }
          final pagination = data['pagination'] ?? {};
          currentPage = pagination['currentPage'] ?? page;
          totalPages = pagination['totalPages'] ?? 1;
          isLoading = false;
          isLoadingMore = false;
          isConnectionError = false;
          _currentUserId = currentUserIdForSession;
          this.targetUserId =
              fetchedTargetUserId ?? this.targetUserId ?? currentUserIdForSession;
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load feed: ${response.statusCode}';
          isLoading = false;
          isLoadingMore = false;
          isConnectionError = false;
        });
        developer.log(
          'Failed to fetch social feed: ${response.statusCode}, response: ${response.body}',
          name: 'SocialFeedPage',
        );
      }
    } catch (e, stackTrace) {
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
          errorMessage = null;
        } else {
          isConnectionError = false;
          errorMessage = 'Error fetching feed: $e';
        }
        isLoading = false;
        isLoadingMore = false;
      });
      developer.log('Error fetching social feed: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _fetchMorePosts() async {
    if (currentPage < totalPages) {
      developer.log('Fetching more posts for page: ${currentPage + 1}',
          name: 'SocialFeedPage');
      await _fetchSocialFeed(page: currentPage + 1);
    }
  }

  // Fonction pour décoder les entités HTML lors de la réception
  String _unescapeHtml(String text) {
    return text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');  // Doit être en dernier pour éviter la double décodage
  }

  // Fonction pour échapper les caractères HTML afin qu'ils soient préservés lors de l'envoi
  String _escapeHtmlForPosting(String text) {
    return text
        .replaceAll('&', '&amp;')  // Doit être en premier pour éviter la double échappement
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  String _stripHtml(String html) {
    // D'abord, supprimer les balises HTML
    String stripped = html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    // Ensuite, décoder les entités HTML pour afficher correctement les caractères < et >
    return _unescapeHtml(stripped);
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays}j';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'maintenant';
  }

  Future<void> _postStatus(
      BuildContext context,
      String status,
      bool enablePoll,
      List<String> pollOptions,
      String? pollDuration, {
        XFile? image,
        String? statusId,
        bool removeImage = false,
      }) async {
    // Le texte est envoyé tel quel, sans modification, pour préserver tous les caractères spéciaux
    if (status.isEmpty && image == null && (!enablePoll || pollOptions.isEmpty)) {
      developer.log(
          'Post status failed: status, image, and poll are empty',
          name: 'SocialFeedPage');
      SnackBarHelper.showWarning(context, 'Veuillez saisir un statut, ajouter une image ou activer un sondage.');
      return;
    }

    if (enablePoll && (pollDuration == null || pollDuration.isEmpty)) {
      developer.log('Post status failed: poll duration is missing',
          name: 'SocialFeedPage');
      SnackBarHelper.showWarning(context, 'Veuillez choisir une durée pour le sondage.');
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available', name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    setState(() {
      isPosting = true;
    });

    final baseUrl = statusId != null
        ? 'https://www.unistudious.com/api/social-media-status-update'
        : 'https://www.unistudious.com/api/social-media-status-create';
    final uri = statusId != null ? Uri.parse('$baseUrl/$statusId') : Uri.parse(baseUrl);

    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..headers['Content-Type'] = 'multipart/form-data; charset=utf-8'
        ..fields['status'] = _escapeHtmlForPosting(status)
        ..fields['enable_poll'] = enablePoll.toString()
        ..fields['remove_media'] = removeImage.toString();

      if (enablePoll) {
        request.fields.addAll({
          'option1': pollOptions.length > 0 ? _escapeHtmlForPosting(pollOptions[0]) : '',
          'option2': pollOptions.length > 1 ? _escapeHtmlForPosting(pollOptions[1]) : '',
          'option3': pollOptions.length > 2 ? _escapeHtmlForPosting(pollOptions[2]) : '',
          'option4': pollOptions.length > 3 ? _escapeHtmlForPosting(pollOptions[3]) : '',
          'poll_duration': pollDuration ?? '',
        });
      } else {
        request.fields.addAll({
          'option1': '',
          'option2': '',
          'option3': '',
          'option4': '',
          'poll_duration': '',
        });
      }

      if (image != null && !removeImage) {
        request.files.add(await http.MultipartFile.fromPath('media', image.path));
      }

      developer.log(
        'Sending POST request to $uri with fields: ${request.fields}, '
            'image: ${image?.path}, removeImage: $removeImage',
        name: 'SocialFeedPage',
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log(
          'Status ${statusId != null ? 'updated' : 'posted'} successfully: ${responseData['message']}',
          name: 'SocialFeedPage',
        );
        await _handlePostSuccess(context, responseData, statusId);
      } else {
        developer.log(
          'Failed to ${statusId != null ? 'update' : 'post'} status: ${response.statusCode}, response: $responseBody',
          name: 'SocialFeedPage',
        );
        SnackBarHelper.showError(context, 'Échec de la ${statusId != null ? 'mise à jour' : 'publication'} : ${responseData['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e, stackTrace) {
      developer.log(
        'Error ${statusId != null ? 'updating' : 'posting'} status: $e',
        name: 'SocialFeedPage',
        error: e,
        stackTrace: stackTrace,
      );
      SnackBarHelper.showError(context, 'Erreur lors de la ${statusId != null ? 'mise à jour' : 'publication'} : $e');
    } finally {
      setState(() {
        isPosting = false;
      });
    }
  }

  Future<void> _deleteStatus(String statusId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for deletion',
          name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final uri = Uri.parse(
        'https://www.unistudious.com/api/social-media-delete-status/$statusId');
    try {
      developer.log('Sending POST request to delete status: $uri',
          name: 'SocialFeedPage');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${authProvider.currentToken}',
          'Content-Type': 'application/json',
        },
      );

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Status deleted successfully: ${responseData['message']}',
            name: 'SocialFeedPage');
        setState(() {
          posts.removeWhere((post) => post['id'] == statusId);
        });
        SnackBarHelper.showSuccess(context, 'Statut supprimé avec succès !');
        await _fetchSocialFeed(page: 1);
      } else {
        developer.log(
          'Failed to delete status: ${response.statusCode}, response: ${response.body}',
          name: 'SocialFeedPage',
        );
        SnackBarHelper.showError(context, 'Échec de la suppression : ${responseData['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e, stackTrace) {
      developer.log('Error deleting status: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de la suppression : $e');
    }
  }

  Future<void> _deleteComment(String commentId, String postId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for deleting comment',
          name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final uri =
    Uri.parse('https://www.unistudious.com/api/social-media-delete-comment');
    try {
      developer.log(
          'Sending POST request to delete comment: $uri, commentId: $commentId',
          name: 'SocialFeedPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['commentId'] = commentId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Comment deleted successfully: ${responseData['message']}',
            name: 'SocialFeedPage');
        setState(() {
          final postIndex = posts.indexWhere((post) => post['id'] == postId);
          if (postIndex != -1) {
            posts[postIndex]['comments']
                .removeWhere((comment) => comment['id'] == commentId);
            posts[postIndex]['commentCount'] = posts[postIndex]['comments'].length;
          }
        });
        SnackBarHelper.showSuccess(context, 'Commentaire supprimé avec succès !');
      } else {
        developer.log(
          'Failed to delete comment: ${response.statusCode}, response: $responseBody',
          name: 'SocialFeedPage',
        );
        SnackBarHelper.showError(context, 'Échec de la suppression : ${responseData['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e, stackTrace) {
      developer.log('Error deleting comment: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de la suppression : $e');
    }
  }

  Future<void> _votePoll(String pollId, int optionIndex) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for voting',
          name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['poll']?['id'] == pollId);
    if (postIndex == -1) {
      developer.log('Poll not found: $pollId', name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Sondage introuvable.');
      return;
    }

    final poll = posts[postIndex]['poll'];
    final expiresAt = poll['expires_at'];
    if (expiresAt != null) {
      final expirationDate = DateTime.parse(expiresAt);
      final currentDate = DateTime.now();
      if (currentDate.isAfter(expirationDate)) {
        developer.log('Poll has expired: $pollId', name: 'SocialFeedPage');
        SnackBarHelper.showWarning(context, 'Le temps pour voter sur ce sondage est terminé.');
        return;
      }
    }

    if (poll['voted'] && !poll['multiple']) {
      developer.log(
          'User has already voted and multiple votes not allowed: $pollId',
          name: 'SocialFeedPage');
      SnackBarHelper.showWarning(context, 'Vous avez déjà voté.');
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-vote-poll');
    try {
      developer.log(
          'Sending POST request to vote on poll: $uri, pollId: $pollId, optionIndex: $optionIndex',
          name: 'SocialFeedPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['poll_id'] = pollId
        ..fields['option_index'] = optionIndex.toString();

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Poll vote submitted successfully: ${responseData['message']}',
            name: 'SocialFeedPage');
        setState(() {
          posts[postIndex]['poll'] = responseData['data'];
        });
        SnackBarHelper.showSuccess(context, 'Vote enregistré !');
      } else {
        developer.log(
          'Failed to vote on poll: ${response.statusCode}, response: $responseBody',
          name: 'SocialFeedPage',
        );
        SnackBarHelper.showError(context, 'Échec du vote : ${responseData['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e, stackTrace) {
      developer.log('Error voting on poll: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors du vote : $e');
    }
  }

  Future<void> _markAsFavorite(String postId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for marking favorite',
          name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['id'] == postId);
    if (postIndex == -1) {
      developer.log('Post not found: $postId', name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Post introuvable.');
      return;
    }

    final uri =
    Uri.parse('https://www.unistudious.com/api/social-media-mark-as-favorite');
    try {
      developer.log(
          'Sending POST request to mark post as favorite: $uri, postId: $postId',
          name: 'SocialFeedPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log(
            'Post marked as favorite successfully: ${responseData['message']}',
            name: 'SocialFeedPage');
        setState(() {
          posts[postIndex]['favourited'] = responseData['data']['favourited'];
          posts[postIndex]['likes'] = responseData['data']['favourites_count'];
        });
        SnackBarHelper.showSuccess(context, responseData['data']['favourited']
                ? 'Ajouté aux favoris !'
                : 'Retiré des favoris !');
      } else {
        developer.log(
          'Failed to mark post as favorite: ${response.statusCode}, response: $responseBody',
          name: 'SocialFeedPage',
        );
        SnackBarHelper.showError(context, 'Échec de l\'opération : ${responseData['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e, stackTrace) {
      developer.log('Error marking post as favorite: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de l\'opération : $e');
    }
  }

  Future<void> _markAsNotFavorite(String postId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for marking not favorite',
          name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['id'] == postId);
    if (postIndex == -1) {
      developer.log('Post not found: $postId', name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Post introuvable.');
      return;
    }

    final uri = Uri.parse(
        'https://www.unistudious.com/api/social-media-mark-as-not-favorite');
    try {
      developer.log(
          'Sending POST request to mark post as not favorite: $uri, postId: $postId',
          name: 'SocialFeedPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log(
            'Post marked as not favorite successfully: ${responseData['message']}',
            name: 'SocialFeedPage');
        setState(() {
          posts[postIndex]['favourited'] = responseData['data']['favourited'];
          posts[postIndex]['likes'] = responseData['data']['favourites_count'];
        });
        SnackBarHelper.showSuccess(context, 'Retiré des favoris !');
      } else {
        developer.log(
          'Failed to mark post as not favorite: ${response.statusCode}, response: $responseBody',
          name: 'SocialFeedPage',
        );
        SnackBarHelper.showError(context, 'Échec de l\'opération : ${responseData['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e, stackTrace) {
      developer.log('Error marking post as not favorite: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de l\'opération : $e');
    }
  }

  Future<void> _pinPost(String postId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for pinning post',
          name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-pin');
    try {
      developer.log('Sending POST request to pin post: $uri, postId: $postId',
          name: 'SocialFeedPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Post pinned successfully: ${responseData['message']}',
            name: 'SocialFeedPage');
        setState(() {
          final postIndex = posts.indexWhere((post) => post['id'] == postId);
          if (postIndex != -1) {
            posts[postIndex]['pinned'] = responseData['data']['pinned'] ?? true;
          }
        });
        SnackBarHelper.showSuccess(context, 'Statut épinglé avec succès !');
      } else {
        developer.log(
          'Failed to pin post: ${response.statusCode}, response: $responseBody',
          name: 'SocialFeedPage',
        );
        SnackBarHelper.showError(context, 'Échec de l\'épinglage : ${responseData['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e, stackTrace) {
      developer.log('Error pinning post: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de l\'épinglage : $e');
    }
  }

  Future<void> _unpinPost(String postId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for unpinning post',
          name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-not-pin');
    try {
      developer.log('Sending POST request to unpin post: $uri, postId: $postId',
          name: 'SocialFeedPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Post unpinned successfully: ${responseData['message']}',
            name: 'SocialFeedPage');
        setState(() {
          final postIndex = posts.indexWhere((post) => post['id'] == postId);
          if (postIndex != -1) {
            posts[postIndex]['pinned'] = responseData['data']['pinned'] ?? false;
          }
        });
        SnackBarHelper.showSuccess(context, 'Statut désépinglé avec succès !');
      } else {
        developer.log(
          'Failed to unpin post: ${response.statusCode}, response: $responseBody',
          name: 'SocialFeedPage',
        );
        SnackBarHelper.showError(context, 'Échec du désépinglage : ${responseData['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e, stackTrace) {
      developer.log('Error unpinning post: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors du désépinglage : $e');
    }
  }

  Future<void> _handlePostSuccess(
      BuildContext context, Map<String, dynamic> responseData, String? statusId) async {
    final statusData = responseData['data'];
    developer.log('Processing post success: $statusData', name: 'SocialFeedPage');
    final account = statusData['account'];
    String username = 'Unknown User';
    String userId = '';
    if (account != null) {
      developer.log('Account data: $account', name: 'SocialFeedPage');
      username = (account['display_name']?.toString().trim().isNotEmpty ?? false)
          ? account['display_name']
          : account['username']?.toString() ?? 'Unknown User';
      userId = account['id']?.toString() ?? '';
      if (userId.isEmpty && account['username'] != null) {
        userId = await _fetchUserIdByUsername(account['username']) ?? '';
      }
    } else {
      developer.log('Warning: statusData.account is null', name: 'SocialFeedPage');
    }

    String profileUrl = account?['avatar']?.toString() ?? '';
    String text = _stripHtml(statusData['content'] ?? '');
    String imageUrl = (statusData['media_attachments']?.isNotEmpty ?? false)
        ? statusData['media_attachments'][0]['url']?.toString() ?? ''
        : '';
    String timeAgo = _timeAgo(
        DateTime.parse(statusData['created_at'] ?? DateTime.now().toIso8601String()));
    dynamic poll = statusData['poll'];
    bool favourited = statusData['favourited'] ?? false;
    bool pinned = statusData['pinned'] ?? false;

    setState(() {
      if (statusId != null) {
        final postIndex = posts.indexWhere((post) => post['id'] == statusId);
        if (postIndex != -1) {
          posts[postIndex] = {
            "id": statusData['id']?.toString() ?? '',
            "username": username,
            "userId": userId,
            "timeAgo": timeAgo,
            "text": text,
            "imageUrl": imageUrl,
            "likes": statusData['favourites_count'] ?? 0,
            "comments": posts[postIndex]['comments'],
            "commentCount": statusData['replies_count'] ?? 0,
            "shares": statusData['reblogs_count'] ?? 0,
            "profileUrl": profileUrl,
            "poll": poll,
            "favourited": favourited,
            "userReactions": posts[postIndex]['userReactions'],
            "reactions": posts[postIndex]['reactions'],
            "apiReactions": posts[postIndex]['apiReactions'],
            "pinned": pinned,
          };
        }
      } else {
        final newPost = {
          "id": statusData['id']?.toString() ?? '',
          "username": username,
          "userId": userId,
          "timeAgo": timeAgo,
          "text": text,
          "imageUrl": imageUrl,
          "likes": statusData['favourites_count'] ?? 0,
          "comments": <Map<String, dynamic>>[],
          "commentCount": statusData['replies_count'] ?? 0,
          "shares": statusData['reblogs_count'] ?? 0,
          "profileUrl": profileUrl,
          "poll": poll,
          "favourited": favourited,
          "userReactions": <String, String>{},
          "reactions": <Map<String, dynamic>>[],
          "apiReactions": {"total": 0, "byEmoji": {}},
          "pinned": pinned,
        };
        posts.insert(0, newPost);
      }
      _statusController.clear();
      _selectedImage = null;
    });

    SnackBarHelper.showSuccess(context, statusId != null ? 'Statut mis à jour avec succès !' : 'Statut publié avec succès !');

    await _fetchSocialFeed(page: 1);
  }

  Future<Map<String, dynamic>?> _postComment(String postId, String commentText, {bool showSnackbar = true}) async {
    // Le texte du commentaire est envoyé tel quel, sans modification, pour préserver tous les caractères spéciaux
    if (commentText.isEmpty) {
      developer.log('Comment posting failed: comment is empty',
          name: 'SocialFeedPage');
      SnackBarHelper.showWarning(context, 'Le commentaire ne peut pas être vide.');
      return null;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for posting comment',
          name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return null;
    }

    final uri =
    Uri.parse('https://www.unistudious.com/api/social-media-set-comment');
    try {
      developer.log(
          'Sending POST request to post comment: $uri, postId: $postId',
          name: 'SocialFeedPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..headers['Content-Type'] = 'multipart/form-data; charset=utf-8'
        ..fields['id'] = postId
        ..fields['comment'] = _escapeHtmlForPosting(commentText);

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      developer.log('Comment API response: $responseBody, status: ${response.statusCode}',
          name: 'SocialFeedPage');

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Comment posted successfully: ${responseData['message']}',
            name: 'SocialFeedPage');
        final commentData = responseData['data'];
        final account = commentData['account'];
        String username = 'Unknown User';
        String userId = '';
        if (account != null) {
          developer.log('Account data: $account', name: 'SocialFeedPage');
          username = (account['display_name']?.toString().trim().isNotEmpty ??
              false)
              ? account['display_name']
              : account['username']?.toString() ?? 'Unknown User';
          userId = account['id']?.toString() ?? '';
          if (userId.isEmpty && account['username'] != null) {
            userId = await _fetchUserIdByUsername(account['username']) ?? '';
          }
        } else {
          developer.log('Warning: commentData.account is null',
              name: 'SocialFeedPage');
        }

        String profileUrl = account?['avatar']?.toString() ?? '';
        String text = _stripHtml(commentData['content'] ?? '');
        String timeAgo = _timeAgo(DateTime.parse(
            commentData['created_at'] ?? DateTime.now().toIso8601String()));

        setState(() {
          final postIndex = posts.indexWhere((post) => post['id'] == postId);
          if (postIndex != -1) {
            final newComment = {
              "id": commentData['id']?.toString() ?? '',
              "username": username,
              "userId": userId,
              "text": text,
              "timeAgo": timeAgo,
              "profileUrl": profileUrl,
            };
            posts[postIndex]['comments'].add(newComment);
            posts[postIndex]['commentCount'] = posts[postIndex]['comments'].length;
          }
        });

        if (showSnackbar) {
          SnackBarHelper.showSuccess(context, 'Commentaire publié avec succès !');
        }

        return {
          "id": commentData['id']?.toString() ?? '',
          "username": username,
          "userId": userId,
          "text": text,
          "timeAgo": timeAgo,
          "profileUrl": profileUrl,
        };
      } else {
        developer.log(
          'Failed to post comment: ${response.statusCode}, response: $responseBody',
          name: 'SocialFeedPage',
        );
        if (showSnackbar) {
          SnackBarHelper.showError(context, 'Échec de la publication du commentaire : ${responseData['message'] ?? 'Erreur inconnue'}');
        }
        return null;
      }
    } catch (e, stackTrace) {
      developer.log('Error posting comment: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      if (showSnackbar) {
        SnackBarHelper.showError(context, 'Erreur lors de la publication du commentaire : $e');
      }
      return null;
    }
  }

  Future<void> _handleReaction(String postId, String? reaction, String userId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for setting reaction',
          name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['id'] == postId);
    if (postIndex == -1) {
      developer.log('Post not found: $postId', name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Post introuvable.');
      return;
    }

    final effectiveUserId = (userId.isNotEmpty && userId != 'current_user')
        ? userId
        : await _ensureCurrentUserId() ?? '';
    if (effectiveUserId.isEmpty) {
      developer.log('Unable to resolve current user id for reactions',
          name: 'SocialFeedPage');
      SnackBarHelper.showError(context, 'Impossible d\'identifier votre compte pour réagir. Veuillez réessayer.');
      return;
    }

    Map<String, int> currentByEmoji = {};
    final apiReactions = posts[postIndex]['apiReactions'];
    if (apiReactions is Map && apiReactions['byEmoji'] is Map) {
      Map<String, dynamic>.from(apiReactions['byEmoji']).forEach((key, value) {
        final parsedValue =
            value is int ? value : int.tryParse(value.toString()) ?? 0;
        if (parsedValue > 0) {
          currentByEmoji[key] = parsedValue;
        }
      });
    } else {
      posts[postIndex]['apiReactions'] = {
        'total': 0,
        'byEmoji': <String, int>{},
      };
    }

    try {
      if (reaction == null) {
        final uri = Uri.parse(
            'https://www.unistudious.com/api/social-media-delete-reaction/$postId');
        final response = await http.delete(
          uri,
          headers: {
            'Authorization': 'Bearer ${authProvider.currentToken}',
            'Content-Type': 'application/json',
          },
        );

        Map<String, dynamic> responseData = {};
        if (response.body.isNotEmpty) {
          try {
            responseData = jsonDecode(response.body);
          } catch (e) {
            developer.log('Unable to parse delete reaction response: $e',
                name: 'SocialFeedPage');
          }
        }

        if (response.statusCode == 200) {
          setState(() {
            Map<String, String> userReactions = Map<String, String>.from(
              posts[postIndex]['userReactions'] as Map? ?? {},
            );
            List<Map<String, dynamic>> reactions = List<Map<String, dynamic>>.from(
              posts[postIndex]['reactions'] as List? ?? [],
            );

            final previousReaction = userReactions[effectiveUserId];
            userReactions.remove(effectiveUserId);
            reactions.removeWhere((r) => r['user']['id'] == effectiveUserId);
            final currentLikes =
                (posts[postIndex]['likes'] as int?) ?? 0;
            posts[postIndex]['likes'] =
                currentLikes > 0 ? currentLikes - 1 : 0;

            if (previousReaction != null &&
                currentByEmoji.containsKey(previousReaction)) {
              int count = currentByEmoji[previousReaction]! - 1;
              if (count <= 0) {
                currentByEmoji.remove(previousReaction);
              } else {
                currentByEmoji[previousReaction] = count;
              }
            }
            posts[postIndex]['apiReactions']['byEmoji'] = currentByEmoji;
            posts[postIndex]['apiReactions']['total'] =
                currentByEmoji.values.fold(0, (a, b) => a + b);
            posts[postIndex]['userReactions'] = userReactions;
            posts[postIndex]['reactions'] = reactions;
            posts[postIndex]['userReaction'] = null; // Update userReaction
            developer.log(
              'Reaction removed for post $postId, updated reaction list: ${posts[postIndex]['reactions']}',
              name: 'SocialFeedPage',
            );
          });
        } else {
          final errorMessage = responseData['message']?.toString().isNotEmpty == true
              ? responseData['message'].toString()
              : 'Erreur inconnue';
          SnackBarHelper.showError(context, 'Échec de la suppression de la réaction : $errorMessage');
        }
      } else {
        final uri =
        Uri.parse('https://www.unistudious.com/api/social-media-set-reaction');
        var request = http.MultipartRequest('POST', uri)
          ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
          ..fields['id'] = postId
          ..fields['emoji'] = reaction;

        final response = await request.send();
        final responseBody = await response.stream.bytesToString();
        Map<String, dynamic> responseData = {};
        if (responseBody.isNotEmpty) {
          try {
            responseData = jsonDecode(responseBody);
          } catch (e) {
            developer.log('Unable to parse set reaction response: $e',
                name: 'SocialFeedPage');
          }
        }

        if (response.statusCode == 200) {
          setState(() {
            Map<String, String> userReactions = Map<String, String>.from(
              posts[postIndex]['userReactions'] as Map? ?? {},
            );
            List<Map<String, dynamic>> reactions = List<Map<String, dynamic>>.from(
              posts[postIndex]['reactions'] as List? ?? [],
            );

            if (userReactions.containsKey(effectiveUserId)) {
              final previousReaction = userReactions[effectiveUserId];
              userReactions[effectiveUserId] = reaction!;

              final reactionIndex =
              reactions.indexWhere((r) => r['user']['id'] == effectiveUserId);
              if (reactionIndex != -1) {
                reactions[reactionIndex]['emoji'] = reaction;
              }

              if (previousReaction != null &&
                  currentByEmoji.containsKey(previousReaction)) {
                int count = currentByEmoji[previousReaction]! - 1;
                if (count <= 0) {
                  currentByEmoji.remove(previousReaction);
                } else {
                  currentByEmoji[previousReaction] = count;
                }
              }

              currentByEmoji[reaction!] =
                  (currentByEmoji[reaction!] ?? 0) + 1;
            } else {
              userReactions[effectiveUserId] = reaction!;
              reactions.add({
                'emoji': reaction,
                'user': {
                  'id': effectiveUserId,
                  'username': _finalUsername ?? 'Vous'
                }
              });
              final currentLikes =
                  (posts[postIndex]['likes'] as int?) ?? 0;
              posts[postIndex]['likes'] = currentLikes + 1;
              currentByEmoji[reaction!] =
                  (currentByEmoji[reaction!] ?? 0) + 1;
            }

            posts[postIndex]['apiReactions']['byEmoji'] = currentByEmoji;
            posts[postIndex]['apiReactions']['total'] =
                currentByEmoji.values.fold(0, (a, b) => a + b);
            posts[postIndex]['userReactions'] = userReactions;
            posts[postIndex]['reactions'] = reactions;
            posts[postIndex]['userReaction'] = reaction; // Update userReaction
            developer.log(
              'Reaction added for post $postId, updated reaction list: ${posts[postIndex]['reactions']}',
              name: 'SocialFeedPage',
            );
          });
        } else {
          final errorMessage = responseData['message']?.toString().isNotEmpty ==
              true
              ? responseData['message'].toString()
              : 'Erreur inconnue';
          SnackBarHelper.showError(context, 'Échec de la mise à jour de la réaction : $errorMessage');
        }
      }
    } catch (e, stackTrace) {
      developer.log('Error handling reaction: $e',
          name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de la mise à jour de la réaction : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    developer.log('Building SocialFeedPage, isLoading: $isLoading',
        name: 'SocialFeedPage');
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: GestureDetector(
        onTap: () {
          _focusNode.unfocus();
          developer.log('Tapped outside to unfocus', name: 'SocialFeedPage');
        },
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: _buildPostInput(context),
            ),
            Expanded(
              child: isLoading
                  ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
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
                              _fetchSocialFeed(page: 1);
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
                  : errorMessage != null
                  ? Center(
                child: Text(
                  errorMessage!,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.error,
                    fontFamily: GoogleFonts.poppins().fontFamily,
                  ) ??
                      TextStyle(
                        fontSize: 16,
                        color: theme.colorScheme.error,
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                ),
              )
                  : RefreshIndicator(
                onRefresh: () async {
                  await _fetchSocialFeed(page: 1);
                },
                color: theme.primaryColor,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(10),
                  itemCount: posts.length + (isLoadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == posts.length && isLoadingMore) {
                      return Center(
                          child:
                          CircularProgressIndicator(color: theme.primaryColor));
                    }
                    final post = posts[index];
                    return _buildPostCard(
                      finalUsername: _finalUsername ?? 'Unknown User',
                      id: post["id"],
                      username: post["username"],
                      userId: post["userId"],
                      timeAgo: post["timeAgo"],
                      text: post["text"],
                      imageUrl: post["imageUrl"],
                      likes: post["likes"],
                      comments: post["commentCount"],
                      shares: post["shares"],
                      profileUrl: post["profileUrl"],
                      poll: post["poll"],
                      commentList: post["comments"],
                      favourited: post["favourited"],
                      currentUserId:
                          _currentUserId ?? (targetUserId ?? 'current_user'),
                      currentReaction: post["userReaction"],
                      reactions: post["reactions"],
                      apiReactions: post["apiReactions"],
                      pinned: post["pinned"],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildPostInput(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    developer.log('Building post input', name: 'SocialFeedPage');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: theme.cardColor, // Use theme card color (white in light, dark in dark)
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.deepPurple,
                child: Text(
                  'D',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: GoogleFonts.poppins().fontFamily,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _statusController,
                            focusNode: _focusNode,
                            autofocus: false,
                            decoration: InputDecoration(
                              hintText: "À quoi penses‑tu?",
                              hintStyle: TextStyle(
                                color: theme.hintColor,
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 12.0,
                              ),
                              filled: true,
                              fillColor: isDark ? Colors.grey[800] : Colors.grey[200],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide(
                                  color: _statusLengthError != null ? theme.colorScheme.error : Colors.transparent,
                                  width: _statusLengthError != null ? 1 : 0,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide(
                                  color: _statusLengthError != null ? theme.colorScheme.error : Colors.transparent,
                                  width: _statusLengthError != null ? 1 : 0,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide(
                                  color: _statusLengthError != null ? theme.colorScheme.error : theme.primaryColor,
                                  width: 2,
                                ),
                              ),
                              prefixIcon: IconButton(
                                icon: Icon(Icons.camera_alt,
                                    color: theme.primaryColor, size: 26),
                                onPressed: () async {
                                  final picker = ImagePicker();
                                  final pickedFile = await picker.pickImage(
                                      source: ImageSource.gallery);
                                  if (pickedFile != null) {
                                    setState(() {
                                      _selectedImage = pickedFile;
                                    });
                                  }
                                },
                                tooltip: 'Ajouter une image',
                              ),
                              counter: const SizedBox.shrink(),
                            ),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                              fontSize: 14,
                            ) ?? TextStyle(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                              fontSize: 14,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                            minLines: 1,
                            maxLines: 5,
                            onChanged: (value) {
                              setState(() {
                                if (value.length > 500) {
                                  _statusLengthError = 'Le statut ne doit pas dépasser 500 caractères.';
                                } else {
                                  _statusLengthError = null;
                                }
                              });
                            },
                            onTap: () {
                              _focusNode.requestFocus();
                            },
                            onTapOutside: (event) {
                              _focusNode.unfocus();
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0, top: 2.0, right: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_statusLengthError != null)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: Text(
                                        _statusLengthError!,
                                        style: TextStyle(
                                          color: theme.colorScheme.error,
                                          fontSize: 11,
                                          fontFamily: GoogleFonts.poppins().fontFamily,
                                        ),
                                      ),
                                    ),
                                  ),
                                Text(
                                  "${_statusController.text.length}/500",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _statusController.text.length > 500
                                        ? theme.colorScheme.error
                                        : theme.hintColor,
                                    fontFamily: GoogleFonts.poppins().fontFamily,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    isPosting
                        ? Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                      ),
                    )
                        : IconButton(
                      icon: Icon(Icons.send_rounded,
                          color: theme.primaryColor, size: 28),
                      onPressed: () {
                        final statusText = _statusController.text.trim();
                        if (statusText.isEmpty) {
                          SnackBarHelper.showWarning(context, 'Veuillez saisir un statut.');
                        } else if (statusText.length > 500) {
                          setState(() {
                            _statusLengthError = 'Le statut ne doit pas dépasser 500 caractères.';
                          });
                          SnackBarHelper.showError(context, 'Le statut ne doit pas dépasser 500 caractères.');
                        } else {
                          setState(() {
                            _statusLengthError = null;
                          });
                          _postStatus(
                            context,
                            statusText,
                            false,
                            [],
                            null,
                            image: _selectedImage,
                          );
                        }
                      },
                      tooltip: 'Publier',
                    ),
                    IconButton(
                      icon: Icon(Icons.poll,
                          color: theme.primaryColor, size: 28),
                      onPressed: isPosting
                          ? null
                          : () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20)),
                          ),
                          builder: (_) => _PollCreationSheet(
                            onPostSuccess: () => _fetchSocialFeed(page: 1),
                            postStatus: _postStatus,
                            parentContext: context,
                          ),
                        );
                      },
                      tooltip: 'Créer un sondage',
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_selectedImage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 100),
                    child: Image.file(
                      File(_selectedImage!.path),
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.colorScheme.error),
                    onPressed: () {
                      setState(() {
                        _selectedImage = null;
                      });
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPostCard({
    required String finalUsername,
    required String id,
    required String username,
    required String userId,
    required String timeAgo,
    required String text,
    required String imageUrl,
    required int likes,
    required int comments,
    required int shares,
    required String profileUrl,
    dynamic poll,
    required List<Map<String, dynamic>> commentList,
    required bool favourited,
    required String currentUserId,
    required String? currentReaction,
    required List<Map<String, dynamic>> reactions,
    required Map<String, dynamic> apiReactions,
    required bool pinned,
  }) {
    final theme = Theme.of(context);
    developer.log('finalUsername: $finalUsername', name: 'SocialFeedPage');
    final isOwnPost = userId == currentUserId;

    // Fonction pour copier le lien du post
    void _copyLink() {
      final postLink = 'https://www.unistudious.com/public-social-media-details/$id';
      Clipboard.setData(ClipboardData(text: postLink)).then((_) {
        SnackBarHelper.showSuccess(context, 'Lien copié dans le presse-papiers !');
        developer.log('Link copied for post: $id', name: 'SocialFeedPage');
      });
    }

    // Fonction pour partager sur Facebook
    void _shareToFacebook() {
      final postLink = 'https://www.unistudious.com/public-social-media-details/$id';
      Share.share('Découvrez ce post : $postLink', subject: 'Partage de post');
      developer.log('Share to Facebook for post: $id', name: 'SocialFeedPage');
    }

    // Fonction pour partager via Gmail
    void _shareToGmail() {
      final postLink = 'https://www.unistudious.com/public-social-media-details/$id';
      final Uri emailUri = Uri(
        scheme: 'mailto',
        queryParameters: {
          'subject': 'Partage de post',
          'body': 'Découvrez ce post : $postLink',
        },
      );
      Share.shareUri(emailUri);
      developer.log('Share to Gmail for post: $id', name: 'SocialFeedPage');
    }

    // Fonction pour ouvrir un lien dans le navigateur
    Future<void> _launchUrl(String url) async {
      try {
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          developer.log('Opened URL: $url', name: 'SocialFeedPage');
        } else {
          developer.log('Could not launch URL: $url', name: 'SocialFeedPage');
          SnackBarHelper.showError(context, 'Impossible d\'ouvrir le lien.');
        }
      } catch (e) {
        developer.log('Error launching URL: $e', name: 'SocialFeedPage');
        SnackBarHelper.showError(context, 'Erreur lors de l\'ouverture du lien.');
      }
    }

    // Fonction pour créer un widget avec des liens cliquables
    Widget _buildTextWithLinks(String textContent) {
      final RegExp urlRegex = RegExp(
        r'(?:(?:https?|ftp):\/\/)?(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)',
        caseSensitive: false,
      );

      final List<TextSpan> spans = [];
      int lastMatchEnd = 0;

      for (final Match match in urlRegex.allMatches(textContent)) {
        // Ajouter le texte avant le lien
        if (match.start > lastMatchEnd) {
          spans.add(TextSpan(
            text: textContent.substring(lastMatchEnd, match.start),
            style: TextStyle(
              fontSize: 15,
              fontFamily: GoogleFonts.poppins().fontFamily,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ));
        }

        // Ajouter le lien cliquable
        String url = match.group(0)!;
        if (!url.startsWith('http://') && !url.startsWith('https://')) {
          url = 'https://$url';
        }

        spans.add(TextSpan(
          text: match.group(0),
          style: TextStyle(
            fontSize: 15,
            fontFamily: GoogleFonts.poppins().fontFamily,
            color: theme.primaryColor,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _launchUrl(url),
        ));

        lastMatchEnd = match.end;
      }

      // Ajouter le texte restant après le dernier lien
      if (lastMatchEnd < textContent.length) {
        spans.add(TextSpan(
          text: textContent.substring(lastMatchEnd),
          style: TextStyle(
            fontSize: 15,
            fontFamily: GoogleFonts.poppins().fontFamily,
            color: theme.textTheme.bodyLarge?.color,
          ),
        ));
      }

      return RichText(
        text: TextSpan(children: spans),
      );
    }

    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: NetworkImage(profileUrl),
              radius: 22,
            ),
            title: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      developer.log('Username tapped: $username, userId: $userId', name: 'SocialFeedPage');
                      final profileDetails = await _fetchProfileDetails(userId);
                      if (profileDetails != null) {
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
                      } else {
                        SnackBarHelper.showError(context, 'Impossible de charger les détails du profil.');
                      }
                    },
                    child: Text(
                      username,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ) ??
                          TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                            color: theme.textTheme.titleMedium?.color,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (pinned) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.push_pin, size: 16, color: Colors.orange),
                ],
              ],
            ),
            subtitle: Text(
              timeAgo,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: GoogleFonts.poppins().fontFamily,
              ) ??
                  TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                    fontFamily: GoogleFonts.poppins().fontFamily,
                  ),
            ),
            trailing: IconButton(
              icon: Icon(Icons.more_horiz, color: theme.iconTheme.color),
              onPressed: () {
                developer.log('More options tapped for post: $id', name: 'SocialFeedPage');
                developer.log(
                  'Checking post ownership: userId=$userId, targetUserId=$targetUserId, '
                      'username=$username, finalUsername=$finalUsername, currentUserId=$currentUserId',
                  name: 'SocialFeedPage._buildPostCard',
                );
                developer.log('Condition result: userId == targetUserId is ${userId == targetUserId}', name: 'SocialFeedPage._buildPostCard');
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (bottomSheetContext) => Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).cardColor : Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          leading: Icon(Icons.person, color: theme.primaryColor),
                          title: Text(
                            'Voir le profil',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                              fontSize: 16,
                            ) ??
                                TextStyle(
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                  fontSize: 16,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                          ),
                          onTap: () async {
                            Navigator.pop(bottomSheetContext);
                            developer.log('View Profile tapped for post: $id', name: 'SocialFeedPage');
                            final profileDetails = await _fetchProfileDetails(userId);
                            if (profileDetails != null) {
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
                            } else {
                              SnackBarHelper.showError(context, 'Impossible de charger les détails du profil.');
                            }
                          },
                        ),
                        if (!isOwnPost)
                          ListTile(
                            leading: Icon(Icons.flag, color: Colors.orange),
                            title: Text(
                              'Signaler le statut',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontFamily: GoogleFonts.poppins().fontFamily,
                                fontSize: 16,
                              ) ??
                                  TextStyle(
                                    fontFamily: GoogleFonts.poppins().fontFamily,
                                    fontSize: 16,
                                    color: theme.textTheme.bodyLarge?.color,
                                  ),
                            ),
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              _reportStatus(
                                context: context,
                                accountId: userId,
                                statusId: id,
                              );
                            },
                          ),
                        ListTile(
                          leading: Icon(
                            favourited ? Icons.favorite : Icons.favorite_border,
                            color: Colors.red,
                          ),
                          title: Text(
                            favourited ? 'Retirer des favoris' : 'Ajouter aux favoris',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                              fontSize: 16,
                            ) ??
                                TextStyle(
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                  fontSize: 16,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                          ),
                          onTap: () {
                            Navigator.pop(bottomSheetContext);
                            developer.log(
                              '${favourited ? 'Mark as Not Favorite' : 'Mark as Favorite'} tapped for post: $id',
                              name: 'SocialFeedPage',
                            );
                            if (favourited) {
                              _markAsNotFavorite(id);
                            } else {
                              _markAsFavorite(id);
                            }
                          },
                        ),
                        if (userId == targetUserId) ...[
                          ListTile(
                            leading: const Icon(Icons.push_pin, color: Colors.orange),
                            title: Text(
                              pinned ? 'Désépingler du profil' : 'Épingler au profil',
                              style: TextStyle(
                                fontFamily: GoogleFonts.poppins().fontFamily,
                                fontSize: 16,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              developer.log('${pinned ? 'Unpin' : 'Pin'} to Profile tapped for post: $id', name: 'SocialFeedPage');
                              if (pinned) {
                                _unpinPost(id);
                              } else {
                                _pinPost(id);
                              }
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.edit, color: Colors.blue),
                            title: Text(
                              'Modifier',
                              style: TextStyle(
                                fontFamily: GoogleFonts.poppins().fontFamily,
                                fontSize: 16,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              developer.log('Edit tapped for post: $id', name: 'SocialFeedPage');
                              final post = posts.firstWhere((p) => p['id'] == id);
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                ),
                                builder: (_) => _EditPostSheet(
                                  postId: id,
                                  initialStatus: post['text'],
                                  initialImageUrl: post['imageUrl'],
                                  initialPoll: post['poll'],
                                  postStatus: _postStatus,
                                  onPostSuccess: () => _fetchSocialFeed(page: 1),
                                ),
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.delete, color: Colors.red),
                            title: Text(
                              'Supprimer',
                              style: TextStyle(
                                fontFamily: GoogleFonts.poppins().fontFamily,
                                fontSize: 16,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              developer.log('Delete tapped for post: $id', name: 'SocialFeedPage');
                              showDialog(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: Text(
                                    'Confirmer la suppression',
                                    style: TextStyle(
                                      fontFamily: GoogleFonts.poppins().fontFamily,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  content: Text(
                                    'Voulez-vous vraiment supprimer ce statut ?',
                                    style: TextStyle(
                                      fontFamily: GoogleFonts.poppins().fontFamily,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialogContext),
                                      child: Text(
                                        'Annuler',
                                        style: TextStyle(
                                          fontFamily: GoogleFonts.poppins().fontFamily,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(dialogContext);
                                        _deleteStatus(id);
                                      },
                                      child: Text(
                                        'Supprimer',
                                        style: TextStyle(
                                          fontFamily: GoogleFonts.poppins().fontFamily,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: _buildTextWithLinks(text),
            ),
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity),
            ),
          if (poll != null) ...[
            const SizedBox(height: 12),
            _buildPollWidget(poll, id),
          ],
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () {
                    developer.log('Reactions tapped for post: $id', name: 'SocialFeedPage');
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (_) => ReactionSheet(apiReactions: apiReactions),
                    );
                  },
                  child: Row(
                    children: [
                      if (apiReactions["total"] > 0) ...[
                        ...() {
                          Map<String, int> emojiCount = Map<String, int>.from(apiReactions["byEmoji"]);
                          var sortedEmojis = emojiCount.entries.toList()
                            ..sort((a, b) => b.value.compareTo(a.value));
                          List<String> topEmojis = sortedEmojis.take(2).map((e) => e.key).toList();
                          int totalReactions = apiReactions["total"];

                          return [
                            ...topEmojis.map((emoji) => Row(
                              children: [
                                Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 18),
                                ),
                                const SizedBox(width: 4),
                              ],
                            )),
                            Text(
                              "$totalReactions",
                              style: TextStyle(
                                fontFamily: GoogleFonts.poppins().fontFamily,
                                color: Colors.grey[600],
                              ),
                            ),
                          ];
                        }(),
                      ] else ...[
                        const Icon(Icons.emoji_emotions_outlined, color: Colors.grey, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          "0",
                          style: TextStyle(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    developer.log('Comment count tapped for post: $id', name: 'SocialFeedPage');
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (_) => Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context).cardColor
                              : Colors.white,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        child: CommentSheet(
                          postId: id,
                          comments: commentList,
                          onCommentPosted: (postId, commentText) => _postComment(postId, commentText, showSnackbar: false),
                          fetchComments: _fetchComments,
                          onDeleteComment: _deleteComment,
                          currentUserId: targetUserId,
                          parentContext: context,
                        ),
                      ),
                    );
                  },
                  child: Text(
                    "$comments commentaires • $shares partages",
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontFamily: GoogleFonts.poppins().fontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ReactionButton(
                  postId: id,
                  currentUserId: currentUserId,
                  userReaction: currentReaction,
                  onReactionSelected: _handleReaction,
                ),
                _buildActionButton(Icons.comment_outlined, "Commenter", () {
                  developer.log('Comment button pressed for post: $id', name: 'SocialFeedPage');
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => CommentSheet(
                      postId: id,
                      comments: commentList,
                      onCommentPosted: (postId, commentText) => _postComment(postId, commentText, showSnackbar: false),
                      fetchComments: _fetchComments,
                      onDeleteComment: _deleteComment,
                      currentUserId: targetUserId,
                      parentContext: context,
                    ),
                  );
                }),
                PopupMenuButton<String>(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.share_outlined, color: Colors.grey[700]),
                      const SizedBox(width: 4),
                      Text(
                        'Partager',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontFamily: GoogleFonts.poppins().fontFamily,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  onSelected: (value) {
                    if (value == 'copy_link') {
                      _copyLink();
                    } else if (value == 'facebook') {
                      _shareToFacebook();
                    } else if (value == 'gmail') {
                      _shareToGmail();
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                    PopupMenuItem<String>(
                      value: 'facebook',
                      child: Row(
                        children: [
                          Icon(Icons.facebook, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          Text(
                            'Partager sur Facebook',
                            style: TextStyle(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'gmail',
                      child: Row(
                        children: [
                          Icon(Icons.email, color: Colors.red[700]),
                          const SizedBox(width: 8),
                          Text(
                            'Partager via Gmail',
                            style: TextStyle(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'copy_link',
                      child: Row(
                        children: [
                          Icon(Icons.link, color: Colors.grey[700]),
                          const SizedBox(width: 8),
                          Text(
                            'Copier le lien',
                            style: TextStyle(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPollWidget(dynamic poll, String postId) {
    bool hasVoted = poll['voted'] ?? false;
    List<dynamic> options = poll['options'] ?? [];
    int totalVotes = poll['votes_count'] ?? 0;
    developer.log(
      'Building poll widget, hasVoted: $hasVoted, options: ${options.length}, totalVotes: $totalVotes',
      name: 'SocialFeedPage',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: options.asMap().entries.map((entry) {
        int index = entry.key;
        var option = entry.value;
        String title = option['title'] ?? '';
        int votes = option['votes_count'] ?? 0;
        double percentage = totalVotes > 0 ? (votes / totalVotes * 100) : 0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
          child: GestureDetector(
            onTap: hasVoted && !poll['multiple']
                ? null
                : () {
              developer.log('Poll option tapped: $title, index: $index', name: 'SocialFeedPage');
              _votePoll(poll['id'], index);
            },
            child: Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: hasVoted && poll['own_votes'].contains(index)
                    ? Colors.deepPurple.withOpacity(0.2)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasVoted && poll['own_votes'].contains(index)
                      ? Colors.deepPurple
                      : Colors.grey[400]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[800],
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                    ),
                  ),
                  Text(
                    '${percentage.toStringAsFixed(1)}% ($votes)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontFamily: GoogleFonts.poppins().fontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? Colors.grey[700]),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color ?? Colors.grey[700],
              fontFamily: GoogleFonts.poppins().fontFamily,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionRow(String postId, Map<String, dynamic> apiReactions) {
    final postIndex = posts.indexWhere((post) => post['id'] == postId);
    if (postIndex == -1 || apiReactions['total'] == 0) {
      return const SizedBox.shrink();
    }
    final Map<String, int> reactionCounts = Map<String, int>.from(apiReactions['byEmoji'] ?? {});

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: GestureDetector(
        onTap: () {
          developer.log('Reactions tapped for post: $postId', name: 'SocialFeedPage');
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (context) => ReactionSheet(apiReactions: apiReactions),
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (apiReactions['total'] > 0)
              Text(
                '${apiReactions['total']}',
                style: TextStyle(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            const SizedBox(width: 4),
            ...((apiReactions['byEmoji'] as Map<String, dynamic>?)?.entries
                .take(3)
                .map((entry) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                entry.key,
                style: const TextStyle(fontSize: 16),
              ),
            ))
                .toList() ??
                []),
            if (((apiReactions['byEmoji'] as Map?)?.length ?? 0) > 3)
              Text(
                '+',
                style: TextStyle(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _connectionCheckTimer?.cancel();
    _statusController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}


class _PollCreationSheet extends StatefulWidget {
  final VoidCallback onPostSuccess;
  final Future<void> Function(
      BuildContext,
      String,
      bool,
      List<String>,
      String?, {
      XFile? image,
      String? statusId,
      bool removeImage,
      }) postStatus;
  final BuildContext? parentContext;

  const _PollCreationSheet({
    required this.onPostSuccess,
    required this.postStatus,
    this.parentContext,
  });

  @override
  _PollCreationSheetState createState() => _PollCreationSheetState();
}

class _PollCreationSheetState extends State<_PollCreationSheet> {
  final TextEditingController _pollStatusController = TextEditingController();
  List<TextEditingController> _controllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<String> _durations = [
    '5 Minutes',
    '30 Minutes',
    '1 Heure',
    '6 Heures',
    '1 Jour',
    '3 Jours',
    '7 Jours'
  ];
  String? _selectedDuration;
  String? _statusError;
  String? _optionsError;
  String? _durationError;

  @override
  void initState() {
    super.initState();
    developer.log('Initializing PollCreationSheet', name: 'PollCreationSheet');
  }

  void _addOption() {
    if (_controllers.length < 4) {
      setState(() {
        _controllers.add(TextEditingController());
        developer.log(
          'Added new poll option, total options: ${_controllers.length}',
          name: 'PollCreationSheet',
        );
      });
    }
  }

  void _removeOption(int index) {
    if (_controllers.length > 2) {
      setState(() {
        _controllers[index].dispose();
        _controllers.removeAt(index);
        developer.log(
          'Removed poll option at index $index, total options: ${_controllers.length}',
          name: 'PollCreationSheet',
        );
      });
    }
  }

  Future<void> _postPoll() async {
    List<String> options = _controllers.map((c) => c.text.trim()).where((text) => text.isNotEmpty).toList();
    String statusText = _pollStatusController.text.trim();
    developer.log(
      'Posting poll, status: $statusText, options: $options, selectedDuration: $_selectedDuration',
      name: 'PollCreationSheet',
    );
    
    // Réinitialiser les erreurs
    setState(() {
      _statusError = null;
      _optionsError = null;
      _durationError = null;
    });
    
    bool hasError = false;
    
    if (statusText.isEmpty) {
      developer.log('Poll posting failed: status is empty', name: 'PollCreationSheet');
      setState(() {
        _statusError = 'Veuillez saisir un statut.';
        hasError = true;
      });
    } else if (statusText.length > 500) {
      developer.log('Poll posting failed: status exceeds 500 characters', name: 'PollCreationSheet');
      setState(() {
        _statusError = 'Le statut ne doit pas dépasser 500 caractères.';
        hasError = true;
      });
    }
    if (options.length < 2) {
      developer.log('Poll posting failed: less than 2 options', name: 'PollCreationSheet');
      setState(() {
        _optionsError = 'Veuillez saisir au moins deux options.';
        hasError = true;
      });
    } else {
      // Vérifier que toutes les options sont différentes
      final uniqueOptions = options.toSet();
      if (uniqueOptions.length != options.length) {
        developer.log('Poll posting failed: duplicate options', name: 'PollCreationSheet');
        setState(() {
          _optionsError = 'Les options doivent être différentes les unes des autres.';
          hasError = true;
        });
      }
    }
    if (_selectedDuration == null) {
      developer.log('Poll posting failed: no duration selected', name: 'PollCreationSheet');
      setState(() {
        _durationError = 'Veuillez choisir une durée.';
        hasError = true;
      });
    }
    
    if (hasError) {
      return;
    }
    final durationMap = {
      '5 Minutes': '300',
      '30 Minutes': '1800',
      '1 Heure': '3600',
      '6 Heures': '21600',
      '1 Jour': '86400',
      '3 Jours': '259200',
      '7 Jours': '604800',
    };
    final pollDuration = durationMap[_selectedDuration];
    // Fermer la modal avant d'appeler postStatus pour que le snackbar soit visible
    Navigator.pop(context);
    // Utiliser le contexte parent (page principale) pour afficher le snackbar
    final postContext = widget.parentContext ?? context;
    _pollStatusController.clear();
    _controllers.forEach((controller) => controller.clear());
    setState(() {
      _selectedDuration = null;
    });
    await widget.postStatus(postContext, statusText, true, options, pollDuration, image: null);
    widget.onPostSuccess();
    developer.log('Poll posted successfully, sheet closed', name: 'PollCreationSheet');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    developer.log('Building PollCreationSheet', name: 'PollCreationSheet');
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).cardColor : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "🗳️ Créer un sondage",
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.primaryColor,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ) ?? TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.primaryColor,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              "Votre statut",
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.hintColor,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ) ?? TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.hintColor,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _pollStatusController,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: "Ex : Quelle est votre couleur préférée ?",
                    hintStyle: TextStyle(
                      color: theme.hintColor,
                      fontFamily: GoogleFonts.poppins().fontFamily,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark ? theme.cardColor : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: _statusError != null ? theme.colorScheme.error : Colors.transparent,
                        width: _statusError != null ? 1 : 0,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: _statusError != null ? theme.colorScheme.error : theme.primaryColor,
                        width: 2,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: theme.colorScheme.error,
                        width: 1,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: theme.colorScheme.error,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                  ),
                  style: TextStyle(
                    fontFamily: GoogleFonts.poppins().fontFamily,
                    fontSize: 14,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                  onChanged: (value) {
                    setState(() {
                      if (value.length > 500) {
                        _statusError = 'Le statut ne doit pas dépasser 500 caractères.';
                      } else if (_statusError != null && _statusError!.contains('500 caractères')) {
                        _statusError = null;
                      }
                    });
                    developer.log('Poll status changed: $value', name: 'PollCreationSheet');
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, top: 2.0, right: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_statusError != null)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Text(
                              _statusError!,
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontSize: 11,
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                            ),
                          ),
                        ),
                      Text(
                        "${_pollStatusController.text.length}/500",
                        style: TextStyle(
                          fontSize: 11,
                          color: _pollStatusController.text.length > 500
                              ? theme.colorScheme.error
                              : theme.hintColor,
                          fontFamily: GoogleFonts.poppins().fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              "Options de réponse",
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.hintColor,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ) ?? TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.hintColor,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
            ),
            const SizedBox(height: 10),
            ..._controllers.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          hintText: 'Option ${index + 1}',
                          hintStyle: TextStyle(
                            color: theme.hintColor,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                          filled: true,
                          fillColor: Theme.of(context).brightness == Brightness.dark ? theme.cardColor : Colors.white,                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: theme.primaryColor,
                              width: 2,
                            ),
                          ),
                        ),
                        style: TextStyle(
                          fontFamily: GoogleFonts.poppins().fontFamily,
                          fontSize: 14,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                        onChanged: (value) {
                          // Vérifier les doublons en temps réel
                          final currentOptions = _controllers
                              .map((c) => c.text.trim())
                              .where((text) => text.isNotEmpty)
                              .toList();
                          final uniqueOptions = currentOptions.toSet();
                          
                          setState(() {
                            // Si on a au moins 2 options et qu'il y a des doublons
                            if (currentOptions.length >= 2 && uniqueOptions.length != currentOptions.length) {
                              _optionsError = 'Les options doivent être différentes les unes des autres.';
                            } else if (currentOptions.length < 2) {
                              // Si moins de 2 options, on efface l'erreur de doublon mais on garde l'erreur de nombre si nécessaire
                              if (_optionsError != null && _optionsError!.contains('différentes')) {
                                _optionsError = null;
                              }
                            } else {
                              // Si toutes les options sont uniques, on efface l'erreur
                              if (_optionsError != null && _optionsError!.contains('différentes')) {
                                _optionsError = null;
                              }
                            }
                          });
                          
                          developer.log(
                            'Poll option $index changed: $value',
                            name: 'PollCreationSheet',
                          );
                        },
                      ),
                    ),
                    if (_controllers.length > 2)
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: theme.hintColor, // Use theme hint color
                        ),
                        onPressed: () => _removeOption(index),
                        tooltip: "Supprimer cette option",
                      ),
                  ],
                ),
              );
            }).toList(),
            if (_optionsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.error,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _optionsError!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                          fontFamily: GoogleFonts.poppins().fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_controllers.length < 4)
                  TextButton.icon(
                    onPressed: _addOption,
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: theme.primaryColor,
                    ),
                    label: Text(
                      "Ajouter une option",
                      style: TextStyle(
                        color: theme.primaryColor,
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: theme.cardColor, // Use theme card color
                      shape: const StadiumBorder(),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              "Durée du sondage",
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.hintColor,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ) ?? TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.hintColor,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: "Durée",
                labelStyle: TextStyle(
                  color: theme.hintColor,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark ? theme.cardColor : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: _durationError != null ? theme.colorScheme.error : Colors.transparent,
                    width: _durationError != null ? 1 : 0,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: _durationError != null ? theme.colorScheme.error : theme.primaryColor,
                    width: 2,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: theme.colorScheme.error,
                    width: 1,
                  ),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: theme.colorScheme.error,
                    width: 2,
                  ),
                ),
                errorText: _durationError,
                errorStyle: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 12,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
              ),
              value: _selectedDuration,
              onChanged: (value) {
                setState(() {
                  _selectedDuration = value;
                  if (_durationError != null) {
                    _durationError = null;
                  }
                });
                developer.log('Poll duration changed: $value', name: 'PollCreationSheet');
              },
              items: _durations.map((duration) {
                return DropdownMenuItem(
                  value: duration,
                  child: Text(
                    duration,
                    style: TextStyle(
                      fontFamily: GoogleFonts.poppins().fontFamily,
                      fontSize: 14,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _postPoll,
              icon: Icon(
                Icons.send_rounded,
                color: theme.colorScheme.onPrimary, // Use theme onPrimary color
              ),
              label: Text(
                "Publier le sondage",
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor, // Use theme primary color
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                minimumSize: const Size(double.infinity, 50),
                elevation: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pollStatusController.dispose();
    _controllers.forEach((controller) => controller.dispose());
    super.dispose();
    developer.log('PollCreationSheet disposed', name: 'PollCreationSheet');
  }
}

class _EditPostSheet extends StatefulWidget {
  final String postId;
  final String initialStatus;
  final String initialImageUrl;
  final dynamic initialPoll;
  final Future<void> Function(
      BuildContext,
      String,
      bool,
      List<String>,
      String?, {
      XFile? image,
      String? statusId,
      bool removeImage,
      }) postStatus;
  final VoidCallback onPostSuccess;

  const _EditPostSheet({
    required this.postId,
    required this.initialStatus,
    required this.initialImageUrl,
    required this.initialPoll,
    required this.postStatus,
    required this.onPostSuccess,
  });

  @override
  _EditPostSheetState createState() => _EditPostSheetState();
}

class _EditPostSheetState extends State<_EditPostSheet> {
  final TextEditingController _editStatusController = TextEditingController();
  XFile? _selectedImage;
  bool _enablePoll = false;
  List<TextEditingController> _pollControllers = [];
  String? _selectedDuration;
  String? _originalDuration;
  bool _removeImage = false;
  final List<String> _durations = [
    '5 Minutes',
    '30 Minutes',
    '1 Heure',
    '6 Heures',
    '1 Jour',
    '3 Jours',
    '7 Jours'
  ];

  @override
  void initState() {
    super.initState();
    _editStatusController.text = widget.initialStatus;
    _enablePoll = widget.initialPoll != null;
    if (_enablePoll && widget.initialPoll is Map && widget.initialPoll['options'] != null) {
      _pollControllers = (widget.initialPoll['options'] as List<dynamic>)
          .map((option) => TextEditingController(text: option['title'] as String? ?? ''))
          .toList();
      final durationMap = {
        '300': '5 Minutes',
        '1800': '30 Minutes',
        '3600': '1 Heure',
        '21600': '6 Heures',
        '86400': '1 Jour',
        '259200': '3 Jours',
        '604800': '7 Jours',
      };
      _selectedDuration = durationMap[widget.initialPoll['expires_in']?.toString()];
      _originalDuration = widget.initialPoll['expires_in']?.toString();
    } else {
      _pollControllers = [TextEditingController(), TextEditingController()];
    }
    developer.log(
      'Initializing EditPostSheet for post: ${widget.postId}, enablePoll: $_enablePoll, originalDuration: $_originalDuration',
      name: 'EditPostSheet',
    );
  }

  void _addPollOption() {
    if (_pollControllers.length < 4) {
      setState(() {
        _pollControllers.add(TextEditingController());
        developer.log(
          'Added new poll option, total options: ${_pollControllers.length}',
          name: 'EditPostSheet',
        );
      });
    }
  }

  void _removePollOption(int index) {
    if (_pollControllers.length > 2) {
      setState(() {
        _pollControllers[index].dispose();
        _pollControllers.removeAt(index);
        developer.log(
          'Removed poll option at index $index, total options: ${_pollControllers.length}',
          name: 'EditPostSheet',
        );
      });
    }
  }

  Future<void> _updatePost() async {
    String statusText = _editStatusController.text.trim();
    List<String> pollOptions = _pollControllers.map((c) => c.text.trim()).where((text) => text.isNotEmpty).toList();
    developer.log(
      'Updating post, postId: ${widget.postId}, status: $statusText, enablePoll: $_enablePoll, pollOptions: $pollOptions, selectedDuration: $_selectedDuration, originalDuration: $_originalDuration, image: ${_selectedImage?.path}, removeImage: $_removeImage',
      name: 'EditPostSheet',
    );

    if (statusText.isEmpty && _selectedImage == null && (!_enablePoll || pollOptions.isEmpty) && !widget.initialImageUrl.isNotEmpty) {
      developer.log('Post update failed: status, image, and poll are empty', name: 'EditPostSheet');
      SnackBarHelper.showWarning(context, 'Veuillez saisir un statut, ajouter une image ou activer un sondage.');
      return;
    }

    if (_enablePoll && pollOptions.length < 2) {
      developer.log('Post update failed: less than 2 poll options', name: 'EditPostSheet');
      SnackBarHelper.showWarning(context, 'Veuillez saisir au moins deux options pour le sondage.');
      return;
    }

    if (_enablePoll && _selectedDuration == null && _originalDuration == null) {
      developer.log('Post update failed: no poll duration selected', name: 'EditPostSheet');
      SnackBarHelper.showWarning(context, 'Veuillez choisir une durée pour le sondage.');
      return;
    }

    final durationMap = {
      '5 Minutes': '300',
      '30 Minutes': '1800',
      '1 Heure': '3600',
      '6 Heures': '21600',
      '1 Jour': '86400',
      '3 Jours': '259200',
      '7 Jours': '604800',
    };
    String? pollDuration;
    if (_enablePoll) {
      pollDuration = _selectedDuration != null ? durationMap[_selectedDuration] : _originalDuration;
    }

    if (_selectedImage == null && !_removeImage && widget.initialImageUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(widget.initialImageUrl));
        if (response.statusCode == 200) {
          final tempDir = await getTemporaryDirectory();
          final tempPath = '${tempDir.path}/temp_image.${widget.initialImageUrl.split('.').last}';
          await File(tempPath).writeAsBytes(response.bodyBytes);
          _selectedImage = XFile(tempPath);
          developer.log('Downloaded original image to preserve it', name: 'EditPostSheet');
        } else {
          developer.log('Failed to download original image: ${response.statusCode}', name: 'EditPostSheet');
          SnackBarHelper.showError(context, 'Erreur lors du téléchargement de l\'image originale.');
          return;
        }
      } catch (e, stackTrace) {
        developer.log('Error downloading original image: $e', name: 'EditPostSheet', error: e, stackTrace: stackTrace);
        SnackBarHelper.showError(context, 'Erreur lors du téléchargement de l\'image originale.');
        return;
      }
    }

    await widget.postStatus(
      context,
      statusText,
      _enablePoll,
      pollOptions,
      pollDuration,
      image: _selectedImage,
      statusId: widget.postId,
      removeImage: _removeImage,
    );
    _editStatusController.clear();
    _pollControllers.forEach((controller) => controller.clear());
    setState(() {
      _selectedImage = null;
      _enablePoll = false;
      _selectedDuration = null;
      _removeImage = false;
    });
    widget.onPostSuccess();
    Navigator.pop(context);
    developer.log('Post updated successfully, sheet closed', name: 'EditPostSheet');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    developer.log('Building EditPostSheet', name: 'EditPostSheet');
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).cardColor : Colors.white ,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Modifier le statut",
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.primaryColor,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ) ?? TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.primaryColor,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              "Votre statut",
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.hintColor,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ) ?? TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.hintColor,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _editStatusController,
              decoration: InputDecoration(
                hintText: "Modifier votre statut",
                hintStyle: TextStyle(
                  color: theme.hintColor,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark ? theme.cardColor : Colors.white,                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: theme.primaryColor,
                    width: 2,
                  ),
                ),
                prefixIcon: IconButton(
                  icon: Icon(
                    Icons.camera_alt,
                    color: theme.primaryColor,
                    size: 28,
                  ),
                  onPressed: () async {
                    final picker = ImagePicker();
                    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                    if (pickedFile != null) {
                      setState(() {
                        _selectedImage = pickedFile;
                        _removeImage = false;
                        developer.log(
                          'Image selected for edit: ${pickedFile.path}',
                          name: 'EditPostSheet',
                        );
                      });
                    }
                  },
                  tooltip: 'Ajouter ou remplacer une image',
                ),
              ),
              style: TextStyle(
                fontFamily: GoogleFonts.poppins().fontFamily,
                fontSize: 14,
                color: theme.textTheme.bodyLarge?.color,
              ),
              onChanged: (value) {
                developer.log('Edit status changed: $value', name: 'EditPostSheet');
              },
              maxLines: null,
            ),
            if (_selectedImage != null || (widget.initialImageUrl.isNotEmpty && !_removeImage))
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: _selectedImage != null
                          ? Image.file(
                        File(_selectedImage!.path),
                        width: double.infinity,
                        fit: BoxFit.contain,
                      )
                          : Image.network(
                        widget.initialImageUrl,
                        width: double.infinity,
                        fit: BoxFit.contain,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: theme.colorScheme.error, // Use theme error color
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedImage = null;
                          _removeImage = true;
                          developer.log('Image removed from edit', name: 'EditPostSheet');
                        });
                      },
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Activer le sondage",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: theme.hintColor,
                    fontFamily: GoogleFonts.poppins().fontFamily,
                  ) ?? TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: theme.hintColor,
                    fontFamily: GoogleFonts.poppins().fontFamily,
                  ),
                ),
                Switch(
                  value: _enablePoll,
                  onChanged: (value) {
                    setState(() {
                      _enablePoll = value;
                      developer.log('Poll toggle changed: $_enablePoll', name: 'EditPostSheet');
                    });
                  },
                  activeColor: theme.primaryColor, // Use theme primary color
                  activeTrackColor: theme.primaryColor.withOpacity(0.5),
                ),
              ],
            ),
            if (_enablePoll) ...[
              const SizedBox(height: 20),
              Text(
                "Options de réponse",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.hintColor,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ) ?? TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.hintColor,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
              ),
              const SizedBox(height: 10),
              ..._pollControllers.asMap().entries.map((entry) {
                final index = entry.key;
                final controller = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: 'Option ${index + 1}',
                            hintStyle: TextStyle(
                              color: theme.hintColor,
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ),
                            filled: true,
                            fillColor: Theme.of(context).brightness == Brightness.dark ? theme.cardColor : Colors.white,                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: theme.primaryColor,
                                width: 2,
                              ),
                            ),
                          ),
                          style: TextStyle(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                            fontSize: 14,
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                          onChanged: (value) {
                            developer.log('Poll option $index changed: $value', name: 'EditPostSheet');
                          },
                        ),
                      ),
                      if (_pollControllers.length > 2)
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: theme.hintColor, // Use theme hint color
                          ),
                          onPressed: () => _removePollOption(index),
                          tooltip: "Supprimer cette option",
                        ),
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_pollControllers.length < 4)
                    TextButton.icon(
                      onPressed: _addPollOption,
                      icon: Icon(
                        Icons.add_circle_outline,
                        color: theme.primaryColor,
                      ),
                      label: Text(
                        "Ajouter une option",
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontFamily: GoogleFonts.poppins().fontFamily,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: theme.cardColor, // Use theme card color
                        shape: const StadiumBorder(),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                "Durée du sondage",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.hintColor,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ) ?? TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: theme.hintColor,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: "Durée",
                  labelStyle: TextStyle(
                    color: theme.hintColor,
                    fontFamily: GoogleFonts.poppins().fontFamily,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).cardColor : Colors.white,                  border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: theme.primaryColor,
                      width: 2,
                    ),
                  ),
                ),
                value: _selectedDuration,
                onChanged: (value) {
                  setState(() => _selectedDuration = value);
                  developer.log('Poll duration changed: $value', name: 'EditPostSheet');
                },
                items: _durations.map((duration) {
                  return DropdownMenuItem(
                    value: duration,
                    child: Text(
                      duration,
                      style: TextStyle(
                        fontFamily: GoogleFonts.poppins().fontFamily,
                        fontSize: 14,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _updatePost,
              icon: Icon(
                Icons.send_rounded,
                color: theme.colorScheme.onPrimary, // Use theme onPrimary color
              ),
              label: Text(
                "Mettre à jour",
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor, // Use theme primary color
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                minimumSize: const Size(double.infinity, 50),
                elevation: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _editStatusController.dispose();
    _pollControllers.forEach((controller) => controller.dispose());
    super.dispose();
    developer.log('EditPostSheet disposed', name: 'EditPostSheet');
  }
}

class CommentSheet extends StatefulWidget {
  final String postId;
  final List<Map<String, dynamic>> comments;
  final Future<Map<String, dynamic>?> Function(String, String) onCommentPosted;
  final Future<List<Map<String, dynamic>>> Function(String) fetchComments;
  final void Function(String, String) onDeleteComment;
  final String? currentUserId;
  final BuildContext? parentContext;

  const CommentSheet({
    super.key,
    required this.postId,
    required this.comments,
    required this.onCommentPosted,
    required this.fetchComments,
    required this.onDeleteComment,
    this.currentUserId,
    this.parentContext,
  });

  @override
  _CommentSheetState createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final TextEditingController _commentController = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _isLoadingComments = false;
  final ScrollController _scrollController = ScrollController();
  String? _commentLengthError;
  final Map<String, GlobalKey> _commentKeys = {};

  String? _selectedCommentId; // <-- pour mettre en valeur le commentaire sélectionné

  @override
  void initState() {
    super.initState();
    _comments = List.from(widget.comments);
    for (var comment in _comments) {
      _commentKeys[comment['id']] = GlobalKey();
    }
    _fetchComments();
  }

  Future<void> _fetchComments() async {
    setState(() {
      _isLoadingComments = true;
    });
    try {
      final comments = await widget.fetchComments(widget.postId);
      setState(() {
        _comments = comments;
        _isLoadingComments = false;
        _commentKeys.removeWhere((id, key) => !comments.any((c) => c['id'] == id));
        for (var comment in comments) {
          _commentKeys.putIfAbsent(comment['id'], () => GlobalKey());
        }
      });
    } catch (e) {
      developer.log('Error fetching comments in CommentSheet: $e', name: 'CommentSheet');
      setState(() {
        _isLoadingComments = false;
      });
      SnackBarHelper.showError(context, 'Erreur lors du chargement des commentaires : $e');
    }
  }

  Future<void> _handleCommentPosted(String postId, String commentText) async {
    // Fermer la modal avant d'afficher le snackbar
    Navigator.pop(context);
    // Utiliser le contexte parent (page principale) pour afficher le snackbar
    final snackbarContext = widget.parentContext ?? context;
    final newComment = await widget.onCommentPosted(postId, commentText);
    if (newComment != null) {
      // Afficher le snackbar après avoir fermé la modal
      SnackBarHelper.showSuccess(snackbarContext, 'Commentaire publié avec succès !');
      setState(() {
        _comments.add(newComment);
        _commentKeys[newComment['id']] = GlobalKey();
      });
      await _fetchComments();
    } else {
      // Afficher le snackbar d'erreur si la publication a échoué
      SnackBarHelper.showError(snackbarContext, 'Échec de la publication du commentaire');
    }
  }

  void _handleDeleteComment(String commentId) {
    widget.onDeleteComment(commentId, widget.postId);
    setState(() {
      _comments.removeWhere((c) => c['id'] == commentId);
      _commentKeys.remove(commentId);
      _selectedCommentId = null;
    });
    _fetchComments();
  }

  void _showCommentMenu(BuildContext context, Offset tapPosition, String commentId) async {
    setState(() {
      _selectedCommentId = commentId; // mettre en valeur
    });

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        tapPosition.dx,
        tapPosition.dy,
        tapPosition.dx + 1,
        tapPosition.dy + 1,
      ),
      items: [
        const PopupMenuItem(
          value: "delete",
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red),
              SizedBox(width: 8),
              Text("Supprimer"),
            ],
          ),
        ),
      ],
    );

    if (selected == "delete") {
      _handleDeleteComment(commentId);
    } else {
      // Si l’utilisateur ferme le menu sans rien choisir -> enlever la sélection
      setState(() {
        _selectedCommentId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Offset _tapPosition = Offset.zero;

    return Padding(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Commentaires',
              style: TextStyle(
                color: Colors.deepPurple,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
            ),
            const SizedBox(height: 10),
            _isLoadingComments
                ? const Center(child: CircularProgressIndicator())
                : ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.builder(
                controller: _scrollController,
                shrinkWrap: true,
                itemCount: _comments.length,
                itemBuilder: (context, index) {
                  final comment = _comments[index];
                  final isOwnComment = comment['userId'] == widget.currentUserId;
                  print('Debug: comment[userId] = ${comment['userId']}, currentUserId = ${widget.currentUserId}, isOwnComment = $isOwnComment');

                  final isSelected = _selectedCommentId == comment['id'];

                  return GestureDetector(
                    key: _commentKeys[comment['id']],
                    onTapDown: (details) {
                      _tapPosition = details.globalPosition;
                    },
                    onLongPress: () {
                      developer.log('Long press detected on comment: ${comment['id']}, isOwnComment: $isOwnComment',
                          name: 'CommentSheet');
                      if (isOwnComment) {
                        _showCommentMenu(context, _tapPosition, comment['id']);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.deepPurple.withOpacity(0.1) : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: NetworkImage(comment['profileUrl']),
                        ),
                        title: Text(
                          comment['username'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                        ),
                        subtitle: Text(
                          comment['text'],
                          style: TextStyle(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                        ),
                        trailing: Text(
                          comment['timeAgo'],
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        minLines: 1,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: 'Écrire un commentaire...',
                          hintStyle: TextStyle(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: _commentLengthError != null ? Theme.of(context).colorScheme.error : Colors.transparent,
                              width: _commentLengthError != null ? 1 : 0,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: _commentLengthError != null ? Theme.of(context).colorScheme.error : Colors.transparent,
                              width: _commentLengthError != null ? 1 : 0,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: _commentLengthError != null ? Theme.of(context).colorScheme.error : Theme.of(context).primaryColor,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12.0,
                          ),
                        ),
                        style: TextStyle(
                          fontFamily: GoogleFonts.poppins().fontFamily,
                        ),
                        onChanged: (value) {
                          setState(() {
                            if (value.length > 500) {
                              _commentLengthError = 'Le commentaire ne doit pas dépasser 500 caractères.';
                            } else {
                              _commentLengthError = null;
                            }
                          });
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.deepPurple, size: 28),
                      onPressed: () {
                        final commentText = _commentController.text.trim();
                        if (commentText.isEmpty) {
                          SnackBarHelper.showWarning(context, 'Veuillez saisir un commentaire.');
                        } else if (commentText.length > 500) {
                          setState(() {
                            _commentLengthError = 'Le commentaire ne doit pas dépasser 500 caractères.';
                          });
                          SnackBarHelper.showError(context, 'Le commentaire ne doit pas dépasser 500 caractères.');
                        } else {
                          setState(() {
                            _commentLengthError = null;
                          });
                          _handleCommentPosted(widget.postId, commentText);
                          _commentController.clear();
                        }
                      },
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, top: 2.0, right: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_commentLengthError != null)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Text(
                              _commentLengthError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 11,
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                            ),
                          ),
                        ),
                      Text(
                        "${_commentController.text.length}/500",
                        style: TextStyle(
                          fontSize: 11,
                          color: _commentController.text.length > 500
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).hintColor,
                          fontFamily: GoogleFonts.poppins().fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

