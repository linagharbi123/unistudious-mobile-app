import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart'; // For VideoPlayer
import 'package:audioplayers/audioplayers.dart'; // For AudioPlayer
import 'dart:io'; // For File handling
import '../widgets/sidebar.dart';
import 'package:url_launcher/url_launcher.dart'; // For launching URLs
import 'package:path_provider/path_provider.dart'; // For temporary directory
import 'package:open_file/open_file.dart'; // For opening files
import 'package:path/path.dart' as path; // For path manipulation
import 'dart:async'; // For TimeoutException
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/loading_provider.dart'; // Add LoadingProvider
import '../models/app_bar_provider.dart';
import '../widgets/loading_wrapper.dart'; // Add LoadingWrapper
import 'dart:typed_data'; // For base64 decoding
import 'package:flutter/foundation.dart'; // For compute
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../utils/connection_checker.dart';

class ResourcesPage extends StatefulWidget {
  const ResourcesPage({super.key});

  @override
  _ResourcesPageState createState() => _ResourcesPageState();
}

class ResourceImageViewerScreen extends StatelessWidget {
  final String filePath;
  final String fileName;

  const ResourceImageViewerScreen({super.key, required this.filePath, required this.fileName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.appBarTheme.iconTheme?.color ?? Colors.white),
        title: Text(
          fileName,
          style: TextStyle(
            color: theme.appBarTheme.foregroundColor ?? Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
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
      body: Center(
        child: InteractiveViewer(
          child: Image.file(
            File(filePath),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class ResourceAudioPlayerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;
  final bool isNetwork;

  const ResourceAudioPlayerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
    this.isNetwork = false,
  });

  @override
  State<ResourceAudioPlayerScreen> createState() => _ResourceAudioPlayerScreenState();
}

class _ResourceAudioPlayerScreenState extends State<ResourceAudioPlayerScreen> {
  late final AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initializeAudio();
  }

  Future<void> _initializeAudio() async {
    try {
      if (widget.isNetwork) {
        // Sur iOS, AVPlayer peut avoir des problèmes avec certains formats M4A/MP3 depuis des URLs distantes.
        // On télécharge toujours le fichier sur iOS avant de le lire pour garantir la compatibilité.
        if (Platform.isIOS) {
          final uri = Uri.parse(widget.filePath);
          final response = await http.get(uri).timeout(const Duration(seconds: 30));
          if (response.statusCode != 200) {
            throw Exception('HTTP ${response.statusCode} lors du chargement de l\'audio');
          }

          final tempDir = await getTemporaryDirectory();
          final fileNameFromUrl = uri.pathSegments.isNotEmpty
              ? uri.pathSegments.last
              : '${DateTime.now().millisecondsSinceEpoch}.m4a';
          final sanitizedName = fileNameFromUrl.replaceAll('/', '_').replaceAll('\\', '_');
          final tempFile = File(
            '${tempDir.path}/resource_audio_${DateTime.now().millisecondsSinceEpoch}_$sanitizedName',
          );
          await tempFile.writeAsBytes(response.bodyBytes);

          await _audioPlayer.setSource(DeviceFileSource(tempFile.path));
        } else {
          await _audioPlayer.setSourceUrl(widget.filePath);
        }
      } else {
        await _audioPlayer.setSource(DeviceFileSource(widget.filePath));
      }
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
      _audioPlayer.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
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
        setState(() {
          _errorMessage = 'Erreur lors du chargement de l\'audio: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final maxSeconds = _duration.inSeconds == 0 ? 1 : _duration.inSeconds;
    final currentValue = _position.inSeconds.clamp(0, maxSeconds).toDouble();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.appBarTheme.iconTheme?.color ?? Colors.white),
        title: Text(
          widget.fileName,
          style: TextStyle(
            color: theme.appBarTheme.foregroundColor ?? Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
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
      body: Center(
        child: _errorMessage != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: isDark ? Colors.red[400] : Colors.red[700],
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Retour'),
                  ),
                ],
              )
            : _isInitialized
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(
                          widget.fileName,
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Slider(
                        value: currentValue,
                        max: maxSeconds.toDouble(),
                        activeColor: theme.colorScheme.primary,
                        inactiveColor: (theme.disabledColor ?? Colors.grey).withOpacity(0.4),
                        onChanged: _duration.inSeconds == 0
                            ? null
                            : (value) async {
                                await _audioPlayer.seek(Duration(seconds: value.toInt()));
                              },
                      ),
                      Text(
                        '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      IconButton(
                        iconSize: 48,
                        color: theme.colorScheme.primary,
                        icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
                        onPressed: () async {
                          if (_isPlaying) {
                            await _audioPlayer.pause();
                          } else {
                            await _audioPlayer.resume();
                          }
                        },
                      ),
                    ],
                  )
                : CircularProgressIndicator(color: theme.colorScheme.primary),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

class ResourcePDFViewerScreen extends StatelessWidget {
  final String filePath;
  final String fileName;

  const ResourcePDFViewerScreen({super.key, required this.filePath, required this.fileName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.appBarTheme.iconTheme?.color ?? Colors.white),
        title: Text(
          fileName,
          style: TextStyle(
            color: theme.appBarTheme.foregroundColor ?? Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
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
      body: PDFView(
        filePath: filePath,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: true,
        pageFling: true,
        onError: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur lors du chargement du PDF: $error'),
            ),
          );
        },
        onPageError: (page, error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur sur la page $page: $error'),
            ),
          );
        },
      ),
    );
  }
}

class _ResourcesPageState extends State<ResourcesPage> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(); // Ajout du FocusNode pour la barre de recherche
  String selectedSession = 'Tous';
  List<Map<String, dynamic>> allResources = [];
  List<Map<String, dynamic>> sessions = []; // Store session id and name
  List<String> sessionTabs = ['Tous'];
  TabController? _tabController;
  bool isConnectionError = false;
  Timer? _connectionCheckTimer;
  bool _hasLoadedData = false; // Indique si les données ont été chargées au moins une fois

  final String apiUrl = 'https://www.unistudious.com';

  @override
  void initState() {
    super.initState();
    _startConnectionMonitoring();

    // Configurer l'AppBar via le provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final appBarProvider = Provider.of<AppBarProvider>(context, listen: false);
        appBarProvider.updateConfig(3, AppBarConfig(
          title: 'Ressources',
        ));
      }
      _initializeData();
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
            _initializeData();
          }
        });
      }
    });
  }
  
  void _updateAppBarTabBar() {
    if (!mounted) return;
    final appBarProvider = Provider.of<AppBarProvider>(context, listen: false);
    final theme = Theme.of(context);
    
    PreferredSizeWidget? tabBar;
    if (sessions.isNotEmpty && _tabController != null) {
      tabBar = TabBar(
        controller: _tabController,
        isScrollable: true,
        tabs: sessionTabs.map((tab) => Tab(text: tab)).toList(),
        indicatorColor: theme.appBarTheme.foregroundColor ?? Colors.white,
        labelColor: theme.appBarTheme.foregroundColor ?? Colors.white,
        unselectedLabelColor: (theme.appBarTheme.foregroundColor ?? Colors.white).withOpacity(0.7),
        onTap: (index) {
          setState(() {
            selectedSession = sessionTabs[index];
          });
        },
      );
    }
    
    appBarProvider.updateConfig(3, AppBarConfig(
      title: 'Ressources',
      bottom: tabBar,
    ));
  }

  @override
  void dispose() {
    _connectionCheckTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose(); // Dispose du FocusNode
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);

    setState(() {
      isConnectionError = false;
      _hasLoadedData = false; // Réinitialiser lors d'un nouveau chargement
    });

    if (!authProvider.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez vous connecter pour continuer.')),
      );
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    try {
      loadingProvider.showLoading();
      await Future.delayed(const Duration(milliseconds: 300)); // Ensure animation is visible
      await _fetchSessions();
      await _fetchResources();
    } finally {
      loadingProvider.hideLoading();
    }
  }

  Future<void> _fetchSessions() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      final response = await authProvider.authenticatedRequest(
        'GET',
        '/api/user/get-session',
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final List<dynamic> sessionData = jsonResponse['sessions'] ?? [];
        setState(() {
          sessions = sessionData
              .where((session) => session != null && session['id'] != null && session['name'] != null)
              .map((session) => {
            'id': session['id'],
            'name': session['name'] as String,
          })
              .toList();
          sessionTabs = ['Tous', ...sessions.map((session) => session['name'] as String).toList()];
          _tabController?.dispose(); // Dispose previous controller if exists
          _tabController = TabController(
            length: sessionTabs.length,
            vsync: this,
          );
          isConnectionError = false;
        });
      } else {
        // Ne pas afficher de snackbar pour les erreurs (gérées dans le catch)
        if (mounted && response.statusCode != 401 && response.statusCode != 403) {
          // On laisse les erreurs HTTP s'afficher mais pas les erreurs de connexion
        }
      }
    } catch (e) {
      // Détecter les erreurs de connexion
      final isNetworkError = e is SocketException || 
                             e is TimeoutException ||
                             e.toString().contains('SocketException') ||
                             e.toString().contains('Failed host lookup') ||
                             e.toString().contains('Network is unreachable') ||
                             e.toString().contains('Connection refused') ||
                             e.toString().contains('Connection timed out') ||
                             e.toString().contains('No Internet connection') ||
                             e.toString().contains('ClientException') ||
                             e.toString().contains('OS Error');
      
      if (mounted) {
        setState(() {
          if (isNetworkError) {
            isConnectionError = true;
          } else {
            isConnectionError = false;
            // Ne pas afficher de snackbar pour les erreurs de réseau
          }
        });
      }
    }
  }

  Future<void> _fetchResources() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      final foldersResponse = await authProvider.authenticatedRequest(
        'GET',
        '/api/get-share-resource-folder',
      );

      print('API Response Status: ${foldersResponse.statusCode}');
      print('API Response Body: ${foldersResponse.body}');

      if (foldersResponse.statusCode == 200) {
        final foldersJson = jsonDecode(foldersResponse.body);
        final List<dynamic> folders = foldersJson['folders'] ?? [];

        print('Folders found: ${folders.length}');
        print('Folders data: $folders');

        setState(() {
          final folderResources = folders.map((folder) {
            final session = sessions.firstWhere(
                  (s) => s['id'] == folder['sessionId'],
              orElse: () => {'name': 'Session inconnue'},
            );
            return {
              'id': folder['id'],
              'title': folder['name'] ?? 'Dossier sans nom',
              'category': 'Dossier partagé',
              'size': folder['totalSize'] != null ? '${folder['totalSize']} MB' : 'Inconnu',
              'type': 'Dossiers',
              'time': folder['createdAt'] ?? 'Inconnu',
              'icon': Icons.folder,
              'color': const Color(0xFFFFCC80),
              'itemsCount': folder['itemsCount']?.toString() ?? '0',
              'sessionId': folder['sessionId'],
              'sessionName': session['name'],
            };
          }).toList();

          print('Processed folder resources: ${folderResources.length}');

          allResources = folderResources;
          isConnectionError = false;
          _hasLoadedData = true; // Marquer que les données ont été chargées
        });
      } else {
        print('API Error: ${foldersResponse.statusCode} - ${foldersResponse.body}');
        if (mounted) {
          setState(() {
            isConnectionError = false;
          });
        }
      }
    } catch (e) {
      print('Exception during fetchResources: $e');
      
      // Détecter les erreurs de connexion
      final isNetworkError = e is SocketException || 
                             e is TimeoutException ||
                             e.toString().contains('SocketException') ||
                             e.toString().contains('Failed host lookup') ||
                             e.toString().contains('Network is unreachable') ||
                             e.toString().contains('Connection refused') ||
                             e.toString().contains('Connection timed out') ||
                             e.toString().contains('No Internet connection') ||
                             e.toString().contains('ClientException') ||
                             e.toString().contains('OS Error');
      
      if (mounted) {
        setState(() {
          if (isNetworkError) {
            isConnectionError = true;
          } else {
            isConnectionError = false;
            // Ne pas afficher de snackbar pour les erreurs de réseau
          }
        });
      }
    }
  }

  Future<void> _openFileDirectly(Map<String, dynamic> file) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);

    if (file['id'] == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur : Données manquantes.')),
        );
      }
      return;
    }

    final videoExtensions = ['.mp4'];
    bool isVideo = videoExtensions.any((ext) => file['title'].toLowerCase().endsWith(ext)) || file['type'].toUpperCase() == 'VIDÉOS';

    try {
      loadingProvider.showLoading();
      if (isVideo) {
        final response = await authProvider.authenticatedRequest(
          'POST',
          '/api/share-resource/read-file-video',
          body: json.encode({'id': file['id'].toString().trim()}),
        );

        if (response.statusCode == 200) {
          final body = response.body.trim();
          if (body.startsWith('<!doctype') || body.contains('<html') || body.contains('<body') || body.contains('Fatal error') || body.contains('<br />')) {
            String errorMessage = 'Erreur serveur: Problème de mémoire ou fichier non disponible.';
            if (body.contains('Allowed memory size')) {
              errorMessage = 'Erreur serveur: Mémoire insuffisante pour traiter le fichier. Veuillez contacter le support à kernalsiprod@gmail.com.';
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(errorMessage)),
              );
            }
            await _fetchFileFallback(file);
            return;
          }

          dynamic jsonResponse;
          try {
            jsonResponse = jsonDecode(response.body);
            if (jsonResponse is! Map<String, dynamic>) {
              throw const FormatException('Video API response is not a valid JSON object');
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Erreur: Réponse du serveur non valide (JSON invalide).')),
              );
            }
            await _fetchFileFallback(file);
            return;
          }

          final fileContent = jsonResponse;
          if (fileContent['link'] != null && fileContent['link'].toString().isNotEmpty) {
            final fileUrl = fileContent['link'].toString();
            try {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VideoPlayerScreen(filePath: fileUrl, isNetwork: true),
                ),
              );
            } catch (e) {
              if (await canLaunchUrl(Uri.parse(fileUrl))) {
                await launchUrl(Uri.parse(fileUrl), mode: LaunchMode.externalApplication);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Impossible d\'ouvrir ou diffuser la vidéo.')),
                  );
                }
              }
            }
            return;
          } else {
            await _fetchFileFallback(file);
            return;
          }
        } else {
          await _fetchFileFallback(file);
          return;
        }
      } else {
        await _fetchFileFallback(file);
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'ouverture de la vidéo: $e')),
        );
      }
      await _fetchFileFallback(file);
      return;
    } finally {
      loadingProvider.hideLoading();
    }
  }

  Future<void> _fetchFileFallback(Map<String, dynamic> file) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);

    try {
      loadingProvider.showLoading();
      final response = await authProvider.authenticatedRequest(
        'POST',
        '/api/share-resource/read-file',
        body: json.encode({'id': file['id'].toString().trim()}),
      );

      if (response.statusCode == 200) {
        final body = response.body.trim();
        if (body.startsWith('<!doctype') || body.contains('<html') || body.contains('<body') || body.contains('Fatal error') || body.contains('<br />')) {
          String errorMessage = 'Erreur serveur: Problème de mémoire ou fichier non disponible.';
          if (body.contains('Allowed memory size')) {
            errorMessage = 'Erreur serveur: Mémoire insuffisante pour traiter le fichier. Veuillez contacter le support à kernalsiprod@gmail.com.';
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errorMessage)),
            );
          }
          return;
        }

        dynamic jsonResponse;
        try {
          jsonResponse = jsonDecode(response.body);
          if (jsonResponse is! Map<String, dynamic>) {
            throw const FormatException('Response is not a valid JSON object');
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erreur: Réponse du serveur non valide (JSON invalide).')),
            );
          }
          return;
        }

        final fileContent = jsonResponse;
        final videoExtensions = ['.mp4'];
        final imageExtensions = ['.png', '.jpg', '.jpeg'];
        final audioExtensions = ['.mp3'];
        final fileTitle = (file['title'] ?? '').toString().toLowerCase();
        final fileType = (file['type'] ?? '').toString().toUpperCase();
        final bool isVideo = videoExtensions.any((ext) => fileTitle.endsWith(ext)) || fileType == 'VIDÉOS' || fileType == 'VIDEO';
        final bool isImage = imageExtensions.any((ext) => fileTitle.endsWith(ext)) || fileType == 'IMAGES' || fileType == 'IMAGE';
        final bool isAudio = audioExtensions.any((ext) => fileTitle.endsWith(ext)) || fileType == 'AUDIO';

        if (fileContent['url'] != null && fileContent['url'].toString().isNotEmpty && isVideo) {
          final fileUrl = fileContent['url'].toString();
          try {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoPlayerScreen(filePath: fileUrl, isNetwork: true),
              ),
            );
          } catch (e) {
            if (await canLaunchUrl(Uri.parse(fileUrl))) {
              await launchUrl(Uri.parse(fileUrl), mode: LaunchMode.externalApplication);
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Impossible d\'ouvrir ou diffuser la vidéo.')),
                );
              }
            }
          }
          return;
        }

        final bool isPdf = fileTitle.endsWith('.pdf') || fileType == 'PDF';
        final String rawFileName = fileContent['fileName'] ?? file['title'].replaceAll(RegExp(r'[^\w\.]'), '_');
        final String fileName = _sanitizeFileName(path.basename(rawFileName));
        final String base64Content = fileContent['content']?.toString() ?? '';

        if (base64Content.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Le contenu du fichier est vide.')),
            );
          }
          return;
        }

        if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(base64Content)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erreur: Le contenu du fichier n\'est pas un base64 valide.')),
            );
          }
          return;
        }

        late Uint8List contentBytes;
        try {
          contentBytes = await compute(base64Decode, base64Content);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur lors du décodage du fichier: $e')),
            );
          }
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';
        final tempFile = File(filePath);
        await tempFile.parent.create(recursive: true);
        await tempFile.writeAsBytes(contentBytes);

        if (!await tempFile.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erreur: Le fichier n\'a pas pu être créé.')),
            );
          }
          return;
        }

        loadingProvider.hideLoading();
        if (isVideo) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(filePath: filePath, isNetwork: false),
            ),
          );
          await tempFile.delete();
          return;
        }

        if (isPdf) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResourcePDFViewerScreen(filePath: filePath, fileName: fileName),
            ),
          );
          await tempFile.delete();
          return;
        }

        if (isImage) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResourceImageViewerScreen(filePath: filePath, fileName: fileName),
            ),
          );
          await tempFile.delete();
          return;
        }

        if (isAudio) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResourceAudioPlayerScreen(filePath: filePath, fileName: fileName),
            ),
          );
          await tempFile.delete();
          return;
        }

        final result = await OpenFile.open(filePath);
        if (result.type != ResultType.done) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur lors de l\'ouverture du fichier: ${result.message}')),
            );
          }
        }
        await tempFile.delete();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur lors du téléchargement du fichier: ${response.statusCode} - ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'ouverture du fichier: $e')),
        );
      }
    } finally {
      loadingProvider.hideLoading();
    }
  }

  String _sanitizeFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'[^\w\.]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }

  List<Map<String, dynamic>> get filteredResources {
    List<Map<String, dynamic>> filtered = allResources;

    if (selectedSession != 'Tous') {
      final selectedSessionId = sessions.firstWhere(
            (session) => session['name'] == selectedSession,
        orElse: () => {'id': -1},
      )['id'];
      filtered = filtered.where((r) => r['sessionId'] == selectedSessionId).toList();
    }

    if (_searchController.text.isNotEmpty) {
      final searchText = _searchController.text.toLowerCase();
      filtered = filtered.where((r) {
        final title = r['title'].toString().toLowerCase();
        final sessionName = r['sessionName'].toString().toLowerCase();

        return title.startsWith(searchText) ||
            title.contains(searchText) ||
            sessionName.startsWith(searchText) ||
            sessionName.contains(searchText);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LoadingWrapper(
      child: GestureDetector(
        onTap: () {
          // Retirer le focus lorsque l'utilisateur clique à l'extérieur
          FocusScope.of(context).unfocus();
        },
        child: Scaffold(
          body: Consumer<LoadingProvider>(
            builder: (context, loadingProvider, child) {
              if (loadingProvider.isLoading) {
                return const SizedBox.shrink(); // No background content during loading
              }
              if (isConnectionError) {
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
                          _initializeData();
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
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _buildSearchField(theme),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Text(
                          'Ressources',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (theme.textTheme.bodyLarge?.color ?? Colors.black87).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${filteredResources.length} résultat${filteredResources.length > 1 ? 's' : ''}',
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: !_hasLoadedData
                        ? const SizedBox.shrink() // Ne rien afficher tant que les données ne sont pas chargées
                        : filteredResources.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.folder_open,
                                      size: 64,
                                      color: theme.disabledColor,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Aucune ressource trouvée',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Aucun dossier partagé disponible pour le moment',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: theme.textTheme.bodyMedium?.color ?? Colors.grey[500],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: filteredResources.length,
                                itemBuilder: (context, index) {
                                  return _buildResourceCard(filteredResources[index], theme);
                                },
                              ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode, // Associer le FocusNode
      onChanged: (value) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Rechercher des ressources...',
        prefixIcon: Icon(Icons.search, color: theme.iconTheme.color),
        suffixIcon: IconButton(
          icon: Icon(Icons.clear, color: theme.iconTheme.color),
          onPressed: () {
            _searchController.clear();
            setState(() {});
            _searchFocusNode.unfocus(); // Retirer le focus lors de l'effacement
          },
        ),
        filled: true,
        fillColor: theme.cardColor.withOpacity(0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildTab(String label, bool isSelected, VoidCallback onTap, ThemeData theme) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : (label == 'Tous' ? theme.cardColor.withOpacity(0.3) : theme.cardColor.withOpacity(0.1)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? theme.colorScheme.onPrimary : theme.textTheme.bodyLarge?.color ?? Colors.black87,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildResourceCard(Map<String, dynamic> resource, ThemeData theme) {
    return GestureDetector(
      onTap: () {
        if (resource['type'] == 'Dossiers') {
          Navigator.push(
            context,
            ContentPageRoute(
              resource: resource,
            ),
          );
        } else {
          _openFileDirectly(resource);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (resource['color'] as Color).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (resource['color'] as Color).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Icon(
                resource['icon'],
                color: resource['color'],
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resource['title'],
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (resource['color'] as Color).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          resource['type'],
                          style: TextStyle(
                            color: resource['color'],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${resource['itemsCount']} élément${resource['itemsCount'] != '1' ? 's' : ''}',
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (resource['size'] != null && resource['size'] != 'Inconnu')
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storage, size: 14, color: theme.iconTheme.color?.withOpacity(0.5)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  resource['size'],
                                  style: TextStyle(
                                    color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (resource['size'] != null && resource['size'] != 'Inconnu') const SizedBox(width: 8),
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.access_time, size: 14, color: theme.iconTheme.color?.withOpacity(0.5)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                resource['time'],
                                style: TextStyle(
                                  color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.school, size: 14, color: theme.iconTheme.color?.withOpacity(0.5)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          resource['sessionName'],
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.cardColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.dividerColor,
                  width: 1,
                ),
              ),
              child: Icon(
                resource['type'] == 'Dossiers' ? Icons.folder_open : Icons.open_in_new,
                color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData getIconForType(String? type) {
  switch (type?.toUpperCase()) {
    case 'PDF':
      return Icons.picture_as_pdf;
    case 'VIDÉOS':
    case 'VIDEO':
      return Icons.videocam;
    case 'IMAGES':
    case 'IMAGE':
      return Icons.image;
    case 'AUDIO':
      return Icons.audiotrack;
    case 'DOSSIERS':
    case 'FOLDER':
      return Icons.folder;
    default:
      return Icons.insert_drive_file;
  }
}

Color getColorForType(String? type) {
  switch (type?.toUpperCase()) {
    case 'PDF':
      return const Color(0xFFB2DFDB);
    case 'VIDÉOS':
    case 'VIDEO':
      return const Color(0xFFF8BBD0);
    case 'IMAGES':
    case 'IMAGE':
      return const Color(0xFFDCE775);
    case 'AUDIO':
      return const Color(0xFFFFCC80);
    case 'DOSSIERS':
    case 'FOLDER':
      return const Color(0xFFFFCC80);
    default:
      return const Color(0xFFB3E5FC);
  }
}

class ContentPageRoute extends MaterialPageRoute {
  ContentPageRoute({required Map<String, dynamic> resource})
      : super(
    builder: (context) => FolderDetailsPage(
      folderId: resource['id'],
      folderName: resource['title'],
      folderSize: resource['size'] ?? 'Inconnu',
      folderTime: resource['time'] ?? 'Inconnu',
      folderItemsCount: resource['itemsCount'] ?? '0',
    ),
  );
}

class VideoPlayerScreen extends StatefulWidget {
  final String filePath;
  final bool isNetwork;

  const VideoPlayerScreen({super.key, required this.filePath, this.isNetwork = false});

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = widget.isNetwork
        ? VideoPlayerController.networkUrl(Uri.parse(widget.filePath))
        : VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
          _controller.play();
        }
      }).catchError((e) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Erreur lors du chargement de la vidéo: $e';
          });
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.appBarTheme.iconTheme?.color ?? Colors.white),
        title: Text(
          'Lecteur Vidéo',
          style: TextStyle(
            color: theme.appBarTheme.foregroundColor ?? Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF1A003D), Color(0xFF3C0D73)] // Dark mode gradient
                  : const [Color(0xFF8E2DE2), Color(0xFF4A00E0)], // Light mode gradient
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Center(
        child: _errorMessage != null
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
              child: const Text('Retour'),
            ),
          ],
        )
            : _isInitialized
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: theme.colorScheme.primary,
                  ),
                  onPressed: () {
                    if (mounted) {
                      setState(() {
                        if (_controller.value.isPlaying) {
                          _controller.pause();
                        } else {
                          _controller.play();
                        }
                      });
                    }
                  },
                ),
              ],
            ),
          ],
        )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class FolderDetailsPage extends StatefulWidget {
  final String folderId;
  final String folderName;
  final String folderSize;
  final String folderTime;
  final String folderItemsCount;

  const FolderDetailsPage({
    super.key,
    required this.folderId,
    required this.folderName,
    required this.folderSize,
    required this.folderTime,
    required this.folderItemsCount,
  });

  @override
  _FolderDetailsPageState createState() => _FolderDetailsPageState();
}

class _FolderDetailsPageState extends State<FolderDetailsPage> {
  final String apiUrl = 'https://www.unistudious.com';
  List<Map<String, dynamic>> resources = [];
  bool _isLoading = true;
  String selectedType = 'Tous';
  final List<String> typeTabs = ['Tous', 'PDF', 'Vidéos', 'Images', 'Audio', 'Dossiers'];
  final List<String> videoExtensions = ['.mp4']; // Seuls les MP4 sont pris en charge

  @override
  void initState() {
    super.initState();
    _fetchFolderDetails();
  }

  Future<void> _fetchFolderDetails() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      final response = await authProvider.authenticatedRequest(
        'GET',
        '/api/get-share-resource-folder-details/${widget.folderId}',
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            resources = [
              ...((jsonResponse['folders'] ?? []) as List<dynamic>).map((folder) {
                return {
                  'id': folder['id'],
                  'title': folder['name'] ?? 'Dossier sans nom',
                  'type': 'Dossiers',
                  'size': folder['totalSize'] != null ? '${folder['totalSize']} MB' : 'Inconnu',
                  'time': folder['createdAt'] ?? 'Inconnu',
                  'itemsCount': folder['itemsCount']?.toString() ?? '0',
                  'icon': getIconForType('Dossiers'),
                  'color': getColorForType('Dossiers'),
                };
              }).toList(),
              ...((jsonResponse['files'] ?? []) as List<dynamic>).map((file) {
                // Déterminer le type en fonction de l'extension si file['type'] est vide ou non standard
                String fileType = file['type']?.toUpperCase() ?? 'Inconnu';
                if (fileType == 'Inconnu' && file['name'] != null) {
                  final extension = path.extension(file['name']?.toLowerCase() ?? '');
                  if (videoExtensions.contains(extension)) {
                    fileType = 'VIDÉOS';
                  } else if (extension == '.pdf') {
                    fileType = 'PDF';
                  } else if (['.png', '.jpg', '.jpeg'].contains(extension)) {
                    fileType = 'IMAGES';
                  } else if (extension == '.mp3') {
                    fileType = 'AUDIO';
                  }
                }
                return {
                  'id': file['id'],
                  'title': file['name'] ?? 'Fichier sans nom',
                  'type': fileType,
                  'size': file['size'] != null ? '${file['size']} MB' : 'Inconnu',
                  'time': file['createdAt'] ?? 'Inconnu',
                  'itemsCount': '1',
                  'icon': getIconForType(fileType),
                  'color': getColorForType(fileType),
                };
              }).toList(),
            ];
          });
        }
      }
    } catch (e) {
      // Erreur silencieuse
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openFileDirectly(Map<String, dynamic> file) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);

    if (file['id'] == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur : Données manquantes.')),
        );
      }
      return;
    }

    final videoExtensions = ['.mp4'];
    bool isVideo = videoExtensions.any((ext) => file['title'].toLowerCase().endsWith(ext)) || file['type'].toUpperCase() == 'VIDÉOS';

    try {
      loadingProvider.showLoading();
      if (isVideo) {
        final response = await authProvider.authenticatedRequest(
          'POST',
          '/api/share-resource/read-file-video',
          body: json.encode({'id': file['id'].toString().trim()}),
        );

        if (response.statusCode == 200) {
          final body = response.body.trim();
          if (body.startsWith('<!doctype') || body.contains('<html') || body.contains('<body') || body.contains('Fatal error') || body.contains('<br />')) {
            String errorMessage = 'Erreur serveur: Problème de mémoire ou fichier non disponible.';
            if (body.contains('Allowed memory size')) {
              errorMessage = 'Erreur serveur: Mémoire insuffisante pour traiter le fichier. Veuillez contacter le support à kernalsiprod@gmail.com.';
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(errorMessage)),
              );
            }
            await _fetchFileFallback(file);
            return;
          }

          dynamic jsonResponse;
          try {
            jsonResponse = jsonDecode(response.body);
            if (jsonResponse is! Map<String, dynamic>) {
              throw const FormatException('Video API response is not a valid JSON object');
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Erreur: Réponse du serveur non valide (JSON invalide).')),
              );
            }
            await _fetchFileFallback(file);
            return;
          }

          final fileContent = jsonResponse;
          if (fileContent['link'] != null && fileContent['link'].toString().isNotEmpty) {
            final fileUrl = fileContent['link'].toString();
            try {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VideoPlayerScreen(filePath: fileUrl, isNetwork: true),
                ),
              );
            } catch (e) {
              if (await canLaunchUrl(Uri.parse(fileUrl))) {
                await launchUrl(Uri.parse(fileUrl), mode: LaunchMode.externalApplication);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Impossible d\'ouvrir ou diffuser la vidéo.')),
                  );
                }
              }
            }
            return;
          } else {
            await _fetchFileFallback(file);
            return;
          }
        } else {
          await _fetchFileFallback(file);
          return;
        }
      } else {
        await _fetchFileFallback(file);
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'ouverture de la vidéo: $e')),
        );
      }
      await _fetchFileFallback(file);
      return;
    } finally {
      loadingProvider.hideLoading();
    }
  }

  Future<void> _fetchFileFallback(Map<String, dynamic> file) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);

    try {
      loadingProvider.showLoading();
      final response = await authProvider.authenticatedRequest(
        'POST',
        '/api/share-resource/read-file',
        body: json.encode({'id': file['id'].toString().trim()}),
      );

      if (response.statusCode == 200) {
        final body = response.body.trim();
        if (body.startsWith('<!doctype') || body.contains('<html') || body.contains('<body') || body.contains('Fatal error') || body.contains('<br />')) {
          String errorMessage = 'Erreur serveur: Problème de mémoire ou fichier non disponible.';
          if (body.contains('Allowed memory size')) {
            errorMessage = 'Erreur serveur: Mémoire insuffisante pour traiter le fichier. Veuillez contacter le support à kernalsiprod@gmail.com.';
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errorMessage)),
            );
          }
          return;
        }

        dynamic jsonResponse;
        try {
          jsonResponse = jsonDecode(response.body);
          if (jsonResponse is! Map<String, dynamic>) {
            throw const FormatException('Response is not a valid JSON object');
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erreur: Réponse du serveur non valide (JSON invalide).')),
            );
          }
          return;
        }

        final fileContent = jsonResponse;
        final videoExtensions = ['.mp4'];
        final imageExtensions = ['.png', '.jpg', '.jpeg'];
        final audioExtensions = ['.mp3'];
        final fileTitle = (file['title'] ?? '').toString().toLowerCase();
        final fileType = (file['type'] ?? '').toString().toUpperCase();
        final bool isVideoMeta = videoExtensions.any((ext) => fileTitle.endsWith(ext)) || fileType == 'VIDÉOS' || fileType == 'VIDEO';
        final bool isPdfMeta = fileTitle.endsWith('.pdf') || fileType == 'PDF';
        final bool isImageMeta = imageExtensions.any((ext) => fileTitle.endsWith(ext)) || fileType == 'IMAGES' || fileType == 'IMAGE';
        final bool isAudioMeta = audioExtensions.any((ext) => fileTitle.endsWith(ext)) || fileType == 'AUDIO';

        if (fileContent['url'] != null && fileContent['url'].toString().isNotEmpty && isVideoMeta) {
          final fileUrl = fileContent['url'].toString();
          try {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoPlayerScreen(filePath: fileUrl, isNetwork: true),
              ),
            );
          } catch (e) {
            if (await canLaunchUrl(Uri.parse(fileUrl))) {
              await launchUrl(Uri.parse(fileUrl), mode: LaunchMode.externalApplication);
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Impossible d\'ouvrir ou diffuser la vidéo.')),
                );
              }
            }
          }
          return;
        }

        final String rawFileName = fileContent['fileName'] ?? file['title'].replaceAll(RegExp(r'[^\w\.]'), '_');
        final String fileName = _sanitizeFileName(path.basename(rawFileName));
        final String lowerFileName = fileName.toLowerCase();
        final bool isVideo = isVideoMeta || videoExtensions.any((ext) => lowerFileName.endsWith(ext));
        final bool isPdf = isPdfMeta || lowerFileName.endsWith('.pdf');
        final bool isImage = isImageMeta || imageExtensions.any((ext) => lowerFileName.endsWith(ext));
        final bool isAudio = isAudioMeta || audioExtensions.any((ext) => lowerFileName.endsWith(ext));
        final String base64Content = fileContent['content']?.toString() ?? '';

        if (base64Content.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Le contenu du fichier est vide.')),
            );
          }
          return;
        }

        if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(base64Content)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erreur: Le contenu du fichier n\'est pas un base64 valide.')),
            );
          }
          return;
        }

        late Uint8List contentBytes;
        try {
          contentBytes = await compute(base64Decode, base64Content);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur lors du décodage du fichier: $e')),
            );
          }
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';
        final tempFile = File(filePath);
        await tempFile.parent.create(recursive: true);
        await tempFile.writeAsBytes(contentBytes);

        if (!await tempFile.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erreur: Le fichier n\'a pas pu être créé.')),
            );
          }
          return;
        }

        loadingProvider.hideLoading();
        if (isVideo) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(filePath: filePath, isNetwork: false),
            ),
          );
          await tempFile.delete();
          return;
        }

        if (isPdf) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResourcePDFViewerScreen(filePath: filePath, fileName: fileName),
            ),
          );
          await tempFile.delete();
          return;
        }

        if (isImage) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResourceImageViewerScreen(filePath: filePath, fileName: fileName),
            ),
          );
          await tempFile.delete();
          return;
        }

        if (isAudio) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResourceAudioPlayerScreen(filePath: filePath, fileName: fileName),
            ),
          );
          await tempFile.delete();
          return;
        }

        final result = await OpenFile.open(filePath);
        if (result.type != ResultType.done) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur lors de l\'ouverture du fichier: ${result.message}')),
            );
          }
        }
        await tempFile.delete();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur lors du téléchargement du fichier: ${response.statusCode} - ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'ouverture du fichier: $e')),
        );
      }
    } finally {
      loadingProvider.hideLoading();
    }
  }

  String _sanitizeFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'[^\w\.]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }

  Widget _buildTab(String label, bool isSelected, VoidCallback onTap, ThemeData theme) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : (label == 'Tous' ? theme.cardColor.withOpacity(0.3) : theme.cardColor.withOpacity(0.1)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? theme.colorScheme.onPrimary : theme.textTheme.bodyLarge?.color ?? Colors.black87,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get filteredResources {
    List<Map<String, dynamic>> filtered = resources;

    if (selectedType != 'Tous') {
      if (selectedType == 'Vidéos') {
        // Filtrer les vidéos en tenant compte du type et des extensions
        filtered = filtered.where((r) {
          final isVideoType = r['type'].toString().toUpperCase() == 'VIDÉOS' || r['type'].toString().toUpperCase() == 'VIDEO';
          final isVideoExtension = r['title'] != null && videoExtensions.any((ext) => r['title'].toString().toLowerCase().endsWith(ext));
          return isVideoType || isVideoExtension;
        }).toList();
      } else {
        // Pour les autres types, filtrer directement sur r['type']
        filtered = filtered.where((r) => r['type'].toString().toUpperCase() == selectedType.toUpperCase()).toList();
      }
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LoadingWrapper(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: theme.appBarTheme.iconTheme?.color ?? Colors.white),
          title: Text(
            widget.folderName,
            style: TextStyle(
              color: theme.appBarTheme.foregroundColor ?? Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: theme.brightness == Brightness.dark
                    ? const [Color(0xFF1A003D), Color(0xFF3C0D73)] // Dark mode gradient
                    : const [Color(0xFF8E2DE2), Color(0xFF4A00E0)], // Light mode gradient
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        body: Consumer<LoadingProvider>(
          builder: (context, loadingProvider, child) {
            if (loadingProvider.isLoading) {
              return const SizedBox.shrink(); // No background content during loading
            }
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.primary.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.folder,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.folderName,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 16,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.storage, size: 14, color: theme.iconTheme.color?.withOpacity(0.5)),
                                      const SizedBox(width: 4),
                                      Text(
                                        widget.folderSize,
                                        style: TextStyle(
                                          color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.access_time, size: 14, color: theme.iconTheme.color?.withOpacity(0.5)),
                                      const SizedBox(width: 4),
                                      Text(
                                        widget.folderTime,
                                        style: TextStyle(
                                          color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.folder_open, size: 14, color: theme.iconTheme.color?.withOpacity(0.5)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${widget.folderItemsCount} élément${widget.folderItemsCount != '1' ? 's' : ''}',
                                        style: TextStyle(
                                          color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    color: theme.cardColor.withOpacity(0.2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: typeTabs
                            .map((tab) => _buildTab(tab, tab == selectedType, () {
                          setState(() {
                            selectedType = tab;
                          });
                        }, theme))
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Contenu du dossier',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : filteredResources.isEmpty
                        ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.folder_open,
                            size: 64,
                            color: theme.disabledColor,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Aucun contenu trouvé',
                            style: TextStyle(
                              fontSize: 18,
                              color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ce dossier ne contient aucun fichier correspondant au filtre',
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.textTheme.bodyMedium?.color ?? Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                        : ListView.builder(
                      itemCount: filteredResources.length,
                      itemBuilder: (context, index) {
                        final resource = filteredResources[index];
                        return GestureDetector(
                          onTap: () {
                            if (resource['type'] == 'Dossiers') {
                              Navigator.push(
                                context,
                                ContentPageRoute(
                                  resource: resource,
                                ),
                              );
                            } else {
                              _openFileDirectly(resource);
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.shadowColor.withOpacity(0.08),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              border: Border.all(
                                color: theme.dividerColor,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: (resource['color'] as Color).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: (resource['color'] as Color).withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    resource['icon'],
                                    color: resource['color'],
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        resource['title'],
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: (resource['color'] as Color).withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              resource['type'],
                                              style: TextStyle(
                                                color: resource['color'],
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (resource['size'] != null && resource['size'] != 'Inconnu') const SizedBox(width: 8),
                                          if (resource['size'] != null && resource['size'] != 'Inconnu')
                                            Text(
                                              resource['size'],
                                              style: TextStyle(
                                                color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.access_time, size: 14, color: theme.iconTheme.color?.withOpacity(0.5)),
                                          const SizedBox(width: 4),
                                          Text(
                                            resource['time'],
                                            style: TextStyle(
                                              color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: theme.cardColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: theme.dividerColor,
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    resource['type'] == 'Dossiers' ? Icons.folder_open : Icons.open_in_new,
                                    color: theme.textTheme.bodyMedium?.color ?? Colors.grey[600],
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}