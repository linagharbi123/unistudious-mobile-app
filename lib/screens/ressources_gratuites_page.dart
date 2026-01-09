import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:clipboard/clipboard.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/sidebar.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'dart:io' as io;

class Course {
  final int id;
  final String name;
  final String type;
  final CreatedAt createdAt;
  final Account account;
  final String image;
  final List<Tag> tags;
  final List<Subject> subjects;

  Course({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    required this.account,
    required this.image,
    required this.tags,
    required this.subjects,
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'N/A',
      type: json['type'] ?? 'N/A',
      createdAt: CreatedAt.fromJson(json['createdAt'] ?? {}),
      account: Account.fromJson(json['account'] ?? {}),
      image: json['image'] ?? '',
      tags: (json['tags'] as List<dynamic>? ?? []).map((tag) => Tag.fromJson(tag)).toList(),
      subjects: (json['subjects'] as List<dynamic>? ?? []).map((subject) => Subject.fromJson(subject)).toList(),
    );
  }
}

class CreatedAt {
  final String date;
  final int timezoneType;
  final String timezone;

  CreatedAt({
    required this.date,
    required this.timezoneType,
    required this.timezone,
  });

  factory CreatedAt.fromJson(Map<String, dynamic> json) {
    return CreatedAt(
      date: json['date'] ?? '',
      timezoneType: json['timezone_type'] ?? 0,
      timezone: json['timezone'] ?? '',
    );
  }
}

class Account {
  final int id;
  final String name;
  final String type;
  final String image;

  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.image,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'N/A',
      type: json['type'] ?? 'N/A',
      image: json['image'] ?? '',
    );
  }
}

class Tag {
  final int id;
  final String name;

  Tag({required this.id, required this.name});

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'N/A',
    );
  }
}

class Subject {
  final int id;
  final String name;

  Subject({required this.id, required this.name});

  factory Subject.fromJson(Map<String, dynamic> json) {
    return Subject(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'N/A',
    );
  }
}

class CourseDetails {
  final String relativeFolderPath;
  final List<Folder> folders;
  final List<ResourceFile> files;
  final String url;
  final List<Subject> subjects;
  final Map<String, dynamic> allTags;

  CourseDetails({
    required this.relativeFolderPath,
    required this.folders,
    required this.files,
    required this.url,
    required this.subjects,
    required this.allTags,
  });

  factory CourseDetails.fromJson(Map<String, dynamic> json) {
    return CourseDetails(
      relativeFolderPath: json['allData']?['relativeFolderPath'] ?? '',
      folders: (json['allData']?['folders'] as List<dynamic>? ?? []).map((folder) => Folder.fromJson(folder)).toList(),
      files: (json['allData']?['files'] as List<dynamic>? ?? []).map((file) => ResourceFile.fromJson(file)).toList(),
      url: json['allData']?['url'] ?? '',
      subjects: (json['subjects'] as List<dynamic>? ?? []).map((subject) => Subject.fromJson(subject)).toList(),
      allTags: json['allTags'] ?? {},
    );
  }
}

class Folder {
  final String name;
  final String url;
  final bool isFolder;
  final String cleanId;

  Folder({
    required this.name,
    required this.url,
    required this.isFolder,
    required this.cleanId,
  });

  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      name: json['name'] ?? 'N/A',
      url: json['url'] ?? '',
      isFolder: json['is_folder'] ?? false,
      cleanId: json['cleanId'] ?? '',
    );
  }
}

class ResourceFile {
  final String id;
  final String name;
  final String url;
  final bool isFolder;
  final String cleanId;
  final String createdAt;

  ResourceFile({
    required this.id,
    required this.name,
    required this.url,
    required this.isFolder,
    required this.cleanId,
    required this.createdAt,
  });

  factory ResourceFile.fromJson(Map<String, dynamic> json) {
    return ResourceFile(
      id: json['id'] ?? '',
      name: json['name'] ?? 'N/A',
      url: json['url'] ?? '',
      isFolder: json['is_folder'] ?? false,
      cleanId: json['cleanId'] ?? '',
      createdAt: json['createdAt'] ?? '',
    );
  }
}

class RessourcesGratuitesPage extends StatefulWidget {
  const RessourcesGratuitesPage({Key? key}) : super(key: key);

  @override
  State<RessourcesGratuitesPage> createState() => _RessourcesGratuitesPageState();
}

class _RessourcesGratuitesPageState extends State<RessourcesGratuitesPage> {
  String? selectedAccount;
  Course? selectedCourse;
  List<Course> courses = [];
  CourseDetails? courseDetails;
  String? currentFolderPath;
  bool isLoading = false;
  String? errorMessage;
  bool isConnectionError = false;
  final Map<String, Uint8List?> _imageCache = {};
  final Map<String, double> _aspectRatioCache = {};
  Future<void>? _accountImagePreloadFuture;

  @override
  void initState() {
    super.initState();
    developer.log('Initializing RessourcesGratuitesPage', name: 'RessourcesGratuitesPage');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuth();
      _fetchCourses();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      isConnectionError = false;
    });

    try {
      if (selectedCourse != null) {
        await _fetchCourseDetails(selectedCourse!.id, folderPath: currentFolderPath);
      } else {
        await _fetchCourses();
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
            errorMessage = null;
          } else {
            isConnectionError = false;
            errorMessage = 'Erreur lors du rechargement: $e';
          }
        });
      }
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _checkAuth() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    developer.log('Checking authentication status: ${authProvider.isLoggedIn}', name: 'AuthCheck');
    if (!authProvider.isLoggedIn) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Veuillez vous connecter pour continuer.',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                backgroundColor: Colors.red.shade100,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            );
            Navigator.pushReplacementNamed(context, '/login');
          }
        });
      }
    }
  }

  Future<void> _fetchCourses() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
      isConnectionError = false;
    });
    developer.log('Fetching courses started', name: 'FetchCourses');

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.token == null) {
        developer.log('No authentication token found', name: 'FetchCourses');
        if (mounted) {
          setState(() {
            isLoading = false;
            errorMessage = 'Erreur d\'authentification. Veuillez vous reconnecter.';
            isConnectionError = false;
          });
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      final response = await http.get(
        Uri.parse('https://www.unistudious.com/free-course-mobile'),
        headers: {
          'Authorization': 'Bearer ${authProvider.token}',
          'Content-Type': 'application/json',
        },
      );

      if (!mounted) return;

      developer.log('API response: ${response.statusCode} - ${response.body}', name: 'FetchCourses');
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          courses = data.map((json) => Course.fromJson(json)).toList();
          isLoading = false;
          isConnectionError = false;
        });
        developer.log('Courses fetched: ${courses.length} items', name: 'FetchCourses');
        _accountImagePreloadFuture = _preloadAccountImages(courses);
      } else if (response.statusCode == 401) {
        developer.log('Authentication error: 401 Unauthorized', name: 'FetchCourses');
        setState(() {
          isLoading = false;
          errorMessage = 'Erreur d\'authentification. Veuillez vous reconnecter.';
          isConnectionError = false;
        });
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      } else {
        developer.log('Unexpected status code: ${response.statusCode}', name: 'FetchCourses');
        setState(() {
          isLoading = false;
          errorMessage = 'Erreur lors de la récupération des cours: ${response.statusCode}';
          isConnectionError = false;
        });
      }
    } catch (e) {
      developer.log('Network error: $e', name: 'FetchCourses');
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
            errorMessage = null;
          } else {
            isConnectionError = false;
            errorMessage = 'Erreur réseau: $e';
          }
          isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchCourseDetails(int courseId, {String? folderPath}) async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
      isConnectionError = false;
    });
    developer.log('Fetching course details for courseId: $courseId, folderPath: $folderPath', name: 'FetchCourseDetails');

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.token == null) {
        developer.log('No authentication token found', name: 'FetchCourseDetails');
        if (mounted) {
          setState(() {
            isLoading = false;
            errorMessage = 'Erreur d\'authentification. Veuillez vous reconnecter.';
          });
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      final response = await http.post(
        Uri.parse('https://www.unistudious.com/free-course-list-mobile/$courseId'),
        headers: {
          'Authorization': 'Bearer ${authProvider.token}',
          'Content-Type': 'application/json',
        },
        body: folderPath != null ? jsonEncode({'folderPath': folderPath}) : null,
      );

      if (!mounted) return;

      developer.log('API response: ${response.statusCode} - ${response.body}', name: 'FetchCourseDetails');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          courseDetails = CourseDetails.fromJson(data);
          currentFolderPath = folderPath ?? courseDetails!.relativeFolderPath;
          isLoading = false;
          isConnectionError = false;
        });
        developer.log('Course details fetched: folders=${courseDetails!.folders.length}, files=${courseDetails!.files.length}', name: 'FetchCourseDetails');
      } else if (response.statusCode == 401) {
        developer.log('Authentication error: 401 Unauthorized', name: 'FetchCourseDetails');
        setState(() {
          isLoading = false;
          errorMessage = 'Erreur d\'authentification. Veuillez vous reconnecter.';
          isConnectionError = false;
        });
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      } else {
        developer.log('Unexpected status code: ${response.statusCode}', name: 'FetchCourseDetails');
        setState(() {
          isLoading = false;
          errorMessage = 'Erreur lors de la récupération des détails: ${response.statusCode}';
          isConnectionError = false;
        });
      }
    } catch (e) {
      developer.log('Network error: $e', name: 'FetchCourseDetails');
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
            errorMessage = null;
          } else {
            isConnectionError = false;
            errorMessage = 'Erreur réseau: $e';
          }
          isLoading = false;
        });
      }
    }
  }

  Future<double> _getImageAspectRatio(String filename) async {
    if (_aspectRatioCache.containsKey(filename)) {
      return _aspectRatioCache[filename]!;
    }

    final imageData = _imageCache[filename];
    if (imageData != null) {
      final image = img.decodeImage(imageData);
      if (image != null) {
        final aspectRatio = image.width / image.height.toDouble();
        _aspectRatioCache[filename] = aspectRatio;
        developer.log('Aspect ratio for $filename: $aspectRatio', name: 'ImageFetch');
        return aspectRatio;
      }
    }
    return 16 / 9;
  }

  Future<void> _preloadAccountImages(List<Course> courses) async {
    developer.log('Preloading account images for ${courses.length} courses', name: 'ImagePreload');
    final futures = <Future<void>>[];
    final uniqueAccountImages = courses.map((course) => course.account.image).toSet();

    for (final image in uniqueAccountImages) {
      if (!_imageCache.containsKey(image)) {
        futures.add(_fetchImageWithAuth(image).then((imageData) {
          _imageCache[image] = imageData;
          developer.log('Preloaded image: $image', name: 'ImagePreload');
        }));
      }
    }

    await Future.wait(futures);

    if (!mounted) return;

    if (_imageCache.values.every((data) => data == null)) {
      developer.log('All image preloads failed', name: 'ImagePreload');
      setState(() {
        errorMessage = 'Impossible de charger les images. Vérifiez votre connexion ou vos identifiants.';
      });
    } else {
      developer.log('Image preloading completed', name: 'ImagePreload');
      setState(() {});
    }

    _preloadCourseImages(courses);
  }

  Future<void> _preloadCourseImages(List<Course> courses) async {
    developer.log('Preloading course images for ${courses.length} courses', name: 'ImagePreload');
    final futures = <Future<void>>[];

    for (final course in courses) {
      if (!_imageCache.containsKey(course.image)) {
        futures.add(_fetchImageWithAuth(course.image).then((imageData) {
          _imageCache[course.image] = imageData;
          developer.log('Preloaded course image: ${course.image}', name: 'ImagePreload');
        }));
      }
    }

    await Future.wait(futures);

    if (!mounted) return;

    setState(() {});
  }

  Future<Uint8List?> _fetchImageWithAuth(String filename, {int retryCount = 2}) async {
    if (_imageCache.containsKey(filename)) {
      return _imageCache[filename];
    }

    developer.log('Fetching image: $filename', name: 'ImageFetch');
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;
      if (token == null) {
        developer.log('No auth token available for $filename', name: 'ImageFetch');
        if (mounted) {
          setState(() {
            errorMessage = 'Erreur d\'authentification. Veuillez vous reconnecter.';
          });
          Navigator.pushReplacementNamed(context, '/login');
        }
        return null;
      }

      for (int attempt = 0; attempt <= retryCount; attempt++) {
        final response = await http.post(
          Uri.parse('https://www.unistudious.com/api/public-image-server/$filename'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'image/*',
          },
        );

        if (!mounted) return null;

        if (response.statusCode == 200) {
          developer.log('Successfully fetched image $filename', name: 'ImageFetch');
          return response.bodyBytes;
        } else if (response.statusCode == 401) {
          developer.log('Unauthorized access for $filename: ${response.statusCode}', name: 'ImageFetch');
          if (attempt == retryCount) {
            if (mounted) {
              setState(() {
                errorMessage = 'Erreur d\'authentification pour les images. Veuillez vous reconnecter.';
              });
              Navigator.pushReplacementNamed(context, '/login');
            }
            return null;
          }
          await authProvider.refreshToken();
          continue;
        } else {
          developer.log('Failed to fetch image $filename: ${response.statusCode}', name: 'ImageFetch');
          if (attempt == retryCount) return null;
        }
      }
    } catch (e) {
      developer.log('Error fetching image $filename: $e', name: 'ImageFetch');
      return null;
    }
    return null;
  }

  Widget _buildCourseImage(String filename) {
    final theme = Theme.of(context);
    if (_imageCache.containsKey(filename) && _imageCache[filename] != null) {
      return Image.memory(
        _imageCache[filename]!,
        height: double.infinity,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          developer.log('Error displaying image $filename: $error', name: 'ImageFetch');
          return Icon(Icons.book, size: 50, color: theme.iconTheme.color);
        },
      );
    }
    return Icon(Icons.book, size: 50, color: theme.iconTheme.color);
  }

  Widget _buildAccountImage(String filename) {
    final theme = Theme.of(context);
    if (_imageCache.containsKey(filename) && _imageCache[filename] != null) {
      return Image.memory(
        _imageCache[filename]!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          developer.log('Error displaying image $filename: $error', name: 'ImageFetch');
          return Icon(Icons.school, size: 50, color: theme.iconTheme.color);
        },
      );
    }
    return Icon(Icons.school, size: 50, color: theme.iconTheme.color);
  }

  Map<String, dynamic> buildFolderTree(CourseDetails details) {
    developer.log('Building folder tree for: ${details.relativeFolderPath}', name: 'FolderTree');
    final folderMap = <String, dynamic>{};

    folderMap[details.relativeFolderPath] = {
      'name': details.relativeFolderPath.replaceAll(RegExp(r'/$'), ''),
      'url': details.relativeFolderPath,
      'subfolders': [],
      'files': [],
      'courseId': selectedCourse!.id,
    };

    for (var folder in details.folders) {
      final pathParts = folder.url.split('/').where((part) => part.isNotEmpty).toList();
      if (pathParts.length > 1) {
        final parentPath = pathParts.sublist(0, pathParts.length - 1).join('/');
        final currentFolder = {
          'name': folder.name.replaceAll(RegExp(r'/$'), ''),
          'url': folder.url,
          'subfolders': [],
          'files': [],
          'courseId': selectedCourse!.id,
        };
        folderMap[folder.url] = currentFolder;
        if (folderMap.containsKey(parentPath + '/')) {
          folderMap[parentPath + '/']['subfolders'].add(currentFolder);
        } else {
          folderMap[details.relativeFolderPath]['subfolders'].add(currentFolder);
        }
      } else {
        folderMap[folder.url] = {
          'name': folder.name.replaceAll(RegExp(r'/$'), ''),
          'url': folder.url,
          'subfolders': [],
          'files': [],
          'courseId': selectedCourse!.id,
        };
        folderMap[details.relativeFolderPath]['subfolders'].add(folderMap[folder.url]);
      }
    }

    for (var file in details.files) {
      final filePathParts = file.id.split('/').where((part) => part.isNotEmpty).toList();
      if (filePathParts.length > 1) {
        final parentPath = filePathParts.sublist(0, filePathParts.length - 1).join('/');
        if (folderMap.containsKey(parentPath + '/')) {
          folderMap[parentPath + '/']['files'].add(file);
        } else {
          folderMap[details.relativeFolderPath]['files'].add(file);
        }
      } else {
        folderMap[details.relativeFolderPath]['files'].add(file);
      }
    }

    developer.log('Folder tree built: ${folderMap.length} entries', name: 'FolderTree');
    return folderMap;
  }

  bool _validateFileUrl(String url, String fileName) {
    try {
      final uri = Uri.parse(url);
      if (!uri.isAbsolute || !uri.queryParameters.containsKey('GoogleAccessId') ||
          !uri.queryParameters.containsKey('Expires') ||
          !uri.queryParameters.containsKey('Signature')) {
        developer.log('Invalid URL structure for $fileName: $url', name: 'UrlValidation');
        return false;
      }

      final expiresStr = uri.queryParameters['Expires'];
      if (expiresStr == null) {
        developer.log('Missing Expires parameter for $fileName: $url', name: 'UrlValidation');
        return false;
      }

      final expires = int.tryParse(expiresStr);
      if (expires == null) {
        developer.log('Invalid Expires format for $fileName: $expiresStr', name: 'UrlValidation');
        return false;
      }

      final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (expires < currentTimestamp) {
        developer.log('URL expired for $fileName: expires=$expires, current=$currentTimestamp', name: 'UrlValidation');
        return false;
      }

      developer.log('URL validated successfully for $fileName', name: 'UrlValidation');
      return true;
    } catch (e) {
      developer.log('Error validating URL for $fileName: $e', name: 'UrlValidation');
      return false;
    }
  }

  String _constructFolderUrl(String folderPath) {
    final pathParts = folderPath.split('/').where((part) => part.isNotEmpty).toList();
    final folderName = pathParts.isNotEmpty ? pathParts.last : '';
    final encodedFolderName = Uri.encodeComponent(folderName.replaceAll(' ', '-'));

    if (folderPath == courseDetails?.relativeFolderPath) {
      return 'https://unistudious.com/free-course-list/${selectedCourse!.id}';
    } else {
      return 'https://unistudious.com/free-course-folder/${selectedCourse!.id}/$encodedFolderName';
    }
  }

  Future<void> _openFile(ResourceFile file) async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
    });

    final fileName = file.name;
    final fileUrl = file.url;
    final fileType = _getFileType(fileName).toUpperCase();

    developer.log('Attempting to open file: $fileName, type: $fileType, url: $fileUrl', name: 'OpenFile');

    if (!_validateFileUrl(fileUrl, fileName)) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lien invalide ou expiré pour $fileName',
            style: GoogleFonts.poppins(fontSize: 14),
          ),
          backgroundColor: Colors.red.shade100,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    final videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'wmv'];
    final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp'];
    final audioExtensions = ['mp3', 'wav', 'ogg', 'm4a'];
    final pdfExtensions = ['pdf'];

    final extension = fileName.split('.').last.toLowerCase();
    final isVideo = videoExtensions.contains(extension) || fileType == 'VIDÉOS';
    final isImage = imageExtensions.contains(extension) || fileType == 'IMAGES';
    final isAudio = audioExtensions.contains(extension) || fileType == 'AUDIO';
    final isPdf = pdfExtensions.contains(extension) || fileType == 'PDF';

    try {
      if (isVideo) {
        developer.log('Opening video file: $fileName', name: 'OpenFile');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPlayerScreen(filePath: fileUrl, isNetwork: true),
          ),
        );
      } else if (isImage) {
        developer.log('Opening image file: $fileName', name: 'OpenFile');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageViewerScreen(imageUrl: fileUrl),
          ),
        );
      } else if (isAudio) {
        developer.log('Opening audio file: $fileName', name: 'OpenFile');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AudioPlayerScreen(audioUrl: fileUrl, fileName: fileName),
          ),
        );
      } else if (isPdf) {
        developer.log('Opening PDF file: $fileName', name: 'OpenFile');
        await _openFileFallback(file, isPdf: true);
      } else {
        developer.log('Attempting to open unsupported file type with fallback: $fileName', name: 'OpenFile');
        await _openFileFallback(file);
      }
    } catch (e) {
      developer.log('Error opening file $fileName: $e', name: 'OpenFile');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erreur lors de l\'ouverture du fichier: $e',
            style: GoogleFonts.poppins(fontSize: 14),
          ),
          backgroundColor: Colors.red.shade100,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      await _openFileFallback(file);
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _openFileFallback(ResourceFile file, {bool isPdf = false}) async {
    try {
      setState(() {
        isLoading = true;
      });

      // No Authorization header needed for signed URLs
      final response = await http.get(Uri.parse(file.url));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type']?.toLowerCase();
        final fileName = _sanitizeFileName(path.basename(file.name));
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';
        final tempFile = io.File(filePath);

        await tempFile.parent.create(recursive: true);
        await tempFile.writeAsBytes(response.bodyBytes);

        if (!await tempFile.exists()) {
          developer.log('Failed to create file: $filePath', name: 'OpenFileFallback');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Erreur: Le fichier n\'a pas pu être créé.',
                style: GoogleFonts.poppins(fontSize: 14),
              ),
              backgroundColor: Colors.red.shade100,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
          return;
        }

        if (isPdf) {
          developer.log('Navigating to PDFViewerScreen for: $fileName', name: 'OpenFileFallback');
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PDFViewerScreen(filePath: filePath, fileName: fileName),
            ),
          );
          await tempFile.delete();
        } else {
          final videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'wmv'];
          final isVideo = videoExtensions.contains(fileName.split('.').last.toLowerCase());

          if (isVideo) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoPlayerScreen(filePath: filePath, isNetwork: false),
              ),
            );
            await tempFile.delete();
          } else {
            final result = await OpenFile.open(filePath);
            if (result.type != ResultType.done) {
              developer.log('Error opening file $fileName: ${result.message}', name: 'OpenFileFallback');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Erreur lors de l\'ouverture du fichier: ${result.message}',
                    style: GoogleFonts.poppins(fontSize: 14),
                  ),
                  backgroundColor: Colors.red.shade100,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              );
            }
            await tempFile.delete();
          }
        }
      } else {
        developer.log('Failed to download file ${file.name}: ${response.statusCode}', name: 'OpenFileFallback');
        if (await canLaunchUrl(Uri.parse(file.url))) {
          await launchUrl(Uri.parse(file.url), mode: LaunchMode.externalApplication);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Impossible d\'ouvrir le fichier ${file.name}.',
                style: GoogleFonts.poppins(fontSize: 14),
              ),
              backgroundColor: Colors.red.shade100,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
      }
    } catch (e) {
      developer.log('Error in fallback file opening for ${file.name}: $e', name: 'OpenFileFallback');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erreur lors de l\'ouverture du fichier: $e',
            style: GoogleFonts.poppins(fontSize: 14),
          ),
          backgroundColor: Colors.red.shade100,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  String _sanitizeFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'[^\w\.]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    developer.log('Building UI - selectedAccount: $selectedAccount, selectedCourse: $selectedCourse', name: 'Build');

    Widget content;
    if (selectedCourse != null) {
      content = _buildCourseDetails();
    } else if (selectedAccount != null) {
      content = _buildCoursesList();
    } else {
      content = _buildCentersList();
    }

    return Scaffold(
      backgroundColor: isDark ? theme.scaffoldBackgroundColor : Colors.grey.shade50,
      appBar: AppBar(
        leading: selectedAccount != null || selectedCourse != null
            ? IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            setState(() {
              if (currentFolderPath != null) {
                final pathSegments = currentFolderPath!.split('/').where((s) => s.isNotEmpty).toList();
                if (pathSegments.isEmpty || currentFolderPath == courseDetails?.relativeFolderPath) {
                  selectedCourse = null;
                  courseDetails = null;
                  currentFolderPath = null;
                } else {
                  pathSegments.removeLast();
                  final newPath = pathSegments.isEmpty ? null : '${pathSegments.join('/')}/';
                  developer.log('Navigating to folder: $newPath', name: 'Navigation');
                  currentFolderPath = newPath;
                  _fetchCourseDetails(selectedCourse!.id, folderPath: newPath);
                }
              } else if (selectedCourse != null) {
                selectedCourse = null;
                courseDetails = null;
                currentFolderPath = null;
              } else if (selectedAccount != null) {
                selectedAccount = null;
              }
            });
          },
        )
            : Builder(
          builder: (context) {
            return IconButton(
              icon: Icon(Icons.menu, color: theme.appBarTheme.iconTheme?.color ?? Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            );
          },
        ),
        title: Text(
          selectedCourse != null
              ? selectedCourse!.name
              : selectedAccount != null
              ? selectedAccount!
              : "Centres d'étude",
          style: GoogleFonts.poppins(
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        centerTitle: false, // Aligne le titre à gauche
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
      drawer: const AppSidebar(),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: Colors.deepPurple))
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
                      if (selectedCourse != null) {
                        _fetchCourseDetails(selectedCourse!.id, folderPath: currentFolderPath);
                      } else {
                        _fetchCourses();
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
            )
          : errorMessage != null
          ? Center(
        child: Text(
          errorMessage!,
          style: GoogleFonts.poppins(
            fontSize: 16,
            color: isDark ? Colors.red[400] : Colors.red[700],
          ),
        ),
      )
          : RefreshIndicator(
        onRefresh: _refresh,
        child: content,
      ),
    );
  }

  Widget _buildCentersList() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    developer.log('Building centers list with ${courses.length} courses', name: 'BuildCentersList');
    if (courses.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200),
          Center(
            child: Text(
              'Aucun centre d\'étude disponible',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      );
    }

    final uniqueAccounts = courses.map((course) => course.account.name).toSet().toList();

    if (uniqueAccounts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200),
          Center(
            child: Text(
              'Aucun centre d\'étude disponible',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: uniqueAccounts.length,
      itemBuilder: (context, index) {
        final accountName = uniqueAccounts[index];
        final firstCourse = courses.firstWhere((course) => course.account.name == accountName);

        return FutureBuilder<double>(
          future: _getImageAspectRatio(firstCourse.account.image),
          builder: (context, snapshot) {
            double imageHeight = 120;
            if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
              final aspectRatio = snapshot.data!;
              final containerWidth = MediaQuery.of(context).size.width - 32;
              imageHeight = containerWidth / aspectRatio;
              imageHeight = imageHeight.clamp(100.0, 200.0);
            }

            return GestureDetector(
              onTap: () {
                setState(() {
                  selectedAccount = accountName;
                  developer.log('Selected account: $accountName', name: 'Selection');
                });
              },
              child: Card(
                color: theme.cardColor,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                child: SizedBox(
                  height: imageHeight + 120,
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        child: Container(
                          color: isDark ? Colors.deepPurple.shade900 : Colors.deepPurple.shade100,
                          height: imageHeight,
                          width: double.infinity,
                          child: _buildAccountImage(firstCourse.account.image),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 16, color: theme.iconTheme.color),
                                  const SizedBox(width: 6),
                                  Text(
                                    firstCourse.createdAt.date.split(' ')[0],
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: theme.textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                accountName,
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Free",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple,
                                ),
                              ),
                              const Spacer(),
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: isDark ? Colors.deepPurple.shade700 : Colors.deepPurple.shade50,
                                    child: ClipOval(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: _buildAccountImage(firstCourse.account.image),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    accountName,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: theme.textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCoursesList() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    developer.log('Building courses list for account: $selectedAccount', name: 'BuildCoursesList');
    final filteredCourses = courses.where((course) => course.account.name == selectedAccount).toList();

    if (filteredCourses.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200),
          Center(
            child: Text(
              'Aucun cours disponible',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: filteredCourses.length,
      itemBuilder: (context, index) {
        final course = filteredCourses[index];

        return GestureDetector(
          onTap: () {
            setState(() {
              selectedCourse = course;
              courseDetails = null;
              currentFolderPath = null;
              developer.log('Selected course: ${course.name}', name: 'Selection');
            });
            _fetchCourseDetails(course.id);
          },
          child: Card(
            color: theme.cardColor,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 4,
            child: SizedBox(
              height: 180,
              child: Row(
                children: [
                  Container(
                    width: 120,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                      color: isDark ? Colors.deepPurple.shade900 : Colors.deepPurple.shade100,
                    ),
                    child: Center(
                      child: _buildCourseImage(course.image),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            course.name,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 14, color: theme.iconTheme.color),
                                  const SizedBox(width: 6),
                                  Text(
                                    course.createdAt.date.split(' ')[0],
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: theme.textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.green.shade900 : Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  course.type,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.green.shade300 : Colors.green.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            course.account.name,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.deepPurple,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCourseDetails() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    developer.log('Building course details - currentFolderPath: $currentFolderPath', name: 'BuildCourseDetails');
    if (courseDetails == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200),
          Center(child: CircularProgressIndicator(color: Colors.deepPurple)),
        ],
      );
    }

    final folderTree = buildFolderTree(courseDetails!);
    dynamic currentFolder;
    if (currentFolderPath != null && folderTree.containsKey(currentFolderPath)) {
      currentFolder = folderTree[currentFolderPath];
    } else {
      currentFolder = folderTree[courseDetails!.relativeFolderPath];
    }

    if (currentFolder == null || (currentFolder['subfolders'].isEmpty && currentFolder['files'].isEmpty)) {
      developer.log('No folders or files in current folder: ${currentFolder?['name']}', name: 'BuildCourseDetails');
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200),
          Center(
            child: Text(
              'Aucun fichier ou dossier disponible',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: _buildFolderContent(currentFolder),
    );
  }

  List<Widget> _buildFolderContent(dynamic folder) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    developer.log('Building folder content for: ${folder['name']}, files: ${folder['files'].length}, subfolders: ${folder['subfolders'].length}', name: 'BuildFolderContent');
    final widgets = <Widget>[];

    for (var file in folder['files']) {
      final isValidUrl = _validateFileUrl(file.url, file.name);
      widgets.add(
        Card(
          color: theme.cardColor,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: _buildFileIcon(_getFileType(file.name)),
            title: Text(
              file.name,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: theme.textTheme.bodyLarge?.color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              isValidUrl
                  ? 'Fichier • Modifié le ${file.createdAt.split('T')[0]}'
                  : 'Fichier • Lien invalide ou expiré',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: isValidUrl ? theme.textTheme.bodyMedium?.color : (isDark ? Colors.red[400] : Colors.red[600]),
              ),
            ),
            trailing: PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 8,
              color: theme.cardColor,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'copy_link',
                  enabled: isValidUrl,
                  child: Row(
                    children: [
                      Icon(Icons.link, color: isValidUrl ? Colors.deepPurple : Colors.grey, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Copier le lien',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isValidUrl ? theme.textTheme.bodyLarge?.color : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    if (!isValidUrl) {
                      developer.log('Cannot copy invalid or expired URL for file: ${file.name}', name: 'FileAction');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Lien invalide ou expiré pour ${file.name}',
                              style: GoogleFonts.poppins(fontSize: 14),
                            ),
                            backgroundColor: Colors.red.shade100,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        );
                      }
                      return;
                    }
                    developer.log('Copying link for file: ${file.name}', name: 'FileAction');
                    FlutterClipboard.copy(file.url).then((_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Lien copié ',
                              style: GoogleFonts.poppins(fontSize: 14),
                            ),
                            backgroundColor: isDark ? Colors.deepPurple.shade700 : Colors.deepPurple.shade100,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        );
                      }
                    });
                  },
                ),
              ],
            ),
            onTap: () {
              if (!isValidUrl) {
                developer.log('Cannot open invalid or expired URL for file: ${file.name}', name: 'FileAction');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Lien invalide ou expiré pour ${file.name}',
                        style: GoogleFonts.poppins(fontSize: 14),
                      ),
                      backgroundColor: Colors.red.shade100,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  );
                }
                return;
              }
              developer.log('Opening file: ${file.url}', name: 'FileAction');
              _openFile(file);
            },
          ),
        ),
      );
    }

    for (var subfolder in folder['subfolders']) {
      final folderUrl = _constructFolderUrl(subfolder['url']);
      widgets.add(
        Card(
          color: theme.cardColor,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            leading: _buildFileIcon('folder'),
            title: Text(
              subfolder['name'],
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            subtitle: Text(
              'Dossier',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            trailing: PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 8,
              color: theme.cardColor,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'copy_link',
                  child: Row(
                    children: [
                      const Icon(Icons.link, color: Colors.deepPurple, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Copier le lien',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    developer.log('Copying link for folder: ${subfolder['name']}, url: $folderUrl', name: 'FolderAction');
                    FlutterClipboard.copy(folderUrl).then((_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Lien copié',
                              style: GoogleFonts.poppins(fontSize: 14),
                            ),
                            backgroundColor: isDark ? Colors.deepPurple.shade700 : Colors.deepPurple.shade100,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        );
                      }
                    });
                  },
                ),
              ],
            ),
            children: _buildFolderContent(subfolder),
            onExpansionChanged: (expanded) {
              if (expanded) {
                setState(() {
                  currentFolderPath = subfolder['url'];
                  developer.log('Expanded folder: ${subfolder['name']}, new path: $currentFolderPath', name: 'Expansion');
                });
                _fetchCourseDetails(selectedCourse!.id, folderPath: subfolder['url']);
              }
            },
          ),
        ),
      );
    }

    return widgets;
  }

  String _getFileType(String name) {
    final extension = name.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'pdf';
      case 'doc':
      case 'docx':
        return 'doc';
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'wmv':
        return 'vid';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
        return 'image';
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'm4a':
        return 'audio';
      default:
        return 'file';
    }
  }

  Widget _buildFileIcon(String type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (type) {
      case 'folder':
        return Icon(
          Icons.folder,
          color: isDark ? const Color(0xFFCABDE1) : const Color(0xFFCABDE1),
          size: 36,
        );
      case 'pdf':
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark ? Colors.red.shade900 : Colors.red.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.picture_as_pdf, color: isDark ? Colors.red.shade300 : Colors.red),
        );
      case 'doc':
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark ? Colors.deepPurple.shade900 : Colors.deepPurple.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.description, color: isDark ? Colors.deepPurple.shade300 : Colors.deepPurple),
        );
      case 'vid':
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark ? Colors.blue.shade900 : Colors.blue.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.videocam, color: isDark ? Colors.blue.shade300 : Colors.blue),
        );
      case 'image':
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark ? Colors.green.shade900 : Colors.green.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.image, color: isDark ? Colors.green.shade300 : Colors.green),
        );
      case 'audio':
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark ? Colors.orange.shade900 : Colors.orange.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.audiotrack, color: isDark ? Colors.orange.shade300 : Colors.orange),
        );
      default:
        return Icon(Icons.insert_drive_file, color: Theme.of(context).iconTheme.color, size: 36);
    }
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
    _controller = widget.isNetwork
        ? VideoPlayerController.networkUrl(Uri.parse(widget.filePath))
        : VideoPlayerController.file(io.File(widget.filePath))
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
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Lecteur Vidéo',
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
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Retour', style: GoogleFonts.poppins(fontSize: 16)),
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
                    color: Colors.deepPurple,
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
            : CircularProgressIndicator(color: Colors.deepPurple),
      ),
    );
  }
}

class ImageViewerScreen extends StatelessWidget {
  final String imageUrl;

  const ImageViewerScreen({Key? key, required this.imageUrl}) : super(key: key);

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
          'Visualiseur d\'Image',
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
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.contain,
          placeholder: (context, url) => CircularProgressIndicator(color: Colors.deepPurple),
          errorWidget: (context, url, error) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Erreur lors du chargement de l\'image: $error',
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.red[400] : Colors.red[700],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Retour', style: GoogleFonts.poppins(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AudioPlayerScreen extends StatefulWidget {
  final String audioUrl;
  final String fileName;

  const AudioPlayerScreen({Key? key, required this.audioUrl, required this.fileName}) : super(key: key);

  @override
  _AudioPlayerScreenState createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  late AudioPlayer _audioPlayer;
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
      await _audioPlayer.setSourceUrl(widget.audioUrl);
      _audioPlayer.onDurationChanged.listen((d) {
        if (mounted) {
          setState(() {
            _duration = d;
          });
        }
      });
      _audioPlayer.onPositionChanged.listen((p) {
        if (mounted) {
          setState(() {
            _position = p;
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.fileName,
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
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Retour', style: GoogleFonts.poppins(fontSize: 16)),
            ),
          ],
        )
            : _isInitialized
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.fileName,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.textTheme.bodyLarge?.color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Slider(
              value: _position.inSeconds.toDouble(),
              max: _duration.inSeconds.toDouble(),
              activeColor: Colors.deepPurple,
              inactiveColor: isDark ? Colors.grey[700] : Colors.grey[300],
              onChanged: (value) async {
                await _audioPlayer.seek(Duration(seconds: value.toInt()));
              },
            ),
            Text(
              '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.deepPurple,
                    size: 36,
                  ),
                  onPressed: () async {
                    if (_isPlaying) {
                      await _audioPlayer.pause();
                    } else {
                      await _audioPlayer.resume();
                    }
                  },
                ),
              ],
            ),
          ],
        )
            : CircularProgressIndicator(color: Colors.deepPurple),
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Erreur lors du chargement du PDF: $error',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                backgroundColor: Colors.red.shade100,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            );
          },
          onRender: (pages) {
            developer.log('PDF rendered with $pages pages', name: 'PDFViewer');
          },
          onPageError: (page, error) {
            developer.log('Error on page $page: $error', name: 'PDFViewer');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Erreur sur la page $page: $error',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                backgroundColor: Colors.red.shade100,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            );
          },
        ),
      ),
    );
  }
}