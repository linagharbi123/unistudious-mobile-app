package com.unistudious.projet1v2

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.unistudious.projet1v2/notification"
    private val PLAY_STORE_CHANNEL = "com.unistudious.projet1v2/playstore"
    private var notificationChannel: MethodChannel? = null
    private var playStoreChannel: MethodChannel? = null

    /** Redirect conservé jusqu'à consommation explicite par Flutter (cold start). */
    private var pendingRedirect: String? = null
    private var pendingData: Map<String, Any>? = null
    private var pendingConsumed = false

    /** Évite de retraiter le même Intent sticky à chaque onResume. */
    private var lastHandledIntentHash: Int? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        notificationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        playStoreChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLAY_STORE_CHANNEL)

        // Flutter peut récupérer le redirect cold start quand il est prêt
        notificationChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingNotification" -> {
                    val redirect = pendingRedirect
                    if (redirect != null && !pendingConsumed) {
                        val args = mutableMapOf<String, Any>("redirect" to redirect)
                        pendingData?.let { args["data"] = it }
                        Log.d(TAG, "getPendingNotification → $redirect")
                        result.success(args)
                    } else {
                        result.success(null)
                    }
                }
                "clearPendingNotification" -> {
                    clearPending()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        playStoreChannel?.setMethodCallHandler { call, result ->
            if (call.method == "openAppStore" || call.method == "openPlayStore") {
                val packageName = call.argument<String>("packageName") ?: "com.unistudious.projet1v2"
                try {
                    try {
                        val marketIntent = Intent(Intent.ACTION_VIEW).apply {
                            data = Uri.parse("market://details?id=$packageName")
                            setPackage("com.android.vending")
                        }
                        startActivity(marketIntent)
                        result.success(true)
                    } catch (e: Exception) {
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

        // Relancer le redirect en attente (Flutter listener peut être prêt maintenant)
        schedulePendingDelivery()
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Capturer l'intent dès le cold start (avant Flutter)
        handleIntent(intent, fromColdStart = true)
    }

    override fun onResume() {
        super.onResume()
        handleIntent(intent, fromColdStart = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        lastHandledIntentHash = null
        pendingConsumed = false
        handleIntent(intent, fromColdStart = false)
    }

    private fun extractRedirect(intent: Intent): String? {
        val candidates = listOf(
            intent.getStringExtra("redirect"),
            intent.getStringExtra("direction"),
            intent.getStringExtra("location"),
            intent.getStringExtra("route"),
            intent.getStringExtra("action"),
            intent.getStringExtra("click_action"),
        )
        for (value in candidates) {
            val trimmed = value?.trim().orEmpty()
            if (trimmed.isEmpty()) continue
            if (trimmed.equals("flutter_notification_click", ignoreCase = true)) {
                return "messagerie"
            }
            return trimmed
        }

        // Heuristique titre FCM (extras système au cold start)
        val title = (intent.getStringExtra("title")
            ?: intent.getStringExtra("gcm.notification.title")
            ?: intent.getStringExtra("gcm.n.title")
            ?: "").lowercase()
        if (title.contains("message") || title.contains("chat") || title.contains("msg")) {
            Log.d(TAG, "Fallback redirect messagerie via titre: $title")
            return "messagerie"
        }

        val messageId = intent.getStringExtra("google.message_id")
            ?: intent.getStringExtra("message_id")
        if (messageId != null) {
            Log.d(TAG, "Intent FCM détecté (message_id=$messageId) sans redirect explicite — laisser getInitialMessage Flutter")
        }
        return null
    }

    private fun handleIntent(intent: Intent?, fromColdStart: Boolean) {
        if (intent == null) return

        // Debug: voir tous les extras au cold start (clic notif app fermée)
        if (fromColdStart || intent.extras != null) {
            val keys = intent.extras?.keySet()?.joinToString() ?: "(aucun)"
            Log.d(TAG, "handleIntent coldStart=$fromColdStart extras=[$keys]")
        }

        val redirect = extractRedirect(intent) ?: return

        val intentHash = System.identityHashCode(intent) xor redirect.hashCode()
        if (lastHandledIntentHash == intentHash && pendingConsumed) {
            return
        }
        // Même Intent déjà capturé en pending non consommé → ok, on garde
        if (lastHandledIntentHash == intentHash && pendingRedirect != null && !pendingConsumed) {
            schedulePendingDelivery()
            return
        }
        lastHandledIntentHash = intentHash

        val dataMap = mutableMapOf<String, Any>()
        intent.extras?.let { extras ->
            for (key in extras.keySet()) {
                val value = extras.get(key) ?: continue
                dataMap[key] = value.toString()
            }
        }
        dataMap["redirect"] = redirect

        pendingRedirect = redirect
        pendingData = dataMap.toMap()
        pendingConsumed = false

        Log.d(TAG, "Notification intent capturé (coldStart=$fromColdStart): redirect=$redirect extras=${dataMap.keys}")

        // Ne pas supprimer click_action tout de suite : Flutter peut poller plus tard
        schedulePendingDelivery()
    }

    private fun schedulePendingDelivery() {
        if (pendingRedirect == null || pendingConsumed) return
        // Retries : le handler Dart n'est souvent pas prêt au tout premier onResume
        val delaysMs = longArrayOf(0L, 500L, 1000L, 2000L, 3500L)
        for (delay in delaysMs) {
            mainHandler.postDelayed({
                deliverPendingToFlutter()
            }, delay)
        }
    }

    private fun deliverPendingToFlutter() {
        val redirect = pendingRedirect ?: return
        if (pendingConsumed) return
        val channel = notificationChannel ?: return
        val args = mutableMapOf<String, Any>("redirect" to redirect)
        pendingData?.let { args["data"] = it }
        try {
            channel.invokeMethod("onNotificationOpened", args)
            Log.d(TAG, "onNotificationOpened envoyé à Flutter: $redirect")
        } catch (e: Exception) {
            Log.w(TAG, "Échec envoi onNotificationOpened: ${e.message}")
        }
    }

    private fun clearPending() {
        pendingRedirect = null
        pendingData = null
        pendingConsumed = true
        intent?.let { intent ->
            intent.removeExtra("redirect")
            intent.removeExtra("direction")
            intent.removeExtra("location")
            intent.removeExtra("route")
            intent.removeExtra("action")
            intent.removeExtra("click_action")
        }
        Log.d(TAG, "Pending notification cleared")
    }

    companion object {
        private const val TAG = "MainActivityNotif"
    }
}
