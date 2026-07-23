// lib/pages/groupe_chat_page.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:async';
import '../providers/auth_provider.dart';
import '../utils/app_bar_gradient.dart';
import '../providers/loading_provider.dart';
import '../utils/snackbar_helper.dart';
import '../screens/group_info_page.dart';
import '../services/rocketchat_websocket_service.dart';
import '../widgets/linkable_text.dart';

class GroupeChatPage extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String? avatarUrl;
  final bool isPublicChannel;
  final bool isLeader;

  const GroupeChatPage({
    super.key,
    required this.groupId,
    required this.groupName,
    this.avatarUrl,
    required this.isPublicChannel,
    this.isLeader = false,
  });

  @override
  State<GroupeChatPage> createState() => _GroupeChatPageState();
}

class _GroupeChatPageState extends State<GroupeChatPage>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _editController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final _jitsiMeet = JitsiMeet();

  // Enregistrement audio (messages vocaux)
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingFilePath;

  List<Map<String, dynamic>> messages = [];
  bool isLoadingMessages = false;
  String? errorMessage;
  String? currentUser;
  String? channelAnnouncement;
  String? _editingMessageId;
  int? _editingIndex;
  String? _replyingToId;
  Map<String, dynamic>? _replyingMessage;
  int? _reactionIndex;
  int? _highlightedIndex;
  bool _readOnly = false;
  bool _isLeaderFromApi = false; // Pour stocker isLeader depuis l'API

  List<Map<String, dynamic>> membres = [];

  // Cache des avatars SVG parsés (username/url → Map avec color et initial)
  final Map<String, Map<String, dynamic>> _avatarSvgCache = {};
  final Map<String, Future<Map<String, dynamic>>> _avatarFutures = {};

  // WebSocket service
  final RocketChatWebSocketService _wsService = RocketChatWebSocketService();
  StreamSubscription<Map<String, dynamic>>? _wsMessageSubscription;
  StreamSubscription<String>? _wsDeleteSubscription;
  StreamSubscription<bool>? _wsConnectionSubscription;

  // Polling (même logique que dans ChatPage)
  Timer? _pollingTimer;

  bool _showScrollToBottom = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<String> reactions = ['❤️', '😂', '😯', '😍', '😢', '😡', '👍'];
  final Map<String, String> reactionLabels = {
  '❤️' : 'heart',
  '😂' : 'joy',
  '😯' : 'mind_blown',
  '😢' : 'cry',
  '😡' : 'rage',
  '👍' : '+1',
  };
  // Mapping des réactions vers les emojis pour l'affichage
  final Map<String, String> reactionEmojis = {
    'heart': '❤️️️️️',
    'joy': '😂',
    'mind_blown': '😯',
    'cry': '😢',
    'rage': '😡',
    '+1': '👍' ,
  };

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_scrollListener);

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkAuthAndFetchData();
      }
    });
  }

  Future<bool> _checkIfChannelJoined() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final endpoint =
        widget.isPublicChannel ? '/api/chat/list-channels' : '/api/chat/my-channels';

    try {
      final response = await authProvider
          .authenticatedRequest('GET', endpoint)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);

        if (jsonResponse['success'] == true) {
          final List<dynamic> channels = jsonResponse['channels'] ?? [];

          // Chercher le canal actuel dans la liste
          for (var channel in channels) {
            final channelId = channel['id']?.toString() ?? channel['_id']?.toString() ?? '';
            final roomId = channel['room_id']?.toString() ?? channelId;

            if (roomId == widget.groupId || channelId == widget.groupId) {
              final joined = channel['joined'] ?? false;
              
              // Récupérer readonly et isLeader depuis l'API
              final readOnlyValue = channel['readonly'] ?? channel['readOnly'] ?? false;
              final isLeaderValue = channel['isLeader'] ?? false;
              
              if (mounted) {
                setState(() {
                  _readOnly = readOnlyValue == true || readOnlyValue == 'true' || readOnlyValue == 1;
                  _isLeaderFromApi = isLeaderValue == true;
                });
                developer.log('Channel info from API: readonly=$readOnlyValue, isLeader=$isLeaderValue, _readOnly=$_readOnly, _isLeaderFromApi=$_isLeaderFromApi', name: 'GroupeChatPage');
              }
              
              return joined == true;
            }
          }
        }
      }
      // Si on ne trouve pas le canal ou si l'API échoue, on assume qu'il n'est pas rejoint
      return false;
    } catch (e, s) {
      developer.log('Error checking channel joined status: $e', error: e, stackTrace: s, name: 'GroupeChatPage');
      return false;
    }
  }

  Future<void> _checkAuthAndFetchData() async {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loadingProvider = Provider.of<LoadingProvider>(context, listen: false);

    if (!authProvider.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          SnackBarHelper.showWarning(context, 'Veuillez vous connecter pour continuer.');
          Navigator.pop(context);
        }
      });
      return;
    }

    loadingProvider.showLoading();

    try {
      // Vérifier si le canal est rejoint avant de charger les messages
      final isJoined = await _checkIfChannelJoined();

      if (!isJoined) {
        // Si le canal n'est pas rejoint, le joindre d'abord
        developer.log('Channel not joined, joining channel: ${widget.groupId}', name: 'GroupeChatPage');
        final joinSuccess = await _joinChannel(widget.groupId);

        if (!joinSuccess) {
          throw Exception('Impossible de rejoindre le canal. Veuillez réessayer.');
        }
      }

      // Maintenant que le canal est rejoint, charger les données
      // Chaque fonction gère ses propres erreurs silencieusement
      await Future.wait([
        fetchCurrentUser().catchError((e) {
          developer.log('Error fetching current user: $e', name: 'GroupeChatPage');
          return null;
        }),
        fetchMessages().catchError((e) {
          developer.log('Error fetching messages: $e', name: 'GroupeChatPage');
          return null;
        }),
        fetchMembers().catchError((e) {
          developer.log('Error fetching members: $e', name: 'GroupeChatPage');
          return null;
        }),
      ]);

      // Démarrer le polling + WebSocket après le chargement initial (comme dans ChatPage)
      _startPolling();
      _initializeWebSocket();
    } catch (e, s) {
      developer.log('Error during data fetch: $e', error: e, stackTrace: s, name: 'GroupeChatPage');
      // Ne pas afficher d'erreur agressive, les fonctions individuelles gèrent leurs erreurs
    } finally {
      if (mounted) {
        loadingProvider.hideLoading();
      }
    }
  }

  // ================== GESTION DES MESSAGES VOCAUX ==================
  Future<void> _handleMicPressed() async {
    // Vérifier les permissions pour les membres readOnly non-leaders
    if (!_canSendMessage()) {
      if (mounted) {
        SnackBarHelper.showWarning(context, 'Seul l\'admin peut envoyer des messages vocaux dans ce canal.');
      }
      return;
    }
    
    if (_isRecording) {
      await _stopAndSendRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      // Vérifier les permissions micro
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        SnackBarHelper.showInfo(context, 'Autorisez l\'accès au micro dans les paramètres pour envoyer un message vocal.');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      // IMPORTANT : pour les mêmes raisons que dans `ChatPage`, on reste en .m4a ici.
      final path = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingFilePath = path;
      });
    } catch (e, s) {
      developer.log('Erreur lors du démarrage de l\'enregistrement: $e',
          name: 'GroupeChatPage.Audio', error: e, stackTrace: s);
      if (!mounted) return;
      SnackBarHelper.showError(context, 'Erreur lors du démarrage de l\'enregistrement: $e');
    }
  }

  Future<void> _stopAndSendRecording() async {
    try {
      final path = await _audioRecorder.stop();

      if (!mounted) return;

      setState(() {
        _isRecording = false;
      });

      final filePath = path ?? _recordingFilePath;
      if (filePath == null) return;

      final file = io.File(filePath);
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();
      // On garde également l'extension .m4a lors de l'envoi.
      final fileName = 'vocal_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _sendAudioAttachment(bytes, fileName);
    } catch (e, s) {
      developer.log('Erreur lors de l\'arrêt de l\'enregistrement: $e',
          name: 'GroupeChatPage.Audio', error: e, stackTrace: s);
      if (!mounted) return;
      SnackBarHelper.showError(context, 'Erreur lors de l\'envoi du vocal: $e');
    } finally {
      _recordingFilePath = null;
    }
  }

  Future<void> _sendAudioAttachment(Uint8List bytes, String fileName) async {
    // Vérifier les permissions pour les membres readOnly non-leaders
    if (!_canSendMessage()) {
      if (mounted) {
        SnackBarHelper.showWarning(context, 'Seul l\'admin peut envoyer des fichiers dans ce canal.');
      }
      return;
    }
    
    const endpoint = 'https://www.unistudious.com/api/chat/send-attachment';

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) {
        throw Exception('Aucun token d\'authentification trouvé.');
      }

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId;

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final dynamic rawMessage = data['message'] ?? data['data']?['message'] ?? data;
          if (rawMessage is! Map) {
            return;
          }
          final message = Map<String, dynamic>.from(rawMessage as Map);

          // Conversion vers le format local utilisé par fetchMessages()
          final newMessage = <String, dynamic>{
            'id': message['id']?.toString() ?? message['_id']?.toString() ?? '',
            'sender': message['name']?.toString() ??
                message['u']?['name']?.toString() ??
                message['username']?.toString() ??
                currentUser ??
                'Toi',
            'message': message['text']?.toString() ?? message['msg']?.toString() ?? '',
            'time': _formatTimestamp(message['timestamp'] ?? message['ts']),
            'isMe': true,
            'reactions': message['reactions'] ?? [],
            'timestamp': message['timestamp'] ?? message['ts'],
            'username': message['username']?.toString() ??
                message['u']?['username']?.toString() ??
                '',
            'avatar': message['avatar']?.toString() ?? '',
            'type': message['type']?.toString() ?? 'attachment',
            'editedAt': message['editedAt'],
            'isEdited': message['editedAt'] != null,
            'replyTo': message['replyTo'] ?? message['tmid'],
            'threadMessages': message['threadMessages'] ?? [],
            'threadCount': message['threadCount'] ?? 0,
            'attachments': message['attachments'] ?? [],
            'file': message['file'],
          };

          setState(() {
            messages.insert(0, newMessage);
          });
          _scrollToBottom();
        } else {
          throw Exception(
              data['message']?.toString() ?? 'Échec de l\'envoi du message vocal.');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
        Navigator.pop(context);
      } else {
        throw Exception('Erreur HTTP ${response.statusCode}');
      }
    } catch (e, s) {
      developer.log('Erreur _sendAudioAttachment: $e',
          name: 'GroupeChatPage.Audio', error: e, stackTrace: s);
      if (!mounted) return;
      SnackBarHelper.showError(context, 'Erreur lors de l\'envoi du vocal: $e');
    }
  }

  // --------------------------------------------------------------------------
  // Envoi de pièce jointe : /api/chat/send-attachment (POST, form-data)
  // --------------------------------------------------------------------------
  Future<void> _pickAndSendAttachment() async {
    // Vérifier les permissions pour les membres readOnly non-leaders
    if (!_canSendMessage()) {
      if (mounted) {
        SnackBarHelper.showWarning(context, 'Seul l\'admin peut envoyer des fichiers dans ce canal.');
      }
      return;
    }

    if (!mounted || widget.groupId.isEmpty) return;

    // 1) Demander à l'utilisateur s'il veut envoyer une photo (galerie) ou un fichier (documents/audio/vidéo...)
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo),
                title: const Text('Photo'),
                onTap: () => Navigator.of(ctx).pop('photo'),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: const Text('Fichier'),
                onTap: () => Navigator.of(ctx).pop('file'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || widget.groupId.isEmpty) return;
    if (choice == null) return; // feuille fermée sans choix

    Uint8List? bytes;
    String? fileName;

    if (choice == 'photo') {
      // 2a) Sélection d'une image depuis la galerie
      final picker = ImagePicker();
      final XFile? imageFile = await picker.pickImage(source: ImageSource.gallery);
      if (imageFile == null) return;
      bytes = await imageFile.readAsBytes();
      fileName = imageFile.name;
    } else {
      // 2b) Sélection d'un fichier (document/audio/vidéo...) via FilePicker
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      bytes = picked.bytes;
      fileName = picked.name;
    }

    if (bytes == null) return;

    // Afficher une popup avec indicateur de chargement
    ScaffoldMessengerState? scaffoldMessenger;
    if (choice == 'photo' && mounted) {
      scaffoldMessenger = ScaffoldMessenger.of(context);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Envoi de la photo en cours...',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.deepPurple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          elevation: 6,
          duration: const Duration(days: 1), // Durée très longue pour rester visible
          dismissDirection: DismissDirection.none, // Empêcher le dismiss manuel
        ),
      );
    }

    const endpoint = 'https://www.unistudious.com/api/chat/send-attachment';

    try {
      // 2) Préparation de la requête multipart/form-data
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId;

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName ?? 'attachment',
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) {
        throw Exception('Aucun token d\'authentification trouvé.');
      }

      request.headers.addAll({'Authorization': 'Bearer $token'});

      // 3) Envoi
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final dynamic rawMessage = data['message'] ?? data['data']?['message'] ?? data;
          if (rawMessage is! Map) {
            // Fermer la popup en cas d'erreur
            if (choice == 'photo' && scaffoldMessenger != null && mounted) {
              scaffoldMessenger.hideCurrentSnackBar();
            }
            return;
          }
          final message = Map<String, dynamic>.from(rawMessage as Map);

          // 4) Conversion en modèle local de message (identique à _sendAudioAttachment)
          final newMessage = <String, dynamic>{
            'id': message['id']?.toString() ?? message['_id']?.toString() ?? '',
            'sender': message['name']?.toString() ??
                message['u']?['name']?.toString() ??
                message['username']?.toString() ??
                currentUser ??
                'Toi',
            'message': message['text']?.toString() ?? message['msg']?.toString() ?? '',
            'time': _formatTimestamp(message['timestamp'] ?? message['ts']),
            'isMe': true,
            'reactions': message['reactions'] ?? [],
            'timestamp': message['timestamp'] ?? message['ts'],
            'username': message['username']?.toString() ??
                message['u']?['username']?.toString() ??
                '',
            'avatar': message['avatar']?.toString() ?? '',
            'type': message['type']?.toString() ?? 'attachment',
            'editedAt': message['editedAt'],
            'isEdited': message['editedAt'] != null,
            'replyTo': message['replyTo'] ?? message['tmid'],
            'threadMessages': message['threadMessages'] ?? [],
            'threadCount': message['threadCount'] ?? 0,
            'attachments': message['attachments'] ?? [],
            'file': message['file'],
            'files': message['files'] ?? [],
          };

          // 5) Mise à jour de l'état : ajouter le nouveau message
          setState(() {
            // Vérifier si le message existe déjà (ajouté par WebSocket)
            final existingIndex = messages.indexWhere((msg) => msg['id'] == newMessage['id']);
            if (existingIndex == -1) {
              messages.insert(0, newMessage);
            } else {
              messages[existingIndex] = newMessage;
            }
          });

          // Fermer la popup de chargement et afficher un message de succès
          if (choice == 'photo' && scaffoldMessenger != null && mounted) {
            scaffoldMessenger.hideCurrentSnackBar();
            SnackBarHelper.showSuccess(context, 'Photo envoyée avec succès', duration: const Duration(seconds: 2));
          }

          _scrollToBottom();
        } else {
          throw Exception('Échec de l\'envoi de la pièce jointe.');
        }
      } else {
        throw Exception(
          'Erreur ${response.statusCode} lors de l\'envoi de la pièce jointe.',
        );
      }
    } catch (e, s) {
      developer.log(
        'Error sending attachment: $e',
        name: 'GroupeChatPage',
        error: e,
        stackTrace: s,
      );
      
      // Fermer la popup de chargement en cas d'erreur
      if (choice == 'photo' && scaffoldMessenger != null && mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
      }
      
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors de l\'envoi de la pièce jointe : $e');
      }
    }
  }
  // ================================================================

  Future<void> fetchCurrentUser() async {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    const endpoint = '/api/chat-message';

    try {
      final response = await authProvider
          .authenticatedRequest('GET', endpoint)
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      final data = jsonDecode(response.body);
      final user = data['currentUser']?.toString();

      if (mounted) {
        setState(() => currentUser = user);
      }
    } catch (e, s) {
      developer.log('fetchCurrentUser error: $e', error: e, stackTrace: s);
    }
  }

  Future<void> fetchMessages() async {
    if (!mounted) return;

    setState(() {
      isLoadingMessages = true;
      errorMessage = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    const endpoint = 'https://www.unistudious.com/api/chat/get-channel-messages';

    try {
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId;

      final token = authProvider.token;
      if (token == null || token.isEmpty) {
        throw Exception('Aucun token d\'authentification trouvé.');
      }

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final channelData = data['channel'];
          final String? announcement = channelData is Map<String, dynamic>
              ? channelData['announcement']?.toString()
              : null;
          
          // Note: readOnly et isLeader sont maintenant récupérés depuis my-channels/list-channels
          // dans _checkIfChannelJoined(), donc on ne les récupère plus ici
          // On garde cette section pour compatibilité mais elle ne sera plus utilisée pour readOnly

          // Handle both Map and List responses
          dynamic messagesData = data['messages'] ?? [];
          List<dynamic> messagesList;

          if (messagesData is Map) {
            // If messages is a Map, convert to List by taking values
            messagesList = messagesData.values.toList();
          } else if (messagesData is List) {
            // If messages is already a List, use it directly
            messagesList = messagesData;
          } else {
            // Fallback to empty list
            messagesList = [];
          }

          // Filter to ensure we only process Map items
          final List<Map<String, dynamic>> tempMessages =
          messagesList.whereType<Map>().map((msg) {
            // Déterminer si le message est non lu (pas envoyé par l'utilisateur actuel)
            final msgUsername = msg['username']?.toString() ?? '';
            final isUnread = msgUsername != currentUser && msg['isSent'] != true;
            
            return {
              'id': msg['id']?.toString() ?? '',
              'sender': msg['name']?.toString() ?? msg['username']?.toString() ?? 'Inconnu',
              'message': msg['text']?.toString() ?? '',
              'time': _formatTimestamp(msg['timestamp']),
              'isMe': msg['isSent'] == true,
              'isUnread': isUnread, // Flag pour les messages non lus
              'reactions': msg['reactions'] ?? [],
              'timestamp': msg['timestamp'],
              'username': msg['username']?.toString() ?? '',
              'avatar': msg['avatar']?.toString() ?? '',
              'type': msg['type']?.toString() ?? 'text',
              'editedAt': msg['editedAt'],
              'isEdited': msg['editedAt'] != null,
              'replyTo': msg['replyTo'] ?? msg['tmid'],
              'threadMessages': msg['threadMessages'] ?? [],
              'threadCount': msg['threadCount'] ?? 0,
              'attachments': msg['attachments'] ?? [],
              'file': msg['file'],
            };
          }).toList();

          // Enrichir les replyTo avec les données des messages originaux
          final List<Map<String, dynamic>> newMessages = tempMessages.map((msg) {
            if (msg['replyTo'] != null) {
              if (msg['replyTo'] is Map) {
                // Si replyTo est déjà un objet, normaliser les champs
                final replyToObj = Map<String, dynamic>.from(msg['replyTo'] as Map);
                msg['replyTo'] = {
                  'messageId': replyToObj['messageId'] ?? replyToObj['id'],
                  'id': replyToObj['messageId'] ?? replyToObj['id'],
                  'sender': replyToObj['sender'] ?? replyToObj['name'] ?? replyToObj['username'] ?? 'Inconnu',
                  'username': replyToObj['username'] ?? 'Inconnu',
                  'message': replyToObj['message'] ?? replyToObj['text'] ?? 'Ce message a été supprimé ou n\'est pas disponible.',
                };
              } else {
                // Si replyTo est un ID, chercher le message original
                final replyToId = msg['replyTo'].toString();
                final originalMsg = tempMessages.firstWhere(
                  (m) => m['id'] == replyToId,
                  orElse: () => {
                    'sender': 'Message supprimé',
                    'username': 'Inconnu',
                    'message': 'Ce message a été supprimé ou n\'est pas disponible.',
                    'id': replyToId
                  },
                );
                msg['replyTo'] = {
                  'messageId': replyToId,
                  'id': replyToId,
                  'sender': originalMsg['sender'] ?? 'Message supprimé',
                  'username': originalMsg['username'] ?? 'Inconnu',
                  'message': originalMsg['message'] ?? 'Ce message a été supprimé ou n\'est pas disponible.',
                };
              }
            }
            return msg;
          }).toList();

          if (mounted) {
            setState(() {
              // Inversion : les messages les plus récents en haut de la liste
              // → avec reverse: true dans ListView, ils seront en bas
              messages = newMessages.reversed.toList();
              channelAnnouncement = (announcement != null && announcement.trim().isNotEmpty)
                  ? announcement.trim()
                  : null;
              isLoadingMessages = false;
            });

            // Ne scroller vers le bas que si l'utilisateur est déjà en bas
            // (_showScrollToBottom == false signifie qu'on est proche du bas)
            if (!_showScrollToBottom) {
              _scrollToBottom();
            }
            
            // Marquer les messages comme lus quand la conversation est ouverte
            _markMessagesAsRead();
          }
        } else {
          // Si success: false, initialiser avec une liste vide au lieu de lancer une exception
          developer.log('fetchMessages: API returned success: false, initializing with empty list', name: 'GroupeChatPage');
          if (mounted) {
            setState(() {
              messages = [];
              isLoadingMessages = false;
            });
          }
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        if (mounted) {
          SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
          Navigator.pop(context);
        }
        await authProvider.logout();
      } else if (response.statusCode == 500) {
        // Erreur serveur (500) : initialiser avec une liste vide sans afficher d'erreur
        developer.log('fetchMessages: HTTP 500 error, initializing with empty list (server error is usually temporary)', name: 'GroupeChatPage');
        if (mounted) {
          setState(() {
            messages = [];
            isLoadingMessages = false;
            // Ne pas définir errorMessage pour éviter d'afficher l'erreur à l'utilisateur
          });
        }
      } else {
        // Autres erreurs HTTP : initialiser avec une liste vide
        developer.log('fetchMessages: HTTP ${response.statusCode} error, initializing with empty list', name: 'GroupeChatPage');
        if (mounted) {
          setState(() {
            messages = [];
            isLoadingMessages = false;
            // Ne pas définir errorMessage pour éviter d'afficher l'erreur à l'utilisateur
          });
        }
      }
    } catch (e, s) {
      developer.log('fetchMessages error: $e', error: e, stackTrace: s, name: 'GroupeChatPage');
      // En cas d'exception, initialiser avec une liste vide au lieu d'afficher une erreur
      if (mounted) {
        setState(() {
          messages = [];
          isLoadingMessages = false;
          // Ne pas définir errorMessage pour éviter d'afficher l'erreur à l'utilisateur
        });
      }
    }
  }

  void _initializeWebSocket() {
    if (widget.groupId.isEmpty) return;

    // Initialiser le WebSocket
    _wsService.initialize(roomId: widget.groupId).then((_) {
      if (!mounted) return;

      // Écouter les nouveaux messages
      _wsMessageSubscription?.cancel();
      _wsMessageSubscription = _wsService.messageStream.listen((wsMessage) {
        if (!mounted) return;
        _handleWebSocketMessage(wsMessage);
      });

      // Écouter les suppressions de messages
      _wsDeleteSubscription?.cancel();
      _wsDeleteSubscription = _wsService.deleteMessageStream.listen((messageId) {
        if (!mounted) return;
        _handleWebSocketDelete(messageId);
      });

      // Écouter les changements de connexion
      _wsConnectionSubscription?.cancel();
      _wsConnectionSubscription = _wsService.connectionStream.listen((isConnected) {
        if (!mounted) return;
        developer.log('WebSocket connection status: $isConnected', name: 'GroupeChatPage');

        if (isConnected && widget.groupId.isNotEmpty) {
          _wsService.subscribeToRoom(widget.groupId);
          // Comme dans ChatPage : WebSocket actif → polling léger pour les mises à jour
          _pollingTimer?.cancel();
          _startPollingForUpdates();
          developer.log('WebSocket actif pour le groupe ${widget.groupId}, polling léger activé', name: 'GroupeChatPage');
        } else {
          // Si déconnecté, reprendre le polling normal
          if (_pollingTimer == null || !_pollingTimer!.isActive) {
            _startPolling();
          }
        }
      });
    }).catchError((error) {
      developer.log('Error initializing WebSocket: $error', name: 'GroupeChatPage');
    });
  }

  // ================== POLLING (copié de ChatPage, adapté au groupe) ==================

  void _startPolling() {
    _pollingTimer?.cancel();

    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        fetchMessages();
      } else {
        timer.cancel();
      }
    });

    developer.log('Started polling for new messages (GroupeChatPage)', name: 'GroupeChatPage');
  }

  // Polling léger pour détecter les modifications même avec WebSocket actif
  void _startPollingForUpdates() {
    _pollingTimer?.cancel();

    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && widget.groupId.isNotEmpty) {
        fetchMessages();
      } else {
        timer.cancel();
      }
    });

    developer.log('Started fast polling for message updates (WebSocket active, GroupeChatPage)', name: 'GroupeChatPage');
  }

  void _handleWebSocketMessage(Map<String, dynamic> wsMessage) {
    if (!mounted || widget.groupId.isEmpty) return;

    // Convertir le message WebSocket en format UI
    final message = _convertWebSocketMessageToUI(wsMessage);
    final messageId = message['id'];
    final isUpdate = wsMessage['isUpdate'] == true;

    // Ignorer les messages qui sont des images/vidéos (on les affiche uniquement via polling)
    final isMediaMessage =
        message['type'] == 'attachment' &&
            (message['attachments'] as List?)?.isNotEmpty == true &&
            ((message['attachments'][0] as Map?)?.containsKey('image_url') == true ||
                (message['attachments'][0] as Map?)?.containsKey('video_url') == true);

    final isMediaFile =
        message['file'] != null &&
            (message['file'] as Map<String, dynamic>?)?.containsKey('type') == true &&
            ((message['file']['type'] as String).startsWith('image/') ||
                (message['file']['type'] as String).startsWith('video/'));

    if (isMediaMessage || isMediaFile) {
      developer.log('WebSocket: Message média ignoré (image/vidéo) → affiché via fetchMessages uniquement', name: 'GroupeChatPage');
      return;
    }

    final existingIndex = messages.indexWhere((m) => m['id'] == messageId);

    if (existingIndex != -1 || isUpdate) {
      if (mounted) {
        setState(() {
          if (existingIndex != -1) {
            final existingMessage = messages[existingIndex];
            final updatedMessage = {
              ...existingMessage,
              ...message,
              'threadMessages': message['threadMessages'] ?? existingMessage['threadMessages'] ?? [],
              'threadCount': message['threadCount'] ?? existingMessage['threadCount'] ?? 0,
            };
            messages[existingIndex] = updatedMessage;
          } else {
            messages.insert(0, message);
          }
        });

        // Mettre à jour le cache
        SharedPreferences.getInstance().then((prefs) {
          if (widget.groupId.isNotEmpty) {
            final cached = prefs.getString('messages_cache_${widget.groupId}');
            if (cached != null) {
              final data = jsonDecode(cached);
              final cacheIndex = (data['messages'] as List).indexWhere((m) => m['id'] == messageId);
              if (cacheIndex != -1) {
                data['messages'][cacheIndex] = messages[existingIndex != -1 ? existingIndex : 0];
                prefs.setString('messages_cache_${widget.groupId}', jsonEncode(data));
              }
            }
          }
        });
      }
      return;
    }

    // Nouveau message texte, audio, fichier → affiché en temps réel
    if (mounted) {
      setState(() {
        messages.insert(0, message);
      });

      // Mettre à jour le cache
      SharedPreferences.getInstance().then((prefs) {
        if (widget.groupId.isNotEmpty) {
          final cached = prefs.getString('messages_cache_${widget.groupId}');
          final data = cached != null ? jsonDecode(cached) : {'messages': <Map<String, dynamic>>[]};
          data['messages'].insert(0, message);
          prefs.setString('messages_cache_${widget.groupId}', jsonEncode(data));
        }
      });

      // Scroll automatique si l'utilisateur est en bas
      final isAtBottom = _scrollController.offset <= 100;
      if (isAtBottom || message['isMe'] == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });
      }
    }
  }

  void _handleWebSocketDelete(String messageId) {
    if (!mounted) return;

    developer.log('WebSocket delete message received: $messageId', name: 'GroupeChatPage');

    setState(() {
      final removedCount = messages.length;
      messages.removeWhere((m) => m['id'] == messageId);
      final newCount = messages.length;

      if (removedCount != newCount) {
        developer.log('Message deleted from UI: $messageId (removed ${removedCount - newCount} message(s))', name: 'GroupeChatPage');
      } else {
        developer.log('Warning: Message $messageId not found in messages list', name: 'GroupeChatPage');
      }

      // Si on répondait à ce message
      if (_replyingToId == messageId) {
        _replyingToId = null;
        _replyingMessage = null;
      }
    });

    // Mettre à jour le cache
    SharedPreferences.getInstance().then((prefs) {
      if (widget.groupId.isNotEmpty) {
        final cached = prefs.getString('messages_cache_${widget.groupId}');
        if (cached != null) {
          final data = jsonDecode(cached);
          final beforeCount = (data['messages'] as List).length;
          data['messages'].removeWhere((m) => m['id'] == messageId);
          final afterCount = (data['messages'] as List).length;
          prefs.setString('messages_cache_${widget.groupId}', jsonEncode(data));
          developer.log('Message deleted from cache: $messageId (removed ${beforeCount - afterCount} message(s))', name: 'GroupeChatPage');
        }
      }
    });
  }

  /// Marque tous les messages non lus comme lus
  void _markMessagesAsRead() {
    if (!mounted) return;
    
    bool hasChanges = false;
    setState(() {
      for (var i = 0; i < messages.length; i++) {
        if (messages[i]['isUnread'] == true) {
          messages[i]['isUnread'] = false;
          hasChanges = true;
        }
      }
    });
    
    if (hasChanges) {
      // Mettre à jour le cache
      SharedPreferences.getInstance().then((prefs) {
        if (widget.groupId.isNotEmpty) {
          final cached = prefs.getString('messages_cache_${widget.groupId}');
          if (cached != null) {
            final data = jsonDecode(cached);
            final cacheMessages = data['messages'] as List;
            for (var i = 0; i < cacheMessages.length; i++) {
              if (cacheMessages[i]['isUnread'] == true) {
                cacheMessages[i]['isUnread'] = false;
              }
            }
            prefs.setString('messages_cache_${widget.groupId}', jsonEncode(data));
          }
        }
      });
    }
  }

  Map<String, dynamic> _convertWebSocketMessageToUI(Map<String, dynamic> wsMsg) {
    // Gérer replyTo : peut être un objet ou un ID
    dynamic replyTo = wsMsg['replyTo'];
    if (replyTo != null && replyTo is! Map) {
      // Si c'est juste un ID, chercher le message dans la liste pour obtenir les données
      final replyToId = replyTo.toString();
      final originalMsg = messages.firstWhere(
            (m) => m['id'] == replyToId,
        orElse: () => {
          'id': replyToId,
          'sender': 'Message supprimé',
          'username': 'Inconnu',
          'message': 'Ce message a été supprimé ou n\'est pas disponible.'
        },
      );
      replyTo = {
        'messageId': replyToId,
        'id': replyToId,
        'sender': originalMsg['sender'] ?? 'Message supprimé',
        'username': originalMsg['username'] ?? 'Inconnu',
        'message': originalMsg['message'] ?? 'Ce message a été supprimé ou n\'est pas disponible.'
      };
    } else if (replyTo is Map) {
      // Normaliser les champs si c'est déjà un objet
      final replyToObj = Map<String, dynamic>.from(replyTo);
      replyTo = {
        'messageId': replyToObj['messageId'] ?? replyToObj['id'],
        'id': replyToObj['messageId'] ?? replyToObj['id'],
        'sender': replyToObj['sender'] ?? replyToObj['name'] ?? replyToObj['username'] ?? 'Inconnu',
        'username': replyToObj['username'] ?? 'Inconnu',
        'message': replyToObj['message'] ?? replyToObj['text'] ?? 'Ce message a été supprimé ou n\'est pas disponible.',
      };
    }

    // Déterminer si le message est non lu (pas envoyé par l'utilisateur actuel)
    final isUnread = wsMsg['username'] != currentUser && wsMsg['isSent'] != true;
    
    // Convertir le format du websocket vers le format utilisé par groupe_chat_page
    return {
      'id': wsMsg['id'],
      'sender': wsMsg['name'] ?? wsMsg['username']?.toString() ?? 'Unknown',
      'message': wsMsg['text'] ?? '',
      'time': _formatTimestamp(wsMsg['timestamp']),
      'isMe': wsMsg['isSent'] ?? false,
      'isUnread': isUnread, // Flag pour les messages non lus
      'reactions': wsMsg['reactions'] ?? [],
      'timestamp': wsMsg['timestamp'],
      'username': wsMsg['username']?.toString() ?? '',
      'avatar': wsMsg['avatar'] ?? '',
      'type': wsMsg['type'] ?? 'text',
      'editedAt': wsMsg['editedAt'],
      'isEdited': wsMsg['isEdited'] ?? (wsMsg['editedAt'] != null),
      'replyTo': replyTo,
      'threadMessages': wsMsg['threadMessages'] ?? [],
      'threadCount': wsMsg['threadCount'] ?? 0,
      'attachments': wsMsg['attachments'] ?? [],
      'file': wsMsg['file'],
    };
  }

  Future<void> fetchMembers() async {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    const endpoint = '/api/chat/get-channel-members';

    try {
      final request = http.MultipartRequest('POST', Uri.parse('https://www.unistudious.com$endpoint'))
        ..fields['roomId'] = widget.groupId;

      final token = authProvider.token;
      if (token != null && token.isNotEmpty) {
        request.headers.addAll({'Authorization': 'Bearer $token'});
      }

      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> membersData = data['members'] ?? [];
          final List<Map<String, dynamic>> loadedMembers = membersData.map((member) {
            return {
              'name': member['name']?.toString() ?? member['username']?.toString() ?? 'Inconnu',
              'status': member['status']?.toString() ?? 'offline',
            };
          }).toList();

          if (mounted) {
            setState(() {
              membres = loadedMembers;
            });
          }
        }
      }
    } catch (e, s) {
      developer.log('fetchMembers error: $e', error: e, stackTrace: s, name: 'GroupeChatPage');
      if (mounted && membres.isEmpty) {
        setState(() {
          membres = [
            {'name': 'Chargement...', 'status': 'offline'},
          ];
        });
      }
    }
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return 'Maintenant';
    try {
      final timestamp = ts is String ? DateTime.parse(ts).toLocal() :
      ts is int ? DateTime.fromMillisecondsSinceEpoch(ts).toLocal() :
      DateTime.now();
      final now = DateTime.now();
      final difference = now.difference(timestamp);

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          if (difference.inMinutes == 0) return 'Maintenant';
          return '${difference.inMinutes}m';
        }
        return DateFormat('HH:mm').format(timestamp);
      } else if (difference.inDays == 1) {
        return 'Hier ${DateFormat('HH:mm').format(timestamp)}';
      } else if (difference.inDays < 7) {
        return DateFormat('EEE HH:mm').format(timestamp);
      } else {
        return DateFormat('dd/MM/yyyy HH:mm').format(timestamp);
      }
    } catch (e) {
      developer.log('Error formatting timestamp: $e', name: 'GroupeChatPage');
      return 'Maintenant';
    }
  }

  void _scrollListener() {
    final threshold = 100.0;
    final shouldShow = _scrollController.offset > threshold;
    if (shouldShow != _showScrollToBottom) {
      setState(() => _showScrollToBottom = shouldShow);
      shouldShow ? _animationController.forward() : _animationController.reverse();
    }
  }

  // Méthode helper pour construire un avatar avec cache (identique à groupes_page)
  Widget _buildAvatarWidget(String? url, String username, {double size = 40}) {
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.deepPurple,
        child: username.isNotEmpty
            ? Text(
          username[0].toUpperCase(),
          style: TextStyle(
            fontSize: size * 0.45,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        )
            : Icon(Icons.group, size: size * 0.6, color: Colors.white),
      );
    }

    // Avatar encodé en base64 (PNG inline)
    if (url.startsWith('data:image/png;base64,')) {
      try {
        final bytes = base64Decode(url.split(',').last);
        return ClipOval(
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: size,
            height: size,
          ),
        );
      } catch (_) {
        return CircleAvatar(
          radius: size / 2,
          backgroundColor: Colors.deepPurple,
          child: username.isNotEmpty
              ? Text(
            username[0].toUpperCase(),
            style: TextStyle(
              fontSize: size * 0.45,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          )
              : Icon(Icons.group, size: size * 0.6, color: Colors.white),
        );
      }
    }

    // SVG avatar
    final isSvg = url.endsWith('.svg') ||
        url.contains('message.unistudious.com/avatar/');

    if (isSvg) {
      // Vérifier le cache
      final cacheKey = username.isNotEmpty ? username : url;
      if (_avatarSvgCache.containsKey(cacheKey)) {
        final cached = _avatarSvgCache[cacheKey]!;
        return CircleAvatar(
          backgroundColor: cached['color'] as Color,
          radius: size / 2,
          child: Text(
            cached['initial'] as String,
            style: TextStyle(
              fontSize: size * 0.45,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      }

      // Charger et mettre en cache
      if (!_avatarFutures.containsKey(cacheKey)) {
        _avatarFutures[cacheKey] = _loadAndCacheSvg(url, cacheKey);
      }

      return SizedBox(
        width: size,
        height: size,
        child: FutureBuilder<Map<String, dynamic>>(
          key: ValueKey('avatar_$cacheKey'),
          future: _avatarFutures[cacheKey],
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              );
            }

            if (snapshot.hasData) {
              final avatarStyle = snapshot.data!;
              return CircleAvatar(
                backgroundColor: avatarStyle['color'] as Color,
                radius: size / 2,
                child: Text(
                  avatarStyle['initial'] as String,
                  style: TextStyle(
                    fontSize: size * 0.45,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              );
            }

            return CircleAvatar(
              radius: size / 2,
              backgroundColor: Colors.deepPurple,
              child: username.isNotEmpty
                  ? Text(
                username[0].toUpperCase(),
                style: TextStyle(
                  fontSize: size * 0.45,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              )
                  : Icon(Icons.group, size: size * 0.6, color: Colors.white),
            );
          },
        ),
      );
    }

    // Image réseau - utiliser CachedNetworkImage
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => Center(
            child: SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
          errorWidget: (context, url, error) => CircleAvatar(
            radius: size / 2,
            backgroundColor: Colors.deepPurple,
            child: username.isNotEmpty
                ? Text(
              username[0].toUpperCase(),
              style: TextStyle(
                fontSize: size * 0.45,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            )
                : Icon(Icons.group, size: size * 0.6, color: Colors.white),
          ),
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

      final avatarStyle = _extractAvatarStyleFromSvg(svgData);

      // Mettre en cache
      _avatarSvgCache[cacheKey] = avatarStyle;

      return avatarStyle;
    } catch (e) {
      developer.log('Error loading SVG avatar: $e', name: 'GroupeChatPage');
      return {'color': Colors.deepPurple, 'initial': '?'};
    }
  }

  Future<String?> _fetchAndSanitizeSvg(String url, String username) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      developer.log(
        'GroupeChatPage.fetchAndSanitizeSvg for $username: '
            '${response.statusCode} | ${response.headers['content-type']}',
        name: 'GroupeChatPage',
      );

      if (response.statusCode != 200) return null;

      final contentType = response.headers['content-type'] ?? '';

      if (!contentType.contains('image/svg')) {
        // Pas un SVG : on ne traite pas ici
        return null;
      }

      var svg = response.body;

      // Tenter de récupérer la taille du viewBox (ex: viewBox="0 0 200 200")
      double? vbWidth;
      double? vbHeight;

      final viewBoxMatch = RegExp(
        r'viewBox="\s*([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*"',
      ).firstMatch(svg);

      if (viewBoxMatch != null && viewBoxMatch.groupCount == 4) {
        try {
          vbWidth = double.parse(viewBoxMatch.group(3)!);
          vbHeight = double.parse(viewBoxMatch.group(4)!);
        } catch (_) {
          vbWidth = null;
          vbHeight = null;
        }
      }

      // Remplacer width/height en pourcentage par des valeurs numériques
      if (vbWidth != null || vbHeight != null) {
        svg = svg.replaceAllMapped(
          RegExp(r'(width|height)="([\d.]+)%"'),
              (m) {
            final attr = m.group(1);
            final percentStr = m.group(2);
            if (attr == null || percentStr == null) return m.group(0) ?? '';

            final p = double.tryParse(percentStr);
            if (p == null) return m.group(0) ?? '';

            if (attr == 'width' && vbWidth != null) {
              final v = vbWidth * p / 100.0;
              return 'width="$v"';
            }

            if (attr == 'height' && vbHeight != null) {
              final v = vbHeight * p / 100.0;
              return 'height="$v"';
            }

            return m.group(0) ?? '';
          },
        );
      }

      developer.log(
        'GroupeChatPage.Sanitized SVG for $username (length: ${svg.length})',
        name: 'GroupeChatPage',
      );

      return svg;
    } catch (e, s) {
      developer.log(
        'GroupeChatPage.fetchAndSanitizeSvg FAILED for $username: $e',
        error: e,
        stackTrace: s,
        name: 'GroupeChatPage',
      );
      return null;
    }
  }

  Map<String, dynamic> _extractAvatarStyleFromSvg(String svg) {
    // Couleur de fond : on cherche le premier <rect ... fill="...">
    final rectMatch =
    RegExp(r'<rect[^>]*fill="([^"]+)"', caseSensitive: false).firstMatch(svg);

    final bgFill = rectMatch?.group(1) ?? '#6200EE';

    // Texte (initiale) : contenu du premier <text>...</text>
    final textMatch =
    RegExp(r'<text[^>]*>([^<]+)</text>', caseSensitive: false).firstMatch(svg);

    final rawText = (textMatch?.group(1) ?? '').trim();
    final initial = rawText.isNotEmpty ? rawText[0].toUpperCase() : '?';

    return {
      'color': _colorFromHex(bgFill),
      'initial': initial,
    };
  }

  Color _colorFromHex(String hex) {
    var value = hex.replaceAll('#', '').trim();

    if (value.length == 6) {
      value = 'FF$value';
    }

    if (value.length != 8) {
      return Colors.deepPurple;
    }

    return Color(int.parse(value, radix: 16));
  }

  // Vérifie si l'utilisateur peut envoyer des messages (text, vocal, fichiers)
  bool _canSendMessage() {
    // Utiliser _isLeaderFromApi si disponible, sinon utiliser widget.isLeader
    final isLeader = _isLeaderFromApi || widget.isLeader;
    // Si isLeader est true, l'utilisateur peut toujours envoyer
    // Si isLeader est false ET readOnly est true, l'utilisateur ne peut pas envoyer
    final canSend = isLeader || !_readOnly;
    return canSend;
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || !mounted) return;
    
    // Vérifier les permissions pour les membres readOnly non-leaders
    if (!_canSendMessage()) {
      if (mounted) {
        SnackBarHelper.showWarning(context, 'Seul l\'admin peut envoyer des messages dans ce canal.');
      }
      return;
    }

    final messageContent = _messageController.text.trim();

    // Message optimiste
    final tempMessage = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'sender': currentUser ?? 'Toi',
      'message': messageContent,
        'time': 'Maintenant',
        'isMe': true,
        'reactions': {},
      'isSending': true,
    };

    setState(() {
      // On ajoute le nouveau message en DEBUT de liste (car reverse: true)
      messages.insert(0, tempMessage);
    });

    _messageController.clear();
    _scrollToBottom();

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    var endpoint = 'https://www.unistudious.com/api/chat/send-messages';

    if (_replyingToId != null) {
      endpoint = 'https://www.unistudious.com/api/chat/reply-message';
    }

    try {
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId;

      if (_replyingToId != null) {
        request.fields['text'] = messageContent;
        request.fields['replyToId'] = _replyingToId!;
      } else {
        request.fields['message'] = messageContent;
      }

      final token = authProvider.token;
      if (token == null || token.isEmpty) {
        throw Exception('Aucun token d\'authentification trouvé.');
      }

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final message = _replyingToId != null ? data['data']['message'] : (data['message'] ?? data);
          final replyToId = message['tmid'] ?? _replyingToId ?? message['replyTo'];

          // Enrichir replyTo avec les données du message original
          dynamic replyToData;
          if (replyToId != null && _replyingMessage != null) {
            final replyingMsg = _replyingMessage!;
            replyToData = {
              'messageId': replyToId.toString(),
              'id': replyToId.toString(),
              'sender': replyingMsg['sender'] ?? replyingMsg['username'] ?? 'Inconnu',
              'username': replyingMsg['username'] ?? 'Inconnu',
              'message': replyingMsg['message'] ?? 'Ce message a été supprimé ou n\'est pas disponible.',
            };
          } else if (replyToId != null) {
            // Chercher le message original dans la liste
            final originalMsg = messages.firstWhere(
              (m) => m['id'] == replyToId.toString(),
              orElse: () => {
                'sender': 'Message supprimé',
                'username': 'Inconnu',
                'message': 'Ce message a été supprimé ou n\'est pas disponible.',
              },
            );
            replyToData = {
              'messageId': replyToId.toString(),
              'id': replyToId.toString(),
              'sender': originalMsg['sender'] ?? 'Message supprimé',
              'username': originalMsg['username'] ?? 'Inconnu',
              'message': originalMsg['message'] ?? 'Ce message a été supprimé ou n\'est pas disponible.',
            };
          }

          final newMessage = {
            'id': message['id']?.toString() ?? message['_id']?.toString() ?? tempMessage['id'],
            'sender': message['name']?.toString() ?? message['u']?['name']?.toString() ?? message['username']?.toString() ?? currentUser ?? 'Toi',
            'message': message['text']?.toString() ?? message['msg']?.toString() ?? messageContent,
            'time': _formatTimestamp(message['timestamp'] ?? message['ts']),
            'isMe': true,
            'reactions': message['reactions'] is List ? message['reactions'] : (message['reactions'] is Map ? message['reactions'] : []),
            'timestamp': message['timestamp'] ?? message['ts'],
            'username': message['username']?.toString() ?? '',
            'avatar': message['avatar']?.toString() ?? '',
            'type': message['type']?.toString() ?? 'text',
            'editedAt': message['editedAt'],
            'isEdited': message['editedAt'] != null,
            'replyTo': replyToData,
            'threadMessages': message['threadMessages'] ?? [],
            'threadCount': message['threadCount'] ?? 0,
          };

          if (mounted) {
            setState(() {
              final index = messages.indexWhere((m) => m['id'] == tempMessage['id']);
              if (index != -1) {
                messages[index] = newMessage;
              } else {
                // Si pas trouvé (rare), on l'ajoute au début
                messages.insert(0, newMessage);
              }
              _replyingToId = null;
              _replyingMessage = null;
            });
            _scrollToBottom();
          }
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        if (mounted) {
          SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
          Navigator.pop(context);
        }
        await authProvider.logout();
      } else {
        throw Exception('Erreur HTTP ${response.statusCode}');
      }
    } catch (e, s) {
      developer.log('_sendMessage error: $e', error: e, stackTrace: s, name: 'GroupeChatPage');

      if (mounted) {
        setState(() {
          messages.removeWhere((m) => m['id'] == tempMessage['id']);
        });

      SnackBarHelper.showError(context, 'Erreur lors de l\'envoi: $e');
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0, // 0 = bas avec reverse: true
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleMoreOptionSelected(String option, int index) async {
    if (index < 0 || index >= messages.length) return;

    final message = messages[index];
    final isMe = message['isMe'] == true;

    switch (option) {
      case 'edit':
        if (isMe) {
          _startEditing(index);
        } else {
          SnackBarHelper.showWarning(context, 'Vous ne pouvez modifier que vos propres messages');
        }
        break;

      case 'reply':
        _cancelEditing();
        setState(() {
          _replyingToId = message['id']?.toString();
          _replyingMessage = Map.from(message);
        });
        break;

      case 'delete':
        if (isMe) {
          await _confirmDeleteMessage(index);
        } else {
          SnackBarHelper.showWarning(context, 'Vous ne pouvez supprimer que vos propres messages');
        }
        break;

      case 'copy':
        await Clipboard.setData(ClipboardData(text: message['message']?.toString() ?? ''));
        if (mounted) {
          SnackBarHelper.showSuccess(context, 'Message copié');
        }
        break;

      case 'transfer':
        await _transferMessage(index);
        break;
    }
  }

  void _startEditing(int index) {
    if (index < 0 || index >= messages.length) return;

    final message = messages[index];

    setState(() {
      _editingMessageId = message['id']?.toString();
      _editingIndex = index;
      _editController.text = message['message']?.toString() ?? '';
      // Annuler la réponse si on commence à éditer
      _replyingToId = null;
      _replyingMessage = null;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingMessageId = null;
      _editingIndex = null;
      _editController.clear();
    });
  }

  void _confirmEditing(int index) async {
    if (_editController.text.trim().isEmpty) {
      SnackBarHelper.showWarning(context, 'Le message ne peut pas être vide');
      return;
    }

    await _editMessage(
      messages[index]['id']?.toString() ?? '',
      _editController.text.trim(),
      index,
    );
  }

  Future<void> _editMessage(String messageId, String newText, int index) async {
    if (!mounted || index < 0 || index >= messages.length) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    const endpoint = 'https://www.unistudious.com/api/chat/edit-message';

    try {
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId
        ..fields['messageId'] = messageId
        ..fields['text'] = newText;

      final token = authProvider.token;
      if (token == null || token.isEmpty) {
        throw Exception('Aucun token d\'authentification trouvé.');
      }

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['result']?['success'] == true) {
          final editedMessage = data['result']['message'];

          if (mounted) {
            setState(() {
              final existing = messages[index];

              messages[index] = {
                'id': editedMessage['_id']?.toString() ?? messageId,
                'sender': editedMessage['u']?['name']?.toString() ??
                    existing['sender']?.toString() ??
                    currentUser ??
                    '',
                'message': editedMessage['msg']?.toString() ?? newText,
                'time': _formatTimestamp(
                  editedMessage['_updatedAt'] ?? editedMessage['ts'],
                ),
                'isMe': true,
                'reactions': existing['reactions'] ?? [],
                'timestamp': editedMessage['_updatedAt'] ?? editedMessage['ts'],
                'username': editedMessage['u']?['username']?.toString() ??
                    existing['username']?.toString() ??
                    '',
                'avatar': existing['avatar']?.toString() ??
                    editedMessage['avatar']?.toString() ??
                    '',
                'type': editedMessage['type']?.toString() ?? 'text',
                'editedAt': editedMessage['_updatedAt'],
                'isEdited': true,
                'replyTo': existing['replyTo'],
                'threadMessages': existing['threadMessages'] ?? [],
                'threadCount': existing['threadCount'] ?? 0,
              };

              _cancelEditing();
            });

            SnackBarHelper.showSuccess(context, 'Message modifié avec succès');
          }
        } else {
          throw Exception('Échec de la modification du message.');
        }
      } else {
        throw Exception(
          'Erreur ${response.statusCode} lors de la modification du message.',
        );
      }
    } catch (e, stackTrace) {
      developer.log(
        'Error editing message: $e',
        name: 'GroupeChatPage',
        error: e,
        stackTrace: stackTrace,
      );

      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors de la modification : $e');
      }
    }
  }

  Future<void> _transferMessage(int index) async {
    if (index < 0 || index >= messages.length) return;

    final message = messages[index];
    String? selectedRoomId;

    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? null : Colors.white,
              title: Text('Transférer le message', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              content: FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchAvailableGroups(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Voulez-vous transférer ce message ?', style: GoogleFonts.poppins()),
                        const SizedBox(height: 8),
                        Text(
                          message['message']?.toString() ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          snapshot.hasError
                            ? 'Erreur lors du chargement des groupes'
                            : 'Aucun groupe disponible',
                          style: GoogleFonts.poppins(color: Colors.red),
                        ),
                      ],
                    );
                  }

                  final groups = snapshot.data!
                      .where((group) => group['room_id']?.toString() != widget.groupId)
                      .toList();

                  if (groups.isEmpty) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Voulez-vous transférer ce message ?', style: GoogleFonts.poppins()),
                        const SizedBox(height: 8),
                        Text(
                          message['message']?.toString() ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 16),
                        Text('Aucun autre groupe disponible', style: GoogleFonts.poppins(color: Colors.grey)),
                      ],
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Voulez-vous transférer ce message ?', style: GoogleFonts.poppins()),
                      const SizedBox(height: 8),
                      Text(
                        message['message']?.toString() ?? '',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      Text('Destinataire :', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        dropdownColor: isDark ? null : Colors.white,
                        hint: Text(
                          'Sélectionner un groupe',
                          style: GoogleFonts.poppins(fontSize: 15),
                        ),
                        value: selectedRoomId,
                        items: groups.map((group) {
                          return DropdownMenuItem<String>(
                            value: group['room_id']?.toString() ?? group['id']?.toString(),
                            child: Text(group['name']?.toString() ?? 'Groupe sans nom', style: GoogleFonts.poppins()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedRoomId = value;
                          });
                          // Force rebuild of actions
                          setDialogState(() {});
                        },
                      ),
                    ],
                  );
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.grey[600])),
                ),
                TextButton(
                  onPressed: selectedRoomId == null
                      ? null
                      : () => Navigator.of(context).pop(selectedRoomId),
                  child: Text('Transférer', style: GoogleFonts.poppins(color: selectedRoomId == null ? Colors.grey : Colors.blue)),
                ),
              ],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            );
          },
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      await _forwardMessage(message['id']?.toString() ?? '', result);
    }
  }

  Future<bool> _joinChannel(String channelId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    const endpoint = 'https://www.unistudious.com/api/chat/join-channel';

    try {
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['id'] = channelId;

      final token = authProvider.token;
      if (token != null && token.isNotEmpty) {
        request.headers.addAll({'Authorization': 'Bearer $token'});
      }

      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data']?['success'] == true || data['success'] == true) {
          // Après avoir rejoint, récupérer les messages du canal
          await _getChannelMessages(channelId);
          return true;
        }
        return false;
      } else {
        developer.log('Error joining channel: ${response.statusCode}', name: 'GroupeChatPage');
        return false;
      }
    } catch (e, s) {
      developer.log('Error joining channel: $e', error: e, stackTrace: s, name: 'GroupeChatPage');
      return false;
    }
  }

  Future<void> _getChannelMessages(String channelId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    const endpoint = 'https://www.unistudious.com/api/chat/get-channel-messages';

    try {
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = channelId;

      final token = authProvider.token;
      if (token != null && token.isNotEmpty) {
        request.headers.addAll({'Authorization': 'Bearer $token'});
      }

      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        developer.log('Channel messages fetched successfully for $channelId', name: 'GroupeChatPage');
      } else {
        developer.log('Error fetching channel messages: ${response.statusCode}', name: 'GroupeChatPage');
      }
    } catch (e, s) {
      developer.log('Error fetching channel messages: $e', error: e, stackTrace: s, name: 'GroupeChatPage');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAvailableGroups() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final endpoint =
        widget.isPublicChannel ? '/api/chat/list-channels' : '/api/chat/my-channels';

    try {
      final response = await authProvider
          .authenticatedRequest('GET', endpoint)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = jsonDecode(response.body);

        if (jsonResponse['success'] != true) {
          throw Exception('API a retourné success: false');
        }

        final List<dynamic> channels = jsonResponse['channels'] ?? [];
        final List<Map<String, dynamic>> processedChannels = [];

        for (var channel in channels) {
          final channelId = channel['id']?.toString() ?? channel['_id']?.toString() ?? '';
          final roomId = channel['room_id']?.toString() ?? channelId;
          final joined = channel['joined'] ?? false;

          // Si le canal n'est pas rejoint, le joindre d'abord
          if (joined == false && channelId.isNotEmpty) {
            final joinSuccess = await _joinChannel(channelId);
            if (!joinSuccess) {
              // Si le join échoue, on skip ce canal
              continue;
            }
          }

          // Vérifier le type de canal
          final type = channel['type']?.toString().toLowerCase() ??
              (widget.isPublicChannel ? 'public' : 'private');

          // Propose uniquement les destinataires du même type que l'origine
          if (widget.isPublicChannel) {
            if (type != 'public') continue;
          } else {
            if (type != 'private') continue;
          }

          // Exclure le groupe/canal actuel
          if (roomId == widget.groupId) continue;

          processedChannels.add({
            'id': channelId,
            'room_id': roomId,
            'name': channel['name']?.toString() ??
                channel['username']?.toString() ??
                'Groupe sans nom',
            'type': type,
          });
        }

        return processedChannels;
      } else {
        throw Exception('Erreur HTTP ${response.statusCode}');
      }
    } catch (e, s) {
      developer.log('_fetchAvailableGroups error: $e', error: e, stackTrace: s, name: 'GroupeChatPage');
      return [];
    }
  }

  Future<void> _forwardMessage(String messageId, String targetRoomId) async {
    if (!mounted || widget.groupId.isEmpty || targetRoomId.isEmpty) return;

    const endpoint = 'https://www.unistudious.com/api/chat/forward-message';

    try {
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['messageId'] = messageId
        ..fields['targetRoomId'] = targetRoomId;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;
      if (token == null || token.isEmpty) {
        throw Exception('Aucun token d\'authentification trouvé.');
      }

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          if (mounted) {
            SnackBarHelper.showSuccess(context, 'Message transféré avec succès');
          }
        } else {
          throw Exception('Échec du transfert du message: ${data['message'] ?? 'Erreur inconnue'}');
        }
      } else {
        throw Exception('Erreur ${response.statusCode} lors du transfert du message.');
      }
    } catch (e, stackTrace) {
      developer.log('Error forwarding message: $e', name: 'GroupeChatPage', error: e, stackTrace: stackTrace);
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors du transfert : $e');
      }
    }
  }

  Future<void> _confirmDeleteMessage(int index) async {
    if (index < 0 || index >= messages.length) return;

    final message = messages[index];
    final isMe = message['isMe'] == true;

    if (!isMe) {
      SnackBarHelper.showWarning(context, 'Vous ne pouvez supprimer que vos propres messages');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Supprimer le message',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          content: Text(
            'Êtes-vous sûr de vouloir supprimer ce message ? Cette action est irréversible.',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Annuler',
                style: GoogleFonts.poppins(color: Colors.grey[600]),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Supprimer',
                style: GoogleFonts.poppins(color: Colors.red),
              ),
            ),
          ],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        );
      },
    );

    if (confirmed == true && mounted) {
      await _deleteMessage(message['id']?.toString() ?? '', index);
    }
  }

  Future<void> _deleteMessage(String messageId, int index) async {
    if (!mounted || messageId.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    const endpoint = 'https://www.unistudious.com/api/chat/delete-message';

    try {
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['messageId'] = messageId
        ..fields['roomId'] = widget.groupId;

      final token = authProvider.token;
      if (token == null || token.isEmpty) {
        throw Exception('Aucun token d\'authentification trouvé.');
      }

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          if (mounted && index >= 0 && index < messages.length) {
            setState(() {
              messages.removeAt(index);
              // Si on répondait à ce message, annuler la réponse
              if (_replyingToId == messageId) {
                _replyingToId = null;
                _replyingMessage = null;
              }
            });
          }
        } else {
          throw Exception('Erreur lors de la suppression');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        if (mounted) {
          SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
          Navigator.pop(context);
        }
        await authProvider.logout();
      } else {
        throw Exception('Erreur HTTP ${response.statusCode}');
      }
    } catch (e, s) {
      developer.log('Error deleting message: $e', error: e, stackTrace: s, name: 'GroupeChatPage');
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors de la suppression : $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers globaux pour le chargement d'images protégées
  // ---------------------------------------------------------------------------

  Future<Uint8List?> fetchProtectedImage(String url) async {
    try {
      developer.log('fetchProtectedImage (global): URL = "$url"', name: 'GroupeChatPage.Media');

      final uri = Uri.parse(url);
      final hasRcToken = uri.queryParameters.containsKey('rc_token');
      final hasRcUid = uri.queryParameters.containsKey('rc_uid');

      final headers = <String, String>{};

      // Pour les URLs Rocket.Chat avec rc_token/rc_uid, ne pas ajouter de header Authorization
      if (!hasRcToken || !hasRcUid) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token') ?? '';
        if (token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      }

      developer.log(
        'fetchProtectedImage (global): hasRcToken=$hasRcToken, hasRcUid=$hasRcUid, headers=$headers',
        name: 'GroupeChatPage.Media',
      );

      final response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 30));

      developer.log(
        'fetchProtectedImage (global): statusCode = ${response.statusCode}',
        name: 'GroupeChatPage.Media',
      );

      if (response.statusCode == 200) {
        developer.log(
          'fetchProtectedImage (global): succès, ${response.bodyBytes.length} bytes',
          name: 'GroupeChatPage.Media',
        );
        return response.bodyBytes;
      } else {
        developer.log(
          'fetchProtectedImage (global): échec HTTP ${response.statusCode}, body = ${response.body.length > 0 ? response.body.substring(0, response.body.length > 200 ? 200 : response.body.length) : "(vide)"}',
          name: 'GroupeChatPage.Media',
        );
        return null;
      }
    } catch (e, s) {
      developer.log(
        'fetchProtectedImage (global): exception lors du téléchargement de l\'image: $e',
        name: 'GroupeChatPage.Media',
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }

  // Helper pour obtenir l'URL complète
  String _getFullUrl(String? url) {
    developer.log('_getFullUrl: url originale = "$url"', name: 'GroupeChatPage.Media');
    if (url == null || url.isEmpty) {
      developer.log('_getFullUrl: URL vide ou null', name: 'GroupeChatPage.Media');
      return '';
    }
    if (url.startsWith('http')) {
      developer.log('_getFullUrl: URL complète déjà, retour = "$url"', name: 'GroupeChatPage.Media');
      return url;
    }
    final fullUrl = 'https://message.unistudious.com$url';
    developer.log('_getFullUrl: URL transformée = "$fullUrl"', name: 'GroupeChatPage.Media');
    return fullUrl;
  }

  // Helper pour enrichir une URL avec les tokens Rocket.Chat si nécessaire
  String _enrichUrlWithRcTokens(String url, Map<String, dynamic>? message) {
    final uri = Uri.parse(url);

    // Si l'URL a déjà les tokens, la retourner telle quelle
    if (uri.queryParameters.containsKey('rc_token') && uri.queryParameters.containsKey('rc_uid')) {
      developer.log('_enrichUrlWithRcTokens: URL a déjà les tokens Rocket.Chat', name: 'GroupeChatPage.Media');
      return url;
    }

    // Essayer d'extraire les tokens depuis le message
    String? rcToken;
    String? rcUid;

    // Chercher dans file['url']
    if (message?['file'] != null && message!['file'] is Map) {
      final fileUrl = message['file']['url']?.toString();
      if (fileUrl != null && fileUrl.isNotEmpty) {
        try {
          final fileUri = Uri.parse(fileUrl);
          rcToken = fileUri.queryParameters['rc_token'];
          rcUid = fileUri.queryParameters['rc_uid'];
        } catch (e) {
          developer.log('_enrichUrlWithRcTokens: Erreur parsing file URL: $e', name: 'GroupeChatPage.Media');
        }
      }
    }

    // Si pas trouvé, chercher dans files[0]['url']
    if ((rcToken == null || rcUid == null) && message?['files'] != null && message!['files'] is List && (message['files'] as List).isNotEmpty) {
      final files = message['files'] as List;
      final firstFile = files.first;
      if (firstFile is Map && firstFile['url'] != null) {
        final fileUrl = firstFile['url']?.toString();
        if (fileUrl != null && fileUrl.isNotEmpty) {
          try {
            final fileUri = Uri.parse(fileUrl);
            rcToken ??= fileUri.queryParameters['rc_token'];
            rcUid ??= fileUri.queryParameters['rc_uid'];
          } catch (e) {
            developer.log('_enrichUrlWithRcTokens: Erreur parsing files[0] URL: $e', name: 'GroupeChatPage.Media');
          }
        }
      }
    }

    // Si on a trouvé les tokens, les ajouter à l'URL
    if (rcToken != null && rcUid != null) {
      final enrichedUri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'rc_token': rcToken,
        'rc_uid': rcUid,
      });
      developer.log('_enrichUrlWithRcTokens: URL enrichie avec les tokens Rocket.Chat', name: 'GroupeChatPage.Media');
      return enrichedUri.toString();
    }

    developer.log('_enrichUrlWithRcTokens: Pas de tokens Rocket.Chat trouvés, URL retournée sans modification', name: 'GroupeChatPage.Media');
    return url;
  }

  // Helper pour obtenir l'URL du média depuis un attachment
  String? _getMediaUrlFromAttachment(Map<String, dynamic>? attachment) {
    developer.log('_getMediaUrlFromAttachment: attachment = $attachment', name: 'GroupeChatPage.Media');
    if (attachment == null) {
      developer.log('_getMediaUrlFromAttachment: attachment est null', name: 'GroupeChatPage.Media');
      return null;
    }

    final imageUrl = attachment['image_url']?.toString();
    final titleLink = attachment['title_link']?.toString();
    final audioUrl = attachment['audio_url']?.toString();
    final videoUrl = attachment['video_url']?.toString();

    developer.log('_getMediaUrlFromAttachment: image_url = "$imageUrl"', name: 'GroupeChatPage.Media');
    developer.log('_getMediaUrlFromAttachment: title_link = "$titleLink"', name: 'GroupeChatPage.Media');
    developer.log('_getMediaUrlFromAttachment: audio_url = "$audioUrl"', name: 'GroupeChatPage.Media');
    developer.log('_getMediaUrlFromAttachment: video_url = "$videoUrl"', name: 'GroupeChatPage.Media');

    final result = titleLink ?? imageUrl ?? videoUrl ?? audioUrl;
    developer.log('_getMediaUrlFromAttachment: résultat = "$result"', name: 'GroupeChatPage.Media');
    return result;
  }

  // Helper pour obtenir le preview base64 depuis un attachment
  String? _getImagePreviewBase64(Map<String, dynamic>? attachment) {
    if (attachment == null) return null;
    final preview = attachment['image_preview']?.toString();
    if (preview != null && preview.isNotEmpty && preview.startsWith('/9j/')) {
      developer.log('_getImagePreviewBase64: Preview base64 trouvé (${preview.length} chars)', name: 'GroupeChatPage.Media');
      return preview;
    }
    return null;
  }

  // Helper pour obtenir l'URL depuis le champ file
  String? _getMediaUrlFromFile(dynamic file) {
    developer.log('_getMediaUrlFromFile: file = $file', name: 'GroupeChatPage.Media');
    if (file == null) {
      developer.log('_getMediaUrlFromFile: file est null', name: 'GroupeChatPage.Media');
      return null;
    }
    if (file is Map<String, dynamic>) {
      final url = file['url']?.toString();
      final downloadUrl = file['download_url']?.toString();
      developer.log('_getMediaUrlFromFile: url = "$url", download_url = "$downloadUrl"', name: 'GroupeChatPage.Media');
      final result = url ?? downloadUrl;
      developer.log('_getMediaUrlFromFile: résultat = "$result"', name: 'GroupeChatPage.Media');
      return result;
    }
    final result = file.toString();
    developer.log('_getMediaUrlFromFile: résultat (toString) = "$result"', name: 'GroupeChatPage.Media');
    return result;
  }

  // Helper pour détecter le type de média
  String? _getMediaType(String? url, String? fileName) {
    developer.log('_getMediaType: url = "$url", fileName = "$fileName"', name: 'GroupeChatPage.Media');
    if (url == null || url.isEmpty) {
      developer.log('_getMediaType: URL vide ou null, retour null', name: 'GroupeChatPage.Media');
      return null;
    }

    final lowerUrl = url.toLowerCase();
    final lowerFileName = fileName?.toLowerCase() ?? '';

    // Extensions d'images
    final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];
    // Extensions de vidéos
    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm'];
    // Extensions audio
    final audioExtensions = ['.mp3', '.wav', '.ogg', '.m4a', '.aac', '.flac'];
    // Extensions PDF
    final pdfExtensions = ['.pdf'];

    // Vérifier par extension de fichier
    for (final ext in imageExtensions) {
      if (lowerUrl.contains(ext) || lowerFileName.endsWith(ext)) {
        developer.log('_getMediaType: détecté comme IMAGE (extension: $ext)', name: 'GroupeChatPage.Media');
        return 'image';
      }
    }
    for (final ext in videoExtensions) {
      if (lowerUrl.contains(ext) || lowerFileName.endsWith(ext)) {
        developer.log('_getMediaType: détecté comme VIDEO (extension: $ext)', name: 'GroupeChatPage.Media');
        return 'video';
      }
    }
    for (final ext in audioExtensions) {
      if (lowerUrl.contains(ext) || lowerFileName.endsWith(ext)) {
        developer.log('_getMediaType: détecté comme AUDIO (extension: $ext)', name: 'GroupeChatPage.Media');
        return 'audio';
      }
    }
    for (final ext in pdfExtensions) {
      if (lowerUrl.contains(ext) || lowerFileName.endsWith(ext)) {
        developer.log('_getMediaType: détecté comme PDF (extension: $ext)', name: 'GroupeChatPage.Media');
        return 'pdf';
      }
    }

    // Vérifier par type MIME dans l'URL
    if (lowerUrl.contains('image/') || lowerUrl.contains('jpeg') || lowerUrl.contains('png')) {
      developer.log('_getMediaType: détecté comme IMAGE (MIME)', name: 'GroupeChatPage.Media');
      return 'image';
    }
    if (lowerUrl.contains('video/') || lowerUrl.contains('mp4')) {
      developer.log('_getMediaType: détecté comme VIDEO (MIME)', name: 'GroupeChatPage.Media');
      return 'video';
    }
    if (lowerUrl.contains('audio/') || lowerUrl.contains('mp3')) {
      developer.log('_getMediaType: détecté comme AUDIO (MIME)', name: 'GroupeChatPage.Media');
      return 'audio';
    }
    if (lowerUrl.contains('application/pdf') || lowerUrl.contains('pdf')) {
      developer.log('_getMediaType: détecté comme PDF (MIME)', name: 'GroupeChatPage.Media');
      return 'pdf';
    }

    developer.log('_getMediaType: type non détecté, retour null', name: 'GroupeChatPage.Media');
    return null;
  }

  // API qui récupère le fichier audio via /api/chat/read/file-audio et le sauve en local
  Future<String?> _getPlayableFileUrl({
    required String fileId,
    required String fileName,
  }) async {
    const endpoint = 'https://www.unistudious.com/api/chat/read/file-audio';

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) return null;

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['fileId'] = fileId
        ..fields['fileName'] = fileName
        ..headers['Authorization'] = 'Bearer $token';

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 30));

      final statusCode = streamedResponse.statusCode;
      final rawBody = await streamedResponse.stream.bytesToString();

      if (statusCode == 200) {
        Map<String, dynamic> json;
        try {
          json = jsonDecode(rawBody) as Map<String, dynamic>;
        } catch (e) {
          developer.log(
            'Erreur de parsing JSON pour read/file-audio: $e, body: $rawBody',
            name: 'GroupeChatPage.Media',
          );
          return null;
        }

        final success = json['success'] == true;
        final fileBase64 = json['fileBase64'] as String?;
        final serverFileName = (json['fileName'] as String?) ?? fileName;

        if (!success || fileBase64 == null || fileBase64.isEmpty) {
          developer.log(
            'read/file-audio a répondu sans fichier utilisable: success=$success, fileBase64 length=${fileBase64?.length ?? 0}',
            name: 'GroupeChatPage.Media',
          );
          return null;
        }

        Uint8List bytes;
        try {
          bytes = base64Decode(fileBase64);
        } catch (e) {
          developer.log(
            'Erreur de décodage base64 pour read/file-audio: $e',
            name: 'GroupeChatPage.Media',
          );
          return null;
        }

        final tempDir = await getTemporaryDirectory();
        // Conserver le nom/extension retournés par l'API (important pour iOS/AVPlayer)
        final sanitizedName =
            serverFileName.replaceAll('/', '_').replaceAll('\\', '_');
        final tempFile = io.File(
          '${tempDir.path}/chat_media_${fileId}_${DateTime.now().millisecondsSinceEpoch}_$sanitizedName',
        );
        await tempFile.writeAsBytes(bytes);
        
        // Attendre un peu pour s'assurer que le fichier est complètement écrit
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Vérifier que le fichier existe et a une taille valide
        if (!await tempFile.exists()) {
          developer.log(
            'Le fichier temporaire n\'existe pas après écriture: ${tempFile.path}',
            name: 'GroupeChatPage.Media',
          );
          return null;
        }
        
        final fileSize = await tempFile.length();
        if (fileSize == 0) {
          developer.log(
            'Le fichier temporaire est vide (0 bytes): ${tempFile.path}',
            name: 'GroupeChatPage.Media',
          );
          return null;
        }
        
        if (fileSize != bytes.length) {
          developer.log(
            'ATTENTION: Taille du fichier sur disque ($fileSize) différente de la taille décodée (${bytes.length})',
            name: 'GroupeChatPage.Media',
          );
        }
        
        // Vérifier les premiers bytes pour s'assurer que c'est un fichier audio valide
        if (bytes.length >= 4) {
          final textStart = String.fromCharCodes(bytes.take(100));
          if (textStart.toLowerCase().contains('<html') || 
              textStart.toLowerCase().contains('<!doctype') ||
              textStart.toLowerCase().contains('error') ||
              textStart.toLowerCase().contains('{"error')) {
            developer.log(
              'Le serveur a retourné du HTML/JSON d\'erreur au lieu d\'un fichier audio',
              name: 'GroupeChatPage.Media',
            );
            return null;
          }
        }
        
        developer.log(
          'Fichier audio temporaire créé via read/file-audio : ${tempFile.path} (${fileSize} bytes)',
          name: 'GroupeChatPage.Media',
        );
        return tempFile.path;
      } else {
        developer.log(
          'Erreur read/file-audio : $statusCode $rawBody',
          name: 'GroupeChatPage.Media',
        );
        return null;
      }
    } catch (e, s) {
      developer.log('Exception dans _getPlayableFileUrl: $e', name: 'GroupeChatPage.Media', error: e, stackTrace: s);
      return null;
    }
  }

  // Clé de cache stable (on enlève rc_token et rc_uid car ils changent à chaque connexion)
  String _generateCacheKey(String url) {
    final uri = Uri.parse(url);
    final params = Map<String, String>.from(uri.queryParameters)
      ..remove('rc_token')
      ..remove('rc_uid');
    return Uri.parse(url).replace(queryParameters: params).toString();
  }

  // Helpers pour les miniatures vidéo
  Widget _buildCachedThumbnail(String thumbnailUrl, bool isDark, Map<String, dynamic>? message) {
    return CachedNetworkImage(
      imageUrl: _enrichUrlWithRcTokens(_getFullUrl(thumbnailUrl), message),
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: isDark ? Colors.grey[800] : Colors.grey[200],
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (context, url, error) => _buildVideoPlaceholder(isDark),
    );
  }

  Widget _buildBase64Thumbnail(String previewBase64, bool isDark) {
    try {
      final bytes = base64Decode(
        previewBase64.startsWith('data:image')
            ? previewBase64.split(',').last
            : previewBase64,
      );
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildVideoPlaceholder(isDark),
      );
    } catch (_) {
      return _buildVideoPlaceholder(isDark);
    }
  }

  Widget _buildVideoPlaceholder(bool isDark) {
    return Container(
      color: isDark ? Colors.grey[800] : Colors.grey[200],
      child: const Icon(Icons.videocam, size: 48, color: Colors.white70),
    );
  }

  // Widget pour afficher une image
  Widget _buildImageWidget(String imageUrl, bool isDark, {String? previewBase64}) {
    // 1. Si on a un preview base64 → affichage IMMÉDIAT
    if (previewBase64 != null && previewBase64.isNotEmpty) {
      try {
        Uint8List bytes;
        if (previewBase64.startsWith('data:image')) {
          bytes = base64Decode(previewBase64.split(',').last);
        } else {
          bytes = base64Decode(previewBase64);
        }

        return _buildImageContainer(
          child: Image.memory(bytes, fit: BoxFit.cover),
          imageUrl: imageUrl,
          isDark: isDark,
        );
      } catch (e) {
        developer.log('Erreur décodage preview base64', name: 'GroupeChatPage.Media');
      }
    }

    // 2. Sinon → on utilise CachedNetworkImage avec cache forcé
    final fullUrl = _getFullUrl(imageUrl);
    if (fullUrl.isEmpty) return const SizedBox.shrink();

    return _buildImageContainer(
      child: CachedNetworkImage(
        imageUrl: fullUrl,
        fit: BoxFit.cover,
        memCacheWidth: 800,
        fadeInDuration: const Duration(milliseconds: 300),
        placeholder: (context, url) => Container(
          color: isDark ? Colors.grey[800] : Colors.grey[300],
          child: const Center(
            child: SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          color: isDark ? Colors.grey[800] : Colors.grey[300],
          child: const Icon(Icons.error, color: Colors.red),
        ),
        cacheKey: _generateCacheKey(fullUrl),
      ),
      imageUrl: fullUrl,
      isDark: isDark,
    );
  }

  // Conteneur commun avec GestureDetector pour zoom
  Widget _buildImageContainer({
    required Widget child,
    required String imageUrl,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _ImageViewerScreen(imageUrl: imageUrl),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.6,
          height: 200,
          child: child,
        ),
      ),
    );
  }

  // Widget pour afficher une vidéo avec miniature (si dispo)
  Widget _buildVideoWidget(String videoUrl, bool isDark, Map<String, dynamic> message) {
    // Extraire fileId et fileName depuis le message
    final fileId = message['file']?['_id']?.toString() ??
        message['files']?[0]?['_id']?.toString();

    final fileName = message['file']?['name']?.toString() ??
        message['files']?[0]?['name']?.toString() ??
        'video.mp4';

    // Chercher une miniature dans les attachments
    String? thumbnailUrl;
    String? previewBase64;
    if (message['attachments'] != null && (message['attachments'] as List).isNotEmpty) {
      final attachment = (message['attachments'] as List).first as Map<String, dynamic>;
      thumbnailUrl = attachment['image_url']?.toString() ?? attachment['thumb_url']?.toString();
      previewBase64 = attachment['image_preview']?.toString();
    }

    if (fileId == null) {
      return _buildVideoFallback(
        videoUrl,
        isDark,
        thumbnailUrl: thumbnailUrl,
        previewBase64: previewBase64,
      );
    }

    return GestureDetector(
      onTap: () async {
        final localPath = await _getPlayableFileUrl(fileId: fileId, fileName: fileName);
        if (localPath != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => _VideoPlayerScreen(filePath: localPath, isNetwork: false),
            ),
          );
        } else {
          if (mounted) {
            SnackBarHelper.showError(context, 'Impossible de charger la vidéo');
          }
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.6,
          height: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (previewBase64 != null && previewBase64.isNotEmpty)
                _buildBase64Thumbnail(previewBase64, isDark)
              else if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                _buildCachedThumbnail(thumbnailUrl, isDark, message)
              else
                _buildVideoPlaceholder(isDark),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                ),
              ),
              const Center(
                child: Icon(Icons.play_circle_filled, size: 64, color: Colors.white),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Vidéo', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Fallback vidéo
  Widget _buildVideoFallback(String videoUrl, bool isDark, {String? thumbnailUrl, String? previewBase64}) {
    final fullUrl = _getFullUrl(videoUrl);

    return GestureDetector(
      onTap: () async {
        final bytes = await fetchProtectedImage(fullUrl);
        if (bytes == null || !mounted) {
          SnackBarHelper.showError(context, 'Impossible de charger la vidéo');
          return;
        }

        try {
          final tempDir = await getTemporaryDirectory();
          final tempFile = io.File('${tempDir.path}/fallback_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
          await tempFile.writeAsBytes(bytes);

          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => _VideoPlayerScreen(filePath: tempFile.path, isNetwork: false),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            SnackBarHelper.showError(context, 'Erreur de lecture vidéo : $e');
          }
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.6,
          height: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (previewBase64 != null && previewBase64.isNotEmpty)
                _buildBase64Thumbnail(previewBase64, isDark)
              else if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                _buildCachedThumbnail(thumbnailUrl, isDark, null)
              else
                _buildVideoPlaceholder(isDark),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                ),
              ),
              const Center(
                child: Icon(Icons.play_circle_filled, size: 64, color: Colors.white),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                  child: const Text('Vidéo', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Widget pour afficher un audio (message vocal)
  //
  // Utilise l'API /api/chat/read/file lorsque nous avons un fileId,
  // sinon on retombe sur l'URL enrichie comme avant.
  Widget _buildAudioWidget(
      String audioUrl, String? fileName, bool isDark, Map<String, dynamic> message) {
    final fileId = message['file']?['_id']?.toString() ??
        message['files']?[0]?['_id']?.toString();

    // Toujours utiliser le vrai nom de fichier Rocket.Chat pour l'API read/file
    final rcFileName = message['file']?['name']?.toString() ??
        message['files']?[0]?['name']?.toString();

    final nameForApi = rcFileName ?? fileName ?? 'audio';
    final nameForDisplay = fileName ?? rcFileName ?? 'audio';

    final audioKey = ValueKey('audio_${message['_id'] ?? message['id'] ?? fileId ?? audioUrl}');

    if (fileId == null) {
      // Fallback : ancien comportement avec URL enrichie
      final fullUrl = _getFullUrl(audioUrl);
      final enrichedUrl = _enrichUrlWithRcTokens(fullUrl, message);

      return _AudioPlayerWidget(
        key: audioKey,
        audioUrl: enrichedUrl,
        fileName: nameForDisplay,
        isDark: isDark,
      );
    }

    return FutureBuilder<String?>(
      key: audioKey,
      future: _getPlayableFileUrl(fileId: fileId, fileName: nameForApi),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: const CircularProgressIndicator(),
          );
        }

        final path = snapshot.data;
        if (path == null) {
          // Fallback : URL Rocket.Chat enrichie
          final fullUrl = _getFullUrl(audioUrl);
          final enrichedUrl = _enrichUrlWithRcTokens(fullUrl, message);

          return _AudioPlayerWidget(
            key: audioKey,
            audioUrl: enrichedUrl,
            fileName: nameForDisplay,
            isDark: isDark,
          );
        }

        return _AudioPlayerWidget(
          key: audioKey,
          audioUrl: path,
          fileName: nameForDisplay,
          isDark: isDark,
        );
      },
    );
  }

  // Widget pour afficher un PDF
  Widget _buildPdfWidget(String pdfUrl, String? fileName, bool isDark, Map<String, dynamic> message) {
    final fileId = message['file']?['_id']?.toString() ??
        message['files']?[0]?['_id']?.toString();

    final name = fileName ?? 'document.pdf';

    return GestureDetector(
      onTap: () async {
        String? localPath;
        
        if (fileId != null) {
          // Télécharger le fichier via l'API
          localPath = await _getPlayableFileUrl(fileId: fileId, fileName: name);
        } else {
          // Si pas d'ID, télécharger directement depuis l'URL
          try {
            final bytes = await fetchProtectedImage(_getFullUrl(pdfUrl));
            if (bytes != null && mounted) {
              final tempDir = await getTemporaryDirectory();
              final tempFile = io.File('${tempDir.path}/pdf_${DateTime.now().millisecondsSinceEpoch}.pdf');
              await tempFile.writeAsBytes(bytes);
              localPath = tempFile.path;
            }
          } catch (e) {
            developer.log('Error downloading PDF: $e', name: 'GroupeChatPage.Media');
          }
        }

        if (localPath != null && mounted) {
          final path = localPath!; // On est sûr que localPath n'est pas null ici
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => _PdfViewerScreen(filePath: path, fileName: name),
            ),
          );
        } else {
          if (mounted) {
            SnackBarHelper.showError(context, 'Impossible de charger le PDF');
          }
        }
      },
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.deepPurple[300]! : Colors.deepPurple[400]!,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.picture_as_pdf,
              color: Colors.deepPurple,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Appuyez pour ouvrir',
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: isDark ? Colors.white70 : Colors.black54,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // Fonction helper pour construire le widget média approprié depuis un message
  Widget? _buildMediaWidgetFromMessage(Map<String, dynamic> message, bool isDark) {
    developer.log('_buildMediaWidgetFromMessage: Analyse du message', name: 'GroupeChatPage.Media');
    developer.log('_buildMediaWidgetFromMessage: message keys = ${message.keys.toList()}', name: 'GroupeChatPage.Media');
    developer.log('_buildMediaWidgetFromMessage: message type = ${message['type']}', name: 'GroupeChatPage.Media');
    developer.log('_buildMediaWidgetFromMessage: message[attachments] = ${message['attachments']}', name: 'GroupeChatPage.Media');
    developer.log('_buildMediaWidgetFromMessage: message[file] = ${message['file']}', name: 'GroupeChatPage.Media');
    developer.log('_buildMediaWidgetFromMessage: message[files] = ${message['files']}', name: 'GroupeChatPage.Media');

    // Vérifier d'abord les attachments
    if (message['attachments'] != null && (message['attachments'] as List).isNotEmpty) {
      developer.log('_buildMediaWidgetFromMessage: Traitement des attachments', name: 'GroupeChatPage.Media');

      final attachments = message['attachments'] as List;
      developer.log('_buildMediaWidgetFromMessage: Nombre d\'attachments = ${attachments.length}', name: 'GroupeChatPage.Media');

      final attachment = attachments.first as Map<String, dynamic>;
      developer.log('_buildMediaWidgetFromMessage: Premier attachment = $attachment', name: 'GroupeChatPage.Media');

      var mediaUrl = _getMediaUrlFromAttachment(attachment);

      if (mediaUrl == null || mediaUrl.isEmpty) {
        developer.log('_buildMediaWidgetFromMessage: mediaUrl vide depuis attachment, retour null', name: 'GroupeChatPage.Media');
        return null;
      }

      // Enrichir l'URL avec les tokens Rocket.Chat si nécessaire
      final fullUrl = _getFullUrl(mediaUrl);
      mediaUrl = _enrichUrlWithRcTokens(fullUrl, message);

      final title = attachment['title']?.toString() ?? '';
      final fileName = attachment['title']?.toString() ?? attachment['description']?.toString();
      final mediaType = _getMediaType(mediaUrl, fileName);

      developer.log('_buildMediaWidgetFromMessage: mediaUrl = "$mediaUrl", mediaType = "$mediaType"', name: 'GroupeChatPage.Media');

      if (mediaType == 'image') {
        developer.log('_buildMediaWidgetFromMessage: Construction du widget image', name: 'GroupeChatPage.Media');
        final previewBase64 = _getImagePreviewBase64(attachment);
        return _buildImageWidget(mediaUrl, isDark, previewBase64: previewBase64);
      } else if (mediaType == 'video') {
        developer.log('_buildMediaWidgetFromMessage: Construction du widget vidéo', name: 'GroupeChatPage.Media');
        return _buildVideoWidget(mediaUrl, isDark, message);
      } else if (mediaType == 'audio') {
        developer.log('_buildMediaWidgetFromMessage: Construction du widget audio', name: 'GroupeChatPage.Media');
        return _buildAudioWidget(mediaUrl, fileName, isDark, message);
      } else if (mediaType == 'pdf') {
        developer.log('_buildMediaWidgetFromMessage: Construction du widget PDF', name: 'GroupeChatPage.Media');
        return _buildPdfWidget(mediaUrl, fileName, isDark, message);
      } else {
        developer.log('_buildMediaWidgetFromMessage: Type média inconnu ou null: "$mediaType"', name: 'GroupeChatPage.Media');
      }
    }

    // Vérifier le champ file
    if (message['file'] != null && message['file'] is Map) {
      developer.log('_buildMediaWidgetFromMessage: Traitement du champ file', name: 'GroupeChatPage.Media');

      final file = message['file'] as Map<String, dynamic>;
      final fileUrl = file['url']?.toString();

      if (fileUrl == null || fileUrl.isEmpty) {
        developer.log('_buildMediaWidgetFromMessage: fileUrl vide depuis file, retour null', name: 'GroupeChatPage.Media');
        return null;
      }

      final category = file['category']?.toString().toLowerCase();
      final fileName = file['name']?.toString();

      developer.log('_buildMediaWidgetFromMessage: fileUrl = "$fileUrl", category = "$category"', name: 'GroupeChatPage.Media');

      if (category == 'image') {
        return _buildImageWidget(fileUrl, isDark);
      } else if (category == 'video') {
        return _buildVideoWidget(fileUrl, isDark, message);
      } else if (category == 'audio') {
        return _buildAudioWidget(fileUrl, fileName, isDark, message);
      } else if (category == 'file' || category == 'other') {
        // Pour les fichiers (PDF, etc.), essayer de détecter depuis l'URL
        final mediaType = _getMediaType(fileUrl, fileName);
        developer.log('_buildMediaWidgetFromMessage: Détection depuis URL, mediaType = "$mediaType"', name: 'GroupeChatPage.Media');

        if (mediaType == 'image') {
          return _buildImageWidget(fileUrl, isDark);
        } else if (mediaType == 'video') {
          return _buildVideoWidget(fileUrl, isDark, message);
        } else if (mediaType == 'audio') {
          return _buildAudioWidget(fileUrl, fileName, isDark, message);
        } else if (mediaType == 'pdf') {
          return _buildPdfWidget(fileUrl, fileName, isDark, message);
        }
      } else {
        // Si category n'est pas définie, essayer de détecter depuis l'URL
        final mediaType = _getMediaType(fileUrl, fileName);
        developer.log('_buildMediaWidgetFromMessage: Détection depuis URL, mediaType = "$mediaType"', name: 'GroupeChatPage.Media');

        if (mediaType == 'image') {
          return _buildImageWidget(fileUrl, isDark);
        } else if (mediaType == 'video') {
          return _buildVideoWidget(fileUrl, isDark, message);
        } else if (mediaType == 'audio') {
          return _buildAudioWidget(fileUrl, fileName, isDark, message);
        } else if (mediaType == 'pdf') {
          return _buildPdfWidget(fileUrl, fileName, isDark, message);
        }
      }
    }

    // Vérifier le champ files
    if (message['files'] != null && (message['files'] as List).isNotEmpty) {
      developer.log('_buildMediaWidgetFromMessage: Traitement du champ files', name: 'GroupeChatPage.Media');

      final files = message['files'] as List;
      final file = files.first;
      final fileUrl = _getMediaUrlFromFile(file);

      if (fileUrl == null || fileUrl.isEmpty) {
        developer.log('_buildMediaWidgetFromMessage: fileUrl vide depuis files, retour null', name: 'GroupeChatPage.Media');
        return null;
      }

      final fileName = (file is Map) ? file['name']?.toString() : null;
      final mediaType = _getMediaType(fileUrl, fileName);

      if (mediaType == 'image') {
        return _buildImageWidget(fileUrl, isDark);
      } else if (mediaType == 'video') {
        return _buildVideoWidget(fileUrl, isDark, message);
      } else if (mediaType == 'audio') {
        return _buildAudioWidget(fileUrl, fileName, isDark, message);
      } else if (mediaType == 'pdf') {
        return _buildPdfWidget(fileUrl, fileName, isDark, message);
      }
    }

    developer.log('_buildMediaWidgetFromMessage: Aucun média détecté, retour null', name: 'GroupeChatPage.Media');
    return null;
  }

  // Fonction pour envoyer une réaction
  // Note: Les réactions fonctionnent toujours, indépendamment de l'état readOnly
  // Les utilisateurs peuvent réagir aux messages même si le canal est en lecture seule
  Future<void> _sendReaction(String messageId, String emoji) async {
    if (!mounted || widget.groupId.isEmpty) return;

    const endpoint = 'https://www.unistudious.com/api/chat/react-message';

    try {
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['messageId'] = messageId
        ..fields['emoji'] = emoji;

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['response']['success'] == true) {
          if (mounted) {
            setState(() {
              final messageIndex = messages.indexWhere((m) => m['id'] == messageId);
              if (messageIndex != -1) {
                final message = Map<String, dynamic>.from(messages[messageIndex]);
                
                // Gérer le cas où reactions peut être une List ou une Map
                final reactionsRaw = message['reactions'];
                Map<String, dynamic> reactions;
                
                if (reactionsRaw == null) {
                  reactions = {};
                } else if (reactionsRaw is Map) {
                  reactions = Map<String, dynamic>.from(reactionsRaw);
                } else if (reactionsRaw is List) {
                  // Si c'est une List, convertir en Map vide (pas de réactions structurées)
                  reactions = {};
                } else {
                  reactions = {};
                }
                
                final reactionKey = ':$emoji:';
                final usernames = reactions[reactionKey] != null ? List<String>.from(reactions[reactionKey]['usernames'] ?? []) : [];

                if (!usernames.contains(currentUser)) {
                  usernames.add(currentUser ?? 'Utilisateur');
                  reactions[reactionKey] = {'usernames': usernames};
                  message['reactions'] = reactions;
                  messages[messageIndex] = message;
                }
              }
              _reactionIndex = null;
              _highlightedIndex = null;
            });
            await fetchMessages();
          }
        } else {
          throw Exception('Échec de l\'envoi de la réaction.');
        }
      } else {
        throw Exception('Erreur ${response.statusCode} lors de l\'envoi de la réaction.');
      }
    } catch (e, stackTrace) {
      developer.log('Error sending reaction: $e', name: 'GroupeChatPage', error: e, stackTrace: stackTrace);
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors de l\'envoi de la réaction : $e');
      }
    }
  }

  // Fonction pour supprimer une réaction
  // Note: Les réactions fonctionnent toujours, indépendamment de l'état readOnly
  // Les utilisateurs peuvent supprimer leurs réactions même si le canal est en lecture seule
  Future<void> _removeReaction(String messageId, String emoji) async {
    if (!mounted || widget.groupId.isEmpty) return;

    const endpoint = 'https://www.unistudious.com/api/chat/remove-react-message';

    try {
      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['messageId'] = messageId
        ..fields['emoji'] = emoji;

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['response']['success'] == true) {
          if (mounted) {
            setState(() {
              final messageIndex = messages.indexWhere((m) => m['id'] == messageId);
              if (messageIndex != -1) {
                final message = Map<String, dynamic>.from(messages[messageIndex]);
                
                // Gérer le cas où reactions peut être une List ou une Map
                final reactionsRaw = message['reactions'];
                Map<String, dynamic> reactions;
                
                if (reactionsRaw == null) {
                  reactions = {};
                } else if (reactionsRaw is Map) {
                  reactions = Map<String, dynamic>.from(reactionsRaw);
                } else if (reactionsRaw is List) {
                  // Si c'est une List, convertir en Map vide (pas de réactions structurées)
                  reactions = {};
                } else {
                  reactions = {};
                }
                
                final reactionKey = ':$emoji:';

                if (reactions[reactionKey] != null) {
                  final usernames = List<String>.from(reactions[reactionKey]['usernames'] ?? []);
                  usernames.remove(currentUser);

                  if (usernames.isEmpty) {
                    reactions.remove(reactionKey);
                  } else {
                    reactions[reactionKey] = {'usernames': usernames};
                  }

                  message['reactions'] = reactions;
                  messages[messageIndex] = message;
                }
              }
              _reactionIndex = null;
              _highlightedIndex = null;
            });
            await fetchMessages();
          }
        } else {
          throw Exception('Échec de la suppression de la réaction.');
        }
      } else {
        throw Exception('Erreur ${response.statusCode} lors de la suppression de la réaction.');
      }
    } catch (e, stackTrace) {
      developer.log('Error removing reaction: $e', name: 'GroupeChatPage', error: e, stackTrace: stackTrace);
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors de la suppression de la réaction : $e');
      }
    }
  }

  // Fonction pour afficher le menu de réactions
  // Note: Les réactions fonctionnent toujours, indépendamment de l'état readOnly
  // Les utilisateurs peuvent réagir aux messages même si le canal est en lecture seule
  void _showReactions(BuildContext context, int index) {
    if (_editingMessageId != null) return;

    setState(() {
      _highlightedIndex = index;
      _reactionIndex = index;
    });
  }

  // Fonction pour basculer entre ajouter/supprimer une réaction
  // Note: Les réactions fonctionnent toujours, indépendamment de l'état readOnly
  // Les utilisateurs peuvent réagir aux messages même si le canal est en lecture seule
  void _toggleReaction(int index, String emoji) {
    if (!mounted || _editingMessageId != null) return;

    final messageId = messages[index]['id'];
    final reactionKey = ':${reactionLabels[emoji]}:';
    
    // Gérer le cas où reactions peut être une List ou une Map
    final reactionsData = messages[index]['reactions'];
    Map<String, dynamic> reactions;
    
    if (reactionsData == null) {
      reactions = {};
    } else if (reactionsData is Map) {
      reactions = Map<String, dynamic>.from(reactionsData);
    } else if (reactionsData is List) {
      // Si c'est une List, convertir en Map vide (pas de réactions structurées)
      reactions = {};
    } else {
      reactions = {};
    }
    
    final usernames = reactions[reactionKey] != null ? List<String>.from(reactions[reactionKey]['usernames'] ?? []) : [];

    if (usernames.contains(currentUser)) {
      _removeReaction(messageId, reactionLabels[emoji]!);
    } else {
      _sendReaction(messageId, reactionLabels[emoji]!);
    }
  }

  // Fonction pour gérer les clics en dehors du message
  void _handleOutsideClick() {
    _messageFocusNode.unfocus();

    if (_reactionIndex != null) {
      setState(() {
        _reactionIndex = null;
        _highlightedIndex = null;
      });
    }
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _messageController.dispose();
    _editController.dispose();
    _messageFocusNode.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _animationController.dispose();
    _pollingTimer?.cancel();
    _wsMessageSubscription?.cancel();
    _wsDeleteSubscription?.cancel();
    _wsConnectionSubscription?.cancel();
    _wsService.dispose();
    super.dispose();
  }

  // Fonction pour décoder le JWT et extraire le room depuis le payload
  String? _extractRoomFromJWT(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) {
        developer.log('❌ Invalid JWT format: expected 3 parts, got ${parts.length}', name: 'GroupeChatPage.Jitsi');
        return null;
      }
      
      // Décoder le payload (partie 2, index 1)
      final payload = parts[1];
      // Ajouter le padding si nécessaire pour base64
      String normalizedPayload = payload;
      switch (payload.length % 4) {
        case 1:
          normalizedPayload += '===';
          break;
        case 2:
          normalizedPayload += '==';
          break;
        case 3:
          normalizedPayload += '=';
          break;
      }
      
      final decodedBytes = base64Url.decode(normalizedPayload);
      final decodedString = utf8.decode(decodedBytes);
      final payloadMap = jsonDecode(decodedString) as Map<String, dynamic>;
      
      final room = payloadMap['room'] as String?;
      developer.log('✅ Extracted room from JWT: $room', name: 'GroupeChatPage.Jitsi');
      return room;
    } catch (e, stackTrace) {
      developer.log('❌ Error decoding JWT: $e', name: 'GroupeChatPage.Jitsi', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<Map<String, dynamic>?> _startCall({required bool isVideoCall}) async {
    if (!mounted) return null;
    
    // Vérifier les permissions pour les membres readOnly non-leaders
    if (!_canSendMessage()) {
      if (mounted) {
        SnackBarHelper.showWarning(context, 'Seul l\'admin peut démarrer un appel dans ce canal.');
      }
      return null;
    }

    const endpoint = 'https://www.unistudious.com/api/chat/start-call';

    try {
      developer.log('=== _startCall() ===', name: 'GroupeChatPage.Jitsi');
      developer.log('groupId: ${widget.groupId}', name: 'GroupeChatPage.Jitsi');
      developer.log('isVideoCall: $isVideoCall', name: 'GroupeChatPage.Jitsi');

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId;

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';

      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      );

      if (!mounted) return null;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        developer.log('API Response: ${jsonEncode(data)}', name: 'GroupeChatPage.Jitsi');

        if (data['success'] == true) {
          final message = data['data']['message'];
          
          // IMPORTANT: Utiliser le roomId comme source principale pour garantir que tous les utilisateurs
          // (web et mobile) rejoignent la même room. Le roomId est le même pour tous dans une conversation.
          String? roomName;
          
          // Priorité 1: Utiliser message['rid'] comme source principale (c'est le roomId de la conversation)
          if (message['rid'] != null) {
            roomName = message['rid'].toString();
            // Nettoyer le roomId (enlever "Message+" si présent)
            if (roomName.startsWith('Message+')) {
              roomName = roomName.substring(8);
            }
            developer.log('✅ Using roomName from message[rid]: $roomName', name: 'GroupeChatPage.Jitsi');
          }
          
          // Priorité 2: Utiliser roomId de l'API s'il est disponible et message['rid'] n'est pas disponible
          if ((roomName == null || roomName.isEmpty) && data['roomId'] != null) {
            roomName = data['roomId'].toString();
            // Nettoyer le roomId (enlever "Message+" si présent)
            if (roomName.startsWith('Message+')) {
              roomName = roomName.substring(8);
            }
            developer.log('✅ Using roomId from API: $roomName', name: 'GroupeChatPage.Jitsi');
          }

          // Générer l'URL de meeting avec baseUrl + roomId + ?jwt= + jwtToken si disponible
          String? meetingUrl;
          String? jwt;
          
          if (data['baseUrl'] != null && data['jwt'] != null && roomName != null) {
            // Nouveau format: générer l'URL directement
            final baseUrl = data['baseUrl'].toString();
            jwt = data['jwt'].toString();
            // S'assurer que baseUrl se termine par /
            final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
            meetingUrl = '$cleanBaseUrl$roomName?jwt=$jwt';
            developer.log('✅ Generated meetingUrl from baseUrl: $meetingUrl', name: 'GroupeChatPage.Jitsi');
          } else {
            // Ancien format: utiliser meetingUrl de la réponse
            meetingUrl = data['meetingUrl'];
            developer.log('meetingUrl: $meetingUrl', name: 'GroupeChatPage.Jitsi');
            
            jwt = data['jwt'] ?? (meetingUrl != null && meetingUrl.contains('jwt=') ? meetingUrl.split('jwt=')[1].split('&')[0] : null);
            developer.log('jwt extracted: ${jwt != null ? "${jwt.substring(0, 20)}..." : "null"}', name: 'GroupeChatPage.Jitsi');
            
            // Fallback: Extraire depuis le JWT seulement si aucune autre source n'est disponible
            if ((roomName == null || roomName.isEmpty) && jwt != null) {
              roomName = _extractRoomFromJWT(jwt);
              if (roomName != null) {
                developer.log('⚠️ Using room from JWT (fallback): $roomName', name: 'GroupeChatPage.Jitsi');
              }
            }

            // Normaliser l'URL retournée par l'API pour retirer le préfixe "Message+"
            if (meetingUrl != null) {
              final uri = Uri.parse(meetingUrl);
              String? urlRoom = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;

              if (urlRoom != null) {
                urlRoom = Uri.decodeComponent(urlRoom);

                // Retirer "Message+" si présent dans l'URL
                if (urlRoom.startsWith('Message+')) {
                  urlRoom = urlRoom.substring(8);
                }

                // Si roomName est encore null, l'initialiser avec la valeur nettoyée
                roomName ??= urlRoom;

                // Reconstruire l'URL propre sans "Message+"
                final normalizedBase = '${uri.scheme}://${uri.host}';
                final normalizedQuery = uri.hasQuery ? '?${uri.query}' : '';
                meetingUrl = '$normalizedBase/$urlRoom$normalizedQuery';

                developer.log('✅ Normalized meetingUrl without \"Message+\": $meetingUrl', name: 'GroupeChatPage.Jitsi');
              }
            }
          }

          final newMessage = {
            'id': message['_id'],
            'type': 'attachment',
            'username': currentUser,
            'name': message['u']['name'],
            'avatar': widget.avatarUrl,
            'timestamp': message['ts'],
            'reactions': {},
            'isSent': true,
            'text': message['msg'],
            'attachments': message['attachments'],
            'editedAt': null,
            'isEdited': false,
            'replyTo': null,
            'threadMessages': [],
            'threadCount': 0,
            'threadLastMessage': null,
          };

          if (mounted) {
            setState(() {
              messages.add(newMessage);
            });

            final prefs = await SharedPreferences.getInstance();
            final cachedMessages = prefs.getString('messages_cache_${widget.groupId}');
            final cacheData = cachedMessages != null ? jsonDecode(cachedMessages) : {'messages': []};
            cacheData['messages'].add(newMessage);
            await prefs.setString('messages_cache_${widget.groupId}', jsonEncode(cacheData));
          }

          developer.log('✅ _startCall() returning: roomName=$roomName, jwt=${jwt != null ? "present" : "null"}', name: 'GroupeChatPage.Jitsi');
          return {'roomName': roomName, 'jwt': jwt, 'meetingUrl': meetingUrl};
        } else {
          developer.log('❌ API returned success=false', name: 'GroupeChatPage.Jitsi');
          throw Exception('Échec du lancement de l\'appel.');
        }
      } else {
        developer.log('❌ API returned status ${response.statusCode}', name: 'GroupeChatPage.Jitsi');
        throw Exception('Erreur ${response.statusCode} lors du lancement de l\'appel.');
      }
    } catch (e, stackTrace) {
      developer.log('❌ Error starting call: $e', name: 'GroupeChatPage.Jitsi', error: e, stackTrace: stackTrace);
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors du lancement de l\'appel : $e');
      }
      return null;
    }
  }

  Future<Map<String, dynamic>?> _joinCall() async {
    if (!mounted) return null;

    const endpoint = 'https://www.unistudious.com/api/chat/join-call';

    try {
      developer.log('=== _joinCall() ===', name: 'GroupeChatPage.Jitsi');
      developer.log('groupId: ${widget.groupId}', name: 'GroupeChatPage.Jitsi');

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = widget.groupId;

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';

      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      );

      if (!mounted) return null;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        developer.log('API Response: ${jsonEncode(data)}', name: 'GroupeChatPage.Jitsi');

        if (data['success'] == true) {
          // IMPORTANT: Utiliser le roomId comme source principale pour garantir que tous les utilisateurs
          // (web et mobile) rejoignent la même room. Le roomId est le même pour tous dans une conversation.
          String? roomName;
          
          // Priorité 1: Utiliser roomId de l'API s'il est disponible
          if (data['roomId'] != null) {
            roomName = data['roomId'].toString();
            // Nettoyer le roomId (enlever "Message+" si présent)
            if (roomName.startsWith('Message+')) {
              roomName = roomName.substring(8);
            }
            developer.log('✅ Using roomId from API: $roomName', name: 'GroupeChatPage.Jitsi');
          }
          
          // Priorité 2: Utiliser message['rid'] si roomId de l'API n'est pas disponible
          if ((roomName == null || roomName.isEmpty) && data['data'] != null && data['data']['message'] != null) {
            final message = data['data']['message'];
            if (message['rid'] != null) {
              roomName = message['rid'].toString();
              // Nettoyer le roomId (enlever "Message+" si présent)
              if (roomName.startsWith('Message+')) {
                roomName = roomName.substring(8);
              }
              developer.log('✅ Using roomName from message[rid]: $roomName', name: 'GroupeChatPage.Jitsi');
            }
          }

          // Générer l'URL de meeting avec baseUrl + roomId + ?jwt= + jwtToken si disponible
          String? meetingUrl;
          String? jwt;
          
          if (data['baseUrl'] != null && data['jwt'] != null && roomName != null) {
            // Nouveau format: générer l'URL directement
            final baseUrl = data['baseUrl'].toString();
            jwt = data['jwt'].toString();
            // S'assurer que baseUrl se termine par /
            final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
            meetingUrl = '$cleanBaseUrl$roomName?jwt=$jwt';
            developer.log('✅ Generated meetingUrl from baseUrl: $meetingUrl', name: 'GroupeChatPage.Jitsi');
          } else {
            // Ancien format: utiliser meetingUrl de la réponse
            meetingUrl = data['meetingUrl'];
            developer.log('meetingUrl: $meetingUrl', name: 'GroupeChatPage.Jitsi');
            
            jwt = data['jwt'] ?? (meetingUrl != null && meetingUrl.contains('jwt=') ? meetingUrl.split('jwt=')[1].split('&')[0] : null);
            developer.log('jwt from API: ${jwt != null ? "${jwt.substring(0, 20)}..." : "null"}', name: 'GroupeChatPage.Jitsi');
            
            // Fallback: Extraire depuis le JWT seulement si aucune autre source n'est disponible
            if ((roomName == null || roomName.isEmpty) && jwt != null) {
              roomName = _extractRoomFromJWT(jwt);
              if (roomName != null) {
                developer.log('⚠️ Using room from JWT (fallback): $roomName', name: 'GroupeChatPage.Jitsi');
              }
            }
            
            // Fallback: extraire de l'URL si toujours pas de roomName
            if ((roomName == null || roomName.isEmpty) && meetingUrl != null) {
              final uri = Uri.parse(meetingUrl);
              roomName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
              // Décoder les + en espaces (URL encoding)
              if (roomName != null) {
                roomName = Uri.decodeComponent(roomName);
                // Extraire seulement la partie après "Message+" si présent
                if (roomName.startsWith('Message+')) {
                  roomName = roomName.substring(8); // Enlever "Message+"
                }
              }
              developer.log('⚠️ Using roomName from URL (fallback): $roomName', name: 'GroupeChatPage.Jitsi');
            }
            
            // Dernier fallback: message['rid']
            if ((roomName == null || roomName.isEmpty) && data['data'] != null && data['data']['message'] != null) {
              final message = data['data']['message'];
              if (message['rid'] != null) {
                roomName = message['rid'].toString();
                // Nettoyer le roomId (enlever "Message+" si présent)
                if (roomName.startsWith('Message+')) {
                  roomName = roomName.substring(8);
                }
                developer.log('⚠️ Using roomName from message[rid] (fallback): $roomName', name: 'GroupeChatPage.Jitsi');
              }
            }
          }
          
          if (roomName == null || roomName.isEmpty || jwt == null || jwt.isEmpty) {
            developer.log('❌ Missing roomName or jwt. roomName=$roomName, jwt=${jwt != null ? "present" : "null"}', name: 'GroupeChatPage.Jitsi');
            throw Exception('Données de réunion invalides dans la réponse.');
          }

          developer.log('✅ _joinCall() returning: roomName=$roomName, jwt=${jwt != null ? "present" : "null"}', name: 'GroupeChatPage.Jitsi');
          return {'roomName': roomName, 'jwt': jwt, 'meetingUrl': meetingUrl};
        } else {
          developer.log('❌ API returned success=false', name: 'GroupeChatPage.Jitsi');
          throw Exception('Échec du lancement de l\'appel.');
        }
      } else {
        developer.log('❌ API returned status ${response.statusCode}', name: 'GroupeChatPage.Jitsi');
        throw Exception('Erreur ${response.statusCode} lors du lancement de l\'appel.');
      }
    } catch (e, stackTrace) {
      developer.log('❌ Error joining call: $e', name: 'GroupeChatPage.Jitsi', error: e, stackTrace: stackTrace);
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors de la connexion à l\'appel : $e');
      }
      return null;
    }
  }

  Future<void> _launchCall({String? url, required bool isVideoCall}) async {
    developer.log('=== _launchCall() ===', name: 'GroupeChatPage.Jitsi');
    developer.log('url: $url', name: 'GroupeChatPage.Jitsi');
    developer.log('isVideoCall: $isVideoCall', name: 'GroupeChatPage.Jitsi');
    developer.log('groupId: ${widget.groupId}', name: 'GroupeChatPage.Jitsi');
    developer.log('currentUser: $currentUser', name: 'GroupeChatPage.Jitsi');
    
    // Si url est null, c'est un nouveau démarrage d'appel
    // Les membres readOnly non-leaders ne peuvent pas démarrer un appel, seulement rejoindre
    if (url == null && !_canSendMessage()) {
      if (mounted) {
        SnackBarHelper.showWarning(context, 'Seul l\'admin peut démarrer un appel dans ce canal. Vous pouvez seulement rejoindre un appel existant.');
      }
      return;
    }
    
    Map<String, dynamic>? meetingData;
    
    if (url == null) {
      // Démarrer un nouvel appel
      developer.log('Starting new call...', name: 'GroupeChatPage.Jitsi');
      meetingData = await _startCall(isVideoCall: isVideoCall);
    } else {
      // Rejoindre un appel existant - utiliser _joinCall() qui fait l'appel API
      // pour obtenir la même room que celle créée par _startCall() pour le même roomId
      developer.log('Joining existing call...', name: 'GroupeChatPage.Jitsi');
      meetingData = await _joinCall();
    }

    if (meetingData == null ||
        meetingData['roomName'] == null ||
        meetingData['jwt'] == null) {
      developer.log('❌ Missing meeting data. meetingData=$meetingData', name: 'GroupeChatPage.Jitsi');
      if (mounted) {
        SnackBarHelper.showError(context, 'Impossible de récupérer les données de réunion.');
      }
      return;
    }

    // Données renvoyées par l'API
    String roomName = meetingData['roomName'];
    String jwt = meetingData['jwt'];
    final String? meetingUrl = meetingData['meetingUrl'];

    // Domaine par défaut (fallback)
    String domain = 'https://meet.unistudious.com';

    // Si une meetingUrl générée est fournie, on la considère comme source de vérité
    if (meetingUrl != null) {
      try {
        final uri = Uri.parse(meetingUrl);

        // Domaine dynamique depuis l'URL (ex: https://meet.unistudious.com)
        domain = '${uri.scheme}://${uri.host}';

        // Room = dernier segment du path
        if (uri.pathSegments.isNotEmpty) {
          final lastSeg = uri.pathSegments.last;
          if (lastSeg.isNotEmpty) {
            roomName = Uri.decodeComponent(lastSeg);
          }
        }

        // JWT depuis le paramètre de query si présent
        final jwtFromUrl = uri.queryParameters['jwt'];
        if (jwtFromUrl != null && jwtFromUrl.isNotEmpty) {
          jwt = jwtFromUrl;
        }

        developer.log('✅ Using meetingUrl as source of truth:', name: 'GroupeChatPage.Jitsi');
        developer.log('  - meetingUrl: $meetingUrl', name: 'GroupeChatPage.Jitsi');
        developer.log('  - parsed domain: $domain', name: 'GroupeChatPage.Jitsi');
        developer.log('  - parsed roomName: $roomName', name: 'GroupeChatPage.Jitsi');
        developer.log('  - parsed jwt (start): ${jwt.substring(0, 20)}...', name: 'GroupeChatPage.Jitsi');
      } catch (e, stackTrace) {
        developer.log(
          '⚠️ Failed to parse meetingUrl, falling back to API fields. Error: $e',
          name: 'GroupeChatPage.Jitsi',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
    
    developer.log('🎯 Joining Jitsi room:', name: 'GroupeChatPage.Jitsi');
    developer.log('  - roomName: $roomName', name: 'GroupeChatPage.Jitsi');
    developer.log('  - jwt: ${jwt.substring(0, 20)}...', name: 'GroupeChatPage.Jitsi');
    developer.log('  - domain: $domain', name: 'GroupeChatPage.Jitsi');

    try {
      final options = JitsiMeetConferenceOptions(
        serverURL: domain,
        room: roomName,
        token: jwt,
        configOverrides: {
          'startWithAudioMuted': false,
          'startWithVideoMuted': url != null ? false : !isVideoCall,
        },
        featureFlags: {
          'welcomepage.enabled': false,
          'chat.enabled': false,
          'invite.enabled': false,
          'live-streaming.enabled': false,
          'recording.enabled': false,
          'add-people.enabled': false,
          'kick-out.enabled': false,
          'raise-hand.enabled': false,
          'tile-view.enabled': false,
          'video-share.enabled': false,
          'settings.enabled': false,
          'car-mode.enabled': false,
          'breakout-rooms.enabled': false,
          'security-options.enabled': false,
          'participants-stats.enabled': false,
          'enable-low-bandwidth-mode.enabled': false,
        },
        userInfo: JitsiMeetUserInfo(
          displayName: currentUser ?? 'Utilisateur',
          email: 'utilisateur@example.com',
        ),
      );

      developer.log('🚀 Calling _jitsiMeet.join() with room=$roomName', name: 'GroupeChatPage.Jitsi');
      await _jitsiMeet.join(options);
      developer.log('✅ Successfully joined Jitsi meeting', name: 'GroupeChatPage.Jitsi');
    } catch (e, stackTrace) {
      developer.log('❌ Error joining Jitsi meeting: $e',
          name: 'GroupeChatPage.Jitsi', error: e, stackTrace: stackTrace);
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors de la connexion à la réunion : $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              _buildAvatarWidget(
                widget.avatarUrl,
                widget.groupName,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.groupName,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (membres.isNotEmpty)
                      Text(
                        '${membres.length} membre${membres.length > 1 ? 's' : ''} • ${membres.where((m) => m['status'] == 'online').length} en ligne',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(
                Icons.call, 
                color: _canSendMessage() ? Colors.white : Colors.white38,
              ),
              onPressed: _canSendMessage() 
                ? () => _launchCall(isVideoCall: false)
                : null,
              tooltip: _canSendMessage() 
                ? 'Appel audio' 
                : 'Vous ne pouvez pas démarrer un appel en lecture seule',
            ),
            IconButton(
              icon: Icon(
                Icons.videocam, 
                color: _canSendMessage() ? Colors.white : Colors.white38,
              ),
              onPressed: _canSendMessage() 
                ? () => _launchCall(isVideoCall: true)
                : null,
              tooltip: _canSendMessage() 
                ? 'Appel vidéo' 
                : 'Vous ne pouvez pas démarrer un appel en lecture seule',
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white), // Icône plus claire
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GroupInfoPage(
                      groupId: widget.groupId,
                      groupName: widget.groupName,
                      avatarUrl: widget.avatarUrl,
                      members: membres.isNotEmpty ? membres : null, // Passer les membres si disponibles, sinon l'API les chargera
                      isLeader: widget.isLeader,
                    ),
                  ),
                );
                // Si le canal a été supprimé, remonter jusqu'à la liste des groupes
                if (result != null && result is Map && result['deleted'] == true) {
                  Navigator.pop(context, {'deleted': true, 'roomId': result['roomId']});
                  return;
                }
                // Si le canal a été quitté, retourner à la page précédente avec le roomId
                if (result != null && result is Map && result['left'] == true) {
                  Navigator.pop(context, {'left': true, 'roomId': result['roomId']});
                }
              },
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(isDark ? 'assets/msg dark.png' : 'assets/msg light.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: GestureDetector(
            onTap: _handleOutsideClick,
          child: Stack(
            children: [
              Column(
                children: [
                  if (channelAnnouncement != null && channelAnnouncement!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        // Fond plus opaque et légèrement coloré en dark mode
                        color: isDark
                            ? const Color(0xFF2A1B3D).withOpacity(0.95)  // Violet foncé semi-opaque
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF8E2DE2).withOpacity(0.5)  // Bordure violette visible
                              : Colors.deepPurple.withOpacity(0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? const Color(0xFF8E2DE2).withOpacity(0.2)
                                : Colors.black.withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.push_pin,
                            color: isDark ? Colors.amber[300] : Colors.deepPurple,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Annonce',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: isDark ? Colors.amber[200] : Colors.deepPurple[700],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  channelAnnouncement!,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: isDark ? Colors.white : Colors.black87,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: isLoadingMessages && messages.isEmpty
                        ? Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? Colors.white : Colors.deepPurple,
                        ),
                      ),
                    )
                        : errorMessage != null && messages.isEmpty
                        ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: isDark ? Colors.white70 : Colors.grey[600]),
                          const SizedBox(height: 16),
                          Text(errorMessage!, style: GoogleFonts.poppins(color: isDark ? Colors.white70 : Colors.grey[600], fontSize: 16), textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton(onPressed: _checkAuthAndFetchData, child: const Text('Réessayer')),
                        ],
                      ),
                    )
                        : ListView.builder(
                      controller: _scrollController,
                      reverse: true, // Important : les nouveaux messages en bas
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg['isMe'] == true;
                        final isEditing = _editingMessageId == msg['id'];
                        final isEditedMsg = msg['editedAt'] != null || msg['isEdited'] == true;

                        // Widget pour afficher le message cité (replyTo)
                        Widget? quotedWidget;
                        if (msg['replyTo'] != null) {
                          dynamic replyToData = msg['replyTo'];
                          String? replyToId;
                          Map<String, dynamic>? originalMessageData;

                          if (replyToData is Map) {
                            originalMessageData = Map<String, dynamic>.from(replyToData);
                            replyToId = originalMessageData['messageId'] ?? originalMessageData['id'];
                          } else {
                            replyToId = replyToData?.toString();
                          }

                          if (originalMessageData == null && replyToId != null) {
                            originalMessageData = messages.firstWhere(
                              (m) => m['id'] == replyToId,
                              orElse: () => {
                                'sender': 'Message supprimé',
                                'username': 'Inconnu',
                                'message': 'Ce message a été supprimé ou n\'est pas disponible.',
                                'id': replyToId
                              },
                            );
                          }

                          final originalMessage = originalMessageData ?? {
                            'sender': 'Message supprimé',
                            'username': 'Inconnu',
                            'message': 'Ce message a été supprimé ou n\'est pas disponible.'
                          };

                          // Ne pas afficher le widget si le message est vide
                          final replyText = originalMessage['message']?.toString() ?? '';
                          final replySender = originalMessage['sender'] ?? originalMessage['username'] ?? 'Inconnu';

                          if (replyText.isNotEmpty || replySender != 'Inconnu') {
                            quotedWidget = Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? (isDark ? Colors.black.withOpacity(0.2) : Colors.white.withOpacity(0.2))
                                    : (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
                                borderRadius: BorderRadius.circular(8),
                                border: Border(left: BorderSide(color: Colors.blueAccent, width: 4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    replySender,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: isMe
                                          ? Colors.white70
                                          : (isDark ? Colors.white70 : Colors.black87),
                                    ),
                                  ),
                                  if (replyText.isNotEmpty)
                                    Text(
                                      replyText,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: isMe
                                            ? Colors.white70
                                            : (isDark ? Colors.white70 : Colors.grey[600]),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: isEditing && isMe
                              ? Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.grey[900] : Colors.white,
                                  border: Border.all(color: Colors.blue, width: 2),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 6,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Édition',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.check, size: 20, color: Colors.green),
                                              onPressed: () => _confirmEditing(index),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.close, size: 20, color: Colors.red),
                                              onPressed: _cancelEditing,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    TextField(
                                      controller: _editController,
                                      maxLines: null,
                                      decoration: InputDecoration(
                                        hintText: 'Modifier votre message...',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide.none,
                                        ),
                                        filled: true,
                                        fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                                      ),
                                      style: GoogleFonts.poppins(
                                        color: isDark ? Colors.white : Colors.black87,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : GestureDetector(
                              onLongPress: () => _showReactions(context, index),
                              child: Row(
                            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe) ...[
                                const SizedBox(width: 8),
                                _buildAvatarWidget(
                                  msg['avatar']?.toString(),
                                  msg['sender']?.toString() ?? msg['username']?.toString() ?? '',
                                  size: 28,
                                ),
                                const SizedBox(width: 8),
                              Flexible(
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                          color: _highlightedIndex == index && !isEditing ? (isDark ? Colors.grey[700] : Colors.grey[300]) : (isDark ? Colors.grey[800] : Colors.grey[200]),
                                        borderRadius: BorderRadius.circular(20).copyWith(
                                            bottomLeft: const Radius.circular(0),
                                            bottomRight: const Radius.circular(20),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (quotedWidget != null) quotedWidget,
                                          // Afficher le nom de l'expéditeur au-dessus des médias
                                          if (!isMe && (msg['type'] == 'attachment' || msg['file'] != null || (msg['files'] != null && (msg['files'] as List).isNotEmpty))) ...[
                                            Text(
                                              msg['sender']?.toString() ?? msg['username']?.toString() ?? '',
                                              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.deepPurple[200]),
                                            ),
                                            const SizedBox(height: 4),
                                          ],
                                          // Essayer d'afficher un média (image, vidéo, audio)
                                          if (msg['type'] == 'attachment' || msg['file'] != null || (msg['files'] != null && (msg['files'] as List).isNotEmpty)) ...[
                                            Builder(
                                              builder: (context) {
                                                developer.log('=== DÉBUT TRAITEMENT ATTACHMENT (message reçu) ===', name: 'GroupeChatPage.Media');
                                                developer.log('Message complet: ${jsonEncode(msg)}', name: 'GroupeChatPage.Media');
                                                developer.log('msg[type]: ${msg['type']}', name: 'GroupeChatPage.Media');

                                                // Essayer d'afficher un média (image, vidéo, audio)
                                                final mediaWidget = _buildMediaWidgetFromMessage(msg, isDark);

                                                if (mediaWidget != null) {
                                                  developer.log('_buildMediaWidgetFromMessage a retourné un widget média', name: 'GroupeChatPage.Media');
                                                  return mediaWidget;
                                                }

                                                developer.log('_buildMediaWidgetFromMessage a retourné null, affichage format classique', name: 'GroupeChatPage.Media');
                                                return const SizedBox.shrink();
                                              },
                                            ),
                                          ],
                                          // Gestion des attachments d'appel
                                          if (msg['type'] == 'attachment' && msg['attachments'] != null && (msg['attachments'] as List).isNotEmpty) ...[
                                            Builder(
                                              builder: (context) {
                                                final attachments = msg['attachments'] as List;
                                                if (attachments.isEmpty) return const SizedBox.shrink();
                                                final attachment = attachments.first as Map<String, dynamic>;
                                                final actions = attachment['actions'] as List?;
                                                final String? actionText = (actions != null && actions.isNotEmpty)
                                                    ? actions[0]['text']?.toString()
                                                    : null;
                                                final String? actionUrl = (actions != null && actions.isNotEmpty)
                                                    ? actions[0]['url']?.toString()
                                                    : null;
                                                final String title = attachment['title']?.toString() ?? 'Video Call';
                                                final String description = attachment['text']?.toString() ?? 'Click the button below to join the meeting';

                                                if (actionUrl != null && actionText != null) {
                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.all(16),
                                                        decoration: BoxDecoration(
                                                          color: isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0),
                                                          borderRadius: BorderRadius.circular(16),
                                                        ),
                                                        child: Stack(
                                                          children: [
                                                            Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Row(
                                                                  children: [
                                                                    Text(
                                                                      title,
                                                                      style: GoogleFonts.poppins(
                                                                        color: Colors.white,
                                                                        fontSize: 16,
                                                                        fontWeight: FontWeight.w600,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                const SizedBox(height: 8),
                                                                Text(
                                                                  description,
                                                                  style: GoogleFonts.poppins(
                                                                    color: Colors.white,
                                                                    fontSize: 14,
                                                                  ),
                                                                ),
                                                                const SizedBox(height: 16),
                                                                ElevatedButton(
                                                                  onPressed: () => _launchCall(url: actionUrl, isVideoCall: true),
                                                                  style: ElevatedButton.styleFrom(
                                                                    backgroundColor: isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0),
                                                                    foregroundColor: Colors.white,
                                                                  ),
                                                                  child: Text(
                                                                    actionText,
                                                                    style: GoogleFonts.poppins(
                                                                      color: Colors.white,
                                                                      fontSize: 14,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            Positioned(
                                                              bottom: 0,
                                                              right: 0,
                                                              child: Text(
                                                                msg['time'] ?? '',
                                                                style: GoogleFonts.poppins(
                                                                  color: Colors.white70,
                                                                  fontSize: 10,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                }
                                                return const SizedBox.shrink();
                                              },
                                            ),
                                          ]
                                          else ...[
                                            // Afficher le nom de l'expéditeur seulement si ce n'est pas un média et pas déjà affiché au-dessus
                                            if (!isMe && !(msg['type'] == 'attachment' || msg['file'] != null || (msg['files'] != null && (msg['files'] as List).isNotEmpty))) ...[
                                            Text(
                                                msg['sender']?.toString() ?? msg['username']?.toString() ?? '',
                                              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.deepPurple[200]),
                                            ),
                                            ],
                                            LinkableText(
                                              text: msg['message']?.toString() ?? '',
                                              style: GoogleFonts.poppins(
                                                color: isDark ? Colors.white : Colors.black87,
                                                fontSize: 15,
                                                fontWeight: msg['isUnread'] == true ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                          // Timestamp seulement si ce n'est pas un message d'appel (le timestamp est dans la carte)
                                          if (msg['type'] != 'attachment' || msg['attachments'] == null || (msg['attachments'] as List).isEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              '${msg['time']}${isEditedMsg ? ' • Édité' : ''}',
                                              style: GoogleFonts.poppins(
                                                fontSize: 10,
                                                color: Colors.grey[600],
                                                fontStyle: isEditedMsg ? FontStyle.italic : FontStyle.normal,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                      // Menu de réactions
                                      if (_reactionIndex == index && !isEditing)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isDark ? Colors.grey[850] : Colors.grey[100],
                                            borderRadius: BorderRadius.circular(16),
                                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
                                          ),
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: reactions.map((reactionKey) => GestureDetector(
                                                  onTap: () => _toggleReaction(index, reactionKey),
                                                  child: Container(
                                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                                    padding: const EdgeInsets.all(4),
                                                    child: Text(reactionEmojis[reactionKey] ?? reactionKey, style: const TextStyle(fontSize: 20)),
                                                  ),
                                                )).toList(),
                                              ),
                                            ),
                                          ),
                                        ),
                                      // Affichage des réactions existantes
                                      if ((msg['reactions'] is List && (msg['reactions'] as List).isNotEmpty) ||
                                          (msg['reactions'] is Map && (msg['reactions'] as Map).isNotEmpty))
                                        Builder(
                                          builder: (context) {
                                            // Gérer le cas où reactions peut être une List ou une Map
                                            final reactionsRaw = msg['reactions'];
                                            Map<String, dynamic> reactionsData;
                                            
                                            if (reactionsRaw == null) {
                                              reactionsData = {};
                                            } else if (reactionsRaw is Map) {
                                              reactionsData = Map<String, dynamic>.from(reactionsRaw);
                                            } else if (reactionsRaw is List) {
                                              // Si c'est une List, convertir en Map vide (pas de réactions structurées)
                                              reactionsData = {};
                                            } else {
                                              reactionsData = {};
                                            }
                                            
                                            final displayedReactions = <Map<String, dynamic>>[];

                                            reactionsData.forEach((key, value) {
                                              // Extraire le code de réaction depuis la clé (format :thumbsup:)
                                              final code = key.replaceAll(':', '');
                                              // Trouver l'emoji correspondant
                                              final emojiEntry = reactionLabels.entries.firstWhere(
                                                (entry) => entry.value == code,
                                                orElse: () => const MapEntry('', ''),
                                              );

                                              if (emojiEntry.key.isNotEmpty) {
                                                final usernames = value['usernames'] is List ? List<String>.from(value['usernames']) : [];
                                                final count = usernames.length;
                                                final userReacted = usernames.contains(currentUser);

                                                displayedReactions.add({
                                                  'emoji': reactionEmojis[emojiEntry.key] ?? emojiEntry.key,
                                                  'code': code,
                                                  'count': count,
                                                  'userReacted': userReacted,
                                                  'reactionKey': emojiEntry.key,
                                                });
                                              }
                                            });

                                            if (displayedReactions.isEmpty) {
                                              return const SizedBox.shrink();
                                            }

                                            return Container(
                                        margin: const EdgeInsets.only(top: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.grey[850] : Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                                          ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: displayedReactions.map((reaction) => GestureDetector(
                                                  onTap: () => _toggleReaction(index, reaction['reactionKey']),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                                    child: Text(
                                                      reaction['count'] > 1 ? '${reaction['emoji']} ${reaction['count']}' : reaction['emoji'],
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        color: reaction['userReacted'] ? Colors.blue : null,
                                                      ),
                                                    ),
                                                  ),
                                                )).toList(),
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                                // Menu à 3 points pour les messages des autres (à droite)
                                Padding(
                                  padding: const EdgeInsets.only(left: 2, top: 8),
                                  child: PopupMenuButton<String>(
                                    icon: Icon(
                                      Icons.more_vert,
                                      size: 20,
                                      color: isDark ? Colors.white70 : Colors.grey[600],
                                    ),
                                    onSelected: (option) => _handleMoreOptionSelected(option, index),
                                    itemBuilder: (BuildContext context) => [
                                      PopupMenuItem<String>(
                                        value: 'reply',
                                        child: Row(
                                          children: [
                                            Icon(Icons.reply, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                                            const SizedBox(width: 8),
                                            Text('Répondre', style: GoogleFonts.poppins(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                                  ],
                                ),
                              ),
                                      PopupMenuItem<String>(
                                        value: 'transfer',
                                        child: Row(
                                          children: [
                                            Icon(Icons.forward, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                                            const SizedBox(width: 8),
                                            Text('Transférer', style: GoogleFonts.poppins(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'copy',
                                        child: Row(
                                          children: [
                                            Icon(Icons.copy, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                                            const SizedBox(width: 8),
                                            Text('Copier', style: GoogleFonts.poppins(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                                          ],
                                        ),
                                      ),
                                    ],
                                    color: isDark ? Colors.grey[850] : Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    offset: const Offset(0, 40),
                                  ),
                                ),
                              ],
                              if (isMe) ...[
                                // Menu à 3 points pour mes propres messages (à gauche, AVANT le message)
                                Padding(
                                  padding: const EdgeInsets.only(right: 2, top: 8),
                                  child: PopupMenuButton<String>(
                                    icon: Icon(
                                      Icons.more_vert,
                                      size: 20,
                                      color: isDark ? Colors.white70 : Colors.grey[600],
                                    ),
                                    onSelected: (option) => _handleMoreOptionSelected(option, index),
                                    itemBuilder: (BuildContext context) => [
                                      PopupMenuItem<String>(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                                            const SizedBox(width: 8),
                                            Text('Éditer', style: GoogleFonts.poppins(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'transfer',
                                        child: Row(
                                          children: [
                                            Icon(Icons.forward, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                                            const SizedBox(width: 8),
                                            Text('Transférer', style: GoogleFonts.poppins(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'reply',
                                        child: Row(
                                          children: [
                                            Icon(Icons.reply, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                                            const SizedBox(width: 8),
                                            Text('Répondre', style: GoogleFonts.poppins(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'copy',
                                        child: Row(
                                          children: [
                                            Icon(Icons.copy, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                                            const SizedBox(width: 8),
                                            Text('Copier', style: GoogleFonts.poppins(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete, size: 20, color: Colors.red),
                                            const SizedBox(width: 8),
                                            Text('Supprimer', style: GoogleFonts.poppins(color: Colors.red, fontSize: 14)),
                                          ],
                                        ),
                                      ),
                                    ],
                                    color: isDark ? Colors.grey[850] : Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    offset: const Offset(0, 40),
                                  ),
                                ),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: _highlightedIndex == index && !isEditing ? (isDark ? Colors.grey[700] : Colors.grey[300]) : (isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0)),
                                          borderRadius: BorderRadius.circular(20).copyWith(
                                            bottomLeft: const Radius.circular(20),
                                            bottomRight: const Radius.circular(0),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (quotedWidget != null) quotedWidget,
                                            // Afficher le nom de l'expéditeur au-dessus des médias (même pour les messages envoyés)
                                            if (msg['type'] == 'attachment' || msg['file'] != null || (msg['files'] != null && (msg['files'] as List).isNotEmpty)) ...[
                                              Text(
                                                msg['sender']?.toString() ?? msg['username']?.toString() ?? currentUser ?? 'Vous',
                                                style: GoogleFonts.poppins(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                            ],
                                            // Essayer d'afficher un média (image, vidéo, audio)
                                            if (msg['type'] == 'attachment' || msg['file'] != null || (msg['files'] != null && (msg['files'] as List).isNotEmpty)) ...[
                                              Builder(
                                                builder: (context) {
                                                  developer.log('=== DÉBUT TRAITEMENT ATTACHMENT (message envoyé) ===', name: 'GroupeChatPage.Media');
                                                  developer.log('Message complet: ${jsonEncode(msg)}', name: 'GroupeChatPage.Media');
                                                  developer.log('msg[type]: ${msg['type']}', name: 'GroupeChatPage.Media');

                                                  // Essayer d'afficher un média (image, vidéo, audio)
                                                  final mediaWidget = _buildMediaWidgetFromMessage(msg, isDark);

                                                  if (mediaWidget != null) {
                                                    developer.log('_buildMediaWidgetFromMessage a retourné un widget média', name: 'GroupeChatPage.Media');
                                                    return mediaWidget;
                                                  }

                                                  developer.log('_buildMediaWidgetFromMessage a retourné null, affichage format classique', name: 'GroupeChatPage.Media');
                                                  return const SizedBox.shrink();
                                                },
                                              ),
                                            ],
                                            // Gestion des attachments d'appel
                                            if (msg['type'] == 'attachment' && msg['attachments'] != null && (msg['attachments'] as List).isNotEmpty) ...[
                                              Builder(
                                                builder: (context) {
                                                  final attachments = msg['attachments'] as List;
                                                  if (attachments.isEmpty) return const SizedBox.shrink();
                                                  final attachment = attachments.first as Map<String, dynamic>;
                                                  final actions = attachment['actions'] as List?;
                                                  final String? actionText = (actions != null && actions.isNotEmpty)
                                                      ? actions[0]['text']?.toString()
                                                      : null;
                                                  final String? actionUrl = (actions != null && actions.isNotEmpty)
                                                      ? actions[0]['url']?.toString()
                                                      : null;
                                                  final String title = attachment['title']?.toString() ?? 'Video Call';
                                                  final String description = attachment['text']?.toString() ?? 'Click the button below to join the meeting';
                                                  
                                                  if (actionUrl != null && actionText != null) {
                                                    return Container(
                                                      margin: const EdgeInsets.only(top: 8),
                                                      padding: const EdgeInsets.all(16),
                                                      decoration: BoxDecoration(
                                                        color: isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0),
                                                        borderRadius: BorderRadius.circular(16),
                                                      ),
                                                      child: Stack(
                                                        children: [
                                                          Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Row(
                                                                children: [
                                                                  Text(
                                                                    title,
                                                                    style: GoogleFonts.poppins(
                                                                      color: Colors.white,
                                                                      fontSize: 16,
                                                                      fontWeight: FontWeight.w600,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(height: 8),
                                                              Text(
                                                                description,
                                                                style: GoogleFonts.poppins(
                                                                  color: Colors.white,
                                                                  fontSize: 14,
                                                                ),
                                                              ),
                                                              const SizedBox(height: 16),
                                                              ElevatedButton(
                                                                onPressed: () => _launchCall(url: actionUrl, isVideoCall: true),
                                                                style: ElevatedButton.styleFrom(
                                                                  backgroundColor: isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0),
                                                                  foregroundColor: Colors.white,
                                                                ),
                                                                child: Text(
                                                                  actionText,
                                                                  style: GoogleFonts.poppins(
                                                                    color: Colors.white,
                                                                    fontSize: 14,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          Positioned(
                                                            bottom: 0,
                                                            right: 0,
                                                            child: Text(
                                                              msg['time'] ?? '',
                                                              style: GoogleFonts.poppins(
                                                                color: Colors.white70,
                                                                fontSize: 10,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }
                                                  return const SizedBox.shrink();
                                                },
                                              ),
                                            ] else if (msg['message'] != null && msg['message'].toString().isNotEmpty) ...[
                                              LinkableText(
                                                text: msg['message']?.toString() ?? '',
                                                style: GoogleFonts.poppins(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ],
                                            // Timestamp seulement si ce n'est pas un message d'appel (le timestamp est dans la carte)
                                            if (msg['type'] != 'attachment' || msg['attachments'] == null || (msg['attachments'] as List).isEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                '${msg['time']}${isEditedMsg ? ' • Édité' : ''}',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 10,
                                                  color: Colors.white70,
                                                  fontStyle: isEditedMsg ? FontStyle.italic : FontStyle.normal,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      // Menu de réactions
                                      if (_reactionIndex == index && !isEditing)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isDark ? Colors.grey[850] : Colors.grey[100],
                                            borderRadius: BorderRadius.circular(16),
                                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
                                          ),
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: reactions.map((reactionKey) => GestureDetector(
                                                  onTap: () => _toggleReaction(index, reactionKey),
                                                  child: Container(
                                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                                    padding: const EdgeInsets.all(4),
                                                    child: Text(reactionEmojis[reactionKey] ?? reactionKey, style: const TextStyle(fontSize: 20)),
                                                  ),
                                                )).toList(),
                                              ),
                                            ),
                                          ),
                                        ),
                                      // Affichage des réactions existantes
                                      if ((msg['reactions'] is List && (msg['reactions'] as List).isNotEmpty) ||
                                          (msg['reactions'] is Map && (msg['reactions'] as Map).isNotEmpty))
                                        Builder(
                                          builder: (context) {
                                            // Gérer le cas où reactions peut être une List ou une Map
                                            final reactionsRaw = msg['reactions'];
                                            Map<String, dynamic> reactionsData;
                                            
                                            if (reactionsRaw == null) {
                                              reactionsData = {};
                                            } else if (reactionsRaw is Map) {
                                              reactionsData = Map<String, dynamic>.from(reactionsRaw);
                                            } else if (reactionsRaw is List) {
                                              // Si c'est une List, convertir en Map vide (pas de réactions structurées)
                                              reactionsData = {};
                                            } else {
                                              reactionsData = {};
                                            }
                                            
                                            final displayedReactions = <Map<String, dynamic>>[];

                                            reactionsData.forEach((key, value) {
                                              // Extraire le code de réaction depuis la clé (format :thumbsup:)
                                              final code = key.replaceAll(':', '');
                                              // Trouver l'emoji correspondant
                                              final emojiEntry = reactionLabels.entries.firstWhere(
                                                (entry) => entry.value == code,
                                                orElse: () => const MapEntry('', ''),
                                              );

                                              if (emojiEntry.key.isNotEmpty) {
                                                final usernames = value['usernames'] is List ? List<String>.from(value['usernames']) : [];
                                                final count = usernames.length;
                                                final userReacted = usernames.contains(currentUser);

                                                displayedReactions.add({
                                                  'emoji': reactionEmojis[emojiEntry.key] ?? emojiEntry.key,
                                                  'code': code,
                                                  'count': count,
                                                  'userReacted': userReacted,
                                                  'reactionKey': emojiEntry.key,
                                                });
                                              }
                                            });

                                            if (displayedReactions.isEmpty) {
                                              return const SizedBox.shrink();
                                          }

                                          return Container(
                                            margin: const EdgeInsets.only(top: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isDark ? Colors.grey[850] : Colors.white,
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                                            ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: displayedReactions.map((reaction) => GestureDetector(
                                                  onTap: () => _toggleReaction(index, reaction['reactionKey']),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                                    child: Text(
                                                      reaction['count'] > 1 ? '${reaction['emoji']} ${reaction['count']}' : reaction['emoji'],
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        color: reaction['userReacted'] ? Colors.blue : null,
                                                      ),
                                                    ),
                                                  ),
                                                )).toList(),
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_replyingToId != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: isDark ? Colors.grey[800] : Colors.grey[200],
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Réponse à ${_replyingMessage?['sender'] ?? _replyingMessage?['username'] ?? 'Inconnu'}',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                Text(
                                  _replyingMessage?['message']?.toString() ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: isDark ? Colors.white70 : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() {
                                _replyingToId = null;
                                _replyingMessage = null;
                              });
                            },
                          ),
                        ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    color: isDark ? Colors.grey[850] : Colors.white,
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.file_present, 
                            color: _canSendMessage() 
                              ? (isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0))
                              : Colors.grey,
                          ),
                          onPressed: _canSendMessage() 
                            ? _pickAndSendAttachment
                            : () {
                                SnackBarHelper.showWarning(context, 'Seul l\'admin peut envoyer des fichiers dans ce canal.');
                              },
                        ),
                        IconButton(
                          icon: Icon(
                            _isRecording ? Icons.stop : Icons.mic,
                            color: _isRecording
                                ? Colors.red
                                : (_canSendMessage()
                                    ? (isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0))
                                    : Colors.grey),
                          ),
                          onPressed: _canSendMessage() 
                            ? _handleMicPressed 
                            : () {
                                SnackBarHelper.showWarning(context, 'Seul l\'admin peut envoyer des messages vocaux dans ce canal.');
                              },
                        ),
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(25),
                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                                  ),
                                  child: TextField(
                                    controller: _messageController,
                                    focusNode: _messageFocusNode,
                                    enabled: _canSendMessage(),
                                    readOnly: !_canSendMessage(),
                                    decoration: InputDecoration(
                                      hintText: 'Écrire un message...',
                                      border: InputBorder.none,
                                      hintStyle: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.grey[600]),
                                    ),
                                    style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black87),
                                    onSubmitted: _canSendMessage() ? (_) => _sendMessage() : null,
                                  ),
                                ),
                                // Overlay qui bloque la zone de texte quand readOnly
                                // Affichage conditionnel : si readOnly est true ET que l'utilisateur n'est pas leader
                                if (!_canSendMessage())
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: false,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          _messageFocusNode.unfocus();
                                          SnackBarHelper.showWarning(context, 'Seul l\'admin peut envoyer des messages dans ce canal.');
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: isDark 
                                              ? Colors.orange.withOpacity(0.4) 
                                              : Colors.orange.withOpacity(0.35),
                                            borderRadius: BorderRadius.circular(25),
                                            border: Border.all(
                                              color: isDark 
                                                ? Colors.orange.withOpacity(0.9) 
                                                : Colors.orange.withOpacity(0.8),
                                              width: 2.5,
                                            ),
                                          ),
                                          child: Center(
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.lock_outline,
                                                    size: 22,
                                                    color: isDark ? Colors.orange[50] : Colors.orange[900],
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Flexible(
                                                    child: Text(
                                                      'Seul l\'admin peut envoyer des messages',
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 14,
                                                        color: isDark ? Colors.orange[50] : Colors.orange[900],
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                      textAlign: TextAlign.center,
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0),
                          child: IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: _canSendMessage() 
                              ? _sendMessage 
                              : () {
                                  SnackBarHelper.showWarning(context, 'Seul l\'admin peut envoyer des messages dans ce canal.');
                                },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Bouton descendre vers le bas
              if (_showScrollToBottom)
                Positioned(
                  bottom: 90,
                  right: 20,
                  child: AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(position: _slideAnimation, child: child),
                      );
                    },
                    child: FloatingActionButton(
                      mini: true,
                      backgroundColor: isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0),
                      onPressed: () {
                        _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                      },
                      child: const Icon(Icons.arrow_downward, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
            ),
          ),
        );
  }
}

// Widget pour lire un fichier audio
class _AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  final String fileName;
  final bool isDark;

  const _AudioPlayerWidget({
    super.key,
    required this.audioUrl,
    required this.fileName,
    required this.isDark,
  });

  @override
  State<_AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<_AudioPlayerWidget> {
  late AudioPlayer _audioPlayer;
  Source? _audioSource; // Pour rejouer après completion (resume() ne fonctionne pas)
  bool _isPlaying = false;
  bool _isInitialized = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initializeAudio();
  }

  Future<void> _initializeAudio() async {
    try {
      final rawUrl = widget.audioUrl.trim();

      // Si l'URL est vide ou invalide, on arrête proprement pour éviter "Bad state: No element"
      if (rawUrl.isEmpty) {
        developer.log(
          'Audio URL vide pour le fichier "${widget.fileName}"',
          name: 'AudioPlayerWidget',
        );
        if (mounted) {
          setState(() {
            _errorMessage = 'Aucun fichier audio disponible pour ce message.';
            _isInitialized = true;
          });
        }
        return;
      }

      // Vérifier si c'est un fichier local ou une URL
      final isLocalFile = !rawUrl.startsWith('http');

      if (isLocalFile) {
        // Pour les fichiers locaux, vérifier que le fichier existe et utiliser DeviceFileSource
        final localFile = io.File(rawUrl);
        if (!await localFile.exists()) {
          throw Exception('Le fichier audio local n\'existe pas: $rawUrl');
        }
        
        // Vérifier la taille du fichier
        final fileSize = await localFile.length();
        if (fileSize == 0) {
          throw Exception('Le fichier audio local est vide (0 bytes): $rawUrl');
        }
        
        // Vérifier que le fichier est lisible
        try {
          final testBytes = await localFile.readAsBytes();
          if (testBytes.isEmpty) {
            throw Exception('Le fichier audio local ne peut pas être lu: $rawUrl');
          }
          
          // Vérifier que ce n'est pas du HTML/JSON d'erreur
          if (testBytes.length >= 100) {
            final textStart = String.fromCharCodes(testBytes.take(100));
            if (textStart.toLowerCase().contains('<html') || 
                textStart.toLowerCase().contains('<!doctype') ||
                textStart.toLowerCase().contains('{"error')) {
              throw Exception('Le fichier local contient du HTML/JSON au lieu d\'un fichier audio: $rawUrl');
            }
          }
        } catch (e) {
          developer.log('Erreur lors de la vérification du fichier local: $e', name: 'AudioPlayerWidget', error: e);
          throw Exception('Le fichier audio local est corrompu ou inaccessible: $e');
        }
        
        developer.log('Lecture fichier local: $rawUrl (${fileSize} bytes)', name: 'AudioPlayerWidget');
        
        // Utiliser DeviceFileSource avec le chemin absolu
        _audioSource = DeviceFileSource(localFile.absolute.path);
        await _audioPlayer.setSource(_audioSource!);
      } else {
        // Sur iOS, AVPlayer peut avoir des problèmes avec certains formats M4A/MP3 depuis des URLs distantes.
        // On télécharge toujours le fichier sur iOS avant de le lire pour garantir la compatibilité.
        // Sur Android, on télécharge aussi pour les URLs Rocket.Chat, sinon on utilise setSourceUrl.
        final shouldDownload = io.Platform.isIOS || 
            rawUrl.contains('message.unistudious.com/file-upload/') ||
            rawUrl.contains('/file-upload/');
        
        if (shouldDownload) {
          developer.log('Téléchargement audio pour iOS: $rawUrl', name: 'AudioPlayerWidget');

          final uri = Uri.parse(rawUrl);
          final headers = <String, String>{};
          
          // Vérifier si l'URL contient déjà les tokens Rocket.Chat
          final hasRcToken = uri.queryParameters.containsKey('rc_token');
          final hasRcUid = uri.queryParameters.containsKey('rc_uid');
          
          // Pour les URLs Rocket.Chat avec rc_token/rc_uid, ne pas ajouter de header Authorization
          // Ces tokens dans l'URL sont suffisants pour l'authentification Rocket.Chat
          // Ajouter un header Bearer cause un conflit et retourne 403
          if (!hasRcToken || !hasRcUid) {
            // Seulement pour les URLs sans tokens Rocket.Chat, ajouter le Bearer token
            final prefs = await SharedPreferences.getInstance();
            final token = prefs.getString('auth_token') ?? '';
            if (token.isNotEmpty) {
              headers['Authorization'] = 'Bearer $token';
            }
          } else {
            developer.log('URL contient déjà les tokens Rocket.Chat, pas de header Authorization ajouté', name: 'AudioPlayerWidget');
          }

          final response =
              await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
          if (response.statusCode != 200) {
            throw Exception('HTTP ${response.statusCode} lors du chargement de l\'audio');
          }

          final tempDir = await getTemporaryDirectory();
          // Extraire l'extension du nom de fichier ou de l'URL
          String extension = '.m4a'; // Par défaut
          if (widget.fileName.isNotEmpty) {
            final dotIndex = widget.fileName.lastIndexOf('.');
            if (dotIndex > 0 && dotIndex < widget.fileName.length - 1) {
              extension = widget.fileName.substring(dotIndex);
            }
          } else {
            final fileNameFromUrl = uri.pathSegments.isNotEmpty
                ? uri.pathSegments.last
                : '';
            if (fileNameFromUrl.isNotEmpty) {
              final dotIndex = fileNameFromUrl.lastIndexOf('.');
              if (dotIndex > 0 && dotIndex < fileNameFromUrl.length - 1) {
                extension = fileNameFromUrl.substring(dotIndex);
              }
            }
          }
          
          final sanitizedName = widget.fileName.isNotEmpty 
              ? widget.fileName.replaceAll('/', '_').replaceAll('\\', '_')
              : 'audio_${DateTime.now().millisecondsSinceEpoch}$extension';
          final tempFile = io.File(
            '${tempDir.path}/chat_audio_${DateTime.now().millisecondsSinceEpoch}_$sanitizedName',
          );
          await tempFile.writeAsBytes(response.bodyBytes);
          
          developer.log('Fichier audio téléchargé: ${tempFile.path}', name: 'AudioPlayerWidget');
          _audioSource = DeviceFileSource(tempFile.path);
          await _audioPlayer.setSource(_audioSource!);
        } else {
          // Pour les autres URLs classiques sur Android uniquement, utiliser setSourceUrl directement
          // Sur iOS, on ne devrait jamais arriver ici grâce à la condition shouldDownload
          if (io.Platform.isIOS) {
            developer.log('ERREUR: Tentative d\'utiliser setSourceUrl sur iOS pour: $rawUrl', name: 'AudioPlayerWidget');
            throw Exception('iOS ne supporte pas setSourceUrl pour cette URL. Le téléchargement devrait avoir été effectué.');
          }
          _audioSource = UrlSource(rawUrl);
          await _audioPlayer.setSource(_audioSource!);
        }
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
      final errorText = e.toString();

      // Certains plugins audio iOS/Android lèvent parfois "Bad state: No element"
      // alors que la lecture fonctionne quand même. On adoucit donc ce cas.
      if (errorText.contains('Bad state: No element')) {
        developer.log(
          'Erreur bénigne "Bad state: No element" ignorée pendant l\'init audio',
          name: 'AudioPlayerWidget',
          error: e,
        );
        if (mounted && !_isInitialized) {
          setState(() {
            _isInitialized = true;
          });
        }
        return;
      }

      developer.log('Error initializing audio: $e', name: 'AudioPlayerWidget', error: e);
      if (mounted) {
        setState(() {
          _errorMessage = 'Erreur lors du chargement de l\'audio: $e';
          _isInitialized = true; // Pour permettre l'affichage de l'erreur
        });
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      // Quand l'audio est terminé (completed), resume() ne fonctionne pas - il faut appeler play() avec la source
      final state = _audioPlayer.state;
      final isCompleted = state == PlayerState.completed ||
          (_duration > Duration.zero && _position >= _duration - const Duration(milliseconds: 500));

      if (isCompleted && _audioSource != null) {
        await _audioPlayer.play(_audioSource!);
      } else {
        await _audioPlayer.resume();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Container(
        width: MediaQuery.of(context).size.width * 0.6,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.red[900] : Colors.red[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _errorMessage!,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
      );
    }

    return Container(
      width: MediaQuery.of(context).size.width * 0.6,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Couleurs distinctes pour mieux ressortir en dark/light
        color: widget.isDark ? Colors.grey[850]: Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: _isInitialized ? _togglePlayPause : null,
            color: widget.isDark ? Colors.white : Colors.black87,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.fileName,
                  style: GoogleFonts.poppins(
                    color: widget.isDark ? Colors.white : Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (!_isInitialized)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_duration != Duration.zero)
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _position.inSeconds.toDouble(),
                          min: 0,
                          max: _duration.inSeconds.toDouble(),
                          onChanged: (value) {
                            _audioPlayer.seek(Duration(seconds: value.toInt()));
                          },
                        ),
                      ),
                      Text(
                        '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                        style: GoogleFonts.poppins(
                          color: widget.isDark ? Colors.white70 : Colors.black54,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  )
                else
                  const SizedBox(height: 8),
              ],
            ),
          ),
        ],
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

// Screen pour afficher une image en plein écran
class _ImageViewerScreen extends StatelessWidget {
  final String imageUrl;

  const _ImageViewerScreen({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    developer.log('_ImageViewerScreen.build: imageUrl = "$imageUrl"', name: 'GroupeChatPage.Media');
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: AppBarGradient.flexibleSpace(isDark),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Image',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
      ),
      body: Center(
        child: _buildImageViewerContent(imageUrl),
      ),
    );
  }

  Widget _buildImageViewerContent(String url) {
    final uri = Uri.parse(url);
    final hasRcToken = uri.queryParameters.containsKey('rc_token');
    final hasRcUid = uri.queryParameters.containsKey('rc_uid');

    if (hasRcToken && hasRcUid) {
      return InteractiveViewer(
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          placeholder: (context, url) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          errorWidget: (context, url, error) {
            developer.log(
              '_ImageViewerScreen: Erreur lors du chargement de l\'image avec CachedNetworkImage: $error',
              name: 'GroupeChatPage.Media',
            );
            return SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.white, size: 48),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Erreur lors du chargement de l\'image',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } else {
      // Utiliser FutureBuilder avec fetchProtectedImage pour les autres URLs
      // Note: fetchProtectedImage doit être accessible depuis le contexte
      return FutureBuilder<Uint8List?>(
        future: _fetchImageBytes(url),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.white, size: 48),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Erreur lors du chargement de l\'image',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }

          return InteractiveViewer(
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
            ),
          );
        },
      );
    }
  }

  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      final uri = Uri.parse(url);
      final hasRcToken = uri.queryParameters.containsKey('rc_token');
      final hasRcUid = uri.queryParameters.containsKey('rc_uid');

      final headers = <String, String>{};

      if (!hasRcToken || !hasRcUid) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token') ?? '';
        if (token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      }

      final response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      developer.log('Error fetching image bytes: $e', name: 'GroupeChatPage.Media');
      return null;
    }
  }
}

// Screen pour afficher une vidéo en plein écran
class _VideoPlayerScreen extends StatefulWidget {
  final String filePath;
  final bool isNetwork;

  const _VideoPlayerScreen({
    required this.filePath,
    this.isNetwork = false,
  });

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
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
          setState(() => _isInitialized = true);
          _controller.play();
        }
      }).catchError((e) {
        if (mounted) {
          setState(() => _errorMessage = 'Erreur lors du chargement de la vidéo: $e');
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: AppBarGradient.flexibleSpace(isDark),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _errorMessage != null
          ? Center(child: Text(_errorMessage!, style: GoogleFonts.poppins(color: Colors.white)))
          : _isInitialized
          ? Center(child: AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)))
          : const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}

// Screen pour afficher un PDF en plein écran
class _PdfViewerScreen extends StatelessWidget {
  final String filePath;
  final String fileName;

  const _PdfViewerScreen({
    required this.filePath,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: AppBarGradient.flexibleSpace(isDark),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          fileName,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: PDFView(
        filePath: filePath,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: true,
        pageFling: true,
        onError: (error) {
          developer.log('Error loading PDF: $error', name: 'GroupeChatPage.PDF');
          SnackBarHelper.showError(context, 'Erreur lors du chargement du PDF: $error');
        },
        onRender: (pages) {
          developer.log('PDF rendered with $pages pages', name: 'GroupeChatPage.PDF');
        },
        onPageError: (page, error) {
          developer.log('Error on page $page: $error', name: 'GroupeChatPage.PDF');
          SnackBarHelper.showError(context, 'Erreur sur la page $page: $error');
        },
      ),
    );
  }
}