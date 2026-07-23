import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'dart:io' as io;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';

import 'package:file_picker/file_picker.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:image_picker/image_picker.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:video_player/video_player.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:record/record.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

import '../providers/auth_provider.dart';
import '../utils/app_bar_gradient.dart';
import '../utils/snackbar_helper.dart';

import '../services/rocketchat_websocket_service.dart';

import 'chat_details_page.dart';
import '../widgets/linkable_text.dart';

import 'dart:async';

import 'dart:io' as io;

import 'dart:typed_data';


Future<Uint8List?> fetchProtectedImage(String url) async {

  try {

    developer.log('fetchProtectedImage (global): URL = "$url"', name: 'ChatPage.Media');



    final uri = Uri.parse(url);

    final hasRcToken = uri.queryParameters.containsKey('rc_token');

    final hasRcUid = uri.queryParameters.containsKey('rc_uid');



    final headers = <String, String>{};



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

    }

    developer.log(

      'fetchProtectedImage (global): hasRcToken=$hasRcToken, hasRcUid=$hasRcUid, headers=$headers',

      name: 'ChatPage.Media',

    );

    final response = await http.get(uri, headers: headers);

    developer.log(

      'fetchProtectedImage (global): statusCode = ${response.statusCode}',

      name: 'ChatPage.Media',

    );

    if (response.statusCode == 200) {

      return response.bodyBytes;

    } else {

      developer.log(

        'fetchProtectedImage (global): échec HTTP ${response.statusCode}, body = ${response.body.length > 0 ? response.body.substring(0, response.body.length > 200 ? 200 : response.body.length) : "(vide)"}',

        name: 'ChatPage.Media',

      );

      return null;

    }

  } catch (e, s) {

    developer.log(

      'fetchProtectedImage (global): exception lors du téléchargement de l\'image: $e',

      name: 'ChatPage.Media',

      error: e,

      stackTrace: s,

    );

    return null;

  }

}
String _formatMessageTime(String isoTimestamp) {
  try {
    final DateTime utcTime = DateTime.parse(isoTimestamp).toUtc();
    final DateTime localTime = utcTime.add(const Duration(hours: 1));
    return DateFormat('HH:mm').format(localTime);
  } catch (e) {
    return DateFormat('HH:mm').format(DateTime.now());
  }
}
class ChatPage extends StatefulWidget {

  const ChatPage({super.key});

  @override

  _ChatPageState createState() => _ChatPageState();

}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {

  final TextEditingController _messageController = TextEditingController();

  final TextEditingController _editController = TextEditingController();

  final FocusNode _messageFocusNode = FocusNode();

  final _jitsiMeet = JitsiMeet();

  // Enregistrement audio (messages vocaux)
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingFilePath;

  List<Map<String, dynamic>> messages = [];

  List<Map<String, dynamic>> users = [];

  String? roomId;

  String? contactName;

  String? avatarUrl;

  String? status;

  String? currentUser;

  Timer? _pollingTimer;

  final RocketChatWebSocketService _wsService = RocketChatWebSocketService();
  StreamSubscription<Map<String, dynamic>>? _wsMessageSubscription;
  StreamSubscription<String>? _wsDeleteSubscription;
  StreamSubscription<bool>? _wsConnectionSubscription;

  // Cache des avatars SVG parsés (username/url → Map avec color et initial)
  final Map<String, Map<String, dynamic>> _avatarSvgCache = {};
  final Map<String, Future<Map<String, dynamic>>> _avatarFutures = {};

  final List<String> reactions = ['😀', '😄', '😂', '😍', '😢', '😡', '👍', '👎', '👏', '🤔', '😎'];

  final Map<String, String> reactionLabels = {

    '😀': 'grinning',

    '😄': 'smile',

    '😂': 'joy',

    '😍': 'heart_eyes',

    '😢': 'cry',

    '😡': 'rage',

    '👍': '+1',

    '👎': '-1',

    '👏': 'clap',

    '🤔': 'thinking_face',

    '😎': 'sunglasses',

  };

  int? _highlightedIndex;

  int? _reactionIndex;

  int? _moreOptionsIndex;

  String? _editingMessageId;

  int? _editingIndex;

  String? _replyingToId;

  Map<String, dynamic>? _replyingMessage;

  String? _lastMessageId;

  late ScrollController _scrollController;

  bool _showScrollToBottom = false;

  late AnimationController _animationController;

  late Animation<double> _fadeAnimation;

  late Animation<Offset> _slideAnimation;

  late AnimationController _forwardAnimationController;

  late Animation<double> _forwardScaleAnimation;

  // --------------------------------------------------------------------------

  // Helpers pour avatars (même logique que dans MessageriePage)

  // --------------------------------------------------------------------------

  Future<String?> _fetchAndSanitizeSvg(String url, String username) async {

    try {

      final response = await http

          .get(Uri.parse(url))

          .timeout(const Duration(seconds: 15));

      developer.log(

        'ChatPage.fetchAndSanitizeSvg for $username: '

            '${response.statusCode} | ${response.headers['content-type']}',

        name: 'ChatPage',

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

        'ChatPage.Sanitized SVG for $username (length: ${svg.length})',

        name: 'ChatPage',

      );

      return svg;

    } catch (e, s) {

      developer.log(

        'ChatPage.fetchAndSanitizeSvg FAILED for $username: $e',

        error: e,

        stackTrace: s,

        name: 'ChatPage',

      );

      return null;

    }

  }

  // Méthode helper pour construire un avatar avec cache
  Widget _buildAvatarWidget(String? url, String username, {double size = 40}) {
    if (url == null || url.isEmpty) {
      return Icon(Icons.person, size: size, color: Colors.white);
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
        return Icon(Icons.person, size: size, color: Colors.white);
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

      return FutureBuilder<Map<String, dynamic>>(
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

          return Icon(Icons.person, size: size, color: Colors.white);
        },
      );
    }

    // Image réseau - utiliser CachedNetworkImage
    return ClipOval(
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
        errorWidget: (context, url, error) => Icon(
          Icons.person,
          size: size,
          color: Colors.white,
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _loadAndCacheSvg(String avatarUrl, String cacheKey) async {
    try {
      final svgData = await _fetchAndSanitizeSvg(avatarUrl, cacheKey);
      if (svgData == null || svgData.isEmpty) {
        return {'color': Colors.purple, 'initial': '?'};
      }

      final avatarStyle = _extractAvatarStyleFromSvg(svgData);

      // Mettre en cache
      _avatarSvgCache[cacheKey] = avatarStyle;

      return avatarStyle;
    } catch (e) {
      developer.log('Error loading SVG avatar: $e', name: 'ChatPage');
      return {'color': Colors.purple, 'initial': '?'};
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

      return const Color(0xFF6200EE);

    }

    return Color(int.parse(value, radix: 16));

  }

  @override

  void initState() {

    super.initState();

    developer.log('Initializing ChatPage', name: 'ChatPage');

    _scrollController = ScrollController();

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

    _forwardAnimationController = AnimationController(

      vsync: this,

      duration: const Duration(milliseconds: 200),

    );

    _forwardScaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(

      CurvedAnimation(parent: _forwardAnimationController, curve: Curves.easeInOut),

    );

    _scrollController.addListener(() {

      final shouldShow = _scrollController.offset > MediaQuery.of(context).size.height / 2;

      if (shouldShow != _showScrollToBottom) {

        setState(() {

          _showScrollToBottom = shouldShow;

        });

        if (shouldShow) {

          _animationController.forward();

        } else {

          _animationController.reverse();

        }

      }

    });

    WidgetsBinding.instance.addPostFrameCallback((_) {

      if (mounted) {

        final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;

        roomId = args?['room_id']?.toString();

        contactName = args?['name']?.toString() ?? 'Sans nom';

        avatarUrl = args?['avatar_url']?.toString();

        _loadCachedData();

        _checkAuthAndFetchData();

        _startPolling();

        _initializeWebSocket();

      }

    });

  }

  void _initializeWebSocket() {
    if (roomId == null) return;

    // Initialiser le WebSocket
    _wsService.initialize(roomId: roomId).then((_) {
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
        developer.log('WebSocket connection status: $isConnected', name: 'ChatPage');

        if (isConnected && roomId != null) {
          _wsService.subscribeToRoom(roomId!);

          // IMPORTANT : Garder un polling léger même avec WebSocket actif
          // pour détecter les modifications (edit, reactions, delete, reply) qui ne sont pas toujours envoyées via WS
          _pollingTimer?.cancel();
          _startPollingForUpdates(); // Polling moins fréquent pour les mises à jour
          developer.log('WebSocket actif, polling léger activé pour les mises à jour', name: 'ChatPage');
        } else {
          // Reprendre le polling normal si déconnecté
          if (_pollingTimer == null || !_pollingTimer!.isActive) {
            _startPolling();
          }
        }
      });
    }).catchError((error) {
      developer.log('Error initializing WebSocket: $error', name: 'ChatPage');
    });
  }

  void _updateWebSocketRoom(String newRoomId) {
    if (newRoomId == roomId) return;
    roomId = newRoomId;
    _wsService.subscribeToRoom(newRoomId);
  }

  void _handleWebSocketMessage(Map<String, dynamic> wsMessage) {
    if (!mounted || roomId == null) return;

    // Convertir le message WebSocket en format UI
    final message = _convertWebSocketMessageToUI(wsMessage);
    final messageId = message['id'];
    final isUpdate = wsMessage['isUpdate'] == true;

    // NOUVEAU : Ignorer les messages qui sont des images (on les affiche uniquement via polling)
    // IGNORER TOUS LES FICHIERS MÉDIA (images + vidéos) dans le WebSocket
    // → ils seront affichés une seule fois via le polling
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
      developer.log('WebSocket: Message média ignoré (image/vidéo) → affiché via polling uniquement', name: 'ChatPage');
      return; // Plus rien à faire ici
    }
    // FIN DU FILTRE

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
              'threadLastMessage': message['threadLastMessage'] ?? existingMessage['threadLastMessage'],
            };
            messages[existingIndex] = updatedMessage;
          } else {
            messages.insert(0, message);
          }
        });

        // Cache mis à jour...
        SharedPreferences.getInstance().then((prefs) {
          if (roomId != null) {
            final cached = prefs.getString('messages_cache_$roomId');
            if (cached != null) {
              final data = jsonDecode(cached);
              final cacheIndex = (data['messages'] as List).indexWhere((m) => m['id'] == messageId);
              if (cacheIndex != -1) {
                data['messages'][cacheIndex] = messages[existingIndex != -1 ? existingIndex : 0];
                prefs.setString('messages_cache_$roomId', jsonEncode(data));
              }
            }
          }
        });
      }
      return;
    }

    // Nouveau message texte, vidéo, audio, fichier → affiché en temps réel
    if (mounted) {
      setState(() {
        messages.insert(0, message);
        _lastMessageId = messageId;
      });

      // Cache + scroll comme avant...
      SharedPreferences.getInstance().then((prefs) {
        if (roomId != null) {
          final cached = prefs.getString('messages_cache_$roomId');
          final data = cached != null ? jsonDecode(cached) : {'messages': <Map<String, dynamic>>[]};
          data['messages'].insert(0, message);
          prefs.setString('messages_cache_$roomId', jsonEncode(data));
        }
      });

      final isAtBottom = _scrollController.offset <= 100;
      if (isAtBottom || message['username'] == currentUser) {
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

    developer.log('WebSocket delete message received: $messageId', name: 'ChatPage');

    setState(() {
      final removedCount = messages.length;
      messages.removeWhere((m) => m['id'] == messageId);
      final newCount = messages.length;

      if (removedCount != newCount) {
        developer.log('Message deleted from UI: $messageId (removed ${removedCount - newCount} message(s))', name: 'ChatPage');
      } else {
        developer.log('Warning: Message $messageId not found in messages list', name: 'ChatPage');
      }

      // Si on répondait à ce message
      if (_replyingToId == messageId) {
        _replyingToId = null;
        _replyingMessage = null;
      }
    });

    // Mettre à jour le cache
    SharedPreferences.getInstance().then((prefs) {
      if (roomId != null) {
        final cached = prefs.getString('messages_cache_$roomId');
        if (cached != null) {
          final data = jsonDecode(cached);
          final beforeCount = (data['messages'] as List).length;
          data['messages'].removeWhere((m) => m['id'] == messageId);
          final afterCount = (data['messages'] as List).length;
          prefs.setString('messages_cache_$roomId', jsonEncode(data));
          developer.log('Message deleted from cache: $messageId (removed ${beforeCount - afterCount} message(s))', name: 'ChatPage');
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
        if (roomId != null) {
          final cached = prefs.getString('messages_cache_$roomId');
          if (cached != null) {
            final data = jsonDecode(cached);
            final cacheMessages = data['messages'] as List;
            for (var i = 0; i < cacheMessages.length; i++) {
              if (cacheMessages[i]['isUnread'] == true) {
                cacheMessages[i]['isUnread'] = false;
              }
            }
            prefs.setString('messages_cache_$roomId', jsonEncode(data));
          }
        }
      });
    }
  }

  Map<String, dynamic> _convertWebSocketMessageToUI(Map<String, dynamic> wsMsg) {
    // Le message WebSocket est déjà dans le bon format grâce au service
    // On s'assure juste qu'il a tous les champs nécessaires

    // Gérer replyTo : peut être un objet ou un ID
    dynamic replyTo = wsMsg['replyTo'];
    if (replyTo != null && replyTo is! Map) {
      // Si c'est juste un ID, chercher le message dans la liste pour obtenir les données
      final replyToId = replyTo.toString();
      final originalMsg = messages.firstWhere(
            (m) => m['id'] == replyToId,
        orElse: () => {
          'id': replyToId,
          'name': 'Message supprimé',
          'username': 'Inconnu',
          'text': 'Ce message a été supprimé ou n\'est pas disponible.'
        },
      );
      replyTo = {
        'messageId': replyToId,
        'id': replyToId,
        'name': originalMsg['name'] ?? 'Message supprimé',
        'username': originalMsg['username'] ?? 'Inconnu',
        'text': originalMsg['text'] ?? 'Ce message a été supprimé ou n\'est pas disponible.'
      };
    }

    // Déterminer si le message est non lu (pas envoyé par l'utilisateur actuel)
    final isUnread = wsMsg['username'] != currentUser && wsMsg['isSent'] != true;
    
    return {
      'id': wsMsg['id'],
      'text': wsMsg['text'] ?? '',
      'name': wsMsg['name'] ?? 'Unknown',
      'username': wsMsg['username'] ?? '',
      'avatar': wsMsg['avatar'] ?? '',
      'timestamp': wsMsg['timestamp'] ?? DateTime.now().toIso8601String(),
      'editedAt': wsMsg['editedAt'],
      'isEdited': wsMsg['isEdited'] ?? (wsMsg['editedAt'] != null),
      'type': wsMsg['type'] ?? 'text',
      'file': wsMsg['file'],
      'attachments': wsMsg['attachments'] ?? [],
      'replyTo': replyTo,
      'reactions': wsMsg['reactions'] ?? {},
      'isSent': wsMsg['isSent'] ?? false,
      'isUpdate': wsMsg['isUpdate'] ?? false, // Préserver le flag de mise à jour
      'isUnread': isUnread, // Flag pour les messages non lus
      'threadMessages': wsMsg['threadMessages'] ?? [],
      'threadCount': wsMsg['threadCount'] ?? 0,
      'threadLastMessage': wsMsg['threadLastMessage'],
    };
  }

  void _startPolling() {

    _pollingTimer?.cancel();

    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {

      if (mounted) {

        fetchMessages();

      } else {

        timer.cancel();

      }

    });

    developer.log('Started polling for new messages', name: 'ChatPage');

  }

  // Polling léger pour détecter les modifications même avec WebSocket actif
  // Les modifications (edit, reactions, delete, reply) ne sont pas toujours envoyées via WebSocket
  void _startPollingForUpdates() {
    _pollingTimer?.cancel();

    // Polling toutes les 1 seconde pour détecter les modifications en quasi temps réel
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && roomId != null) {
        // Utiliser fetchMessages qui détecte automatiquement les modifications
        fetchMessages();
      } else {
        timer.cancel();
      }
    });

    developer.log('Started fast polling for message updates (WebSocket active)', name: 'ChatPage');
  }

  Future<void> _loadCachedData() async {

    final prefs = await SharedPreferences.getInstance();

    final cachedUsers = prefs.getString('users_cache');

    final cachedMessages = prefs.getString('messages_cache_$roomId');

    final cachedCurrentUser = prefs.getString('current_user');

    if (mounted) {

      setState(() {

        if (cachedCurrentUser != null) {

          currentUser = cachedCurrentUser;

        }

        if (cachedUsers != null) {

          final List<dynamic> userData = jsonDecode(cachedUsers);

          users = userData.cast<Map<String, dynamic>>();

          final currentUserData = users.firstWhere(

                (user) => user['room_id'] == roomId,

            orElse: () => {},

          );

          status = currentUserData['status']?.toString();

          contactName = currentUserData['name']?.toString() ?? contactName;

          avatarUrl = currentUserData['avatar']?.toString() ?? avatarUrl;

        }

        if (cachedMessages != null) {

          final data = jsonDecode(cachedMessages);

          if (data['messages'] != null) {

            // D'abord créer la liste des messages
            final tempMessages = List<Map<String, dynamic>>.from(data['messages']).map((msg) {
              msg['reactions'] = msg['reactions'] is Map ? msg['reactions'] : {};
              return msg;
            }).toList();

            // Ensuite, enrichir les replyTo avec les données des messages originaux
            messages = tempMessages.map((msg) {
              // Déterminer si le message est non lu (pas envoyé par l'utilisateur actuel)
              final msgUsername = msg['username']?.toString() ?? '';
              final isUnread = msgUsername != currentUser && msg['isSent'] != true;
              msg['isUnread'] = isUnread;
              
              // Gérer replyTo : convertir tmid en objet avec les données du message original
              if (msg['tmid'] != null) {
                final tmid = msg['tmid'].toString();
                final originalMsg = tempMessages.firstWhere(
                      (m) => m['id'] == tmid,
                  orElse: () => {
                    'id': tmid,
                    'name': 'Message supprimé',
                    'username': 'Inconnu',
                    'text': 'Ce message a été supprimé ou n\'est pas disponible.'
                  },
                );
                msg['replyTo'] = {
                  'messageId': tmid,
                  'id': tmid,
                  'name': originalMsg['name'] ?? 'Message supprimé',
                  'username': originalMsg['username'] ?? 'Inconnu',
                  'text': originalMsg['text'] ?? 'Ce message a été supprimé ou n\'est pas disponible.'
                };
              } else if (msg['replyTo'] != null && msg['replyTo'] is! Map) {
                final replyToId = msg['replyTo'].toString();
                final originalMsg = tempMessages.firstWhere(
                      (m) => m['id'] == replyToId,
                  orElse: () => {
                    'id': replyToId,
                    'name': 'Message supprimé',
                    'username': 'Inconnu',
                    'text': 'Ce message a été supprimé ou n\'est pas disponible.'
                  },
                );
                msg['replyTo'] = {
                  'messageId': replyToId,
                  'id': replyToId,
                  'name': originalMsg['name'] ?? 'Message supprimé',
                  'username': originalMsg['username'] ?? 'Inconnu',
                  'text': originalMsg['text'] ?? 'Ce message a été supprimé ou n\'est pas disponible.'
                };
              }
              return msg;
            }).toList();

            if (messages.isNotEmpty) {

              _lastMessageId = messages.last['id'];

            }

            if (_replyingToId != null) {

              _replyingMessage = messages.firstWhere(

                    (msg) => msg['id'] == _replyingToId,

                orElse: () => {'name': 'Message supprimé', 'username': 'Inconnu', 'text': 'Ce message a été supprimé ou n\'est pas disponible.'},

              );

            }

          }

        }

      });

    }

  }

  Future<void> _checkAuthAndFetchData() async {

    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.isLoggedIn) {

      if (mounted) {

        SnackBarHelper.showWarning(context, 'Veuillez vous connecter pour continuer.');

        Navigator.pushReplacementNamed(context, '/login');

      }

      return;

    }

    try {

      if (currentUser == null) {

        await fetchCurrentUser();

      }

      await fetchUsers();

      await fetchMessages();
      
      // Marquer les messages comme lus quand la conversation est ouverte
      _markMessagesAsRead();

    } catch (e, stackTrace) {

      developer.log(

        'Error during data fetch: $e',

        name: 'ChatPage',

        error: e,

        stackTrace: stackTrace,

      );

      if (mounted) {

        SnackBarHelper.showError(context, 'Erreur : $e');

      }

    }

  }

  Future<void> fetchCurrentUser() async {

    if (!mounted) return;

    const endpoint = 'https://www.unistudious.com/api/chat-message';

    try {
      // Utiliser le cache local si disponible pour éviter un timeout bloquant
      final prefs = await SharedPreferences.getInstance();
      final cachedUser = prefs.getString('current_user');
      if (cachedUser != null && cachedUser.isNotEmpty) {
        setState(() {
          currentUser = cachedUser;
        });
        // On continue tout de même en arrière-plan pour rafraîchir
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      final response = await authProvider.authenticatedRequest('GET', endpoint).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (response.statusCode == 200) {

        final data = jsonDecode(response.body);

        if (data['currentUser'] != null) {

          final prefs = await SharedPreferences.getInstance();

          await prefs.setString('current_user', data['currentUser']);

          if (mounted) {

            setState(() {

              currentUser = data['currentUser'];

            });

          }

        } else {

          throw Exception('Échec de la récupération de l\'utilisateur actuel.');

        }

      } else {

        throw Exception('Erreur ${response.statusCode} lors de la récupération de l\'utilisateur actuel.');

      }

    } catch (e) {
      // Si on avait déjà un utilisateur en cache, on ne bloque pas l'app
      final prefs = await SharedPreferences.getInstance();
      final cachedUser = prefs.getString('current_user');
      if (cachedUser != null && cachedUser.isNotEmpty) {
        developer.log('fetchCurrentUser fallback to cached user after error: $e', name: 'ChatPage');
        return;
      }
      rethrow;

    }

  }

  Future<void> fetchUsers() async {

    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    const endpoint = 'https://www.unistudious.com/api/chat/list-users';

    try {

      final response = await authProvider.authenticatedRequest('GET', endpoint).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (response.statusCode == 200) {

        final List<dynamic> data = jsonDecode(response.body);

        final prefs = await SharedPreferences.getInstance();

        await prefs.setString('users_cache', jsonEncode(data));

        if (mounted) {

          setState(() {

            users = data.cast<Map<String, dynamic>>();

            final currentUserData = users.firstWhere(

                  (user) => user['room_id'] == roomId,

              orElse: () => {},

            );

            status = currentUserData['status']?.toString();

            contactName = currentUserData['name']?.toString() ?? contactName;

            avatarUrl = currentUserData['avatar']?.toString() ?? avatarUrl;

          });

        }

      } else {

        throw Exception('Erreur ${response.statusCode} lors du chargement des utilisateurs.');

      }

    } catch (e) {

      rethrow;

    }

  }

  Future<void> fetchMessages() async {

    if (!mounted || roomId == null) return;

    const endpoint = 'https://www.unistudious.com/api/chat/get-messages';

    try {

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))..fields['roomId'] = roomId!;

      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token') ?? '';

      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));

      if (!mounted) return;

      if (response.statusCode == 200) {

        final data = jsonDecode(response.body);

        if (data['success'] == true) {

          final List<Map<String, dynamic>> newMessages = List<Map<String, dynamic>>.from(data['messages']).map((msg) {

            msg['reactions'] = msg['reactions'] is Map ? msg['reactions'] : {};

            msg['isEdited'] = msg['editedAt'] != null;

            // Gérer replyTo : convertir tmid en objet avec les données du message original
            if (msg['tmid'] != null) {
              final tmid = msg['tmid'].toString();
              // Chercher le message original dans la liste actuelle pour obtenir ses données
              final originalMsg = messages.firstWhere(
                    (m) => m['id'] == tmid,
                orElse: () => {
                  'id': tmid,
                  'name': 'Message supprimé',
                  'username': 'Inconnu',
                  'text': 'Ce message a été supprimé ou n\'est pas disponible.'
                },
              );
              msg['replyTo'] = {
                'messageId': tmid,
                'id': tmid,
                'name': originalMsg['name'] ?? 'Message supprimé',
                'username': originalMsg['username'] ?? 'Inconnu',
                'text': originalMsg['text'] ?? 'Ce message a été supprimé ou n\'est pas disponible.'
              };
            } else if (msg['replyTo'] != null && msg['replyTo'] is! Map) {
              // Si replyTo est juste un ID, le convertir en objet
              final replyToId = msg['replyTo'].toString();
              final originalMsg = messages.firstWhere(
                    (m) => m['id'] == replyToId,
                orElse: () => {
                  'id': replyToId,
                  'name': 'Message supprimé',
                  'username': 'Inconnu',
                  'text': 'Ce message a été supprimé ou n\'est pas disponible.'
                },
              );
              msg['replyTo'] = {
                'messageId': replyToId,
                'id': replyToId,
                'name': originalMsg['name'] ?? 'Message supprimé',
                'username': originalMsg['username'] ?? 'Inconnu',
                'text': originalMsg['text'] ?? 'Ce message a été supprimé ou n\'est pas disponible.'
              };
            }

            return msg;

          }).toList();

          // IMPORTANT : Toujours mettre à jour pour détecter les modifications (edit, reactions, delete, reply)
          // Ne pas seulement vérifier si le dernier message a changé
          bool hasChanges = false;
          if (newMessages.isNotEmpty) {
            // Vérifier s'il y a de nouveaux messages OU des modifications
            final newLastMessageId = newMessages.last['id'];
            final hasNewMessages = newLastMessageId != _lastMessageId || messages.isEmpty;

            // Vérifier s'il y a des modifications dans les messages existants
            final existingMessageMap = <String, Map<String, dynamic>>{};
            for (var msg in messages) {
              existingMessageMap[msg['id']] = msg;
            }

            for (var newMsg in newMessages) {
              final msgId = newMsg['id'];
              final existingMsg = existingMessageMap[msgId];

              if (existingMsg != null) {
                // Vérifier si le message a été modifié (edit, reactions, etc.)
                final textChanged = existingMsg['text'] != newMsg['text'];
                final editedAtChanged = existingMsg['editedAt'] != newMsg['editedAt'];
                final reactionsChanged = jsonEncode(existingMsg['reactions']) != jsonEncode(newMsg['reactions']);
                final replyToChanged = existingMsg['replyTo'] != newMsg['replyTo'];

                if (textChanged || editedAtChanged || reactionsChanged || replyToChanged) {
                  hasChanges = true;
                  developer.log('Message modified detected: $msgId (text=$textChanged, edited=$editedAtChanged, reactions=$reactionsChanged, reply=$replyToChanged)', name: 'ChatPage');
                  break;
                }
              } else {
                // Nouveau message
                hasChanges = true;
                break;
              }
            }

            hasChanges = hasChanges || hasNewMessages;
          }

          if (hasChanges || newMessages.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('messages_cache_$roomId', jsonEncode({'messages': newMessages}));

            if (mounted) {
              setState(() {
                String? previousReplyingToId = _replyingToId;
                Map<String, dynamic>? previousReplyingMessage = _replyingMessage;

                final messageMap = <String, Map<String, dynamic>>{};

                // Copie de l'état actuel
                for (var msg in messages) {
                  messageMap[msg['id']] = Map<String, dynamic>.from(msg);
                }

                // On parcourt les nouveaux messages du polling
                for (var newMsg in newMessages) {
                  final id = newMsg['id'];
                  final existing = messageMap[id];

                  // DÉTECTION QUE C'EST UNE IMAGE
                  final isImage = (newMsg['attachments'] as List?)?.isNotEmpty == true &&
                      (newMsg['attachments'][0] as Map?)?.containsKey('image_url') == true;

                  // Si c'est une image ET qu'on a déjà une version affichable → ON IGNORE COMPLÈTEMENT
                  if (isImage) {
                    final existingHasPreview = existing != null &&
                        (existing['attachments'] as List?)?.isNotEmpty == true &&
                        (existing['attachments'][0] as Map).containsKey('image_preview');

                    final existingHasUrl = existing != null &&
                        (existing['attachments'] as List?)?.isNotEmpty == true &&
                        (existing['attachments'][0] as Map).containsKey('image_url');

                    if (existingHasPreview || existingHasUrl) {
                      developer.log('Image déjà affichée (preview ou URL) → ignorée par polling (ID: $id)', name: 'ChatPage');
                      continue; // ON NE TOUCHE PLUS À CE MESSAGE
                    }
                  }

                  // Sinon, on met à jour normalement
                  messageMap[id] = Map<String, dynamic>.from(newMsg);
                }

                // Suppression des messages supprimés
                final newIds = newMessages.map((m) => m['id']).toSet();
                messageMap.removeWhere((id, _) => !newIds.contains(id));

                messages = messageMap.values.toList()
                  ..sort((a, b) => DateTime.parse(a['timestamp'] ?? '1970-01-01')
                      .compareTo(DateTime.parse(b['timestamp'] ?? '1970-01-01')));

                if (messages.isNotEmpty) {
                  _lastMessageId = messages.last['id'];
                }

                // Restauration de la réponse en cours
                if (previousReplyingToId != null) {
                  _replyingToId = previousReplyingToId;
                  _replyingMessage = messages.firstWhere(
                        (msg) => msg['id'] == previousReplyingToId,
                    orElse: () => {
                      'name': 'Message supprimé',
                      'username': 'Inconnu',
                      'text': 'Ce message a été supprimé ou n\'est pas disponible.'
                    },
                  );
                } else {
                  _replyingToId = null;
                  _replyingMessage = null;
                }
              });
            }
          }

        } else {

          throw Exception('Échec de la récupération des messages.');

        }

      } else {

        throw Exception('Erreur ${response.statusCode} lors du chargement des messages.');

      }

    } catch (e) {

      rethrow;

    }

  }

  Future<void> _deleteMessage(String messageId, int index) async {

    if (!mounted || roomId == null) return;

    const endpoint = 'https://www.unistudious.com/api/chat/delete-message';

    try {

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))

        ..fields['roomId'] = roomId!

        ..fields['messageId'] = messageId;

      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token') ?? '';

      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));

      if (!mounted) return;

      if (response.statusCode == 200) {

        final data = jsonDecode(response.body);

        if (data['success'] == true && data['result']['success'] == true) {

          if (mounted) {

            setState(() {

              messages.removeAt(index);

              if (_replyingToId == messageId) {

                _replyingToId = null;

                _replyingMessage = null;

              }

            });

            final cachedMessages = prefs.getString('messages_cache_$roomId');

            final cacheData = cachedMessages != null ? jsonDecode(cachedMessages) : {'messages': []};

            cacheData['messages'].removeWhere((m) => m['id'] == messageId);

            await prefs.setString('messages_cache_$roomId', jsonEncode(cacheData));

            SnackBarHelper.showSuccess(context, 'Message supprimé avec succès');

          }

        } else {

          throw Exception('Échec de la suppression du message.');

        }

      } else {

        throw Exception('Erreur ${response.statusCode} lors de la suppression du message.');

      }

    } catch (e, stackTrace) {

      developer.log('Error deleting message: $e', name: 'ChatPage', error: e, stackTrace: stackTrace);

      if (mounted) {

        SnackBarHelper.showError(context, 'Erreur lors de la suppression : $e');

      }

    }

  }

  Future<void> _confirmDeleteMessage(int index) async {

    final message = messages[index];

    final isMe = message['username'] == currentUser;

    if (!isMe) {

      SnackBarHelper.showWarning(context, 'Vous ne pouvez supprimer que vos propres messages');

      return;

    }

    final confirmed = await showDialog<bool>(

      context: context,

      builder: (BuildContext context) {

        return AlertDialog(

          title: Text('Supprimer le message', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),

          content: Text('Êtes-vous sûr de vouloir supprimer ce message ? Cette action est irréversible.', style: GoogleFonts.poppins()),

          actions: [

            TextButton(

              onPressed: () => Navigator.of(context).pop(false),

              child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.grey[600])),

            ),

            TextButton(

              onPressed: () => Navigator.of(context).pop(true),

              child: Text('Supprimer', style: GoogleFonts.poppins(color: Colors.red)),

            ),

          ],

          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

        );

      },

    );

    if (confirmed == true) {

      await _deleteMessage(message['id'], index);

    }

  }

  Future<void> _editMessage(String messageId, String newText, int index) async {

    if (!mounted || roomId == null) return;

    const endpoint = 'https://www.unistudious.com/api/chat/edit-message';

    try {

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))

        ..fields['roomId'] = roomId!

        ..fields['messageId'] = messageId

        ..fields['text'] = newText;

      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token') ?? '';

      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));

      if (!mounted) return;

      if (response.statusCode == 200) {

        final data = jsonDecode(response.body);

        if (data['success'] == true && data['result']['success'] == true) {

          final editedMessage = data['result']['message'];

          if (mounted) {

            setState(() {

              messages[index] = {

                'id': editedMessage['_id'],

                'type': 'text',

                'username': editedMessage['u']['username'],

                'name': editedMessage['u']['name'],

                'avatar': avatarUrl,

                'timestamp': editedMessage['ts'],

                'reactions': messages[index]['reactions'] ?? {},

                'isSent': true,

                'text': editedMessage['msg'],

                'editedAt': editedMessage['_updatedAt'],

                'isEdited': true,

                'replyTo': messages[index]['replyTo'],

                'threadMessages': messages[index]['threadMessages'] ?? [],

                'threadCount': messages[index]['threadCount'] ?? 0,

                'threadLastMessage': messages[index]['threadLastMessage'],

              };

              _cancelEditing();

            });

            final cachedMessages = prefs.getString('messages_cache_$roomId');

            final cacheData = cachedMessages != null ? jsonDecode(cachedMessages) : {'messages': []};

            final cacheMessageIndex = cacheData['messages'].indexWhere((m) => m['id'] == messageId);

            if (cacheMessageIndex != -1) {

              cacheData['messages'][cacheMessageIndex] = messages[index];

              await prefs.setString('messages_cache_$roomId', jsonEncode(cacheData));

            }

            SnackBarHelper.showSuccess(context, 'Message modifié avec succès');

          }

        } else {

          throw Exception('Échec de la modification du message.');

        }

      } else {

        throw Exception('Erreur ${response.statusCode} lors de la modification du message.');

      }

    } catch (e, stackTrace) {

      developer.log('Error editing message: $e', name: 'ChatPage', error: e, stackTrace: stackTrace);

      if (mounted) {

        SnackBarHelper.showError(context, 'Erreur lors de la modification : $e');

      }

    }

  }

  // --------------------------------------------------------------------------

  // Envoi de pièce jointe : /api/chat/send-attachment (POST, form-data)

  // --------------------------------------------------------------------------

  Future<void> _pickAndSendAttachment() async {

    if (!mounted || roomId == null) return;

    // 1) Demander à l'utilisateur s'il veut envoyer une photo (galerie) ou un fichier (documents/audio/vidéo...)

    final choice = await showModalBottomSheet<String>(

      context: context,

      shape: const RoundedRectangleBorder(

        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),

      ),

      builder: (ctx) {

        final theme = Theme.of(ctx);

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

    if (!mounted || roomId == null) return;

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

        ..fields['roomId'] = roomId!;

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

      final streamed =

      await request.send().timeout(const Duration(seconds: 60));

      final response = await http.Response.fromStream(streamed);

      if (!mounted) return;

      if (response.statusCode == 200) {

        final data = jsonDecode(response.body);

        if (data['success'] == true) {

          final Map<String, dynamic> message =

          Map<String, dynamic>.from(data['message'] as Map);

          // 4) Conversion en modèle local de message

          final newMessage = <String, dynamic>{

            'id': message['_id'],

            'type': 'attachment',

            'username': (message['u'] as Map)['username'],

            'name': (message['u'] as Map)['name'],

            'avatar': avatarUrl,

            'timestamp': message['ts'],

            'reactions': <String, dynamic>{},

            'isSent': true,

            'text': message['msg'] ?? '',

            'file': message['file'],

            'files': message['files'] ?? [],

            'attachments': message['attachments'] ?? [],

            'editedAt': null,

            'isEdited': false,

            'replyTo': message['tmid'],

            'threadMessages': <dynamic>[],

            'threadCount': 0,

            'threadLastMessage': null,

          };

          // 5) Mise à jour de l'état + cache local (comme _sendMessage)
          setState(() {
            // Vérifier si le message existe déjà (ajouté par WebSocket)
            final existingIndex = messages.indexWhere((msg) => msg['id'] == newMessage['id']);
            if (existingIndex == -1) {
              messages.add(newMessage);
            } else {
              messages[existingIndex] = newMessage;
            }

            _lastMessageId = newMessage['id'] as String?;

          });

          // Fermer la popup de chargement et afficher un message de succès
          if (choice == 'photo' && scaffoldMessenger != null && mounted) {
            scaffoldMessenger.hideCurrentSnackBar();
            SnackBarHelper.showSuccess(context, 'Photo envoyée avec succès', duration: const Duration(seconds: 2));
          }

          final cached = prefs.getString('messages_cache_$roomId');

          final cacheData = cached != null

              ? jsonDecode(cached) as Map<String, dynamic>

              : {'messages': []};

          (cacheData['messages'] as List).add(newMessage);

          await prefs.setString(

              'messages_cache_$roomId', jsonEncode(cacheData));

          _scrollController.animateTo(

            0,

            duration: const Duration(milliseconds: 300),

            curve: Curves.easeInOut,

          );

        } else {

          throw Exception('Échec de l\'envoi de la pièce jointe.');

        }

      } else {

        throw Exception(

          'Erreur ${response.statusCode} lors de l\'envoi de la pièce jointe.',

        );

      }

    } catch (e, s) {
      // Fermer la popup de chargement en cas d'erreur
      if (choice == 'photo' && scaffoldMessenger != null && mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
      }

      developer.log(

        'Error sending attachment: $e',

        name: 'ChatPage',

        error: e,

        stackTrace: s,

      );

      if (mounted) {

        SnackBarHelper.showError(context, 'Erreur lors de l\'envoi de la pièce jointe : $e');

      }

    }

  }

  // ================== GESTION DES MESSAGES VOCAUX ==================
  Future<void> _handleMicPressed() async {
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
      // IMPORTANT : iOS/macOS ne supporte pas l'enregistrement AAC dans un conteneur .mp3 via le plugin `record`.
      // On reste donc en .m4a (AAC dans un conteneur compatible) pour éviter l'erreur OSStatus.
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
          name: 'ChatPage.Audio', error: e, stackTrace: s);
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
      // Même remarque : on envoie le fichier tel qu'il est enregistré, en .m4a.
      // Si vous avez besoin de MP3, il faudra convertir côté serveur ou avec un autre outil.
      final fileName = 'vocal_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _sendAudioAttachment(bytes, fileName);
    } catch (e, s) {
      developer.log('Erreur lors de l\'arrêt de l\'enregistrement: $e',
          name: 'ChatPage.Audio', error: e, stackTrace: s);
      if (!mounted) return;
      SnackBarHelper.showError(context, 'Erreur lors de l\'envoi du vocal: $e');
    } finally {
      _recordingFilePath = null;
    }
  }

  Future<void> _sendAudioAttachment(Uint8List bytes, String fileName) async {
    if (!mounted || roomId == null) return;
    const endpoint = 'https://www.unistudious.com/api/chat/send-attachment';

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      if (token.isEmpty) {
        throw Exception('Aucun token d\'authentification trouvé.');
      }

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))
        ..fields['roomId'] = roomId!;

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
          final Map<String, dynamic> message =
              Map<String, dynamic>.from(data['message'] as Map);

          // Conversion en modèle local de message
          final newMessage = <String, dynamic>{
            'id': message['_id'],
            'type': 'attachment',
            'username': (message['u'] as Map)['username'],
            'name': (message['u'] as Map)['name'],
            'avatar': avatarUrl,
            'timestamp': message['ts'],
            'reactions': <String, dynamic>{},
            'isSent': true,
            'text': message['msg'] ?? '',
            'file': message['file'],
            'files': message['files'] ?? [],
            'attachments': message['attachments'] ?? [],
            'editedAt': null,
            'isEdited': false,
            'replyTo': message['tmid'],
            'threadMessages': <dynamic>[],
            'threadCount': 0,
            'threadLastMessage': null,
          };

          // Mise à jour de l'état + cache local
          if (mounted) {
            setState(() {
              messages.add(newMessage);
              _lastMessageId = newMessage['id'] as String?;
            });
          }

          final cached = prefs.getString('messages_cache_$roomId');
          final cacheData = cached != null
              ? jsonDecode(cached) as Map<String, dynamic>
              : {'messages': []};

          (cacheData['messages'] as List).add(newMessage);

          await prefs.setString(
              'messages_cache_$roomId', jsonEncode(cacheData));

          if (mounted) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        } else {
          throw Exception(
              data['message']?.toString() ?? 'Échec de l\'envoi du message vocal.');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        if (mounted) {
          SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
          Navigator.pop(context);
        }
      } else {
        throw Exception('Erreur HTTP ${response.statusCode}');
      }
    } catch (e, s) {
      developer.log('Erreur _sendAudioAttachment: $e',
          name: 'ChatPage.Audio', error: e, stackTrace: s);
      if (!mounted) return;
      SnackBarHelper.showError(context, 'Erreur lors de l\'envoi du vocal: $e');
    }
  }
  // ================================================================

  // Ouvrir une URL de pièce jointe (image, fichier...) dans le navigateur / app externe

  Future<void> _openAttachmentUrl(String rawUrl) async {

    var url = rawUrl.trim();

    if (url.isEmpty) return;

    if (!url.startsWith('http')) {

      // L'API renvoie souvent des chemins relatifs comme /file-upload/...

      url = 'https://www.unistudious.com$url';

    }

    final uri = Uri.parse(url);

    try {

      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!opened && mounted) {

        SnackBarHelper.showError(context, 'Impossible d\'ouvrir le fichier.');

      }

    } catch (e) {

      if (mounted) {

        SnackBarHelper.showError(context, 'Erreur lors de l\'ouverture du fichier : $e');

      }

    }

  }

  // Helper pour obtenir l'URL complète d'un fichier

  String _getFullUrl(String? url) {

    developer.log('_getFullUrl: url originale = "$url"', name: 'ChatPage.Media');

    if (url == null || url.isEmpty) {

      developer.log('_getFullUrl: URL vide ou null', name: 'ChatPage.Media');

      return '';

    }

    if (url.startsWith('http')) {

      developer.log('_getFullUrl: URL complète déjà, retour = "$url"', name: 'ChatPage.Media');

      return url;

    }

    // Utiliser message.unistudious.com pour les fichiers, pas www.unistudious.com

    final fullUrl = 'https://message.unistudious.com$url';

    developer.log('_getFullUrl: URL transformée = "$fullUrl"', name: 'ChatPage.Media');

    return fullUrl;

  }

  // Helper pour enrichir une URL avec les tokens Rocket.Chat si nécessaire

  String _enrichUrlWithRcTokens(String url, Map<String, dynamic>? message) {

    final uri = Uri.parse(url);



    // Si l'URL a déjà les tokens, la retourner telle quelle

    if (uri.queryParameters.containsKey('rc_token') && uri.queryParameters.containsKey('rc_uid')) {

      developer.log('_enrichUrlWithRcTokens: URL a déjà les tokens Rocket.Chat', name: 'ChatPage.Media');

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

          developer.log('_enrichUrlWithRcTokens: Erreur parsing file URL: $e', name: 'ChatPage.Media');

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

            developer.log('_enrichUrlWithRcTokens: Erreur parsing files[0] URL: $e', name: 'ChatPage.Media');

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

      developer.log('_enrichUrlWithRcTokens: URL enrichie avec les tokens Rocket.Chat (token: ${rcToken.substring(0, rcToken.length > 10 ? 10 : rcToken.length)}..., uid: $rcUid)', name: 'ChatPage.Media');

      return enrichedUri.toString();

    }



    developer.log('_enrichUrlWithRcTokens: Pas de tokens Rocket.Chat trouvés, URL retournée sans modification', name: 'ChatPage.Media');

    return url;

  }

  // Helper pour obtenir l'URL du média depuis un attachment

  String? _getMediaUrlFromAttachment(Map<String, dynamic>? attachment) {

    developer.log('_getMediaUrlFromAttachment: attachment = $attachment', name: 'ChatPage.Media');

    if (attachment == null) {

      developer.log('_getMediaUrlFromAttachment: attachment est null', name: 'ChatPage.Media');

      return null;

    }



    // Chercher l'URL dans différents champs possibles

    // Pour les images : préférer title_link (image complète) à image_url (thumbnail)

    final imageUrl = attachment['image_url']?.toString();

    final titleLink = attachment['title_link']?.toString();

    final audioUrl = attachment['audio_url']?.toString();

    final videoUrl = attachment['video_url']?.toString();



    developer.log('_getMediaUrlFromAttachment: image_url = "$imageUrl"', name: 'ChatPage.Media');

    developer.log('_getMediaUrlFromAttachment: title_link = "$titleLink"', name: 'ChatPage.Media');

    developer.log('_getMediaUrlFromAttachment: audio_url = "$audioUrl"', name: 'ChatPage.Media');

    developer.log('_getMediaUrlFromAttachment: video_url = "$videoUrl"', name: 'ChatPage.Media');



    // Pour les images : préférer title_link (image complète) puis image_url (thumbnail)

    // Pour vidéo/audio : utiliser les champs spécifiques

    final result = titleLink ?? imageUrl ?? videoUrl ?? audioUrl;

    developer.log('_getMediaUrlFromAttachment: résultat = "$result"', name: 'ChatPage.Media');



    return result;

  }

  // Helper pour obtenir le preview base64 depuis un attachment

  String? _getImagePreviewBase64(Map<String, dynamic>? attachment) {

    if (attachment == null) return null;

    final preview = attachment['image_preview']?.toString();

    if (preview != null && preview.isNotEmpty && preview.startsWith('/9j/')) {

      developer.log('_getImagePreviewBase64: Preview base64 trouvé (${preview.length} chars)', name: 'ChatPage.Media');

      return preview;

    }

    return null;

  }

  // Helper pour obtenir l'URL depuis le champ file

  String? _getMediaUrlFromFile(dynamic file) {

    developer.log('_getMediaUrlFromFile: file = $file', name: 'ChatPage.Media');

    if (file == null) {

      developer.log('_getMediaUrlFromFile: file est null', name: 'ChatPage.Media');

      return null;

    }

    if (file is Map<String, dynamic>) {

      final url = file['url']?.toString();

      final downloadUrl = file['download_url']?.toString();

      developer.log('_getMediaUrlFromFile: url = "$url", download_url = "$downloadUrl"', name: 'ChatPage.Media');

      final result = url ?? downloadUrl;

      developer.log('_getMediaUrlFromFile: résultat = "$result"', name: 'ChatPage.Media');

      return result;

    }

    final result = file.toString();

    developer.log('_getMediaUrlFromFile: résultat (toString) = "$result"', name: 'ChatPage.Media');

    return result;

  }

  // Helper pour détecter le type de média

  String? _getMediaType(String? url, String? fileName) {

    developer.log('_getMediaType: url = "$url", fileName = "$fileName"', name: 'ChatPage.Media');

    if (url == null || url.isEmpty) {

      developer.log('_getMediaType: URL vide ou null, retour null', name: 'ChatPage.Media');

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

        developer.log('_getMediaType: détecté comme IMAGE (extension: $ext)', name: 'ChatPage.Media');

        return 'image';

      }

    }

    for (final ext in videoExtensions) {

      if (lowerUrl.contains(ext) || lowerFileName.endsWith(ext)) {

        developer.log('_getMediaType: détecté comme VIDEO (extension: $ext)', name: 'ChatPage.Media');

        return 'video';

      }

    }

    for (final ext in audioExtensions) {

      if (lowerUrl.contains(ext) || lowerFileName.endsWith(ext)) {

        developer.log('_getMediaType: détecté comme AUDIO (extension: $ext)', name: 'ChatPage.Media');

        return 'audio';

      }

    }

    for (final ext in pdfExtensions) {

      if (lowerUrl.contains(ext) || lowerFileName.endsWith(ext)) {

        developer.log('_getMediaType: détecté comme PDF (extension: $ext)', name: 'ChatPage.Media');

        return 'pdf';

      }

    }



    // Vérifier par type MIME dans l'URL

    if (lowerUrl.contains('image/') || lowerUrl.contains('jpeg') || lowerUrl.contains('png')) {

      developer.log('_getMediaType: détecté comme IMAGE (MIME)', name: 'ChatPage.Media');

      return 'image';

    }

    if (lowerUrl.contains('video/') || lowerUrl.contains('mp4')) {

      developer.log('_getMediaType: détecté comme VIDEO (MIME)', name: 'ChatPage.Media');

      return 'video';

    }

    if (lowerUrl.contains('audio/') || lowerUrl.contains('mp3')) {

      developer.log('_getMediaType: détecté comme AUDIO (MIME)', name: 'ChatPage.Media');

      return 'audio';

    }

    if (lowerUrl.contains('application/pdf') || lowerUrl.contains('pdf')) {

      developer.log('_getMediaType: détecté comme PDF (MIME)', name: 'ChatPage.Media');

      return 'pdf';

    }



    developer.log('_getMediaType: type non détecté, retour null', name: 'ChatPage.Media');

    return null;

  }

  void _cancelEditing() {

    setState(() {

      _editingMessageId = null;

      _editingIndex = null;

      _editController.clear();

      _highlightedIndex = null;

    });

  }

  Future<void> _sendMessage() async {

    if (_messageController.text.trim().isEmpty || !mounted || roomId == null) return;

    final messageContent = _messageController.text.trim();

    var endpoint = 'https://www.unistudious.com/api/chat/send-messages';

    if (_replyingToId != null) {

      endpoint = 'https://www.unistudious.com/api/chat/reply-message';

    }

    try {

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))..fields['roomId'] = roomId!;

      if (_replyingToId != null) {

        request.fields['text'] = messageContent;

        request.fields['replyToId'] = _replyingToId!;

      } else {

        request.fields['message'] = messageContent;

      }

      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token') ?? '';

      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));

      if (!mounted) return;

      if (response.statusCode == 200) {

        final data = jsonDecode(response.body);

        if (data['success'] == true) {

          final message = _replyingToId != null ? data['data']['message'] : data['message'];

          final newMessage = {

            'id': message['_id'],

            'type': 'text',

            'username': message['u']['username'],

            'name': message['u']['name'],

            'avatar': avatarUrl,

            'timestamp': message['ts'],

            'reactions': {},

            'isSent': true,

            'text': message['msg'],

            'editedAt': null,

            'isEdited': false,

            'replyTo': message['tmid'] ?? _replyingToId,

            'threadMessages': [],

            'threadCount': 0,

            'threadLastMessage': null,

          };

          if (mounted) {

            setState(() {

              messages.add(newMessage);

              _lastMessageId = newMessage['id'];

              _messageController.clear();

              _replyingToId = null;

              _replyingMessage = null;

            });

            final cachedMessages = prefs.getString('messages_cache_$roomId');

            final cacheData = cachedMessages != null ? jsonDecode(cachedMessages) : {'messages': []};

            cacheData['messages'].add(newMessage);

            await prefs.setString('messages_cache_$roomId', jsonEncode(cacheData));

            _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);

          }

        } else {

          throw Exception('Échec de l\'envoi du message.');

        }

      } else {

        throw Exception('Erreur ${response.statusCode} lors de l\'envoi du message.');

      }

    } catch (e, stackTrace) {

      developer.log('Error sending message: $e', name: 'ChatPage', error: e, stackTrace: stackTrace);

      if (mounted) {

        SnackBarHelper.showError(context, 'Erreur lors de l\'envoi du message : $e');

      }

    }

  }

  Future<void> _sendReaction(String messageId, String emoji) async {

    if (!mounted || roomId == null) return;

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

                final reactions = Map<String, dynamic>.from(message['reactions'] ?? {});

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

            final cachedMessages = prefs.getString('messages_cache_$roomId');

            final cacheData = cachedMessages != null ? jsonDecode(cachedMessages) : {'messages': []};

            final cacheMessageIndex = cacheData['messages'].indexWhere((m) => m['id'] == messageId);

            if (cacheMessageIndex != -1) {

              final message = Map<String, dynamic>.from(cacheData['messages'][cacheMessageIndex]);

              final reactions = Map<String, dynamic>.from(message['reactions'] ?? {});

              final reactionKey = ':$emoji:';

              final usernames = reactions[reactionKey] != null ? List<String>.from(reactions[reactionKey]['usernames'] ?? []) : [];

              if (!usernames.contains(currentUser)) {

                usernames.add(currentUser ?? 'Utilisateur');

                reactions[reactionKey] = {'usernames': usernames};

                message['reactions'] = reactions;

                cacheData['messages'][cacheMessageIndex] = message;

                await prefs.setString('messages_cache_$roomId', jsonEncode(cacheData));

              }

            }

            await fetchMessages();

          }

        } else {

          throw Exception('Échec de l\'envoi de la réaction.');

        }

      } else {

        throw Exception('Erreur ${response.statusCode} lors de l\'envoi de la réaction.');

      }

    } catch (e, stackTrace) {

      developer.log('Error sending reaction: $e', name: 'ChatPage', error: e, stackTrace: stackTrace);

      if (mounted) {

        SnackBarHelper.showError(context, 'Erreur lors de l\'envoi de la réaction : $e');

      }

    }

  }

  Future<void> _removeReaction(String messageId, String emoji) async {

    if (!mounted || roomId == null) return;

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

                final reactions = Map<String, dynamic>.from(message['reactions'] ?? {});

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

            final cachedMessages = prefs.getString('messages_cache_$roomId');

            final cacheData = cachedMessages != null ? jsonDecode(cachedMessages) : {'messages': []};

            final cacheMessageIndex = cacheData['messages'].indexWhere((m) => m['id'] == messageId);

            if (cacheMessageIndex != -1) {

              final message = Map<String, dynamic>.from(cacheData['messages'][cacheMessageIndex]);

              final reactions = Map<String, dynamic>.from(message['reactions'] ?? {});

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

                cacheData['messages'][cacheMessageIndex] = message;

                await prefs.setString('messages_cache_$roomId', jsonEncode(cacheData));

              }

            }

            await fetchMessages();

          }

        } else {

          throw Exception('Échec de la suppression de la réaction.');

        }

      } else {

        throw Exception('Erreur ${response.statusCode} lors de la suppression de la réaction.');

      }

    } catch (e, stackTrace) {

      developer.log('Error removing reaction: $e', name: 'ChatPage', error: e, stackTrace: stackTrace);

      if (mounted) {

        SnackBarHelper.showError(context, 'Erreur lors de la suppression de la réaction : $e');

      }

    }

  }

  Future<void> _forwardMessage(String messageId, String targetRoomId) async {

    if (!mounted || roomId == null || targetRoomId.isEmpty) return;

    const endpoint = 'https://www.unistudious.com/api/chat/forward-message';

    try {

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))

        ..fields['messageId'] = messageId

        ..fields['targetRoomId'] = targetRoomId;

      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token') ?? '';

      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));

      if (!mounted) return;

      if (response.statusCode == 200) {

        final data = jsonDecode(response.body);

        if (data['success'] == true) {

          SnackBarHelper.showSuccess(context, 'Message transféré avec succès');

        } else {

          throw Exception('Échec du transfert du message: ${data['message'] ?? 'Erreur inconnue'}');

        }

      } else {

        throw Exception('Erreur ${response.statusCode} lors du transfert du message.');

      }

    } catch (e, stackTrace) {

      developer.log('Error forwarding message: $e', name: 'ChatPage', error: e, stackTrace: stackTrace);

      if (mounted) {

        SnackBarHelper.showError(context, 'Erreur lors du transfert : $e');

      }

    }

  }

  Future<void> _showForwardDialog(int index) async {

    final message = messages[index];

    String? selectedRoomId;

    await _forwardAnimationController.forward();

    await _forwardAnimationController.reverse();

    final confirmed = await showDialog<bool>(

      context: context,

      builder: (BuildContext context) {

        return StatefulBuilder(

          builder: (context, setDialogState) {

            return AnimatedBuilder(

              animation: _forwardAnimationController,

              builder: (context, child) {

                final theme = Theme.of(context);
                final isDark = theme.brightness == Brightness.dark;

                return Transform.scale(

                  scale: _forwardScaleAnimation.value,

                  child: AlertDialog(

                    backgroundColor: isDark ? null : Colors.white,

                    title: Text('Transférer le message', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),

                    content: Column(

                      mainAxisSize: MainAxisSize.min,

                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [

                        Text('Voulez-vous transférer ce message ?', style: GoogleFonts.poppins()),

                        const SizedBox(height: 8),

                        Text(

                          message['text'] ?? '',

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

                            'Sélectionner un destinataire',

                            style: GoogleFonts.poppins(fontSize: 15),

                          ),

                          value: selectedRoomId,

                          isExpanded: true,

                          items: users

                              .where((user) => user['room_id'] != roomId)

                              .map((user) {

                            return DropdownMenuItem<String>(

                              value: user['room_id'],

                              child: Text(

                                user['name'] ?? 'Sans nom',

                                style: GoogleFonts.poppins(),

                                overflow: TextOverflow.ellipsis,

                              ),

                            );

                          }).toList(),

                          onChanged: (value) {

                            setDialogState(() {

                              selectedRoomId = value;

                            });

                          },

                        ),

                      ],

                    ),

                    actions: [

                      TextButton(

                        onPressed: () => Navigator.of(context).pop(false),

                        child: Text('Annuler', style: GoogleFonts.poppins(color: Colors.grey[600])),

                      ),

                      TextButton(

                        onPressed: selectedRoomId == null

                            ? null

                            : () => Navigator.of(context).pop(true),

                        child: Text('Transférer', style: GoogleFonts.poppins(color: selectedRoomId == null ? Colors.grey : Colors.blue)),

                      ),

                    ],

                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

                  ),

                );

              },

            );

          },

        );

      },

    );

    if (confirmed == true && selectedRoomId != null) {

      await _forwardMessage(message['id'], selectedRoomId!);

    } else if (confirmed == true && selectedRoomId == null) {

      SnackBarHelper.showWarning(context, 'Veuillez sélectionner un destinataire.');

    }

  }

  // Fonction pour décoder le JWT et extraire le room depuis le payload
  String? _extractRoomFromJWT(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) {
        developer.log('❌ Invalid JWT format: expected 3 parts, got ${parts.length}', name: 'ChatPage.Jitsi');
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
      developer.log('✅ Extracted room from JWT: $room', name: 'ChatPage.Jitsi');
      return room;
    } catch (e, stackTrace) {
      developer.log('❌ Error decoding JWT: $e', name: 'ChatPage.Jitsi', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<Map<String, dynamic>?> _startCall({required bool isVideoCall}) async {

    if (!mounted || roomId == null) return null;

    const endpoint = 'https://www.unistudious.com/api/chat/start-call';

    try {
      developer.log('=== _startCall() ===', name: 'ChatPage.Jitsi');
      developer.log('roomId: $roomId', name: 'ChatPage.Jitsi');
      developer.log('isVideoCall: $isVideoCall', name: 'ChatPage.Jitsi');

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))..fields['roomId'] = roomId!;

      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token') ?? '';

      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));

      if (!mounted) return null;

      if (response.statusCode == 200) {

        final data = jsonDecode(response.body);
        developer.log('API Response: ${jsonEncode(data)}', name: 'ChatPage.Jitsi');

        if (data['success'] == true) {

          final message = data['data']['message'];

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
            developer.log('✅ Using roomId from API: $roomName', name: 'ChatPage.Jitsi');
          }
          
          // Priorité 2: Utiliser message['rid'] si roomId de l'API n'est pas disponible
          if ((roomName == null || roomName.isEmpty) && message['rid'] != null) {
            roomName = message['rid'].toString();
            // Nettoyer le roomId (enlever "Message+" si présent)
            if (roomName.startsWith('Message+')) {
              roomName = roomName.substring(8);
            }
            developer.log('✅ Using roomName from message[rid]: $roomName', name: 'ChatPage.Jitsi');
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
            developer.log('✅ Generated meetingUrl from baseUrl: $meetingUrl', name: 'ChatPage.Jitsi');
          } else {
            // Ancien format: utiliser meetingUrl de la réponse
            meetingUrl = data['meetingUrl'];
            developer.log('meetingUrl: $meetingUrl', name: 'ChatPage.Jitsi');
            
            jwt = data['jwt'] ?? (meetingUrl != null && meetingUrl.contains('jwt=') ? meetingUrl.split('jwt=')[1].split('&')[0] : null);
            developer.log('jwt extracted: ${jwt != null ? "${jwt.substring(0, 20)}..." : "null"}', name: 'ChatPage.Jitsi');
            
            // Fallback: Extraire depuis le JWT seulement si aucune autre source n'est disponible
            if ((roomName == null || roomName.isEmpty) && jwt != null) {
              roomName = _extractRoomFromJWT(jwt);
              if (roomName != null) {
                developer.log('⚠️ Using room from JWT (fallback): $roomName', name: 'ChatPage.Jitsi');
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

                developer.log('✅ Normalized meetingUrl without \"Message+\": $meetingUrl', name: 'ChatPage.Jitsi');
              }
            }
          }

          final newMessage = {

            'id': message['_id'],

            'type': 'attachment',

            'username': currentUser,

            'name': message['u']['name'],

            'avatar': avatarUrl,

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

              _lastMessageId = newMessage['id'];

            });

            final prefs = await SharedPreferences.getInstance();

            final cachedMessages = prefs.getString('messages_cache_$roomId');

            final cacheData = cachedMessages != null ? jsonDecode(cachedMessages) : {'messages': []};

            cacheData['messages'].add(newMessage);

            await prefs.setString('messages_cache_$roomId', jsonEncode(cacheData));

          }

          developer.log('✅ _startCall() returning: roomName=$roomName, jwt=${jwt != null ? "present" : "null"}', name: 'ChatPage.Jitsi');
          return {'roomName': roomName, 'jwt': jwt, 'meetingUrl': meetingUrl};

        } else {

          developer.log('❌ API returned success=false', name: 'ChatPage.Jitsi');
          throw Exception('Échec du lancement de l\'appel.');

        }

      } else {

        developer.log('❌ API returned status ${response.statusCode}', name: 'ChatPage.Jitsi');
        throw Exception('Erreur ${response.statusCode} lors du lancement de l\'appel.');

      }

    } catch (e, stackTrace) {

      developer.log('❌ Error starting call: $e', name: 'ChatPage.Jitsi', error: e, stackTrace: stackTrace);

      if (mounted) {

        SnackBarHelper.showError(context, 'Erreur lors du lancement de l\'appel : $e');

      }

      return null;

    }

  }

  Future<Map<String, dynamic>?> _joinCall() async {

    if (!mounted || roomId == null) return null;

    const endpoint = 'https://www.unistudious.com/api/chat/join-call';

    try {
      developer.log('=== _joinCall() ===', name: 'ChatPage.Jitsi');
      developer.log('roomId: $roomId', name: 'ChatPage.Jitsi');

      final request = http.MultipartRequest('POST', Uri.parse(endpoint))..fields['roomId'] = roomId!;

      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('auth_token') ?? '';

      if (token.isEmpty) throw Exception('Aucun token d\'authentification trouvé.');

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 30)));

      if (!mounted) return null;

      if (response.statusCode == 200) {

        final data = jsonDecode(response.body);
        developer.log('API Response: ${jsonEncode(data)}', name: 'ChatPage.Jitsi');

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
            developer.log('✅ Using roomId from API: $roomName', name: 'ChatPage.Jitsi');
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
              developer.log('✅ Using roomName from message[rid]: $roomName', name: 'ChatPage.Jitsi');
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
            developer.log('✅ Generated meetingUrl from baseUrl: $meetingUrl', name: 'ChatPage.Jitsi');
          } else {
            // Ancien format: utiliser meetingUrl de la réponse
            meetingUrl = data['meetingUrl'];
            developer.log('meetingUrl: $meetingUrl', name: 'ChatPage.Jitsi');
            
            jwt = data['jwt'] ?? (meetingUrl != null && meetingUrl.contains('jwt=') ? meetingUrl.split('jwt=')[1].split('&')[0] : null);
            developer.log('jwt from API: ${jwt != null ? "${jwt.substring(0, 20)}..." : "null"}', name: 'ChatPage.Jitsi');
            
            // Fallback: Extraire depuis le JWT seulement si aucune autre source n'est disponible
            if ((roomName == null || roomName.isEmpty) && jwt != null) {
              roomName = _extractRoomFromJWT(jwt);
              if (roomName != null) {
                developer.log('⚠️ Using room from JWT (fallback): $roomName', name: 'ChatPage.Jitsi');
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

                developer.log('✅ Normalized meetingUrl without \"Message+\": $meetingUrl', name: 'ChatPage.Jitsi');
              }
            }
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
              developer.log('⚠️ Using roomName from message[rid] (fallback): $roomName', name: 'ChatPage.Jitsi');
            }
          }
          
          if (roomName == null || roomName.isEmpty || jwt == null || jwt.isEmpty) {
            developer.log('❌ Missing roomName or jwt. roomName=$roomName, jwt=${jwt != null ? "present" : "null"}', name: 'ChatPage.Jitsi');
            throw Exception('Données de réunion invalides dans la réponse.');
          }

          developer.log('✅ _joinCall() returning: roomName=$roomName, jwt=${jwt != null ? "present" : "null"}', name: 'ChatPage.Jitsi');
          return {'roomName': roomName, 'jwt': jwt, 'meetingUrl': meetingUrl};

        } else {

          developer.log('❌ API returned success=false', name: 'ChatPage.Jitsi');
          throw Exception('Échec du lancement de l\'appel.');

        }

      } else {

        developer.log('❌ API returned status ${response.statusCode}', name: 'ChatPage.Jitsi');
        throw Exception('Erreur ${response.statusCode} lors du lancement de l\'appel.');

      }

    } catch (e, stackTrace) {

      developer.log('❌ Error joining call: $e', name: 'ChatPage.Jitsi', error: e, stackTrace: stackTrace);

      if (mounted) {

        SnackBarHelper.showError(context, 'Erreur lors de la connexion à l\'appel : $e');

      }

      return null;

    }

  }

  Future<void> _launchCall({String? url, required bool isVideoCall}) async {

    developer.log('=== _launchCall() ===', name: 'ChatPage.Jitsi');
    developer.log('url: $url', name: 'ChatPage.Jitsi');
    developer.log('isVideoCall: $isVideoCall', name: 'ChatPage.Jitsi');
    developer.log('roomId: $roomId', name: 'ChatPage.Jitsi');
    developer.log('currentUser: $currentUser', name: 'ChatPage.Jitsi');

    Map<String, dynamic>? meetingData;

    if (url == null) {
      // Démarrer un nouvel appel
      developer.log('Starting new call...', name: 'ChatPage.Jitsi');
      meetingData = await _startCall(isVideoCall: isVideoCall);
    } else {
      // Rejoindre un appel existant - IGNORER l'URL car elle ne contient pas de JWT
      // Toujours utiliser _joinCall() qui fait l'appel API pour obtenir le bon JWT et room
      developer.log('Joining existing call from message...', name: 'ChatPage.Jitsi');
      developer.log('⚠️ URL from message (will be ignored): $url', name: 'ChatPage.Jitsi');
      developer.log('⚠️ URL does not contain JWT, using _joinCall() API instead', name: 'ChatPage.Jitsi');
      meetingData = await _joinCall();
    }

    if (meetingData == null || meetingData['roomName'] == null || meetingData['jwt'] == null) {
      developer.log('❌ Missing meeting data. meetingData=$meetingData', name: 'ChatPage.Jitsi');
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

        developer.log('✅ Using meetingUrl as source of truth:', name: 'ChatPage.Jitsi');
        developer.log('  - meetingUrl: $meetingUrl', name: 'ChatPage.Jitsi');
        developer.log('  - parsed domain: $domain', name: 'ChatPage.Jitsi');
        developer.log('  - parsed roomName: $roomName', name: 'ChatPage.Jitsi');
        developer.log('  - parsed jwt (start): ${jwt.substring(0, 20)}...', name: 'ChatPage.Jitsi');
      } catch (e, stackTrace) {
        developer.log(
          '⚠️ Failed to parse meetingUrl, falling back to API fields. Error: $e',
          name: 'ChatPage.Jitsi',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    developer.log('🎯 Joining Jitsi room:', name: 'ChatPage.Jitsi');
    developer.log('  - roomName: $roomName', name: 'ChatPage.Jitsi');
    developer.log('  - jwt: ${jwt.substring(0, 20)}...', name: 'ChatPage.Jitsi');
    developer.log('  - domain: $domain', name: 'ChatPage.Jitsi');

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

        userInfo: JitsiMeetUserInfo(displayName: currentUser ?? 'Utilisateur', email: 'utilisateur@example.com'),

      );

      developer.log('🚀 Calling _jitsiMeet.join() with room=$roomName', name: 'ChatPage.Jitsi');
      await _jitsiMeet.join(options);
      developer.log('✅ Successfully joined Jitsi meeting', name: 'ChatPage.Jitsi');

    } catch (e, stackTrace) {

      developer.log('❌ Error joining Jitsi meeting: $e', name: 'ChatPage.Jitsi', error: e, stackTrace: stackTrace);

      if (mounted) {

        SnackBarHelper.showError(context, 'Erreur lors de la connexion à la réunion : $e');

      }

    }

  }

  void _showReactions(BuildContext context, int index) {

    if (_editingMessageId != null) return;

    setState(() {

      _highlightedIndex = index;

      _reactionIndex = index;

    });

  }

  void _handleOutsideClick() {

    // Unfocus de la barre d'écriture
    _messageFocusNode.unfocus();

    if (_reactionIndex != null || _moreOptionsIndex != null) {

      setState(() {

        _reactionIndex = null;

        _highlightedIndex = null;

        _moreOptionsIndex = null;

      });

    }

  }

  void _toggleReaction(int index, String emoji) {

    if (!mounted || _editingMessageId != null) return;

    final messageId = messages[index]['id'];

    final reactionKey = ':${reactionLabels[emoji]}:';

    final reactions = Map<String, dynamic>.from(messages[index]['reactions'] ?? {});

    final usernames = reactions[reactionKey] != null ? List<String>.from(reactions[reactionKey]['usernames'] ?? []) : [];

    if (usernames.contains(currentUser)) {

      _removeReaction(messageId, reactionLabels[emoji]!);

    } else {

      _sendReaction(messageId, reactionLabels[emoji]!);

    }

  }

  void _showMoreOptions(BuildContext context, int index) {

    if (_editingMessageId != null) return;

    setState(() {

      _moreOptionsIndex = index;

      _highlightedIndex = index;

    });

  }

  void _handleMoreOptionSelected(String option, int index) async {

    final message = messages[index];

    final isMe = message['username'] == currentUser;

    setState(() {

      _moreOptionsIndex = null;

      _highlightedIndex = null;

    });

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

          _replyingToId = message['id'];

          _replyingMessage = Map.from(message);

        });

        break;

      case 'delete':

        await _confirmDeleteMessage(index);

        break;

      case 'copy':

        await Clipboard.setData(ClipboardData(text: message['text']));

        SnackBarHelper.showSuccess(context, 'Message copié');

        break;

      case 'forward':

        await _showForwardDialog(index);

        break;

    }

  }

  void _startEditing(int index) {

    final message = messages[index];

    setState(() {

      _editingMessageId = message['id'];

      _editingIndex = index;

      _editController.text = message['text'] ?? '';

      _highlightedIndex = index;

    });

  }

  void _confirmEditing(int index) async {

    if (_editController.text.trim().isEmpty) {

      SnackBarHelper.showWarning(context, 'Le message ne peut pas être vide');

      return;

    }

    await _editMessage(messages[index]['id'], _editController.text.trim(), index);

  }

  @override

  void dispose() {

    _messageController.dispose();

    _editController.dispose();

    _messageFocusNode.dispose();

    _pollingTimer?.cancel();

    _wsMessageSubscription?.cancel();
    _wsDeleteSubscription?.cancel();
    _wsConnectionSubscription?.cancel();
    _wsService.dispose();

    _scrollController.dispose();

    _animationController.dispose();

    _forwardAnimationController.dispose();

    _audioRecorder.dispose();

    super.dispose();

  }

  // Widget pour afficher une image dans le chat

  // Remplace toute la partie image par ÇA :

  Widget _buildImageWidget(String imageUrl, bool isDark, {String? previewBase64}) {
    // 1. Si on a un preview base64 → affichage IMMÉDIAT (comme Messenger)
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
        developer.log('Erreur décodage preview base64', name: 'ChatPage.Media');
      }
    }

    // 2. Sinon → on utilise CachedNetworkImage avec cache forcé
    final fullUrl = _getFullUrl(imageUrl);
    if (fullUrl.isEmpty) return const SizedBox.shrink();

    return _buildImageContainer(
      child: CachedNetworkImage(
        imageUrl: fullUrl,
        fit: BoxFit.cover,
        memCacheWidth: 800, // optimise la mémoire
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
        // IMPORTANT : forcer le cache même avec query params dynamiques
        cacheKey: _generateCacheKey(fullUrl), // on retire les tokens du cache key
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

// Clé de cache stable (on enlève rc_token et rc_uid car ils changent à chaque connexion
  String _generateCacheKey(String url) {
    final uri = Uri.parse(url);
    final params = Map<String, String>.from(uri.queryParameters)
      ..remove('rc_token')
      ..remove('rc_uid');
    return Uri.parse(url).replace(queryParameters: params).toString();
  }

  // Widget pour utiliser CachedNetworkImage (pour URLs Rocket.Chat avec tokens)

  Widget _buildCachedNetworkImage(String imageUrl, bool isDark) {

    return CachedNetworkImage(

      imageUrl: imageUrl,

      width: MediaQuery.of(context).size.width * 0.6,

      fit: BoxFit.cover,

      placeholder: (context, url) => Container(

        width: MediaQuery.of(context).size.width * 0.6,

        height: 200,

        color: isDark ? Colors.grey[800] : Colors.grey[200],

        child: const Center(child: CircularProgressIndicator()),

      ),

      errorWidget: (context, url, error) {

        developer.log(

          '_buildCachedNetworkImage: Erreur lors du chargement de l\'image: $error',

          name: 'ChatPage.Media',

        );

        return Container(

          width: MediaQuery.of(context).size.width * 0.6,

          height: 200,

          color: isDark ? Colors.grey[800] : Colors.grey[200],

          child: Column(

            mainAxisAlignment: MainAxisAlignment.center,

            children: [

              const Icon(Icons.error, color: Colors.red, size: 32),

              const SizedBox(height: 8),

              Text(

                'Erreur de chargement',

                style: GoogleFonts.poppins(

                  color: isDark ? Colors.white : Colors.black87,

                  fontSize: 12,

                ),

              ),

            ],

          ),

        );

      },

    );

  }

  // Widget pour utiliser FutureBuilder avec fetchProtectedImage (pour URLs sans tokens Rocket.Chat)

  Widget _buildFutureBuilderImage(String imageUrl, bool isDark) {

    return FutureBuilder<Uint8List?>(

      future: fetchProtectedImage(imageUrl),

      builder: (context, snapshot) {

        if (snapshot.connectionState == ConnectionState.waiting) {

          return Container(

            width: MediaQuery.of(context).size.width * 0.6,

            height: 200,

            color: isDark ? Colors.grey[800] : Colors.grey[200],

            child: const Center(child: CircularProgressIndicator()),

          );

        }

        if (!snapshot.hasData || snapshot.data == null) {

          developer.log(

            '_buildFutureBuilderImage: impossible de charger l\'image (snapshot vide)',

            name: 'ChatPage.Media',

          );

          return Container(

            width: MediaQuery.of(context).size.width * 0.6,

            height: 200,

            color: isDark ? Colors.grey[800] : Colors.grey[200],

            child: const Icon(Icons.lock, color: Colors.red),

          );

        }

        return Image.memory(

          snapshot.data!,

          width: MediaQuery.of(context).size.width * 0.6,

          fit: BoxFit.cover,

        );

      },

    );

  }

  // Widget pour afficher une vidéo dans le chat

  // Dans _buildVideoWidget et dans _VideoPlayerScreen → remplace tout par ça :

  // Fallback vidéo — FORCE le téléchargement complet (plus jamais d'erreur -12983 sur iOS)
  Widget _buildVideoFallback(String videoUrl, bool isDark) {
    final fullUrl = _getFullUrl(videoUrl);

    return GestureDetector(
      onTap: () async {
        // Télécharge TOUT le fichier en mémoire/temporaire → évite AVPlayer
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
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        height: 200,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[850] : Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.play_circle_filled, size: 64, color: Colors.white70),
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
    );
  }

  Widget _buildVideoWidget(String videoUrl, bool isDark, Map<String, dynamic> message) {
    // Extraire fileId et fileName depuis le message
    final fileId = message['file']?['_id']?.toString() ??
        message['files']?[0]?['_id']?.toString();

    final fileName = message['file']?['name']?.toString() ??
        message['files']?[0]?['name']?.toString() ??
        'video.mp4';

    if (fileId == null) {
      return _buildVideoFallback(videoUrl, isDark); // ancienne méthode si pas d'ID
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
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        height: 200,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[850] : Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.play_circle_filled, size: 64, color: Colors.white70),
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
    );
  }

// Nouvelle fonction à ajouter dans ta classe _ChatPageState
  Future<void> _openVideoInBrowser(String url) async {
    final uri = Uri.parse(url);

    // Si l'URL a déjà les tokens Rocket.Chat → on l'ouvre directement
    if (uri.queryParameters.containsKey('rc_token') &&
        uri.queryParameters.containsKey('rc_uid')) {
      try {
        final bool launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication, // ouvre dans Safari/Chrome
        );

        if (!launched) {
          if (mounted) {
            SnackBarHelper.showError(context, 'Impossible d\'ouvrir la vidéo');
          }
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(context, 'Erreur : $e');
        }
      }
      return;
    }

    // Sinon, on récupère les bytes avec fetchProtectedImage puis on sauve en temporaire
    final bytes = await fetchProtectedImage(url);
    if (bytes == null || !mounted) {
      SnackBarHelper.showError(context, 'Impossible de télécharger la vidéo');
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = io.File('${tempDir.path}/temp_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await tempFile.writeAsBytes(bytes);

      await launchUrl(
        Uri.file(tempFile.path),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur d\'ouverture : $e');
      }
    }
  }

  // Widget pour afficher un audio dans le chat

  Widget _buildAudioWidget(String audioUrl, String? fileName, bool isDark, Map<String, dynamic> message) {
    final fileId = message['file']?['_id']?.toString() ??
        message['files']?[0]?['_id']?.toString();

    // Toujours utiliser en priorité le vrai nom de fichier retourné par Rocket.Chat,
    // car l'API /api/chat/read/file a besoin du nom exact pour autoriser l'accès.
    final rcFileName = message['file']?['name']?.toString() ??
        message['files']?[0]?['name']?.toString();

    final nameForApi = rcFileName ?? fileName ?? 'audio';
    final nameForDisplay = fileName ?? rcFileName ?? 'audio';

    final audioKey = ValueKey('audio_${message['_id'] ?? message['id'] ?? fileId ?? audioUrl}');

    // Cas où on n'a pas d'ID de fichier → on utilise directement l'URL (ancienne méthode)
    if (fileId == null) {
      final fullUrl = _getFullUrl(audioUrl);
      final enrichedUrl = _enrichUrlWithRcTokens(fullUrl, message);
      return _AudioPlayerWidget(key: audioKey, audioUrl: enrichedUrl, fileName: nameForDisplay, isDark: isDark);
    }

    // Cas avec fileId → on essaie d'abord l'API /api/chat/read/file
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

        // Si l'API échoue (null), on retombe sur l'URL enrichie Rocket.Chat comme fallback
        if (path == null) {
          final fullUrl = _getFullUrl(audioUrl);
          final enrichedUrl = _enrichUrlWithRcTokens(fullUrl, message);
          return _AudioPlayerWidget(key: audioKey, audioUrl: enrichedUrl, fileName: nameForDisplay, isDark: isDark);
        }

        // Succès de /api/chat/read/file → lecture du fichier local
        return _AudioPlayerWidget(key: audioKey, audioUrl: path, fileName: nameForDisplay, isDark: isDark);
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
          // Télécharger via l'API pour récupérer le fichier protégé
          localPath = await _getPlayableFileUrl(fileId: fileId, fileName: name);
        } else {
          // Sinon télécharger directement l'URL protégée
          try {
            final bytes = await fetchProtectedImage(_getFullUrl(pdfUrl));
            if (bytes != null && mounted) {
              final tempDir = await getTemporaryDirectory();
              final tempFile = io.File('${tempDir.path}/pdf_${DateTime.now().millisecondsSinceEpoch}.pdf');
              await tempFile.writeAsBytes(bytes);
              localPath = tempFile.path;
            }
          } catch (e) {
            developer.log('Error downloading PDF: $e', name: 'ChatPage.Media');
          }
        }

        if (localPath != null && mounted) {
          final path = localPath;
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

    developer.log('_buildMediaWidgetFromMessage: Analyse du message', name: 'ChatPage.Media');

    developer.log('_buildMediaWidgetFromMessage: message keys = ${message.keys.toList()}', name: 'ChatPage.Media');

    developer.log('_buildMediaWidgetFromMessage: message type = ${message['type']}', name: 'ChatPage.Media');

    developer.log('_buildMediaWidgetFromMessage: message[attachments] = ${message['attachments']}', name: 'ChatPage.Media');

    developer.log('_buildMediaWidgetFromMessage: message[file] = ${message['file']}', name: 'ChatPage.Media');

    developer.log('_buildMediaWidgetFromMessage: message[files] = ${message['files']}', name: 'ChatPage.Media');

    // Vérifier d'abord les attachments

    if (message['attachments'] != null && (message['attachments'] as List).isNotEmpty) {

      developer.log('_buildMediaWidgetFromMessage: Traitement des attachments', name: 'ChatPage.Media');

      final attachments = message['attachments'] as List;

      developer.log('_buildMediaWidgetFromMessage: Nombre d\'attachments = ${attachments.length}', name: 'ChatPage.Media');

      final attachment = attachments.first as Map<String, dynamic>;

      developer.log('_buildMediaWidgetFromMessage: Premier attachment = $attachment', name: 'ChatPage.Media');



      var mediaUrl = _getMediaUrlFromAttachment(attachment);

      if (mediaUrl == null || mediaUrl.isEmpty) {

        developer.log('_buildMediaWidgetFromMessage: mediaUrl vide depuis attachment, retour null', name: 'ChatPage.Media');

        return null;

      }



      // Enrichir l'URL avec les tokens Rocket.Chat si nécessaire

      final fullUrl = _getFullUrl(mediaUrl);

      mediaUrl = _enrichUrlWithRcTokens(fullUrl, message);



      final title = attachment['title']?.toString() ?? '';

      final fileName = attachment['title']?.toString() ?? attachment['description']?.toString();

      final mediaType = _getMediaType(mediaUrl, fileName);



      developer.log('_buildMediaWidgetFromMessage: mediaUrl = "$mediaUrl", mediaType = "$mediaType"', name: 'ChatPage.Media');



      if (mediaType == 'image') {

        developer.log('_buildMediaWidgetFromMessage: Construction du widget image', name: 'ChatPage.Media');

        final previewBase64 = _getImagePreviewBase64(attachment);

        return _buildImageWidget(mediaUrl, isDark, previewBase64: previewBase64);

      } else if (mediaType == 'video') {

        developer.log('_buildMediaWidgetFromMessage: Construction du widget vidéo', name: 'ChatPage.Media');

        return _buildVideoWidget(mediaUrl, isDark, message);  // on passe le message complet;

      } else if (mediaType == 'audio') {

        developer.log('_buildMediaWidgetFromMessage: Construction du widget audio', name: 'ChatPage.Media');

        return _buildAudioWidget(mediaUrl, fileName, isDark, message);

      } else if (mediaType == 'pdf') {

        developer.log('_buildMediaWidgetFromMessage: Construction du widget PDF', name: 'ChatPage.Media');

        return _buildPdfWidget(mediaUrl, fileName, isDark, message);

      } else {

        developer.log('_buildMediaWidgetFromMessage: Type média inconnu ou null: "$mediaType"', name: 'ChatPage.Media');

      }

    }



    // Vérifier le champ file

    if (message['file'] != null && message['file'] is Map) {

      developer.log('_buildMediaWidgetFromMessage: Traitement du champ file', name: 'ChatPage.Media');

      final file = message['file'] as Map<String, dynamic>;

      final fileUrl = file['url']?.toString();



      if (fileUrl == null || fileUrl.isEmpty) {

        developer.log('_buildMediaWidgetFromMessage: fileUrl vide depuis file, retour null', name: 'ChatPage.Media');

        return null;

      }



      // Utiliser directement file['category'] pour déterminer le type de média

      // L'URL est déjà complète avec les tokens Rocket.Chat depuis l'API

      final category = file['category']?.toString().toLowerCase();

      final fileName = file['name']?.toString();



      developer.log('_buildMediaWidgetFromMessage: fileUrl = "$fileUrl", category = "$category"', name: 'ChatPage.Media');



      if (category == 'image') {

        return _buildImageWidget(fileUrl, isDark);

      } else if (category == 'video') {

        return _buildVideoWidget(fileUrl, isDark, message);

      } else if (category == 'audio') {

        return _buildAudioWidget(fileUrl, fileName, isDark, message);

      } else {

        // Si category n'est pas définie ou est "other", essayer de détecter depuis l'URL

        final mediaType = _getMediaType(fileUrl, fileName);

        developer.log('_buildMediaWidgetFromMessage: Détection depuis URL, mediaType = "$mediaType"', name: 'ChatPage.Media');



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

      developer.log('_buildMediaWidgetFromMessage: Traitement du champ files', name: 'ChatPage.Media');

      final files = message['files'] as List;

      final file = files.first;

      final fileUrl = _getMediaUrlFromFile(file);

      if (fileUrl == null || fileUrl.isEmpty) {

        developer.log('_buildMediaWidgetFromMessage: fileUrl vide depuis files, retour null', name: 'ChatPage.Media');

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



    developer.log('_buildMediaWidgetFromMessage: Aucun média détecté, retour null', name: 'ChatPage.Media');

    return null;

  }

  @override

  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    return WillPopScope(

      onWillPop: () async {

        Navigator.pop(context);

        // On retourne false car on gère nous‑mêmes le pop
        return false;

      },

      child: GestureDetector(

      onTap: () {

        _handleOutsideClick();

        if (_editingMessageId != null) {

          _cancelEditing();

        }

      },

        child: Scaffold(

        appBar: AppBar(

          backgroundColor: Colors.transparent,

          elevation: 0,

          flexibleSpace: Container(

            decoration: BoxDecoration(

              gradient: LinearGradient(

                colors: isDark ? const [Color(0xFF1A003D), Color(0xFF3C0D73)]
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

              Stack(

                children: [

                  CircleAvatar(

                    radius: 20,

                    backgroundColor: Colors.grey[300],

                    child: _buildAvatarWidget(avatarUrl, contactName ?? '', size: 40),

                  ),

                  if (status == 'online')

                    Positioned(

                      right: 0,

                      bottom: 0,

                      child: Container(

                        width: 12,

                        height: 12,

                        decoration: const BoxDecoration(

                          color: Colors.green,

                          shape: BoxShape.circle,

                          border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2)),

                        ),

                      ),

                    ),

                ],

              ),

              const SizedBox(width: 10),

              Expanded(

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Text(

                      contactName ?? 'Sans nom',

                      overflow: TextOverflow.ellipsis,

                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 18),

                    ),

                    Text(

                      status == 'online' ? 'Actif maintenant' : 'Hors ligne',

                      style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),

                    ),

                  ],

                ),

              ),

            ],

          ),

          actions: [

            IconButton(

              icon: const Icon(Icons.call, color: Colors.white),

              onPressed: () => _launchCall(isVideoCall: false),

            ),

            IconButton(

              icon: const Icon(Icons.videocam, color: Colors.white),

              onPressed: () => _launchCall(isVideoCall: true),

            ),

            IconButton(

              icon: const Icon(Icons.more_vert, color: Colors.white),

              onPressed: () {

                Navigator.push(

                  context,

                  MaterialPageRoute(

                    builder: (context) => ChatDetailsPage(

                      contactName: contactName ?? 'Sans nom',

                      avatarUrl: avatarUrl,

                      roomId: roomId ?? '', // Pass the roomId

                    ),

                  ),

                );

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

          child: Stack(

            children: [

              Column(

                children: [

                  Expanded(

                    child: ListView.builder(

                      controller: _scrollController,

                      reverse: true,

                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),

                      itemCount: messages.length,

                      itemBuilder: (context, index) {

                        final message = messages[messages.length - 1 - index];

                        final isMe = message['username'] == currentUser;

                        final isAttachment = message['type'] == 'attachment';

                        final listIndex = messages.length - 1 - index;

                        final isEditing = _editingMessageId == message['id'];

                        final formattedTime = _formatMessageTime(message['timestamp'] ?? '');

                        final reactionsData = Map<String, dynamic>.from(message['reactions'] ?? {});

                        final displayedReactions = <Map<String, dynamic>>[];

                        reactionsData.forEach((key, value) {

                          final code = key.substring(1, key.length - 1);

                          final emojiEntry = reactionLabels.entries.firstWhere(

                                (entry) => entry.value == code,

                            orElse: () => const MapEntry('', ''),

                          );

                          if (emojiEntry.key.isNotEmpty) {

                            final count = (value['usernames'] as List).length;

                            final userReacted = (value['usernames'] as List).contains(currentUser);

                            displayedReactions.add({

                              'emoji': emojiEntry.key,

                              'code': code,

                              'count': count,

                              'userReacted': userReacted,

                            });

                          }

                        });

                        Widget? quotedWidget;

                        if (message['replyTo'] != null) {

                          // replyTo peut être un ID (string) ou un objet avec les informations
                          dynamic replyToData = message['replyTo'];
                          String? replyToId;
                          Map<String, dynamic>? originalMessageData;

                          if (replyToData is Map) {
                            // Si c'est un objet, utiliser directement les données
                            originalMessageData = Map<String, dynamic>.from(replyToData);
                            replyToId = originalMessageData['messageId'] ?? originalMessageData['id'];
                          } else {
                            // Si c'est juste un ID, chercher le message dans la liste
                            replyToId = replyToData?.toString();
                          }

                          // Si on n'a pas encore les données du message original, le chercher
                          if (originalMessageData == null && replyToId != null) {
                            originalMessageData = messages.firstWhere(

                                  (m) => m['id'] == replyToId,

                              orElse: () => {
                                'name': 'Message supprimé',
                                'username': 'Inconnu',
                                'text': 'Ce message a été supprimé ou n\'est pas disponible.',
                                'id': replyToId
                              },

                            );
                          }

                          final originalMessage = originalMessageData ?? {
                            'name': 'Message supprimé',
                            'username': 'Inconnu',
                            'text': 'Ce message a été supprimé ou n\'est pas disponible.'
                          };

                          quotedWidget = Container(

                            margin: const EdgeInsets.only(bottom: 8),

                            padding: const EdgeInsets.all(8),

                            decoration: BoxDecoration(

                              color: isMe ? (isDark ? Colors.black.withOpacity(0.2) : Colors.white.withOpacity(0.2)) : (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),

                              borderRadius: BorderRadius.circular(8),

                              border: Border(left: BorderSide(color: Colors.blueAccent, width: 4)),

                            ),

                            child: Column(

                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [

                                Text(

                                  originalMessage['name'] ?? originalMessage['username'] ?? 'Inconnu',

                                  style: GoogleFonts.poppins(

                                    fontWeight: FontWeight.bold,

                                    fontSize: 12,

                                    color: isMe ? Colors.white70 : (isDark ? Colors.white70 : Colors.black87),

                                  ),

                                ),

                                LinkableText(

                                  text: originalMessage['text'] ?? '',

                                  maxLines: 2,

                                  overflow: TextOverflow.ellipsis,

                                  style: GoogleFonts.poppins(

                                    fontSize: 12,

                                    color: isMe ? Colors.white70 : (isDark ? Colors.white70 : Colors.grey[600]),

                                  ),

                                ),

                              ],

                            ),

                          );

                        }

                        Widget editWidget = Container();

                        if (isEditing && isMe) {

                          editWidget = Container(

                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),

                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

                            decoration: BoxDecoration(

                              color: isDark ? Colors.grey[700] : Colors.grey[300],

                              borderRadius: BorderRadius.circular(20),

                              border: Border.all(color: Colors.blue, width: 2),

                            ),

                            child: Column(

                              crossAxisAlignment: CrossAxisAlignment.end,

                              children: [

                                Row(

                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,

                                  children: [

                                    Text(

                                      'Édition',

                                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),

                                    ),

                                    Row(

                                      mainAxisSize: MainAxisSize.min,

                                      children: [

                                        IconButton(

                                          icon: const Icon(Icons.check, size: 20, color: Colors.green),

                                          onPressed: () => _confirmEditing(listIndex),

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

                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),

                                    filled: true,

                                    fillColor: isDark ? Colors.grey[800] : Colors.white,

                                  ),

                                  style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black87, fontSize: 15),

                                ),

                              ],

                            ),

                          );

                        }

                        return Column(

                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [

                            if (!isEditing || !isMe)

                              GestureDetector(

                                onLongPress: () => _showReactions(context, listIndex),

                                child: Padding(

                                  padding: const EdgeInsets.symmetric(vertical: 4),

                                  child: Row(

                                    mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,

                                    crossAxisAlignment: CrossAxisAlignment.start,

                                    children: [

                                      if (!isMe) ...[

                                        const SizedBox(width: 8),

                                        Flexible(

                                          child: Column(

                                            crossAxisAlignment: CrossAxisAlignment.start,

                                            children: [

                                              Container(

                                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),

                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

                                                decoration: BoxDecoration(

                                                  color: _highlightedIndex == listIndex && !isEditing ? (isDark ? Colors.grey[700] : Colors.grey[300]) : (isDark ? Colors.grey[800] : Colors.grey[200]),

                                                  borderRadius: BorderRadius.circular(20).copyWith(bottomLeft: const Radius.circular(0)),

                                                ),

                                                child: Column(

                                                  crossAxisAlignment: CrossAxisAlignment.start,

                                                  children: [

                                                    if (quotedWidget != null) quotedWidget,

                                                    if (isAttachment || message['file'] != null || (message['files'] != null && (message['files'] as List).isNotEmpty))

                                                          () {

                                                        developer.log('=== DÉBUT TRAITEMENT ATTACHMENT (message reçu) ===', name: 'ChatPage.Media');

                                                        developer.log('Message complet: ${jsonEncode(message)}', name: 'ChatPage.Media');

                                                        developer.log('isAttachment: $isAttachment', name: 'ChatPage.Media');

                                                        developer.log('message[type]: ${message['type']}', name: 'ChatPage.Media');



                                                        // Essayer d'afficher un média (image, vidéo, audio)

                                                        final mediaWidget = _buildMediaWidgetFromMessage(message, isDark);



                                                        if (mediaWidget != null) {

                                                          developer.log('_buildMediaWidgetFromMessage a retourné un widget média', name: 'ChatPage.Media');

                                                        } else {

                                                          developer.log('_buildMediaWidgetFromMessage a retourné null, affichage format classique', name: 'ChatPage.Media');

                                                        }



                                                        if (mediaWidget != null) {

                                                          return mediaWidget;

                                                        }



                                                        // Sinon, afficher le format classique pour les autres types de fichiers

                                                        final List attachments =

                                                            (message['attachments'] as List?) ?? [];

                                                        final Map<String, dynamic>? att =

                                                        attachments.isNotEmpty

                                                            ? attachments.first

                                                        as Map<String, dynamic>?

                                                            : null;

                                                        final List<dynamic>? actions =

                                                        att?['actions'] as List<dynamic>?;

                                                        final String title =

                                                            att?['title']?.toString() ??

                                                                att?['description']?.toString() ??

                                                                'Pièce jointe';

                                                        final String description =

                                                            att?['text']?.toString() ??

                                                                'Pièce jointe envoyée';

                                                        final String? actionText =

                                                        (actions != null &&

                                                            actions.isNotEmpty)

                                                            ? actions[0]['text']

                                                            ?.toString()

                                                            : null;

                                                        final String? actionUrl =

                                                        (actions != null &&

                                                            actions.isNotEmpty)

                                                            ? actions[0]['url']

                                                            ?.toString()

                                                            : null;

                                                        // URL de fichier/image à ouvrir au clic

                                                        final String? fileUrl =

                                                            att?['image_url']

                                                                ?.toString() ??

                                                                att?['title_link']

                                                                    ?.toString() ??

                                                                actionUrl ??

                                                                _getMediaUrlFromFile(message['file']);

                                                        return InkWell(

                                                          onTap: fileUrl != null

                                                              ? () =>

                                                              _openAttachmentUrl(

                                                                  fileUrl)

                                                              : null,

                                                          child: Column(

                                                            crossAxisAlignment:

                                                            CrossAxisAlignment

                                                                .start,

                                                            children: [

                                                              Text(

                                                                title,

                                                                style: GoogleFonts.poppins(

                                                                    color: isDark

                                                                        ? Colors

                                                                        .white

                                                                        : Colors

                                                                        .black87,

                                                                    fontSize: 15,

                                                                    fontWeight:

                                                                    FontWeight

                                                                        .bold),

                                                              ),

                                                              const SizedBox(

                                                                  height: 4),

                                                              Text(

                                                                description,

                                                                style: GoogleFonts.poppins(

                                                                    color: isDark

                                                                        ? Colors

                                                                        .white70

                                                                        : Colors

                                                                        .grey[600],

                                                                    fontSize: 13),

                                                              ),

                                                              if (actionUrl !=

                                                                  null &&

                                                                  actionText !=

                                                                      null) ...[

                                                                const SizedBox(

                                                                    height: 8),

                                                                ElevatedButton(

                                                                  onPressed: () =>

                                                                      _launchCall(

                                                                          url: actionUrl,

                                                                          isVideoCall:

                                                                          true),

                                                                  style: ElevatedButton

                                                                      .styleFrom(

                                                                    backgroundColor: isDark

                                                                        ? const Color(

                                                                        0xFF1A003D)

                                                                        : const Color(

                                                                        0xFF4A00E0),

                                                                    foregroundColor:

                                                                    Colors

                                                                        .white,

                                                                  ),

                                                                  child: Text(

                                                                    actionText,

                                                                    style: GoogleFonts.poppins(

                                                                        color: Colors

                                                                            .white,

                                                                        fontSize:

                                                                        14),

                                                                  ),

                                                                ),

                                                              ],

                                                            ],

                                                          ),

                                                        );

                                                      }()

                                                    else

                                                      Column(

                                                        crossAxisAlignment: CrossAxisAlignment.start,

                                                        children: [

                                                          LinkableText(

                                                            text: message['text'] ?? '',

                                                            style: GoogleFonts.poppins(
                                                              color: isDark ? Colors.white : Colors.black87, 
                                                              fontSize: 15,
                                                              fontWeight: message['isUnread'] == true ? FontWeight.bold : FontWeight.normal,
                                                            ),

                                                          ),

                                                          if (message['isEdited'] == true)

                                                            Padding(

                                                              padding: const EdgeInsets.only(top: 4.0),

                                                              child: Text(

                                                                'Édité',

                                                                style: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.grey[600], fontSize: 10, fontStyle: FontStyle.italic),

                                                              ),

                                                            ),

                                                        ],

                                                      ),

                                                    const SizedBox(height: 2),

                                                    Text(

                                                      formattedTime,

                                                      style: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.grey[600], fontSize: 10),

                                                    ),

                                                  ],

                                                ),

                                              ),

                                              if (_reactionIndex == listIndex && !isEditing)

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

                                                        children: reactions

                                                            .map((emoji) => GestureDetector(

                                                          onTap: () => _toggleReaction(listIndex, emoji),

                                                          child: Container(

                                                            margin: const EdgeInsets.symmetric(horizontal: 4),

                                                            padding: const EdgeInsets.all(4),

                                                            child: Text(emoji, style: const TextStyle(fontSize: 20)),

                                                          ),

                                                        ))

                                                            .toList(),

                                                      ),

                                                    ),

                                                  ),

                                                ),

                                              if (displayedReactions.isNotEmpty && !isEditing)

                                                Container(

                                                  margin: const EdgeInsets.only(top: 4),

                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),

                                                  decoration: BoxDecoration(

                                                    color: isDark ? Colors.grey[850] : Colors.white,

                                                    borderRadius: BorderRadius.circular(12),

                                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],

                                                  ),

                                                  child: Row(

                                                    mainAxisSize: MainAxisSize.min,

                                                    children: displayedReactions

                                                        .map((reaction) => GestureDetector(

                                                      onTap: () => _toggleReaction(listIndex, reaction['emoji']),

                                                      child: Padding(

                                                        padding: const EdgeInsets.symmetric(horizontal: 4),

                                                        child: Text(

                                                          reaction['count'] > 1 ? '${reaction['emoji']} ${reaction['count']}' : reaction['emoji'],

                                                          style: TextStyle(fontSize: 16, color: reaction['userReacted'] ? Colors.blue : null),

                                                        ),

                                                      ),

                                                    ))

                                                        .toList(),

                                                  ),

                                                ),

                                            ],

                                          ),

                                        ),

                                        Padding(

                                          padding: const EdgeInsets.only(left: 2, top: 8),

                                          child: PopupMenuButton<String>(

                                            icon: Icon(Icons.more_vert, size: 20, color: isDark ? Colors.white70 : Colors.grey[600]),

                                            onSelected: (option) => _handleMoreOptionSelected(option, listIndex),

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

                                                value: 'forward',

                                                child: AnimatedBuilder(

                                                  animation: _forwardAnimationController,

                                                  builder: (context, child) => Transform.scale(

                                                    scale: _forwardScaleAnimation.value,

                                                    child: Row(

                                                      children: [

                                                        Icon(Icons.forward, size: 20, color: isDark ? Colors.white70 : Colors.black87),

                                                        const SizedBox(width: 8),

                                                        Text('Transférer', style: GoogleFonts.poppins(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),

                                                      ],

                                                    ),

                                                  ),

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

                                        Padding(

                                          padding: const EdgeInsets.only(right: 2, top: 8),

                                          child: PopupMenuButton<String>(

                                            icon: Icon(Icons.more_vert, size: 20, color: isDark ? Colors.white70 : Colors.grey[600]),

                                            onSelected: (option) => _handleMoreOptionSelected(option, listIndex),

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

                                                value: 'forward',

                                                child: AnimatedBuilder(

                                                  animation: _forwardAnimationController,

                                                  builder: (context, child) => Transform.scale(

                                                    scale: _forwardScaleAnimation.value,

                                                    child: Row(

                                                      children: [

                                                        Icon(Icons.forward, size: 20, color: isDark ? Colors.white70 : Colors.black87),

                                                        const SizedBox(width: 8),

                                                        Text('Transférer', style: GoogleFonts.poppins(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),

                                                      ],

                                                    ),

                                                  ),

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

                                                  color: _highlightedIndex == listIndex && !isEditing

                                                      ? (isDark ? Colors.grey[700] : Colors.grey[300])

                                                      : (isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0)),

                                                  borderRadius: BorderRadius.circular(20).copyWith(bottomRight: const Radius.circular(0)),

                                                ),

                                                child: Column(

                                                  crossAxisAlignment: CrossAxisAlignment.end,

                                                  children: [

                                                    if (quotedWidget != null) quotedWidget,

                                                    if (isAttachment || message['file'] != null || (message['files'] != null && (message['files'] as List).isNotEmpty))

                                                          () {

                                                        developer.log('=== DÉBUT TRAITEMENT ATTACHMENT (message envoyé) ===', name: 'ChatPage.Media');

                                                        developer.log('Message complet: ${jsonEncode(message)}', name: 'ChatPage.Media');

                                                        developer.log('isAttachment: $isAttachment', name: 'ChatPage.Media');

                                                        developer.log('message[type]: ${message['type']}', name: 'ChatPage.Media');



                                                        // Essayer d'afficher un média (image, vidéo, audio)

                                                        final mediaWidget = _buildMediaWidgetFromMessage(message, isDark);



                                                        if (mediaWidget != null) {

                                                          developer.log('_buildMediaWidgetFromMessage a retourné un widget média', name: 'ChatPage.Media');

                                                        } else {

                                                          developer.log('_buildMediaWidgetFromMessage a retourné null, affichage format classique', name: 'ChatPage.Media');

                                                        }



                                                        if (mediaWidget != null) {

                                                          return mediaWidget;

                                                        }



                                                        // Sinon, afficher le format classique pour les autres types de fichiers

                                                        final List attachments =

                                                            (message['attachments'] as List?) ?? [];

                                                        final Map<String, dynamic>? att =

                                                        attachments.isNotEmpty

                                                            ? attachments.first

                                                        as Map<String, dynamic>?

                                                            : null;

                                                        final List<dynamic>? actions =

                                                        att?['actions'] as List<dynamic>?;

                                                        final String title =

                                                            att?['title']?.toString() ??

                                                                att?['description']?.toString() ??

                                                                'Pièce jointe';

                                                        final String description =

                                                            att?['text']?.toString() ??

                                                                'Pièce jointe envoyée';

                                                        final String? actionText =

                                                        (actions != null &&

                                                            actions.isNotEmpty)

                                                            ? actions[0]['text']

                                                            ?.toString()

                                                            : null;

                                                        final String? actionUrl =

                                                        (actions != null &&

                                                            actions.isNotEmpty)

                                                            ? actions[0]['url']

                                                            ?.toString()

                                                            : null;

                                                        final String? fileUrl =

                                                            att?['image_url']

                                                                ?.toString() ??

                                                                att?['title_link']

                                                                    ?.toString() ??

                                                                actionUrl ??

                                                                _getMediaUrlFromFile(message['file']);

                                                        return InkWell(

                                                          onTap: fileUrl != null

                                                              ? () =>

                                                              _openAttachmentUrl(

                                                                  fileUrl)

                                                              : null,

                                                          child: Column(

                                                            crossAxisAlignment:

                                                            CrossAxisAlignment

                                                                .start,

                                                            children: [

                                                              Text(

                                                                title,

                                                                style: GoogleFonts.poppins(

                                                                    color:

                                                                    Colors.white,

                                                                    fontSize: 15,

                                                                    fontWeight:

                                                                    FontWeight

                                                                        .bold),

                                                              ),

                                                              const SizedBox(

                                                                  height: 4),

                                                              Text(

                                                                description,

                                                                style: GoogleFonts.poppins(

                                                                    color: Colors

                                                                        .white70,

                                                                    fontSize: 13),

                                                              ),

                                                              if (actionUrl !=

                                                                  null &&

                                                                  actionText !=

                                                                      null) ...[

                                                                const SizedBox(

                                                                    height: 8),

                                                                ElevatedButton(

                                                                  onPressed: () =>

                                                                      _launchCall(

                                                                          url: actionUrl,

                                                                          isVideoCall:

                                                                          true),

                                                                  style: ElevatedButton

                                                                      .styleFrom(

                                                                    backgroundColor: isDark

                                                                        ? const Color(

                                                                        0xFF1A003D)

                                                                        : const Color(

                                                                        0xFF4A00E0),

                                                                    foregroundColor:

                                                                    Colors

                                                                        .white,

                                                                  ),

                                                                  child: Text(

                                                                    actionText,

                                                                    style: GoogleFonts.poppins(

                                                                        color: Colors

                                                                            .white,

                                                                        fontSize:

                                                                        14),

                                                                  ),

                                                                ),

                                                              ],

                                                            ],

                                                          ),

                                                        );

                                                      }()

                                                    else

                                                      Column(

                                                        crossAxisAlignment: CrossAxisAlignment.end,

                                                        children: [

                                                          LinkableText(

                                                            text: message['text'] ?? '',

                                                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),

                                                          ),

                                                          if (message['isEdited'] == true)

                                                            Padding(

                                                              padding: const EdgeInsets.only(top: 4.0),

                                                              child: Text(

                                                                'Édité',

                                                                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10, fontStyle: FontStyle.italic),

                                                              ),

                                                            ),

                                                        ],

                                                      ),

                                                    const SizedBox(height: 2),

                                                    Text(

                                                      formattedTime,

                                                      style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10),

                                                    ),

                                                  ],

                                                ),

                                              ),

                                              if (_reactionIndex == listIndex && !isEditing)

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

                                                        children: reactions

                                                            .map((emoji) => GestureDetector(

                                                          onTap: () => _toggleReaction(listIndex, emoji),

                                                          child: Container(

                                                            margin: const EdgeInsets.symmetric(horizontal: 4),

                                                            padding: const EdgeInsets.all(4),

                                                            child: Text(emoji, style: const TextStyle(fontSize: 20)),

                                                          ),

                                                        ))

                                                            .toList(),

                                                      ),

                                                    ),

                                                  ),

                                                ),

                                              if (displayedReactions.isNotEmpty && !isEditing)

                                                Container(

                                                  margin: const EdgeInsets.only(top: 4),

                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),

                                                  decoration: BoxDecoration(

                                                    color: isDark ? Colors.grey[850] : Colors.white,

                                                    borderRadius: BorderRadius.circular(12),

                                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],

                                                  ),

                                                  child: Row(

                                                    mainAxisSize: MainAxisSize.min,

                                                    children: displayedReactions

                                                        .map((reaction) => GestureDetector(

                                                      onTap: () => _toggleReaction(listIndex, reaction['emoji']),

                                                      child: Padding(

                                                        padding: const EdgeInsets.symmetric(horizontal: 4),

                                                        child: Text(

                                                          reaction['count'] > 1 ? '${reaction['emoji']} ${reaction['count']}' : reaction['emoji'],

                                                          style: TextStyle(fontSize: 16, color: reaction['userReacted'] ? Colors.blue : null),

                                                        ),

                                                      ),

                                                    ))

                                                        .toList(),

                                                  ),

                                                ),

                                            ],

                                          ),

                                        ),

                                        const SizedBox(width: 8),

                                      ],

                                    ],

                                  ),

                                ),

                              ),

                            if (isEditing && isMe) editWidget,

                          ],

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

                                  'Réponse à ${_replyingMessage?['name'] ?? _replyingMessage?['username'] ?? 'Inconnu'}',

                                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white : Colors.black87),

                                ),

                                Text(

                                  _replyingMessage?['text'] ?? '',

                                  maxLines: 1,

                                  overflow: TextOverflow.ellipsis,

                                  style: GoogleFonts.poppins(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey[600]),

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

                          icon: Icon(Icons.file_present, color: isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0)),

                          onPressed: _pickAndSendAttachment,

                        ),

                        IconButton(

                          icon: Icon(
                            _isRecording ? Icons.stop : Icons.mic,
                            color: _isRecording
                                ? Colors.red
                                : (isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0)),
                          ),

                          onPressed: _handleMicPressed,

                        ),

                        Expanded(

                          child: Container(

                            margin: const EdgeInsets.symmetric(horizontal: 8),

                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),

                            decoration: BoxDecoration(

                              color: isDark ? Colors.grey[800] : Colors.grey[100],

                              borderRadius: BorderRadius.circular(25),

                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],

                            ),

                            child: TextField(

                              controller: _messageController,

                              focusNode: _messageFocusNode,

                              enabled: _editingMessageId == null,

                              decoration: InputDecoration(

                                hintText: _editingMessageId != null ? 'Annuler l\'édition et taper un nouveau message...' : 'Aa',

                                border: InputBorder.none,

                                hintStyle: GoogleFonts.poppins(color: isDark ? Colors.white54 : Colors.grey[600]),

                              ),

                              style: GoogleFonts.poppins(color: isDark ? Colors.white : Colors.black87),

                              onSubmitted: (_) => _sendMessage(),

                            ),

                          ),

                        ),

                        CircleAvatar(

                          radius: 22,

                          backgroundColor: isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0),

                          child: IconButton(

                            icon: const Icon(Icons.send, color: Colors.white),

                            onPressed: _editingMessageId == null ? _sendMessage : null,

                          ),

                        ),

                      ],

                    ),

                  ),

                ],

              ),

              if (_showScrollToBottom)

                Positioned(

                  bottom: 90, // Au-dessus de la barre d'entrée (ajustez si nécessaire)

                  right: 20,

                  child: AnimatedBuilder(

                    animation: _animationController,

                    builder: (context, child) {

                      return FadeTransition(

                        opacity: _fadeAnimation,

                        child: SlideTransition(

                          position: _slideAnimation,

                          child: child,

                        ),

                      );

                    },

                    child: FloatingActionButton(

                      mini: true,

                      backgroundColor: isDark ? const Color(0xFF1A003D) : const Color(0xFF4A00E0),

                      onPressed: () {

                        _scrollController.animateTo(

                          0,

                          duration: const Duration(milliseconds: 300),

                          curve: Curves.easeInOut,

                        );

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

// Widget pour afficher un lecteur audio dans le chat

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
        final uri = Uri.parse(rawUrl);

        // Téléchargement direct de l'URL protégée.
        // Sur iOS, AVPlayer peut avoir des problèmes avec certains formats M4A/MP3 depuis des URLs distantes.
        // On télécharge toujours le fichier sur iOS avant de le lire pour garantir la compatibilité.
        // Sur Android, on télécharge aussi pour les URLs Rocket.Chat, sinon on utilise setSourceUrl.
        final shouldDownload = io.Platform.isIOS ||
            rawUrl.contains('message.unistudious.com/file-upload/') ||
            rawUrl.contains('/file-upload/');

        if (shouldDownload) {
          developer.log('Téléchargement audio pour iOS/Android: $rawUrl', name: 'AudioPlayerWidget');
          final headers = <String, String>{};

          // Vérifier si l'URL contient déjà les tokens Rocket.Chat
          final hasRcToken = uri.queryParameters.containsKey('rc_token');
          final hasRcUid = uri.queryParameters.containsKey('rc_uid');

          // Pour les URLs Rocket.Chat avec rc_token/rc_uid, ne pas ajouter de header Authorization
          // Ces tokens dans l'URL sont suffisants pour l'authentification Rocket.Chat
          // Ajouter un header Bearer peut causer un conflit et retourner 403
          if (!hasRcToken || !hasRcUid) {
            final prefs = await SharedPreferences.getInstance();
            final token = prefs.getString('auth_token') ?? '';
            if (token.isNotEmpty) {
              headers['Authorization'] = 'Bearer $token';
            }
          } else {
            developer.log(
              'URL contient déjà les tokens Rocket.Chat, pas de header Authorization ajouté',
              name: 'AudioPlayerWidget',
            );
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
            developer.log(
              'ERREUR: Tentative d\'utiliser setSourceUrl sur iOS pour: $rawUrl',
              name: 'AudioPlayerWidget',
            );
            throw Exception(
              'iOS ne supporte pas setSourceUrl pour cette URL. Le téléchargement devrait avoir été effectué.',
            );
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
        String userFriendly = 'Erreur lors du chargement de l\'audio';
        final errorText2 = e.toString();
        if (errorText2.contains('HTTP 403') || errorText2.contains('403')) {
          userFriendly =
              'Impossible de lire ce fichier audio pour le moment. Réessayez plus tard ou contactez le support.';
        } else if (errorText2.contains('HTTP') || errorText2.contains('timeout')) {
          userFriendly =
              'Erreur de téléchargement du fichier audio. Vérifiez votre connexion internet.';
        }

        setState(() {
          _errorMessage = userFriendly;
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
    // Si erreur, afficher le message d'erreur
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
        color: widget.isDark ? Colors.grey[850] : Colors.grey[300],
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
                if (_isInitialized && _duration != Duration.zero)
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

    developer.log('_ImageViewerScreen.build: imageUrl = "$imageUrl"', name: 'ChatPage.Media');

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

    // Vérifier si l'URL a des tokens Rocket.Chat

    final uri = Uri.parse(url);

    final hasRcToken = uri.queryParameters.containsKey('rc_token');

    final hasRcUid = uri.queryParameters.containsKey('rc_uid');

    if (hasRcToken && hasRcUid) {

      // Utiliser CachedNetworkImage pour les URLs Rocket.Chat avec tokens

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

              name: 'ChatPage.Media',

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

                  const SizedBox(height: 8),

                  Padding(

                    padding: const EdgeInsets.symmetric(horizontal: 16.0),

                    child: Text(

                      'URL: $url',

                      style: GoogleFonts.poppins(

                        color: Colors.white70,

                        fontSize: 12,

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

      return FutureBuilder<Uint8List?>(

        future: fetchProtectedImage(url),

        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {

            return const Center(

              child: CircularProgressIndicator(color: Colors.white),

            );

          }

          if (!snapshot.hasData || snapshot.data == null) {

            developer.log(

              '_ImageViewerScreen: impossible de charger l\'image en plein écran',

              name: 'ChatPage.Media',

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

                  const SizedBox(height: 8),

                  Padding(

                    padding: const EdgeInsets.symmetric(horizontal: 16.0),

                    child: Text(

                      'URL: $url',

                      style: GoogleFonts.poppins(

                        color: Colors.white70,

                        fontSize: 12,

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

  // On récupère les méthodes du parent via widget
  String _getFullUrl(String? url) => (context.findAncestorStateOfType<_ChatPageState>())!._getFullUrl(url);
  Future<void> _openVideoInBrowser(String url) => (context.findAncestorStateOfType<_ChatPageState>())!._openVideoInBrowser(url);

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
          developer.log('Error loading PDF: $error', name: 'ChatPage.PDF');
          SnackBarHelper.showError(context, 'Erreur lors du chargement du PDF: $error');
        },
        onRender: (pages) {
          developer.log('PDF rendered with $pages pages', name: 'ChatPage.PDF');
        },
        onPageError: (page, error) {
          developer.log('Error on page $page: $error', name: 'ChatPage.PDF');
          SnackBarHelper.showError(context, 'Erreur sur la page $page: $error');
        },
      ),
    );
  }
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
          name: 'ChatPage.Media',
        );
        return null;
      }

      final success = json['success'] == true;
      final fileBase64 = json['fileBase64'] as String?;
      final serverFileName = (json['fileName'] as String?) ?? fileName;

      if (!success || fileBase64 == null || fileBase64.isEmpty) {
        developer.log(
          'read/file-audio a répondu sans fichier utilisable: success=$success, fileBase64 length=${fileBase64?.length ?? 0}',
          name: 'ChatPage.Media',
        );
        return null;
      }

      Uint8List bytes;
      try {
        bytes = base64Decode(fileBase64);
      } catch (e) {
        developer.log(
          'Erreur de décodage base64 pour read/file-audio: $e',
          name: 'ChatPage.Media',
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
          name: 'ChatPage.Media',
        );
        return null;
      }
      
      final fileSize = await tempFile.length();
      if (fileSize == 0) {
        developer.log(
          'Le fichier temporaire est vide (0 bytes): ${tempFile.path}',
          name: 'ChatPage.Media',
        );
        return null;
      }
      
      if (fileSize != bytes.length) {
        developer.log(
          'ATTENTION: Taille du fichier sur disque ($fileSize) différente de la taille décodée (${bytes.length})',
          name: 'ChatPage.Media',
        );
      }
      
      // Vérifier les premiers bytes pour s'assurer que c'est un fichier audio valide (M4A commence par certains bytes)
      if (bytes.length >= 4) {
        final firstBytes = bytes.take(4).toList();
        // M4A/MP4 commence généralement par des bytes spécifiques (ftyp box à l'offset 4)
        // Vérifier au moins que ce n'est pas du texte/HTML
        final textStart = String.fromCharCodes(bytes.take(100));
        if (textStart.toLowerCase().contains('<html') || 
            textStart.toLowerCase().contains('<!doctype') ||
            textStart.toLowerCase().contains('error') ||
            textStart.toLowerCase().contains('{"error')) {
          developer.log(
            'Le serveur a retourné du HTML/JSON d\'erreur au lieu d\'un fichier audio',
            name: 'ChatPage.Media',
          );
          return null;
        }
      }
      
      developer.log(
        'Fichier audio temporaire créé via read/file-audio : ${tempFile.path} (${fileSize} bytes)',
        name: 'ChatPage.Media',
      );
      return tempFile.path;
    } else {
      developer.log(
        'Erreur read/file-audio : $statusCode $rawBody',
        name: 'ChatPage.Media',
      );
      return null;
    }
  } catch (e, s) {
    developer.log(
      'Exception dans _getPlayableFileUrl: $e',
      name: 'ChatPage.Media',
      error: e,
      stackTrace: s,
    );
    return null;
  }
}
