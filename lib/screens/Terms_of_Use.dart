import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Conditions d'utilisation",
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Conditions d'utilisation d'Unistudious",
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ) ?? TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Date d'entrée en vigueur : 21/11/2024",
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                "Dernière mise à jour : 21/11/2024",
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Text(
                "Bienvenue sur Unistudious, une plateforme d'apprentissage en ligne qui connecte les étudiants et les éducateurs pour des expériences d'apprentissage en ligne. En accédant ou en utilisant notre plateforme, vous acceptez de respecter les conditions d'utilisation suivantes. Veuillez les lire attentivement.",
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SectionTitle("1. Acceptation des conditions"),
              Text(
                "En accédant ou en utilisant Unistudious (la « Plateforme »), vous acceptez d'être lié par ces conditions d'utilisation, y compris les mises à jour ou modifications que nous pouvons apporter de temps à autre. Si vous n'acceptez pas ces conditions, vous devez vous abstenir d'utiliser nos services.",
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SectionTitle("2. Inscription des utilisateurs"),
              Text(
                "Pour accéder à certaines fonctionnalités de la Plateforme, vous devez créer un compte. En vous inscrivant, vous acceptez de fournir des informations précises, à jour et complètes. Vous êtes responsable de maintenir la confidentialité des informations de votre compte et de votre mot de passe. Vous êtes également responsable de toutes les activités qui se produisent sous votre compte.",
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SectionTitle("3. Utilisation de la Plateforme"),
              Text(
                "Vous acceptez d'utiliser la Plateforme uniquement à des fins légales et conformément à ces conditions d'utilisation. Il vous est interdit d'utiliser la Plateforme de manière à endommager, désactiver ou compromettre les services fournis par Unistudious. Cela inclut, sans s'y limiter :\n\n• Participer à des activités illégales\n• Télécharger ou distribuer du contenu nuisible\n• Violer les droits d'autrui, y compris les droits de propriété intellectuelle",
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SectionTitle("4. Contenu des utilisateurs"),
              Text(
                "Les utilisateurs peuvent télécharger du contenu tel que des supports de cours, des vidéos, des devoirs et autres ressources éducatives. En soumettant du contenu, vous accordez à Unistudious une licence non exclusive, mondiale et sans redevance pour utiliser, distribuer et afficher le contenu sur la Plateforme. Vous garantissez que vous disposez de tous les droits nécessaires sur le contenu que vous téléchargez et qu'il ne viole aucune loi ou droit de tiers.",
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SectionTitle("5. Conditions de paiement"),
              Text(
                "Unistudious propose des cours, services et fonctionnalités payants. En achetant un produit ou un service, vous acceptez de payer tous les frais applicables. Les paiements sont traités via des passerelles de paiement sécurisées tierces, et tous les paiements sont non remboursables sauf indication contraire explicite. Les prix des services peuvent changer avec le temps, mais ces changements vous seront communiqués.",
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SectionTitle("6. Propriété intellectuelle"),
              Text(
                "Tous les droits de propriété intellectuelle liés à la Plateforme, y compris, mais sans s'y limiter, le design, le contenu, les logiciels et les marques, appartiennent à Unistudious ou à ses concédants de licence. Vous ne pouvez pas copier, reproduire ou distribuer le contenu de la Plateforme sans notre consentement écrit préalable.",
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SectionTitle("7. Confidentialité et protection des données"),
              Text(
                "Votre utilisation de la Plateforme est régie par notre [Politique de confidentialité]. Nous respectons votre vie privée et nous engageons à protéger vos informations personnelles conformément aux lois applicables en matière de confidentialité.",
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SectionTitle("8. Disponibilité de la Plateforme"),
              Text(
                "Bien qu'Unistudious s'efforce de fournir un accès fiable à la Plateforme, nous ne pouvons garantir un service ininterrompu ou sans erreur. Nous nous réservons le droit de suspendre ou de mettre fin à l'accès à la Plateforme pour des raisons de maintenance, de mises à jour ou pour d'autres motifs nécessaires.",
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SectionTitle("9. Résiliation"),
              Text(
                "Nous pouvons suspendre ou résilier votre compte si vous violez ces conditions d'utilisation ou pour toute autre raison à notre discrétion. Vous pouvez également résilier votre compte en nous contactant ou via les paramètres de votre compte.",
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SectionTitle("10. Avertissements et limitation de responsabilité"),
              Text(
                "La Plateforme est fournie « telle quelle » et « selon disponibilité ». Nous ne faisons aucune représentation ou garantie d'aucune sorte, explicite ou implicite, concernant la disponibilité, l'exactitude ou la fiabilité de la Plateforme. Nous ne sommes pas responsables des dommages ou pertes pouvant résulter de votre utilisation de la Plateforme, sauf si la loi l'exige.",
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SectionTitle("11. Modifications"),
              Text(
                "Unistudious se réserve le droit de modifier ces conditions d'utilisation à tout moment. Toute modification sera publiée sur cette page, et les conditions révisées entreront en vigueur à la date de publication. Il est de votre responsabilité de consulter ces conditions périodiquement pour prendre connaissance des mises à jour.",
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SectionTitle("12. Modération du contenu et blocage d'utilisateurs"),
              Text(
                "Unistudious s'engage à maintenir un environnement sûr et respectueux pour tous les utilisateurs. Nous disposons de mécanismes de modération du contenu pour identifier et supprimer les contenus inappropriés, harcelants, violents ou autrement violant nos règles communautaires.\n\n"
                    "Les utilisateurs peuvent signaler du contenu inapproprié via les fonctionnalités de signalement disponibles dans l'application. Les utilisateurs peuvent également bloquer d'autres utilisateurs pour empêcher toute interaction future avec eux. Les signalements sont examinés dans les 24 heures et les actions appropriées sont prises, notamment la suppression de contenu, la suspension ou le bannissement d'utilisateurs selon la gravité de la violation.",
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SectionTitle("13. Informations de contact"),
              Text(
                "Si vous avez des questions ou des préoccupations concernant ces conditions d'utilisation, veuillez nous contacter à :\n\n"
                    '📧 Email : kemalsiprod@gmail.com\n'
                    '📞 Téléphone : +216 92 837 249\n'
                    '📬 Adresse : 123 Av. de la République, Hammam Lif, Ben Arous, Tunisie',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.deepPurple[300] : Colors.deepPurple,
      ) ?? TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.deepPurple[300] : Colors.deepPurple,
      ),
    );
  }
}