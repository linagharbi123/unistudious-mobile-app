import UIKit
import Flutter
//import FacebookCore // Ajout pour le SDK Facebook
import FBSDKCoreKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging
import os.log


@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Redirect en attente si Flutter n'est pas encore prêt (cold start)
  private var pendingNotificationArguments: [String: Any]?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    print("═══════════════════════════════════════════════════════")
    print("🍎 iOS AppDelegate - didFinishLaunchingWithOptions")
    print("═══════════════════════════════════════════════════════")
    
    // Initialiser Firebase dès le lancement (requis pour les notifications)
    FirebaseApp.configure()
    print("✅ Firebase configuré")
    
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
    
    // IMPORTANT: Enregistrer pour les notifications à distance (APNs)
    application.registerForRemoteNotifications()
    print("✅ registerForRemoteNotifications() appelé")
    
    // Cold start depuis une notification remote
    if let notification = launchOptions?[.remoteNotification] as? [String: Any] {
      print("📱 App lancée depuis une notification")
      print("  Notification data: \(notification)")
      if let args = Self.buildNotificationArguments(from: notification) {
        pendingNotificationArguments = args
        print("  📍 Redirect cold start mis en attente: \(args["redirect"] ?? "")")
      }
    }
    
    // Initialisation des plugins Flutter
    GeneratedPluginRegistrant.register(with: self)
    print("✅ Plugins Flutter enregistrés")
    
    // Configurer les canaux de méthode
    DispatchQueue.main.async {
      guard let controller = self.window?.rootViewController as? FlutterViewController else { return }
      
      // Canal pour ré-enregistrer les notifications (iOS) quand l'utilisateur accorde la permission
      let notificationChannel = FlutterMethodChannel(
        name: "com.unistudious.projet1v2/notifications",
        binaryMessenger: controller.binaryMessenger
      )
      notificationChannel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "registerForRemoteNotifications" {
          UIApplication.shared.registerForRemoteNotifications()
          print("✅ registerForRemoteNotifications() appelé depuis Flutter")
          result(true)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      
      // Canal pour ouvrir l'App Store
      let appStoreChannel = FlutterMethodChannel(
        name: "com.unistudious.projet1v2/appstore",
        binaryMessenger: controller.binaryMessenger
      )
      appStoreChannel.setMethodCallHandler { (call, result) in
        if call.method == "openAppStore" {
          guard let args = call.arguments as? [String: Any],
                let appId = args["appStoreId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "appStoreId required", details: nil))
            return
          }
          let urlString = "itms-apps://itunes.apple.com/app/id\(appId)"
          guard let url = URL(string: urlString) else {
            result(FlutterError(code: "INVALID_URL", message: "Invalid App Store URL", details: nil))
            return
          }
          UIApplication.shared.open(url) { success in
            result(success)
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      print("✅ Canal App Store enregistré")
      
      // Envoyer le redirect cold start une fois Flutter prêt
      self.flushPendingNotificationToFlutter(delay: 1.0)
    }
    print("═══════════════════════════════════════════════════════")
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  /// Extrait redirect/direction/location/route/action depuis userInfo FCM/APNs
  private static func extractRedirect(from userInfo: [AnyHashable: Any]) -> String? {
    let keys = ["redirect", "direction", "location", "route", "action"]
    for key in keys {
      if let value = userInfo[key] as? String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed.lowercased() != "flutter_notification_click" {
          return trimmed
        }
      }
    }
    // Parfois FCM nest les data sous "data" ou "gcm"
    if let data = userInfo["data"] as? [AnyHashable: Any] {
      return extractRedirect(from: data)
    }
    if let gcm = userInfo["gcm.notification.data"] as? String,
       let data = gcm.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [AnyHashable: Any] {
      return extractRedirect(from: json)
    }
    return nil
  }
  
  private static func buildNotificationArguments(from userInfo: [AnyHashable: Any]) -> [String: Any]? {
    guard let redirect = extractRedirect(from: userInfo) else { return nil }
    var arguments: [String: Any] = ["redirect": redirect]
    var dataDict: [String: String] = ["redirect": redirect]
    for (key, value) in userInfo {
      let keyStr = (key as? String) ?? String(describing: key)
      // Ignorer les clés système APNs / FCM volumineuses
      if keyStr == "aps" || keyStr.hasPrefix("google.") || keyStr.hasPrefix("gcm.") {
        continue
      }
      dataDict[keyStr] = (value as? String) ?? String(describing: value)
    }
    arguments["data"] = dataDict
    return arguments
  }
  
  private func sendNotificationArgumentsToFlutter(_ arguments: [String: Any], attempt: Int = 1) {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      if attempt < 5 {
        let delay = Double(attempt) * 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
          self?.sendNotificationArgumentsToFlutter(arguments, attempt: attempt + 1)
        }
      } else {
        pendingNotificationArguments = arguments
        print("  ⚠️ FlutterViewController indisponible, redirect mis en attente")
      }
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.unistudious.projet1v2/notification",
      binaryMessenger: controller.binaryMessenger
    )
    channel.invokeMethod("onNotificationOpened", arguments: arguments)
    print("  ✅ Redirect envoyé à Flutter: '\(arguments["redirect"] ?? "")' (tentative \(attempt))")
  }
  
  private func flushPendingNotificationToFlutter(delay: Double) {
    guard let args = pendingNotificationArguments else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self else { return }
      // Ne flush que si toujours en attente
      guard self.pendingNotificationArguments != nil else { return }
      self.pendingNotificationArguments = nil
      self.sendNotificationArgumentsToFlutter(args)
    }
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
    print("Identifier: \(notification.request.identifier)")
    
    let content = notification.request.content
    print("  Title: \(content.title)")
    print("  Body: \(content.body)")
    print("  UserInfo count: \(content.userInfo.count)")
    
    let options: UNNotificationPresentationOptions
    if #available(iOS 14.0, *) {
      options = [.banner, .sound, .badge]
    } else {
      options = [.alert, .sound, .badge]
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
    
    let userInfo = response.notification.request.content.userInfo
    print("  UserInfo: \(userInfo)")
    
    if let arguments = Self.buildNotificationArguments(from: userInfo) {
      print("  📍 Paramètre redirect trouvé: '\(arguments["redirect"] ?? "")'")
      // Court délai pour laisser Flutter/navigator se stabiliser
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
        self?.sendNotificationArgumentsToFlutter(arguments)
      }
    } else {
      print("  ⚠️ Aucun paramètre redirect/direction/location trouvé dans userInfo")
    }
    
    print("═══════════════════════════════════════════════════════")
    completionHandler()
  }

  // Transmettre le token APNs à Firebase pour que FCM puisse livrer les notifications
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    print("🍎 iOS - Token APNs reçu, transmission à Firebase...")
    Messaging.messaging().apnsToken = deviceToken
    print("✅ Token APNs transmis à Firebase Messaging")
  }
  
  // Gestion des erreurs d'enregistrement aux notifications
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("⚠️ iOS - Échec enregistrement notifications: \(error.localizedDescription)")
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
