import Flutter
import UIKit

/// Security-scoped bookmarks. On iOS a picked URL grants only temporary access;
/// reopening after relaunch requires a bookmark captured at pick time.
///
/// Deliberately declared in this file rather than its own: a new .swift file is
/// not compiled unless it is added to the Xcode target in project.pbxproj, and
/// a silently-uncompiled plugin fails at runtime with MissingPluginException.
class DocumentHandlePlugin: NSObject, FlutterPlugin {
  private var activeScopes: [String: URL] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.folio.app/handles",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(DocumentHandlePlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createBookmark":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path missing", details: nil))
        return
      }
      do {
        let data = try URL(fileURLWithPath: path).bookmarkData(
          options: .minimalBookmark,
          includingResourceValuesForKeys: nil,
          relativeTo: nil)
        result(FlutterStandardTypedData(bytes: data))
      } catch {
        result(FlutterError(code: "bookmark_failed",
                            message: error.localizedDescription, details: nil))
      }

    case "resolveBookmark":
      guard let args = call.arguments as? [String: Any],
            let typed = args["data"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "bad_args", message: "data missing", details: nil))
        return
      }
      var isStale = false
      do {
        let url = try URL(resolvingBookmarkData: typed.data,
                          options: [],
                          relativeTo: nil,
                          bookmarkDataIsStale: &isStale)
        if isStale {
          result(FlutterError(code: "stale", message: "bookmark is stale", details: nil))
          return
        }
        // Scope must be started before the file is readable, and released later
        // or the kernel resource leaks.
        let scoped = url.startAccessingSecurityScopedResource()
        guard FileManager.default.fileExists(atPath: url.path) else {
          if scoped { url.stopAccessingSecurityScopedResource() }
          result(FlutterError(code: "missing", message: "file not found", details: nil))
          return
        }
        if scoped { activeScopes[url.path] = url }
        result(url.path)

      } catch let error as NSError {
        // Resolution itself fails when the target no longer exists, before any
        // fileExists check can run. Cocoa reports this as NSFileReadNoSuchFile
        // (260) or NSFileNoSuchFile (4); surface it as a moved document rather
        // than an unknown error.
        let missing = error.domain == NSCocoaErrorDomain
          && (error.code == 260 || error.code == 4)
        result(FlutterError(code: missing ? "missing" : "resolve_failed",
                            message: error.localizedDescription, details: nil))
      }

    case "stopAccessing":
      for (_, url) in activeScopes {
        url.stopAccessingSecurityScopedResource()
      }
      activeScopes.removeAll()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    DocumentHandlePlugin.register(
      with: engineBridge.pluginRegistry.registrar(forPlugin: "DocumentHandlePlugin")!)
  }
}
