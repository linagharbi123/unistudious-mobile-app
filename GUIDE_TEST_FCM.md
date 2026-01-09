# 🔔 Guide de Test FCM (Firebase Cloud Messaging) pour iOS

## 📋 Prérequis

✅ Firebase est initialisé dans `main.dart`
✅ `GoogleService-Info.plist` est correctement configuré
✅ L'app iOS est ajoutée dans Firebase Console
✅ Push Notifications est activé dans Xcode

---

## 🚀 Étape 1 : Lancer l'app et obtenir le Token FCM

### Option A : Via la Console Flutter (Recommandé)

1. **Lance l'app sur un iPhone réel** (pas le simulateur) :
   ```bash
   cd /Users/ikrammkaissi/lina/project
   flutter run
   ```

2. **Accepte la permission de notification** quand elle apparaît :
   ```
   "Unistudious" aimerait vous envoyer des notifications
   [Ne pas autoriser]  [Autoriser] ← Clique ici
   ```

3. **Cherche le token FCM dans la console** :
   Tu devrais voir quelque chose comme :
   ```
   🔔 Statut de permission: AuthorizationStatus.authorized
   ✅ Permissions accordées
   📱 Token FCM: dK3jH9fL2mN5pQ8rT1vW4xY7zA0bC3dE6fG9hJ2kL5mN8pQ1rS4tU7vW0xY3zA6bC9dE2fG5hJ8kL1mN4pQ7rS0tU3vW6xY9zA2bC5dE8fG1hJ4kL7mN0pQ3rS6tU9vW2xY5zA8bC1dE4fG7hJ0kL3mN6pQ9rS2tU5vW8xY1zA4bC7dE0fG3hJ6kL9mN2pQ5rS8tU1vW4xY7zA0bC3dE6fG9hJ2kL5mN8pQ1rS4tU7vW0xY3zA6bC9dE2fG5hJ8kL1mN4pQ7rS0tU3vW6xY9zA2bC5dE8fG1hJ4kL7mN0pQ3rS6tU9vW2xY5zA8bC1dE4fG7hJ0kL3mN6pQ9rS2tU5vW8xY1zA4bC7dE0fG3hJ6kL9mN2pQ5rS8tU
   💡 Enregistre ce token sur ton serveur pour envoyer des notifications ciblées
   ```

4. **Copie le token** (tout le long texte après "Token FCM: ")

### Option B : Via la page Paramètres dans l'app

1. **Lance l'app** sur ton iPhone
2. **Va dans Paramètres** → **Push Notification Profile** (ou route `/push_notifications`)
3. **En haut de la page**, tu verras une carte "Token FCM (Debug)" avec :
   - Le token affiché (sélectionnable)
   - Un bouton **"Copier"** pour copier dans le presse-papier
   - Un bouton **"Actualiser"** pour recharger le token

---

## 📤 Étape 2 : Envoyer une notification de test depuis Firebase Console

### 2.1 Accéder à Cloud Messaging

1. Va sur [Firebase Console](https://console.firebase.google.com)
2. Sélectionne ton projet : **e-learning-1727876602993**
3. Dans le menu de gauche, clique sur **Cloud Messaging** (sous "Engage" ou "Grow")

### 2.2 Créer une nouvelle notification

1. Clique sur **"Envoyer votre premier message"** ou **"Nouvelle notification"** (bouton en haut à droite)

2. **Remplis le formulaire de notification** :
   - **Titre de la notification** : `Test iOS FCM`
   - **Texte de la notification** : `Ceci est un test de notification Firebase Cloud Messaging`
   - **Image** (optionnel) : Tu peux ajouter une image si tu veux

3. Clique sur **"Suivant"**

### 2.3 Choisir la cible

1. Sélectionne **"Token FCM"** (ou "Single device")
2. **Colle le token FCM** que tu as copié à l'étape 1
3. Clique sur **"Suivant"**

### 2.4 Programmer l'envoi (optionnel)

- **Envoi immédiat** : Clique directement sur **"Suivant"**
- **Envoi programmé** : Choisis une date et heure

### 2.5 Envoyer la notification

1. Clique sur **"Revoir"** pour vérifier les détails
2. Clique sur **"Publier"** ou **"Envoyer"**

---

## 🧪 Étape 3 : Tester les différents scénarios

### Test 1 : App en Foreground (ouverte)

**Scénario** : L'app est ouverte et visible à l'écran

1. **Garde l'app ouverte** sur l'écran principal
2. **Envoie une notification** depuis Firebase Console
3. **Résultat attendu** :
   - Dans la console Flutter, tu devrais voir :
     ```
     📨 Message reçu en foreground:
        Titre: Test iOS FCM
        Corps: Ceci est un test de notification Firebase Cloud Messaging
        Data: {}
     ```
   - ⚠️ **Note** : Sur iOS, les notifications en foreground ne s'affichent pas automatiquement dans la barre de notifications. Tu dois les gérer manuellement avec `flutter_local_notifications` si tu veux les afficher.

### Test 2 : App en Background (minimisée)

**Scénario** : L'app est minimisée mais toujours en cours d'exécution

1. **Minimise l'app** (appuie sur le bouton Home)
2. **Envoie une notification** depuis Firebase Console
3. **Résultat attendu** :
   - La notification apparaît dans la **barre de notifications iOS** (en haut de l'écran)
   - Quand tu **tapes dessus**, l'app s'ouvre
   - Dans la console Flutter, tu devrais voir :
     ```
     🔓 App ouverte depuis notification:
        Titre: Test iOS FCM
        Data: {}
     ```

### Test 3 : App fermée

**Scénario** : L'app est complètement fermée

1. **Ferme complètement l'app** :
   - Ouvre le multitâche (swipe vers le haut depuis le bas)
   - Swipe vers le haut sur l'app pour la fermer
2. **Envoie une notification** depuis Firebase Console
3. **Résultat attendu** :
   - La notification apparaît dans la **barre de notifications iOS**
   - Quand tu **tapes dessus**, l'app s'ouvre
   - Dans la console Flutter, tu devrais voir :
     ```
     🚀 App ouverte depuis notification (app fermée):
        Titre: Test iOS FCM
        Data: {}
     ```

---

## 🔍 Vérification des logs

Pour voir tous les logs en temps réel :

### Dans le terminal Flutter :
```bash
flutter run
```

### Dans Xcode :
1. Ouvre `ios/Runner.xcworkspace` dans Xcode
2. Va dans **View** → **Debug Area** → **Activate Console** (ou `Cmd + Shift + Y`)
3. Lance l'app depuis Xcode

### Logs à surveiller :

✅ **Au démarrage de l'app** :
```
🔔 Statut de permission: AuthorizationStatus.authorized
✅ Permissions accordées
📱 Token FCM: [ton token]
```

✅ **Quand une notification arrive en foreground** :
```
📨 Message reçu en foreground:
   Titre: [titre]
   Corps: [corps]
   Data: [données]
```

✅ **Quand l'app s'ouvre depuis une notification** :
```
🔓 App ouverte depuis notification:
   Titre: [titre]
   Data: [données]
```

✅ **Quand l'app s'ouvre depuis une notification (app fermée)** :
```
🚀 App ouverte depuis notification (app fermée):
   Titre: [titre]
   Data: [données]
```

---

## 🐛 Dépannage

### Le token FCM n'apparaît pas

**Vérifications** :
- ✅ `GoogleService-Info.plist` est bien dans `ios/Runner/`
- ✅ Push Notifications est activé dans Xcode (Signing & Capabilities)
- ✅ Background Modes → Remote notifications est coché
- ✅ La clé APNs est configurée dans Firebase
- ✅ L'app tourne sur un **appareil réel** (pas le simulateur)

### La permission n'apparaît pas

- Vérifie que c'est le **premier lancement** après l'installation
- Si l'utilisateur a déjà refusé, va dans **Réglages** → **Unistudious** → **Notifications** et active-les

### Les notifications ne sont pas reçues

**Vérifications** :
1. ✅ Le token FCM est valide (pas expiré)
2. ✅ La clé APNs est bien configurée dans Firebase
3. ✅ Le Bundle ID dans Firebase correspond à `com.unistudious.projet1v2.unique`
4. ✅ L'app est bien connectée à Internet
5. ✅ Les notifications ne sont pas désactivées dans les Réglages iOS

### Erreur "Invalid APNs credentials"

- Vérifie que la clé APNs (.p8) est bien uploadée dans Firebase
- Vérifie que le **Key ID** et **Team ID** sont corrects
- Assure-toi que la clé APNs a les bonnes permissions (Apple Push Notifications service)

---

## 📝 Notes importantes

1. **Simulateur iOS** : Les notifications push ne fonctionnent **PAS** sur le simulateur iOS. Tu dois tester sur un **appareil réel**.

2. **Token FCM** : Le token peut changer dans certains cas :
   - Réinstallation de l'app
   - Réinitialisation des données de l'app
   - Mise à jour de l'app (parfois)
   - Changement de périphérique

3. **Permissions** : Si l'utilisateur refuse les permissions, il peut les réactiver dans :
   - **Réglages** → **Unistudious** → **Notifications**

4. **Notifications en Foreground** : Par défaut, iOS n'affiche pas les notifications quand l'app est en foreground. Si tu veux les afficher, tu dois utiliser `flutter_local_notifications`.

---

## ✅ Checklist de test

- [ ] L'app démarre sans erreur
- [ ] La permission de notification apparaît et est acceptée
- [ ] Le token FCM est affiché dans les logs
- [ ] Le token FCM est visible dans la page Paramètres (mode debug)
- [ ] Une notification de test est envoyée depuis Firebase Console
- [ ] La notification est reçue quand l'app est en background
- [ ] La notification est reçue quand l'app est fermée
- [ ] L'app s'ouvre correctement quand on tape sur la notification
- [ ] Les logs montrent les bonnes informations

---

## 🎯 Prochaines étapes

Une fois que tout fonctionne :

1. **Enregistrer le token FCM sur ton serveur** pour envoyer des notifications ciblées
2. **Créer des notifications personnalisées** selon les données (`message.data`)
3. **Implémenter la navigation** vers des pages spécifiques quand l'utilisateur tape sur une notification
4. **Ajouter `flutter_local_notifications`** pour afficher les notifications en foreground

---

**Bon test ! 🚀**



