import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;

import '../models/user_model.dart';
import '../providers/auth_provider.dart';

class GoogleLoginPage extends StatelessWidget {
  const GoogleLoginPage({Key? key}) : super(key: key);

  Future<void> loginWithGoogle(BuildContext context) async {
    debugPrint('[GoogleLoginPage] Initiating Google Sign-In process...');

    try {
      // Initialize Google Sign-In with platform-specific configuration
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
        // iOS: use clientId
        clientId: Platform.isIOS
            ? '641148541518-sa2q0e7s3jn6jgtf60fk41miocjqbte5.apps.googleusercontent.com'
            : null,
        // Android: use serverClientId (Web Client ID) for backend verification
        // The Android Client IDs (debug/release) are configured in Google Cloud Console
        // and are automatically matched by package name + SHA-1
        serverClientId: Platform.isAndroid
            ? '641148541518-j3t36n8duiie6l7uvr8p6v3son4rs4rv.apps.googleusercontent.com'
            : null,
        // Force account selection to avoid cached account issues
        forceCodeForRefreshToken: false,
        // Additional configuration for better compatibility
        hostedDomain: null,
      );

      // Sign in with Google
      GoogleSignInAccount? googleUser;
      try {
        debugPrint('[GoogleLoginPage] Attempting to sign in with Google...');
        debugPrint('[GoogleLoginPage] Platform: ${Platform.operatingSystem}');
        debugPrint('[GoogleLoginPage] ServerClientId: ${Platform.isAndroid ? "641148541518-j3t36n8duiie6l7uvr8p6v3son4rs4rv.apps.googleusercontent.com" : "N/A"}');
        
        // Sign out first to clear any cached account that might cause issues
        try {
          await googleSignIn.signOut();
          debugPrint('[GoogleLoginPage] Signed out from any previous session');
        } catch (e) {
          debugPrint('[GoogleLoginPage] Sign out error (ignored): $e');
        }
        
        // Attempt sign in
        googleUser = await googleSignIn.signIn();
      } catch (e, stackTrace) {
        debugPrint('[GoogleLoginPage] Error during Google Sign-In attempt: $e');
        debugPrint('[GoogleLoginPage] Stack trace: $stackTrace');
        
        String errorMessage = 'Erreur lors de la connexion Google';
        if (e.toString().contains('SIGN_IN_CANCELLED') || e.toString().contains('sign_in_cancelled')) {
          errorMessage = 'Connexion Google annulée';
        } else if (e.toString().contains('SIGN_IN_REQUIRED') || e.toString().contains('sign_in_required')) {
          errorMessage = 'Connexion Google requise. Veuillez réessayer.';
        } else if (e.toString().contains('NETWORK_ERROR') || e.toString().contains('network')) {
          errorMessage = 'Erreur réseau. Vérifiez votre connexion internet.';
        } else if (e.toString().contains('DEVELOPER_ERROR') || e.toString().contains('developer')) {
          errorMessage = 'Erreur de configuration. Vérifiez le SHA-1 fingerprint dans Google Cloud Console.';
        } else {
          errorMessage = 'Erreur: $e';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 5),
          ),
        );
        Navigator.pop(context);
        return;
      }

      if (googleUser == null) {
        debugPrint('[GoogleLoginPage] Google Sign-In cancelled by user');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connexion Google annulée')),
        );
        Navigator.pop(context);
        return;
      }

      debugPrint(
          '[GoogleLoginPage] Google Sign-In successful. User: ${googleUser.email}, ID: ${googleUser.id}');

      // Retrieve authentication details
      debugPrint('[GoogleLoginPage] Fetching Google authentication details...');
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      void printTokenInChunks(String token) {
        const int chunkSize = 200;
        for (int i = 0; i < token.length; i += chunkSize) {
          final end = (i + chunkSize < token.length) ? i + chunkSize : token.length;
          debugPrint('🔹 Token part [${i ~/ chunkSize}]: ${token.substring(i, end)}');
        }
      }

      if (idToken == null) {
        debugPrint('[GoogleLoginPage] Error: ID Token is null');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur : Jeton Google non obtenu')),
        );
        Navigator.pop(context);
        return;
      }

      // Print token in chunks and as a full token for both platforms
      if (Platform.isAndroid) {
        debugPrint('[GoogleLoginPage][Android] Printing ID Token in chunks...');
        printTokenInChunks(idToken);
        debugPrint('[GoogleLoginPage][Android] ID Token (full) = $idToken');
      } else if (Platform.isIOS) {
        debugPrint('[GoogleLoginPage][iOS] Printing ID Token in chunks...');
        printTokenInChunks(idToken);
        debugPrint('[GoogleLoginPage][iOS] ID Token (full) = $idToken');
      }

      // Send idToken to backend
      final response = await http.post(
        Uri.parse('https://www.unistudious.com/mobile/login/google'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'code': idToken}),
      );

      debugPrint(
          '[GoogleLoginPage] Backend response received. Status code: ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final token = responseData['token'] ??
            responseData['new_token'] ??
            responseData['access_token'] ??
            response.headers['authorization']?.replaceFirst('Bearer ', '');

        if (token != null && token.isNotEmpty) {
          // Attendre la sauvegarde du token avant de naviguer,
          // pour que AuthProvider.currentToken et isLoggedIn soient bien à jour
          await Provider.of<AuthProvider>(context, listen: false).setToken(token);
          debugPrint(
              '[GoogleLoginPage] Token saved: ${token.substring(0, token.length > 50 ? 50 : token.length)}...');
        } else {
          debugPrint(
              '[GoogleLoginPage] Error: No token found in response. Response body: ${response.body}');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur : Aucun token reçu')),
          );
          Navigator.pop(context);
          return;
        }

        // Update UserModel
        Provider.of<UserModel>(context, listen: false).name =
            responseData['name'] ?? googleUser.displayName ?? 'Utilisateur';
        Provider.of<UserModel>(context, listen: false).email =
            responseData['email'] ?? googleUser.email;

        Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
      } else {
        final error = jsonDecode(response.body)['message'] ?? 'Échec de la connexion Google';
        debugPrint(
            '[GoogleLoginPage] Backend error: Status ${response.statusCode}, Body: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
        Navigator.pop(context);
      }
    } catch (e, stackTrace) {
      debugPrint('[GoogleLoginPage] Error during Google Sign-In process: $e');
      debugPrint('[GoogleLoginPage] Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la connexion Google : $e')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Trigger loginWithGoogle automatically after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loginWithGoogle(context);
    });

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connexion à Google en cours...', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}