import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';

class AppleLoginPage extends StatelessWidget {
  const AppleLoginPage({Key? key}) : super(key: key);

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

          if (token != null) {
            debugPrint('[AppleLoginPage] ✅ Token reçu : $token');

            await Provider.of<AuthProvider>(context, listen: false).setToken(token);

            Provider.of<UserModel>(context, listen: false).updateUser(
              name: data['name'] ?? 'Utilisateur Apple',
              email: data['email'] ?? 'user@apple.com',
            );


            Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (_) => false);
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
