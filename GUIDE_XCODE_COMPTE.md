# Guide : Ajouter votre compte Apple Developer dans Xcode

## ✅ Configuration actuelle détectée

Votre projet a déjà une équipe configurée :
- **Team ID**: `RSA4WY6M6V`
- **Bundle ID**: `com.unistudious.projet1v2.unique`

## 📱 Méthode 1 : Via l'interface Xcode (Recommandé)

### Étape 1 : Ouvrir les Préférences
1. Dans Xcode, allez dans le menu : **Xcode** > **Settings** (ou **Preferences** sur macOS ancien)
   - Raccourci clavier : `⌘,` (Commande + Virgule)

### Étape 2 : Ajouter votre compte Apple Developer
1. Cliquez sur l'onglet **Accounts** (en haut de la fenêtre)
2. Cliquez sur le bouton **+** (en bas à gauche)
3. Sélectionnez **Apple ID**
4. Entrez votre **Apple ID** et votre **mot de passe**
5. Cliquez sur **Sign In**

### Étape 3 : Vérifier l'ajout
- Votre compte devrait apparaître dans la liste avec :
  - Votre nom/email
  - Le type de compte (Free, Individual, Organization, Enterprise)
  - L'équipe associée

## 🔧 Méthode 2 : Via les paramètres du projet

### Étape 1 : Sélectionner le projet
1. Dans le navigateur de projet (panneau de gauche), cliquez sur **Runner** (le projet bleu en haut)

### Étape 2 : Configurer la signature
1. Sélectionnez la cible **Runner** (sous TARGETS)
2. Allez dans l'onglet **Signing & Capabilities**
3. Cochez **Automatically manage signing**
4. Dans le menu déroulant **Team**, sélectionnez votre équipe Apple Developer
   - Si votre équipe n'apparaît pas, cliquez sur **Add Account...** pour ajouter votre compte

### Étape 3 : Vérifier la configuration
- Le **Bundle Identifier** devrait être : `com.unistudious.projet1v2.unique`
- Le **Team** devrait être sélectionné
- Un message vert devrait indiquer "Signing certificate is valid"

## 🚀 Méthode 3 : Via la ligne de commande (Avancé)

Si vous préférez configurer via la ligne de commande :

```bash
# Ouvrir Xcode avec le projet
cd ios
open Runner.xcworkspace

# Ensuite, utilisez l'interface Xcode pour ajouter le compte
# La ligne de commande ne peut pas ajouter des comptes Apple Developer directement
```

## ⚠️ Résolution de problèmes

### Problème : "No accounts with Apple ID"
**Solution** :
1. Vérifiez que vous avez un compte Apple Developer actif
2. Allez sur [developer.apple.com](https://developer.apple.com) et connectez-vous
3. Vérifiez que votre compte est actif et payé (si nécessaire)

### Problème : "Team not found"
**Solution** :
1. Vérifiez que vous êtes membre de l'équipe dans Apple Developer
2. Attendez quelques minutes après l'ajout du compte
3. Redémarrez Xcode si nécessaire

### Problème : "Signing certificate not found"
**Solution** :
1. Avec "Automatically manage signing" coché, Xcode créera automatiquement les certificats
2. Cliquez sur **Download Manual Profiles** si nécessaire
3. Vérifiez dans **Preferences** > **Accounts** > **Manage Certificates**

## 📋 Vérification rapide

Après avoir ajouté votre compte, vérifiez que :

- ✅ Votre compte apparaît dans **Xcode** > **Settings** > **Accounts**
- ✅ Votre équipe est sélectionnée dans **Signing & Capabilities**
- ✅ Le message "Signing certificate is valid" apparaît
- ✅ Le Bundle Identifier est correct : `com.unistudious.projet1v2.unique`

## 🎯 Prochaines étapes

Une fois le compte configuré :

1. **Construire pour un appareil** :
   - Connectez votre iPhone/iPad
   - Sélectionnez-le dans la liste des destinations
   - Appuyez sur **Run** (⌘R)

2. **Archiver pour distribution** :
   - Sélectionnez **Any iOS Device**
   - **Product** > **Archive**
   - Suivez l'assistant de distribution

## 📞 Support

Si vous rencontrez des problèmes :
- [Documentation Apple Developer](https://developer.apple.com/documentation/)
- [Guide Flutter iOS](https://docs.flutter.dev/deployment/ios)

