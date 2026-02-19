package com.unistudious.projet1v2

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.unistudious.projet1v2/notification"
    private val PLAY_STORE_CHANNEL = "com.unistudious.projet1v2/playstore"
    private var notificationChannel: MethodChannel? = null
    private var playStoreChannel: MethodChannel? = null
    private var pendingRedirect: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        notificationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        playStoreChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLAY_STORE_CHANNEL)
        
        // Configurer le handler pour ouvrir le Play Store
        playStoreChannel?.setMethodCallHandler { call, result ->
            if (call.method == "openPlayStore") {
                val packageName = call.argument<String>("packageName") ?: "com.unistudious.projet1v2"
                try {
                    // Essayer d'abord avec market://
                    try {
                        val marketIntent = Intent(Intent.ACTION_VIEW).apply {
                            data = Uri.parse("market://details?id=$packageName")
                            setPackage("com.android.vending")
                        }
                        startActivity(marketIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        // Si market:// échoue, utiliser le format web
                        val webIntent = Intent(Intent.ACTION_VIEW).apply {
                            data = Uri.parse("https://play.google.com/store/apps/details?id=$packageName")
                        }
                        startActivity(webIntent)
                        result.success(true)
                    }
                } catch (e: Exception) {
                    result.error("UNAVAILABLE", "Impossible d'ouvrir le Play Store", e.message)
                }
            } else {
                result.notImplemented()
            }
        }
        
        // Envoyer le redirect en attente si disponible
        pendingRedirect?.let { redirect ->
            sendRedirectToFlutter(redirect)
            pendingRedirect = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Ne pas gérer l'intent ici car configureFlutterEngine n'a pas encore été appelé
        // Il sera géré dans onResume après que Flutter soit initialisé
    }

    override fun onResume() {
        super.onResume()
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        
        // Vérifier si l'Intent provient d'une notification
        val redirect = intent.getStringExtra("redirect")
        if (redirect != null) {
            if (notificationChannel != null) {
                // Envoyer immédiatement si le canal est disponible
                sendRedirectToFlutter(redirect)
            } else {
                // Stocker pour l'envoyer plus tard
                pendingRedirect = redirect
            }
        }
    }
    
    private fun sendRedirectToFlutter(redirect: String) {
        notificationChannel?.invokeMethod("onNotificationOpened", mapOf("redirect" to redirect))
    }
}



