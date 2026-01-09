#!/bin/bash

# Script pour obtenir les SHA-1 fingerprints pour Google Sign-In

echo "=========================================="
echo "SHA-1 Fingerprints pour Google Sign-In"
echo "=========================================="
echo ""

echo "📱 SHA-1 pour Debug:"
cd "$(dirname "$0")"
./gradlew signingReport 2>&1 | grep -A 2 "Variant: debug" | grep "SHA1" | head -1

echo ""
echo "📱 SHA-1 pour Release:"
./gradlew signingReport 2>&1 | grep -A 2 "Variant: release" | grep "SHA1" | head -1

echo ""
echo "=========================================="
echo "Instructions:"
echo "1. Copiez les SHA-1 ci-dessus"
echo "2. Allez sur Google Cloud Console"
echo "3. APIs & Services > Credentials"
echo "4. Modifiez votre OAuth 2.0 Client ID Android"
echo "5. Ajoutez les SHA-1 dans 'SHA certificate fingerprints'"
echo "6. Sauvegardez et attendez 5-10 minutes"
echo "=========================================="

