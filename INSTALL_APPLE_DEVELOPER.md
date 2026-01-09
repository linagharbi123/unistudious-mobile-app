# Guide d'installation de l'application dans Apple Developer

## Prérequis

1. **Compte Apple Developer** actif (payant ou gratuit)
2. **Xcode** installé sur votre Mac
3. **Certificats et profils de provisioning** configurés

## Configuration du projet

### Bundle Identifier actuel
- **Bundle ID**: `com.unistudious.projet1v2.unique`
- **Nom de l'app**: Unistudious
- **Version**: 1.0.4+5

## Étapes d'installation

### Option 1 : Via Xcode (Recommandé)

1. **Ouvrir le projet dans Xcode**
   ```bash
   cd ios
   open Runner.xcworkspace
   ```

2. **Configurer le compte Apple Developer dans Xcode**
   - Dans Xcode, allez dans **Preferences** > **Accounts**
   - Cliquez sur **+** pour ajouter votre compte Apple Developer
   - Connectez-vous avec votre Apple ID

3. **Sélectionner l'équipe de développement**
   - Dans le navigateur de projet, sélectionnez le projet **Runner**
   - Dans l'onglet **Signing & Capabilities**
   - Cochez **Automatically manage signing**
   - Sélectionnez votre **Team** (équipe Apple Developer)

4. **Vérifier le Bundle Identifier**
   - Assurez-vous que le Bundle Identifier est `com.unistudious.projet1v2.unique`
   - Si nécessaire, modifiez-le dans **General** > **Identity**

5. **Archiver l'application**
   - Dans Xcode, sélectionnez **Product** > **Scheme** > **Runner**
   - Sélectionnez **Any iOS Device** ou un appareil physique connecté
   - Allez dans **Product** > **Archive**
   - Attendez que l'archive soit créée

6. **Distribuer l'application**
   - Dans la fenêtre **Organizer**, sélectionnez votre archive
   - Cliquez sur **Distribute App**
   - Choisissez une option :
     - **App Store Connect** : Pour publier sur l'App Store
     - **Ad Hoc** : Pour installer sur des appareils spécifiques
     - **Development** : Pour installer sur votre appareil de développement
     - **Enterprise** : Si vous avez un compte Enterprise

### Option 2 : Via ligne de commande Flutter

1. **Nettoyer le projet**
   ```bash
   flutter clean
   cd ios
   pod deintegrate
   pod install
   cd ..
   ```

2. **Construire l'application pour iOS**
   ```bash
   flutter build ios --release
   ```

3. **Ouvrir dans Xcode et archiver**
   ```bash
   cd ios
   open Runner.xcworkspace
   ```
   Puis suivez les étapes 2-6 de l'Option 1.

### Option 3 : Installation directe sur appareil (Development)

1. **Connecter votre iPhone/iPad** via USB

2. **Faire confiance à l'ordinateur** sur l'appareil iOS

3. **Sélectionner l'appareil dans Xcode**
   - Dans Xcode, sélectionnez votre appareil dans la liste des destinations

4. **Construire et installer**
   ```bash
   flutter run --release
   ```
   Ou dans Xcode : **Product** > **Run** (⌘R)

## Vérifications importantes

### Certificats et profils de provisioning

Si vous rencontrez des erreurs de signature :

1. **Vérifier les certificats dans Xcode**
   - **Preferences** > **Accounts** > Sélectionnez votre compte
   - Cliquez sur **Manage Certificates**
   - Vérifiez que vous avez un certificat de développement iOS valide

2. **Créer automatiquement les profils**
   - Xcode peut créer automatiquement les profils de provisioning
   - Assurez-vous que **Automatically manage signing** est coché

### Capabilities configurées

Votre application utilise :
- ✅ Sign in with Apple
- ✅ Google Sign-In
- ✅ Facebook Login
- ✅ Camera & Microphone (pour Jitsi Meet)
- ✅ Photo Library

Toutes ces capabilities doivent être activées dans votre compte Apple Developer.

## Commandes utiles

### Vérifier la configuration Flutter
```bash
flutter doctor -v
```

### Nettoyer et reconstruire
```bash
flutter clean
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..
flutter pub get
```

### Construire pour un appareil spécifique
```bash
flutter build ios --release --no-codesign
```

## Résolution de problèmes

### Erreur : "No signing certificate found"
- Vérifiez que votre compte Apple Developer est configuré dans Xcode
- Assurez-vous d'avoir un certificat de développement valide

### Erreur : "Provisioning profile not found"
- Cochez **Automatically manage signing** dans Xcode
- Xcode créera automatiquement le profil nécessaire

### Erreur : "Bundle identifier already in use"
- Changez le Bundle Identifier dans Xcode
- Ou utilisez un identifiant unique dans votre compte Apple Developer

## Support

Pour plus d'informations :
- [Documentation Apple Developer](https://developer.apple.com/documentation/)
- [Guide Flutter iOS](https://docs.flutter.dev/deployment/ios)

