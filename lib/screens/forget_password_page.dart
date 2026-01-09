import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../utils/snackbar_helper.dart';

class ForgetPasswordPage extends StatefulWidget {
  const ForgetPasswordPage({super.key});

  @override
  _ForgetPasswordPageState createState() => _ForgetPasswordPageState();
}

class _ForgetPasswordPageState extends State<ForgetPasswordPage> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final email = _emailController.text.trim();
    final url = Uri.parse('https://www.unistudious.com/forgot-password-mobile');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 30));

      setState(() {
        _isLoading = false;
      });

      final data = jsonDecode(response.body);
      debugPrint('🔵 [ForgetPassword] Response: ${response.body}');

      if (response.statusCode == 200) {
        SnackBarHelper.showSuccess(context, data['message'] ?? 'Email envoyé avec succès.');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VerificationCodePage(email: email),
          ),
        );
      } else {
        SnackBarHelper.showError(context, data['message'] ?? 'Erreur lors de l envoi.');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('❌ [ForgetPassword] Exception: $e');

      SnackBarHelper.showError(context, 'Erreur de connexion: ${e.toString()}');
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.emailAddress,
    int? maxLength,
    bool obscureText = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Ce champ est requis';
          }
          if (label == 'Adresse e-mail' &&
              !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
            return 'Entrez une adresse e-mail valide';
          }
          if (label == 'Code de vérification' && value.length != 6) {
            return 'Le code doit contenir 6 chiffres';
          }
          if ((label == 'Mot de passe' || label == 'Répéter le mot de passe') && value.length < 8) {
            return 'Le mot de passe doit contenir au moins 8 caractères';
          }
          return null;
        },
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.deepPurple[300]),
          labelText: label,
          labelStyle: TextStyle(color: isDark ? theme.textTheme.bodyMedium?.color : Colors.grey),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          counterText: maxLength != null ? '' : null,
          hintText: maxLength != null ? '------' : null,
          hintStyle: maxLength != null ? TextStyle(color: Colors.grey[400]) : null,
        ),
        style: theme.textTheme.bodyLarge,
        keyboardType: keyboardType,
        maxLength: maxLength,
      ),
    );
  }

  Widget _buildElevatedButton({
    required VoidCallback onPressed,
    required String label,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        label: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: isDark ? null : Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 3,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? null : Colors.white,
            gradient: isDark
                ? const LinearGradient(
              colors: [Color(0xFF1A003D), Color(0xFF3C0D73)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
                : null,
          ),
          height: MediaQuery.of(context).size.height,
          child: SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.of(context).size.width * 0.06,
                    vertical: 16,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        Text(
                          'Récupérer votre mot de passe',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ) ??
                              TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Entrez votre adresse e-mail pour recevoir les instructions de réinitialisation',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark ? Colors.white70 : Colors.grey[600],
                          ) ??
                              TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white70 : Colors.grey[600],
                              ),
                        ),
                        const SizedBox(height: 24),
                        _buildTextField(
                          controller: _emailController,
                          label: 'Adresse e-mail',
                          icon: Icons.email_outlined,
                        ),
                        const SizedBox(height: 16),
                        _isLoading
                            ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.deepPurple,
                          ),
                        )
                            : _buildElevatedButton(
                          onPressed: _resetPassword,
                          label: 'Envoyer les instructions',
                          icon: Icons.send,
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Text(
                              'Retour à la connexion',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.deepPurple,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w500,
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
          ),
        ),
      ),
    );
  }
}

class VerificationCodePage extends StatefulWidget {
  final String email;

  const VerificationCodePage({super.key, required this.email});

  @override
  _VerificationCodePageState createState() => _VerificationCodePageState();
}

class _VerificationCodePageState extends State<VerificationCodePage> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _verifyCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final code = _codeController.text.trim();
    final url = Uri.parse('https://www.unistudious.com/password-verify-token-mobile');

    try {
      var request = http.MultipartRequest('POST', url);
      request.fields['token'] = code;

      final response = await request.send().timeout(const Duration(seconds: 30));
      final responseBody = await response.stream.bytesToString();
      final data = jsonDecode(responseBody);
      debugPrint('🔵 [VerificationCode] Response: $responseBody');

      setState(() {
        _isLoading = false;
      });

      if (response.statusCode == 200 && data['success'] == true) {
        SnackBarHelper.showSuccess(context, data['message'] ?? 'Code vérifié avec succès.');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResetPasswordPage(email: widget.email, token: code),
          ),
        );
      } else {
        SnackBarHelper.showError(context, data['message'] ?? 'Erreur lors de la vérification.');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('❌ [VerificationCode] Exception: $e');

      SnackBarHelper.showError(context, 'Erreur de connexion: ${e.toString()}');
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.number,
    int? maxLength,
    bool obscureText = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Ce champ est requis';
          }
          if (label == 'Code de vérification' && value.length != 6) {
            return 'Le code doit contenir 6 chiffres';
          }
          if ((label == 'Mot de passe' || label == 'Répéter le mot de passe') && value.length < 8) {
            return 'Le mot de passe doit contenir au moins 8 caractères';
          }
          return null;
        },
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.deepPurple[300]),
          labelText: label,
          labelStyle: TextStyle(color: isDark ? theme.textTheme.bodyMedium?.color : Colors.grey),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          counterText: maxLength != null ? '' : null,
          hintText: maxLength != null ? '------' : null,
          hintStyle: maxLength != null ? TextStyle(color: Colors.grey[400]) : null,
        ),
        style: theme.textTheme.bodyLarge,
        keyboardType: keyboardType,
        maxLength: maxLength,
      ),
    );
  }

  Widget _buildElevatedButton({
    required VoidCallback onPressed,
    required String label,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        label: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: isDark ? null : Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 3,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? null : Colors.white,
            gradient: isDark
                ? const LinearGradient(
              colors: [Color(0xFF1A003D), Color(0xFF3C0D73)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
                : null,
          ),
          height: MediaQuery.of(context).size.height,
          child: SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.of(context).size.width * 0.06,
                    vertical: 16,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        Text(
                          'Vérifier le code',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ) ??
                              TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Entrez le code à 6 chiffres envoyé à ${widget.email}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark ? Colors.white70 : Colors.grey[600],
                          ) ??
                              TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white70 : Colors.grey[600],
                              ),
                        ),
                        const SizedBox(height: 24),
                        _buildTextField(
                          controller: _codeController,
                          label: 'Code de vérification',
                          icon: Icons.vpn_key_outlined,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                        ),
                        const SizedBox(height: 16),
                        _isLoading
                            ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.deepPurple,
                          ),
                        )
                            : _buildElevatedButton(
                          onPressed: _verifyCode,
                          label: 'Vérifier le code',
                          icon: Icons.check,
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Text(
                              'Retour',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.deepPurple,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w500,
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
          ),
        ),
      ),
    );
  }
}

class ResetPasswordPage extends StatefulWidget {
  final String email;
  final String token;

  const ResetPasswordPage({super.key, required this.email, required this.token});

  @override
  _ResetPasswordPageState createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      SnackBarHelper.showError(context, 'Les mots de passe ne correspondent pas.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final password = _passwordController.text.trim();
    final url = Uri.parse('https://www.unistudious.com/rest-password-mobile');

    try {
      var request = http.MultipartRequest('POST', url);
      request.fields['token'] = widget.token;
      request.fields['password'] = password;
      request.fields['repeat_password'] = _confirmPasswordController.text.trim();

      final response = await request.send().timeout(const Duration(seconds: 30));
      final responseBody = await response.stream.bytesToString();
      final data = jsonDecode(responseBody);
      debugPrint('🔵 [ResetPassword] Response: $responseBody');

      setState(() {
        _isLoading = false;
      });

      if (response.statusCode == 200 && data['success'] == true) {
        SnackBarHelper.showSuccess(context, data['message'] ?? 'Mot de passe réinitialisé avec succès.');
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      } else {
        SnackBarHelper.showError(context, data['message'] ?? 'Erreur lors de la réinitialisation.');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('❌ [ResetPassword] Exception: $e');

      SnackBarHelper.showError(context, 'Erreur de connexion: ${e.toString()}');
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    bool obscureText = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Ce champ est requis';
          }
          if (label == 'Code de vérification' && value.length != 6) {
            return 'Le code doit contenir 6 chiffres';
          }
          if (label == 'Mot de passe' || label == 'Répéter le mot de passe') {
            if (value.length < 8) {
              return 'Le mot de passe doit contenir au moins 8 caractères';
            }
            if (!RegExp(r'\d').hasMatch(value)) {
              return 'Le mot de passe doit contenir au moins un chiffre';
            }
          }
          return null;
        },
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.deepPurple[300]),
          labelText: label,
          labelStyle: TextStyle(color: isDark ? theme.textTheme.bodyMedium?.color : Colors.grey),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          counterText: maxLength != null ? '' : null,
          hintText: maxLength != null ? '------' : null,
          hintStyle: maxLength != null ? TextStyle(color: Colors.grey[400]) : null,
        ),
        style: theme.textTheme.bodyLarge,
        keyboardType: keyboardType,
        maxLength: maxLength,
      ),
    );
  }

  Widget _buildElevatedButton({
    required VoidCallback onPressed,
    required String label,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        label: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: isDark ? null : Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 3,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? null : Colors.white,
            gradient: isDark
                ? const LinearGradient(
              colors: [Color(0xFF1A003D), Color(0xFF3C0D73)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
                : null,
          ),
          height: MediaQuery.of(context).size.height,
          child: SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.of(context).size.width * 0.06,
                    vertical: 16,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        Text(
                          'Réinitialiser le mot de passe',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ) ??
                              TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Entrez votre nouveau mot de passe',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark ? Colors.white70 : Colors.grey[600],
                          ) ??
                              TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white70 : Colors.grey[600],
                              ),
                        ),
                        const SizedBox(height: 24),
                        _buildTextField(
                          controller: _passwordController,
                          label: 'Mot de passe',
                          icon: Icons.lock_outline,
                          obscureText: true,
                        ),
                        _buildTextField(
                          controller: _confirmPasswordController,
                          label: 'Répéter le mot de passe',
                          icon: Icons.lock_outline,
                          obscureText: true,
                        ),
                        const SizedBox(height: 16),
                        _isLoading
                            ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.deepPurple,
                          ),
                        )
                            : _buildElevatedButton(
                          onPressed: _resetPassword,
                          label: 'Changer le mot de passe',
                          icon: Icons.check,
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Text(
                              'Retour',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.deepPurple,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w500,
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
          ),
        ),
      ),
    );
  }
}