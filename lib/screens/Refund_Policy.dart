import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class RefundPolicyPage extends StatelessWidget {
  const RefundPolicyPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "Politique de remboursement",
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
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Politique de remboursement pour Unistudious',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ) ?? TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Date d\'entrée en vigueur : 2024-11-21\nDernière mise à jour : 2024-11-21\n',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Chez Unistudious, nous nous efforçons de fournir les meilleurs services éducatifs et contenus à nos utilisateurs. '
                  'Nous comprenons que parfois les choses ne se passent pas comme prévu, et vous pourriez avoir besoin d\'un remboursement. '
                  'Cette politique de remboursement explique les conditions dans lesquelles les remboursements peuvent être émis.\n',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            PolicySection(
              number: 1,
              title: 'Accès gratuit pour les nouveaux utilisateurs',
              content:
              'Actuellement, nos services sont gratuits pour les nouveaux utilisateurs. Vous pouvez accéder à tous les cours, contenus et fonctionnalités sans être facturé. '
                  'Par conséquent, aucun remboursement n\'est nécessaire pour les services gratuits.',
            ),
            PolicySection(
              number: 2,
              title: 'Services payants (Mise en œuvre future)',
              content:
              'À l\'avenir, si nous introduisons des services payants, nous fournirons des informations détaillées sur les politiques de remboursement applicables à ces services au moment de l\'achat.',
            ),
            PolicySection(
              number: 3,
              title: 'Éligibilité aux remboursements (le cas échéant)',
              content:
              'Les remboursements seront émis sous ces conditions :\n\n'
                  '- Facturations erronées : Vous avez été facturé incorrectement.\n'
                  '- Service inutilisable : Le service est défectueux.\n'
                  '- Erreurs de facturation : Erreurs de facturation ou charges duplicées.\n\n'
                  'Les demandes de remboursement doivent être faites dans un délai de [7–14] jours suivant l\'achat. Après cette période, les remboursements peuvent ne pas être accordés sauf en cas de circonstances exceptionnelles.',
            ),
            PolicySection(
              number: 4,
              title: 'Services non remboursables',
              content:
              'Généralement non remboursables :\n\n'
                  '- Contenu déjà consulté ou téléchargé.\n'
                  '- Frais d\'abonnement pour le cycle de facturation en cours (vous pouvez annuler les renouvellements futurs).',
            ),
            PolicySection(
              number: 5,
              title: 'Comment demander un remboursement',
              content:
              'Si éligible :\n\n'
                  '- Contacter le support : Envoyez un e-mail à kernalsiprod@gmail.com.\n'
                  '- Fournir les détails : Numéro de commande, raison et documents.\n'
                  '- Examen : Notre équipe évaluera votre demande.\n'
                  '- Traitement : Les remboursements approuvés seront émis via votre mode de paiement original.',
            ),
            PolicySection(
              number: 6,
              title: 'Délai de traitement des remboursements',
              content:
              'Les remboursements seront traités dans un délai de [5–10] jours ouvrables. Le temps nécessaire pour que les fonds apparaissent peut dépendre de votre fournisseur de paiement.',
            ),
            PolicySection(
              number: 7,
              title: 'Modifications de la politique de remboursement',
              content:
              'Nous pouvons mettre à jour cette politique de remboursement à tout moment. Toute modification sera publiée ici avec une date mise à jour. '
                  'Vous serez informé si les modifications sont significatives.',
            ),
            PolicySection(
              number: 8,
              title: 'Contactez-nous',
              content:
              'Si vous avez des questions ou besoin d\'aide pour un remboursement :\n\n'
                  '📧 Email : kernalsiprod@gmail.com\n'
                  '📞 Téléphone : +216 92 637 249\n'
                  '📬 Adresse : 123 Av. de la République, Hammam Lif, Ben Arous, Tunisie',
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class PolicySection extends StatelessWidget {
  final int number;
  final String title;
  final String content;

  const PolicySection({
    Key? key,
    required this.number,
    required this.title,
    required this.content,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number. $title',
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.deepPurple[300] : Colors.deepPurple,
            ) ?? TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.deepPurple[300] : Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 16,
              color: isDark ? Colors.white70 : Colors.black87,
            ) ?? TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}