import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as developer;
import '../utils/snackbar_helper.dart';

class ContentModerationPage extends StatefulWidget {
  final String? contentType;
  final String? contentId;

  const ContentModerationPage({super.key, this.contentType, this.contentId});

  @override
  State<ContentModerationPage> createState() => _ContentModerationPageState();
}

class _ContentModerationPageState extends State<ContentModerationPage> {
  final List<String> _reportReasons = [
    'Contenu inapproprié',
    'Harcèlement ou intimidation',
    'Spam ou contenu commercial non autorisé',
    'Contenu violent ou dangereux',
    'Contenu sexuel explicite',
    'Discours de haine',
    'Fausses informations',
    'Violation des droits d\'auteur',
    'Autre'
  ];

  String? _selectedReason;
  final TextEditingController _descriptionController = TextEditingController();
  bool _isSubmitting = false;
  bool _forward = false;
  bool _isBlocking = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitReport({String? contentType, String? contentId}) async {
    if (_selectedReason == null) {
      SnackBarHelper.showWarning(context, 'Veuillez sélectionner une raison');
      return;
    }

    final resolvedType = contentType ?? widget.contentType;
    final resolvedId = contentId ?? widget.contentId;
    if (resolvedType == null || resolvedId == null || resolvedId.isEmpty) {
      SnackBarHelper.showError(context, 'Contenu invalide à signaler');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // Use new API for account reports
      if (resolvedType == 'user') {
        final uri = Uri.parse('https://www.unistudious.com/api/report/account');
        var request = http.MultipartRequest('POST', uri)
          ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
          ..fields['accountId'] = resolvedId
          ..fields['comment'] = _descriptionController.text.isNotEmpty 
              ? _descriptionController.text 
              : (_selectedReason ?? '')
          ..fields['forward'] = _forward.toString();

        developer.log(
          'Sending POST request to $uri with accountId: $resolvedId, comment: ${request.fields['comment']}, forward: $_forward',
          name: 'ContentModerationPage',
        );

        final response = await request.send();
        final responseBody = await response.stream.bytesToString();
        final responseData = jsonDecode(responseBody);

        if (response.statusCode == 200 && responseData['success'] == true) {
          developer.log(
            'Account report submitted successfully: ${responseData['data']?['id']}',
            name: 'ContentModerationPage',
          );
          SnackBarHelper.showSuccess(context, 'Signalement envoyé avec succès');
          Navigator.pop(context);
        } else {
          throw Exception('Failed to submit report: ${responseData['message'] ?? 'Unknown error'}');
        }
      } else {
        // Keep old API for other content types
        final uri = Uri.parse('https://www.unistudious.com/api/report-content');
        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if ((authProvider.currentToken ?? '').isNotEmpty)
              'Authorization': 'Bearer ${authProvider.currentToken}',
          },
          body: jsonEncode({
            'content_type': resolvedType,
            'content_id': resolvedId,
            'reason': _selectedReason,
            'description': _descriptionController.text,
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );

        if (response.statusCode == 200) {
          SnackBarHelper.showSuccess(context, 'Signalement envoyé avec succès');
          Navigator.pop(context);
        } else {
          throw Exception('Failed to submit report');
        }
      }
    } catch (e) {
      developer.log('Error submitting report: $e', name: 'ContentModerationPage');
      SnackBarHelper.showError(
        context,
        'Erreur lors de l\'envoi du signalement: ${e.toString()}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _blockAccount(String accountId) async {
    if (_isBlocking || !mounted) return;

    setState(() {
      _isBlocking = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if ((authProvider.currentToken ?? '').isEmpty) {
      SnackBarHelper.showError(context, 'Session expirée. Veuillez vous reconnecter.');
      if (mounted) setState(() => _isBlocking = false);
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    final uri = Uri.parse('https://www.unistudious.com/api/block/account');
    try {
      var request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${authProvider.currentToken}'
        ..fields['accountId'] = accountId;

      developer.log('Blocking account $accountId via $uri', name: 'ContentModerationPage');

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body);

      if (response.statusCode == 200 && data['success'] == true) {
        SnackBarHelper.showSuccess(context, 'Utilisateur bloqué.');
      } else {
        throw Exception(data['message'] ?? 'Échec du blocage');
      }
    } catch (e) {
      developer.log('Error blocking account: $e', name: 'ContentModerationPage');
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur lors du blocage : $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBlocking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Signaler du contenu',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aidez-nous à maintenir une communauté sûre',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Votre signalement nous aide à identifier et supprimer le contenu inapproprié.',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Raison du signalement',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              ..._reportReasons.map((reason) => RadioListTile<String>(
                title: Text(
                  reason,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                value: reason,
                groupValue: _selectedReason,
                onChanged: (value) {
                  setState(() {
                    _selectedReason = value;
                  });
                },
                activeColor: theme.primaryColor,
              )),
              const SizedBox(height: 24),
              Text(
                'Description (optionnelle)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Ajoutez des détails sur le problème...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                ),
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
              child: ElevatedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => _submitReport(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Envoyer le signalement',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              if (widget.contentType == 'user') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.block, color: theme.colorScheme.error),
                    label: _isBlocking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Bloquer l’utilisateur',
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: theme.colorScheme.error),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isBlocking || (widget.contentId ?? '').isEmpty
                        ? null
                        : () => _blockAccount(widget.contentId!),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.blue[900] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.blue[700]! : Colors.blue[200]!,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: isDark ? Colors.blue[300] : Colors.blue[700],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Les signalements sont traités dans les 24 heures. Nous vous remercions de contribuer à maintenir notre communauté sûre.',
                        style: TextStyle(
                          color: isDark ? Colors.blue[300] : Colors.blue[700],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
