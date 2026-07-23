import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:developer' as developer;
import '../utils/app_bar_gradient.dart';
import '../widgets/notification_icon_button.dart';

class SearchPage extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final Future<void> Function(String, {required int page}) onSearchByHashtag;

  const SearchPage({
    super.key,
    required this.posts,
    required this.onSearchByHashtag,
  });

  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredPosts = [];
  List<Map<String, dynamic>> _hashtagPosts = [];
  bool _isHashtagSearch = false;
  bool _isLoading = false;
  String? _errorMessage;
  int _currentPage = 1;
  int _totalPages = 1;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _filteredPosts = widget.posts;
    developer.log('Initializing SearchPage with ${widget.posts.length} posts', name: 'SearchPage');
    _searchController.addListener(_onSearchQueryChanged);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading &&
          _isHashtagSearch &&
          _currentPage < _totalPages) {
        _fetchMoreHashtagPosts();
      }
    });
  }

  void _onSearchQueryChanged() {
    final query = _searchController.text.trim();
    developer.log('Search query changed: $query', name: 'SearchPage');
    setState(() {
      _errorMessage = null;
      if (query.startsWith('#')) {
        _isHashtagSearch = query.length > 1; // Only treat as hashtag if more than just '#'
        if (_isHashtagSearch) {
          // Defer hashtag search to allow typing
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_searchController.text.trim() == query && query.length > 2) {
              _performHashtagSearch(query.substring(1));
            } else if (query.length <= 2 && query.length > 1) {
              _errorMessage = 'Le hashtag doit contenir au moins 2 caractères.';
              _hashtagPosts = [];
              _isLoading = false;
            }
          });
        }
      } else {
        _isHashtagSearch = false;
        _hashtagPosts = [];
        _filteredPosts = query.isEmpty
            ? widget.posts
            : widget.posts
            .where((post) =>
        post['text'].toLowerCase().contains(query.toLowerCase()) ||
            post['username'].toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
      developer.log(
        'Filtering posts with query: $query, isHashtagSearch: $_isHashtagSearch',
        name: 'SearchPage',
      );
    });
  }

  Future<void> _performHashtagSearch(String hashtag) async {
    if (hashtag.length < 2) {
      setState(() {
        _errorMessage = 'Le hashtag doit contenir au moins 2 caractères.';
        _hashtagPosts = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _currentPage = 1;
    });

    try {
      await widget.onSearchByHashtag(hashtag, page: 1);
      // The posts will be updated in SocialFeedPage and passed back via Navigator.pop
      // For now, we rely on the updated posts being available in widget.posts
      setState(() {
        _hashtagPosts = widget.posts;
        _totalPages = widget.posts.isNotEmpty ? widget.posts[0]['totalPages'] ?? 1 : 1;
        _isLoading = false;
        if (_hashtagPosts.isEmpty) {
          _errorMessage = 'Aucun post trouvé pour le hashtag #$hashtag.';
        }
      });
      developer.log(
        'Hashtag search completed for #$hashtag, posts: ${_hashtagPosts.length}',
        name: 'SearchPage',
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur lors de la recherche du hashtag : $e';
        _isLoading = false;
        _hashtagPosts = [];
      });
      developer.log('Error during hashtag search: $e', name: 'SearchPage');
    }
  }

  Future<void> _fetchMoreHashtagPosts() async {
    if (_currentPage >= _totalPages) return;

    final hashtag = _searchController.text.trim().substring(1);
    setState(() {
      _isLoading = true;
    });

    try {
      await widget.onSearchByHashtag(hashtag, page: _currentPage + 1);
      setState(() {
        _hashtagPosts = widget.posts;
        _currentPage++;
        _isLoading = false;
      });
      developer.log(
        'Fetched more hashtag posts for #$hashtag, page: $_currentPage, total posts: ${_hashtagPosts.length}',
        name: 'SearchPage',
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur lors du chargement des posts supplémentaires : $e';
        _isLoading = false;
      });
      developer.log('Error fetching more hashtag posts: $e', name: 'SearchPage');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    developer.log(
      'Building SearchPage, filtered posts: ${_isHashtagSearch ? _hashtagPosts.length : _filteredPosts.length}, isHashtagSearch: $_isHashtagSearch',
      name: 'SearchPage',
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: AppBarGradient.flexibleSpace(isDark),
        title: Text(
          'Rechercher',
          style: TextStyle(
            color: Colors.white,
            fontFamily: GoogleFonts.poppins().fontFamily,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            developer.log('Back button pressed', name: 'SearchPage');
            Navigator.pop(context, widget.posts);
          },
        ),
        actions: [
          const NotificationIconButton(),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher un post ou un hashtag...',
                prefixIcon: const Icon(Icons.search, color: Colors.deepPurple),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
              ),
              style: TextStyle(
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(child: Text(_errorMessage!))
                : (_isHashtagSearch ? _hashtagPosts : _filteredPosts).isEmpty
                ? const Center(child: Text('Aucun post trouvé.'))
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: (_isHashtagSearch ? _hashtagPosts : _filteredPosts).length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == (_isHashtagSearch ? _hashtagPosts : _filteredPosts).length && _isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                final post = _isHashtagSearch ? _hashtagPosts[index] : _filteredPosts[index];
                return _buildPostCard(post);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: NetworkImage(post['profileUrl']),
                  radius: 20,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post['username'],
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                    ),
                    Text(
                      post['timeAgo'],
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontFamily: GoogleFonts.poppins().fontFamily,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              post['text'],
              style: TextStyle(
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
            ),
            if (post['imageUrl'].isNotEmpty) ...[
              const SizedBox(height: 10),
              Image.network(
                post['imageUrl'],
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '${post['likes']} likes • ${post['commentCount']} commentaires • ${post['shares']} partages',
              style: TextStyle(
                color: Colors.grey[600],
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchQueryChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}