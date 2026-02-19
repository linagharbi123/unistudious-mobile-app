import UIKit
import Flutter
//import FacebookCore // Ajout pour le SDK Facebook
import FBSDKCoreKit
import UserNotifications
import os.log


@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    print("═══════════════════════════════════════════════════════")
    print("🍎 iOS AppDelegate - didFinishLaunchingWithOptions")
    print("═══════════════════════════════════════════════════════")
    
    // Initialisation du SDK Facebook
    ApplicationDelegate.shared.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
    
    // Configurer le delegate pour les notifications en foreground
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      print("✅ UNUserNotificationCenter delegate configuré")
    }
    
    // Vérifier les options de lancement pour les notifications
    if let notification = launchOptions?[.remoteNotification] as? [String: Any] {
      print("📱 App lancée depuis une notification")
      print("  Notification data: \(notification)")
      
      // Extraire le paramètre redirect si présent
      let redirectPath = notification["redirect"] as? String ?? 
                        notification["location"] as? String ?? 
                        notification["route"] as? String
      
      if let redirect = redirectPath {
        print("  📍 Paramètre redirect trouvé au lancement: '\(redirect)'")
        // Le canal de méthode sera configuré plus tard dans Flutter
        // et récupérera ce paramètre via getInitialMessage()
      }
    }
    
    // Initialisation des plugins Flutter
    GeneratedPluginRegistrant.register(with: self)
    print("✅ Plugins Flutter enregistrés")
    print("═══════════════════════════════════════════════════════")
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Présenter les notifications même quand l'app est en foreground
  @available(iOS 10.0, *)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    print("═══════════════════════════════════════════════════════")
    print("🍎 iOS - NOTIFICATION REÇUE EN FOREGROUND")
    print("═══════════════════════════════════════════════════════")
    print("Date: \(notification.date)")
    print("Identifier: \(notification.request.identifier)")
    
    let content = notification.request.content
    print("--- CONTENU DE LA NOTIFICATION ---")
    print("  Title: \(content.title)")
    print("  Body: \(content.body)")
    print("  Subtitle: \(content.subtitle)")
    print("  Badge: \(content.badge?.intValue ?? 0)")
    print("  Sound: \(content.sound?.description ?? "none")")
    print("  Category Identifier: \(content.categoryIdentifier)")
    print("  Thread Identifier: \(content.threadIdentifier)")
    print("  Target Content ID: \(content.targetContentIdentifier ?? "none")")
    
    print("--- USER INFO ---")
    if content.userInfo.isEmpty {
      print("  ⚠️ Aucune donnée dans userInfo")
    } else {
      print("  Nombre de données: \(content.userInfo.count)")
      for (key, value) in content.userInfo {
        print("  \(key): \(value)")
      }
    }
    
    print("--- ATTACHMENTS ---")
    if content.attachments.isEmpty {
      print("  Aucune pièce jointe")
    } else {
      print("  Nombre de pièces jointes: \(content.attachments.count)")
      for (index, attachment) in content.attachments.enumerated() {
        print("  [\(index)] Identifier: \(attachment.identifier)")
        print("  [\(index)] URL: \(attachment.url)")
        print("  [\(index)] Type: \(attachment.type)")
      }
    }
    
    // Afficher la notification même en foreground
    let options: UNNotificationPresentationOptions
    if #available(iOS 14.0, *) {
      options = [.banner, .sound, .badge]
      print("✅ Options iOS 14+: banner, sound, badge")
    } else {
      options = [.alert, .sound, .badge]
      print("✅ Options iOS 10-13: alert, sound, badge")
    }
    
    print("═══════════════════════════════════════════════════════")
    completionHandler(options)
  }
  
  // Handler quand l'utilisateur clique sur une notification
  @available(iOS 10.0, *)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    print("═══════════════════════════════════════════════════════")
    print("🍎 iOS - NOTIFICATION OUVERTE PAR L'UTILISATEUR")
    print("═══════════════════════════════════════════════════════")
    print("Action Identifier: \(response.actionIdentifier)")
    print("Notification Identifier: \(response.notification.request.identifier)")
    
    let content = response.notification.request.content
    print("--- CONTENU ---")
    print("  Title: \(content.title)")
    print("  Body: \(content.body)")
    print("  UserInfo: \(content.userInfo)")
    
    // Extraire le paramètre redirect ou location du userInfo
    let userInfo = content.userInfo
    let redirectPath = userInfo["redirect"] as? String ?? 
                      userInfo["location"] as? String ?? 
                      userInfo["route"] as? String
    
    if let redirect = redirectPath {
      print("  📍 Paramètre redirect/location trouvé: '\(redirect)'")
      
      // Envoyer le paramètre redirect à Flutter via un canal de méthode
      // Attendre que Flutter soit initialisé
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        if let controller = self.window?.rootViewController as? FlutterViewController {
          let channel = FlutterMethodChannel(name: "com.unistudious.projet1v2/notification",
                                            binaryMessenger: controller.binaryMessenger)
          channel.invokeMethod("onNotificationOpened", arguments: ["redirect": redirect])
          print("  ✅ Paramètre redirect envoyé à Flutter: '\(redirect)'")
        } else {
          print("  ⚠️ Impossible d'obtenir FlutterViewController pour envoyer redirect, nouvelle tentative...")
          // Nouvelle tentative après un délai plus long
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let controller = self.window?.rootViewController as? FlutterViewController {
              let channel = FlutterMethodChannel(name: "com.unistudious.projet1v2/notification",
                                                binaryMessenger: controller.binaryMessenger)
              channel.invokeMethod("onNotificationOpened", arguments: ["redirect": redirect])
              print("  ✅ Paramètre redirect envoyé à Flutter (tentative 2): '\(redirect)'")
            }
          }
        }
      }
    } else {
      print("  ⚠️ Aucun paramètre redirect/location trouvé dans userInfo")
    }
    
    print("═══════════════════════════════════════════════════════")
    completionHandler()
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    // Gestion des URL par le SDK Facebook
    return ApplicationDelegate.shared.application(
      app,
      open: url,
      sourceApplication: options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String,
      annotation: options[UIApplication.OpenURLOptionsKey.annotation]
    )
  }
}