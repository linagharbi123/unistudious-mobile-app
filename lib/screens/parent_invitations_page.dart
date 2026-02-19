import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../widgets/sidebar.dart';
import '../widgets/notification_icon_button.dart';
import '../providers/auth_provider.dart';
import '../utils/snackbar_helper.dart';

class ParentInvitationsPage extends StatefulWidget {
  const ParentInvitationsPage({super.key});

  @override
  State<ParentInvitationsPage> createState() => _ParentInvitationsPageState();
}

class _ParentInvitationsPageState extends State<ParentInvitationsPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSending = false;
  bool _isLoading = false;

  List<Map<String, dynamic>> _pendingInvitations = [];
  List<Map<String, dynamic>> _receivedInvitations = [];
  List<Map<String, dynamic>> _requests = [];
  bool _isLoadingRequests = false;
  Map<String, String?> _imageCache = {}; // Cache pour les images

  @override
  void initState() {
    super.initState();
    _loadInvitations();
    _loadRequests();
  }

  Future<void> _loadInvitations() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final response = await authProvider.authenticatedRequest(
        'GET',
        '/api/get-invitation-relation-parent',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final invitationData = data['invitationData'] as List<dynamic>? ?? [];

        // Filtrer les valeurs null et traiter les invitations
        final validInvitations = invitationData
            .where((inv) => inv != null)
            .map((inv) => inv as Map<String, dynamic>)
            .toList();

        // Séparer les invitations en attente et reçues
        // Les invitations avec validation: false sont celles en attente de validation (reçues)
        // Les invitations avec validation: true sont acceptées (on peut les afficher dans une autre section si besoin)
        setState(() {
          // Invitations reçues : celles qui nécessitent une action (validation: false)
          _receivedInvitations = validInvitations
              .where((inv) => inv['validation'] == false)
              .map((inv) => {
                    'id': inv['inviteId']?.toString() ?? inv['uuid'],
                    'inviteId': inv['inviteId'],
                    'uuid': inv['uuid'],
                    // Nouveau champ image envoyé par l'API
                    'parentImage': inv['parentImage'],
                    'parentName': inv['parentName'] ?? 'Parent',
                    // On conserve la structure existante (student_name / student_email)
                    // mais on y place les vraies données parentName / parentEmail.
                    'student_name': inv['parentName'] ?? 'Parent',
                    'student_email': inv['parentEmail'] ?? 'N/A',
                    'note': inv['note'],
                    'created_at': inv['createdAt'],
                    'notificationId': inv['notificationId'],
                  })
              .toList();

          // Charger les images pour les invitations reçues (on utilise parentImage si disponible,
          // sinon on retombe sur uuid pour compatibilité)
          for (final inv in _receivedInvitations) {
            final imageKey = (inv['parentImage'] ?? inv['uuid'])?.toString();
            if (imageKey != null &&
                imageKey.isNotEmpty &&
                !_imageCache.containsKey(imageKey)) {
              _fetchParentImage(imageKey);
            }
          }

          // Invitations en attente : celles envoyées par l'utilisateur (pour l'instant vide, 
          // car l'API ne semble retourner que les invitations reçues)
          // Si vous avez un endpoint séparé pour les invitations envoyées, l'utiliser ici
          _pendingInvitations = [];
        });
      } else {
        if (mounted) {
          SnackBarHelper.showCustom(
            context,
            'Erreur lors du chargement: ${response.statusCode}',
            backgroundColor: Colors.red.shade600,
            icon: Icons.error_outline,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Une erreur est survenue lors du chargement';
        if (e.toString().toLowerCase().contains('network') || e.toString().toLowerCase().contains('connection')) {
          errorMessage = 'Erreur de connexion. Vérifiez votre connexion internet';
        } else if (e.toString().toLowerCase().contains('timeout')) {
          errorMessage = 'La requête a expiré. Veuillez réessayer';
        } else {
          errorMessage = 'Erreur lors du chargement: ${e.toString()}';
        }
        SnackBarHelper.showCustom(
          context,
          errorMessage,
          backgroundColor: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoadingRequests = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final response = await authProvider.authenticatedRequest(
        'GET',
        '/api/get-request-relation-parent',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final requestData = data['requestData'] as List<dynamic>? ?? [];

        setState(() {
          _requests = requestData
              .map((req) => req as Map<String, dynamic>)
              .toList();
        });

        // Précharger les images des demandes, en utilisant parentImg comme filename
        for (final req in _requests) {
          final filename = req['parentImg']?.toString();
          if (filename != null &&
              filename.isNotEmpty &&
              !_imageCache.containsKey(filename)) {
            _fetchParentImage(filename);
          }
        }
      } else {
        if (mounted) {
          SnackBarHelper.showCustom(
            context,
            'Erreur lors du chargement des demandes: ${response.statusCode}',
            backgroundColor: Colors.red.shade600,
            icon: Icons.error_outline,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Une erreur est survenue lors du chargement des demandes';
        if (e.toString().toLowerCase().contains('network') || e.toString().toLowerCase().contains('connection')) {
          errorMessage = 'Erreur de connexion. Vérifiez votre connexion internet';
        } else if (e.toString().toLowerCase().contains('timeout')) {
          errorMessage = 'La requête a expiré. Veuillez réessayer';
        } else {
          errorMessage = 'Erreur lors du chargement des demandes: ${e.toString()}';
        }
        SnackBarHelper.showCustom(
          context,
          errorMessage,
          backgroundColor: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRequests = false;
        });
      }
    }
  }

  Future<void> _sendInvitation() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.currentToken;
      
      if (token == null) {
        if (mounted) {
          SnackBarHelper.showCustom(
            context,
            'Erreur d\'authentification. Veuillez vous reconnecter',
            backgroundColor: Colors.red.shade600,
            icon: Icons.error_outline,
          );
        }
        return;
      }

      // Créer une requête multipart/form-data
      final uri = Uri.parse('https://www.unistudious.com/api/send-invite-relation-parent');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['email'] = _emailController.text.trim()
        ..fields['note'] = _noteController.text.isEmpty ? '' : _noteController.text.trim();

      // Envoyer la requête
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final responseData = json.decode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _emailController.clear();
        _noteController.clear();
        
        // Recharger les invitations après l'envoi
        await _loadInvitations();
        await _loadRequests();

        if (mounted) {
          // Traduire le message de succès en français
          String message = responseData['message'] ?? 'Invitation envoyée avec succès';
          if (message.toLowerCase().contains('sent successfully')) {
            message = 'Invitation envoyée avec succès ✅';
          }
          SnackBarHelper.showSuccess(context, message);
        }
      } else {
        if (mounted) {
          String errorMessage = 'Erreur lors de l\'envoi';
          if (responseData['message'] != null) {
            errorMessage = responseData['message'].toString();
          } else if (response.statusCode == 400) {
            errorMessage = 'Requête invalide. Vérifiez les informations saisies';
          } else if (response.statusCode == 404) {
            errorMessage = 'Endpoint introuvable';
          } else if (response.statusCode == 500) {
            errorMessage = 'Erreur serveur. Veuillez réessayer plus tard';
          } else {
            errorMessage = 'Erreur ${response.statusCode} lors de l\'envoi';
          }
          SnackBarHelper.showCustom(
            context,
            errorMessage,
            backgroundColor: Colors.red.shade600,
            icon: Icons.error_outline,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Une erreur est survenue lors de l\'envoi';
        if (e.toString().toLowerCase().contains('network') || e.toString().toLowerCase().contains('connection')) {
          errorMessage = 'Erreur de connexion. Vérifiez votre connexion internet';
        } else if (e.toString().toLowerCase().contains('timeout')) {
          errorMessage = 'La requête a expiré. Veuillez réessayer';
        } else {
          errorMessage = 'Erreur lors de l\'envoi: ${e.toString()}';
        }
        SnackBarHelper.showCustom(
          context,
          errorMessage,
          backgroundColor: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _respondToInvitation(String id, bool accept) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // Trouver l'invitation pour obtenir l'inviteId
      final invitation = _receivedInvitations.firstWhere(
        (inv) => inv['id'] == id,
        orElse: () => {},
      );

      if (invitation.isEmpty) {
        if (mounted) {
          SnackBarHelper.showCustom(
            context,
            'Invitation introuvable',
            backgroundColor: Colors.red.shade600,
            icon: Icons.error_outline,
          );
        }
        return;
      }

      // Essayer d'abord avec inviteId, sinon utiliser notificationId
      final inviteId = invitation['inviteId'];
      final notificationId = invitation['notificationId'];
      
      // Utiliser inviteId en priorité, sinon notificationId
      final idToUse = inviteId ?? notificationId;
      
      if (idToUse == null) {
        if (mounted) {
          SnackBarHelper.showCustom(
            context,
            'ID d\'invitation invalide (inviteId et notificationId manquants)',
            backgroundColor: Colors.red.shade600,
            icon: Icons.error_outline,
          );
        }
        return;
      }

      // Convertir l'ID en string pour l'URL
      final idString = idToUse.toString();
      
      if (accept) {
        // Accepter l'invitation
        final endpoint = '/api/accept-invite-relation-parent/$idString';
        final response = await authProvider.authenticatedRequest(
          'POST',
          endpoint,
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final responseData = json.decode(response.body);
          
          // Recharger les invitations après l'acceptation
          await _loadInvitations();

          if (mounted) {
            // Traduire le message de l'API en français
            String message = responseData['message'] ?? 'Invitation acceptée avec succès';
            if (message.toLowerCase().contains('accepted successfully')) {
              message = 'Invitation acceptée avec succès ✅';
            } else if (message.toLowerCase().contains('acceptée')) {
              message = message; // Déjà en français
            } else {
              message = 'Invitation acceptée avec succès ✅';
            }
            SnackBarHelper.showSuccess(context, message);
          }
        } else {
          final errorData = response.body.isNotEmpty 
              ? (() {
                  try {
                    return json.decode(response.body);
                  } catch (e) {
                    return null;
                  }
                })()
              : null;
          
          if (mounted) {
            String errorMessage = 'Erreur lors de l\'acceptation de l\'invitation';
            if (errorData?['message'] != null) {
              final apiMessage = errorData!['message'].toString();
              if (apiMessage.toLowerCase().contains('not found') || apiMessage.toLowerCase().contains('404')) {
                errorMessage = 'Invitation introuvable';
              } else if (apiMessage.toLowerCase().contains('already')) {
                errorMessage = 'Cette invitation a déjà été traitée';
              } else {
                errorMessage = apiMessage;
              }
            } else if (response.statusCode == 404) {
              errorMessage = 'Invitation introuvable';
            } else if (response.statusCode == 400) {
              errorMessage = 'Requête invalide';
            } else if (response.statusCode == 500) {
              errorMessage = 'Erreur serveur. Veuillez réessayer plus tard';
            } else {
              errorMessage = 'Erreur ${response.statusCode} lors de l\'acceptation';
            }
            SnackBarHelper.showCustom(
              context,
              errorMessage,
              backgroundColor: Colors.red.shade600,
              icon: Icons.error_outline,
              duration: const Duration(seconds: 5),
            );
          }
        }
      } else {
        // Rejeter l'invitation
        final endpoint = '/api/reject-invite-relation-parent/$idString';
        final response = await authProvider.authenticatedRequest(
          'POST',
          endpoint,
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final responseData = json.decode(response.body);
          
          // Recharger les invitations après le rejet
          await _loadInvitations();

          if (mounted) {
            // Traduire le message de l'API en français
            String message = responseData['message'] ?? 'Invitation rejetée avec succès';
            if (message.toLowerCase().contains('rejected successfully')) {
              message = 'Invitation rejetée avec succès ✅';
            } else if (message.toLowerCase().contains('rejetée')) {
              message = message; // Déjà en français
            } else {
              message = 'Invitation rejetée avec succès ✅';
            }
            SnackBarHelper.showSuccess(context, message);
          }
        } else {
          final errorData = response.body.isNotEmpty 
              ? (() {
                  try {
                    return json.decode(response.body);
                  } catch (e) {
                    return null;
                  }
                })()
              : null;
          
          if (mounted) {
            String errorMessage = 'Erreur lors du rejet de l\'invitation';
            if (errorData?['message'] != null) {
              final apiMessage = errorData!['message'].toString();
              if (apiMessage.toLowerCase().contains('not found') || apiMessage.toLowerCase().contains('404')) {
                errorMessage = 'Invitation introuvable';
              } else if (apiMessage.toLowerCase().contains('already')) {
                errorMessage = 'Cette invitation a déjà été traitée';
              } else {
                errorMessage = apiMessage;
              }
            } else if (response.statusCode == 404) {
              errorMessage = 'Invitation introuvable';
            } else if (response.statusCode == 400) {
              errorMessage = 'Requête invalide';
            } else if (response.statusCode == 500) {
              errorMessage = 'Erreur serveur. Veuillez réessayer plus tard';
            } else {
              errorMessage = 'Erreur ${response.statusCode} lors du rejet';
            }
            SnackBarHelper.showCustom(
              context,
              errorMessage,
              backgroundColor: Colors.red.shade600,
              icon: Icons.error_outline,
              duration: const Duration(seconds: 5),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Une erreur est survenue';
        if (e.toString().toLowerCase().contains('network') || e.toString().toLowerCase().contains('connection')) {
          errorMessage = 'Erreur de connexion. Vérifiez votre connexion internet';
        } else if (e.toString().toLowerCase().contains('timeout')) {
          errorMessage = 'La requête a expiré. Veuillez réessayer';
        } else {
          errorMessage = 'Erreur lors du traitement de l\'invitation: ${e.toString()}';
        }
        SnackBarHelper.showCustom(
          context,
          errorMessage,
          backgroundColor: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    }
  }

  Future<void> _fetchParentImage(String uuid) async {
    if (_imageCache.containsKey(uuid)) {
      return; // Image déjà en cache
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isLoggedIn || uuid.isEmpty) return;

    try {
      final response = await authProvider.authenticatedRequest(
        'POST',
        '/api/private-image-server/$uuid',
      );

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.startsWith('image/')) {
          final base64Image = base64Encode(response.bodyBytes);
          final imageDataUri = 'data:$contentType;base64,$base64Image';
          
          if (mounted) {
            setState(() {
              _imageCache[uuid] = imageDataUri;
            });
          }
        } else {
          final jsonResponse = jsonDecode(response.body);
          final imageUrl = jsonResponse['url'] as String?;
          if (mounted && imageUrl != null) {
            setState(() {
              _imageCache[uuid] = imageUrl;
            });
          }
        }
      }
    } catch (e) {
      // Ne pas afficher d'erreur pour les images manquantes
      if (mounted) {
        setState(() {
          _imageCache[uuid] = null; // Marquer comme échoué pour éviter de réessayer
        });
      }
    }
  }

  Future<void> _cancelPendingInvitation(Map<String, dynamic> item) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Essayer plusieurs clés possibles pour récupérer l'ID
      final possibleKeys = [
        'requestId',
        'inviteId',
        'id',
        'notificationId',
        'uuid',
      ];

      dynamic idToUse;
      for (final key in possibleKeys) {
        if (item[key] != null && item[key].toString().isNotEmpty) {
          idToUse = item[key];
          break;
        }
      }

      if (idToUse == null) {
        if (mounted) {
          SnackBarHelper.showCustom(
            context,
            'Impossible de trouver l\'identifiant de l\'invitation',
            backgroundColor: Colors.red.shade600,
            icon: Icons.error_outline,
          );
        }
        return;
      }

      final idString = idToUse.toString();
      final endpoint = '/api/remove-invite-relation-parent/$idString';

      final response = await authProvider.authenticatedRequest(
        'POST',
        endpoint,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = response.body.isNotEmpty
            ? (() {
                try {
                  return json.decode(response.body);
                } catch (_) {
                  return null;
                }
              })()
            : null;

        // Recharger les données après annulation
        await _loadInvitations();
        await _loadRequests();

        if (mounted) {
          String message = 'Invitation annulée avec succès';
          final apiMessage = responseData is Map<String, dynamic>
              ? responseData['message']?.toString()
              : null;

          if (apiMessage != null && apiMessage.isNotEmpty) {
            if (apiMessage.toLowerCase().contains('cancelled successfully')) {
              message = 'Invitation annulée avec succès ✅';
            } else {
              message = apiMessage;
            }
          }

          SnackBarHelper.showSuccess(context, message);
        }
      } else {
        final errorData = response.body.isNotEmpty
            ? (() {
                try {
                  return json.decode(response.body);
                } catch (_) {
                  return null;
                }
              })()
            : null;

        if (mounted) {
          String errorMessage =
              'Erreur lors de l\'annulation de l\'invitation en attente';

          final apiMessage = errorData is Map<String, dynamic>
              ? errorData['message']?.toString()
              : null;

          if (apiMessage != null && apiMessage.isNotEmpty) {
            if (apiMessage.toLowerCase().contains('not found') ||
                apiMessage.toLowerCase().contains('404')) {
              errorMessage = 'Invitation introuvable';
            } else {
              errorMessage = apiMessage;
            }
          } else if (response.statusCode == 404) {
            errorMessage = 'Invitation introuvable';
          } else if (response.statusCode == 400) {
            errorMessage = 'Requête invalide';
          } else if (response.statusCode == 500) {
            errorMessage = 'Erreur serveur. Veuillez réessayer plus tard';
          } else {
            errorMessage =
                'Erreur ${response.statusCode} lors de l\'annulation';
          }

          SnackBarHelper.showCustom(
            context,
            errorMessage,
            backgroundColor: Colors.red.shade600,
            icon: Icons.error_outline,
            duration: const Duration(seconds: 5),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage =
            'Une erreur est survenue lors de l\'annulation de l\'invitation';
        final errorText = e.toString().toLowerCase();

        if (errorText.contains('network') || errorText.contains('connection')) {
          errorMessage = 'Erreur de connexion. Vérifiez votre connexion internet';
        } else if (errorText.contains('timeout')) {
          errorMessage = 'La requête a expiré. Veuillez réessayer';
        } else {
          errorMessage =
              'Erreur lors de l\'annulation de l\'invitation: ${e.toString()}';
        }

        SnackBarHelper.showCustom(
          context,
          errorMessage,
          backgroundColor: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      drawer: const AppSidebar(),
      appBar: AppBar(
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: Icon(Icons.menu, color: theme.appBarTheme.iconTheme?.color ?? Colors.white),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            );
          },
        ),
        title: Text(
          'Invitations Parents',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
          ) ?? const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: false, // Aligne le titre à gauche
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: theme.iconTheme,
        actions: const [NotificationIconButton()],
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadInvitations();
                await _loadRequests();
              },
              child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sendInvitationCard(theme, isDark),
            const SizedBox(height: 24),
            _sectionTitle('Invitations en attente'),
                    _pendingSection(theme, isDark),
            const SizedBox(height: 24),
            _sectionTitle('Invitations reçues'),
            _receivedSection(theme, isDark),
          ],
                ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // ---------------- SEND CARD ----------------
  Widget _sendInvitationCard(ThemeData theme, bool isDark) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email du parent',
                  prefixIcon: Icon(Icons.email),
                ),
                validator: (v) =>
                v == null || !v.contains('@') ? 'Email invalide' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Note (optionnel)',
                  prefixIcon: Icon(Icons.note),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSending ? null : _sendInvitation,
                  child: _isSending
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Envoyer l’invitation'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- PENDING ----------------
  Widget _pendingSection(ThemeData theme, bool isDark) {
    // Combiner les invitations en attente et les demandes
    final allPending = <Map<String, dynamic>>[];
    allPending.addAll(_pendingInvitations);
    allPending.addAll(_requests);

    if (allPending.isEmpty && !_isLoadingRequests) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Aucune invitation en attente'),
      );
    }

    if (_isLoadingRequests && allPending.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      children: allPending.map((item) {
        // Vérifier si c'est une demande (a un studentName) ou une invitation
        final isRequest = item.containsKey('studentName');

        // Pour les demandes, on utilise l'image privée parentImg via /api/private-image-server/{filename}
        final String? requestImageKey =
            isRequest ? item['parentImg']?.toString() : null;
        final String? requestImageUrl =
            requestImageKey != null ? _imageCache[requestImageKey] : null;

        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ligne 1 : Avatar + Nom
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar
                    if (isRequest && requestImageUrl != null && requestImageUrl.isNotEmpty)
                      requestImageUrl.startsWith('data:')
                          ? ClipOval(
                              child: Image.memory(
                                base64Decode(requestImageUrl.split(',').last),
                                fit: BoxFit.cover,
                                width: 40,
                                height: 40,
                                errorBuilder: (context, error, stackTrace) {
                                  return CircleAvatar(
                                    radius: 20,
                                    backgroundColor:
                                        theme.primaryColor.withOpacity(0.2),
                                    child: Icon(
                                      Icons.person,
                                      color: theme.primaryColor,
                                      size: 20,
                                    ),
                                  );
                                },
                              ),
                            )
                          : CircleAvatar(
                              radius: 20,
                              backgroundImage: NetworkImage(requestImageUrl),
                              onBackgroundImageError: (_, __) {},
                              child: Icon(
                                Icons.person,
                                color: theme.primaryColor,
                                size: 20,
                              ),
                            )
                    else if (isRequest)
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: theme.primaryColor.withOpacity(0.2),
                        child: Icon(
                          Icons.person,
                          color: theme.primaryColor,
                          size: 20,
                        ),
                      )
                    else
                      const Icon(Icons.hourglass_top, size: 24),
                    const SizedBox(width: 12),
                    // Nom
                    Expanded(
                      child: Text(
                        item['parentName'] ?? item['email'] ?? 'Parent',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                // Ligne 2 : Email (aligné avec le nom)
                if (isRequest && item['parentEmail'] != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 52), // Aligné avec le nom (avatar 40 + espace 12)
                    child: Text(
                      item['parentEmail'],
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
                // Ligne 3 : Date (alignée avec le nom/email)
                if (item['createdAt'] != null || item['created_at'] != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 52), // Aligné avec le nom (avatar 40 + espace 12)
                    child: Text(
                      'Envoyé le ${_formatDate(item['createdAt'] ?? item['created_at'])}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                    ),
                  ),
                ],
                // Note si disponible
                if (item['note'] != null && item['note'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 52),
                    child: Text(
                      item['note'],
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Bouton Annuler en bas
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: () => _cancelPendingInvitation(item),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                    ),
                    child: const Text('Annuler'),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------- RECEIVED ----------------
  Widget _receivedSection(ThemeData theme, bool isDark) {
    if (_receivedInvitations.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Aucune invitation reçue'),
      );
    }

    return Column(
      children: _receivedInvitations.map((inv) {
        // Utiliser la même clé que pour le préchargement : parentImage si présent, sinon uuid
        final imageKey = (inv['parentImage'] ?? inv['uuid'])?.toString();
        final imageUrl =
            imageKey != null ? _imageCache[imageKey] : null;

        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ligne 1 : Avatar + Nom
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar avec image du parent
                    if (imageUrl != null && imageUrl.isNotEmpty)
                      imageUrl.startsWith('data:')
                          ? ClipOval(
                              child: Image.memory(
                                base64Decode(imageUrl.split(',').last),
                                fit: BoxFit.cover,
                                width: 40,
                                height: 40,
                                errorBuilder: (context, error, stackTrace) {
                                  return CircleAvatar(
                                    radius: 20,
                                    backgroundColor: theme.primaryColor.withOpacity(0.2),
                                    child: Icon(
                                      Icons.person,
                                      color: theme.primaryColor,
                                      size: 20,
                                    ),
                                  );
                                },
                              ),
                            )
                          : CircleAvatar(
                              radius: 20,
                              backgroundImage: NetworkImage(imageUrl),
                              onBackgroundImageError: (_, __) {},
                              child: Icon(
                                Icons.person,
                                color: theme.primaryColor,
                                size: 20,
                              ),
                            )
                    else
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: theme.primaryColor.withOpacity(0.2),
                        child: Icon(
                          Icons.person,
                          color: theme.primaryColor,
                          size: 20,
                        ),
                      ),
                    const SizedBox(width: 12),
                    // Nom
                    Expanded(
                      child: Text(
                        inv['student_name'] ?? 'Parent',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                // Ligne 2 : Email (aligné avec le nom)
                if (inv['student_email'] != null && inv['student_email'] != 'N/A') ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 52), // Aligné avec le nom (avatar 40 + espace 12)
                    child: Text(
                      inv['student_email'],
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
                // Ligne 3 : Date (alignée avec le nom/email)
                if (inv['created_at'] != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 52), // Aligné avec le nom (avatar 40 + espace 12)
                    child: Text(
                      'Reçu le ${_formatDate(inv['created_at'])}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                    ),
                  ),
                ],
                // Note si disponible
                if (inv['note'] != null && inv['note'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 52),
                    child: Text(
                      inv['note'],
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Boutons Accepter/Rejeter
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            _respondToInvitation(inv['id'], false),
                        child: const Text('Rejeter'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            _respondToInvitation(inv['id'], true),
                        child: const Text('Accepter'),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatDate(String date) {
    try {
      // Gérer le format "2026-02-03 19:51:12"
      final d = DateTime.parse(date.replaceAll(' ', 'T'));
    return '${d.day}/${d.month}/${d.year}';
    } catch (e) {
      return date;
    }
  }
}
