# Configuration Apple Sign-In

## Informations de configuration

Les valeurs suivantes sont configurées pour Apple Sign-In :

```
APPLE_CLIENT_ID=unistudious
APPLE_TEAM_ID=Z48JA9Z442
APPLE_KEY_ID=8HX8674V6A
APPLE_PRIVATE_KEY_PATH=%kernel.project_dir%/config/apple/AuthKey_8HX8674V6A.p8
```

## Fichier de clé privée

Le fichier de clé privée se trouve dans :
- **Chemin local du projet** : `config/apple/AuthKey_8HX8674V6A.p8`
- **Chemin backend (symfony)** : `%kernel.project_dir%/config/apple/AuthKey_8HX8674V6A.p8`

## Configuration iOS

La configuration iOS pour Apple Sign-In est déjà en place dans :
- `ios/Runner/Runner.entitlements` - contient `com.apple.developer.applesignin`

## Configuration backend

Ces valeurs doivent être configurées dans votre backend (probablement Symfony) pour :
- Vérifier les tokens Apple reçus de l'application mobile
- Générer des JWT Apple si nécessaire

## Notes importantes

⚠️ **Sécurité** : Le fichier `AuthKey_8HX8674V6A.p8` contient une clé privée sensible. Assurez-vous qu'il est :
- Exclu du contrôle de version (ajouté au `.gitignore`)
- Protégé sur le serveur backend
- Accessible uniquement aux processus backend autorisés


