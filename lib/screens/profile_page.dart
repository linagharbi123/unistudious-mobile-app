import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:html/parser.dart' show parse;
import 'package:intl/intl.dart';
import 'dart:developer' as developer;

import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/notification_icon_button.dart';

class ProfilePage extends StatefulWidget {
  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _birthPlaceController = TextEditingController();
  final _addressController = TextEditingController();
  final _aboutMeController = TextEditingController();
  String _gender = 'Select gender...';
  String? _initialUsername;
  bool _isLoading = false;

  final List<String> _genderOptions = ['Select gender...', 'Homme', 'Femme'];

  @override
  void initState() {
    super.initState();
    _checkAuthAndFetchData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _birthDateController.dispose();
    _birthPlaceController.dispose();
    _addressController.dispose();
    _aboutMeController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthAndFetchData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.isLoggedIn) {
      SnackBarHelper.showWarning(context, 'Veuillez vous connecter pour continuer.');
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    await _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      final socialMediaResponse = await authProvider.authenticatedRequest(
        'GET',
        '/api/profile-social-media',
      );

      if (socialMediaResponse.statusCode == 200) {
        final jsonResponse = jsonDecode(socialMediaResponse.body);
        final data = jsonResponse['data'] ?? {};

        final aboutMeHtml = data['aboutMe'] as String? ?? '';
        final document = parse(aboutMeHtml);
        final aboutMeText = document.body?.text ?? aboutMeHtml;

        setState(() {
          _aboutMeController.text = aboutMeText;
        });
      } else if (socialMediaResponse.statusCode == 401 || socialMediaResponse.statusCode == 403) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      final profileResponse = await authProvider.authenticatedRequest(
        'GET',
        '/api/show-profile',
      );

      if (profileResponse.statusCode == 200) {
        final jsonResponse = jsonDecode(profileResponse.body);
        final data = jsonResponse['data'][0] ?? {};
        developer.log('Profile API response: ${jsonEncode(jsonResponse)}', time: DateTime.now());

        // Convert birthDate to DD/MM/YYYY for UI, assuming server sends YY-MM-DD
        String birthDate = data['birthDate'] as String? ?? '';
        if (birthDate.isNotEmpty) {
          // Assume 03-03-08 means 2003-03-08 (adjust based on server logic)
          if (RegExp(r'^\d{2}-\d{2}-\d{2}$').hasMatch(birthDate)) {
            birthDate = '20$birthDate'; // Prepend "20" for YY-MM-DD
          }
          try {
            birthDate = DateFormat('dd/MM/yyyy').format(DateTime.parse(birthDate));
          } catch (e) {
            developer.log('Error parsing birthDate: $e', time: DateTime.now());
            birthDate = '';
          }
        }

        setState(() {
          _nameController.text = data['full_name'] as String? ?? '';
          _usernameController.text = data['username'] as String? ?? '';
          _initialUsername = _usernameController.text;
          _emailController.text = data['email'] as String? ?? '';
          _phoneController.text = data['phone_number']?.toString() ?? '';
          _birthDateController.text = birthDate;
          _birthPlaceController.text = data['birthPlace'] as String? ?? '';
          _gender = _mapGenderFromApi(data['gender']?.toString() ?? '');
          _addressController.text = data['address'] as String? ?? '';
        });

        final user = Provider.of<UserModel>(context, listen: false);
        user.updateUser(
          name: _nameController.text,
          username: _usernameController.text,
          email: _emailController.text,
          birthDate: _birthDateController.text,
          birthPlace: _birthPlaceController.text,
          gender: _gender,
          address: _addressController.text,
          aboutMe: _aboutMeController.text,
        );
      } else if (profileResponse.statusCode == 401 || profileResponse.statusCode == 403) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      SnackBarHelper.showError(context, 'Erreur lors du chargement des données : $e');
    }
  }

  String _mapGenderFromApi(String apiGender) {
    switch (apiGender.toLowerCase()) {
      case 'm':
      case 'male':
      case 'homme':
        return 'Homme';
      case 'f':
      case 'female':
      case 'femme':
        return 'Femme';
      default:
        return 'Select gender...';
    }
  }

  String _mapGenderToApi(String gender) {
    switch (gender) {
      case 'Homme':
        return 'M';
      case 'Femme':
        return 'F';
      default:
        return '';
    }
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return regex.hasMatch(email);
  }

  bool _isValidDateFormat(String? date) {
    if (date == null || date.isEmpty) return true;
    final regex = RegExp(r'^\d{2}/\d{2}/\d{4}$');
    if (!regex.hasMatch(date)) return false;

    try {
      final parts = date.split('/');
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      final parsedDate = DateTime(year, month, day);
      return parsedDate.day == day && parsedDate.month == month && parsedDate.year == year;
    } catch (e) {
      return false;
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) {
      final formattedDate = DateFormat('dd/MM/yyyy').format(picked);
      setState(() {
        _birthDateController.text = formattedDate;
      });
    }
  }

  Future<bool> _updateProfile() async {
    setState(() => _isLoading = true);

    if (!_formKey.currentState!.validate()) {
      setState(() => _isLoading = false);
      SnackBarHelper.showError(context, 'Veuillez corriger les erreurs dans le formulaire.');
      return false;
    }

    _formKey.currentState!.save();

    final isUsernameChanged = _usernameController.text != _initialUsername;

    final Map<String, dynamic> profileData = {
      'full_name': _nameController.text,
      'username': _usernameController.text,
      'email': _emailController.text,
      'phone_number': _phoneController.text.isEmpty ? null : int.tryParse(_phoneController.text),
      'birth_date': _birthDateController.text.isEmpty
          ? ''
          : DateFormat('yyyy-MM-dd').format(DateFormat('dd/MM/yyyy').parse(_birthDateController.text)),
      'birth_place': _birthPlaceController.text,
      'gender': _gender == 'Select gender...' ? '' : _mapGenderToApi(_gender),
      'location': _addressController.text,
    };

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    try {
      developer.log('Sending profile data: ${jsonEncode(profileData)}', time: DateTime.now());

      final profileResponse = await authProvider.authenticatedRequest(
        'PUT',
        '/api/update-profile',
        body: jsonEncode(profileData),
      );

      developer.log('Profile update response: ${profileResponse.statusCode} - ${profileResponse.body}',
          time: DateTime.now());

      if (profileResponse.statusCode == 200) {
        final jsonResponse = jsonDecode(profileResponse.body);
        String? newToken = jsonResponse['token'] ??
            jsonResponse['new_token'] ??
            jsonResponse['access_token'] ??
            profileResponse.headers['authorization']?.replaceFirst('Bearer ', '');
        if (newToken != null && newToken.isNotEmpty) {
          await authProvider.saveToken(newToken);
        }

        final user = Provider.of<UserModel>(context, listen: false);
        user.updateUser(
          name: _nameController.text,
          username: _usernameController.text,
          email: _emailController.text,
          birthDate: _birthDateController.text,
          birthPlace: _birthPlaceController.text,
          gender: _gender,
          address: _addressController.text,
          aboutMe: _aboutMeController.text,
        );

        final aboutMeRequest = http.MultipartRequest(
          'POST',
          Uri.parse('https://www.unistudious.com/api/social-media-update-about'),
        );

        aboutMeRequest.fields['about_me'] = _aboutMeController.text;

        // Utiliser le nouveau token s'il est disponible, sinon utiliser le token actuel
        final token = newToken ?? authProvider.currentToken;
        if (token != null && token.isNotEmpty) {
          aboutMeRequest.headers['Authorization'] = 'Bearer $token';
        } else {
          developer.log('Warning: No token available for About Me update', time: DateTime.now());
          setState(() => _isLoading = false);
          SnackBarHelper.showError(context, 'Erreur d\'authentification. Veuillez vous reconnecter.');
          Navigator.pushReplacementNamed(context, '/login');
          return false;
        }

        final aboutMeStreamResponse = await aboutMeRequest.send();
        final aboutMeResponse = await http.Response.fromStream(aboutMeStreamResponse);

        developer.log('About me update response: ${aboutMeResponse.statusCode} - ${aboutMeResponse.body}',
            time: DateTime.now());

        if (aboutMeResponse.statusCode == 200) {
          final aboutMeJson = jsonDecode(aboutMeResponse.body);
          if (aboutMeJson['status'] == 'success' &&
              aboutMeJson['message'] == 'About Me updated successfully!') {
            // Verify server state
            final profileResponseVerify = await authProvider.authenticatedRequest(
              'GET',
              '/api/show-profile',
            );
            if (profileResponseVerify.statusCode == 200) {
              final verifyData = jsonDecode(profileResponseVerify.body)['data'][0] ?? {};
              developer.log('Verify profile API response: ${jsonEncode(verifyData)}', time: DateTime.now());

              // Convert sent birth_date to compare with server birthDate
              String sentBirthDate = profileData['birth_date'];
              String serverBirthDate = verifyData['birthDate'] ?? '';
              if (RegExp(r'^\d{2}-\d{2}-\d{2}$').hasMatch(serverBirthDate)) {
                serverBirthDate = '20$serverBirthDate'; // Adjust for YY-MM-DD
              }

              if (sentBirthDate != serverBirthDate || verifyData['birthPlace'] != profileData['birth_place']) {
                SnackBarHelper.showWarning(context, 'Attention : Date ou lieu de naissance non mis à jour sur le serveur.');
              } else {
                await _fetchProfileData();
              }
            }

            SnackBarHelper.showSuccess(context, 'Profil et À propos mis à jour avec succès !');

            if (isUsernameChanged) {
              await authProvider.logout();
              Navigator.pushReplacementNamed(context, '/login');
              setState(() => _isLoading = false);
              return false;
            }

            setState(() => _isLoading = false);
            return true;
          } else {
            setState(() => _isLoading = false);
            SnackBarHelper.showError(context, 'Erreur lors de la mise à jour de À propos : ${aboutMeJson['message']}');
            return false;
          }
        } else {
          setState(() => _isLoading = false);
          SnackBarHelper.showError(context, 'Erreur lors de la mise à jour de À propos : ${aboutMeResponse.statusCode}');
          return false;
        }
      } else {
        setState(() => _isLoading = false);
        final errorResponse = jsonDecode(profileResponse.body);
        SnackBarHelper.showError(context, 'Erreur lors de la mise à jour du profil : ${errorResponse['message'] ?? profileResponse.statusCode}');
        return false;
      }
    } catch (e) {
      setState(() => _isLoading = false);
      developer.log('Error during profile update: $e', time: DateTime.now());
      SnackBarHelper.showError(context, 'Erreur : $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Profil',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ) ??
              const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
        ),
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
        actions: [
          const NotificationIconButton(),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                _buildTextField(
                  label: 'Nom complet',
                  controller: _nameController,
                  validator: (v) => v!.isEmpty ? 'Entrez votre nom complet' : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'Nom d\'utilisateur',
                  controller: _usernameController,
                  validator: (v) => v!.isEmpty ? 'Entrez votre nom d\'utilisateur' : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'Email',
                  controller: _emailController,
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Entrez votre email';
                    } else if (!_isValidEmail(v)) {
                      return 'Entrez un email valide';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'Numéro de téléphone',
                  controller: _phoneController,
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Entrez votre numéro de téléphone';
                    } else if (!RegExp(r'^[0-9]{8}$').hasMatch(v)) {
                      return 'Le numéro doit contenir exactement 8 chiffres';
                    }
                    return null;
                  },
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'Date de naissance',
                  controller: _birthDateController,
                  validator: (v) => v != null && v.isNotEmpty && !_isValidDateFormat(v)
                      ? 'Format invalide (DD/MM/YYYY)'
                      : null,
                  isDateField: true,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'Lieu de naissance',
                  controller: _birthPlaceController,
                ),
                const SizedBox(height: 16),
                Card(
                  color: theme.cardColor,
                  margin: const EdgeInsets.symmetric(vertical: 6.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: DropdownButtonFormField<String>(
                    value: _genderOptions.contains(_gender) ? _gender : 'Select gender...',
                    decoration: const InputDecoration(
                      labelText: 'Genre',
                      prefixIcon: Icon(Icons.person, color: Colors.deepPurple),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    items: _genderOptions
                        .map((label) => DropdownMenuItem(child: Text(label), value: label))
                        .toList(),
                    onChanged: (value) => setState(() => _gender = value!),
                    validator: null,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'Adresse',
                  controller: _addressController,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'À propos de moi',
                  controller: _aboutMeController,
                  validator: (v) => v != null && v.length > 500
                      ? 'La description ne doit pas dépasser 500 caractères'
                      : null,
                  maxLines: 4,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                    final result = await _updateProfile();
                    if (result) {
                      Navigator.pop(context, result);
                    }
                  },
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Mettre à jour les informations'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    bool isDateField = false,
  }) {
    final theme = Theme.of(context);
    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        readOnly: isDateField,
        onTap: isDateField ? () => _selectDate(context) : null,
        decoration: InputDecoration(
          counterText: maxLength != null ? '' : null,
          labelText: label,
          prefixIcon: Icon(
            label.contains('Email')
                ? Icons.email
                : label.contains('Nom')
                ? Icons.person
                : label.contains('téléphone')
                ? Icons.phone
                : label.contains('Date')
                ? Icons.calendar_today
                : label.contains('Adresse')
                ? Icons.location_on
                : label.contains('À propos')
                ? Icons.insert_drive_file
                : Icons.edit,
            color: Colors.deepPurple,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: theme.textTheme.bodyLarge,
        validator: validator,
        maxLines: maxLines,
      ),
    );
  }
}
