import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/loading_provider.dart';
import '../models/app_bar_provider.dart';
import '../utils/snackbar_helper.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/loading_wrapper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:video_player/video_player.dart';
import '../widgets/sidebar.dart';
import 'dart:async';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'dart:developer' as developer;
import '../utils/connection_checker.dart';

class CourseDetailsPage extends StatefulWidget {
  const CourseDetailsPage({Key? key}) : super(key: key);

  @override
  _CourseDetailsPageState createState() => _CourseDetailsPageState();
}

class _CourseDetailsPageState extends State<CourseDetailsPage> with TickerProviderStateMixin {
  List<Map<String, dynamic>> academies = [];
  List<Map<String, dynamic>> courses = [];
  List<dynamic> chapters = [];
  List<dynamic> chapterParts = [];
  Map<String, dynamic> chapterDetails = {};
  String selectedAcademy = '';
  String selectedSessionId = '';
  String selectedCourseId = '';
  String selectedChapterId = '';
  int currentPage = 0;
  TabController? _tabController;
  bool isConnectionError = false;
  Timer? _connectionCheckTimer;

  // Theme-aware colors
  List<Color> getThemeColors(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? [
      Colors.deepPurple[400]!,
      Colors.teal[300]!,
      Colors.blue[300]!,
      Colors.amber[300]!,
      Colors.redAccent[200]!,
      Colors.green[300]!,
    ]
        : [
      Colors.deepPurple,
      Colors.teal,
      Colors.blue,
      Colors.amber,
      Colors.redAccent,
      Colors.green,
    ];
  }

  // Define poppins font family
  String get poppinsFontFamily => GoogleFonts.poppins().fontFamily ?? 'Roboto';

  @override
  void initState() {
    super.initState();
    _startConnectionMonitoring();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateAppBar();
      _checkAuthAndFetchData();
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
  
  void _updateAppBar() {
    if (!mounted) return;
    final appBarProvider = Provider.of<AppBarProvider>(context, listen: false);
    final theme = Theme.of(context);
    
    String title;
    Widget? leading;
    PreferredSizeWidget? bottom;
    
    if (currentPage == 0) {
      title = 'Mes cours';
      leading = Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      );
      if (academies.isNotEmpty && _tabController != null) {
        bottom = TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: academies.map((academy) => Tab(text: academy['name'])).toList(),
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: TextStyle(
            fontFamily: poppinsFontFamily,
            fontWeight: FontWeight.w600,
          ),
          onTap: (index) {
            setState(() {
              fetchCourses(academies[index]['id'].toString());
            });
          },
        );
      }
    } else if (currentPage == 1) {
      title = 'Cours de $selectedAcademy';
      leading = IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        onPressed: goBack,
      );
    } else if (currentPage == 2) {
      title = 'Chapitres';
      leading = IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        onPressed: goBack,
      );
    } else if (currentPage == 3) {
      title = 'Titres du chapitre';
      leading = IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        onPressed: goBack,
      );
    } else {
      title = 'Détails du chapitre';
      leading = IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        onPressed: goBack,
      );
    }
    
    appBarProvider.updateConfig(1, AppBarConfig(
      title: title,
      leading: leading,
      bottom: bottom,
    ));
  }

  @override
  void dispose() {
    _connectionCheckTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _checkAuthAndFetchData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);

    if (!authProvider.isLoggedIn) {
      if (mounted) {
        SnackBarHelper.showWarning(context, 'Veuillez vous connecter pour continuer.');
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }

    loadingProvider.showLoading();
    try {
      await fetchAcademies();
    } catch (e) {
      if (mounted) {
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
          } else {
            isConnectionError = false;
            SnackBarHelper.showError(context, 'Erreur lors du chargement des données: $e');
          }
        });
      }
    } finally {
      loadingProvider.hideLoading();
    }
  }

  Future<void> _refresh() async {
    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);
    loadingProvider.showLoading();
    try {
      if (currentPage == 0) {
        await fetchAcademies();
      } else if (currentPage == 1 && selectedSessionId.isNotEmpty) {
        await fetchCourses(selectedSessionId);
      } else if (currentPage == 2 && selectedCourseId.isNotEmpty) {
        await fetchChapters(selectedCourseId);
      } else if (currentPage == 3 && selectedChapterId.isNotEmpty) {
        await fetchChapterParts(selectedChapterId);
      } else if (currentPage == 4 && selectedChapterId.isNotEmpty) {
        await fetchChapterDetails(selectedChapterId);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors du rafraîchissement: $e');
      }
    } finally {
      loadingProvider.hideLoading();
    }
  }

  Future<void> fetchAcademies() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    setState(() {
      isConnectionError = false;
    });
    
    try {
      developer.log('Fetching academies', name: 'CourseDetailsPage');
      final response = await authProvider.authenticatedRequest('GET', '/api/user/get-session');
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final courseResponse = await authProvider.authenticatedRequest('GET', '/api/list-course');
        if (!mounted) return;

        if (courseResponse.statusCode == 200) {
          final courseData = json.decode(courseResponse.body);
          final allCourses = courseData['courses'] as List<dynamic>? ?? [];

          setState(() {
            academies = (data['sessions'] as List<dynamic>?)?.asMap().entries.map((entry) {
              int index = entry.key;
              var session = entry.value;
              final courseCount = allCourses
                  .where((course) =>
              (course['sessions'] as List<dynamic>?)?.any((s) => s['id'].toString() == session['id'].toString()) ?? false)
                  .length;
              return {
                'name': session['name'] ?? 'Session',
                'id': session['id'].toString(),
                'courses': courseCount,
                'color': getThemeColors(context)[index % getThemeColors(context).length],
              };
            }).toList() ??
                [];
            _tabController?.dispose();
            _tabController = TabController(length: academies.length, vsync: this);
            isConnectionError = false;
          });
          _updateAppBar();
          developer.log('Fetched ${academies.length} academies', name: 'CourseDetailsPage');
          await fetchCourses('');
        } else {
          setState(() {
            academies = [];
            isConnectionError = false;
          });
          _showError('Erreur lors du chargement des cours: ${courseResponse.statusCode}');
        }
      } else {
        setState(() {
          academies = [];
          isConnectionError = false;
        });
        _showError('Erreur lors du chargement des sessions: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
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
          } else {
            isConnectionError = false;
            _showError('Erreur lors du chargement des sessions: $e');
          }
        });
      }
    }
  }

  Future<void> fetchCourses(String sessionId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      developer.log('Fetching courses for sessionId: $sessionId', name: 'CourseDetailsPage');
      final uri = Uri.parse('/api/list-course${sessionId.isNotEmpty ? '?sessionId=$sessionId' : ''}');
      final response = await authProvider.authenticatedRequest('GET', uri.toString());
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final allCourses = data['courses'] as List<dynamic>? ?? [];
        List<Map<String, dynamic>> filteredCourses = [];

        if (sessionId.isNotEmpty) {
          final selectedSession = academies.firstWhere(
                (academy) => academy['id'] == sessionId,
            orElse: () => {'name': 'Session sélectionnée', 'color': getThemeColors(context)[0]},
          );
          filteredCourses = allCourses
              .where((course) =>
          (course['sessions'] as List<dynamic>?)?.any((s) => s['id'].toString() == sessionId) ?? false)
              .map((course) => {
            'course': course,
            'sessionId': sessionId,
            'sessionName': selectedSession['name'],
            'formationName': (course['sessions'] as List<dynamic>?)?.firstWhere(
                  (s) => s['id'].toString() == sessionId,
              orElse: () => {'formationName': 'Session'},
            )['formationName'] ??
                'Session',
            'color': selectedSession['color'],
          })
              .toList();
          setState(() {
            courses = filteredCourses;
            selectedAcademy = selectedSession['name'];
            selectedSessionId = sessionId;
            currentPage = 1;
            chapters = [];
            chapterParts = [];
            chapterDetails = {};
          });
          _updateAppBar();
        } else {
          filteredCourses = allCourses.expand((course) {
            final sessions = course['sessions'] as List<dynamic>? ?? [];
            return sessions.map((session) {
              final sessionId = session['id'].toString();
              final matchingAcademy = academies.firstWhere(
                    (academy) => academy['id'] == sessionId,
                orElse: () => {
                  'name': session['name'] ?? 'Session',
                  'color': getThemeColors(context)[0],
                },
              );
              return {
                'course': course,
                'sessionId': sessionId,
                'sessionName': matchingAcademy['name'],
                'formationName': session['formationName'] ?? 'Session',
                'color': matchingAcademy['color'],
              };
            });
          }).toList();
          setState(() {
            courses = filteredCourses;
            selectedSessionId = '';
            chapters = [];
            chapterParts = [];
            chapterDetails = {};
          });
        }
        developer.log('Fetched ${courses.length} courses', name: 'CourseDetailsPage');
      } else {
        setState(() {
          courses = [];
        });
        _showError('Erreur lors du chargement des cours: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
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
          } else {
            isConnectionError = false;
            _showError('Erreur lors du chargement des cours: $e');
          }
        });
      }
    }
  }

  Future<void> fetchChapters(String courseId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      developer.log('Fetching chapters for courseId: $courseId', name: 'CourseDetailsPage');
      final response = await authProvider.authenticatedRequest('GET', '/api/list-chapter/$courseId');
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          chapters = data['chapters'] as List<dynamic>? ?? [];
          selectedCourseId = courseId;
          chapterParts = [];
          chapterDetails = {};
          currentPage = 2;
        });
        _updateAppBar();
        developer.log('Fetched ${chapters.length} chapters', name: 'CourseDetailsPage');
      } else {
        setState(() {
          chapters = [];
        });
        _showError('Erreur lors du chargement des chapitres: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
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
          } else {
            isConnectionError = false;
            _showError('Erreur lors du chargement des chapitres: $e');
          }
        });
      }
    }
  }

  Future<void> fetchChapterParts(String chapterId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      developer.log('Fetching chapter parts for chapterId: $chapterId', name: 'CourseDetailsPage');
      final response = await authProvider.authenticatedRequest('GET', '/api/get-chapter-part/$chapterId');
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final detailsResponse = await authProvider.authenticatedRequest(
          'GET',
          'https://www.unistudious.com/api/chapter-details/$chapterId',
        );
        if (!mounted) return;

        if (detailsResponse.statusCode == 200) {
          final detailsData = json.decode(detailsResponse.body);
          setState(() {
            chapterParts = data['chapterParts'] as List<dynamic>? ?? [];
            chapterDetails = detailsData ?? {};
            selectedChapterId = chapterId;
            currentPage = 3;
          });
          _updateAppBar();
          developer.log('Fetched ${chapterParts.length} chapter parts', name: 'CourseDetailsPage');
        } else {
          setState(() {
            chapterParts = [];
            chapterDetails = {};
          });
          _showError('Erreur lors du chargement des détails: ${detailsResponse.statusCode}');
        }
      } else {
        setState(() {
          chapterParts = [];
        });
        _showError('Erreur lors du chargement des parties de chapitre: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
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
          } else {
            isConnectionError = false;
            _showError('Erreur lors du chargement des parties de chapitre: $e');
          }
        });
      }
    }
  }

  Future<void> fetchChapterDetails(String chapterId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      developer.log('Fetching chapter details for chapterId: $chapterId', name: 'CourseDetailsPage');
      final response = await authProvider.authenticatedRequest(
        'GET',
        'https://www.unistudious.com/api/chapter-details/$chapterId',
      );
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          chapterDetails = data ?? {};
          selectedChapterId = chapterId;
          currentPage = 4;
        });
        _updateAppBar();
        developer.log('Fetched chapter details', name: 'CourseDetailsPage');
      } else {
        setState(() {
          chapterDetails = {};
        });
        _showError('Erreur lors du chargement des détails du chapitre: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
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
          } else {
            isConnectionError = false;
            _showError('Erreur lors du chargement des détails du chapitre: $e');
          }
        });
      }
    }
  }

  Future<void> _openFile(String resourceId, String resourceName, {int retryCount = 0, int maxRetries = 2}) async {
    if (resourceId.isEmpty) {
      _showError('Identifiant de ressource invalide.');
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);
    loadingProvider.showLoading();
    developer.log('Attempting to open file: $resourceName, id: $resourceId', name: 'OpenFile');

    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.wmv'];
    final pdfExtensions = ['.pdf'];
    final isVideo = videoExtensions.any((ext) => resourceName.toLowerCase().endsWith(ext));
    final isPdf = pdfExtensions.any((ext) => resourceName.toLowerCase().endsWith(ext));

    try {
      if (isVideo) {
        final response = await authProvider.authenticatedRequest(
          'POST',
          'https://www.unistudious.com/api/share-resource/read-file-video',
          body: json.encode({'id': resourceId.trim()}),
        );
        if (!mounted) return;

        if (response.statusCode == 200) {
          final body = response.body.trim();
          if (_isInvalidResponse(body)) {
            String errorMessage = 'Erreur serveur: Problème de mémoire ou fichier non disponible.';
            if (body.contains('Allowed memory size')) {
              errorMessage = 'Erreur serveur: Mémoire insuffisante pour traiter le fichier. Veuillez contacter le support à kernalsiprod@gmail.com.';
            }
            _showError(errorMessage);
            await _fetchFileFallback(resourceId, resourceName, retryCount: retryCount);
            return;
          }

          final jsonResponse = _parseJsonResponse(body);
          if (jsonResponse == null) {
            _showError('Erreur: Réponse du serveur non valide (JSON invalide).');
            await _fetchFileFallback(resourceId, resourceName, retryCount: retryCount);
            return;
          }

          final fileUrl = jsonResponse['link']?.toString();
          if (fileUrl != null && fileUrl.isNotEmpty) {
            loadingProvider.hideLoading();
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
                _showError('Impossible d\'ouvrir ou diffuser la vidéo.');
              }
            }
          } else {
            await _fetchFileFallback(resourceId, resourceName, retryCount: retryCount);
          }
        } else {
          await _fetchFileFallback(resourceId, resourceName, retryCount: retryCount);
        }
      } else {
        final response = await authProvider.authenticatedRequest(
          'POST',
          'https://www.unistudious.com/api/share-resource/read-file',
          body: json.encode({'id': resourceId.trim()}),
        );
        if (!mounted) return;

        if (response.statusCode == 200) {
          final body = response.body.trim();
          if (_isInvalidResponse(body)) {
            String errorMessage = 'Erreur serveur: Problème de mémoire ou fichier non disponible.';
            if (body.contains('Allowed memory size')) {
              errorMessage = 'Erreur serveur: Mémoire insuffisante pour traiter le fichier. Veuillez contacter le support à kernalsiprod@gmail.com.';
            }
            _showError(errorMessage);
            return;
          }

          final jsonResponse = _parseJsonResponse(body);
          if (jsonResponse == null) {
            _showError('Erreur: Réponse du serveur non valide (JSON invalide).');
            return;
          }

          final fileName = sanitizeFileName(jsonResponse['fileName'] ?? resourceName);
          final base64Content = jsonResponse['content']?.toString() ?? '';

          if (base64Content.isEmpty) {
            _showError('Le contenu du fichier est vide.');
            return;
          }

          if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(base64Content)) {
            _showError('Erreur: Le contenu du fichier n\'est pas un base64 valide.');
            return;
          }

          late List<int> contentBytes;
          try {
            contentBytes = base64Decode(base64Content);
          } catch (e) {
            _showError('Erreur lors du décodage du fichier: $e');
            return;
          }

          final tempDir = await getTemporaryDirectory();
          final filePath = '${tempDir.path}/$fileName';
          final tempFile = File(filePath);
          await tempFile.parent.create(recursive: true);
          await tempFile.writeAsBytes(contentBytes);

          if (!await tempFile.exists()) {
            _showError('Erreur: Le fichier n\'a pas pu être créé.');
            return;
          }

          loadingProvider.hideLoading();
          if (isPdf) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PDFViewerScreen(filePath: filePath, fileName: fileName),
              ),
            );
            await tempFile.delete();
          } else {
            final result = await OpenFile.open(filePath);
            if (result.type != ResultType.done) {
              _showError('Erreur lors de l\'ouverture du fichier: ${result.message}');
            }
            await tempFile.delete();
          }
        } else {
          _handleApiError(response.statusCode, () => _openFile(resourceId, resourceName));
        }
      }
    } catch (e) {
      _showError('Erreur lors de l\'ouverture du fichier: $e', retry: () => _openFile(resourceId, resourceName));
    } finally {
      loadingProvider.hideLoading();
    }
  }

  Future<void> _fetchFileFallback(String resourceId, String resourceName, {int retryCount = 0, int maxRetries = 2}) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);
    try {
      final response = await authProvider.authenticatedRequest(
        'POST',
        'https://www.unistudious.com/api/share-resource/read-file',
        body: json.encode({'id': resourceId.trim()}),
      );
      if (!mounted) return;

      if (response.statusCode == 200) {
        final body = response.body.trim();
        if (_isInvalidResponse(body)) {
          String errorMessage = 'Erreur serveur: Problème de mémoire ou fichier non disponible.';
          if (body.contains('Allowed memory size')) {
            errorMessage = 'Erreur serveur: Mémoire insuffisante pour traiter le fichier. Veuillez contacter le support à kernalsiprod@gmail.com.';
          }
          if (retryCount < maxRetries) {
            await Future.delayed(const Duration(seconds: 2));
            await _fetchFileFallback(resourceId, resourceName, retryCount: retryCount + 1);
            return;
          }
          _showError(errorMessage, retry: () => _openFile(resourceId, resourceName));
          return;
        }

        final jsonResponse = _parseJsonResponse(body);
        if (jsonResponse == null) {
          _showError('Erreur: Réponse du serveur non valide (JSON invalide).');
          return;
        }

        final fileName = sanitizeFileName(jsonResponse['fileName'] ?? resourceName);
        final isVideo = ['.mp4', '.mov', '.avi', '.mkv', '.wmv'].any((ext) => fileName.toLowerCase().endsWith(ext));
        final isPdf = fileName.toLowerCase().endsWith('.pdf');
        final fileUrl = jsonResponse['url']?.toString();
        final base64Content = jsonResponse['content']?.toString() ?? '';

        if (fileUrl != null && fileUrl.isNotEmpty && isVideo) {
          loadingProvider.hideLoading();
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
              _showError('Impossible d\'ouvrir ou diffuser la vidéo.');
            }
          }
          return;
        }

        if (base64Content.isEmpty) {
          _showError('Le contenu du fichier est vide.');
          return;
        }

        if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(base64Content)) {
          _showError('Erreur: Le contenu du fichier n\'est pas un base64 valide.');
          return;
        }

        late List<int> contentBytes;
        try {
          contentBytes = base64Decode(base64Content);
        } catch (e) {
          _showError('Erreur lors du décodage du fichier: $e');
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';
        final tempFile = File(filePath);
        await tempFile.parent.create(recursive: true);
        await tempFile.writeAsBytes(contentBytes);

        if (!await tempFile.exists()) {
          _showError('Erreur: Le fichier n\'a pas pu être créé.');
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
        } else if (isPdf) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PDFViewerScreen(filePath: filePath, fileName: fileName),
            ),
          );
          await tempFile.delete();
        } else {
          final result = await OpenFile.open(filePath);
          if (result.type != ResultType.done) {
            _showError('Erreur lors de l\'ouverture du fichier: ${result.message}');
          }
          await tempFile.delete();
        }
      } else {
        _handleApiError(response.statusCode, () => _openFile(resourceId, resourceName));
      }
    } catch (e) {
      _showError('Erreur lors de l\'ouverture du fichier: $e', retry: () => _openFile(resourceId, resourceName));
    } finally {
      loadingProvider.hideLoading();
    }
  }

  bool _isInvalidResponse(String body) {
    return body.startsWith('<!doctype') ||
        body.contains('<html') ||
        body.contains('<body') ||
        body.contains('Fatal error') ||
        body.contains('<br />');
  }

  Map<String, dynamic>? _parseJsonResponse(String body) {
    try {
      final jsonResponse = json.decode(body);
      if (jsonResponse is Map<String, dynamic>) {
        return jsonResponse;
      }
      return null;
    } catch (e) {
      developer.log('JSON parsing error: $e', name: 'CourseDetailsPage');
      return null;
    }
  }

  void _showError(String message, {VoidCallback? retry}) {
    if (mounted) {
      // Détecter les erreurs de connexion et ne pas afficher de snackbar
      final isNetworkError = message.contains('SocketException') ||
                             message.contains('Failed host lookup') ||
                             message.contains('Network is unreachable') ||
                             message.contains('Connection refused') ||
                             message.contains('Connection timed out') ||
                             message.contains('No Internet connection') ||
                             message.contains('ClientException') ||
                             message.contains('OS Error');
      
      // Ne pas afficher de snackbar pour les erreurs de connexion
      if (!isNetworkError) {
        SnackBarHelper.showError(context, message);
      }
    }
  }

  void _handleApiError(int statusCode, VoidCallback retry) {
    if (statusCode == 401 || statusCode == 403) {
      if (mounted) {
        SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
        Navigator.pushReplacementNamed(context, '/login');
      }
    } else {
      _showError('Erreur lors du téléchargement du fichier: $statusCode', retry: retry);
    }
  }

  String sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^\w\.]'), '_').replaceAll(RegExp(r'\s+'), '_').trim();
  }

  void goBack() {
    setState(() {
      if (currentPage == 1) {
        currentPage = 0;
        selectedAcademy = '';
        selectedSessionId = '';
        selectedCourseId = '';
        selectedChapterId = '';
        chapters = [];
        chapterParts = [];
        chapterDetails = {};
        fetchCourses('');
      } else if (currentPage == 2) {
        currentPage = 1;
        selectedCourseId = '';
        selectedChapterId = '';
        chapters = [];
        chapterParts = [];
        chapterDetails = {};
        if (selectedSessionId.isNotEmpty) {
          fetchCourses(selectedSessionId);
        }
      } else if (currentPage == 3) {
        currentPage = 2;
        selectedChapterId = '';
        chapterParts = [];
        chapterDetails = {};
        fetchChapters(selectedCourseId);
      } else if (currentPage == 4) {
        currentPage = 3;
        fetchChapterParts(selectedChapterId);
      }
    });
    _updateAppBar();
  }

  Widget buildChapterParts(List<dynamic> parts, Map<String, dynamic> chapterRelations) {
    final theme = Theme.of(context);
    final themeColors = getThemeColors(context);

    List<Map<String, dynamic>> flattenedParts = [];
    void flattenParts(List<dynamic> currentParts) {
      for (var part in currentParts) {
        flattenedParts.add({
          'id': part['id'].toString(),
          'title': part['title'] ?? 'Titre',
          'progress': (part['progress'] ?? 0).toDouble(),
          'resources': (chapterRelations[part['id'].toString()] as List<dynamic>? ?? []),
        });
        if (part['children'] != null && part['children'].isNotEmpty) {
          flattenParts(part['children']);
        }
      }
    }

    flattenParts(parts);

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: flattenedParts.length,
      itemBuilder: (context, index) {
        final part = flattenedParts[index];
        final resources = part['resources'] as List<dynamic>;
        final hasResources = resources.isNotEmpty;
        final isVideo = hasResources &&
            resources.any((r) => ['.mp4', '.mov', '.avi', '.mkv', '.wmv'].any((ext) => (r['resourceName']?.toString().toLowerCase() ?? '').endsWith(ext)));
        final progress = part['progress'];

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          color: theme.cardColor,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
            leading: Container(
              width: 4,
              height: 40,
              color: themeColors[index % themeColors.length],
            ),
            title: Text(
              part['title'],
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: poppinsFontFamily,
              ) ?? TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: poppinsFontFamily,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasResources)
                  Wrap(
                    spacing: 8,
                    children: resources.map((resource) {
                      final resId = resource['resourceId']?.toString().trim() ?? '';
                      final resName = resource['resourceName']?.toString() ?? 'document';
                      final isResVideo = ['.mp4', '.mov', '.avi', '.mkv', '.wmv'].any((ext) => resName.toLowerCase().endsWith(ext));
                      final isResPdf = ['.pdf'].any((ext) => resName.toLowerCase().endsWith(ext));
                      return GestureDetector(
                        onTap: resId.isNotEmpty ? () async => await _openFile(resId, resName) : null,
                        child: Chip(
                          label: Text(
                            resName,
                            style: theme.textTheme.bodySmall?.copyWith(fontFamily: poppinsFontFamily),
                          ),
                          backgroundColor: isResVideo
                              ? Colors.redAccent[100]
                              : isResPdf
                              ? Colors.blue[100]
                              : Colors.grey[100],
                          avatar: Icon(
                            isResVideo
                                ? Icons.videocam
                                : isResPdf
                                ? Icons.picture_as_pdf
                                : Icons.description,
                            size: 16,
                            color: isResVideo
                                ? Colors.redAccent
                                : isResPdf
                                ? Colors.blue
                                : Colors.grey,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                if (progress > 0) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress / 100,
                    backgroundColor: theme.dividerColor,
                    valueColor: AlwaysStoppedAnimation<Color>(themeColors[index % themeColors.length]),
                    minHeight: 4,
                  ),
                ],
              ],
            ),
            trailing: hasResources ? const Icon(Icons.attach_file, color: Colors.grey) : null,
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeColors = getThemeColors(context);

    // Afficher le message de connexion si erreur réseau
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
                if (currentPage == 0) {
                  fetchAcademies();
                } else if (currentPage == 1 && selectedSessionId.isNotEmpty) {
                  fetchCourses(selectedSessionId);
                } else if (currentPage == 2 && selectedCourseId.isNotEmpty) {
                  fetchChapters(selectedCourseId);
                } else if (currentPage == 3 && selectedChapterId.isNotEmpty) {
                  fetchChapterParts(selectedChapterId);
                } else if (currentPage == 4 && selectedChapterId.isNotEmpty) {
                  fetchChapterDetails(selectedChapterId);
                }
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

    if (currentPage == 0) {
      if (courses.isEmpty) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height / 2),
            Center(),
          ],
        );
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 20),
          Text(
            'Mes cours en cours',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontFamily: poppinsFontFamily,
            ) ?? TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: poppinsFontFamily,
            ),
          ),
          const SizedBox(height: 12),
          ...courses.map<Widget>((courseData) {
            final course = courseData['course'];
            final color = courseData['color'] as Color;
            final progress = (course['percentage'] ?? 0).toDouble();
            final description = course['description'] ?? 'Aucune description';
            final nbHours = course['nbHours'] ?? 'Non spécifié';
            final formationName = courseData['formationName'] ?? 'Session';
            final sessionId = courseData['sessionId'].toString();

            return GestureDetector(
              onTap: () {
                setState(() {
                  selectedAcademy = courseData['sessionName'];
                  selectedSessionId = sessionId;
                  currentPage = 1;
                });
                _updateAppBar();
                fetchCourses(sessionId);
              },
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                color: theme.cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 24,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              formationName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w600,
                                fontFamily: poppinsFontFamily,
                              ) ?? TextStyle(
                                color: color,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                fontFamily: poppinsFontFamily,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        course['name'] ?? 'Titre du cours',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontFamily: poppinsFontFamily,
                        ) ?? TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: poppinsFontFamily,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Description: $description',
                        style: theme.textTheme.bodyMedium?.copyWith(fontFamily: poppinsFontFamily),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Durée: $nbHours',
                        style: theme.textTheme.bodyMedium?.copyWith(fontFamily: poppinsFontFamily),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Progression',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontFamily: poppinsFontFamily,
                        ) ?? TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: poppinsFontFamily,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress / 100,
                          backgroundColor: theme.dividerColor,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ],
      );
    } else if (currentPage == 1) {
      if (courses.isEmpty) {
        return Center(
          child: Text(
            'Aucun cours disponible pour cette session',
            style: theme.textTheme.bodyLarge?.copyWith(fontFamily: poppinsFontFamily),
            textAlign: TextAlign.center,
          ),
        );
      }
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: courses.length,
        itemBuilder: (context, index) {
          final courseData = courses[index];
          final course = courseData['course'];
          final color = courseData['color'] as Color;
          final description = course['description'] ?? 'Aucune description';
          final nbHours = course['nbHours'] ?? 'Non spécifié';

          return Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: theme.cardColor,
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                backgroundColor: color,
                child: const Icon(Icons.menu_book, color: Colors.white, size: 24),
              ),
              title: Text(
                course['name'] ?? 'Cours',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: poppinsFontFamily,
                ) ?? TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: poppinsFontFamily,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    'Progression: ${course['percentage'] ?? 0}%',
                    style: theme.textTheme.bodyMedium?.copyWith(fontFamily: poppinsFontFamily),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Description: $description',
                    style: theme.textTheme.bodyMedium?.copyWith(fontFamily: poppinsFontFamily),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Durée: $nbHours',
                    style: theme.textTheme.bodyMedium?.copyWith(fontFamily: poppinsFontFamily),
                  ),
                ],
              ),
              onTap: () {
                fetchChapters(course['id'].toString());
              },
            ),
          );
        },
      );
    } else if (currentPage == 2) {
      if (chapters.isEmpty) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height / 2),
            Center(
              child: Text(
                'Aucun chapitre disponible',
                style: theme.textTheme.bodyLarge?.copyWith(fontFamily: poppinsFontFamily),
              ),
            ),
          ],
        );
      }
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: chapters.length,
        itemBuilder: (context, index) {
          final chapter = chapters[index];
          return Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: theme.cardColor,
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                backgroundColor: themeColors[index % themeColors.length],
                child: const Icon(Icons.list_alt, color: Colors.white, size: 24),
              ),
              title: Text(
                chapter['title'] ?? 'Chapitre',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: poppinsFontFamily,
                ) ?? TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: poppinsFontFamily,
                ),
              ),
              subtitle: Text(
                'Progression: ${chapter['progress'] ?? 0}%',
                style: theme.textTheme.bodyMedium?.copyWith(fontFamily: poppinsFontFamily),
              ),
              trailing: IconButton(
                icon: Icon(Icons.info, color: theme.primaryColor),
                onPressed: () {
                  fetchChapterDetails(chapter['id'].toString());
                },
              ),
              onTap: () {
                fetchChapterParts(chapter['id'].toString());
              },
            ),
          );
        },
      );
    } else if (currentPage == 3 && chapterParts.isNotEmpty) {
      return buildChapterParts(chapterParts, chapterDetails['chapterRelations'] ?? {});
    } else if (currentPage == 4 && chapterDetails.isNotEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 20),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: theme.cardColor,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapterDetails['title'] ?? 'Titre du Chapitre',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: poppinsFontFamily,
                    ) ?? TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: poppinsFontFamily,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return const SizedBox();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeColors = getThemeColors(context);

    return LoadingWrapper(
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required String title, required String subtitle, required Color color, IconData? icon}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null)
              Icon(
                icon,
                color: color,
                size: 24,
              ),
            const SizedBox(height: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: poppinsFontFamily,
              ) ?? TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: poppinsFontFamily,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(fontFamily: poppinsFontFamily),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String filePath;
  final bool isNetwork;

  const VideoPlayerScreen({Key? key, required this.filePath, this.isNetwork = false}) : super(key: key);

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
    developer.log('Initializing VideoPlayerScreen for path: ${widget.filePath}, isNetwork: ${widget.isNetwork}', name: 'VideoPlayerScreen');
    _controller = widget.isNetwork
        ? VideoPlayerController.networkUrl(Uri.parse(widget.filePath))
        : VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
          _controller.play();
          developer.log('Video initialized successfully', name: 'VideoPlayerScreen');
        }
      }).catchError((e) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Erreur lors du chargement de la vidéo: $e';
          });
          developer.log('Error initializing video: $e', name: 'VideoPlayerScreen');
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    developer.log('VideoPlayerScreen disposed', name: 'VideoPlayerScreen');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Lecteur Vidéo',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
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
      ),
      body: Center(
        child: _errorMessage != null
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              style: GoogleFonts.poppins(
                color: isDark ? Colors.red[400] : Colors.red[700],
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Retour',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
              ),
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
                    color: theme.primaryColor,
                    size: 36,
                  ),
                  onPressed: () {
                    setState(() {
                      if (_controller.value.isPlaying) {
                        _controller.pause();
                      } else {
                        _controller.play();
                      }
                    });
                  },
                ),
              ],
            ),
          ],
        )
            : CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor)),
      ),
    );
  }
}

class PDFViewerScreen extends StatelessWidget {
  final String filePath;
  final String fileName;

  const PDFViewerScreen({Key? key, required this.filePath, required this.fileName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          fileName,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
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
        child: PDFView(
          filePath: filePath,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          onError: (error) {
            developer.log('Error loading PDF: $error', name: 'PDFViewer');
            SnackBarHelper.showError(context, 'Erreur lors du chargement du PDF: $error');
          },
          onRender: (pages) {
            developer.log('PDF rendered with $pages pages', name: 'PDFViewer');
          },
          onPageError: (page, error) {
            developer.log('Error on page $page: $error', name: 'PDFViewer');
            SnackBarHelper.showError(context, 'Erreur sur la page $page: $error');
          },
        ),
      ),
    );
  }
}