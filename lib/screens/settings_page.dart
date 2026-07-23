import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/user_model.dart';
import '../widgets/sidebar.dart';
import '../providers/auth_provider.dart';
import '../models/bottom_navigation_provider.dart';
import 'profile_page.dart';
import 'privacy_policy_page.dart';
import 'Terms_of_Use.dart';
import 'Cookie_Policy.dart';
import 'Payment_Policy.dart';
import 'Refund_Policy.dart';
import 'push_notification_profile_page.dart';
import 'password_auth_page.dart';
import 'delete_account_page.dart';
import 'theme_customization_page.dart';
import 'blocked_users_page.dart';
import 'notifications_list_page.dart';
import '../providers/notifications_list_provider.dart';
import '../widgets/notification_icon_button.dart';
import '../services/tutorial_service.dart';
import '../utils/main_navigation_helper.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  void _showLogoutConfirmation(BuildContext context) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () {
              if (!mounted) return;
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              if (!mounted) return;
              Navigator.of(context).pop();
              _performLogout(context);
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  void _performLogout(BuildContext context) {
    try {
      Provider.of<UserModel>(context, listen: false).updateUser(
        name: '',
        email: '',
        imageUrl: '',
        hasActiveSession: false,
      );
      Provider.of<AuthProvider>(context, listen: false).logout();
      Provider.of<BottomNavigationProvider>(context, listen: false).updateIndex(0);
      Navigator.pushReplacementNamed(context, '/welcome');
    } catch (e) {
      // Erreur silencieuse
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Paramètres',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        centerTitle: true,
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
      drawer: AppSidebar(),
      body: Container(
        color: theme.scaffoldBackgroundColor,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // ── Compte ──────────────────────────────────────────
            _buildSectionTitle('Compte', theme),
            _buildMenuItem(
              icon: Icons.person,
              title: 'Profil et informations personnelles',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProfilePage()),
                );
              },
              theme: theme,
            ),

            // ── Notifications ───────────────────────────────────
            _buildSectionTitle('Notifications', theme),
            _buildMenuItem(
              icon: Icons.notifications,
              title: 'Notifications push',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PushNotificationProfilePage()),
                );
              },
              theme: theme,
            ),
            Consumer<NotificationsListProvider>(
              builder: (context, provider, child) {
                return _buildMenuItem(
                  icon: Icons.notifications_active,
                  title: 'Mes notifications',
                  badge: provider.unreadCount > 0 ? provider.unreadCount.toString() : null,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NotificationsListPage()),
                    );
                  },
                  theme: theme,
                );
              },
            ),

            // ── Apparence ───────────────────────────────────────
            _buildSectionTitle('Apparence', theme),
            _buildMenuItem(
              icon: Icons.color_lens,
              title: 'Thème et personnalisation',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ThemeCustomizationPage()),
                );
              },
              theme: theme,
            ),

            // ── Aide ────────────────────────────────────────────
            _buildSectionTitle('Aide', theme),
            _buildMenuItem(
              icon: Icons.school_outlined,
              title: 'Revoir le tutoriel',
              subtitle: 'Découvrir les fonctionnalités de l\'application',
              onTap: () async {
                await TutorialService.requestReplay();
                if (!context.mounted) return;
                MainNavigationHelper.navigateToTab(context, 0);
              },
              theme: theme,
            ),

            // ── Sécurité ────────────────────────────────────────
            _buildSectionTitle('Sécurité', theme),
            _buildMenuItem(
              icon: Icons.lock,
              title: 'Mot de passe et authentification',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PasswordAuthPage()),
                );
              },
              theme: theme,
            ),
            _buildMenuItem(
              icon: Icons.block,
              title: 'Utilisateurs bloqués',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BlockedUsersPage()),
                );
              },
              theme: theme,
            ),

            // ── Informations légales ────────────────────────────
            _buildSectionTitle('Informations légales', theme),
            _buildMenuItem(
              icon: Icons.security,
              title: 'Politique de confidentialité',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PrivacyPolicyPage()),
                );
              },
              theme: theme,
            ),
            _buildMenuItem(
              icon: Icons.description,
              title: 'Conditions d\'utilisation',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => TermsOfUsePage()),
                );
              },
              theme: theme,
            ),
            _buildMenuItem(
              icon: Icons.cookie,
              title: 'Politique de Cookies',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CookiePolicyPage()),
                );
              },
              theme: theme,
            ),
            _buildMenuItem(
              icon: Icons.payment,
              title: 'Politique de Paiement',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PaymentPolicyPage()),
                );
              },
              theme: theme,
            ),
            _buildMenuItem(
              icon: Icons.replay,
              title: 'Politique de Remboursement',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => RefundPolicyPage()),
                );
              },
              theme: theme,
            ),

            // ── Gestion du compte (actions sensibles en bas) ────
            _buildSectionTitle('Gestion du compte', theme),
            _buildMenuItem(
              icon: Icons.logout,
              iconColor: Colors.red,
              title: 'Déconnexion',
              textColor: Colors.red,
              onTap: () => _showLogoutConfirmation(context),
              theme: theme,
            ),
            _buildMenuItem(
              icon: Icons.delete_forever,
              iconColor: Colors.redAccent,
              title: 'Supprimer mon compte',
              subtitle:
                  'Suppression définitive du compte après vérification par e-mail',
              textColor: Colors.redAccent,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DeleteAccountPage(),
                  ),
                );
              },
              theme: theme,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.textTheme.bodyMedium?.color,
        ) ?? const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    Color? iconColor,
    required String title,
    String? subtitle,
    Color? textColor,
    VoidCallback? onTap,
    Widget? trailing,
    bool showChevron = true,
    String? badge,
    required ThemeData theme,
  }) {
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: theme.cardColor,
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, color: iconColor ?? theme.iconTheme.color),
        title: Text(
          title,
          style: TextStyle(
            color: textColor ?? (isDark ? Colors.white : Colors.black87),
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
          subtitle,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.grey[600],
          ),
        )
            : null,
        trailing: trailing ??
            (badge != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (showChevron) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: isDark ? Colors.white54 : Colors.grey[400]),
                      ],
                    ],
                  )
                : (showChevron
                    ? Icon(Icons.chevron_right, color: isDark ? Colors.white54 : Colors.grey[400])
                    : null)),
        onTap: onTap,
      ),
    );
  }
}