-keep class io.flutter.** { *; }
-keep class com.unistudious.projet1v2.** { *; }

# Facebook SDK
-keep class com.facebook.** { *; }
-dontwarn com.facebook.**

# Google Play Services / Sign-In
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Jitsi Meet SDK - Règles complètes pour éviter l'obfuscation
-keep class org.jitsi.** { *; }
-keep interface org.jitsi.** { *; }
-dontwarn org.jitsi.**

# WebRTC (utilisé par Jitsi)
-keep class org.webrtc.** { *; }
-keep interface org.webrtc.** { *; }
-dontwarn org.webrtc.**

# Classes natives WebRTC
-keepclasseswithmembernames class * {
    native <methods>;
}

# Réflexion utilisée par Jitsi/WebRTC
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes *Annotation*

# Classes utilisées via réflexion
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Gson (si utilisé par Jitsi)
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# React Native (Jitsi utilise React Native)
-keep class com.facebook.react.** { *; }
-dontwarn com.facebook.react.**

# WebView
-keep class com.reactnativecommunity.webview.** { *; }
-dontwarn com.reactnativecommunity.webview.**

# Image Picker / FileProvider
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**

# Share Plus provider
-keep class dev.fluttercommunity.plus.share.** { *; }
-dontwarn dev.fluttercommunity.plus.share.**

# OpenFile provider
-keep class com.crazecoder.openfile.** { *; }
-dontwarn com.crazecoder.openfile.**

# AndroidX startup / emoji / lifecycle / profile installer
-keep class androidx.startup.** { *; }
-keep class androidx.emoji2.** { *; }
-keep class androidx.lifecycle.** { *; }
-keep class androidx.profileinstaller.** { *; }
-dontwarn androidx.startup.**
-dontwarn androidx.emoji2.**
-dontwarn androidx.lifecycle.**
-dontwarn androidx.profileinstaller.**

# Media3 partial migration warnings
-dontwarn android.support.v4.media.**
-keep class androidx.media3.** { *; }

# Keep annotations
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes Exceptions

# Éviter la suppression de classes utilisées via réflexion
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Conserver les classes natives
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Conserver les classes Parcelable
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Conserver les classes Serializable
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Conserver les classes R (ressources)
-keepclassmembers class **.R$* {
    public static <fields>;
}

# Google Play Core (for Flutter deferred components - optional)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

