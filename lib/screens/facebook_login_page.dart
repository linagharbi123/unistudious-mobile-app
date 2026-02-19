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

      // 1. Déconnecte d'abord pour forcer la sélection de compte (comme Google)
      try {
        await facebookAuth.logOut();
        debugPrint('[FacebookLoginPage] Déconnexion effectuée pour forcer la sélection de compte');
      } catch (e) {
        debugPrint('[FacebookLoginPage] Erreur déconnexion (ignorée): $e');
      }

      // 2. Lance le login avec interface web pour sélection de compte
      final LoginResult loginResult = await facebookAuth.login(
        permissions: ['email', 'public_profile'],
        loginBehavior: LoginBehavior.webOnly, // Utilise le navigateur web pour afficher la page de sélection de compte
      );

      if (loginResult.status == LoginStatus.cancelled) {
        Navigator.pop(context);
        return;
      }

      if (loginResult.status != LoginStatus.success || loginResult.accessToken == null) {
        Navigator.pop(context);
        return;
      }

      final AccessToken accessToken = loginResult.accessToken!;

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
        Navigator.pop(context);
      }
    } catch (e, stack) {
      debugPrint('[FacebookLoginPage] ❌ Exception : $e\n$stack');
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
