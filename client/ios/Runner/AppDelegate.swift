import AVFoundation
import Flutter
import UIKit
import UserNotifications

// FlutterAppDelegate already conforms to UNUserNotificationCenterDelegate and
// implements willPresent (as a no-op), so this restates neither.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// The one pending idle reminder. Reusing the identifier means scheduling
  /// again replaces it rather than stacking up a queue of them.
  private static let idleReminderId = "forma.workout_idle"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Without a delegate iOS drops notifications that come due while the app is
    // in the foreground — and a workout left open on the bench is exactly that
    // case. No plugin here claims the delegate, so taking it is safe.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerAudioSessionChannel(engineBridge.pluginRegistry)
    registerReminderChannel(engineBridge.pluginRegistry)
  }

  /// Show the reminder even when the app is frontmost. The whole point is that
  /// the screen has been sitting untouched, which may well mean untouched and
  /// visible.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  /// Schedules the "still running" reminder for a workout in progress.
  ///
  /// A Dart `Timer` cannot do this job: iOS suspends the app soon after it goes
  /// to the background — which is where a forgotten workout spends its idle
  /// half hour — and a suspended isolate runs nothing. Handing the fire time to
  /// `UNUserNotificationCenter` means the system delivers it whether the app is
  /// foreground, suspended or terminated.
  private func registerReminderChannel(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "FormaReminders") else { return }
    let channel = FlutterMethodChannel(
      name: "forma/reminders", binaryMessenger: registrar.messenger())
    let center = UNUserNotificationCenter.current()

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestPermission":
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
          if let error {
            result(
              FlutterError(
                code: "permission_failed",
                message: "Could not ask for notification permission: \(error)", details: nil))
          } else {
            result(granted)
          }
        }

      case "hasPermission":
        center.getNotificationSettings { settings in
          switch settings.authorizationStatus {
          case .authorized, .provisional, .ephemeral:
            result(true)
          default:
            result(false)
          }
        }

      case "schedule":
        guard let args = call.arguments as? [String: Any],
          let seconds = args["seconds"] as? Double,
          let title = args["title"] as? String,
          let body = args["body"] as? String, seconds > 0
        else {
          result(
            FlutterError(
              code: "bad_arguments", message: "schedule needs seconds > 0, title and body",
              details: nil))
          return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
          identifier: AppDelegate.idleReminderId,
          content: content,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        // Replacing the pending request is what makes each interaction push the
        // reminder out another half hour.
        center.removePendingNotificationRequests(withIdentifiers: [AppDelegate.idleReminderId])
        center.add(request) { error in
          if let error {
            result(
              FlutterError(
                code: "schedule_failed", message: "Could not schedule the reminder: \(error)",
                details: nil))
          } else {
            result(true)
          }
        }

      case "cancel":
        center.removePendingNotificationRequests(withIdentifiers: [AppDelegate.idleReminderId])
        // Also clears one already sitting in Notification Centre, so finishing
        // a workout doesn't leave a stale "still in progress" behind it.
        center.removeDeliveredNotifications(withIdentifiers: [AppDelegate.idleReminderId])
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Lets Dart hand the audio session back after the rest chime.
  ///
  /// `audioplayers` never deactivates it: the one call it makes to
  /// `AVAudioSession.setActive` happens on completion while the player still
  /// reports `isPlaying`, so it re-activates instead. With a `duckOthers`
  /// category, an active session keeps the user's music turned down until iOS
  /// reclaims the session on its own — which is why the volume comes back only
  /// after backgrounding the app or waiting. This channel is the missing
  /// `setActive(false)`.
  private func registerAudioSessionChannel(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "FormaAudioSession") else { return }
    let channel = FlutterMethodChannel(
      name: "forma/audio_session", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "deactivate" else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        // notifyOthersOnDeactivation is what tells whatever was ducked that it
        // can come back up immediately rather than at the system's leisure.
        try AVAudioSession.sharedInstance().setActive(
          false, options: .notifyOthersOnDeactivation)
        result(true)
      } catch {
        // Most often AVAudioSessionErrorCodeIsBusy, when the tail of the chime
        // is still playing. The caller retries; a failure here costs nothing
        // but a few more seconds of ducking.
        result(
          FlutterError(
            code: "audio_session_busy",
            message: "Could not deactivate the audio session: \(error)",
            details: nil))
      }
    }
  }
}
