import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../utils/snackbar_helper.dart';

class AppleLoginPage extends StatelessWidget {
  const AppleLoginPage({Key? key}) : super(key: key);

  /// Affiche une popup bloquante pour saisir le fullName quand hasFullName est false
  Future<String?> _showFullNameDialog(BuildContext context) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Complétez votre profil'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Veuillez saisir votre nom complet pour continuer.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Nom complet',
                  hintText: 'Entrez votre nom complet',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'Le nom complet est obligatoire';
                  }
                  if (trimmed.length < 3) {
                    return 'Le nom complet doit contenir au moins 3 caractères';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }

  Future<void> _signInWithApple(BuildContext context) async {
    debugPrint('[AppleLoginPage] 🚀 Lancement de la connexion Apple...');
    try {
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);
      debugPrint('[AppleLoginPage] 🔐 Nonce généré : $nonce');

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: nonce,
      );

      debugPrint('[AppleLoginPage] ✅ Credential reçu :');
      debugPrint(' - userIdentifier: ${credential.userIdentifier}');
      debugPrint(' - email: ${credential.email}');
      debugPrint(' - givenName: ${credential.givenName}');
      debugPrint(' - familyName: ${credential.familyName}');
      debugPrint(' - identityToken: ${credential.identityToken?.substring(0, 20)}...');

      final appleToken = credential.identityToken;
      debugPrint('[AppleLoginPage] 🍏 Token Apple reçu : ${appleToken}');


      if (appleToken != null) {
        debugPrint('[AppleLoginPage] 🛰 Envoi du token au backend...');

        final response = await http.post(
          Uri.parse('https://www.unistudious.com/mobile/login/apple'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'code': appleToken}),
        );

        debugPrint('[AppleLoginPage] 📬 Réponse backend : ${response.statusCode}');
        debugPrint('[AppleLoginPage] Body : ${response.body}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final token = data['token'] ?? data['access_token'];
          final hasFullName = data['hasFullName'] == true;

          if (token != null) {
            debugPrint('[AppleLoginPage] ✅ Token reçu : $token');
            debugPrint('[AppleLoginPage] hasFullName : $hasFullName');

            await Provider.of<AuthProvider>(context, listen: false).setToken(token);

            if (!hasFullName) {
              // Popup bloquante : l'utilisateur doit saisir son fullName
              bool profileUpdated = false;
              while (!profileUpdated && context.mounted) {
                final fullName = await _showFullNameDialog(context);
                if (fullName == null || fullName.isEmpty) {
                  await Provider.of<AuthProvider>(context, listen: false).clearToken();
                  if (context.mounted) Navigator.of(context).pop();
                  return;
                }

                try {
                  final authProvider = Provider.of<AuthProvider>(context, listen: false);
                  final token = authProvider.currentToken;
                  if (token == null || token.isEmpty) {
                    if (context.mounted) SnackBarHelper.showError(context, 'Session expirée');
                    return;
                  }

                  final request = http.MultipartRequest(
                    'POST',
                    Uri.parse('https://www.unistudious.com/api/apple-update-fields'),
                  )
                    ..headers['Authorization'] = 'Bearer $token'
                    ..fields['fullName'] = fullName;

                  final streamedResponse = await request.send();
                  final profileResponse = await http.Response.fromStream(streamedResponse);

                  if (profileResponse.statusCode == 200) {
                    final profileData = jsonDecode(profileResponse.body);
                    if (profileData['success'] == true) {
                      final updatedFullName = profileData['fullName'] ?? fullName;
                      Provider.of<UserModel>(context, listen: false).updateUser(
                        name: updatedFullName,
                        email: data['email'] ?? 'user@apple.com',
                      );
                      profileUpdated = true;
                    } else {
                      final msg = profileData['message'] ?? 'Erreur lors de la mise à jour du profil';
                      if (context.mounted) SnackBarHelper.showError(context, msg.toString());
                    }
                  } else {
                    String msg = 'Erreur lors de la mise à jour du profil';
                    try {
                      final errBody = jsonDecode(profileResponse.body);
                      msg = (errBody['message'] ?? errBody['error'] ?? msg).toString();
                    } catch (_) {}
                    if (context.mounted) {
                      SnackBarHelper.showError(context, msg);
                    }
                  }
                } catch (e) {
                  debugPrint('[AppleLoginPage] ❌ Erreur apple-update-fields: $e');
                  if (context.mounted) {
                    SnackBarHelper.showError(context, 'Erreur lors de la mise à jour du profil');
                  }
                }
              }
            } else {
              Provider.of<UserModel>(context, listen: false).updateUser(
                name: data['name'] ?? 'Utilisateur Apple',
                email: data['email'] ?? 'user@apple.com',
              );
            }

            if (context.mounted) {
              Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (_) => false);
            }
          } else {
            debugPrint('[AppleLoginPage] ❌ Aucun token reçu dans la réponse');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Aucun token reçu')),
            );
          }
        } else {
          debugPrint('[AppleLoginPage] ❌ Erreur côté serveur (${response.statusCode})');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur serveur Apple')),
          );
        }
      } else {
        debugPrint('[AppleLoginPage] ❌ identityToken null');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : token Apple manquant')),
        );
      }
    } catch (e, stack) {
      debugPrint('[AppleLoginPage] ❌ Erreur Apple Sign-In: $e');
      debugPrint('[AppleLoginPage] 📛 Stacktrace : $stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur Apple Sign-In')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Déclenche la connexion automatiquement au chargement
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _signInWithApple(context);
    });

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  String _generateNonce([int length = 32]) {
    final charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
