package com.unistudious.projet1v2

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class MyFirebaseMessagingService : FirebaseMessagingService() {

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        
        Log.d(TAG, "═══════════════════════════════════════════════════════")
        Log.d(TAG, "📨 NOUVELLE NOTIFICATION REÇUE (onMessageReceived)")
        Log.d(TAG, "═══════════════════════════════════════════════════════")
        Log.d(TAG, "From: ${remoteMessage.from}")
        Log.d(TAG, "Message ID: ${remoteMessage.messageId}")
        Log.d(TAG, "Sent Time: ${remoteMessage.sentTime}")
        Log.d(TAG, "Message Type: ${remoteMessage.messageType}")
        Log.d(TAG, "Collapse Key: ${remoteMessage.collapseKey}")
        Log.d(TAG, "Ttl: ${remoteMessage.ttl}")
        Log.d(TAG, "Priority: ${remoteMessage.priority}")
        Log.d(TAG, "Original Priority: ${remoteMessage.originalPriority}")
        Log.d(TAG, "To: ${remoteMessage.to}")

        // Vérifier si le message contient des données
        Log.d(TAG, "--- DATA PAYLOAD ---")
        if (remoteMessage.data.isNotEmpty()) {
            Log.d(TAG, "Data payload size: ${remoteMessage.data.size}")
            remoteMessage.data.forEach { (key, value) ->
                Log.d(TAG, "  Data[$key] = $value")
            }
        } else {
            Log.d(TAG, "  Aucune donnée dans le message")
        }

        // Vérifier si le message contient une notification
        Log.d(TAG, "--- NOTIFICATION PAYLOAD ---")
        if (remoteMessage.notification != null) {
            val notification = remoteMessage.notification!!
            Log.d(TAG, "  Notification présente: OUI")
            Log.d(TAG, "  Title: ${notification.title}")
            Log.d(TAG, "  Body: ${notification.body}")
            Log.d(TAG, "  Tag: ${notification.tag}")
            Log.d(TAG, "  Sound: ${notification.sound}")
            Log.d(TAG, "  Click Action: ${notification.clickAction}")
            Log.d(TAG, "  Channel ID: ${notification.channelId}")
            Log.d(TAG, "  Image URL: ${notification.imageUrl}")
            Log.d(TAG, "  Icon: ${notification.icon}")
            Log.d(TAG, "  Color: ${notification.color}")
            
            val title = notification.title ?: "Notification"
            val body = notification.body ?: ""
            val clickAction = notification.clickAction
            Log.d(TAG, "✅ Affichage de la notification avec title: '$title' et body: '$body'")
            if (clickAction != null) {
                Log.d(TAG, "  📍 Click Action trouvé: '$clickAction'")
            }
            sendNotification(title, body, remoteMessage.data, clickAction)
        } else {
            Log.d(TAG, "  Notification présente: NON")
        }
        
        // Si le message ne contient que des données (data-only), créer une notification
        if (remoteMessage.notification == null && remoteMessage.data.isNotEmpty()) {
            Log.d(TAG, "--- TRAITEMENT DATA-ONLY ---")
            val title = remoteMessage.data["title"] 
                ?: remoteMessage.data["notification.title"]
                ?: remoteMessage.data["notification_title"]
                ?: "Notification"
            val body = remoteMessage.data["body"] 
                ?: remoteMessage.data["message"]
                ?: remoteMessage.data["notification.body"]
                ?: remoteMessage.data["notification_body"]
                ?: remoteMessage.data["text"]
                ?: "Nouvelle notification"
            Log.d(TAG, "📝 Data-only message détecté")
            Log.d(TAG, "  Title extrait: '$title'")
            Log.d(TAG, "  Body extrait: '$body'")
            Log.d(TAG, "✅ Création de notification depuis data-only")
            sendNotification(title, body, remoteMessage.data, null)
        } else if (remoteMessage.notification == null && remoteMessage.data.isEmpty()) {
            Log.w(TAG, "⚠️ Message reçu sans notification ET sans data - impossible d'afficher")
        }
        
        Log.d(TAG, "═══════════════════════════════════════════════════════")
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "Refreshed token: $token")
        // Envoyer le token au serveur si nécessaire
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = getString(R.string.default_notification_channel_id)
            val channelName = "Notifications"
            val channelDescription = "Notifications pour Unistudious"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = channelDescription
                enableLights(true)
                enableVibration(true)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
        }
    }

    private fun sendNotification(title: String, messageBody: String, data: Map<String, String> = emptyMap(), clickAction: String? = null) {
        try {
            Log.d(TAG, "🔔 DÉBUT sendNotification")
            Log.d(TAG, "  Title: '$title'")
            Log.d(TAG, "  Body: '$messageBody'")
            
            // Extraire le paramètre redirect ou location pour la navigation
            // Vérifier d'abord dans les données, puis éventuellement dans clickAction
            // Attention: pour Flutter, Firebase utilise souvent "FLUTTER_NOTIFICATION_CLICK"
            // comme click_action générique, qui NE DOIT PAS être utilisé comme route.
            val rawClickAction = data["click_action"] ?: clickAction
            val sanitizedClickAction = when (rawClickAction?.lowercase()) {
                // Valeur par défaut utilisée par Firebase pour Flutter : on l'ignore
                "flutter_notification_click" -> null
                else -> rawClickAction
            }

            val redirectPath = data["redirect"]
                ?: data["location"]
                ?: data["route"]
                ?: sanitizedClickAction  // Utiliser une vraie valeur métier en fallback
            if (redirectPath != null) {
                val source = when {
                    data["redirect"] != null -> "données (redirect)"
                    data["location"] != null -> "données (location)"
                    data["route"] != null -> "données (route)"
                    sanitizedClickAction != null -> "click_action"
                    else -> "inconnu"
                }
                Log.d(TAG, "  📍 Paramètre redirect/location trouvé dans $source: '$redirectPath'")
            } else {
                Log.d(TAG, "  ⚠️ Aucun paramètre redirect/location trouvé dans les données ni dans clickAction")
            }
            
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                // Passer le paramètre redirect/location dans l'Intent
                if (redirectPath != null) {
                    putExtra("redirect", redirectPath)
                    Log.d(TAG, "  ✅ Paramètre redirect ajouté à l'Intent: '$redirectPath'")
                }
                // Passer toutes les données de la notification pour que Flutter puisse les utiliser
                data.forEach { (key, value) ->
                    putExtra(key, value)
                }
            }
            Log.d(TAG, "  Intent créé: $intent")
            
            val pendingIntent = PendingIntent.getActivity(
                this, 0, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            Log.d(TAG, "  PendingIntent créé: $pendingIntent")

            val channelId = getString(R.string.default_notification_channel_id)
            Log.d(TAG, "  Channel ID: $channelId")
            
            val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            Log.d(TAG, "  Sound URI: $defaultSoundUri")
            
            val notificationBuilder = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(messageBody)
                .setAutoCancel(true)
                .setSound(defaultSoundUri)
                .setContentIntent(pendingIntent)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)

            Log.d(TAG, "  NotificationBuilder créé")

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            Log.d(TAG, "  NotificationManager obtenu: $notificationManager")
            
            // Vérifier si les notifications sont activées
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val areNotificationsEnabled = notificationManager.areNotificationsEnabled()
                Log.d(TAG, "  Notifications activées: $areNotificationsEnabled")
                if (!areNotificationsEnabled) {
                    Log.w(TAG, "⚠️ Les notifications sont désactivées pour cette application!")
                }
            }
            
            val notificationId = System.currentTimeMillis().toInt()
            val notification = notificationBuilder.build()
            Log.d(TAG, "  Notification construite, ID: $notificationId")
            
            notificationManager.notify(notificationId, notification)
            Log.d(TAG, "✅ Notification affichée avec succès!")
            Log.d(TAG, "  ID: $notificationId")
            Log.d(TAG, "  Titre: '$title'")
            Log.d(TAG, "  Message: '$messageBody'")
        } catch (e: Exception) {
            Log.e(TAG, "❌ ERREUR lors de l'affichage de la notification", e)
            Log.e(TAG, "  Exception: ${e.message}")
            Log.e(TAG, "  StackTrace: ${e.stackTraceToString()}")
        }
    }

    companion object {
        private const val TAG = "MyFirebaseMsgService"
    }
}
