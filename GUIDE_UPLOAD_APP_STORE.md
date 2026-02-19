# Guide : Upload sur App Store Connect

## Étape 1 : Build IPA (en cours)

```bash
flutter build ipa
```

L'IPA sera généré dans : `build/ios/ipa/`

---

## Étape 2 : Vérifier la build

Une fois le build terminé, vérifiez que le fichier existe :

```bash
ls -la build/ios/ipa/
```

Vous devriez voir un fichier `.ipa` (ex: `projet1.ipa`).

---

## Étape 3 : Upload via Transporter (méthode simple)

1. **Télécharger Transporter** depuis le Mac App Store (gratuit)
2. **Ouvrir Transporter** et vous connecter avec votre Apple ID Developer
3. **Faire glisser** le fichier `.ipa` dans la fenêtre
4. **Cliquer sur "Livrer"** (Deliver)
5. Attendre la fin de l'upload

---

## Étape 4 : Upload via Xcode (alternative)

1. **Ouvrir le projet iOS** dans Xcode :
   ```bash
   open ios/Runner.xcworkspace
   ```

2. **Sélectionner** : Product → Archive (ou Cmd+B puis Product → Archive)

3. Une fois l'archive créée, la fenêtre **Organizer** s'ouvre

4. **Sélectionner** l'archive et cliquer sur **"Distribute App"**

5. Choisir :
   - **App Store Connect** → Next
   - **Upload** → Next
   - **Automatic signing** (ou manuel si configuré) → Next
   - **Upload**

---

## Étape 5 : Sur App Store Connect (developer.apple.com)

1. Aller sur **https://appstoreconnect.apple.com**

2. **Ma App** → sélectionner **Unistudious**

3. La build apparaîtra dans **15-30 minutes** sous l'onglet **TestFlight** ou **+ Version iOS**

4. Pour une nouvelle version :
   - Cliquer sur **+ Version iOS**
   - Entrer **1.0.15** comme numéro de version
   - Sélectionner la build **17** (ou la dernière uploadée)
   - Remplir les notes de publication et soumettre pour révision

---

## Checklist avant upload

- [ ] Version `1.0.15+17` dans pubspec.yaml ✓
- [ ] Certificats Apple Developer valides
- [ ] Profil de provisioning App Store configuré
- [ ] Icône et captures d'écran à jour (si première soumission)

---

## En cas d'erreur

**"No valid code signing"** :
- Ouvrir `ios/Runner.xcworkspace` dans Xcode
- Sélectionner le projet → Signing & Capabilities
- Vérifier que le Team et Bundle ID sont corrects

**"Build already exists"** :
- Incrémenter le build number dans pubspec.yaml (ex: `1.0.15+18`)
