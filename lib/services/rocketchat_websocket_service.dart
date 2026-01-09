import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class RocketChatWebSocketService {
  static const String wsUrl = 'wss://message.unistudious.com/websocket';
  static const String httpBase = 'https://message.unistudious.com';

  WebSocketChannel? _channel;
  bool _isReady = false;
  bool _isLoggedIn = false;
  String? _authToken;
  String? _userId;
  String? _currentRoomId;

  final Map<String, String> _subscriptions = {};
  final Map<String, dynamic> _messagesCache = {};

  // Stream controllers pour les événements
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _deleteMessageController = StreamController<String>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  // Getters pour les streams
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<String> get deleteMessageStream => _deleteMessageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  bool get isConnected => _channel != null && _isReady && _isLoggedIn;

  // Singleton pattern
  static final RocketChatWebSocketService _instance = RocketChatWebSocketService._internal();
  factory RocketChatWebSocketService() => _instance;
  RocketChatWebSocketService._internal();

  /// Récupère les credentials RocketChat depuis l'API
  Future<Map<String, String>?> fetchRocketChatCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';

      if (token.isEmpty) {
        developer.log('No auth token found', name: 'RocketChatWS');
        return null;
      }

      final endpoints = [
        'https://www.unistudious.com/api/chat/get-rocketchat-credentials',
        'https://www.unistudious.com/api/chat/rocketchat-auth',
        'https://www.unistudious.com/api/chat/auth-token',
      ];

      for (final endpoint in endpoints) {
        try {
          final response = await http.post(
            Uri.parse(endpoint),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          ).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);

            String? rcToken = data['rcToken'] ?? data['token'] ?? data['rc_token'] ?? data['data']?['authToken'];
            String? rcUserId = data['rcUserId'] ?? data['userId'] ?? data['rc_uid'] ?? data['user_id'] ?? data['data']?['userId'];

            if (rcToken != null && rcUserId != null) {
              developer.log('Successfully fetched RocketChat credentials from $endpoint', name: 'RocketChatWS');
              return {'token': rcToken, 'userId': rcUserId};
            }
          }
        } catch (e) {
          developer.log('Error trying endpoint $endpoint: $e', name: 'RocketChatWS');
        }
      }

      developer.log('Failed to fetch RocketChat credentials from any endpoint', name: 'RocketChatWS');
      return null;
    } catch (e, stackTrace) {
      developer.log('Error fetching RocketChat credentials: $e',
          name: 'RocketChatWS', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  void setCredentials(String token, String userId) {
    _authToken = token;
    _userId = userId;
  }

  Future<void> initialize({String? roomId}) async {
    if (_channel != null && isConnected) {
      developer.log('WebSocket already connected', name: 'RocketChatWS');
      if (roomId != null && roomId != _currentRoomId) {
        await subscribeToRoom(roomId);
      }
      return;
    }

    final credentials = await fetchRocketChatCredentials();
    if (credentials == null) {
      developer.log('Failed to get RocketChat credentials', name: 'RocketChatWS');
      if (!_connectionController.isClosed) {
        if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
      }
      return;
    }

    _authToken = credentials['token'];
    _userId = credentials['userId'];
    _currentRoomId = roomId;

    await _connect();
  }

  Future<void> _connect() async {
    try {
      _channel?.sink.close();
      _channel = null;
      _isReady = false;
      _isLoggedIn = false;
      _subscriptions.clear();

      developer.log('Connecting to RocketChat WebSocket...', name: 'RocketChatWS');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleClose,
      );

      _send({
        'msg': 'connect',
        'version': '1',
        'support': ['1', 'pre2', 'pre1'],
      });

    } catch (e, stackTrace) {
      developer.log('Error connecting WebSocket: $e',
          name: 'RocketChatWS', error: e, stackTrace: stackTrace);
      if (!_connectionController.isClosed) {
        if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
      }

      Future.delayed(const Duration(seconds: 5), () {
        if (!isConnected) _connect();
      });
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      // Log tous les messages pour déboguer
      if (data['msg'] == 'changed' || data['collection']?.toString().contains('message') == true || 
          data['collection']?.toString().contains('room') == true) {
        developer.log('WebSocket message received: msg=${data['msg']}, collection=${data['collection']}, fields=${data['fields']}', name: 'RocketChatWS');
      }

      if (data['msg'] == 'ping') {
        _send({'msg': 'pong'});
        return;
      }

      if (data['msg'] == 'connected') {
        developer.log('DDP connected, session: ${data['session']}', name: 'RocketChatWS');
        _login();
        return;
      }

      if (data['msg'] == 'result' && data['id']?.toString().startsWith('login-') == true) {
        if (data['error'] != null) {
          developer.log('Login failed: ${data['error']}', name: 'RocketChatWS');
          if (!_connectionController.isClosed) {
            if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
          }
          return;
        }

        _isLoggedIn = true;
        _isReady = true;
        developer.log('Logged in successfully as $_userId', name: 'RocketChatWS');
        if (!_connectionController.isClosed) {
          if (!_connectionController.isClosed) {
          _connectionController.add(true);
        }
        }

        // Abonnements globaux
        _subscribeToAllRoomMessages();
        _subscribeToUserNotifications();

        if (_currentRoomId != null) {
          _subscribeToRoomNotifications(_currentRoomId!);
        }

        return;
      }

      // Messages de room - nouveaux messages et mises à jour (réactions, éditions, réponses)
      // IMPORTANT : Capturer TOUS les événements possibles
      if (data['msg'] == 'added' || data['msg'] == 'changed' || data['msg'] == 'updated') {
        String? collection = data['collection']?.toString();
        final isUpdate = data['msg'] == 'changed' || data['msg'] == 'updated';
        
        // Nouveaux messages ou mises à jour via stream-room-messages
        if (collection == 'stream-room-messages' || collection?.contains('room-messages') == true) {
          final fields = data['fields'];
          dynamic args = fields?['args'] ?? fields;
          
          // Format avec args comme liste
          if (args is List && args.isNotEmpty) {
            for (final item in args) {
              if (item is Map<String, dynamic> && item['_id'] != null) {
                developer.log('WebSocket ${isUpdate ? "UPDATE" : "NEW"} message from stream-room-messages (list): ${item['_id']}', name: 'RocketChatWS');
                _handleIncomingMessage(item, isUpdate: isUpdate);
              }
            }
          } 
          // Format avec args comme Map directement
          else if (args is Map<String, dynamic> && args['_id'] != null) {
            developer.log('WebSocket ${isUpdate ? "UPDATE" : "NEW"} message from stream-room-messages (map): ${args['_id']}', name: 'RocketChatWS');
            _handleIncomingMessage(args, isUpdate: isUpdate);
          }
          // Format avec fields directement (pour les changements)
          else if (fields is Map<String, dynamic> && fields['_id'] != null) {
            developer.log('WebSocket UPDATE message from stream-room-messages (fields): ${fields['_id']}', name: 'RocketChatWS');
            _handleIncomingMessage(fields, isUpdate: true);
          }
          // Vérifier aussi dans les champs modifiés (pour les événements changed)
          else if (isUpdate && fields is Map) {
            // Chercher un message dans les champs modifiés
            for (final key in fields.keys) {
              final value = fields[key];
              if (value is Map<String, dynamic> && value['_id'] != null) {
                developer.log('WebSocket UPDATE message found in field $key: ${value['_id']}', name: 'RocketChatWS');
                _handleIncomingMessage(value, isUpdate: true);
                break;
              } else if (value is List) {
                for (final item in value) {
                  if (item is Map<String, dynamic> && item['_id'] != null) {
                    developer.log('WebSocket UPDATE message found in field $key (list): ${item['_id']}', name: 'RocketChatWS');
                    _handleIncomingMessage(item, isUpdate: true);
                  }
                }
              }
            }
          }
        }
        
        // IMPORTANT : Les modifications peuvent aussi arriver via la collection 'messages' directement
        // RocketChat envoie parfois les modifications via cette collection avec msg: 'changed'
        if (collection == 'messages' || collection?.startsWith('messages') == true) {
          final fields = data['fields'];
          if (fields is Map<String, dynamic> && fields['_id'] != null) {
            developer.log('WebSocket UPDATE message from messages collection: ${fields['_id']}', name: 'RocketChatWS');
            _handleIncomingMessage(fields, isUpdate: true);
          } else if (fields is Map && fields.containsKey('_id')) {
            developer.log('WebSocket UPDATE message from messages collection (alt): ${fields['_id']}', name: 'RocketChatWS');
            _handleIncomingMessage(Map<String, dynamic>.from(fields), isUpdate: true);
          }
        }
        
        // Mises à jour de messages via stream-notify-room (réactions, éditions, suppressions)
        if (collection == 'stream-notify-room' || collection?.contains('notify-room') == true) {
          final eventName = data['fields']?['eventName']?.toString() ?? '';
          final args = data['fields']?['args'] ?? [];
          final fields = data['fields'];
          
          developer.log('WebSocket stream-notify-room event: $eventName, args=$args', name: 'RocketChatWS');
          
          // Suppression de message
          if (eventName.endsWith('/deleteMessage') || eventName.contains('delete') || 
              eventName.contains('Delete')) {
            for (final arg in args) {
              if (arg is Map && arg['_id'] != null) {
                final msgId = arg['_id'].toString();
                developer.log('WebSocket delete message: $msgId', name: 'RocketChatWS');
                _messagesCache.remove(msgId);
                if (!_deleteMessageController.isClosed) {
                  _deleteMessageController.add(msgId);
                }
              }
            }
            // Aussi vérifier dans les fields directement
            if (fields is Map && fields['_id'] != null) {
              final msgId = fields['_id'].toString();
              developer.log('WebSocket delete message (from fields): $msgId', name: 'RocketChatWS');
              _messagesCache.remove(msgId);
              if (!_deleteMessageController.isClosed) {
                _deleteMessageController.add(msgId);
              }
            }
          }
          // Réactions sur messages
          else if (eventName.endsWith('/messageReaction') || 
                   eventName.contains('reaction') || 
                   eventName.contains('Reaction') ||
                   eventName.contains('setReaction')) {
            developer.log('WebSocket reaction event detected: $eventName', name: 'RocketChatWS');
            for (final arg in args) {
              if (arg is Map<String, dynamic>) {
                // Les réactions peuvent être dans différents formats
                if (arg['_id'] != null) {
                  _handleIncomingMessage(arg, isUpdate: true);
                } else if (arg['message'] != null && arg['message'] is Map) {
                  _handleIncomingMessage(arg['message'], isUpdate: true);
                } else if (arg['messageId'] != null) {
                  // Format alternatif avec messageId
                  final messageId = arg['messageId'].toString();
                  if (_messagesCache.containsKey(messageId)) {
                    final existing = Map<String, dynamic>.from(_messagesCache[messageId]!);
                    existing['reactions'] = arg['reactions'] ?? existing['reactions'];
                    _handleIncomingMessage(existing, isUpdate: true);
                  }
                }
              }
            }
            // Aussi vérifier dans les fields directement
            if (fields is Map<String, dynamic> && fields['_id'] != null) {
              _handleIncomingMessage(fields, isUpdate: true);
            }
          }
          // Mises à jour de messages (éditions, modifications)
          else if (eventName.contains('message') || 
                   eventName.contains('update') || 
                   eventName.contains('edit') ||
                   eventName.contains('changed') ||
                   eventName.contains('Update') ||
                   eventName.contains('Edit')) {
            developer.log('WebSocket message update event detected: $eventName', name: 'RocketChatWS');
            for (final arg in args) {
              if (arg is Map<String, dynamic>) {
                if (arg['_id'] != null) {
                  _handleIncomingMessage(arg, isUpdate: true);
                } else if (arg['message'] != null && arg['message'] is Map) {
                  _handleIncomingMessage(arg['message'], isUpdate: true);
                } else if (arg['messageId'] != null) {
                  // Format alternatif avec messageId
                  final messageId = arg['messageId'].toString();
                  if (_messagesCache.containsKey(messageId)) {
                    final existing = Map<String, dynamic>.from(_messagesCache[messageId]!);
                    // Fusionner les modifications
                    existing.addAll(arg);
                    _handleIncomingMessage(existing, isUpdate: true);
                  }
                }
              }
            }
            // Aussi vérifier dans les fields directement
            if (fields is Map<String, dynamic> && fields['_id'] != null) {
              _handleIncomingMessage(fields, isUpdate: true);
            }
          }
        }
        
        // Détection générique : si c'est un événement 'changed' avec un _id, c'est probablement une mise à jour
        if (isUpdate && data['id'] != null) {
          final messageId = data['id'].toString();
          if (_messagesCache.containsKey(messageId)) {
            developer.log('WebSocket generic update detected for message: $messageId', name: 'RocketChatWS');
            final existing = Map<String, dynamic>.from(_messagesCache[messageId]!);
            final fields = data['fields'];
            if (fields is Map) {
              existing.addAll(Map<String, dynamic>.from(fields));
              _handleIncomingMessage(existing, isUpdate: true);
            }
          }
        }
      }

    } catch (e, stackTrace) {
      developer.log('Error in _handleMessage: $e', name: 'RocketChatWS', error: e, stackTrace: stackTrace);
    }
  }

  void _login() {
    if (_authToken == null || _userId == null) return;

    final loginId = 'login-${DateTime.now().millisecondsSinceEpoch}';
    _send({
      'msg': 'method',
      'method': 'login',
      'id': loginId,
      'params': [{'resume': _authToken}],
    });
  }

  // CORRECT : s'abonner à TOUS les messages des rooms (pas juste __my_messages__)
  void _subscribeToAllRoomMessages() {
    if (_subscriptions.containsKey('stream-room-messages')) return;

    final subId = 'sub-room-msgs-${DateTime.now().millisecondsSinceEpoch}';
    _subscriptions['stream-room-messages'] = subId;

    _send({
      'msg': 'sub',
      'id': subId,
      'name': 'stream-room-messages',
      'params': ['', false], // '' = toutes les rooms
    });
  }

  void _subscribeToUserNotifications() {
    final subId = 'sub-user-${DateTime.now().millisecondsSinceEpoch}';
    _subscriptions['stream-notify-user'] = subId;

    _send({
      'msg': 'sub',
      'id': subId,
      'name': 'stream-notify-user',
      'params': ['$_userId/rooms-changed', false],
    });
  }

  void _subscribeToRoomNotifications(String roomId) {
    // Abonnement pour les suppressions de messages
    final deleteKey = 'delete-$roomId';
    if (!_subscriptions.containsKey(deleteKey)) {
      final subId = 'sub-del-$roomId-${DateTime.now().millisecondsSinceEpoch}';
      _subscriptions[deleteKey] = subId;
      _send({
        'msg': 'sub',
        'id': subId,
        'name': 'stream-notify-room',
        'params': ['$roomId/deleteMessage', false],
      });
    }

    // Abonnement pour les réactions sur messages
    final reactionKey = 'reaction-$roomId';
    if (!_subscriptions.containsKey(reactionKey)) {
      final subId = 'sub-reaction-$roomId-${DateTime.now().millisecondsSinceEpoch}';
      _subscriptions[reactionKey] = subId;
      _send({
        'msg': 'sub',
        'id': subId,
        'name': 'stream-notify-room',
        'params': ['$roomId/messageReaction', false],
      });
    }

    // Abonnement pour les mises à jour de messages (éditions, etc.)
    final updateKey = 'update-$roomId';
    if (!_subscriptions.containsKey(updateKey)) {
      final subId = 'sub-update-$roomId-${DateTime.now().millisecondsSinceEpoch}';
      _subscriptions[updateKey] = subId;
      _send({
        'msg': 'sub',
        'id': subId,
        'name': 'stream-notify-room',
        'params': ['$roomId/updatedMessage', false],
      });
    }

    // IMPORTANT : S'abonner à la collection 'messages' pour recevoir les événements 'changed' (modifications)
    // RocketChat envoie les modifications via la collection 'messages' avec msg: 'changed'
    final messagesKey = 'messages-$roomId';
    if (!_subscriptions.containsKey(messagesKey)) {
      final subId = 'sub-msgs-$roomId-${DateTime.now().millisecondsSinceEpoch}';
      _subscriptions[messagesKey] = subId;
      _send({
        'msg': 'sub',
        'id': subId,
        'name': 'stream-room-messages',
        'params': [roomId, false], // RoomId spécifique pour recevoir les changements
      });
      developer.log('Subscribed to messages collection for room: $roomId', name: 'RocketChatWS');
    }
  }

  Future<void> subscribeToRoom(String roomId) async {
    _currentRoomId = roomId;
    if (isConnected) {
      _subscribeToRoomNotifications(roomId);
    } else {
      await initialize(roomId: roomId);
    }
  }

  void _handleIncomingMessage(Map<String, dynamic> payload, {bool isUpdate = false}) {
    try {
      final rid = payload['rid']?.toString();
      if (rid == null) return;

      if (_currentRoomId == null) {
        _currentRoomId = rid;
        _subscribeToRoomNotifications(rid);
      }

      final messageId = payload['_id']?.toString();
      if (messageId == null) return;

      // Vérifier si le message existe déjà dans le cache
      final messageExists = _messagesCache.containsKey(messageId);
      
      // Si le message existe déjà OU si c'est marqué comme mise à jour, c'est une mise à jour
      // Aussi vérifier si le payload contient editedAt (indique une modification)
      final hasEditedAt = payload['editedAt'] != null || payload['_updatedAt'] != null;
      final shouldTreatAsUpdate = isUpdate || messageExists || hasEditedAt;

      // Récupérer le message existant du cache pour préserver les données
      Map<String, dynamic>? existingMessage;
      if (shouldTreatAsUpdate && _messagesCache.containsKey(messageId)) {
        existingMessage = Map<String, dynamic>.from(_messagesCache[messageId]);
        developer.log('Message exists in cache, treating as update: $messageId', name: 'RocketChatWS');
      }

      final uiMessage = _mapRocketChatMessageToUI(payload, existingMessage: existingMessage);
      uiMessage['rid'] = rid;
      uiMessage['roomId'] = rid;
      uiMessage['isUpdate'] = shouldTreatAsUpdate; // Flag pour indiquer que c'est une mise à jour

      _messagesCache[messageId] = uiMessage;
      if (!_messageController.isClosed) {
        _messageController.add(uiMessage);
      }

      developer.log('WebSocket message ${shouldTreatAsUpdate ? "UPDATED" : "ADDED"}: $messageId (hasEditedAt=$hasEditedAt, messageExists=$messageExists, isUpdate=$isUpdate)', name: 'RocketChatWS');

    } catch (e, stackTrace) {
      developer.log('Error handling incoming message: $e', error: e, stackTrace: stackTrace);
    }
  }

  Map<String, dynamic> _mapRocketChatMessageToUI(Map<String, dynamic> m, {Map<String, dynamic>? existingMessage}) {
    final u = m['u'] as Map<String, dynamic>?;
    final authorName = u?['name'] ?? u?['username'] ?? existingMessage?['name'] ?? 'Unknown';
    final authorUsername = u?['username'] ?? existingMessage?['username'] ?? '';
    final avatar = authorUsername.isNotEmpty
        ? '$httpBase/avatar/${Uri.encodeComponent(authorUsername)}'
        : existingMessage?['avatar'] ?? '/assets/admin/images/defult-admin.png';

    String text = m['msg']?.toString().trim() ?? existingMessage?['text'] ?? '';
    if (text.isEmpty && m['attachments'] is List && (m['attachments'] as List).isNotEmpty) {
      text = m['attachments'][0]['title'] ?? 'Attachment';
    } else if (text.isEmpty && m['file'] != null) {
      text = m['file']['name'] ?? 'File';
    }

    String type = existingMessage?['type'] ?? 'text';
    Map<String, dynamic>? file = existingMessage?['file'];

    if (m['file'] != null) {
      type = 'file';
      final f = m['file'];
      final fileType = f['type']?.toString() ?? '';
      String category = fileType.startsWith('image/') ? 'image' :
      fileType.startsWith('video/') ? 'video' :
      fileType.startsWith('audio/') ? 'audio' : 'other';

      file = {
        'category': category,
        'name': f['name'] ?? 'File',
        'url': _getRocketChatFileUrl(f, _userId!, _authToken!),
        'type': fileType,
        'size': f['size'] ?? 0,
      };
    }

    // Timestamp
    int timestamp = DateTime.now().millisecondsSinceEpoch;
    final ts = m['ts'];
    if (ts is Map && ts['\$date'] is int) {
      timestamp = ts['\$date'];
    } else if (ts is int) {
      timestamp = ts;
    } else if (ts is String) {
      try {
        timestamp = DateTime.parse(ts).millisecondsSinceEpoch;
      } catch (e) {
        // Garder le timestamp existant si erreur de parsing
        if (existingMessage?['timestamp'] != null) {
          try {
            timestamp = DateTime.parse(existingMessage!['timestamp']).millisecondsSinceEpoch;
          } catch (_) {}
        }
      }
    } else if (existingMessage?['timestamp'] != null) {
      try {
        timestamp = DateTime.parse(existingMessage!['timestamp']).millisecondsSinceEpoch;
      } catch (_) {}
    }

    // EditedAt - important pour détecter les modifications
    int? editedAt;
    final edited = m['editedAt'];
    if (edited != null) {
      if (edited is Map && edited['\$date'] is int) {
        editedAt = edited['\$date'];
      } else if (edited is int) {
        editedAt = edited;
      } else if (edited is String) {
        try {
          editedAt = DateTime.parse(edited).millisecondsSinceEpoch;
        } catch (_) {}
      }
    } else if (existingMessage?['editedAt'] != null) {
      try {
        editedAt = DateTime.parse(existingMessage!['editedAt']).millisecondsSinceEpoch;
      } catch (_) {}
    }

    // Réactions - fusionner intelligemment avec les réactions existantes
    Map<String, dynamic> reactions = {};
    
    // D'abord, récupérer les réactions existantes
    if (existingMessage?['reactions'] != null && existingMessage!['reactions'] is Map) {
      reactions = Map<String, dynamic>.from(existingMessage!['reactions']);
    }
    
    // Ensuite, fusionner avec les nouvelles réactions (les nouvelles écrasent les anciennes)
    if (m['reactions'] != null && m['reactions'] is Map) {
      final newReactions = Map<String, dynamic>.from(m['reactions']);
      // Fusionner les réactions : les nouvelles remplacent les anciennes pour chaque emoji
      reactions.addAll(newReactions);
      
      // Nettoyer les réactions vides
      reactions.removeWhere((key, value) => 
        value == null || 
        (value is Map && (value['usernames'] == null || (value['usernames'] as List).isEmpty))
      );
    }

    // ReplyTo - préserver les données existantes si disponibles
    Map<String, dynamic>? replyTo;
    if (m['tmid'] != null) {
      final tmid = m['tmid'].toString();
      final parent = _messagesCache[tmid];
      if (parent != null) {
        replyTo = {
          'messageId': tmid,
          'id': tmid,
          'username': parent['username'] ?? 'Unknown',
          'name': parent['name'] ?? parent['username'] ?? 'Unknown',
          'text': parent['text'] ?? ''
        };
      } else if (existingMessage?['replyTo'] != null) {
        // Préserver les données existantes si disponibles
        replyTo = Map<String, dynamic>.from(existingMessage!['replyTo']);
        // S'assurer que messageId est défini
        if (!replyTo!.containsKey('messageId') && replyTo.containsKey('id')) {
          replyTo['messageId'] = replyTo['id'];
        }
      } else {
        replyTo = {
          'messageId': tmid,
          'id': tmid,
          'username': 'Unknown',
          'name': 'Unknown',
          'text': '(Loading...)'
        };
      }
    } else if (existingMessage?['replyTo'] != null) {
      replyTo = Map<String, dynamic>.from(existingMessage!['replyTo']);
      // S'assurer que messageId est défini
      if (!replyTo!.containsKey('messageId') && replyTo.containsKey('id')) {
        replyTo['messageId'] = replyTo['id'];
      }
    }

    return {
      'id': m['_id'],
      'isSent': (u?['_id'] ?? existingMessage?['isSent'] ?? '') == _userId,
      'text': text,
      'name': authorName,
      'username': authorUsername,
      'avatar': avatar,
      'timestamp': DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String(),
      'editedAt': editedAt != null ? DateTime.fromMillisecondsSinceEpoch(editedAt).toIso8601String() : null,
      'isEdited': editedAt != null,
      'type': type,
      'file': file,
      'attachments': m['attachments'] ?? existingMessage?['attachments'] ?? [],
      'replyTo': replyTo,
      'reactions': reactions,
    };
  }

  String _getRocketChatFileUrl(Map<String, dynamic> file, String userId, String authToken) {
    final id = file['_id'];
    final name = file['name'];
    if (id == null || name == null) return '#';
    return '$httpBase/file-upload/$id/${Uri.encodeComponent(name)}?rc_uid=$userId&rc_token=$authToken';
  }

  void _handleError(dynamic error) {
    developer.log('WebSocket error: $error', name: 'RocketChatWS');
    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
  }

  void _handleClose() {
    developer.log('WebSocket closed, reconnecting in 5s...', name: 'RocketChatWS');
    _isReady = false;
    _isLoggedIn = false;
    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }

    Future.delayed(const Duration(seconds: 5), () {
      if (!isConnected) {
        initialize(roomId: _currentRoomId);
      }
    });
  }

  void _send(Map<String, dynamic> message) {
    if (_channel?.sink == null) return;
    try {
      final json = jsonEncode(message);
      _channel!.sink.add(json);
    } catch (e) {
      developer.log('Failed to send message: $e', name: 'RocketChatWS');
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _isReady = false;
    _isLoggedIn = false;
    _subscriptions.clear();
    // Vérifier si le contrôleur n'est pas fermé avant d'ajouter un événement
    if (!_connectionController.isClosed) {
      if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
    }
  }

  void dispose() {
    // Fermer d'abord les contrôleurs pour éviter d'ajouter des événements après fermeture
    if (!_messageController.isClosed) {
      _messageController.close();
    }
    if (!_deleteMessageController.isClosed) {
      _deleteMessageController.close();
    }
    if (!_connectionController.isClosed) {
      _connectionController.close();
    }
    // Appeler disconnect après avoir fermé les contrôleurs
    _channel?.sink.close();
    _channel = null;
    _isReady = false;
    _isLoggedIn = false;
    _subscriptions.clear();
  }
}