import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class PaymentPolicyPage extends StatelessWidget {
  const PaymentPolicyPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "Politique de paiement",
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
              'Politique de paiement pour Unistudious',
              style: theme.textTheme.headlineMedium?.copyWith(
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
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ) ?? TextStyle(
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Chez Unistudious, nous nous engageons à offrir une expérience fluide et sécurisée à tous nos utilisateurs...',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black87,
              ) ?? TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            PolicySection(
              number: 1,
              title: 'Accès gratuit pour les nouveaux utilisateurs',
              content:
              'Nous offrons un accès gratuit à tous nos services pour les nouveaux utilisateurs... toute modification concernant les tarifs et les services premium sera communiquée à l\'avance.',
            ),
            PolicySection(
              number: 2,
              title: 'Services payants à venir',
              content:
              'Bien que notre plateforme soit actuellement gratuite... une communication claire concernant toute nouvelle fonctionnalité payante, les tarifs et les cycles de facturation.',
            ),
            PolicySection(
              number: 3,
              title: 'Méthodes de paiement (le cas échéant)',
              content:
              'Une fois les services payants introduits, nous accepterons diverses méthodes de paiement, y compris :\n\n'
                  '- Cartes de crédit : Visa, MasterCard, American Express, etc.\n'
                  '- Cartes de débit : Visa, MasterCard, Maestro, etc.\n'
                  '- PayPal\n'
                  '- Virements bancaires\n'
                  '- Paiements en espèces : Disponibles dans les centres de service.',
            ),
            PolicySection(
              number: 4,
              title: 'Abonnement et renouvellement (le cas échéant)',
              content:
              'Pour tout futur service basé sur un abonnement... jusqu\'à la fin de votre cycle de facturation actuel.',
            ),
            PolicySection(
              number: 5,
              title: 'Sécurité des paiements (le cas échéant)',
              content:
              'Nous prenons la sécurité de vos informations de paiement très au sérieux... conforme aux normes de sécurité les plus élevées.',
            ),
            PolicySection(
              number: 6,
              title: 'Taxation (le cas échéant)',
              content:
              'Si applicable, des taxes (telles que la TVA) peuvent être ajoutées en fonction de votre localisation.',
            ),
            PolicySection(
              number: 7,
              title: 'Politique de remboursement (le cas échéant)',
              content:
              'Notre politique de remboursement sera clairement indiquée au moment de l\'achat... traitée via votre méthode de paiement initiale.',
            ),
            PolicySection(
              number: 8,
              title: 'Vérification des paiements',
              content:
              'Nous pouvons exiger des étapes de vérification (comme une pièce d\'identité ou des documents)... pour garantir transparence et exactitude.',
            ),
            PolicySection(
              number: 9,
              title: 'Modifications de la politique de paiement',
              content:
              'Nous pouvons mettre à jour ou modifier cette politique de paiement de temps à autre... communiquées à l\'avance.',
            ),
            PolicySection(
              number: 10,
              title: 'Nous contacter',
              content:
              'Si vous avez des questions, contactez-nous :\n\n'
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