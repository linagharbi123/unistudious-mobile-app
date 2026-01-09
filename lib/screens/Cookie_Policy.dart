import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class CookiePolicyPage extends StatelessWidget {
  const CookiePolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "Politique de cookies",
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
                "Politique de cookies pour Unistudious",
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
              const SizedBox(height: 4),
              Text(
                "Date d'entrée en vigueur : 21/11/2024",
                style: TextStyle(
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
              Text(
                "Dernière mise à jour : 21/11/2024",
                style: TextStyle(
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Chez Unistudious, nous utilisons des cookies et des technologies similaires pour améliorer votre expérience utilisateur, analyser l'utilisation du site et proposer des contenus et publicités personnalisés. En accédant ou en utilisant notre plateforme, vous consentez à notre utilisation des cookies telle que décrite dans cette politique. Veuillez lire attentivement cette politique de cookies pour comprendre comment nous utilisons les cookies et comment vous pouvez les contrôler.",
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              _SectionTitle("1. Qu'est-ce qu'un cookie ?"),
              Text(
                "Les cookies sont de petits fichiers texte stockés sur votre appareil lorsque vous visitez un site web. Ils permettent aux sites de mémoriser vos actions et préférences au fil du temps. Les cookies peuvent être définis par le site que vous visitez ou par des services tiers.\n\n"
                    "Il existe différents types de cookies :\n\n"
                    "• Cookies internes : Ils sont définis par le site que vous visitez et ne sont accessibles que par ce site.\n"
                    "• Cookies tiers : Ils sont définis par des services ou organisations externes au site que vous visitez, tels que des fournisseurs d'analytique ou des réseaux publicitaires.",
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              _SectionTitle("2. Comment utilisons-nous les cookies ?"),
              Text(
                "Nous utilisons des cookies à diverses fins, notamment :\n\n"
                    "• Cookies essentiels : Nécessaires au fonctionnement de base, comme mémoriser les détails de connexion ou les préférences de session.\n"
                    "• Cookies de performance : Collectent des données sur la manière dont les visiteurs utilisent notre plateforme pour améliorer ses fonctionnalités et l'expérience utilisateur.\n"
                    "• Cookies fonctionnels : Mémorisent vos préférences, comme la langue ou les paramètres de compte.\n"
                    "• Cookies publicitaires : Affichent des publicités pertinentes en fonction de votre comportement de navigation et de vos centres d'intérêt.",
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              _SectionTitle("3. Quels cookies utilisons-nous System: Nous utilisons ?"),
                Text(
                "Voici des exemples de cookies que nous pouvons utiliser :\n\n"
                "• Cookies de session : Cookies temporaires supprimés après la fermeture du navigateur, utilisés pour mémoriser les actions pendant une session.\n"
                "• Cookies persistants : Restent sur votre appareil pendant une certaine période et nous aident à reconnaître les utilisateurs récurrents.\n"
                "• Cookies tiers : Provenant de services comme Google Analytics pour l'analyse de l'utilisation du site et la publicité ciblée.\n"
                "• Cookies publicitaires : Suivent l'activité sur notre plateforme et d'autres sites web pour afficher des publicités pertinentes.",
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              _SectionTitle("4. Comment contrôler les cookies ?"),
              Text(
                "Vous avez des options pour contrôler les cookies :\n\n"
                    "• Paramètres du navigateur : Gérez les préférences de cookies via votre navigateur. Leur désactivation peut affecter les fonctionnalités de la plateforme.\n"
                    "• Bannière de consentement aux cookies : Choisissez 'Accepter' ou 'Gérer les paramètres' lors de votre première visite sur notre plateforme.\n"
                    "• Outils de désactivation tiers : Des services comme www.youronlinechoices.com ou www.allaboutcookies.org permettent la gestion et la désactivation des cookies.",
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              _SectionTitle("5. Modifications de cette politique de cookies"),
              Text(
                "Nous pouvons mettre à jour cette politique de cookies pour refléter les changements dans nos pratiques ou pour des raisons légales et opérationnelles. Lors d'une mise à jour, nous modifierons la date de 'Dernière mise à jour'. Veuillez consulter cette politique régulièrement.",
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              _SectionTitle("6. Contactez-nous"),
              Text(
                "Si vous avez des questions concernant notre utilisation des cookies ou cette politique de cookies, veuillez nous contacter :\n\n"
                    "📧 Email : kernalsiprod@gmail.com\n"
                    "📞 Téléphone : +216 92 637 249\n"
                    "📬 Adresse postale : 123 Av. de la République Hammam Lif, Ben Arous, Tunisie",
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
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
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.deepPurple[200] : Colors.deepPurple,
      ),
    );
  }
}