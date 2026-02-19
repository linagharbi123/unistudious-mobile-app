import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class PrivacyPolicyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "Politique de confidentialité",
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
        padding: const EdgeInsets.all(16.0),
        child: Card(
          color: theme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Politique de confidentialité pour Unistudious",
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
                Text(
                  'Date d\'entrée en vigueur : 21 novembre 2024',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Dernière mise à jour : ${DateTime.now().day} ${['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'][DateTime.now().month - 1]} ${DateTime.now().year}',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Bienvenue chez Unistudious ! Votre vie privée est importante pour nous. Cette politique de confidentialité explique comment nous collectons, utilisons et protégeons vos informations personnelles lorsque vous utilisez notre site web, nos services et nos applications.',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '1. Informations que nous collectons',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ) ?? TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nous collectons les types d\'informations suivants :',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '1.1 Informations personnelles',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Nom',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Adresse e-mail',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Numéro de téléphone',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Détails de paiement (par exemple, adresse de facturation, informations de carte de crédit)',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '1.2 Informations non personnelles',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Type et version du navigateur',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Type de dispositif et système d\'exploitation',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Adresse IP et localisation géographique',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Données d\'utilisation (par exemple, pages visitées, temps passé sur le site)',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '1.3 Cookies et suivi',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ) ?? TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nous utilisons des cookies pour améliorer votre expérience. Pour plus de détails, consultez notre politique en matière de cookies.',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '2. Comment nous utilisons vos informations',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ) ?? TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vos informations sont utilisées pour :',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Fournir et améliorer nos services.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Traiter les paiements et les transactions.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Communiquer avec vous concernant les cours, les mises à jour et les promotions.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Personnaliser le contenu et les recommandations.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Assurer la sécurité et prévenir la fraude.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '3. Partage de vos informations',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ) ?? TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nous ne vendons pas vos informations personnelles. Cependant, nous pouvons partager vos données avec :',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Fournisseurs de services : Pour le traitement des paiements, les services d\'e-mail et les analyses.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Autorités légales : Lorsque cela est requis par la loi ou pour faire respecter nos termes et politiques.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Transferts d\'entreprise : En cas de fusion, d\'acquisition ou de vente d\'actifs.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '4. Vos droits en matière de confidentialité',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ) ?? TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vous avez le droit de :',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Accéder, corriger ou supprimer vos données personnelles.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Vous désinscrire des communications marketing.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Restreindre ou vous opposer au traitement des données.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Demander la portabilité des données.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pour exercer vos droits, contactez-nous à kemalsiprod@gmail.com.',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '5. Sécurité des données',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ) ?? TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nous mettons en place des mesures de sécurité robustes pour protéger vos données, notamment :',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Chiffrement SSL pour la transmission des données.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Audits de sécurité réguliers.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Accès restreint aux informations sensibles.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cependant, aucun système n\'est totalement sécurisé. Nous vous encourageons à protéger vos identifiants de compte.',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '6. Conservation des données',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ) ?? TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nous conservons vos données aussi longtemps que nécessaire pour :',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Remplir les objectifs décrits dans cette politique.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Respecter les obligations légales.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Résoudre les litiges et faire respecter nos accords.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '7. Cookies et suivi',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ) ?? TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nous utilisons des cookies et des technologies similaires pour :',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Analyse et suivi des performances.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.deepPurple),
                  title: Text(
                    'Contenu et publicité personnalisés.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pour plus de détails, consultez notre politique en matière de cookies.',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '8. Liens vers des sites tiers',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ) ?? TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Notre site web peut inclure des liens vers des sites tiers. Nous ne sommes pas responsables de leurs pratiques en matière de confidentialité. Nous vous encourageons à consulter leurs politiques.',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '9. Modifications de cette politique',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ) ?? TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nous pouvons mettre à jour cette politique de confidentialité périodiquement. Les modifications seront publiées sur cette page avec la date de "Dernière mise à jour".',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '10. Contactez-nous',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ) ?? TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Si vous avez des questions ou des préoccupations concernant cette politique de confidentialité, contactez-nous à :',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                ListTile(
                  title: Text(
                    '📧 E-mail : kemalsiprod@gmail.com',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  title: Text(
                    '📞 Téléphone : +216 92 837 249',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ListTile(
                  title: Text(
                    '📬 Adresse postale : 123 Av. de la République, Hammam Lif, Ben Arous, Tunisie',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
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
}