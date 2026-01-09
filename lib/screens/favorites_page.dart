import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:developer' as developer;
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/snackbar_helper.dart';
import 'user_posts_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  _FavoritesPageState createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  bool isLoading = true;
  bool isLoadingMore = false;
  String? errorMessage;
  List<Map<String, dynamic>> posts = [];
  String? _finalUsername;
  String? targetUserId;
  final String _currentUserId = "current_user";
  int currentPage = 1;
  int totalPages = 1;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    developer.log('🔵 FavoritesPage initState called', name: 'FavoritesPage');
    _checkAuthAndFetchData();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200 &&
          !isLoading &&
          !isLoadingMore &&
          currentPage < totalPages) {
        developer.log('🔵 Scroll listener triggered, fetching more posts',
            name: 'FavoritesPage');
        _fetchMorePosts();
      }
    });
  }

  Future<void> _checkAuthAndFetchData() async {
    developer.log('🔵 _checkAuthAndFetchData called', name: 'FavoritesPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    developer.log('🔵 AuthProvider logged in: ${authProvider.isLoggedIn}',
        name: 'FavoritesPage');
    developer.log(
        '🔵 AuthProvider token: ${authProvider.currentToken != null ? "${authProvider.currentToken!.substring(0, 10)}..." : "null"}',
        name: 'FavoritesPage');

    if (!authProvider.isLoggedIn) {
      developer.log('🔵 User not logged in, redirecting to login',
          name: 'FavoritesPage');
      if (mounted) {
        SnackBarHelper.showWarning(context, 'Veuillez vous connecter pour continuer.');
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }
    developer.log('🔵 User authenticated, fetching favorites page 1',
        name: 'FavoritesPage');
    await _fetchFavoritePosts(page: 1);
  }

  Future<String?> _fetchUserIdByUsername(String username) async {
    developer.log('🔵 _fetchUserIdByUsername called with username: $username',
        name: 'FavoritesPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('🔴 No valid token available for fetching user ID',
          name: 'FavoritesPage');
      return null;
    }

    final uri = Uri.parse(
        'https://www.unistudious.com/api/social-media-get-userid-by-username');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['username'] = username;

      developer.log(
          '🔵 Sending request to fetch user ID for username: $username',
          name: 'FavoritesPage');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      developer.log(
          '🔵 User ID API response: $responseBody, status: ${response.statusCode}',
          name: 'FavoritesPage');

      final responseData = jsonDecode(responseBody);
      if (response.statusCode == 200 && responseData['id'] != null) {
        developer.log('🟢 User ID fetched successfully: ${responseData['id']}',
            name: 'FavoritesPage');
        return responseData['id']?.toString();
      } else {
        developer.log(
            '🔴 Failed to fetch user ID: ${response.statusCode}, response: $responseBody',
            name: 'FavoritesPage');
        return null;
      }
    } catch (e, stackTrace) {
      developer.log('🔴 Error fetching user ID: $e',
          name: 'FavoritesPage', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchProfileDetails(String userId) async {
    developer.log('🔵 _fetchProfileDetails called with userId: $userId',
        name: 'FavoritesPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('🔴 No valid token available for fetching profile details',
          name: 'FavoritesPage');
      return null;
    }

    final uri = Uri.parse(
        'https://www.unistudious.com/api/profile-details-social-media/$userId');
    try {
      developer.log('🔵 Fetching profile details for userId: $userId',
          name: 'FavoritesPage');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${authProvider.currentToken}',
          'Content-Type': 'application/json',
        },
      );

      developer.log(
          '🔵 Profile details API response: ${response.body}, status: ${response.statusCode}',
          name: 'FavoritesPage');
      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['data'] != null) {
        developer.log('🟢 Profile details fetched successfully',
            name: 'FavoritesPage');
        return responseData['data'];
      } else {
        developer.log(
            '🔴 Failed to fetch profile details: ${response.statusCode}, response: ${response.body}',
            name: 'FavoritesPage');
        return null;
      }
    } catch (e, stackTrace) {
      developer.log('🔴 Error fetching profile details: $e',
          name: 'FavoritesPage', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchComments(String postId) async {
    developer.log('🔵 _fetchComments called for postId: $postId',
        name: 'FavoritesPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      final uri =
      Uri.parse('https://www.unistudious.com/api/social-media-get-comment');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      developer.log('🔵 Fetching comments for post: $postId',
          name: 'FavoritesPage');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      developer.log(
          '🔵 Comment API response: $responseBody, status: ${response.statusCode}',
          name: 'FavoritesPage');

      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final List<dynamic> comments = responseData['data'] ?? [];
        developer.log('🟢 Number of comments received: ${comments.length}',
            name: 'FavoritesPage');

        return comments.map((comment) {
          developer.log('🔵 Processing comment: $comment', name: 'FavoritesPage');

          final account = comment['account'];
          String username = 'Unknown User';
          String userId = '';
          if (account != null) {
            developer.log('🔵 Account data: $account', name: 'FavoritesPage');
            username = account['display_name']?.toString().trim().isNotEmpty ??
                false
                ? account['display_name']
                : account['username']?.toString() ?? 'Unknown User';
            userId = account['id']?.toString() ?? '';
          } else {
            developer.log('⚠️ Warning: comment.account is null',
                name: 'FavoritesPage');
          }

          String text = _stripHtml(comment['content'] ?? '');
          String timeAgo = _timeAgo(DateTime.parse(
              comment['created_at'] ?? DateTime.now().toIso8601String()));
          String profileUrl = comment['account']?['avatar'] ?? '';

          return {
            "id": comment['id'] ?? '',
            "username": username,
            "userId": userId,
            "text": text,
            "timeAgo": timeAgo,
            "profileUrl": profileUrl,
          };
        }).toList();
      } else {
        developer.log(
            '🔴 Failed to fetch comments: ${response.statusCode}, response: $responseBody',
            name: 'FavoritesPage');
        return [];
      }
    } catch (e, stackTrace) {
      developer.log('🔴 Error fetching comments: $e',
          name: 'FavoritesPage', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchReactions(String postId) async {
    developer.log('🔵 _fetchReactions called for postId: $postId',
        name: 'FavoritesPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('🔴 No valid token available for fetching reactions',
          name: 'FavoritesPage');
      return [];
    }

    final uri =
    Uri.parse('https://www.unistudious.com/api/social-media-get-reaction');
    try {
      developer.log('🔵 Fetching reactions for post: $postId',
          name: 'FavoritesPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      developer.log(
          '🔵 Reaction API response: $responseBody, status: ${response.statusCode}',
          name: 'FavoritesPage');
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final List<dynamic> reactions = responseData['reactions'] ?? [];
        developer.log('🟢 Number of reactions received: ${reactions.length}',
            name: 'FavoritesPage');
        // Log the full list of reactions
        developer.log('🟢 Reactions list: $reactions',
            name: 'FavoritesPage');
        return reactions.map((reaction) {
          final user = reaction['user'];
          String username = 'Unknown User';
          String userId = '';
          if (user != null) {
            developer.log('🔵 User data: $user', name: 'FavoritesPage');
            username = user['display_name']?.toString().trim().isNotEmpty ?? false
                ? user['display_name']
                : user['username']?.toString() ?? 'Unknown User';
            userId = user['id']?.toString() ?? '';
          } else {
            developer.log('⚠️ Warning: reaction.user is null',
                name: 'FavoritesPage');
          }
          return {
            'emoji': reaction['emoji'] ?? '',
            'user': {
              'id': userId,
              'username': username,
            },
          };
        }).toList();
      } else {
        developer.log(
            '🔴 Failed to fetch reactions: ${response.statusCode}, response: $responseBody',
            name: 'FavoritesPage');
        return [];
      }
    } catch (e, stackTrace) {
      developer.log('🔴 Error fetching reactions: $e',
          name: 'FavoritesPage', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  Future<void> _fetchFavoritePosts({required int page}) async {
    developer.log('Fetching favorite posts for page: $page',
        name: 'FavoritesPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      setState(() {
        if (page == 1) {
          isLoading = true;
          developer.log('Setting isLoading to true for initial load',
              name: 'FavoritesPage');
        } else {
          isLoadingMore = true;
          developer.log('Setting isLoadingMore to true for page $page',
              name: 'FavoritesPage');
        }
      });

      final uri = Uri.parse(
          'https://www.unistudious.com/api/favorite-social-media?page=$page');
      developer.log('Sending GET request to $uri', name: 'FavoritesPage');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${authProvider.currentToken}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      developer.log(
          'Response status: ${response.statusCode}, headers: ${response.headers}, body: ${response.body.substring(0, response.body.length > 100 ? 100 : response.body.length)}...',
          name: 'FavoritesPage');

      if (response.statusCode != 200) {
        setState(() {
          errorMessage = 'Échec du chargement des favoris : Code ${response.statusCode}';
          isLoading = false;
          isLoadingMore = false;
          developer.log(
              'Failed to load favorites, status: ${response.statusCode}, body: ${response.body.substring(0, response.body.length > 100 ? 100 : response.body.length)}...',
              name: 'FavoritesPage');
        });
        return;
      }

      if (response.body.trim().startsWith('<!doctype html') ||
          response.body.trim().startsWith('<html')) {
        developer.log('Unexpected HTML response detected', name: 'FavoritesPage');
        setState(() {
          errorMessage = 'Réponse inattendue du serveur : Contenu HTML reçu';
          isLoading = false;
          isLoadingMore = false;
        });
        return;
      }

      if (response.headers['content-type']?.contains('application/json') !=
          true) {
        developer.log('Unexpected response type: ${response.headers['content-type']}',
            name: 'FavoritesPage');
        setState(() {
          errorMessage = 'Réponse inattendue du serveur : format non JSON';
          isLoading = false;
          isLoadingMore = false;
        });
        return;
      }

      final responseData = jsonDecode(response.body);
      developer.log(
          'Favorites response: statusCode=${response.statusCode}, body=$responseData',
          name: 'FavoritesPage');

      final data = responseData['data'] ?? {};
      final List<dynamic> statuses = data['statuses'] ?? [];
      final String? finalUsername = data['finalUsername']?.toString();
      final pagination = data['pagination'] ?? {};

      developer.log('Number of statuses received: ${statuses.length}',
          name: 'FavoritesPage');
      developer.log('Final username: $finalUsername', name: 'FavoritesPage');
      developer.log('Pagination: $pagination', name: 'FavoritesPage');

      if (statuses.isEmpty) {
        developer.log('No statuses returned from API', name: 'FavoritesPage');
        setState(() {
          posts = [];
          currentPage = page;
          totalPages = pagination['totalPages'] ?? 1;
          isLoading = false;
          isLoadingMore = false;
          _finalUsername = finalUsername ?? 'Unknown User';
          this.targetUserId = null;
        });
        return;
      }

      setState(() {
        _finalUsername = finalUsername ?? 'Unknown User';
        developer.log('Set _finalUsername: $_finalUsername',
            name: 'FavoritesPage');
      });

      if (_finalUsername != null && _finalUsername != 'Unknown User') {
        developer.log('Fetching user ID for finalUsername: $_finalUsername',
            name: 'FavoritesPage');
        targetUserId = await _fetchUserIdByUsername(_finalUsername!);
        developer.log('Fetched targetUserId: $targetUserId',
            name: 'FavoritesPage');
      } else {
        developer.log('No valid _finalUsername to fetch targetUserId',
            name: 'FavoritesPage');
      }

      final Map<String, String> userReactions = {};
      final mappedPosts = <Map<String, dynamic>>[];
      for (var status in statuses) {
        final statusData = status['status'];
        final account = statusData?['account'];
        String username = 'Unknown User';
        String profileUrl = '';
        String userId = '';

        if (account != null) {
          username = account['display_name']?.toString().trim().isNotEmpty ??
              false
              ? account['display_name']
              : account['username']?.toString() ?? 'Unknown User';
          profileUrl = account['avatar']?.toString() ?? '';
          userId = account['id']?.toString() ?? '';
          if (userId.isEmpty && account['username'] != null) {
            developer.log(
                'User ID empty, fetching for username: ${account['username']}',
                name: 'FavoritesPage');
            userId = await _fetchUserIdByUsername(account['username']) ?? '';
          }
        }
        developer.log(
            'Processed account: username=$username, userId=$userId, profileUrl=$profileUrl',
            name: 'FavoritesPage');

        String text = _stripHtml(statusData?['content'] ?? '');
        String imageUrl = '';
        if (statusData?['media_attachments']?.isNotEmpty ?? false) {
          if (statusData['media_attachments'][0]['type'] == 'image') {
            imageUrl = statusData['media_attachments'][0]['url']?.toString() ?? '';
            developer.log('Found image attachment: $imageUrl',
                name: 'FavoritesPage');
          }
        }
        String timeAgo = _timeAgo(DateTime.parse(
            statusData?['created_at'] ?? DateTime.now().toIso8601String()));
        int likes = statusData?['favourites_count'] ?? 0;
        int commentCount = statusData?['replies_count'] ?? 0;
        int shares = statusData?['reblogs_count'] ?? 0;
        dynamic poll = statusData?['poll'];
        bool favourited = statusData?['favourited'] ?? false;

        developer.log('Fetching comments for postId: ${statusData?['id']}',
            name: 'FavoritesPage');
        final commentList = await _fetchComments(statusData?['id'] ?? '');
        developer.log('Fetching reactions for postId: ${statusData?['id']}',
            name: 'FavoritesPage');
        final reactionList = await _fetchReactions(statusData?['id'] ?? '');

        final postReactions = <String, String>{};
        for (var reaction in reactionList) {
          final userId = reaction['user']['id'];
          final emoji = reaction['emoji'];
          postReactions[userId] = emoji;
        }
        final userReaction = status['userReaction'] ?? null;

        if (userReaction != null) {
          postReactions[_currentUserId] = userReaction;
          userReactions[statusData?['id']] = userReaction;
        }

        if (statusData != null) {
          final postData = {
            "id": statusData['id'] ?? '',
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
          };
          mappedPosts.add(postData);
          developer.log(
              'Added post to mappedPosts: id=${postData['id']}, username=$username',
              name: 'FavoritesPage');
        }
      }

      setState(() {
        if (page == 1) {
          posts = List<Map<String, dynamic>>.from(mappedPosts);
          developer.log('Replaced posts with ${posts.length} items for page 1',
              name: 'FavoritesPage');
        } else {
          posts.addAll(mappedPosts);
          developer.log(
              'Appended ${mappedPosts.length} posts, total now: ${posts.length}',
              name: 'FavoritesPage');
        }
        currentPage = pagination['currentPage'] ?? page;
        totalPages = pagination['totalPages'] ?? 1;
        isLoading = false;
        isLoadingMore = false;
        this.targetUserId = targetUserId;
        developer.log(
            'Updated state: currentPage=$currentPage, totalPages=$totalPages, targetUserId=$targetUserId',
            name: 'FavoritesPage');
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Erreur lors du chargement des favoris : $e';
        isLoading = false;
        isLoadingMore = false;
        developer.log('Error loading favorites: $errorMessage',
            name: 'FavoritesPage', error: e);
      });
    }
  }

  Future<void> _fetchMorePosts() async {
    developer.log(
        '🔵 _fetchMorePosts called, currentPage: $currentPage, totalPages: $totalPages',
        name: 'FavoritesPage');
    if (currentPage < totalPages) {
      developer.log('🔵 Fetching more posts for page: ${currentPage + 1}',
          name: 'FavoritesPage');
      await _fetchFavoritePosts(page: currentPage + 1);
    } else {
      developer.log(
          '🔵 No more pages to load (current: $currentPage, total: $totalPages)',
          name: 'FavoritesPage');
    }
  }

  String _stripHtml(String html) {
    final stripped = html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    developer.log(
        '🔵 Stripped HTML: "${html.substring(0, html.length > 50 ? 50 : html.length)}..." -> "${stripped.substring(0, stripped.length > 50 ? 50 : stripped.length)}..."',
        name: 'FavoritesPage');
    return stripped;
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    String result;
    if (diff.inDays > 0) {
      result = '${diff.inDays}j';
    } else if (diff.inHours > 0) {
      result = '${diff.inHours}h';
    } else if (diff.inMinutes > 0) {
      result = '${diff.inMinutes}m';
    } else {
      result = 'maintenant';
    }
    developer.log('🔵 Time ago for $date: $result', name: 'FavoritesPage');
    return result;
  }

  Future<void> _markAsNotFavorite(String postId) async {
    developer.log('🔵 _markAsNotFavorite called for postId: $postId',
        name: 'FavoritesPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('🔴 No valid token for mark as not favorite',
          name: 'FavoritesPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['id'] == postId);
    developer.log('🔵 Post index for $postId: $postIndex', name: 'FavoritesPage');
    if (postIndex == -1) {
      developer.log('🔴 Post not found: $postId', name: 'FavoritesPage');
      SnackBarHelper.showError(context, 'Post introuvable.');
      return;
    }

    final uri = Uri.parse(
        'https://www.unistudious.com/api/social-media-mark-as-not-favorite');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      developer.log('🔵 Sending request to mark as not favorite: $postId',
          name: 'FavoritesPage');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);
      developer.log(
          '🔵 Mark as not favorite response: $responseBody, status: ${response.statusCode}',
          name: 'FavoritesPage');

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('🟢 Post marked as not favorite successfully',
            name: 'FavoritesPage');
        setState(() {
          posts.removeAt(postIndex);
        });
        SnackBarHelper.showSuccess(context, 'Retiré des favoris !');
      } else {
        developer.log(
            '🔴 Failed to mark as not favorite: ${response.statusCode}, response: $responseBody',
            name: 'FavoritesPage');
        SnackBarHelper.showError(context, 'Échec de l\'opération : ${responseData['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e, stackTrace) {
      developer.log('🔴 Error marking as not favorite: $e',
          name: 'FavoritesPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de l\'opération : $e');
    }
  }

  Future<void> _markAsFavorite(String postId) async {
    developer.log('🔵 _markAsFavorite called for postId: $postId',
        name: 'FavoritesPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('🔴 No valid token for mark as favorite',
          name: 'FavoritesPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['id'] == postId);
    developer.log('🔵 Post index for $postId: $postIndex', name: 'FavoritesPage');
    if (postIndex == -1) {
      developer.log('🔴 Post not found: $postId', name: 'FavoritesPage');
      SnackBarHelper.showError(context, 'Post introuvable.');
      return;
    }

    final uri = Uri.parse(
        'https://www.unistudious.com/api/social-media-mark-as-favorite');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      developer.log('🔵 Sending request to mark as favorite: $postId',
          name: 'FavoritesPage');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);
      developer.log(
          '🔵 Mark as favorite response: $responseBody, status: ${response.statusCode}',
          name: 'FavoritesPage');

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log(
            '🟢 Post marked as favorite successfully, new favourited: ${responseData['data']['favourited']}',
            name: 'FavoritesPage');
        setState(() {
          posts[postIndex]['favourited'] = responseData['data']['favourited'];
          posts[postIndex]['likes'] = responseData['data']['favourites_count'];
        });
        SnackBarHelper.showSuccess(context, responseData['data']['favourited'] ? 'Ajouté aux favoris !' : 'Retiré des favoris !');
      } else {
        developer.log(
            '🔴 Failed to mark as favorite: ${response.statusCode}, response: $responseBody',
            name: 'FavoritesPage');
        SnackBarHelper.showError(context, 'Échec de l\'opération : ${responseData['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e, stackTrace) {
      developer.log('🔴 Error marking as favorite: $e',
          name: 'FavoritesPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de l\'opération : $e');
    }
  }

  Future<void> _deleteComment(String commentId, String postId) async {
    developer.log(
        '🔵 _deleteComment called for commentId: $commentId, postId: $postId',
        name: 'FavoritesPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('🔴 No valid token for delete comment',
          name: 'FavoritesPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final uri = Uri.parse(
        'https://www.unistudious.com/api/social-media-delete-comment');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['commentId'] = commentId;

      developer.log('🔵 Sending request to delete comment: $commentId',
          name: 'FavoritesPage');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);
      developer.log(
          '🔵 Delete comment response: $responseBody, status: ${response.statusCode}',
          name: 'FavoritesPage');

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('🟢 Comment deleted successfully', name: 'FavoritesPage');
        setState(() {
          final postIndex = posts.indexWhere((post) => post['id'] == postId);
          if (postIndex != -1) {
            posts[postIndex]['comments']
                .removeWhere((comment) => comment['id'] == commentId);
            posts[postIndex]['commentCount'] = posts[postIndex]['comments'].length;
            developer.log(
                '🔵 Updated comments count: ${posts[postIndex]['commentCount']}',
                name: 'FavoritesPage');
          }
        });
        SnackBarHelper.showSuccess(context, 'Commentaire supprimé avec succès !');
      } else {
        developer.log(
            '🔴 Failed to delete comment: ${response.statusCode}, response: $responseBody',
            name: 'FavoritesPage');
        SnackBarHelper.showError(context, 'Échec de la suppression : ${responseData['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e, stackTrace) {
      developer.log('🔴 Error deleting comment: $e',
          name: 'FavoritesPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de la suppression : $e');
    }
  }

  Future<Map<String, dynamic>?> _postComment(
      String postId, String commentText) async {
    developer.log(
        '🔵 _postComment called for postId: $postId, comment: ${commentText.substring(0, commentText.length > 50 ? 50 : commentText.length)}...',
        name: 'FavoritesPage');
    if (commentText.isEmpty) {
      developer.log('🔴 Comment posting failed: comment is empty',
          name: 'FavoritesPage');
      SnackBarHelper.showWarning(context, 'Le commentaire ne peut pas être vide.');
      return null;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('🔴 No valid token for posting comment',
          name: 'FavoritesPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return null;
    }

    final uri =
    Uri.parse('https://www.unistudious.com/api/social-media-set-comment');
    try {
      developer.log(
          '🔵 Sending POST request to post comment: $uri, postId: $postId',
          name: 'FavoritesPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId
        ..fields['comment'] = commentText;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      developer.log(
          '🔵 Comment API response: $responseBody, status: ${response.statusCode}',
          name: 'FavoritesPage');

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('🟢 Comment posted successfully', name: 'FavoritesPage');
        final commentData = responseData['data'];
        final account = commentData['account'];
        String username = 'Unknown User';
        String userId = '';
        if (account != null) {
          developer.log('🔵 Account data: $account', name: 'FavoritesPage');
          username = account['display_name']?.toString().trim().isNotEmpty ??
              false
              ? account['display_name']
              : account['username']?.toString() ?? 'Unknown User';
          userId = account['id']?.toString() ?? '';
          if (userId.isEmpty && account['username'] != null) {
            userId = await _fetchUserIdByUsername(account['username']) ?? '';
          }
        } else {
          developer.log('⚠️ Warning: commentData.account is null',
              name: 'FavoritesPage');
        }

        String profileUrl = account?['avatar'] ?? '';
        String text = _stripHtml(commentData['content'] ?? '');
        String timeAgo = _timeAgo(DateTime.parse(
            commentData['created_at'] ?? DateTime.now().toIso8601String()));

        setState(() {
          final postIndex = posts.indexWhere((post) => post['id'] == postId);
          if (postIndex != -1) {
            final newComment = {
              "id": commentData['id'] ?? '',
              "username": username,
              "userId": userId,
              "text": text,
              "timeAgo": timeAgo,
              "profileUrl": profileUrl,
            };
            posts[postIndex]['comments'].add(newComment);
            posts[postIndex]['commentCount'] = posts[postIndex]['comments'].length;
            developer.log(
                '🔵 Added new comment, new count: ${posts[postIndex]['commentCount']}',
                name: 'FavoritesPage');
          }
        });

        SnackBarHelper.showSuccess(context, 'Commentaire publié avec succès !');

        return {
          "id": commentData['id'] ?? '',
          "username": username,
          "userId": userId,
          "text": text,
          "timeAgo": timeAgo,
          "profileUrl": profileUrl,
        };
      } else {
        developer.log(
            '🔴 Failed to post comment: ${response.statusCode}, response: $responseBody',
            name: 'FavoritesPage');
        SnackBarHelper.showError(context, 'Échec de la publication du commentaire : ${responseData['message'] ?? 'Erreur inconnue'}');
        return null;
      }
    } catch (e, stackTrace) {
      developer.log('🔴 Error posting comment: $e',
          name: 'FavoritesPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de la publication du commentaire : $e');
      return null;
    }
  }

  Future<void> _votePoll(String pollId, int optionIndex) async {
    developer.log(
        '🔵 _votePoll called for pollId: $pollId, optionIndex: $optionIndex',
        name: 'FavoritesPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('🔴 No valid token for voting poll', name: 'FavoritesPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['poll']?['id'] == pollId);
    developer.log('🔵 Post index for poll $pollId: $postIndex',
        name: 'FavoritesPage');
    if (postIndex == -1) {
      developer.log('🔴 Poll not found: $pollId', name: 'FavoritesPage');
      SnackBarHelper.showError(context, 'Sondage introuvable.');
      return;
    }

    final poll = posts[postIndex]['poll'];
    if (poll['voted'] && !poll['multiple']) {
      developer.log(
          '🔴 User has already voted and multiple votes not allowed: $pollId',
          name: 'FavoritesPage');
      SnackBarHelper.showWarning(context, 'Vous avez déjà voté.');
      return;
    }

    final uri =
    Uri.parse('https://www.unistudious.com/api/social-media-vote-poll');
    try {
      developer.log(
          '🔵 Sending POST request to vote on poll: $uri, pollId: $pollId, optionIndex: $optionIndex',
          name: 'FavoritesPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['poll_id'] = pollId
        ..fields['option_index'] = optionIndex.toString();

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      developer.log(
          '🔵 Vote poll response: $responseBody, status: ${response.statusCode}',
          name: 'FavoritesPage');

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('🟢 Poll vote submitted successfully',
            name: 'FavoritesPage');
        setState(() {
          posts[postIndex]['poll'] = responseData['data'];
        });
        SnackBarHelper.showSuccess(context, 'Vote enregistré !');
      } else {
        developer.log(
            '🔴 Failed to vote on poll: ${response.statusCode}, response: $responseBody',
            name: 'FavoritesPage');
        SnackBarHelper.showError(context, 'Échec du vote : ${responseData['message'] ?? 'Erreur inconnue'}');
      }
    } catch (e, stackTrace) {
      developer.log('🔴 Error voting on poll: $e',
          name: 'FavoritesPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors du vote : $e');
    }
  }

  Future<void> _handleReaction(
      String postId, String? reaction, String userId) async {
    developer.log(
        '🔵 _handleReaction called for postId: $postId, reaction: $reaction, userId: $userId',
        name: 'FavoritesPage');
    // Log the user's reaction
    developer.log('🟢 User reaction: $reaction for userId: $userId on post: $postId',
        name: 'FavoritesPage');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('🔴 No valid token for setting reaction',
          name: 'FavoritesPage');
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['id'] == postId);
    developer.log('🔵 Post index for reaction $postId: $postIndex',
        name: 'FavoritesPage');
    if (postIndex == -1) {
      developer.log('🔴 Post not found for reaction: $postId',
          name: 'FavoritesPage');
      SnackBarHelper.showError(context, 'Post introuvable.');
      return;
    }

    Map<String, int> currentByEmoji = Map<String, int>.from(
      (posts[postIndex]['apiReactions']['byEmoji'] is Map)
          ? Map<String, dynamic>.from(posts[postIndex]['apiReactions']['byEmoji'])
          .map((key, value) => MapEntry(key, value as int))
          : {},
    );
    developer.log('🔵 Current byEmoji: $currentByEmoji', name: 'FavoritesPage');

    try {
      if (reaction == null) {
        developer.log('🔵 Deleting reaction for post: $postId',
            name: 'FavoritesPage');
        final uri = Uri.parse(
            'https://www.unistudious.com/api/social-media-delete-reaction/$postId');
        final response = await http.delete(
          uri,
          headers: {
            'Authorization': 'Bearer ${authProvider.currentToken}',
            'Content-Type': 'application/json',
          },
        );

        developer.log('🔵 Delete reaction response status: ${response.statusCode}',
            name: 'FavoritesPage');

        if (response.statusCode == 200) {
          setState(() {
            Map<String, String> userReactions = Map<String, String>.from(
                posts[postIndex]['userReactions'] as Map? ?? {});
            List<Map<String, dynamic>> reactions =
            List<Map<String, dynamic>>.from(
                posts[postIndex]['reactions'] as List? ?? []);

            final previousReaction = userReactions[userId];
            userReactions.remove(userId);
            reactions.removeWhere((r) => r['user']['id'] == userId);
            posts[postIndex]['likes'] = (posts[postIndex]['likes'] ?? 1) - 1;

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
            developer.log(
                '🟢 Reaction deleted, new total: ${posts[postIndex]['apiReactions']['total']}',
                name: 'FavoritesPage');
          });
        } else {
          developer.log('🔴 Failed to delete reaction: ${response.statusCode}',
              name: 'FavoritesPage');
          SnackBarHelper.showError(context, 'Échec de la suppression de la réaction');
        }
      } else {
        developer.log('🔵 Setting reaction $reaction for post: $postId',
            name: 'FavoritesPage');
        final uri = Uri.parse(
            'https://www.unistudious.com/api/social-media-set-reaction');
        var request = http.MultipartRequest('POST', uri)
          ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
          ..fields['id'] = postId
          ..fields['emoji'] = reaction;

        final response = await request.send();
        final responseBody = await response.stream.bytesToString();
        developer.log(
            '🔵 Set reaction response: $responseBody, status: ${response.statusCode}',
            name: 'FavoritesPage');

        if (response.statusCode == 200) {
          setState(() {
            Map<String, String> userReactions = Map<String, String>.from(
                posts[postIndex]['userReactions'] as Map? ?? {});
            List<Map<String, dynamic>> reactions =
            List<Map<String, dynamic>>.from(
                posts[postIndex]['reactions'] as List? ?? []);

            if (userReactions.containsKey(userId)) {
              final previousReaction = userReactions[userId];
              userReactions[userId] = reaction;

              final reactionIndex =
              reactions.indexWhere((r) => r['user']['id'] == userId);
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

              currentByEmoji[reaction] = (currentByEmoji[reaction] ?? 0) + 1;
            } else {
              userReactions[userId] = reaction;
              reactions.add({
                'emoji': reaction,
                'user': {'id': userId, 'username': 'current_user'}
              });
              posts[postIndex]['likes'] = (posts[postIndex]['likes'] ?? 0) + 1;
              currentByEmoji[reaction] = (currentByEmoji[reaction] ?? 0) + 1;
            }

            posts[postIndex]['apiReactions']['byEmoji'] = currentByEmoji;
            posts[postIndex]['apiReactions']['total'] =
                currentByEmoji.values.fold(0, (a, b) => a + b);
            posts[postIndex]['userReactions'] = userReactions;
            posts[postIndex]['reactions'] = reactions;
            developer.log(
                '🟢 Reaction set, new total: ${posts[postIndex]['apiReactions']['total']}',
                name: 'FavoritesPage');
          });
        } else {
          developer.log('🔴 Failed to set reaction: ${response.statusCode}',
              name: 'FavoritesPage');
          SnackBarHelper.showError(context, 'Échec de la mise à jour de la réaction');
        }
      }
    } catch (e, stackTrace) {
      developer.log('🔴 Error handling reaction: $e',
          name: 'FavoritesPage', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors de la mise à jour de la réaction : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    developer.log(
        '🔵 Building FavoritesPage, isLoading: $isLoading, posts.length: ${posts.length}, error: $errorMessage',
        name: 'FavoritesPage');
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Favoris',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ) ??
              const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
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
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
          : errorMessage != null
          ? Center(
        child: Text(
          errorMessage!,
          style: theme.textTheme.bodyLarge,
        ),
      )
          : posts.isEmpty
          ? Center(
        child: Text(
          'Aucun favori pour le moment',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.textTheme.bodyLarge?.color ??
                Colors.grey,
          ) ??
              TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
        ),
      )
          : RefreshIndicator(
        onRefresh: () async {
          developer.log(
              '🔵 RefreshIndicator onRefresh called',
              name: 'FavoritesPage');
          await _fetchFavoritePosts(page: 1);
        },
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(10),
          itemCount: posts.length + (isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            developer.log(
                '🔵 ListView itemBuilder index: $index, total items: ${posts.length + (isLoadingMore ? 1 : 0)}',
                name: 'FavoritesPage');
            if (index == posts.length && isLoadingMore) {
              developer.log(
                  '🔵 Rendering loading more indicator',
                  name: 'FavoritesPage');
              return Center(
                  child: CircularProgressIndicator(
                      color: theme.primaryColor));
            }
            final post = posts[index];
            developer.log(
                '🔵 Building post card for id: ${post["id"]}, username: ${post["username"]}',
                name: 'FavoritesPage');
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
              currentUserId: _currentUserId,
              currentReaction: post["userReaction"],
              reactions: post["reactions"],
              apiReactions: post["apiReactions"],
            );
          },
        ),
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
  }) {
    final theme = Theme.of(context);
    developer.log('🔵 _buildPostCard called for id: $id', name: 'FavoritesPage');
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: theme.cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: NetworkImage(profileUrl),
              radius: 22,
            ),
            title: GestureDetector(
              onTap: () async {
                developer.log('🔵 Username tapped: $username, userId: $userId',
                    name: 'FavoritesPage');
                final profileDetails = await _fetchProfileDetails(userId);
                if (profileDetails != null) {
                  developer.log(
                      '🟢 Navigating to UserPostsPage for user: $userId',
                      name: 'FavoritesPage');
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
                  developer.log(
                      '🔴 Failed to fetch profile details for navigation',
                      name: 'FavoritesPage');
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
                      color: Colors.black,
                    ),
              ),
            ),
            subtitle: Text(
              timeAgo,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: GoogleFonts.poppins().fontFamily,
              ) ??
                  TextStyle(
                    fontFamily: GoogleFonts.poppins().fontFamily,
                  ),
            ),
            trailing: IconButton(
              icon: Icon(Icons.more_horiz, color: theme.iconTheme.color),
              onPressed: () {
                developer.log('🔵 More options tapped for post: $id',
                    name: 'FavoritesPage');
                developer.log(
                  '🔵 Checking post ownership: userId=$userId, targetUserId=$targetUserId, '
                      'username=$username, finalUsername=$finalUsername, currentUserId=$currentUserId',
                  name: 'FavoritesPage._buildPostCard',
                );
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  backgroundColor: theme.dialogBackgroundColor,
                  builder: (bottomSheetContext) => Container(
                    padding: const EdgeInsets.all(16),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          leading: Icon(Icons.person,
                              color: theme.iconTheme.color),
                          title: Text(
                            'Voir le profil',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ) ??
                                TextStyle(
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                  fontSize: 16,
                                ),
                          ),
                          onTap: () async {
                            developer.log(
                                '🔵 View Profile tapped for post: $id',
                                name: 'FavoritesPage');
                            Navigator.pop(bottomSheetContext);
                            final profileDetails =
                            await _fetchProfileDetails(userId);
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
                        ListTile(
                          leading: Icon(
                            favourited ? Icons.favorite : Icons.favorite_border,
                            color: Colors.red,
                          ),
                          title: Text(
                            favourited
                                ? 'Retirer des favoris'
                                : 'Ajouter aux favoris',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ) ??
                                TextStyle(
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                  fontSize: 16,
                                ),
                          ),
                          onTap: () {
                            developer.log(
                              '${favourited ? 'Mark as Not Favorite' : 'Mark as Favorite'} tapped for post: $id',
                              name: 'FavoritesPage',
                            );
                            Navigator.pop(bottomSheetContext);
                            if (favourited) {
                              _markAsNotFavorite(id);
                            } else {
                              _markAsFavorite(id);
                            }
                          },
                        ),
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
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ) ??
                    TextStyle(
                      fontSize: 15,
                      fontFamily: GoogleFonts.poppins().fontFamily,
                    ),
              ),
            ),
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(imageUrl,
                  fit: BoxFit.cover, width: double.infinity),
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
                    developer.log('🔵 Reactions tapped for post: $id',
                        name: 'FavoritesPage');
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      backgroundColor: theme.dialogBackgroundColor,
                      builder: (_) => ReactionSheet(apiReactions: apiReactions),
                    );
                  },
                  child: Row(
                    children: [
                      if (apiReactions["total"] > 0) ...[
                        ...() {
                          Map<String, int> emojiCount =
                          Map<String, int>.from(apiReactions["byEmoji"]);
                          var sortedEmojis = emojiCount.entries.toList()
                            ..sort((a, b) => b.value.compareTo(a.value));
                          List<String> topEmojis =
                          sortedEmojis.take(2).map((e) => e.key).toList();
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily:
                                GoogleFonts.poppins().fontFamily,
                                color: theme.textTheme.bodySmall?.color ??
                                    Colors.grey[600],
                              ) ??
                                  TextStyle(
                                    fontFamily: GoogleFonts.poppins().fontFamily,
                                    color: Colors.grey[600],
                                  ),
                            ),
                          ];
                        }(),
                      ] else ...[
                        Icon(Icons.emoji_emotions_outlined,
                            color: theme.iconTheme.color, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          "0",
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                            color: theme.textTheme.bodySmall?.color ??
                                Colors.grey[600],
                          ) ??
                              TextStyle(
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
                    developer.log('🔵 Comment count tapped for post: $id',
                        name: 'FavoritesPage');
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      backgroundColor: theme.dialogBackgroundColor,
                      builder: (_) => CommentSheet(
                        postId: id,
                        comments: commentList,
                        onCommentPosted: _postComment,
                        fetchComments: _fetchComments,
                        onDeleteComment: _deleteComment,
                        currentUserId: targetUserId,
                      ),
                    );
                  },
                  child: Text(
                    "$comments commentaires • $shares partages",
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: GoogleFonts.poppins().fontFamily,
                      color: theme.textTheme.bodySmall?.color ??
                          Colors.grey[700],
                    ) ??
                        TextStyle(
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
                  developer.log('🔵 Comment button pressed for post: $id',
                      name: 'FavoritesPage');
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    backgroundColor: theme.dialogBackgroundColor,
                    builder: (_) => CommentSheet(
                      postId: id,
                      comments: commentList,
                      onCommentPosted: _postComment,
                      fetchComments: _fetchComments,
                      onDeleteComment: _deleteComment,
                      currentUserId: targetUserId,
                    ),
                  );
                }, color: theme.iconTheme.color),
                _buildActionButton(Icons.share_outlined, "Partager", () {
                  developer.log('🔵 Share button pressed for post: $id',
                      name: 'FavoritesPage');
                }, color: theme.iconTheme.color),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPollWidget(dynamic poll, String postId) {
    final theme = Theme.of(context);
    developer.log('🔵 _buildPollWidget called for postId: $postId',
        name: 'FavoritesPage');
    bool hasVoted = poll['voted'] ?? false;
    List<dynamic> options = poll['options'] ?? [];
    int totalVotes = poll['votes_count'] ?? 0;
    developer.log(
        '🔵 Building poll widget, hasVoted: $hasVoted, options: ${options.length}, totalVotes: $totalVotes',
        name: 'FavoritesPage');
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
        developer.log(
        '🔵 Poll option tapped: $title, index: $index',
        name: 'FavoritesPage');
        _votePoll(poll['id'], index);
        },
        child: Container(
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
        color: hasVoted && poll['own_votes'].contains(index)
        ? Colors.deepPurple.withOpacity(0.2)
            : theme.dividerColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
        color: hasVoted && poll['own_votes'].contains(index)
        ? Colors.deepPurple
            : theme.dividerColor,
        width: 1,
        ),
        ),
        child: Row(
        children: [
        Expanded(
        child: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
        fontFamily: GoogleFonts.poppins().fontFamily,
        color: theme.textTheme.bodyMedium?.color ??
        Colors.grey[800],
        ) ??
        TextStyle(
        fontSize: 14,
        color: Colors.grey[800],
        fontFamily: GoogleFonts.poppins().fontFamily,
        ),
        ),
        ),
        Text(
        '${percentage.toStringAsFixed(1)}% ($votes)',
        style: theme.textTheme.bodySmall?.copyWith(
        fontFamily: GoogleFonts.poppins().fontFamily,
        color: theme.textTheme.bodySmall?.color ??
        Colors.grey[600],
        ) ??
        TextStyle(
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

  Widget _buildActionButton(
      IconData icon, String label, VoidCallback onTap, {Color? color}) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? theme.iconTheme.color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: GoogleFonts.poppins().fontFamily,
              color: color ?? theme.textTheme.bodyMedium?.color,
            ) ??
                TextStyle(
                  color: color ?? Colors.grey[700],
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    developer.log('🔵 FavoritesPage dispose called', name: 'FavoritesPage');
    _scrollController.dispose();
    super.dispose();
  }
}

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
    developer.log('🔵 ReactionButton init with ${widget.userReaction}',
        name: 'ReactionButton');
  }

  @override
  void didUpdateWidget(covariant ReactionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userReaction != widget.userReaction) {
      developer.log('🟢 ReactionButton updated: ${widget.userReaction}',
          name: 'ReactionButton');
      setState(() {
        _selectedReaction = widget.userReaction;
      });
    }
  }

  void _showReactions(BuildContext context) {
    final theme = Theme.of(context);
    developer.log('🔵 _showReactions called', name: 'ReactionButton');
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
                    color: theme.dialogBackgroundColor,
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: [
                      BoxShadow(
                          color: theme.shadowColor.withOpacity(0.2),
                          blurRadius: 6,
                          spreadRadius: 2),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: reactions.map((emoji) {
                      return GestureDetector(
                        onTap: () {
                          developer.log(
                              '🔵 Reaction emoji selected: $emoji',
                              name: 'ReactionButton');
                          setState(() {
                            _selectedReaction = emoji;
                          });
                          widget.onReactionSelected(
                              widget.postId, emoji, widget.currentUserId);
                          _removeOverlay();
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(emoji, style: const TextStyle(fontSize: 26)),
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
  }

  void _removeOverlay() {
    developer.log('🔵 _removeOverlay called', name: 'ReactionButton');
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    developer.log('🔵 ReactionButton build, selected: $_selectedReaction',
        name: 'ReactionButton');
    return GestureDetector(
        onLongPress: () => _showReactions(context),
        onTap: () {
          developer.log(
              '🔵 ReactionButton tap, current selected: $_selectedReaction',
              name: 'ReactionButton');
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
              Icon(Icons.thumb_up_alt_outlined,
                  size: 20, color: theme.iconTheme.color),
              const SizedBox(width: 6),
            ] else ...[
            Text(_selectedReaction!, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 6),
        ],
    Text(
    _selectedReaction != null
    ? reactionLabels[_selectedReaction] ?? "Réagir"
        : "Réagir",
        style: theme.textTheme.bodyMedium?.copyWith(
        fontFamily: GoogleFonts.poppins().fontFamily,
    color: _selectedReaction != null
    ? theme.textTheme.bodyMedium?.color
        : theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
    ) ??
    TextStyle(
    fontFamily: GoogleFonts.poppins().fontFamily,
    fontSize: 14,
    color: _selectedReaction != null
    ? Colors.black
        : Colors.grey[700],
    ),
    ),
    ],
    ),
    );
  }

  @override
  void dispose() {
    developer.log('🔵 ReactionButton dispose', name: 'ReactionButton');
    _removeOverlay();
    super.dispose();
  }
}

class ReactionSheet extends StatelessWidget {
  final Map<String, dynamic> apiReactions;

  const ReactionSheet({super.key, required this.apiReactions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    developer.log('🔵 ReactionSheet build, apiReactions: $apiReactions',
        name: 'ReactionSheet');
    final Map<String, dynamic> byEmoji = apiReactions['byEmoji'] ?? {};
    final int totalReactions = apiReactions['total'] ?? 0;

    final List<MapEntry<String, dynamic>> emojiList = byEmoji.entries.toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.dialogBackgroundColor,
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
                style: TextStyle(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (emojiList.isEmpty && totalReactions == 0)
            const Center(
              child: Text(
                'Aucune réaction pour le moment.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
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
                      style: TextStyle(
                        fontFamily: GoogleFonts.poppins().fontFamily,
                        fontSize: 16,
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

class CommentSheet extends StatefulWidget {
  final String postId;
  final List<Map<String, dynamic>> comments;
  final Future<Map<String, dynamic>?> Function(String, String) onCommentPosted;
  final Future<List<Map<String, dynamic>>> Function(String) fetchComments;
  final void Function(String, String) onDeleteComment;
  final String? currentUserId;

  const CommentSheet({
    super.key,
    required this.postId,
    required this.comments,
    required this.onCommentPosted,
    required this.fetchComments,
    required this.onDeleteComment,
    this.currentUserId,
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
    developer.log('🔵 CommentSheet initState for postId: ${widget.postId}, initial comments: ${widget.comments.length}', name: 'CommentSheet');
    _comments = List.from(widget.comments);
    for (var comment in _comments) {
      _commentKeys[comment['id']] = GlobalKey();
    }
    _fetchComments();
  }

  Future<void> _fetchComments() async {
    developer.log('🔵 _fetchComments in CommentSheet for postId: ${widget.postId}', name: 'CommentSheet');
    setState(() {
      _isLoadingComments = true;
    });
    try {
      final comments = await widget.fetchComments(widget.postId);
      developer.log('🟢 Fetched ${comments.length} comments in CommentSheet', name: 'CommentSheet');
      setState(() {
        _comments = comments;
        _isLoadingComments = false;
        _commentKeys.removeWhere((id, key) => !comments.any((c) => c['id'] == id));
        for (var comment in comments) {
          _commentKeys.putIfAbsent(comment['id'], () => GlobalKey());
        }
      });
    } catch (e, stackTrace) {
      developer.log('🔴 Error fetching comments in CommentSheet: $e', name: 'CommentSheet', error: e, stackTrace: stackTrace);
      SnackBarHelper.showError(context, 'Erreur lors du chargement des commentaires : $e');
      setState(() {
        _isLoadingComments = false;
      });
    }
  }

  Future<void> _handleCommentPosted(String postId, String commentText) async {
    developer.log('🔵 _handleCommentPosted in CommentSheet for postId: $postId', name: 'CommentSheet');
    final newComment = await widget.onCommentPosted(postId, commentText);
    if (newComment != null) {
      setState(() {
        _comments.add(newComment);
        _commentKeys[newComment['id']] = GlobalKey();
        developer.log('🟢 Added new comment to sheet, total: ${_comments.length}', name: 'CommentSheet');
      });
      await _fetchComments();
    }
  }

  void _handleDeleteComment(String commentId) {
    developer.log('🔵 _handleDeleteComment in CommentSheet for commentId: $commentId', name: 'CommentSheet');
    widget.onDeleteComment(commentId, widget.postId);
    setState(() {
      _comments.removeWhere((c) => c['id'] == commentId);
      _commentKeys.remove(commentId);
      _selectedCommentId = null;
      developer.log('🟢 Removed comment from sheet, total: ${_comments.length}', name: 'CommentSheet');
    });
    _fetchComments();
  }

  void _showCommentMenu(BuildContext context, Offset tapPosition, String commentId) async {
    developer.log('🔵 _showCommentMenu called for commentId: $commentId', name: 'CommentSheet');
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
      developer.log('🟢 Delete selected for comment: $commentId', name: 'CommentSheet');
      _handleDeleteComment(commentId);
    } else {
      // Si l'utilisateur ferme le menu sans rien choisir -> enlever la sélection
      setState(() {
        _selectedCommentId = null;
      });
      developer.log('🔵 Menu closed without selection', name: 'CommentSheet');
    }
  }

  @override
  Widget build(BuildContext context) {
    developer.log('🔵 CommentSheet build, comments.length: ${_comments.length}, isLoading: $_isLoadingComments', name: 'CommentSheet');
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
                  final isSelected = _selectedCommentId == comment['id'];

                  developer.log(
                    '🔵 Building comment item $index: ${comment['username']} - ${comment['text'].substring(0, comment['text'].length > 50 ? 50 : comment['text'].length)}...',
                    name: 'CommentSheet',
                  );

                  return Builder(
                    builder: (BuildContext context) {
                      try {
                        return GestureDetector(
                          key: _commentKeys[comment['id']],
                          onTapDown: (details) {
                            _tapPosition = details.globalPosition;
                          },
                          onLongPress: () {
                            developer.log('🔵 Long press on comment: ${comment['id']}, own: $isOwnComment', name: 'CommentSheet');
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
                      } catch (e, stackTrace) {
                        developer.log('🔴 Error rendering comment item $index: $e', name: 'CommentSheet', error: e, stackTrace: stackTrace);
                        return const ListTile(
                          title: Text('Erreur lors de l\'affichage du commentaire'),
                          subtitle: Text('Veuillez réessayer plus tard.'),
                        );
                      }
                    },
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
                    decoration: InputDecoration(
                      hintText: 'Écrire un commentaire...',
                      hintStyle: TextStyle(
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    style: TextStyle(
                      fontFamily: GoogleFonts.poppins().fontFamily,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.deepPurple, size: 28),
                  onPressed: () {
                    developer.log('🔵 Send comment button pressed, text: ${_commentController.text}', name: 'CommentSheet');
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
    developer.log('🔵 CommentSheet dispose', name: 'CommentSheet');
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}