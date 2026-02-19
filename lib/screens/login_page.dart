import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/snackbar_helper.dart';
import 'google_login_page.dart';
import 'facebook_login_page.dart';
import 'apple_login_page.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      final success = await authProvider.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (success) {
        Provider.of<UserModel>(context, listen: false).updateUser(
          name: 'Utilisateur',
          email: 'user@unistudious.com',
        );
        Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
      } else {
        final rawError = authProvider.error ?? '';
        String displayMessage;

        // Personnaliser le message pour les erreurs de type 401 / compte inexistant
        if (rawError.contains('401') ||
            rawError.toLowerCase().contains('unauthorized') ||
            rawError.toLowerCase().contains('login failed')) {
          displayMessage = 'Ce compte n\'existe pas ou le mot de passe est incorrect.';
        } else if (rawError.isNotEmpty) {
          displayMessage = rawError;
        } else {
          displayMessage = 'Échec de la connexion';
        }

        SnackBarHelper.showError(context, displayMessage);
      }
    } catch (e) {
      debugPrint('Erreur de connexion (LOGIN) : $e');
      SnackBarHelper.showError(context, 'Erreur de connexion : $e');
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Card(
        color: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: (value) => (value == null || value.isEmpty) ? 'Ce champ est requis' : null,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.deepPurple),
            labelText: label,
            labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          ),
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }

  Widget _buildElevatedButton({
    required VoidCallback onPressed,
    required String label,
    IconData? icon,
    Widget? leading,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? borderColor,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Card(
        color: backgroundColor ?? theme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: borderColor != null ? BorderSide(color: borderColor) : BorderSide.none,
        ),
        elevation: 4,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Row(
              children: [
                if (leading != null)
                  leading
                else if (icon != null)
                  Icon(icon, color: foregroundColor ?? theme.iconTheme.color, size: 24),
                if (leading != null || icon != null) SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: foregroundColor ?? theme.textTheme.bodyLarge?.color,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus(); // Dismiss keyboard when tapping outside
        },
        behavior: HitTestBehavior.opaque, // Ensures taps anywhere are detected
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 24),
                  Text(
                    'Se connecter',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ) ?? TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Accédez à votre compte Unistudious',
                    style: theme.textTheme.bodyMedium,
                  ),
                  SizedBox(height: 24),
                  _buildTextField(
                    controller: _usernameController,
                    label: 'Nom d\'utilisateur',
                    icon: Icons.person_outline,
                  ),
                  _buildTextField(
                    controller: _passwordController,
                    label: 'Mot de passe',
                    icon: Icons.lock_outline,
                    obscure: true,
                  ),
                  SizedBox(height: 16),
                  _buildElevatedButton(
                    onPressed: _login,
                    label: 'Se connecter',
                    icon: Icons.login,
                    backgroundColor: isDark ? const Color(0xFF1A003D) : Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  SizedBox(height: 16),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/forget-password'),
                      child: Text(
                        'Mot de passe oublié ?',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.deepPurple,
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: Divider(color: isDark ? Colors.white24 : Colors.grey[300])),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Ou connectez-vous avec',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Expanded(child: Divider(color: isDark ? Colors.white24 : Colors.grey[300])),
                    ],
                  ),
                  SizedBox(height: 16),
                  _buildElevatedButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GoogleLoginPage())),
                    label: 'Continuer avec Google',
                    leading: Image.asset(
                      'assets/google.png',
                      width: 24,
                      height: 24,
                    ),
                    backgroundColor: isDark ? Colors.grey[800] : Colors.white,
                    foregroundColor: isDark ? Colors.white : Colors.black87,
                    borderColor: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                  ),
                  //_buildElevatedButton(
                    //onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FacebookLoginPage())),
                    //label: 'Continuer avec Facebook',
                    //icon: Icons.facebook,
                    //backgroundColor: Color(0xFF1877F2),
                    //foregroundColor: Colors.white,
                  //),
                  if (Platform.isIOS)
                    _buildElevatedButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AppleLoginPage())),
                      label: 'Continuer avec Apple',
                      icon: Icons.apple,
                      backgroundColor: isDark ? Colors.grey[900] : Colors.black,
                      foregroundColor: Colors.white,
                    ),
                  SizedBox(height: 24),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/signup'),
                      child: RichText(
                        text: TextSpan(
                          text: 'Vous n\'avez pas de compte ? ',
                          style: theme.textTheme.bodyMedium,
                          children: [
                            TextSpan(
                              text: 'Créer un compte',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.deepPurple,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}