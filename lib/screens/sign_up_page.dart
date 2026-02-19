import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'dart:io';
import '../models/user_model.dart';
import '../providers/theme_provider.dart';
import '../utils/snackbar_helper.dart';
import 'apple_login_page.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  _SignUpPageState createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isTermsAccepted = false;

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    // Vérifier la confirmation du mot de passe
    if (_passwordController.text != _confirmPasswordController.text) {
      SnackBarHelper.showError(context, 'Les mots de passe ne correspondent pas');
      return;
    }

    if (!_isTermsAccepted) {
      SnackBarHelper.showWarning(context, 'Veuillez accepter les conditions d\'utilisation');
      return;
    }

    setState(() => _isLoading = true);

    final url = Uri.parse('https://www.unistudious.com/register-mobile');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'full_name': _fullNameController.text.trim(),
          'username': _usernameController.text.trim(),
          'email': _emailController.text.trim().toLowerCase(),
          'password': _passwordController.text,
          'phone_number': _phoneController.text.trim(),
          'location': null,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        // Mettre à jour le modèle utilisateur si disponible
        if (data['user'] != null) {
          Provider.of<UserModel>(context, listen: false).name =
              data['user']['full_name'] ?? _fullNameController.text;
          Provider.of<UserModel>(context, listen: false).email =
              data['user']['email'] ?? _emailController.text;
          Provider.of<UserModel>(context, listen: false).username =
              data['user']['username'] ?? _usernameController.text;
        }

        if (mounted) {
          SnackBarHelper.showSuccess(context, data['message'] ?? 'Inscription réussie !');
          Navigator.pushNamedAndRemoveUntil(
              context, '/dashboard', (route) => false);
        }
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['message'] ??
            errorData['error'] ??
            'Échec de l\'inscription';

        if (mounted) {
          SnackBarHelper.showError(context, errorMessage);
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, 'Erreur de connexion: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _validatePhone(String? value) {
    // Le numéro de téléphone est maintenant optionnel : on ne valide que s'il est renseigné
    if (value != null && value.isNotEmpty) {
      // Validation simple pour numéro de téléphone (8 chiffres pour Tunisie)
      if (!RegExp(r'^\d{8}$')
          .hasMatch(value.replaceAll(RegExp(r'[^\d]'), ''))) {
        return 'Numéro de téléphone invalide (8 chiffres)';
      }
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'L\'email est requis';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Email invalide';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Le mot de passe est requis';
    }
    if (value.length < 6) {
      return 'Le mot de passe doit contenir au moins 6 caractères';
    }
    return null;
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    bool _obscureText = obscure; // Track visibility state

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Card(
        color: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: _isLoading ? 0 : 2,
        child: StatefulBuilder(
          builder: (context, setState) {
            return TextFormField(
              controller: controller,
              obscureText: _obscureText,
              keyboardType: keyboardType,
              enabled: !_isLoading,
              validator: validator,
              decoration: InputDecoration(
                prefixIcon: Icon(icon, color: Colors.deepPurple[300]),
                labelText: label,
                labelStyle: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                suffixIcon: obscure
                    ? IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey[400],
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureText = !_obscureText;
                    });
                  },
                )
                    : null,
              ),
              style: theme.textTheme.bodyLarge,
            );
          },
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
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : onPressed,
        icon: _isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    foregroundColor ?? Colors.white,
                  ),
                ),
              )
            : (leading ??
                (icon != null
                    ? Icon(
                        icon,
                        size: 24,
                      )
                    : const SizedBox.shrink())),
        label: Text(
          _isLoading ? 'Inscription...' : label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ??
              (Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF1A003D)
                  : Colors.deepPurple),
          foregroundColor: foregroundColor ?? Colors.white,
          minimumSize: Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: borderColor != null
              ? BorderSide(color: borderColor)
              : BorderSide.none,
          elevation: _isLoading ? 0 : 3,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    'Créer un compte',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ) ?? const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rejoignez Unistudious pour commencer votre parcours d\'apprentissage',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),

                  // Champs de formulaire avec validations spécifiques
                  _buildTextField(
                    controller: _fullNameController,
                    label: 'Nom complet',
                    icon: Icons.person_outline,
                    validator: (value) =>
                    (value?.isEmpty ?? true) ? 'Le nom complet est requis' : null,
                  ),
                  _buildTextField(
                    controller: _usernameController,
                    label: 'Nom d\'utilisateur',
                    icon: Icons.person,
                    validator: (value) =>
                    (value?.isEmpty ?? true) ? 'Le nom d\'utilisateur est requis' : null,
                  ),
                  _buildTextField(
                    controller: _emailController,
                    label: 'Adresse e-mail',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                  ),
                  _buildTextField(
                    controller: _phoneController,
                    label: 'Numéro de téléphone',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: _validatePhone,
                  ),
                  _buildTextField(
                    controller: _passwordController,
                    label: 'Mot de passe',
                    icon: Icons.lock_outline,
                    obscure: true,
                    validator: _validatePassword,
                  ),
                  _buildTextField(
                    controller: _confirmPasswordController,
                    label: 'Confirmer le mot de passe',
                    icon: Icons.lock_outline,
                    obscure: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'La confirmation est requise';
                      }
                      if (value != _passwordController.text) {
                        return 'Les mots de passe ne correspondent pas';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // Checkbox conditions
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isTermsAccepted = !_isTermsAccepted;
                      });
                    },
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _isTermsAccepted,
                          onChanged: (_) {
                            setState(() {
                              _isTermsAccepted = !_isTermsAccepted;
                            });
                          },
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          activeColor: Colors.deepPurple,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text.rich(
                              TextSpan(
                                text: 'J\'accepte les ',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.grey[400] : Colors.grey[600]
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Conditions d\'utilisation',
                                    style: TextStyle(
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.deepPurple[300] : Colors.deepPurple,
                                    ),
                                  ),
                                  const TextSpan(text: ' et la '),
                                  TextSpan(
                                    text: 'Politique de confidentialité',
                                    style: TextStyle(
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.deepPurple[300] : Colors.deepPurple,
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

                  const SizedBox(height: 16),

                  // Bouton d'inscription
                  _buildElevatedButton(
                    onPressed: _signUp,
                    label: 'S\'inscrire',
                    icon: Icons.person_add,
                  ),

                  const SizedBox(height: 24),

                  // Boutons sociaux
                  Row(
                    children: [
                      Expanded(
                          child: Divider(
                              thickness: 1,
                              color: isDark ? Colors.white24 : Colors.grey[300]
                          )
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Ou inscrivez-vous avec',
                          style: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey[600]
                          ),
                        ),
                      ),
                      Expanded(
                          child: Divider(
                              thickness: 1,
                              color: isDark ? Colors.white24 : Colors.grey[300]
                          )
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _buildElevatedButton(
                    onPressed: () {}, // TODO: Google sign-in
                    label: 'Continuer avec Google',
                    leading: Image.asset(
                      'assets/google.png',
                      width: 24,
                      height: 24,
                    ),
                    backgroundColor: isDark ? Colors.grey[800] : Colors.white,
                    foregroundColor: isDark ? Colors.white : Colors.black87,
                    borderColor: isDark ? Colors.grey[600] : Colors.grey[300],
                  ),

                  //_buildElevatedButton(
                    //onPressed: () {}, // TODO: Facebook sign-in
                    //label: 'Continuer avec Facebook',
                    //icon: Icons.facebook,
                    //backgroundColor: const Color(0xFF1877F2),
                    //foregroundColor: Colors.white,
                  //),

                  if (Platform.isIOS)
                    _buildElevatedButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AppleLoginPage())
                      ),
                      label: 'Continuer avec Apple',
                      icon: Icons.apple,
                      backgroundColor: isDark ? Colors.grey[900] : Colors.black,
                      foregroundColor: Colors.white,
                    ),

                  const SizedBox(height: 24),

                  // Lien de connexion
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/login'),
                      child: RichText(
                        text: TextSpan(
                          text: 'Vous avez déjà un compte ? ',
                          style: theme.textTheme.bodyMedium,
                          children: [
                            TextSpan(
                              text: 'Se connecter',
                              style: const TextStyle(
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