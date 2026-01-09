import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';

class PasswordAuthPage extends StatefulWidget {
  const PasswordAuthPage({super.key});

  @override
  State<PasswordAuthPage> createState() => _PasswordAuthPageState();
}

class _PasswordAuthPageState extends State<PasswordAuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _currentPassword = '********'; // Masked placeholder for current password
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Check authentication status
  Future<void> _checkAuth() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.isLoggedIn) {
      print('No token found in AuthProvider');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Veuillez vous connecter pour continuer.'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  // Update password via API
  Future<void> _updatePassword() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (!authProvider.isLoggedIn) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Veuillez vous connecter pour modifier le mot de passe.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        final response = await authProvider.authenticatedRequest(
          'PUT',
          '/api/update-password',
          body: jsonEncode({
            'old_password': _currentPasswordController.text,
            'new_password': _newPasswordController.text,
            'confirm_password': _confirmPasswordController.text,
          }),
        );

        setState(() {
          _isLoading = false;
        });

        // Check Content-Type to detect non-JSON responses
        final contentType = response.headers['content-type'];
        if (contentType == null || !contentType.contains('application/json')) {
          print('Non-JSON response received: ${response.body}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Erreur serveur : réponse inattendue (Code: ${response.statusCode}). Veuillez réessayer.'),
              backgroundColor: Colors.red,
            ),
          );
          if (response.statusCode == 401 || response.statusCode == 403) {
            await authProvider.logout();
            Navigator.pushReplacementNamed(context, '/login');
          }
          return;
        }

        final jsonResponse = jsonDecode(response.body);

        if (response.statusCode == 200) {
          String? newToken = jsonResponse['token'] ??
              jsonResponse['new_token'] ??
              jsonResponse['access_token'] ??
              response.headers['authorization']?.replaceFirst('Bearer ', '');
          if (newToken != null && newToken.isNotEmpty) {
            await authProvider.saveToken(newToken);
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Mot de passe mis à jour avec succès ! Veuillez vous reconnecter.'),
              backgroundColor: Colors.green,
            ),
          );

          await authProvider.logout();
          Navigator.pushReplacementNamed(context, '/login');
        } else {
          final errorMessage = jsonResponse['error'] ??
              jsonResponse['message'] ??
              'Échec de la mise à jour du mot de passe';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$errorMessage (Code: ${response.statusCode})'),
              backgroundColor: Colors.red,
            ),
          );
          if (response.statusCode == 401 || response.statusCode == 403) {
            await authProvider.logout();
            Navigator.pushReplacementNamed(context, '/login');
          }
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        print('Error updating password: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de la mise à jour du mot de passe : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    bool obscureText = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(
            label.contains('Password') ? Icons.lock : Icons.edit,
            color: Colors.deepPurple,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
        ),
        style: theme.textTheme.bodyLarge,
        validator: validator,
        obscureText: obscureText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Mot de passe et authentification',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ) ?? const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () {
            Navigator.pushNamed(context, '/parametres');
          },
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
      body: Container(
        color: theme.scaffoldBackgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const SizedBox(height: 16),
              _buildTextField(
                label: 'Mot de passe actuel',
                controller: _currentPasswordController,
                obscureText: true,
                validator: (value) =>
                value!.isEmpty ? 'Entrez votre mot de passe actuel' : null,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                label: 'Nouveau mot de passe',
                controller: _newPasswordController,
                obscureText: true,
                validator: (value) {
                  if (value!.isEmpty) return 'Entrez un nouveau mot de passe';
                  if (value.length < 8) {
                    return 'Le mot de passe doit contenir au moins 8 caractères';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                label: 'Confirmer le nouveau mot de passe',
                controller: _confirmPasswordController,
                obscureText: true,
                validator: (value) {
                  if (value!.isEmpty) return 'Confirmez votre nouveau mot de passe';
                  if (value != _newPasswordController.text) {
                    return 'Les mots de passe ne correspondent pas';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _updatePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Mettre à jour le mot de passe'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}