#!/bin/bash

# Script pour préparer la construction iOS pour Apple Developer
# Usage: ./scripts/prepare_ios_build.sh

set -e

echo "🚀 Préparation de la construction iOS pour Apple Developer"
echo "=========================================================="
echo ""

# Vérifier que Flutter est installé
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter n'est pas installé. Veuillez installer Flutter d'abord."
    exit 1
fi

# Vérifier que CocoaPods est installé
if ! command -v pod &> /dev/null; then
    echo "❌ CocoaPods n'est pas installé. Installation..."
    sudo gem install cocoapods
fi

echo "📦 Nettoyage du projet..."
flutter clean

echo "📥 Récupération des dépendances Flutter..."
flutter pub get

echo "📦 Installation des pods iOS..."
cd ios
pod deintegrate 2>/dev/null || true
pod install
cd ..

echo "✅ Vérification de la configuration Flutter..."
flutter doctor

echo ""
echo "✅ Préparation terminée !"
echo ""
echo "📱 Prochaines étapes :"
echo "1. Ouvrez Xcode : cd ios && open Runner.xcworkspace"
echo "2. Configurez votre compte Apple Developer dans Xcode"
echo "3. Sélectionnez votre équipe dans Signing & Capabilities"
echo "4. Archivez l'application : Product > Archive"
echo ""


