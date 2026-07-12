import Flutter
import UIKit
import BackgroundTasks
import UserNotifications
import CoreLocation
import ActivityKit

private let backgroundRefreshIdentifier = "com.susu.kelivo.background-generation.refresh"
private let backgroundProcessingIdentifier = "com.susu.kelivo.background-generation.processing"

private func kelivoLocalized(_ key: String, fallback: String) -> String {
  NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "")
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let fileSaveHandler = NativeFileSaveHandler()
  private let backgroundGenerationHandler = IosBackgroundGenerationHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    backgroundGenerationHandler.registerBackgroundTasks()
    if let controller = window?.rootViewController as? FlutterViewController {
      let clipboardChannel = FlutterMethodChannel(name: "app.clipboard", binaryMessenger: controller.binaryMessenger)
      clipboardChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "getClipboardImages" {
          var paths: [String] = []
          if let image = UIPasteboard.general.image {
            if let data = image.pngData() ?? image.jpegData(compressionQuality: 0.95) {
              let tmp = NSTemporaryDirectory()
              let filename = "pasted_\(Int(Date().timeIntervalSince1970 * 1000)).png"
              let url = URL(fileURLWithPath: tmp).appendingPathComponent(filename)
              do {
                try data.write(to: url)
                paths.append(url.path)
              } catch {
                // ignore write error
              }
            }
          }
          result(paths)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      let fileSaveChannel = FlutterMethodChannel(name: "app.file_save", binaryMessenger: controller.binaryMessenger)
      fileSaveHandler.presentingViewController = controller
      fileSaveChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        guard call.method == "saveFileFromPath" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.fileSaveHandler.handle(call: call, result: result)
      }

      let iosBackgroundChannel = FlutterMethodChannel(name: "app.ios_background_generation", binaryMessenger: controller.binaryMessenger)
      iosBackgroundChannel.setMethodCallHandler { [weak self] call, result in
        self?.backgroundGenerationHandler.handle(call: call, result: result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class IosBackgroundGenerationHandler: NSObject, CLLocationManagerDelegate {
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var notificationsEnabled = false
  private var refreshEnabled = false
  private var locationTrackingRequested = false
  private var locationTrackingActive = false
  private var locationManager: CLLocationManager?
  private var pendingLocationAuthorizationResult: FlutterResult?
  private var liveActivity: Any?

  func registerBackgroundTasks() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundRefreshIdentifier, using: nil) { task in
      self.handleBackgroundTask(task)
    }
    BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundProcessingIdentifier, using: nil) { task in
      self.handleBackgroundTask(task)
    }
  }

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getStatus":
      getStatus(result: result)
    case "requestNotificationAuthorization":
      requestNotificationAuthorization(result: result)
    case "requestLocationAlwaysAuthorization", "requestLocationAuthorization":
      requestLocationAuthorization(result: result)
    case "setLocationTrackingEnabled":
      setLocationTrackingEnabled(arguments: call.arguments, result: result)
    case "openAppSettings":
      openAppSettings(result: result)
    case "openNotificationSettings":
      openNotificationSettings(result: result)
    case "start":
      start(arguments: call.arguments, result: result)
    case "update":
      update(arguments: call.arguments, result: result)
    case "finish":
      finish(arguments: call.arguments, result: result)
    case "cancel":
      cancel(arguments: call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    notificationsEnabled = args["notificationsEnabled"] as? Bool ?? false
    refreshEnabled = args["refreshEnabled"] as? Bool ?? false
    let liveActivityEnabled = args["liveActivityEnabled"] as? Bool ?? false
    let locationTrackingEnabled = args["locationTrackingEnabled"] as? Bool ?? false
    let title = args["title"] as? String ?? "Kelivo"
    let detail = args["detail"] as? String ?? ""
    let tokenCount = args["tokenCount"] as? Int ?? 0
    let tokenLabel = args["tokenLabel"] as? String ?? "\(tokenCount) tokens"
    let conversationId = args["conversationId"] as? String ?? UUID().uuidString

    beginBackgroundTask()
    if refreshEnabled { scheduleBackgroundTasks() }
    if locationTrackingEnabled {
      _ = startLocationTracking(requestAuthorization: false)
    }
    if liveActivityEnabled {
      startLiveActivity(taskId: conversationId, title: title, detail: detail, tokenCount: tokenCount, tokenLabel: tokenLabel)
    }
    result(true)
  }

  private func update(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    let detail = args["detail"] as? String ?? ""
    let tokenCount = args["tokenCount"] as? Int ?? 0
    let tokenLabel = args["tokenLabel"] as? String ?? "\(tokenCount) tokens"
    let conversationId = args["conversationId"] as? String ?? UUID().uuidString
    updateLiveActivity(detail: detail, tokenCount: tokenCount, tokenLabel: tokenLabel)
    result(true)
  }

  private func finish(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    let title = args["title"] as? String ?? "Kelivo"
    let detail = args["detail"] as? String ?? ""
    let success = args["success"] as? Bool ?? true
    if notificationsEnabled { showCompletionNotification(title: title, body: detail) }
    endLiveActivity(title: title, detail: detail, success: success)
    endBackgroundTask()
    resetGenerationOptions()
    result(true)
  }

  private func cancel(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    let detail = args["detail"] as? String ?? kelivoLocalized("ios_background_generation_cancelled_detail", fallback: "Generation stopped")
    endLiveActivity(title: "Kelivo", detail: detail, success: false)
    endBackgroundTask()
    resetGenerationOptions()
    result(true)
  }

  private func resetGenerationOptions() {
    notificationsEnabled = false
    refreshEnabled = false
    stopLocationTracking()
  }

  private func getStatus(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        result([
          "backgroundTaskActive": self.backgroundTask != .invalid,
          "notificationsAuthorized": settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
          "liveActivityAvailable": self.liveActivitiesAvailable(),
          "liveActivitiesEnabled": self.liveActivitiesAvailable(),
          "liveActivityActive": self.liveActivity != nil,
          "locationServicesEnabled": CLLocationManager.locationServicesEnabled(),
          "locationTrackingActive": self.locationTrackingActive,
          "locationAlwaysAuthorized": self.currentLocationAuthorization() == .authorizedAlways,
          "locationAuthorizationStatus": self.locationAuthorizationString(),
          "locationAuthorization": self.locationAuthorizationString(),
        ])
      }
    }
  }

  private func requestNotificationAuthorization(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      DispatchQueue.main.async { result(granted) }
    }
  }

  private func requestLocationAuthorization(result: @escaping FlutterResult) {
    guard CLLocationManager.locationServicesEnabled() else {
      result(false)
      return
    }

    let manager = ensureLocationManager()
    let status = currentLocationAuthorization()
    if status == .authorizedAlways {
      result(true)
      return
    }
    if status == .denied || status == .restricted {
      result(false)
      return
    }
    if pendingLocationAuthorizationResult != nil {
      result(false)
      return
    }

    pendingLocationAuthorizationResult = result
    manager.requestAlwaysAuthorization()
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
      self?.finishPendingLocationAuthorizationIfNeeded()
    }
  }

  private func setLocationTrackingEnabled(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    let enabled = args["enabled"] as? Bool ?? false
    if enabled {
      let active = startLocationTracking(requestAuthorization: false)
      result(active)
    } else {
      stopLocationTracking()
      result(true)
    }
  }

  private func openAppSettings(result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
      result(opened)
    }
  }

  private func openNotificationSettings(result: @escaping FlutterResult) {
    let url: URL?
    if #available(iOS 16.0, *) {
      url = URL(string: UIApplication.openNotificationSettingsURLString)
    } else {
      url = URL(string: UIApplication.openSettingsURLString)
    }
    guard let url else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
      result(opened)
    }
  }

  private func beginBackgroundTask() {
    if backgroundTask != .invalid { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "KelivoBackgroundGeneration") { [weak self] in
      self?.endBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }

  private func scheduleBackgroundTasks() {
    let refresh = BGAppRefreshTaskRequest(identifier: backgroundRefreshIdentifier)
    refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    do {
      try BGTaskScheduler.shared.submit(refresh)
    } catch {
      NSLog("Kelivo background refresh schedule failed: \(error)")
    }

    let processing = BGProcessingTaskRequest(identifier: backgroundProcessingIdentifier)
    processing.requiresNetworkConnectivity = true
    processing.requiresExternalPower = false
    processing.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    do {
      try BGTaskScheduler.shared.submit(processing)
    } catch {
      NSLog("Kelivo background processing schedule failed: \(error)")
    }
  }

  private func handleBackgroundTask(_ task: BGTask) {
    if refreshEnabled { scheduleBackgroundTasks() }
    task.expirationHandler = { task.setTaskCompleted(success: false) }
    task.setTaskCompleted(success: true)
  }

  private func showCompletionNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(identifier: "kelivo.background-generation.\(Date().timeIntervalSince1970)", content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  private func ensureLocationManager() -> CLLocationManager {
    if let locationManager { return locationManager }
    let manager = CLLocationManager()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    manager.distanceFilter = 1000
    manager.activityType = .other
    manager.pausesLocationUpdatesAutomatically = false
    if #available(iOS 9.0, *) {
      manager.allowsBackgroundLocationUpdates = true
    }
    locationManager = manager
    return manager
  }

  private func startLocationTracking(requestAuthorization: Bool) -> Bool {
    locationTrackingRequested = true
    let manager = ensureLocationManager()
    let status = currentLocationAuthorization()
    guard CLLocationManager.locationServicesEnabled() else {
      locationTrackingActive = false
      return false
    }
    guard status == .authorizedAlways else {
      locationTrackingActive = false
      if requestAuthorization {
        manager.requestAlwaysAuthorization()
      }
      return false
    }
    manager.startUpdatingLocation()
    locationTrackingActive = true
    return true
  }

  private func stopLocationTracking() {
    locationTrackingRequested = false
    locationTrackingActive = false
    locationManager?.stopUpdatingLocation()
  }

  private func currentLocationAuthorization() -> CLAuthorizationStatus {
    if #available(iOS 14.0, *) {
      return locationManager?.authorizationStatus ?? CLLocationManager().authorizationStatus
    }
    return CLLocationManager.authorizationStatus()
  }

  private func locationAuthorizationString() -> String {
    guard CLLocationManager.locationServicesEnabled() else { return "disabled" }
    switch currentLocationAuthorization() {
    case .authorizedAlways:
      return "always"
    case .authorizedWhenInUse:
      return "whenInUse"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unknown"
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    handleLocationAuthorizationChanged()
  }

  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    handleLocationAuthorizationChanged()
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    NSLog("Kelivo location tracking failed: \(error)")
  }

  private func handleLocationAuthorizationChanged() {
    finishPendingLocationAuthorizationIfNeeded()
    if locationTrackingRequested {
      if currentLocationAuthorization() == .authorizedAlways {
        _ = startLocationTracking(requestAuthorization: false)
      } else {
        locationTrackingActive = false
      }
    }
  }

  private func finishPendingLocationAuthorizationIfNeeded() {
    guard let pending = pendingLocationAuthorizationResult else { return }
    let granted = currentLocationAuthorization() == .authorizedAlways
    pendingLocationAuthorizationResult = nil
    pending(granted)
  }

  private func liveActivitiesAvailable() -> Bool {
    if #available(iOS 16.1, *) {
      return ActivityAuthorizationInfo().areActivitiesEnabled
    }
    return false
  }

  private func startLiveActivity(taskId: String, title: String, detail: String, tokenCount: Int, tokenLabel: String) {
    guard #available(iOS 16.1, *) else { return }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let state = KelivoBackgroundActivityAttributes.ContentState(
      title: title,
      detail: detail,
      tokenCount: tokenCount,
      tokenLabel: tokenLabel,
      isFinished: false,
      success: false
    )
    if liveActivity != nil {
      updateLiveActivity(detail: detail, tokenCount: tokenCount, tokenLabel: tokenLabel)
      return
    }
    do {
      let attributes = KelivoBackgroundActivityAttributes(taskId: taskId)
      if #available(iOS 16.2, *) {
        let content = ActivityContent(state: state, staleDate: nil)
        liveActivity = try Activity<KelivoBackgroundActivityAttributes>.request(
          attributes: attributes,
          content: content,
          pushType: nil
        )
      } else {
        liveActivity = try Activity<KelivoBackgroundActivityAttributes>.request(
          attributes: attributes,
          contentState: state,
          pushType: nil
        )
      }
    } catch {
      NSLog("Kelivo live activity start failed: \(error)")
    }
  }

  private func updateLiveActivity(detail: String, tokenCount: Int, tokenLabel: String) {
    guard #available(iOS 16.1, *) else { return }
    guard let activity = liveActivity as? Activity<KelivoBackgroundActivityAttributes> else { return }
    let state = KelivoBackgroundActivityAttributes.ContentState(
      title: kelivoLocalized("ios_background_generation_active_title", fallback: "Kelivo is generating"),
      detail: detail,
      tokenCount: tokenCount,
      tokenLabel: tokenLabel,
      isFinished: false,
      success: false
    )
    Task {
      if #available(iOS 16.2, *) {
        await activity.update(ActivityContent(state: state, staleDate: nil))
      } else {
        await activity.update(using: state)
      }
    }
  }

  private func endLiveActivity(title: String, detail: String, success: Bool) {
    guard #available(iOS 16.1, *) else { return }
    guard let activity = liveActivity as? Activity<KelivoBackgroundActivityAttributes> else { return }
    liveActivity = nil
    let state = KelivoBackgroundActivityAttributes.ContentState(
      title: title,
      detail: detail,
      tokenCount: 0,
      tokenLabel: success ? kelivoLocalized("ios_background_generation_finished_success", fallback: "Done") : kelivoLocalized("ios_background_generation_finished_interrupted", fallback: "Interrupted"),
      isFinished: true,
      success: success
    )
    Task {
      if #available(iOS 16.2, *) {
        await activity.end(
          ActivityContent(state: state, staleDate: nil),
          dismissalPolicy: .after(Date(timeIntervalSinceNow: success ? 30 : 10))
        )
      } else {
        await activity.end(using: state, dismissalPolicy: .immediate)
      }
    }
  }
}

private final class NativeFileSaveHandler: NSObject, UIDocumentPickerDelegate {
  weak var presentingViewController: UIViewController?
  private var pendingResult: FlutterResult?

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    if pendingResult != nil {
      result(FlutterError(code: "busy", message: "Another save operation is already in progress.", details: nil))
      return
    }

    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_args", message: "Arguments must be a map.", details: nil))
      return
    }

    let rawSourcePath = (args["sourcePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !rawSourcePath.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Missing sourcePath.", details: nil))
      return
    }

    let sourceURL = URL(fileURLWithPath: rawSourcePath)
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      result(FlutterError(code: "not_found", message: "Source file does not exist.", details: nil))
      return
    }

    guard let presenter = topViewController(from: presentingViewController) else {
      result(FlutterError(code: "unavailable", message: "Unable to present document picker.", details: nil))
      return
    }

    pendingResult = result

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }

      let picker: UIDocumentPickerViewController
      if #available(iOS 14.0, *) {
        picker = UIDocumentPickerViewController(forExporting: [sourceURL], asCopy: true)
      } else {
        picker = UIDocumentPickerViewController(url: sourceURL, in: .exportToService)
      }

      picker.delegate = self
      picker.modalPresentationStyle = .formSheet
      if let popover = picker.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }

      presenter.present(picker, animated: true)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(with: false)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(with: !urls.isEmpty)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
    finish(with: true)
  }

  private func finish(with value: Bool) {
    let result = pendingResult
    pendingResult = nil
    result?(value)
  }

  private func topViewController(from controller: UIViewController?) -> UIViewController? {
    if let navigation = controller as? UINavigationController {
      return topViewController(from: navigation.visibleViewController)
    }
    if let tab = controller as? UITabBarController {
      return topViewController(from: tab.selectedViewController)
    }
    if let presented = controller?.presentedViewController {
      return topViewController(from: presented)
    }
    return controller
  }
}
