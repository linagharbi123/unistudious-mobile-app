import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';

class FacebookLoginPage extends StatelessWidget {
  const FacebookLoginPage({Key? key}) : super(key: key);

  Future<void> loginWithFacebook(BuildContext context) async {
    debugPrint('[FacebookLoginPage] ▶️ Début connexion Facebook...');

    try {
      final facebookAuth = FacebookAuth.instance;

      // 1. Vérifie si un token existe déjà
      AccessToken? accessToken = await facebookAuth.accessToken;

      // 2. Si pas de token, lance login
      if (accessToken == null) {
        final LoginResult loginResult = await facebookAuth.login(
          permissions: ['email', 'public_profile'],
          loginBehavior: LoginBehavior.webOnly, // Force l'utilisation du navigateur web au lieu de l'app native
        );

        if (loginResult.status == LoginStatus.cancelled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connexion Facebook annulée')),
          );
          Navigator.pop(context);
          return;
        }

        if (loginResult.status != LoginStatus.success || loginResult.accessToken == null) {
          final error = loginResult.message ?? 'Erreur inconnue';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connexion Facebook échouée : $error')),
          );
          Navigator.pop(context);
          return;
        }

        accessToken = loginResult.accessToken!;
      }

      final String fbToken = accessToken.token;
      debugPrint('[FacebookLoginPage] ✅ AccessToken : $fbToken');

      // 3. Appelle API Graph pour vérification (facultatif mais utile pour debug)
      final graphResponse = await http.get(
        Uri.parse('https://graph.facebook.com/me?fields=id,name,email&access_token=$fbToken'),
      );
      debugPrint('[FacebookLoginPage] Graph API : ${graphResponse.body}');

      // 4. Récupère données Facebook
      final userData = await facebookAuth.getUserData(
        fields: 'id,name,email,picture.width(200)',
      );
      debugPrint('[FacebookLoginPage] 👤 UserData : $userData');

      // 5. Envoie à ton backend
      final response = await http.post(
        Uri.parse('https://www.unistudious.com/mobile/login/facebook'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': userData['id'],
          'email': userData['email'],
          'name': userData['name'],
        }),
      );

      debugPrint('[FacebookLoginPage] Réponse backend : ${response.statusCode} ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final jwt = responseData['token'] ??
            responseData['new_token'] ??
            responseData['access_token'] ??
            response.headers['authorization']?.replaceFirst('Bearer ', '');

        if (jwt != null && jwt.isNotEmpty) {
          await Provider.of<AuthProvider>(context, listen: false).setToken(jwt);

          // 6. Met à jour UserModel
          Provider.of<UserModel>(context, listen: false).updateUser(
            name: responseData['name'] ?? userData['name'],
            email: responseData['email'] ?? userData['email'],
            imageUrl: userData['picture']?['data']?['url'],
            facebookToken: fbToken,
            facebookUserId: userData['id'],
          );

          Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
        } else {
          throw Exception("❌ Aucun token JWT dans la réponse.");
        }
      } else {
        final error = jsonDecode(response.body)['message'] ?? 'Erreur inconnue';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erreur backend : $error')),
        );
        Navigator.pop(context);
      }
    } catch (e, stack) {
      debugPrint('[FacebookLoginPage] ❌ Exception : $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la connexion Facebook : $e')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Appel automatique du login après rendu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loginWithFacebook(context);
    });

    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Connexion à Facebook en cours...',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
