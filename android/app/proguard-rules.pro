-keep class io.flutter.** { *; }
-keep class com.unistudious.projet1v2.** { *; }

# Facebook SDK
-keep class com.facebook.** { *; }
-dontwarn com.facebook.**

# Google Play Services / Sign-In
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Jitsi Meet SDK
-keep class org.jitsi.** { *; }
-dontwarn org.jitsi.**

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

# Google Play Core (for Flutter deferred components - optional)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

