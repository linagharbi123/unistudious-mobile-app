import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'content_moderation_page.dart';
import '../utils/snackbar_helper.dart';

class UserPostsPage extends StatefulWidget {
  final String userId;
  final String username;
  final Map<String, dynamic>? profileDetails;

  const UserPostsPage({
    super.key,
    required this.userId,
    required this.username,
    this.profileDetails,
  });

  @override
  _UserPostsPageState createState() => _UserPostsPageState();
}

class _UserPostsPageState extends State<UserPostsPage> {
  List<Map<String, dynamic>> posts = [];
  bool isLoading = true;
  String? errorMessage;
  final String _currentUserId = "current_user"; // Replace with actual user ID logic
  String? targetUserId;

  @override
  void initState() {
    super.initState();
    developer.log('Initializing UserPostsPage for userId: ${widget.userId}', name: 'UserPostsPage');
    targetUserId = widget.userId;
    _fetchUserPosts();
  }

  Future<String?> _fetchUserIdByUsername(String username) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for fetching user ID', name: 'UserPostsPage');
      return null;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-get-userid-by-username');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['username'] = username;

      developer.log('Fetching user ID for username: $username', name: 'UserPostsPage');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      developer.log('User ID API response: $responseBody, status: ${response.statusCode}', name: 'UserPostsPage');

      final responseData = jsonDecode(responseBody);
      if (response.statusCode == 200 && responseData['status'] == 'success') {
        return responseData['id']?.toString();
      } else {
        developer.log(
          'Failed to fetch user ID: ${response.statusCode}, response: $responseBody',
          name: 'UserPostsPage',
        );
        return null;
      }
    } catch (e, stackTrace) {
      developer.log('Error fetching user ID: $e', name: 'UserPostsPage', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> _fetchUserPosts() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      setState(() {
        errorMessage = 'Session expirée. Veuillez vous reconnecter.';
        isLoading = false;
      });
      developer.log('No valid token available', name: 'UserPostsPage');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/profile-details-social-media/${widget.userId}');
    try {
      developer.log('Fetching posts for user: ${widget.userId}', name: 'UserPostsPage');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${authProvider.currentToken}',
          'Content-Type': 'application/json',
        },
      );

      developer.log('User posts API response: ${response.body}, status: ${response.statusCode}', name: 'UserPostsPage');
      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['data'] != null) {
        final List<dynamic> statuses = responseData['data']['statuses'] ?? [];
        final mappedPosts = <Map<String, dynamic>>[];
        for (var status in statuses) {
          final statusData = status['status'];
          String text = _stripHtml(statusData['content'] ?? '');
          String imageUrl = statusData['media_attachments']?.isNotEmpty ?? false
              ? statusData['media_attachments'][0]['url']?.toString() ?? ''
              : '';
          String timeAgo = _timeAgo(DateTime.parse(statusData['created_at'] ?? DateTime.now().toIso8601String()));
          final postId = statusData['id']?.toString() ?? '';
          final commentList = await _fetchComments(postId);
          final userReaction = status['userReaction']?.toString();
          dynamic rawReactions = status['reactions'];
          Map<String, dynamic> reactions;
          if (rawReactions is List<dynamic>) {
            Map<String, int> byEmoji = {};
            for (var reaction in rawReactions) {
              String emoji;
              if (reaction is String) {
                emoji = reaction;
              } else if (reaction is Map<dynamic, dynamic>) {
                emoji = reaction['emoji'] ?? reaction['name'] ?? '?';
              } else {
                continue;
              }
              byEmoji[emoji] = (byEmoji[emoji] ?? 0) + 1;
            }
            reactions = {
              'total': rawReactions.length,
              'byEmoji': byEmoji,
            };
          } else if (rawReactions is Map<String, dynamic>) {
            dynamic byEmojiRaw = rawReactions['byEmoji'];
            if (byEmojiRaw is List<dynamic>) {
              Map<String, int> byEmoji = {};
              for (var item in byEmojiRaw) {
                if (item is Map<dynamic, dynamic>) {
                  String emoji = item['name'] ?? item['emoji'] ?? '?';
                  int count = int.tryParse(item['count']?.toString() ?? '0') ?? 0;
                  if (count > 0) {
                    byEmoji[emoji] = count;
                  }
                }
              }
              reactions = {
                'total': byEmoji.values.fold<int>(0, (sum, c) => sum + c),
                'byEmoji': byEmoji,
              };
            } else {
              reactions = rawReactions;
            }
          } else {
            reactions = {'total': 0, 'byEmoji': {}};
          }

          mappedPosts.add({
            'id': postId,
            'text': text,
            'imageUrl': imageUrl,
            'timeAgo': timeAgo,
            'likes': statusData['favourites_count'] ?? 0,
            'comments': commentList,
            'commentCount': commentList.length,
            'shares': statusData['reblogs_count'] ?? 0,
            'favourited': statusData['favourited'] ?? false,
            'pinned': statusData['pinned'] ?? false,
            'poll': statusData['poll'],
            'userReaction': userReaction,
            'apiReactions': reactions,
          });
        }

        setState(() {
          posts = mappedPosts;
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Échec du chargement des publications : ${responseData['message'] ?? 'Erreur inconnue'}';
          isLoading = false;
        });
        developer.log(
          'Failed to fetch user posts: ${response.statusCode}, response: ${response.body}',
          name: 'UserPostsPage',
        );
      }
    } catch (e, stackTrace) {
      setState(() {
        errorMessage = 'Erreur lors du chargement des publications : $e';
        isLoading = false;
      });
      developer.log('Error fetching user posts: $e', name: 'UserPostsPage', error: e, stackTrace: stackTrace);
    }
  }

  Future<Map<String, dynamic>?> _fetchProfileDetails(String userId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for fetching profile details',
          name: 'UserPostsPage');
      return null;
    }

    final uri = Uri.parse(
        'https://www.unistudious.com/api/profile-details-social-media/$userId');
    try {
      developer.log('Fetching profile details for userId: $userId',
          name: 'UserPostsPage');
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${authProvider.currentToken}',
          'Content-Type': 'application/json',
        },
      );

      developer.log(
          'Profile details API response: ${response.body}, status: ${response.statusCode}',
          name: 'UserPostsPage');
      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['data'] != null) {
        return responseData['data'];
      } else {
        developer.log(
          'Failed to fetch profile details: ${response.statusCode}, response: ${response.body}',
          name: 'UserPostsPage',
        );
        return null;
      }
    } catch (e, stackTrace) {
      developer.log('Error fetching profile details: $e',
          name: 'UserPostsPage', error: e, stackTrace: stackTrace);
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
        name: 'UserPostsPage',
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
      developer.log('Error reporting status: $e', name: 'UserPostsPage');
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors du signalement : $e');
      }
    } finally {
      commentController.dispose();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchComments(String postId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      final uri = Uri.parse('https://www.unistudious.com/api/social-media-get-comment');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      developer.log('Fetching comments for post: $postId', name: 'SocialFeedPage');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      developer.log('Comment API response: $responseBody, status: ${response.statusCode}', name: 'SocialFeedPage');

      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        final List<dynamic> comments = responseData['data'] ?? [];
        developer.log('Number of comments received: ${comments.length}', name: 'SocialFeedPage');

        return comments.map((comment) {
          final account = comment['account'];
          String username = 'Unknown User';
          String userId = '';
          if (account != null) {
            username = account['display_name']?.toString().trim().isNotEmpty ?? false
                ? account['display_name']
                : account['username']?.toString() ?? 'Unknown User';
            userId = account['id']?.toString() ?? '';
          }
          String text = _stripHtml(comment['content'] ?? '');
          String timeAgo = _timeAgo(DateTime.parse(comment['created_at'] ?? DateTime.now().toIso8601String()));
          String profileUrl = comment['account']?['avatar'] ?? '';

          return {
            'id': comment['id'] ?? '',
            'username': username,
            'userId': userId,
            'text': text,
            'timeAgo': timeAgo,
            'profileUrl': profileUrl,
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
      developer.log('Error fetching comments: $e', name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  Future<void> _handleReaction(String postId, String? reaction) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for setting reaction', name: 'SocialFeedPage');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.')),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['id'] == postId);
    if (postIndex == -1) {
      developer.log('Post not found: $postId', name: 'SocialFeedPage');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post introuvable.')),
      );
      return;
    }

    Map<String, int> currentByEmoji = Map<String, int>.from(posts[postIndex]['apiReactions']['byEmoji'] ?? {});

    try {
      if (reaction == null) {
        final uri = Uri.parse('https://www.unistudious.com/api/social-media-delete-reaction/$postId');
        final response = await http.delete(
          uri,
          headers: {
            'Authorization': 'Bearer ${authProvider.currentToken}',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          setState(() {
            final previousReaction = posts[postIndex]['userReaction'];
            if (previousReaction != null && currentByEmoji.containsKey(previousReaction)) {
              int count = currentByEmoji[previousReaction]! - 1;
              if (count <= 0) {
                currentByEmoji.remove(previousReaction);
              } else {
                currentByEmoji[previousReaction] = count;
              }
            }
            posts[postIndex]['apiReactions']['byEmoji'] = currentByEmoji;
            posts[postIndex]['apiReactions']['total'] = currentByEmoji.values.fold(0, (a, b) => a + b);
            posts[postIndex]['userReaction'] = null;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Échec de la suppression de la réaction')),
          );
        }
      } else {
        final uri = Uri.parse('https://www.unistudious.com/api/social-media-set-reaction');
        var request = http.MultipartRequest('POST', uri)
          ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
          ..fields['id'] = postId
          ..fields['emoji'] = reaction;

        final response = await request.send();
        final responseBody = await response.stream.bytesToString();

        if (response.statusCode == 200) {
          setState(() {
            final previousReaction = posts[postIndex]['userReaction'];
            if (previousReaction != null && currentByEmoji.containsKey(previousReaction)) {
              int count = currentByEmoji[previousReaction]! - 1;
              if (count <= 0) {
                currentByEmoji.remove(previousReaction);
              } else {
                currentByEmoji[previousReaction] = count;
              }
            }
            currentByEmoji[reaction] = (currentByEmoji[reaction] ?? 0) + 1;
            posts[postIndex]['apiReactions']['byEmoji'] = currentByEmoji;
            posts[postIndex]['apiReactions']['total'] = currentByEmoji.values.fold(0, (a, b) => a + b);
            posts[postIndex]['userReaction'] = reaction;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Échec de la mise à jour de la réaction')),
          );
        }
      }
    } catch (e, stackTrace) {
      developer.log('Error handling reaction: $e', name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la mise à jour de la réaction : $e')),
      );
    }
  }

  Future<Map<String, dynamic>?> _postComment(String postId, String commentText) async {
    if (commentText.isEmpty) {
      developer.log('Comment posting failed: comment is empty', name: 'SocialFeedPage');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le commentaire ne peut pas être vide.')),
      );
      return null;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for posting comment', name: 'SocialFeedPage');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.')),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return null;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-set-comment');
    try {
      developer.log('Sending POST request to post comment: $uri, postId: $postId', name: 'SocialFeedPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId
        ..fields['comment'] = commentText;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      developer.log('Comment API response: $responseBody, status: ${response.statusCode}', name: 'SocialFeedPage');

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Comment posted successfully: ${responseData['message']}', name: 'SocialFeedPage');
        final commentData = responseData['data'];
        final account = commentData['account'];
        String username = 'Unknown User';
        String userId = '';
        if (account != null) {
          username = account['display_name']?.toString().trim().isNotEmpty ?? false
              ? account['display_name']
              : account['username']?.toString() ?? 'Unknown User';
          userId = account['id']?.toString() ?? '';
          if (userId.isEmpty && account['username'] != null) {
            userId = await _fetchUserIdByUsername(account['username']) ?? '';
          }
        }
        String profileUrl = account?['avatar'] ?? '';
        String text = _stripHtml(commentData['content'] ?? '');
        String timeAgo = _timeAgo(DateTime.parse(commentData['created_at'] ?? DateTime.now().toIso8601String()));

        setState(() {
          final postIndex = posts.indexWhere((post) => post['id'] == postId);
          if (postIndex != -1) {
            final newComment = {
              'id': commentData['id'] ?? '',
              'username': username,
              'userId': userId,
              'text': text,
              'timeAgo': timeAgo,
              'profileUrl': profileUrl,
            };
            posts[postIndex]['comments'].add(newComment);
            posts[postIndex]['commentCount'] = posts[postIndex]['comments'].length;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Commentaire publié avec succès !'),
            backgroundColor: Colors.green,
          ),
        );

        return {
          'id': commentData['id'] ?? '',
          'username': username,
          'userId': userId,
          'text': text,
          'timeAgo': timeAgo,
          'profileUrl': profileUrl,
        };
      } else {
        developer.log(
          'Failed to post comment: ${response.statusCode}, response: $responseBody',
          name: 'SocialFeedPage',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Échec de la publication du commentaire : ${responseData['message'] ?? 'Erreur inconnue'}'),
          ),
        );
        return null;
      }
    } catch (e, stackTrace) {
      developer.log('Error posting comment: $e', name: 'SocialFeedPage', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la publication du commentaire : $e')),
      );
      return null;
    }
  }

  Future<void> _deleteComment(String commentId, String postId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for deleting comment', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.')),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-delete-comment');
    try {
      developer.log('Sending POST request to delete comment: $uri, commentId: $commentId', name: 'UserPostsPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['commentId'] = commentId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Comment deleted successfully: ${responseData['message']}', name: 'UserPostsPage');
        setState(() {
          final postIndex = posts.indexWhere((post) => post['id'] == postId);
          if (postIndex != -1) {
            posts[postIndex]['comments'].removeWhere((comment) => comment['id'] == commentId);
            posts[postIndex]['commentCount'] = posts[postIndex]['comments'].length;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Commentaire supprimé avec succès !'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        developer.log(
          'Failed to delete comment: ${response.statusCode}, response: $responseBody',
          name: 'UserPostsPage',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Échec de la suppression : ${responseData['message'] ?? 'Erreur inconnue'}'),
          ),
        );
      }
    } catch (e, stackTrace) {
      developer.log('Error deleting comment: $e', name: 'UserPostsPage', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression : $e')),
      );
    }
  }

  Future<void> _votePoll(String pollId, int optionIndex) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for voting', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['poll']?['id'] == pollId);
    if (postIndex == -1) {
      developer.log('Poll not found: $pollId', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sondage introuvable.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      return;
    }

    final poll = posts[postIndex]['poll'];
    if (poll['voted'] && !poll['multiple']) {
      developer.log('User has already voted and multiple votes not allowed: $pollId', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vous avez déjà voté.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-vote-poll');
    try {
      developer.log('Sending POST request to vote on poll: $uri, pollId: $pollId, optionIndex: $optionIndex', name: 'UserPostsPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['poll_id'] = pollId
        ..fields['option_index'] = optionIndex.toString();

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Poll vote submitted successfully: ${responseData['message']}', name: 'UserPostsPage');
        setState(() {
          posts[postIndex]['poll'] = responseData['data'];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Vote enregistré !', style: Theme.of(context).textTheme.bodyMedium),
            backgroundColor: Theme.of(context).primaryColor,
          ),
        );
      } else {
        developer.log(
          'Failed to vote on poll: ${response.statusCode}, response: $responseBody',
          name: 'UserPostsPage',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Échec du vote : ${responseData['message'] ?? 'Erreur inconnue'}',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        );
      }
    } catch (e, stackTrace) {
      developer.log('Error voting on poll: $e', name: 'UserPostsPage', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors du vote : $e', style: Theme.of(context).textTheme.bodyMedium)),
      );
    }
  }

  Future<void> _markAsFavorite(String postId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for marking favorite', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['id'] == postId);
    if (postIndex == -1) {
      developer.log('Post not found: $postId', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Post introuvable.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-mark-as-favorite');
    try {
      developer.log('Sending POST request to mark post as favorite: $uri, postId: $postId', name: 'UserPostsPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Post marked as favorite successfully: ${responseData['message']}', name: 'UserPostsPage');
        setState(() {
          posts[postIndex]['favourited'] = responseData['data']['favourited'];
          posts[postIndex]['likes'] = responseData['data']['favourites_count'];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(responseData['data']['favourited']
                ? 'Ajouté aux favoris !'
                : 'Retiré des favoris !', style: Theme.of(context).textTheme.bodyMedium),
            backgroundColor: Theme.of(context).primaryColor,
          ),
        );
      } else {
        developer.log(
          'Failed to mark post as favorite: ${response.statusCode}, response: $responseBody',
          name: 'UserPostsPage',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Échec de l\'opération : ${responseData['message'] ?? 'Erreur inconnue'}',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        );
      }
    } catch (e, stackTrace) {
      developer.log('Error marking post as favorite: $e', name: 'UserPostsPage', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'opération : $e', style: Theme.of(context).textTheme.bodyMedium)),
      );
    }
  }

  Future<void> _blockUser(String userId, String username) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session expirée. Veuillez vous reconnecter.', 
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final theme = Theme.of(context);
    // Confirm blocking action
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.brightness == Brightness.dark
            ? theme.cardColor
            : Colors.white,
        title: Text(
          'Bloquer $username ?',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.textTheme.bodyLarge?.color,
          ),
        ),
        content: Text(
          'Vous ne pourrez plus voir les messages, publications ou profils de cette personne. '
          'Ils ne pourront plus vous contacter non plus.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Annuler',
              style: theme.textTheme.labelLarge,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Bloquer',
              style: theme.textTheme.labelLarge?.copyWith(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final uri = Uri.parse('https://www.unistudious.com/api/block/account');
    try {
      developer.log('Blocking user: $userId via $uri', name: 'UserPostsPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['accountId'] = userId;

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body);

      if (response.statusCode == 200 && data['success'] == true && mounted) {
        SnackBarHelper.showSuccess(context, 'Utilisateur bloqué avec succès');
        Navigator.pop(context);
      } else {
        throw Exception(data['message'] ?? 'Erreur lors du blocage');
      }
    } catch (e) {
      developer.log('Error blocking user: $e', name: 'UserPostsPage');
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        'Erreur lors du blocage: ${e.toString()}',
      );
    }
  }

  Future<void> _markAsNotFavorite(String postId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for marking not favorite', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['id'] == postId);
    if (postIndex == -1) {
      developer.log('Post not found: $postId', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Post introuvable.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-mark-as-not-favorite');
    try {
      developer.log('Sending POST request to mark post as not favorite: $uri, postId: $postId', name: 'UserPostsPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Post marked as not favorite successfully: ${responseData['message']}', name: 'UserPostsPage');
        setState(() {
          posts[postIndex]['favourited'] = responseData['data']['favourited'];
          posts[postIndex]['likes'] = responseData['data']['favourites_count'];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Retiré des favoris !', style: Theme.of(context).textTheme.bodyMedium),
            backgroundColor: Theme.of(context).primaryColor,
          ),
        );
      } else {
        developer.log(
          'Failed to mark post as not favorite: ${response.statusCode}, response: $responseBody',
          name: 'UserPostsPage',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Échec de l\'opération : ${responseData['message'] ?? 'Erreur inconnue'}',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        );
      }
    } catch (e, stackTrace) {
      developer.log('Error marking post as not favorite: $e', name: 'UserPostsPage', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'opération : $e', style: Theme.of(context).textTheme.bodyMedium)),
      );
    }
  }

  Future<void> _deleteStatus(String statusId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for deletion', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-delete-status/$statusId');
    try {
      developer.log('Sending POST request to delete status: $uri', name: 'UserPostsPage');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${authProvider.currentToken}',
          'Content-Type': 'application/json',
        },
      );

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Status deleted successfully: ${responseData['message']}', name: 'UserPostsPage');
        setState(() {
          posts.removeWhere((post) => post['id'] == statusId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Statut supprimé avec succès !', style: Theme.of(context).textTheme.bodyMedium),
            backgroundColor: Theme.of(context).primaryColor,
          ),
        );
        await _fetchUserPosts();
      } else {
        developer.log(
          'Failed to delete status: ${response.statusCode}, response: ${response.body}',
          name: 'UserPostsPage',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Échec de la suppression : ${responseData['message'] ?? 'Erreur inconnue'}',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        );
      }
    } catch (e, stackTrace) {
      developer.log('Error deleting status: $e', name: 'UserPostsPage', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression : $e', style: Theme.of(context).textTheme.bodyMedium)),
      );
    }
  }

  Future<void> _pinToProfile(String postId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for pinning', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['id'] == postId);
    if (postIndex == -1) {
      developer.log('Post not found: $postId', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Post introuvable.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-pin-status');
    try {
      developer.log('Sending POST request to pin post: $uri, postId: $postId', name: 'UserPostsPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Post pinned successfully: ${responseData['message']}', name: 'UserPostsPage');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Épinglé au profil !', style: Theme.of(context).textTheme.bodyMedium),
            backgroundColor: Theme.of(context).primaryColor,
          ),
        );
        await _fetchUserPosts();
      } else {
        developer.log(
          'Failed to pin post: ${response.statusCode}, response: $responseBody',
          name: 'UserPostsPage',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Échec de l\'épinglage : ${responseData['message'] ?? 'Erreur inconnue'}',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        );
      }
    } catch (e, stackTrace) {
      developer.log('Error pinning post: $e', name: 'UserPostsPage', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'épinglage : $e', style: Theme.of(context).textTheme.bodyMedium)),
      );
    }
  }

  Future<void> _unpinFromProfile(String postId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available for unpinning', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final postIndex = posts.indexWhere((post) => post['id'] == postId);
    if (postIndex == -1) {
      developer.log('Post not found: $postId', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Post introuvable.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/social-media-unpin-status');
    try {
      developer.log('Sending POST request to unpin post: $uri, postId: $postId', name: 'UserPostsPage');
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['id'] = postId;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log('Post unpinned successfully: ${responseData['message']}', name: 'UserPostsPage');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Désépinglé du profil !', style: Theme.of(context).textTheme.bodyMedium),
            backgroundColor: Theme.of(context).primaryColor,
          ),
        );
        await _fetchUserPosts();
      } else {
        developer.log(
          'Failed to unpin post: ${response.statusCode}, response: $responseBody',
          name: 'UserPostsPage',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Échec du désépinglage : ${responseData['message'] ?? 'Erreur inconnue'}',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        );
      }
    } catch (e, stackTrace) {
      developer.log('Error unpinning post: $e', name: 'UserPostsPage', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors du désépinglage : $e', style: Theme.of(context).textTheme.bodyMedium)),
      );
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
    if (status.isEmpty) {
      developer.log('Post status failed: status is empty', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Veuillez saisir un statut.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentToken == null) {
      developer.log('No valid token available', name: 'UserPostsPage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session expirée. Veuillez vous reconnecter.', style: Theme.of(context).textTheme.bodyMedium)),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

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

      developer.log(
        'Sending POST request to $uri with fields: ${request.fields}, '
            'image: ${image?.path}, removeImage: $removeImage',
        name: 'UserPostsPage',
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = jsonDecode(responseBody);

      if (response.statusCode == 200 && responseData['status'] == 'success') {
        developer.log(
          'Status ${statusId != null ? 'updated' : 'posted'} successfully: ${responseData['message']}',
          name: 'UserPostsPage',
        );
        _handlePostSuccess(context, responseData, statusId);
      } else {
        developer.log(
          'Failed to ${statusId != null ? 'update' : 'post'} status: ${response.statusCode}, response: $responseBody',
          name: 'UserPostsPage',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Échec de la ${statusId != null ? 'mise à jour' : 'publication'} : ${responseData['message'] ?? 'Erreur inconnue'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      developer.log(
        'Error ${statusId != null ? 'updating' : 'posting'} status: $e',
        name: 'UserPostsPage',
        error: e,
        stackTrace: stackTrace,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la ${statusId != null ? 'mise à jour' : 'publication'} : $e',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }
  }

  Future<void> _handlePostSuccess(BuildContext context, Map<String, dynamic> responseData, String? statusId) async {
    final statusData = responseData['data'];
    developer.log('Processing post success: $statusData', name: 'UserPostsPage');
    final account = statusData['account'];
    String username = 'Unknown User';
    String userId = '';
    if (account != null) {
      developer.log('Account data: $account', name: 'UserPostsPage');
      username = account['display_name']?.toString().trim().isNotEmpty ?? false
          ? account['display_name']
          : account['username']?.toString() ?? 'Unknown User';
      userId = account['id']?.toString() ?? '';
      if (userId.isEmpty && account['username'] != null) {
        userId = await _fetchUserIdByUsername(account['username']) ?? '';
      }
    }
    String profileUrl = account?['avatar'] ?? '';
    String text = _stripHtml(statusData['content'] ?? '');
    String imageUrl = statusData['media_attachments']?.isNotEmpty ?? false
        ? statusData['media_attachments'][0]['url'] ?? ''
        : '';
    String timeAgo = _timeAgo(DateTime.parse(statusData['created_at'] ?? DateTime.now().toIso8601String()));
    dynamic poll = statusData['poll'];
    bool favourited = statusData['favourited'] ?? false;
    bool pinned = statusData['pinned'] ?? false;

    setState(() {
      if (statusId != null) {
        final postIndex = posts.indexWhere((post) => post['id'] == statusId);
        if (postIndex != -1) {
          posts[postIndex] = {
            'id': statusData['id'] ?? '',
            'text': text,
            'imageUrl': imageUrl,
            'timeAgo': timeAgo,
            'likes': statusData['favourites_count'] ?? 0,
            'comments': posts[postIndex]['comments'],
            'commentCount': statusData['replies_count'] ?? 0,
            'shares': statusData['reblogs_count'] ?? 0,
            'favourited': favourited,
            'pinned': pinned,
            'poll': poll,
            'userReaction': posts[postIndex]['userReaction'],
            'apiReactions': posts[postIndex]['apiReactions'],
          };
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(statusId != null ? 'Statut mis à jour avec succès !' : 'Statut publié avec succès !',
            style: Theme.of(context).textTheme.bodyMedium),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );

    await _fetchUserPosts();
  }

  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays}j';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'maintenant';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final account = widget.profileDetails?['account'] ?? {};
    final profileUrl = account['avatar'] ?? 'https://social.unistudious.com/avatars/original/missing.png';
    final displayName = account['display_name']?.toString().trim().isNotEmpty ?? false
        ? account['display_name']
        : widget.username;
    developer.log('Building UserPostsPage, profileDetails available: ${widget.profileDetails != null}', name: 'UserPostsPage');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF1A003D), Color(0xFF3C0D73)]
                  : const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: theme.appBarTheme.iconTheme?.color ?? Colors.white),
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  Navigator.pushReplacementNamed(context, '/home');
                }
              },
              tooltip: 'Retour à la page principale',
            ),
            title: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: NetworkImage(profileUrl),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: theme.appBarTheme.titleTextStyle?.copyWith(
                          fontFamily: GoogleFonts.poppins().fontFamily,
                          color: Colors.white,
                        ) ?? TextStyle(
                          fontFamily: GoogleFonts.poppins().fontFamily,
                          color: Colors.white,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${widget.profileDetails?['pagination']?['totalItems'] ?? 0} publications',
                        style: theme.appBarTheme.titleTextStyle?.copyWith(
                          fontFamily: GoogleFonts.poppins().fontFamily,
                          color: Colors.white70,
                          fontSize: 14,
                        ) ?? TextStyle(
                          fontFamily: GoogleFonts.poppins().fontFamily,
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.copy, color: theme.appBarTheme.iconTheme?.color ?? Colors.white),
                onPressed: () {
                  final profileUrl = account['id'] != null
                      ? 'https://unistudious.com/public-social-media-profile/${account['id']}'
                      : 'https://unistudious.com/public-social-media-profile/${account['id']}';
                  Clipboard.setData(ClipboardData(text: profileUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Lien du profil copié dans le presse-papiers !',
                          style: Theme.of(context).textTheme.bodyMedium),
                      backgroundColor: theme.primaryColor,
                    ),
                  );
                  developer.log('Profile URL copied: $profileUrl', name: 'UserPostsPage');
                },
                tooltip: 'Copier le lien du profil',
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: theme.appBarTheme.iconTheme?.color ?? Colors.white),
                color: isDark ? theme.cardColor : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (value) async {
                  if (value == 'block') {
                    await _blockUser(widget.userId, account['username'] ?? widget.username);
                  } else if (value == 'report') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ContentModerationPage(
                          contentType: 'user',
                          contentId: widget.userId,
                        ),
                      ),
                    );
                  }
                },
                itemBuilder: (BuildContext context) {
                  // Only show block/report options if viewing someone else's profile
                  final isOwnProfile = widget.userId == _currentUserId || 
                                      account['id']?.toString() == _currentUserId;
                  
                  if (isOwnProfile) {
                    return [];
                  }
                  
                  return [
                    PopupMenuItem<String>(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(Icons.block, color: Colors.red),
                          const SizedBox(width: 12),
                          Text(
                            'Bloquer l\'utilisateur',
                            style: TextStyle(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'report',
                      child: Row(
                        children: [
                          Icon(Icons.flag, color: Colors.orange),
                          const SizedBox(width: 12),
                          Text(
                            'Signaler l\'utilisateur',
                            style: TextStyle(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ],
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
          : errorMessage != null
          ? Center(child: Text(errorMessage!, style: theme.textTheme.bodyMedium))
          : SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                return _buildPostCard(
                  id: post['id'],
                  username: widget.username,
                  userId: widget.userId,
                  timeAgo: post['timeAgo'],
                  text: post['text'],
                  imageUrl: post['imageUrl'],
                  likes: post['likes'],
                  comments: post['commentCount'],
                  shares: post['shares'],
                  profileUrl: profileUrl,
                  poll: post['poll'],
                  commentList: post['comments'],
                  favourited: post['favourited'],
                  pinned: post['pinned'],
                  currentUserId: _currentUserId,
                  userReaction: post['userReaction'],
                  apiReactions: post['apiReactions'],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard({
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
    required bool pinned,
    required String currentUserId,
    required String? userReaction,
    required Map<String, dynamic> apiReactions,
  }) {
    developer.log('UserPostsPage: Building post card for postId: $id', name: 'UserPostsPage');
    final isOwnPost = userId == currentUserId;
    final theme = Theme.of(context);

    List<Map<String, dynamic>> validatedComments = [];
    if (commentList is List) {
      validatedComments = commentList
          .where((item) => item is Map<String, dynamic>)
          .cast<Map<String, dynamic>>()
          .toList();
    } else {
      developer.log(
          'UserPostsPage: Invalid comments type for postId: $id, type: ${commentList.runtimeType}, data: $commentList',
          name: 'UserPostsPage');
    }

    // Function to copy post link
    void _copyLink() {
      final postLink = 'https://www.unistudious.com/post/$id';
      Clipboard.setData(ClipboardData(text: postLink)).then((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Lien copié dans le presse-papiers !',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
        developer.log('Link copied for post: $id', name: 'UserPostsPage');
      });
    }

    // Function to share on Facebook
    void _shareToFacebook() {
      final postLink = 'https://www.unistudious.com/post/$id';
      Share.share('Découvrez ce post : $postLink', subject: 'Partage de post');
      developer.log('Share to Facebook for post: $id', name: 'UserPostsPage');
    }

    // Function to share via Gmail
    void _shareToGmail() {
      final postLink = 'https://www.unistudious.com/post/$id';
      final Uri emailUri = Uri(
        scheme: 'mailto',
        queryParameters: {
          'subject': 'Partage de post',
          'body': 'Découvrez ce post : $postLink',
        },
      );
      Share.shareUri(emailUri);
      developer.log('Share to Gmail for post: $id', name: 'UserPostsPage');
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
              backgroundImage: NetworkImage(profileUrl),
              radius: 22,
              backgroundColor: theme.colorScheme.surface,
            ),
            title: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      developer.log('UserPostsPage: Tapped username for userId: $userId', name: 'UserPostsPage');
                      final profileDetails = widget.profileDetails;
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
                        developer.log('UserPostsPage: Profile details not available for userId: $userId', name: 'UserPostsPage');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Impossible de charger les détails du profil.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            backgroundColor: theme.colorScheme.surface,
                          ),
                        );
                      }
                    },
                    child: Text(
                      username,
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
                developer.log('UserPostsPage: Showing post options for postId: $id', name: 'UserPostsPage');
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
                            developer.log('UserPostsPage: View Profile tapped for post: $id', name: 'UserPostsPage');
                            Navigator.pop(bottomSheetContext);
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
                            developer.log('UserPostsPage: Favorite toggled for postId: $id, current: $favourited', name: 'UserPostsPage');
                            Navigator.pop(bottomSheetContext);
                            if (favourited) {
                              _markAsNotFavorite(id);
                            } else {
                              _markAsFavorite(id);
                            }
                          },
                        ),
                        if (isOwnPost) ...[
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
                              developer.log('UserPostsPage: Pin toggled for postId: $id, current: $pinned', name: 'UserPostsPage');
                              Navigator.pop(bottomSheetContext);
                              if (pinned) {
                                _unpinFromProfile(id);
                              } else {
                                _pinToProfile(id);
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
                              developer.log('UserPostsPage: Edit selected for postId: $id', name: 'UserPostsPage');
                              Navigator.pop(bottomSheetContext);
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                ),
                                builder: (_) => _EditPostSheet(
                                  postId: id,
                                  initialStatus: text,
                                  initialImageUrl: imageUrl,
                                  initialPoll: poll,
                                  postStatus: _postStatus,
                                  onPostSuccess: _fetchUserPosts,
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
                              developer.log('UserPostsPage: Delete selected for postId: $id', name: 'UserPostsPage');
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
                                        developer.log('UserPostsPage: Delete cancelled for postId: $id', name: 'UserPostsPage');
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
                                        developer.log('UserPostsPage: Delete confirmed for postId: $id', name: 'UserPostsPage');
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
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
              ),
            ),
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) {
                  developer.log('UserPostsPage: Image load failed for postId: $id, url: $imageUrl, error: $error', name: 'UserPostsPage');
                  return const Icon(Icons.broken_image, size: 50);
                },
              ),
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
                    developer.log('UserPostsPage: Showing reactions for postId: $id, apiReactions: $apiReactions', name: 'UserPostsPage');
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (_) => ReactionSheet(
                        apiReactions: apiReactions,
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      if (apiReactions['total'] > 0) ...[
                        ...() {
                          Map<String, int> emojiCount = Map<String, int>.from(apiReactions['byEmoji']);
                          var sortedEmojis = emojiCount.entries.toList()
                            ..sort((a, b) => b.value.compareTo(a.value));
                          List<String> topEmojis = sortedEmojis.take(2).map((e) => e.key).toList();
                          int totalReactions = apiReactions['total'];

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
                    developer.log('UserPostsPage: Showing comments for postId: $id', name: 'UserPostsPage');
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
                          postId: id,
                          comments: validatedComments,
                          onCommentPosted: _postComment,
                          fetchComments: _fetchComments,
                          onDeleteComment: _deleteComment,
                          currentUserId: currentUserId,
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
                  userReaction: userReaction,
                  onReactionSelected: _handleReaction,
                ),
                _buildActionButton(
                  Icons.comment_outlined,
                  "Commenter",
                      () {
                    developer.log('UserPostsPage: Comment button tapped for postId: $id', name: 'UserPostsPage');
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
                          postId: id,
                          comments: validatedComments,
                          onCommentPosted: _postComment,
                          fetchComments: _fetchComments,
                          onDeleteComment: _deleteComment,
                          currentUserId: currentUserId,
                        ),
                      ),
                    );
                  },
                  color: theme.hintColor,
                ),
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
    final theme = Theme.of(context);
    bool hasVoted = poll['voted'] ?? false;
    List<dynamic> options = poll['options'] ?? [];
    int totalVotes = poll['votes_count'] ?? 0;
    developer.log(
      'Building poll widget, hasVoted: $hasVoted, options: ${options.length}, totalVotes: $totalVotes',
      name: 'UserPostsPage',
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
              developer.log('Poll option tapped: $title, index: $index', name: 'UserPostsPage');
              _votePoll(poll['id'], index);
            },
            child: Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: hasVoted && poll['own_votes'].contains(index)
                    ? theme.primaryColor.withOpacity(0.2)
                    : theme.cardColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasVoted && poll['own_votes'].contains(index)
                      ? theme.primaryColor
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
                        color: theme.textTheme.bodyMedium?.color ?? Colors.grey[800],
                      ),
                    ),
                  ),
                  Text(
                    '${percentage.toStringAsFixed(1)}% ($votes)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: GoogleFonts.poppins().fontFamily,
                      color: theme.textTheme.bodySmall?.color ?? Colors.grey[600],
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

  Widget _buildReactionRow(String postId, Map<String, dynamic> apiReactions, String? userReaction) {
    final theme = Theme.of(context);
    final Map<String, int> reactionCounts = Map<String, int>.from(apiReactions['byEmoji'] ?? {});
    final int totalReactions = apiReactions['total'] ?? 0;

    if (totalReactions == 0 && userReaction == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_emotions_outlined, color: Colors.grey, size: 18),
            const SizedBox(width: 4),
            Text(
              "0",
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
            ),
          ],
        ),
      );
    }


    var sortedReactions = reactionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    List<String> topReactions = sortedReactions.take(2).map((e) => e.key).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: GestureDetector(
        onTap: () {
          developer.log('Reactions tapped for post: $postId', name: 'UserPostsPage');
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
          mainAxisSize: MainAxisSize.min,
          children: [
            if (totalReactions > 0) ...[
              ...topReactions.map((emoji) => Row(
                children: [
                  Text(
                    emoji,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(width: 4),
                ],
              )),
              Text(
                '$totalReactions',
                style: TextStyle(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap, {Color? color}) {
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
              color: color ?? theme.textTheme.bodyMedium?.color ?? Colors.grey[700],
              fontFamily: GoogleFonts.poppins().fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}

class ReactionSheet extends StatelessWidget {
  final Map<String, dynamic> apiReactions;

  const ReactionSheet({super.key, required this.apiReactions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    developer.log('🔵 ReactionSheet build, apiReactions: $apiReactions', name: 'ReactionSheet');
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

class ReactionButton extends StatefulWidget {
  final String postId;
  final String currentUserId;
  final String? userReaction;
  final Function(String, String?) onReactionSelected;

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

  final List<String> reactions = ['👍', '❤️', '😂', '😮', '😢', '😡', '🔥', '💯'];
  final Map<String, String> reactionLabels = {
    '👍': 'J\'aime',
    '❤️': 'Love',
    '😂': 'Haha',
    '😮': 'Wow',
    '😢': 'Triste',
    '😡': 'Grr',
    '🔥': 'Génial',
    '💯': 'Parfait',
  };

  @override
  void initState() {
    super.initState();
    _selectedReaction = widget.userReaction;
    developer.log('🔵 ReactionButton init with ${widget.userReaction}', name: 'ReactionButton');
  }

  @override
  void didUpdateWidget(covariant ReactionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userReaction != widget.userReaction) {
      developer.log('🟢 ReactionButton updated: ${widget.userReaction}', name: 'ReactionButton');
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
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: reactions.map((emoji) {
                      return GestureDetector(
                        onTap: () {
                          developer.log('🔵 Reaction emoji selected: $emoji', name: 'ReactionButton');
                          setState(() {
                            _selectedReaction = emoji;
                          });
                          widget.onReactionSelected(widget.postId, emoji);
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
    developer.log('🔵 ReactionButton build, selected: $_selectedReaction', name: 'ReactionButton');
    return GestureDetector(
      onLongPress: () => _showReactions(context),
      onTap: () {
        developer.log('🔵 ReactionButton tap, current selected: $_selectedReaction', name: 'ReactionButton');
        if (_selectedReaction != null) {
          setState(() {
            _selectedReaction = null;
          });
          widget.onReactionSelected(widget.postId, null);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selectedReaction == null) ...[
            Icon(Icons.thumb_up_alt_outlined, size: 20, color: theme.iconTheme.color),
            const SizedBox(width: 6),
          ] else ...[
            Text(_selectedReaction!, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
          ],
          Text(
            _selectedReaction != null
                ? reactionLabels[_selectedReaction] ?? 'Réagir'
                : 'Réagir',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: GoogleFonts.poppins().fontFamily,
              color: _selectedReaction != null
                  ? theme.textTheme.bodyMedium?.color
                  : theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            ) ?? TextStyle(
              fontFamily: GoogleFonts.poppins().fontFamily,
              fontSize: 14,
              color: _selectedReaction != null ? Colors.black : Colors.grey[700],
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

  String? _selectedCommentId; // To highlight selected comment

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors du chargement des commentaires : $e')),
      );
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
      _selectedCommentId = commentId; // Highlight selected comment
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
      // If the user closes the menu without selecting, clear the highlight
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
      name: 'UserPostsPage.EditPostSheet',
    );
  }

  void _addPollOption() {
    if (_pollControllers.length < 4) {
      setState(() {
        _pollControllers.add(TextEditingController());
        developer.log(
          'Added new poll option, total options: ${_pollControllers.length}',
          name: 'UserPostsPage.EditPostSheet',
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
          name: 'UserPostsPage.EditPostSheet',
        );
      });
    }
  }

  Future<void> _updatePost() async {
    final theme = Theme.of(context);
    String statusText = _editStatusController.text.trim();
    List<String> pollOptions = _pollControllers.map((c) => c.text.trim()).where((text) => text.isNotEmpty).toList();
    developer.log(
      'Updating post, postId: ${widget.postId}, status: $statusText, enablePoll: $_enablePoll, pollOptions: $pollOptions, selectedDuration: $_selectedDuration, originalDuration: $_originalDuration, image: ${_selectedImage?.path}, removeImage: $_removeImage',
      name: 'UserPostsPage.EditPostSheet',
    );

    if (statusText.isEmpty && _selectedImage == null && (!_enablePoll || pollOptions.isEmpty) && !widget.initialImageUrl.isNotEmpty) {
      developer.log('Post update failed: status, image, and poll are empty', name: 'UserPostsPage.EditPostSheet');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Veuillez saisir un statut, ajouter une image ou activer un sondage.',
            style: theme.textTheme.bodyMedium,
          ),
          backgroundColor: theme.primaryColor,
        ),
      );
      return;
    }

    if (_enablePoll && pollOptions.length < 2) {
      developer.log('Post update failed: less than 2 poll options', name: 'UserPostsPage.EditPostSheet');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Veuillez saisir au moins deux options pour le sondage.',
            style: theme.textTheme.bodyMedium,
          ),
          backgroundColor: theme.primaryColor,
        ),
      );
      return;
    }

    if (_enablePoll && _selectedDuration == null && _originalDuration == null) {
      developer.log('Post update failed: no poll duration', name: 'UserPostsPage.EditPostSheet');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Veuillez choisir une durée pour le sondage.',
            style: theme.textTheme.bodyMedium,
          ),
          backgroundColor: theme.primaryColor,
        ),
      );
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
          developer.log('Downloaded original image to preserve it', name: 'UserPostsPage.EditPostSheet');
        } else {
          developer.log('Failed to download original image: ${response.statusCode}', name: 'UserPostsPage.EditPostSheet');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Erreur lors du téléchargement de l\'image originale.',
                style: theme.textTheme.bodyMedium,
              ),
              backgroundColor: theme.primaryColor,
            ),
          );
          return;
        }
      } catch (e) {
        developer.log('Error downloading original image: $e', name: 'UserPostsPage.EditPostSheet');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erreur lors du téléchargement de l\'image originale.',
              style: theme.textTheme.bodyMedium,
            ),
            backgroundColor: theme.primaryColor,
          ),
        );
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
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.dialogBackgroundColor,
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
                fontFamily: GoogleFonts.poppins().fontFamily,
                color: theme.primaryColor,
                fontWeight: FontWeight.bold,
              ) ?? TextStyle(
                fontFamily: GoogleFonts.poppins().fontFamily,
                color: theme.primaryColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              "Votre statut",
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: GoogleFonts.poppins().fontFamily,
                color: theme.textTheme.bodySmall?.color ?? Colors.grey[700],
                fontWeight: FontWeight.w500,
              ) ?? TextStyle(
                fontFamily: GoogleFonts.poppins().fontFamily,
                color: theme.textTheme.bodySmall?.color ?? Colors.grey[700],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _editStatusController,
              decoration: InputDecoration(
                hintText: "Modifier votre statut",
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  color: theme.textTheme.bodySmall?.color ?? Colors.grey[600],
                ),
                filled: true,
                fillColor: theme.inputDecorationTheme.fillColor ?? theme.cardColor.withOpacity(0.1),
                border: theme.inputDecorationTheme.border ??
                    OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                prefixIcon: IconButton(
                  icon: Icon(Icons.camera_alt, color: theme.primaryColor, size: 28),
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
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: GoogleFonts.poppins().fontFamily,
                fontSize: 14,
              ),
              onChanged: (value) {
                developer.log('Edit status changed: $value', name: 'UserPostsPage.EditPostSheet');
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
                      icon: const Icon(Icons.close, color: Colors.red),
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: GoogleFonts.poppins().fontFamily,
                    color: theme.textTheme.bodySmall?.color ?? Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ) ?? TextStyle(
                    fontFamily: GoogleFonts.poppins().fontFamily,
                    color: theme.textTheme.bodySmall?.color ?? Colors.grey[700],
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Switch(
                  value: _enablePoll,
                  onChanged: (value) {
                    setState(() {
                      _enablePoll = value;
                    });
                    developer.log('Poll toggle changed: $_enablePoll', name: 'UserPostsPage.EditPostSheet');
                  },
                  activeColor: theme.primaryColor,
                ),
              ],
            ),
            if (_enablePoll) ...[
              const SizedBox(height: 20),
              Text(
                "Options de réponse",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  color: theme.textTheme.bodySmall?.color ?? Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ) ?? TextStyle(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  color: theme.textTheme.bodySmall?.color ?? Colors.grey[700],
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
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
                            hintStyle: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: GoogleFonts.poppins().fontFamily,
                              color: theme.textTheme.bodySmall?.color ?? Colors.grey[600],
                            ),
                            filled: true,
                            fillColor: theme.inputDecorationTheme.fillColor ?? theme.cardColor.withOpacity(0.1),
                            border: theme.inputDecorationTheme.border ??
                                OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: GoogleFonts.poppins().fontFamily,
                            fontSize: 14,
                          ),
                          onChanged: (value) {
                            developer.log('Poll option $index changed: $value',
                                name: 'UserPostsPage.EditPostSheet');
                          },
                        ),
                      ),
                      if (_pollControllers.length > 2)
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: theme.iconTheme.color ?? Colors.grey[600]),
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
                      icon: Icon(Icons.add_circle_outline, color: theme.primaryColor),
                      label: Text(
                        "Ajouter une option",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: GoogleFonts.poppins().fontFamily,
                          color: theme.primaryColor,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: theme.cardColor,
                        shape: const StadiumBorder(),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                "Durée du sondage",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  color: theme.textTheme.bodySmall?.color ?? Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ) ?? TextStyle(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  color: theme.textTheme.bodySmall?.color ?? Colors.grey[700],
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: "Durée",
                  labelStyle: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: GoogleFonts.poppins().fontFamily,
                    color: theme.textTheme.bodySmall?.color ?? Colors.grey[600],
                  ),
                  filled: true,
                  fillColor: theme.inputDecorationTheme.fillColor ?? theme.cardColor.withOpacity(0.1),
                  border: theme.inputDecorationTheme.border ??
                      OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                ),
                value: _selectedDuration,
                onChanged: (value) {
                  setState(() => _selectedDuration = value);
                  developer.log('Poll duration changed: $value', name: 'UserPostsPage.EditPostSheet');
                },
                items: _durations.map((duration) {
                  return DropdownMenuItem(
                    value: duration,
                    child: Text(
                      duration,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: GoogleFonts.poppins().fontFamily,
                        fontSize: 14,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _updatePost,
              icon: Icon(Icons.send_rounded, color: theme.colorScheme.onPrimary),
              label: Text(
                "Mettre à jour",
                style: theme.textTheme.labelLarge?.copyWith(
                  fontFamily: GoogleFonts.poppins().fontFamily,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
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