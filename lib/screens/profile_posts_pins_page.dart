import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'dart:convert';
import 'dart:developer' as developer;
import '../providers/auth_provider.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/sidebar.dart';
import 'user_posts_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'social_feed_page.dart' as SocialFeed;

class ProfilePostsPinsPage extends StatefulWidget {
  final String? userId; // Optional: Pass userId to view specific user's profile
  final String? currentUserId; // Current logged-in user ID

  const ProfilePostsPinsPage({super.key, this.userId, this.currentUserId});

  @override
  _ProfilePostsPinsPageState createState() => _ProfilePostsPinsPageState();
}

class _ProfilePostsPinsPageState extends State<ProfilePostsPinsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool isLoading = true;
  bool isLoadingMore = false;
  String? errorMessage;
  String _currentUserId = '';
  List<Map<String, dynamic>> statuses = [];
  List<Map<String, dynamic>> pinnedStatuses = [];
  String? targetUserId;
  String? finalUsername;
  int currentPage = 1;
  int totalPages = 1;

  final ScrollController _scrollControllerStatuses = ScrollController();
  final ScrollController _scrollControllerPinned = ScrollController();

  final List<String> tabs = ['Mes publications', 'Mes épingles'];

  @override
  void initState() {
    super.initState();
    developer.log('ProfilePostsPinsPage: initState called, userId: ${widget.userId}, currentUserId: ${widget.currentUserId}',
        name: 'ProfilePostsPinsPage');
    _tabController = TabController(length: tabs.length, vsync: this);
    _checkAuthAndFetchData();
    _scrollControllerStatuses.addListener(() {
      if (_scrollControllerStatuses.position.pixels >=
          _scrollControllerStatuses.position.maxScrollExtent - 200 &&
          !isLoading &&
          !isLoadingMore &&
          currentPage < totalPages) {
        developer.log('ProfilePostsPinsPage: Scroll reached end, fetching more posts for page ${currentPage + 1}',
            name: 'ProfilePostsPinsPage');
        _fetchMorePosts();
      }
    });
  }

  @override
  void dispose() {
    developer.log('ProfilePostsPinsPage: dispose called', name: 'ProfilePostsPinsPage');
    _tabController.dispose();
    _scrollControllerStatuses.dispose();
    _scrollControllerPinned.dispose();
    super.dispose();
  }

  Future<bool> _checkAuth(BuildContext context, AuthProvider authProvider) async {
    developer.log('ProfilePostsPinsPage: Checking authentication', name: 'ProfilePostsPinsPage');
    if (!authProvider.isLoggedIn || authProvider.currentToken == null) {
      developer.log('ProfilePostsPinsPage: No valid token available, redirecting to login',
          name: 'ProfilePostsPinsPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return false;
    }
    developer.log('ProfilePostsPinsPage: Authentication valid', name: 'ProfilePostsPinsPage');
    return true;
  }

  Future<void> _checkAuthAndFetchData() async {
    developer.log('ProfilePostsPinsPage: _checkAuthAndFetchData started',
        name: 'ProfilePostsPinsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!await _checkAuth(context, authProvider)) return;

    setState(() {
      _currentUserId = widget.currentUserId ?? widget.userId ?? '';
      targetUserId = widget.userId ?? _currentUserId;
      developer.log('ProfilePostsPinsPage: Set _currentUserId: $_currentUserId, targetUserId: $targetUserId',
          name: 'ProfilePostsPinsPage');
    });
    await _fetchSocialMediaData(page: 1);
    if (finalUsername == null || finalUsername == 'Unknown User') {
      developer.log('ProfilePostsPinsPage: Failed to fetch valid username',
          name: 'ProfilePostsPinsPage');
      setState(() {
        errorMessage = 'Impossible de charger le profil de l\'utilisateur.';
      });
    }
  }

  Future<void> _fetchSocialMediaData({required int page}) async {
    developer.log('ProfilePostsPinsPage: _fetchSocialMediaData started for page $page, targetUserId: $targetUserId', name: 'ProfilePostsPinsPage');
    setState(() {
      if (page == 1) {
        isLoading = true;
      } else {
        isLoadingMore = true;
      }
      errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final url = 'https://www.unistudious.com/api/profile-social-media?page=$page${widget.userId != null ? "&userId=${widget.userId}" : ""}';
      developer.log('ProfilePostsPinsPage: Sending GET request to $url', name: 'ProfilePostsPinsPage');
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${authProvider.currentToken}',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      developer.log('ProfilePostsPinsPage: Social media response status: ${response.statusCode}, body length: ${response.body.length}', name: 'ProfilePostsPinsPage');

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        developer.log('ProfilePostsPinsPage: Raw JSON response: $jsonResponse', name: 'ProfilePostsPinsPage');
        final data = jsonResponse['data'];
        List<dynamic> statusesData;
        List<dynamic> pinnedData;
        String? username;

        if (data is Map<String, dynamic>) {
          statusesData = data['statuses'] ?? [];
          pinnedData = data['pinnedStatuses'] ?? [];
          username = data['finalUsername']?.toString();
        } else if (data is List<dynamic>) {
          statusesData = data.where((item) {
            if (item is Map<String, dynamic>) {
              return !(item['pinned'] ?? false);
            }
            return false;
          }).toList();
          pinnedData = data.where((item) {
            if (item is Map<String, dynamic>) {
              return item['pinned'] ?? false;
            }
            return false;
          }).toList();
          username = jsonResponse['finalUsername']?.toString();
        } else {
          statusesData = [];
          pinnedData = [];
          username = 'Unknown User';
        }

        setState(() {
          finalUsername = username ?? 'Unknown User';
          developer.log('ProfilePostsPinsPage: Set finalUsername: $finalUsername', name: 'ProfilePostsPinsPage');
        });

        final mappedStatuses = await _mapStatuses(statusesData);
        final mappedPinned = await _mapStatuses(pinnedData);

        setState(() {
          if (page == 1) {
            statuses = mappedStatuses;
            pinnedStatuses = mappedPinned;
          } else {
            statuses.addAll(mappedStatuses);
          }
          final pagination = jsonResponse['pagination'] ?? {};
          currentPage = pagination['currentPage'] ?? page;
          totalPages = pagination['totalPages'] ?? 1;
          isLoading = false;
          isLoadingMore = false;
          developer.log('ProfilePostsPinsPage: Updated state - statuses: ${statuses.length}, pinned: ${pinnedStatuses.length}, currentPage: $currentPage, totalPages: $totalPages, sample status reactions: ${mappedStatuses.isNotEmpty ? mappedStatuses[0]['reactions'] : "none"}', name: 'ProfilePostsPinsPage');
        });
      } else {
        String errorMessageLocal;
        switch (response.statusCode) {
          case 401:
          case 403:
            errorMessageLocal = 'Session expirée. Veuillez vous reconnecter.';
            developer.log('ProfilePostsPinsPage: Authentication error, redirecting to login',
                name: 'ProfilePostsPinsPage');
            Navigator.pushReplacementNamed(context, '/login');
            break;
          case 404:
            errorMessageLocal = 'Ressource non trouvée.';
            break;
          case 500:
            errorMessageLocal = 'Erreur interne du serveur. Veuillez réessayer plus tard.';
            break;
          default:
            errorMessageLocal = 'Erreur serveur (${response.statusCode})';
        }
        try {
          final jsonResponse = jsonDecode(response.body);
          errorMessageLocal = jsonResponse['message'] ?? errorMessageLocal;
        } catch (_) {}
        developer.log(
            'ProfilePostsPinsPage: Social media fetch failed with status: ${response.statusCode}, message: $errorMessageLocal',
            name: 'ProfilePostsPinsPage');
        setState(() {
          errorMessage =
          'Erreur lors de la récupération des publications : $errorMessageLocal';
        });
      }
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error in _fetchSocialMediaData: $e', name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      setState(() {
        errorMessage = 'Erreur lors de la récupération des publications : $e';
      });
    } finally {
      setState(() {
        isLoading = false;
        isLoadingMore = false;
      });
      developer.log('ProfilePostsPinsPage: _fetchSocialMediaData completed', name: 'ProfilePostsPinsPage');
    }
  }

  Future<List<Map<String, dynamic>>> _mapStatuses(List<dynamic> statusesData) async {
    developer.log('ProfilePostsPinsPage: Mapping ${statusesData.length} statuses', name: 'ProfilePostsPinsPage');
    final List<Map<String, dynamic>> mappedStatuses = [];

    for (var status in statusesData) {
      if (status is! Map<String, dynamic>) {
        developer.log('ProfilePostsPinsPage: Skipping invalid status type: ${status.runtimeType}, data: $status', name: 'ProfilePostsPinsPage');
        continue;
      }

      final statusData = status.containsKey('status')
          ? (status['status'] is Map<String, dynamic> ? status['status'] : null)
          : status;

      if (statusData == null || statusData is! Map<String, dynamic> || statusData.isEmpty || !statusData.containsKey('id') || statusData['id'] == null) {
        developer.log('ProfilePostsPinsPage: Skipping invalid status data: $statusData', name: 'ProfilePostsPinsPage');
        continue;
      }

      final account = statusData['account'] is Map<String, dynamic> ? statusData['account'] : {};
      String username = account['display_name']?.toString().trim().isNotEmpty ?? false
          ? account['display_name']
          : account['username']?.toString() ?? 'Unknown User';
      String profileUrl = account['avatar']?.toString() ?? '';
      String userId = account['id']?.toString() ?? '';
      if (userId.isEmpty && account['username'] != null) {
        userId = await _fetchUserIdByUsername(account['username']) ?? '';
        developer.log('ProfilePostsPinsPage: Fetched userId: $userId for username: ${account['username']}', name: 'ProfilePostsPinsPage');
      }

      final content = parse(statusData['content'] ?? '').body?.text.trim() ?? '';
      final createdAt = statusData['created_at'] != null
          ? DateTime.parse(statusData['created_at']).toLocal()
          : DateTime.now();
      final timeAgo = _timeAgo(createdAt);
      final dynamic rawAttachments = statusData['media_attachments'];
      List<Map<String, dynamic>> mediaAttachments = [];
      if (rawAttachments is List) {
        final invalidItems = rawAttachments.where((item) => item is! Map<String, dynamic>).toList();
        if (invalidItems.isNotEmpty) {
          developer.log('Invalid media attachments for status ${statusData['id']}: $invalidItems', name: 'ProfilePostsPinsPage');
        }
        mediaAttachments = rawAttachments.where((item) => item is Map<String, dynamic>).cast<Map<String, dynamic>>().toList();
      } else if (rawAttachments != null) {
        developer.log('Media attachments not a list for status ${statusData['id']}: ${rawAttachments.runtimeType}', name: 'ProfilePostsPinsPage');
      }
      String imageUrl = mediaAttachments.isNotEmpty && mediaAttachments[0]['type'] == 'image'
          ? mediaAttachments[0]['url']?.toString() ?? ''
          : '';
      final repliesCount = statusData['replies_count'] ?? 0;
      final reblogsCount = statusData['reblogs_count'] ?? 0;
      final favouritesCount = statusData['favourites_count'] ?? 0;
      final favourited = statusData['favourited'] ?? false;
      final pinned = statusData['pinned'] ?? false;
      final poll = statusData['poll'];

      final dynamic rawUserReaction = status['userReaction'];
      final String? userReaction = rawUserReaction is String ? rawUserReaction : null;
      if (rawUserReaction != null && rawUserReaction is! String) {
        developer.log('Invalid userReaction type for status ${statusData['id']}: ${rawUserReaction.runtimeType}', name: 'ProfilePostsPinsPage');
      }

      final dynamic rawApiReactions = status['reactions'];
      Map<String, dynamic> apiReactions = {'total': 0, 'byEmoji': {}};
      if (rawApiReactions is Map<String, dynamic>) {
        apiReactions = rawApiReactions;
      } else if (rawApiReactions != null) {
        developer.log('Invalid reactions type for status ${statusData['id']}: ${rawApiReactions.runtimeType}', name: 'ProfilePostsPinsPage');
      }

      final dynamic rawByEmoji = apiReactions['byEmoji'] ?? {};
      final Map<String, int> byEmoji = rawByEmoji is Map
          ? Map<String, int>.from(rawByEmoji.map((k, v) => MapEntry(k.toString(), v is int ? v : 0)))
          : {};
      final int totalReactions = apiReactions['total'] is int ? apiReactions['total'] : 0;

      developer.log('ProfilePostsPinsPage: Mapping reactions for status ${statusData['id']} - userReaction: $userReaction, total: $totalReactions, byEmoji: $byEmoji', name: 'ProfilePostsPinsPage');

      final commentList = await _fetchComments(statusData['id'] ?? '');
      if (commentList is! List) {
        developer.log('ProfilePostsPinsPage: Invalid commentList type for status ${statusData['id']}: ${commentList.runtimeType}', name: 'ProfilePostsPinsPage');
      }

      mappedStatuses.add({
        'id': statusData['id'] ?? '',
        'username': username,
        'userId': userId,
        'timeAgo': timeAgo,
        'text': content,
        'imageUrl': imageUrl,
        'likes': favouritesCount,
        'comments': commentList,
        'commentCount': commentList.length,
        'shares': reblogsCount,
        'profileUrl': profileUrl,
        'poll': poll,
        'favourited': favourited,
        'pinned': pinned,
        'userReaction': userReaction,
        'userReactions': {},
        'reactions': [],
        'apiReactions': {
          'total': totalReactions,
          'byEmoji': byEmoji,
        },
      });
      developer.log('ProfilePostsPinsPage: Mapped status id: ${statusData['id']}', name: 'ProfilePostsPinsPage');
    }

    developer.log('ProfilePostsPinsPage: Mapped ${mappedStatuses.length} statuses', name: 'ProfilePostsPinsPage');
    return mappedStatuses;
  }

  Future<String?> _fetchUserIdByUsername(String username) async {
    developer.log('ProfilePostsPinsPage: Fetching user ID for username: $username',
        name: 'ProfilePostsPinsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('ProfilePostsPinsPage: No valid token available for fetching user ID',
          name: 'ProfilePostsPinsPage');
      return null;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-get-userid-by-username');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['username'] = username;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);
      if (response.statusCode == 200 && responseData['id'] != null) {
        developer.log('ProfilePostsPinsPage: Successfully fetched user ID: ${responseData['id']}',
            name: 'ProfilePostsPinsPage');
        return responseData['id']?.toString();
      }
      developer.log('ProfilePostsPinsPage: Failed to fetch user ID, status: ${response.statusCode}',
          name: 'ProfilePostsPinsPage');
      return null;
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error fetching user ID: $e',
          name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchProfileDetails(String userId) async {
    developer.log('ProfilePostsPinsPage: Fetching profile details for userId: $userId',
        name: 'ProfilePostsPinsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('ProfilePostsPinsPage: No valid token available for fetching profile details',
          name: 'ProfilePostsPinsPage');
      return null;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/profile-details-social-media/$userId');
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
        developer.log('ProfilePostsPinsPage: Successfully fetched profile details for userId: $userId',
            name: 'ProfilePostsPinsPage');
        return responseData['data'];
      }
      developer.log('ProfilePostsPinsPage: Failed to fetch profile details, status: ${response.statusCode}',
          name: 'ProfilePostsPinsPage');
      return null;
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error fetching profile details: $e',
          name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
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
        'ProfilePostsPinsPage: Reporting status $statusId for account $accountId with forward=$forwardValue',
        name: 'ProfilePostsPinsPage',
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
      developer.log('ProfilePostsPinsPage: Error reporting status: $e', name: 'ProfilePostsPinsPage');
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors du signalement : $e');
      }
    } finally {
      commentController.dispose();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchComments(String postId) async {
    developer.log('ProfilePostsPinsPage: Fetching comments for postId: $postId',
        name: 'ProfilePostsPinsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      final uri = Uri.parse('https://www.unistudious.com/api/social-media-get-comment');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final dynamic commentsData = responseData['data'] ?? [];
        List<dynamic> comments;
        if (commentsData is List) {
          comments = commentsData;
        } else if (commentsData is Map) {
          developer.log('ProfilePostsPinsPage: Comments data is a Map, converting to List: $commentsData',
              name: 'ProfilePostsPinsPage');
          comments = [commentsData];
        } else {
          developer.log('ProfilePostsPinsPage: Invalid comments data type: ${commentsData.runtimeType}',
              name: 'ProfilePostsPinsPage');
          comments = [];
        }
        developer.log('ProfilePostsPinsPage: Fetched ${comments.length} comments for postId: $postId',
            name: 'ProfilePostsPinsPage');
        return comments.map((comment) {
          final account = comment['account'] ?? {};
          String username = account['display_name']?.toString().trim().isNotEmpty ?? false
              ? account['display_name']
              : account['username']?.toString() ?? 'Unknown User';
          String userId = account['id']?.toString() ?? '';
          String text = parse(comment['content'] ?? '').body?.text.trim() ?? '';
          String timeAgo =
          _timeAgo(DateTime.parse(comment['created_at'] ?? DateTime.now().toIso8601String()));
          String profileUrl = comment['account']?['avatar'] ?? '';

          return {
            "id": comment['id']?.toString() ?? '',
            "username": username,
            "userId": userId,
            "text": text,
            "timeAgo": timeAgo,
            "profileUrl": profileUrl,
          };
        }).toList();
      }
      developer.log('ProfilePostsPinsPage: Failed to fetch comments, status: ${response.statusCode}',
          name: 'ProfilePostsPinsPage');
      return [];
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error fetching comments: $e',
          name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchReactions(String postId) async {
    developer.log('ProfilePostsPinsPage: Fetching reactions for postId: $postId',
        name: 'ProfilePostsPinsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('ProfilePostsPinsPage: No token available for fetching reactions',
          name: 'ProfilePostsPinsPage');
      return [];
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-get-reaction');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      developer.log('ProfilePostsPinsPage: Reaction API response - status: ${response.statusCode}, body: $responseBody',
          name: 'ProfilePostsPinsPage');

      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final List<dynamic> reactions = responseData['reactions'] ?? [];
        developer.log('ProfilePostsPinsPage: Fetched ${reactions.length} reactions for postId: $postId',
            name: 'ProfilePostsPinsPage');
        return reactions.map((reaction) {
          final user = reaction['user'];
          String username = 'Unknown User';
          String userId = '';
          if (user != null) {
            username = user['display_name']?.toString().trim().isNotEmpty ?? false
                ? user['display_name']
                : user['username']?.toString() ?? 'Unknown User';
            userId = user['id']?.toString() ?? '';
          }
          return {
            'emoji': reaction['emoji'] ?? '',
            'user': {
              'id': userId,
              'username': username,
            },
          };
        }).toList();
      }
      developer.log('ProfilePostsPinsPage: Failed to fetch reactions, status: ${response.statusCode}, body: $responseBody',
          name: 'ProfilePostsPinsPage');
      return [];
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error fetching reactions: $e',
          name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  Future<void> _fetchMorePosts() async {
    if (currentPage < totalPages) {
      developer.log('ProfilePostsPinsPage: Fetching more posts for page: ${currentPage + 1}',
          name: 'ProfilePostsPinsPage');
      await _fetchSocialMediaData(page: currentPage + 1);
    } else {
      developer.log('ProfilePostsPinsPage: No more pages to fetch, currentPage: $currentPage, totalPages: $totalPages',
          name: 'ProfilePostsPinsPage');
    }
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays}j';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'maintenant';
  }

  Future<void> _handleReaction(String postId, String? reaction, String userId) async {
    developer.log('ProfilePostsPinsPage: Handling reaction for postId: $postId, reaction: $reaction, userId: $userId',
        name: 'ProfilePostsPinsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!await _checkAuth(context, authProvider)) return;

    final postIndex = statuses.indexWhere((post) => post['id'] == postId);
    final pinnedIndex = pinnedStatuses.indexWhere((post) => post['id'] == postId);
    final targetIndex = postIndex != -1 ? postIndex : pinnedIndex;
    final targetList = postIndex != -1 ? statuses : pinnedStatuses;

    if (targetIndex == -1) {
      developer.log('ProfilePostsPinsPage: Post not found for reaction, postId: $postId',
          name: 'ProfilePostsPinsPage');
      SnackBarHelper.showError(context, 'Post introuvable.');
      return;
    }

    Map<String, int> currentByEmoji = Map<String, int>.from(
      (targetList[targetIndex]['apiReactions']['byEmoji'] is Map)
          ? Map<String, dynamic>.from(targetList[targetIndex]['apiReactions']['byEmoji'])
          .map((key, value) => MapEntry(key, value as int))
          : {},
    );

    try {
      if (reaction == null) {
        final uri = Uri.parse('https://www.unistudious.com/api/social-media-delete-reaction/$postId');
        developer.log('ProfilePostsPinsPage: Sending DELETE reaction request to $uri',
            name: 'ProfilePostsPinsPage');
        final response = await http.delete(
          uri,
          headers: {
            'Authorization': 'Bearer ${authProvider.currentToken}',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          setState(() {
            Map<String, String> userReactions =
            Map<String, String>.from(targetList[targetIndex]['userReactions'] ?? {});
            List<Map<String, dynamic>> reactions =
            List<Map<String, dynamic>>.from(targetList[targetIndex]['reactions'] ?? []);

            final previousReaction = userReactions[userId];
            userReactions.remove(userId);
            reactions.removeWhere((r) => r['user']['id'] == userId);

            if (previousReaction != null && currentByEmoji.containsKey(previousReaction)) {
              int count = currentByEmoji[previousReaction]! - 1;
              if (count <= 0) {
                currentByEmoji.remove(previousReaction);
              } else {
                currentByEmoji[previousReaction] = count;
              }
            }
            targetList[targetIndex]['apiReactions']['byEmoji'] = currentByEmoji;
            targetList[targetIndex]['apiReactions']['total'] =
                currentByEmoji.values.fold(0, (a, b) => a + b).toInt();
            targetList[targetIndex]['userReactions'] = userReactions;
            targetList[targetIndex]['reactions'] = reactions;
            targetList[targetIndex]['userReaction'] = null;
            developer.log('ProfilePostsPinsPage: Reaction deleted successfully, postId: $postId',
                name: 'ProfilePostsPinsPage');
          });
        } else {
          developer.log('ProfilePostsPinsPage: Failed to delete reaction, status: ${response.statusCode}',
              name: 'ProfilePostsPinsPage');
        }
      } else {
        final uri = Uri.parse('https://www.unistudious.com/api/social-media-set-reaction');
        var request = http.MultipartRequest('POST', uri)
          ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
          ..fields['id'] = postId
          ..fields['emoji'] = reaction;

        developer.log('ProfilePostsPinsPage: Sending POST reaction request to $uri',
            name: 'ProfilePostsPinsPage');
        final response = await request.send().timeout(const Duration(seconds: 10));
        final responseBody = await response.stream.bytesToString();

        if (response.statusCode == 200) {
          setState(() {
            Map<String, String> userReactions =
            Map<String, String>.from(targetList[targetIndex]['userReactions'] ?? {});
            List<Map<String, dynamic>> reactions =
            List<Map<String, dynamic>>.from(targetList[targetIndex]['reactions'] ?? {});

            bool isNewReaction = !userReactions.containsKey(userId);

            if (userReactions.containsKey(userId)) {
              final previousReaction = userReactions[userId];
              userReactions[userId] = reaction;
              final reactionIndex = reactions.indexWhere((r) => r['user']['id'] == userId);
              if (reactionIndex != -1) {
                reactions[reactionIndex]['emoji'] = reaction;
              }
              if (previousReaction != null && currentByEmoji.containsKey(previousReaction)) {
                int count = currentByEmoji[previousReaction]! - 1;
                if (count <= 0) {
                  currentByEmoji.remove(previousReaction);
                } else {
                  currentByEmoji[previousReaction] = count;
                }
              }
              currentByEmoji[reaction] = (currentByEmoji[reaction] ?? 0) + 1;
            } else {
              userReactions[userId] = reaction;
              reactions.add({
                'emoji': reaction,
                'user': {'id': userId, 'username': finalUsername ?? 'current_user'}
              });
              currentByEmoji[reaction] = (currentByEmoji[reaction] ?? 0) + 1;
            }

            targetList[targetIndex]['apiReactions']['byEmoji'] = currentByEmoji;
            targetList[targetIndex]['apiReactions']['total'] =
                currentByEmoji.values.fold(0, (a, b) => a + b).toInt();
            targetList[targetIndex]['userReactions'] = userReactions;
            targetList[targetIndex]['reactions'] = reactions;
            targetList[targetIndex]['userReaction'] = reaction;
            developer.log('ProfilePostsPinsPage: Reaction set successfully, postId: $postId, reaction: $reaction',
                name: 'ProfilePostsPinsPage');
          });
        } else {
          developer.log('ProfilePostsPinsPage: Failed to set reaction, status: ${response.statusCode}, body: $responseBody',
              name: 'ProfilePostsPinsPage');
        }
      }
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error handling reaction: $e',
          name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de la mise à jour de la réaction : $e');
    }
  }

  Future<Map<String, dynamic>?> _postComment(String postId, String commentText) async {
    developer.log('ProfilePostsPinsPage: Posting comment for postId: $postId, comment: $commentText', name: 'ProfilePostsPinsPage');
    if (commentText.isEmpty) {
      developer.log('ProfilePostsPinsPage: Empty comment, aborting', name: 'ProfilePostsPinsPage');
      SnackBarHelper.showWarning(context, 'Le commentaire ne peut pas être vide.');
      return null;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!await _checkAuth(context, authProvider)) return null;

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-set-comment');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId
        ..fields['comment'] = commentText;

      developer.log('ProfilePostsPinsPage: Sending POST comment request to $uri', name: 'ProfilePostsPinsPage');
      final response = await request.send().timeout(const Duration(seconds: 10));
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final commentData = responseData['data'] is Map<String, dynamic> ? responseData['data'] : {};
        final account = commentData['account'] is Map<String, dynamic> ? commentData['account'] : {};
        String username = account['display_name']?.toString().trim().isNotEmpty ?? false
            ? account['display_name']
            : account['username']?.toString() ?? 'Unknown User';
        String userId = account['id']?.toString() ?? '';

        String profileUrl = account['avatar'] ?? '';
        String text = parse(commentData['content'] ?? '').body?.text.trim() ?? '';
        String timeAgo = _timeAgo(DateTime.parse(commentData['created_at'] ?? DateTime.now().toIso8601String()));

        final newComment = {
          "id": commentData['id'] ?? '',
          "username": username,
          "userId": userId,
          "text": text,
          "timeAgo": timeAgo,
          "profileUrl": profileUrl,
        };

        setState(() {
          final postIndex = statuses.indexWhere((post) => post['id'] == postId);
          final pinnedIndex = pinnedStatuses.indexWhere((post) => post['id'] == postId);
          final targetList = postIndex != -1 ? statuses : pinnedStatuses;
          final targetIndex = postIndex != -1 ? postIndex : pinnedIndex;

          if (targetIndex != -1) {
            if (targetList[targetIndex]['comments'] is! List) {
              developer.log('ProfilePostsPinsPage: Fixing invalid comments type for postId: $postId, type: ${targetList[targetIndex]['comments']?.runtimeType}', name: 'ProfilePostsPinsPage');
              targetList[targetIndex]['comments'] = [];
            }
            targetList[targetIndex]['comments'].add(newComment);
            targetList[targetIndex]['commentCount'] = targetList[targetIndex]['comments'].length;
            developer.log('ProfilePostsPinsPage: Comment added to postId: $postId, commentId: ${commentData['id']}', name: 'ProfilePostsPinsPage');
          }
        });

        SnackBarHelper.showSuccess(context, 'Commentaire publié avec succès !');

        return newComment;
      }
      developer.log('ProfilePostsPinsPage: Failed to post comment, status: ${response.statusCode}, body: $responseBody', name: 'ProfilePostsPinsPage');
      return null;
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error posting comment: $e', name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de la publication du commentaire : $e');
      return null;
    }
  }

  Future<void> _deleteComment(String commentId, String postId) async {
    developer.log('ProfilePostsPinsPage: Deleting comment, commentId: $commentId, postId: $postId',
        name: 'ProfilePostsPinsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!await _checkAuth(context, authProvider)) return;

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-delete-comment');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['commentId'] = commentId;

      final response = await request.send().timeout(const Duration(seconds: 10));
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        setState(() {
          final postIndex = statuses.indexWhere((post) => post['id'] == postId);
          final pinnedIndex = pinnedStatuses.indexWhere((post) => post['id'] == postId);
          final targetList = postIndex != -1 ? statuses : pinnedStatuses;
          final targetIndex = postIndex != -1 ? postIndex : pinnedIndex;

          if (targetIndex != -1) {
            targetList[targetIndex]['comments'].removeWhere((comment) => comment['id'] == commentId);
            targetList[targetIndex]['commentCount'] = targetList[targetIndex]['comments'].length;
            developer.log('ProfilePostsPinsPage: Comment deleted successfully, commentId: $commentId',
                name: 'ProfilePostsPinsPage');
          }
        });
        SnackBarHelper.showSuccess(context, 'Commentaire supprimé avec succès !');
      } else {
        developer.log(
            'ProfilePostsPinsPage: Failed to delete comment, status: ${response.statusCode}, body: $responseBody',
            name: 'ProfilePostsPinsPage');
        SnackBarHelper.showError(context, 'Échec de la suppression : ${responseData['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error deleting comment: $e',
          name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de la suppression : $e');
    }
  }

  Future<void> _markAsFavorite(String postId) async {
    developer.log('ProfilePostsPinsPage: Marking post as favorite, postId: $postId',
        name: 'ProfilePostsPinsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!await _checkAuth(context, authProvider)) return;

    final postIndex = statuses.indexWhere((post) => post['id'] == postId);
    final pinnedIndex = pinnedStatuses.indexWhere((post) => post['id'] == postId);
    final targetIndex = postIndex != -1 ? postIndex : pinnedIndex;
    final targetList = postIndex != -1 ? statuses : pinnedStatuses;

    if (targetIndex == -1) {
      developer.log('ProfilePostsPinsPage: Post not found for marking as favorite, postId: $postId',
          name: 'ProfilePostsPinsPage');
      SnackBarHelper.showError(context, 'Post introuvable.');
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-mark-as-favorite');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send().timeout(const Duration(seconds: 10));
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        setState(() {
          targetList[targetIndex]['favourited'] = responseData['data']['favourited'];
          targetList[targetIndex]['likes'] = responseData['data']['favourites_count'];
          developer.log('ProfilePostsPinsPage: Post marked as favorite, postId: $postId, favourited: ${responseData['data']['favourited']}',
              name: 'ProfilePostsPinsPage');
        });
        SnackBarHelper.showSuccess(context, responseData['data']['favourited'] ? 'Ajouté aux favoris !' : 'Retiré des favoris !');
      } else {
        developer.log('ProfilePostsPinsPage: Failed to mark as favorite, status: ${response.statusCode}, body: $responseBody',
            name: 'ProfilePostsPinsPage');
      }
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error marking post as favorite: $e',
          name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de l\'opération : $e');
    }
  }

  Future<void> _markAsNotFavorite(String postId) async {
    developer.log('ProfilePostsPinsPage: Marking post as not favorite, postId: $postId',
        name: 'ProfilePostsPinsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!await _checkAuth(context, authProvider)) return;

    final postIndex = statuses.indexWhere((post) => post['id'] == postId);
    final pinnedIndex = pinnedStatuses.indexWhere((post) => post['id'] == postId);
    final targetIndex = postIndex != -1 ? postIndex : pinnedIndex;
    final targetList = postIndex != -1 ? statuses : pinnedStatuses;

    if (targetIndex == -1) {
      developer.log('ProfilePostsPinsPage: Post not found for marking as not favorite, postId: $postId',
          name: 'ProfilePostsPinsPage');
      SnackBarHelper.showError(context, 'Post introuvable.');
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-mark-as-not-favorite');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send().timeout(const Duration(seconds: 10));
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        setState(() {
          targetList[targetIndex]['favourited'] = responseData['data']['favourited'];
          targetList[targetIndex]['likes'] = responseData['data']['favourites_count'];
          developer.log('ProfilePostsPinsPage: Post marked as not favorite, postId: $postId',
              name: 'ProfilePostsPinsPage');
        });
        SnackBarHelper.showSuccess(context, 'Retiré des favoris !');
      } else {
        developer.log('ProfilePostsPinsPage: Failed to mark as not favorite, status: ${response.statusCode}, body: $responseBody',
            name: 'ProfilePostsPinsPage');
      }
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error marking post as not favorite: $e',
          name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de l\'opération : $e');
    }
  }

  Future<void> _pinPost(String postId) async {
    developer.log('ProfilePostsPinsPage: Pinning post, postId: $postId',
        name: 'ProfilePostsPinsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!await _checkAuth(context, authProvider)) return;

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-pin');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send().timeout(const Duration(seconds: 10));
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        setState(() {
          final postIndex = statuses.indexWhere((post) => post['id'] == postId);
          if (postIndex != -1) {
            final post = Map<String, dynamic>.from(statuses[postIndex]);
            post['pinned'] = true;
            statuses.removeAt(postIndex);
            pinnedStatuses.insert(0, post);
            developer.log('ProfilePostsPinsPage: Post pinned successfully, postId: $postId',
                name: 'ProfilePostsPinsPage');
          }
        });
        SnackBarHelper.showSuccess(context, 'Statut épinglé avec succès !');
      } else {
        developer.log('ProfilePostsPinsPage: Failed to pin post, status: ${response.statusCode}, body: $responseBody',
            name: 'ProfilePostsPinsPage');
      }
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error pinning post: $e',
          name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de l\'épinglage : $e');
    }
  }

  Future<void> _unpinPost(String postId) async {
    developer.log('ProfilePostsPinsPage: Unpinning post, postId: $postId',
        name: 'ProfilePostsPinsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!await _checkAuth(context, authProvider)) return;

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-not-pin');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send().timeout(const Duration(seconds: 10));
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        setState(() {
          final pinnedIndex = pinnedStatuses.indexWhere((post) => post['id'] == postId);
          if (pinnedIndex != -1) {
            final post = Map<String, dynamic>.from(pinnedStatuses[pinnedIndex]);
            post['pinned'] = false;
            pinnedStatuses.removeAt(pinnedIndex);
            statuses.insert(0, post);
            developer.log('ProfilePostsPinsPage: Post unpinned successfully, postId: $postId',
                name: 'ProfilePostsPinsPage');
          }
        });
        SnackBarHelper.showSuccess(context, 'Statut désépinglé avec succès !');
      } else {
        developer.log('ProfilePostsPinsPage: Failed to unpin post, status: ${response.statusCode}, body: $responseBody',
            name: 'ProfilePostsPinsPage');
      }
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error unpinning post: $e',
          name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors du désépinglage : $e');
    }
  }

  Future<void> _deleteStatus(String statusId) async {
    developer.log('ProfilePostsPinsPage: Deleting status, statusId: $statusId',
        name: 'ProfilePostsPinsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!await _checkAuth(context, authProvider)) return;

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-delete-status/$statusId');
    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${authProvider.currentToken}',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['status'] == 'success') {
        setState(() {
          statuses.removeWhere((post) => post['id'] == statusId);
          pinnedStatuses.removeWhere((post) => post['id'] == statusId);
          developer.log('ProfilePostsPinsPage: Status deleted successfully, statusId: $statusId',
              name: 'ProfilePostsPinsPage');
        });
        SnackBarHelper.showSuccess(context, 'Statut supprimé avec succès !');
      } else {
        developer.log('ProfilePostsPinsPage: Failed to delete status, status: ${response.statusCode}, body: ${response.body}',
            name: 'ProfilePostsPinsPage');
      }
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error deleting status: $e',
          name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de la suppression : $e');
    }
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
    developer.log('ProfilePostsPinsPage: Posting status, statusId: $statusId, status: $status, enablePoll: $enablePoll, pollOptions: $pollOptions, pollDuration: $pollDuration, image: ${image?.path}, removeImage: $removeImage',
        name: 'ProfilePostsPinsPage');
    if (status.isEmpty && image == null && !enablePoll) {
      developer.log('ProfilePostsPinsPage: Post is empty, aborting',
          name: 'ProfilePostsPinsPage');
      SnackBarHelper.showWarning(context, 'Veuillez saisir un statut, ajouter une image ou activer un sondage.');
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!await _checkAuth(context, authProvider)) return;

    final baseUrl = statusId != null
        ? 'https://www.unistudious.com/api/social-media-status-update'
        : 'https://www.unistudious.com/api/social-media-status-create';
    final uri = statusId != null ? Uri.parse('$baseUrl/$statusId') : Uri.parse(baseUrl);

    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['status'] = status
        ..fields['enable_poll'] = enablePoll.toString()
        ..fields['remove_media'] = removeImage.toString();

      if (enablePoll) {
        request.fields.addAll({
          'option1': pollOptions.length > 0 ? pollOptions[0] : '',
          'option2': pollOptions.length > 1 ? pollOptions[1] : '',
          'option3': pollOptions.length > 2 ? pollOptions[2] : '',
          'option4': pollOptions.length > 3 ? pollOptions[3] : '',
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

      developer.log('ProfilePostsPinsPage: Sending POST status request to $uri',
          name: 'ProfilePostsPinsPage');
      final response = await request.send().timeout(const Duration(seconds: 10));
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final statusData = responseData['data'] is Map<String, dynamic> ? responseData['data'] : {};
        final account = statusData['account'] is Map<String, dynamic> ? statusData['account'] : {};
        String username = account['display_name']?.toString().trim().isNotEmpty ?? false
            ? account['display_name']
            : account['username']?.toString() ?? 'Unknown User';
        String userId = account['id']?.toString() ?? '';

        String profileUrl = account['avatar'] ?? '';
        String text = parse(statusData['content'] ?? '').body?.text.trim() ?? '';
        String imageUrl = statusData['media_attachments']?.isNotEmpty ?? false
            ? statusData['media_attachments'][0]['url'] ?? ''
            : '';
        String timeAgo =
        _timeAgo(DateTime.parse(statusData['created_at'] ?? DateTime.now().toIso8601String()));
        dynamic poll = statusData['poll'];
        bool favourited = statusData['favourited'] ?? false;
        bool pinned = statusData['pinned'] ?? false;

        setState(() {
          if (statusId != null) {
            final postIndex = statuses.indexWhere((post) => post['id'] == statusId);
            if (postIndex != -1) {
              statuses[postIndex] = {
                "id": statusData['id'] ?? '',
                "username": username,
                "userId": userId,
                "timeAgo": timeAgo,
                "text": text,
                "imageUrl": imageUrl,
                "likes": statusData['favourites_count'] ?? 0,
                "comments": statuses[postIndex]['comments'],
                "commentCount": statusData['replies_count'] ?? 0,
                "shares": statusData['reblogs_count'] ?? 0,
                "profileUrl": profileUrl,
                "poll": poll,
                "favourited": favourited,
                "userReaction": statuses[postIndex]['userReaction'],
                "userReactions": statuses[postIndex]['userReactions'],
                "reactions": statuses[postIndex]['reactions'],
                "apiReactions": statuses[postIndex]['apiReactions'],
                "pinned": pinned,
              };
              developer.log('ProfilePostsPinsPage: Updated existing post, postId: $statusId',
                  name: 'ProfilePostsPinsPage');
            }
          } else {
            final newPost = {
              "id": statusData['id'] ?? '',
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
              "userReaction": null,
              "userReactions": <String, String>{},
              "reactions": <Map<String, dynamic>>[],
              "apiReactions": {"total": 0, "byEmoji": <String, int>{}},
              "pinned": pinned,
            };
            statuses.insert(0, newPost);
            developer.log('ProfilePostsPinsPage: Added new post, postId: ${statusData['id']}',
                name: 'ProfilePostsPinsPage');
          }
        });

        SnackBarHelper.showSuccess(context, statusId != null ? 'Statut mis à jour avec succès !' : 'Statut publié avec succès !');

        await _fetchSocialMediaData(page: 1);
      } else {
        developer.log('ProfilePostsPinsPage: Failed to post status, status: ${response.statusCode}, body: $responseBody',
            name: 'ProfilePostsPinsPage');
      }
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error posting status: $e',
          name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de la publication : $e');
    }
  }

  Widget _buildPostCard(Map<String, dynamic> post) {
    developer.log('ProfilePostsPinsPage: Building post card for postId: ${post['id']}', name: 'ProfilePostsPinsPage');
    final isOwnPost = post['userId'] == _currentUserId;
    final theme = Theme.of(context);

    List<Map<String, dynamic>> validatedComments = [];
    if (post['comments'] is List) {
      validatedComments = (post['comments'] as List)
          .where((item) => item is Map<String, dynamic>)
          .cast<Map<String, dynamic>>()
          .toList();
    } else {
      developer.log(
          'ProfilePostsPinsPage: Invalid comments type for postId: ${post['id']}, type: ${post['comments']?.runtimeType}, data: ${post['comments']}',
          name: 'ProfilePostsPinsPage');
    }

    // Fonction pour copier le lien du post
    void _copyLink() {
      final postLink = 'https://www.unistudious.com/post/${post['id']}';
      Clipboard.setData(ClipboardData(text: postLink)).then((_) {
        SnackBarHelper.showSuccess(context, 'Lien copié dans le presse-papiers !');
        developer.log('Link copied for post: ${post['id']}', name: 'ProfilePostsPinsPage');
      });
    }

    // Fonction pour partager sur Facebook
    void _shareToFacebook() {
      final postLink = 'https://www.unistudious.com/post/${post['id']}';
      Share.share('Découvrez ce post : $postLink', subject: 'Partage de post');
      developer.log('Share to Facebook for post: ${post['id']}', name: 'ProfilePostsPinsPage');
    }

    // Fonction pour partager via Gmail
    void _shareToGmail() {
      final postLink = 'https://www.unistudious.com/post/${post['id']}';
      final Uri emailUri = Uri(
        scheme: 'mailto',
        queryParameters: {
          'subject': 'Partage de post',
          'body': 'Découvrez ce post : $postLink',
        },
      );
      Share.shareUri(emailUri);
      developer.log('Share to Gmail for post: ${post['id']}', name: 'ProfilePostsPinsPage');
    }

    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: NetworkImage(post['profileUrl']),
              radius: 22,
              backgroundColor: theme.colorScheme.surface,
            ),
            title: Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    developer.log('ProfilePostsPinsPage: Tapped username for userId: ${post['userId']}', name: 'ProfilePostsPinsPage');
                    final profileDetails = await _fetchProfileDetails(post['userId']);
                    if (profileDetails != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserPostsPage(
                            userId: post['userId'],
                            username: post['username'],
                            profileDetails: profileDetails,
                          ),
                        ),
                      );
                    } else {
                      developer.log('ProfilePostsPinsPage: Failed to fetch profile details for userId: ${post['userId']}', name: 'ProfilePostsPinsPage');
                      SnackBarHelper.showError(context, 'Impossible de charger les détails du profil.');
                    }
                  },
                  child: Text(
                    post['username'],
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      fontFamily: GoogleFonts.poppins().fontFamily,
                      color: theme.textTheme.titleMedium?.color,
                    ) ??
                        TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          fontFamily: GoogleFonts.poppins().fontFamily,
                          color: theme.textTheme.titleMedium?.color,
                        ),
                  ),
                ),
                if (post['pinned']) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.push_pin, size: 16, color: Colors.orange),
                ],
              ],
            ),
            subtitle: Text(
              post['timeAgo'],
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: GoogleFonts.poppins().fontFamily,
                color: theme.textTheme.bodySmall?.color,
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
                developer.log('ProfilePostsPinsPage: Showing post options for postId: ${post['id']}', name: 'ProfilePostsPinsPage');
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (bottomSheetContext) => Container(
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark ? theme.cardColor : Colors.white,
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
                            developer.log('ProfilePostsPinsPage: View Profile tapped for post: ${post['id']}', name: 'ProfilePostsPinsPage');
                            Navigator.pop(bottomSheetContext);
                            final profileDetails = await _fetchProfileDetails(post['userId']);
                            if (profileDetails != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserPostsPage(
                                    userId: post['userId'],
                                    username: post['username'],
                                    profileDetails: profileDetails,
                                  ),
                                ),
                              );
                            } else {
                              SnackBarHelper.showError(context, 'Impossible de charger les détails du profil.');
                            }
                          },
                        ),
                        ListTile(
                          leading: Icon(
                            post['favourited'] ? Icons.favorite : Icons.favorite_border,
                            color: Colors.red,
                          ),
                          title: Text(
                            post['favourited'] ? 'Retirer des favoris' : 'Ajouter aux favoris',
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
                            developer.log('ProfilePostsPinsPage: Favorite toggled for postId: ${post['id']}, current: ${post['favourited']}', name: 'ProfilePostsPinsPage');
                            Navigator.pop(bottomSheetContext);
                            if (post['favourited']) {
                              _markAsNotFavorite(post['id']);
                            } else {
                              _markAsFavorite(post['id']);
                            }
                          },
                        ),
                        if (isOwnPost) ...[
                          ListTile(
                            leading: const Icon(Icons.push_pin, color: Colors.orange),
                            title: Text(
                              post['pinned'] ? 'Désépingler du profil' : 'Épingler au profil',
                              style: TextStyle(
                                fontFamily: GoogleFonts.poppins().fontFamily,
                                fontSize: 16,
                              ),
                            ),
                            onTap: () {
                              developer.log('ProfilePostsPinsPage: Pin toggled for postId: ${post['id']}, current: ${post['pinned']}', name: 'ProfilePostsPinsPage');
                              Navigator.pop(bottomSheetContext);
                              if (post['pinned']) {
                                _unpinPost(post['id']);
                              } else {
                                _pinPost(post['id']);
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
                              developer.log('ProfilePostsPinsPage: Edit selected for postId: ${post['id']}', name: 'ProfilePostsPinsPage');
                              Navigator.pop(bottomSheetContext);
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                ),
                                builder: (_) => EditPostSheet(
                                  postId: post['id'],
                                  initialStatus: post['text'],
                                  initialImageUrl: post['imageUrl'],
                                  initialPoll: post['poll'],
                                  postStatus: _postStatus,
                                  onPostSuccess: () => _fetchSocialMediaData(page: 1),
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
                              developer.log('ProfilePostsPinsPage: Delete selected for postId: ${post['id']}', name: 'ProfilePostsPinsPage');
                              Navigator.pop(bottomSheetContext);
                              showDialog(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  backgroundColor: theme.brightness == Brightness.dark ? theme.cardColor : Colors.white,
                                  title: Text(
                                    'Confirmer la suppression',
                                    style: TextStyle(
                                      fontFamily: GoogleFonts.poppins().fontFamily,
                                      fontWeight: FontWeight.bold,
                                      color: theme.textTheme.titleLarge?.color,
                                    ),
                                  ),
                                  content: Text(
                                    'Voulez-vous vraiment supprimer ce statut ?',
                                    style: TextStyle(
                                      fontFamily: GoogleFonts.poppins().fontFamily,
                                      color: theme.textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        developer.log('ProfilePostsPinsPage: Delete cancelled for postId: ${post['id']}', name: 'ProfilePostsPinsPage');
                                        Navigator.pop(dialogContext);
                                      },
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
                                        developer.log('ProfilePostsPinsPage: Delete confirmed for postId: ${post['id']}', name: 'ProfilePostsPinsPage');
                                        Navigator.pop(dialogContext);
                                        _deleteStatus(post['id']);
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
          if (post['text'].isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                post['text'],
                style: TextStyle(
                  fontSize: 15,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
              ),
            ),
          if (post['imageUrl'].isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                post['imageUrl'],
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) {
                  developer.log('ProfilePostsPinsPage: Image load failed for postId: ${post['id']}, url: ${post['imageUrl']}, error: $error', name: 'ProfilePostsPinsPage');
                  return const Icon(Icons.broken_image, size: 50);
                },
              ),
            ),
          if (post['poll'] != null) ...[
            const SizedBox(height: 12),
            _buildPollWidget(post['poll'], post['id']),
          ],
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () {
                    developer.log('ProfilePostsPinsPage: Showing reactions for postId: ${post['id']}, apiReactions: ${post['apiReactions']}', name: 'ProfilePostsPinsPage');
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (_) => ReactionSheet(
                        apiReactions: post['apiReactions'] ?? {'total': 0, 'byEmoji': {}},
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      if (post['apiReactions']['total'] > 0) ...[
                        ...() {
                          Map<String, int> emojiCount = Map<String, int>.from(post['apiReactions']['byEmoji']);
                          var sortedEmojis = emojiCount.entries.toList()
                            ..sort((a, b) => b.value.compareTo(a.value));
                          List<String> topEmojis = sortedEmojis.take(2).map((e) => e.key).toList();
                          int totalReactions = post['apiReactions']['total'];

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
                    developer.log('ProfilePostsPinsPage: Showing comments for postId: ${post['id']}', name: 'ProfilePostsPinsPage');
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (_) => Container(
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark ? theme.cardColor : Colors.white,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        child: CommentSheet(
                          postId: post['id'],
                          comments: validatedComments,
                          onCommentPosted: _postComment,
                          fetchComments: _fetchComments,
                          onDeleteComment: _deleteComment,
                          currentUserId: _currentUserId,
                        ),
                      ),
                    );
                  },
                  child: Text(
                    "${post['commentCount']} commentaires • ${post['shares']} partages",
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
                  postId: post['id'],
                  currentUserId: _currentUserId,
                  userReaction: post['userReaction'],
                  onReactionSelected: _handleReaction,
                ),
                ActionButton(
                  icon: Icons.comment_outlined,
                  label: "Commenter",
                  onTap: () {
                    developer.log('ProfilePostsPinsPage: Comment button tapped for postId: ${post['id']}', name: 'ProfilePostsPinsPage');
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (_) => Container(
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark ? theme.cardColor : Colors.white,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        child: CommentSheet(
                          postId: post['id'],
                          comments: validatedComments,
                          onCommentPosted: _postComment,
                          fetchComments: _fetchComments,
                          onDeleteComment: _deleteComment,
                          currentUserId: _currentUserId,
                        ),
                      ),
                    );
                  },
                ),
                PopupMenuButton<String>(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.share_outlined),
                      const SizedBox(width: 4),
                      Text(
                        'Partager',
                        style: TextStyle(
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

  void _showReactionSheet(BuildContext context, String postId, Map<String, dynamic> reactions) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ReactionSheet(
        apiReactions: reactions,
      ),
    );
  }

  Widget _buildPinnedPostCard(BuildContext context, Map<String, dynamic> status) {
    final postId = status['id'];
    final userReaction = status['userReaction'];
    final apiReactions = status['apiReactions'] ?? {'total': 0, 'byEmoji': {}};
    developer.log('Showing reactions for postId: $postId', name: 'ProfilePostsPinsPage');

    return ListTile(
      title: Text(status['content']),
      trailing: ReactionButton(
        postId: postId,
        currentUserId: 'currentUserId', // Remplacez par la vraie valeur
        userReaction: userReaction,
        onReactionSelected: (postId, emoji, userId) {
          _handleReaction(postId, emoji, userId);
        },
      ),
      onTap: () => _showReactionSheet(context, postId, apiReactions),
    );
  }

  Widget _buildPollWidget(dynamic poll, String postId) {
    developer.log('ProfilePostsPinsPage: Building poll widget for postId: $postId, pollId: ${poll['id']}',
        name: 'ProfilePostsPinsPage');
    bool hasVoted = poll['voted'] ?? false;
    List<dynamic> options = poll['options'] ?? [];
    int totalVotes = poll['votes_count'] ?? 0;
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
              developer.log('ProfilePostsPinsPage: Poll option tapped, postId: $postId, optionIndex: $index',
                  name: 'ProfilePostsPinsPage');
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

  Future<void> _votePoll(String pollId, int optionIndex) async {
    developer.log('ProfilePostsPinsPage: Voting on poll, pollId: $pollId, optionIndex: $optionIndex',
        name: 'ProfilePostsPinsPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!await _checkAuth(context, authProvider)) return;

    final postIndex = statuses.indexWhere((post) => post['poll']?['id'] == pollId);
    final pinnedIndex = pinnedStatuses.indexWhere((post) => post['poll']?['id'] == pollId);
    final targetIndex = postIndex != -1 ? postIndex : pinnedIndex;
    final targetList = postIndex != -1 ? statuses : pinnedStatuses;

    if (targetIndex == -1) {
      developer.log('ProfilePostsPinsPage: Poll not found, pollId: $pollId',
          name: 'ProfilePostsPinsPage');
      SnackBarHelper.showError(context, 'Sondage introuvable.');
      return;
    }

    final poll = targetList[targetIndex]['poll'];
    if (poll['voted'] && !poll['multiple']) {
      developer.log('ProfilePostsPinsPage: User has already voted, pollId: $pollId',
          name: 'ProfilePostsPinsPage');
      SnackBarHelper.showWarning(context, 'Vous avez déjà voté.');
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-vote-poll');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['poll_id'] = pollId
        ..fields['option_index'] = optionIndex.toString();

      developer.log('ProfilePostsPinsPage: Sending POST vote request to $uri',
          name: 'ProfilePostsPinsPage');
      final response = await request.send().timeout(const Duration(seconds: 10));
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        setState(() {
          targetList[targetIndex]['poll'] = responseData['data'];
          developer.log('ProfilePostsPinsPage: Vote recorded successfully, pollId: $pollId',
              name: 'ProfilePostsPinsPage');
        });
        SnackBarHelper.showSuccess(context, 'Vote enregistré !');
      } else {
        developer.log('ProfilePostsPinsPage: Failed to vote on poll, status: ${response.statusCode}, body: $responseBody',
            name: 'ProfilePostsPinsPage');
      }
    } catch (e, stackTrace) {
      developer.log('ProfilePostsPinsPage: Error voting on poll: $e',
          name: 'ProfilePostsPinsPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors du vote : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    developer.log(
        'ProfilePostsPinsPage: build called, isLoading: $isLoading, errorMessage: $errorMessage, statuses: ${statuses.length}, pinnedStatuses: ${pinnedStatuses.length}',
        name: 'ProfilePostsPinsPage');

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[1100] : Colors.grey[100],

      drawer: const AppSidebar(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: theme.appBarTheme.iconTheme?.color ?? Colors.white),
          onPressed: () {
            developer.log('ProfilePostsPinsPage: Back button pressed',
                name: 'ProfilePostsPinsPage');
            Navigator.pop(context);
          },
        ),
        title: Text(
          'Publications et épingles',
          style: GoogleFonts.poppins(
            color: theme.appBarTheme.foregroundColor ?? Colors.white,
          ),
        ),
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: tabs
              .map((tab) => Tab(
            child: Text(
              tab,
              style: TextStyle(
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
            ),
          ))
              .toList(),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
          ? Center(
        child: Text(errorMessage!,
            style: TextStyle(
                fontFamily: GoogleFonts.poppins().fontFamily,
                color: isDark ? Colors.white70 : Colors.black)),
      )
          : TabBarView(
        controller: _tabController,
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await _fetchSocialMediaData(page: 1);
            },
            child: statuses.isEmpty
                ? Center(
              child: Text(
                'Aucune publication disponible',
                style: TextStyle(
                    fontFamily: GoogleFonts.poppins().fontFamily,
                    color: isDark ? Colors.white70 : Colors.black),
              ),
            )
                : ListView.builder(
              controller: _scrollControllerStatuses,
              cacheExtent: 1000,
              itemCount: statuses.length + (isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == statuses.length && isLoadingMore) {
                  return const Center(
                      child: CircularProgressIndicator());
                }
                return _buildPostCard(statuses[index]);
              },
            ),
          ),
          pinnedStatuses.isEmpty
              ? Center(
            child: Text(
              'Aucune épingle disponible',
              style: TextStyle(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  color: isDark ? Colors.white70 : Colors.black),
            ),
          )
              : ListView.builder(
            controller: _scrollControllerPinned,
            cacheExtent: 1000,
            itemCount: pinnedStatuses.length,
            itemBuilder: (context, index) =>
                _buildPostCard(pinnedStatuses[index]),
          ),
        ],
      ),
    );
  }


}

// EditPostSheet implementation
class EditPostSheet extends StatefulWidget {
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

  const EditPostSheet({
    super.key,
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

class _EditPostSheetState extends State<EditPostSheet> {
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
    if (_enablePoll) {
      _pollControllers = (widget.initialPoll['options'] as List<dynamic>)
          .map((option) => TextEditingController(text: option['title'] as String))
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
      name: 'SocialFeedPage.EditPostSheet',
    );
  }

  void _addPollOption() {
    if (_pollControllers.length < 4) {
      setState(() {
        _pollControllers.add(TextEditingController());
        developer.log(
          'Added new poll option, total options: ${_pollControllers.length}',
          name: 'SocialFeedPage.EditPostSheet',
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
          name: 'SocialFeedPage.EditPostSheet',
        );
      });
    }
  }

  Future<void> _updatePost() async {
    String statusText = _editStatusController.text.trim();
    List<String> pollOptions = _pollControllers.map((c) => c.text.trim()).where((text) => text.isNotEmpty).toList();
    developer.log(
      'Updating post, postId: ${widget.postId}, status: $statusText, enablePoll: $_enablePoll, pollOptions: $pollOptions, selectedDuration: $_selectedDuration, originalDuration: $_originalDuration, image: ${_selectedImage?.path}, removeImage: $_removeImage',
      name: 'SocialFeedPage.EditPostSheet',
    );

    if (statusText.isEmpty && _selectedImage == null && (!_enablePoll || pollOptions.isEmpty) && widget.initialImageUrl.isEmpty) {
      developer.log('Post update failed: status, image, and poll are empty', name: 'SocialFeedPage.EditPostSheet');
      SnackBarHelper.showWarning(context, 'Veuillez saisir un statut, ajouter une image ou activer un sondage.');
      return;
    }

    if (_enablePoll && pollOptions.length < 2) {
      developer.log('Post update failed: less than 2 poll options', name: 'SocialFeedPage.EditPostSheet');
      SnackBarHelper.showWarning(context, 'Veuillez saisir au moins deux options pour le sondage.');
      return;
    }

    if (_enablePoll && _selectedDuration == null && _originalDuration == null) {
      developer.log('Post update failed: no poll duration selected', name: 'SocialFeedPage.EditPostSheet');
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
          developer.log('Downloaded original image to preserve it', name: 'SocialFeedPage.EditPostSheet');
        } else {
          developer.log('Failed to download original image: ${response.statusCode}', name: 'SocialFeedPage.EditPostSheet');
          SnackBarHelper.showError(context, 'Erreur lors du téléchargement de l\'image originale.');
          return;
        }
      } catch (e) {
        developer.log('Error downloading original image: $e', name: 'SocialFeedPage.EditPostSheet');
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
  }

  @override
  Widget build(BuildContext context) {
    developer.log('Building EditPostSheet', name: 'SocialFeedPage.EditPostSheet');
    return Padding(
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontFamily: GoogleFonts.poppins().fontFamily,
                color: Theme.of(context).colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              "Votre statut",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
                fontFamily: GoogleFonts.poppins().fontFamily,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _editStatusController,
              decoration: InputDecoration(
                hintText: "Modifier votre statut",
                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainer,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: IconButton(
                  icon: Icon(
                    Icons.camera_alt,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  onPressed: () async {
                    final picker = ImagePicker();
                    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                    if (pickedFile != null) {
                      setState(() {
                        _selectedImage = pickedFile;
                        _removeImage = false;
                      });
                    }
                  },
                  tooltip: 'Ajouter ou remplacer une image',
                ),
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFamily: GoogleFonts.poppins().fontFamily,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onChanged: (value) {
                developer.log('Edit status changed: $value', name: 'SocialFeedPage.EditPostSheet');
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
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.broken_image,
                          size: 50,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedImage = null;
                          _removeImage = true;
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontFamily: GoogleFonts.poppins().fontFamily,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Switch(
                  value: _enablePoll,
                  onChanged: (value) {
                    setState(() {
                      _enablePoll = value!;
                    });
                    developer.log('Poll toggle changed: $_enablePoll', name: 'SocialFeedPage.EditPostSheet');
                  },
                  activeColor: Theme.of(context).colorScheme.primary,
                  inactiveTrackColor: Theme.of(context).colorScheme.surfaceContainer,
                ),
              ],
            ),
            if (_enablePoll) ...[
              const SizedBox(height: 20),
              Text(
                "Options de réponse",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceContainer,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          onChanged: (value) {
                            developer.log('Poll option $index changed: $value',
                                name: 'SocialFeedPage.EditPostSheet');
                          },
                        ),
                      ),
                      if (_pollControllers.length > 2)
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      label: Text(
                        "Ajouter une option",
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontFamily: GoogleFonts.poppins().fontFamily,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        shape: const StadiumBorder(),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                "Durée du sondage",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: "Durée",
                  labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: GoogleFonts.poppins().fontFamily,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                value: _selectedDuration,
                onChanged: (value) {
                  setState(() => _selectedDuration = value);
                  developer.log('Poll duration changed: $value', name: 'SocialFeedPage.EditPostSheet');
                },
                items: _durations.map((duration) {
                  return DropdownMenuItem(
                    value: duration,
                    child: Text(
                      duration,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: GoogleFonts.poppins().fontFamily,
                        color: Theme.of(context).colorScheme.onSurface,
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
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              label: Text(
                "Mettre à jour",
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
  }
}

// ReactionButton implementation
class ReactionButton extends StatefulWidget {
  final String postId;
  final String currentUserId;
  final String? userReaction;
  final Function(String, String?, String) onReactionSelected;

  const ReactionButton({
    super.key,
    required this.postId,
    required this.currentUserId,
    required this.userReaction,
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
    developer.log("🔵 ReactionButton init avec ${widget.userReaction}",
        name: 'ReactionButton');
  }

  @override
  void didUpdateWidget(covariant ReactionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userReaction != widget.userReaction) {
      developer.log("🟢 ReactionButton MAJ : ${widget.userReaction}",
          name: 'ReactionButton');
      setState(() {
        _selectedReaction = widget.userReaction;
      });
    }
  }

  void _showReactions(BuildContext context) {
    _removeOverlay();
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
                child: Semantics(
                  label: 'Menu de sélection des réactions',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.shadow.withOpacity(0.2),
                          blurRadius: 6,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: reactions.map((emoji) {
                        return Semantics(
                          label: reactionLabels[emoji] ?? 'Réaction',
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedReaction = emoji;
                              });
                              widget.onReactionSelected(widget.postId, emoji, widget.currentUserId);
                              _removeOverlay();
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                emoji,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontSize: 26,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showReactions(context),
      onTap: () {
        if (_selectedReaction != null) {
          setState(() {
            _selectedReaction = null;
          });
          widget.onReactionSelected(widget.postId, null, widget.currentUserId);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selectedReaction == null) ...[
            Icon(
              Icons.thumb_up_alt_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
          ] else ...[
            Text(
              _selectedReaction!,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            _selectedReaction != null
                ? reactionLabels[_selectedReaction] ?? "Réagir"
                : "Réagir",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _selectedReaction != null
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
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
  }
}

// ReactionSheet implementation
class ReactionSheet extends StatelessWidget {
  final Map<String, dynamic> apiReactions;

  const ReactionSheet({super.key, required this.apiReactions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Map<String, dynamic> byEmoji = apiReactions['byEmoji'] ?? {};
    final int totalReactions = apiReactions['total'] ?? 0;
    final List<MapEntry<String, dynamic>> emojiList = byEmoji.entries.toList();

    // Log reaction data for debugging
    developer.log(
      'ReactionSheet data for post: byEmoji: $byEmoji, total: $totalReactions',
      name: 'ReactionSheet',
    );

    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
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
                color: theme.colorScheme.onSurface,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.close,
                color: theme.colorScheme.onSurface,
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
          color: theme.colorScheme.onSurfaceVariant,
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
    style: theme.textTheme.bodyLarge?.copyWith(
    fontSize: 24,
    color: theme.colorScheme.onSurface,
    ),
    ),
    title: Text(
    '$count réaction${count > 1 ? 's' : ''}',
    style: theme.textTheme.bodyLarge?.copyWith(
    fontFamily: GoogleFonts.poppins().fontFamily,
    fontSize: 16,
    color: theme.colorScheme.onSurface,
    ),
    ),
    );
    }
    ),
    ),
    ],
    ),
    );
    }
  }



// CommentSheet implementation
class CommentSheet extends StatefulWidget {
  final String postId;
  final List<Map<String, dynamic>> comments;
  final Future<Map<String, dynamic>?> Function(String, String) onCommentPosted;
  final Future<List<Map<String, dynamic>>> Function(String) fetchComments;
  final void Function(String, String) onDeleteComment;
  final String currentUserId;

  const CommentSheet({
    super.key,
    required this.postId,
    required this.comments,
    required this.onCommentPosted,
    required this.fetchComments,
    required this.onDeleteComment,
    required this.currentUserId,
  });

  @override
  _CommentSheetState createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final TextEditingController _commentController = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _isLoadingComments = false;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _commentKeys = {};

  String? _selectedCommentId;

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
    final newComment = await widget.onCommentPosted(postId, commentText);
    if (newComment != null) {
      setState(() {
        _comments.add(newComment);
        _commentKeys[newComment['id']] = GlobalKey();
      });
      await _fetchComments();
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
      _selectedCommentId = commentId;
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
        PopupMenuItem(
          value: "delete",
          child: Row(
            children: [
              Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 8),
              Text(
                "Supprimer",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (selected == "delete") {
      _handleDeleteComment(commentId);
    } else {
      setState(() {
        _selectedCommentId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Offset _tapPosition = Offset.zero;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Material(
        color: theme.cardColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Commentaires',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
            ),
            const SizedBox(height: 10),
            _isLoadingComments
                ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
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
                        color: isSelected ? theme.colorScheme.primary.withOpacity(0.1) : null,
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
                            color: theme.textTheme.bodyLarge?.color ?? (isDark ? Colors.white : Colors.black87),
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                        ),
                        subtitle: Text(
                          comment['text'],
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color ?? (isDark ? Colors.white70 : Colors.black87),
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                        ),
                        trailing: Text(
                          comment['timeAgo'],
                          style: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color ?? (isDark ? Colors.white : Colors.black87),
                      fontFamily: GoogleFonts.poppins().fontFamily,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Écrire un commentaire...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send_rounded, color: theme.colorScheme.primary, size: 28),
                  onPressed: () {
                    if (_commentController.text.isNotEmpty) {
                      _handleCommentPosted(widget.postId, _commentController.text);
                      _commentController.clear();
                    }
                  },
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

// ActionButton widget
class ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultColor = theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      splashColor: theme.colorScheme.primary.withOpacity(0.1),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: color ?? defaultColor,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color ?? defaultColor,
              fontFamily: GoogleFonts.poppins().fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}