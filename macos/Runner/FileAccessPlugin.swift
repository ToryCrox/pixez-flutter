import Cocoa
import FlutterMacOS

/// Flutter 平台通道插件，用于处理文件访问权限
class FileAccessPlugin: NSObject, FlutterPlugin {
    private var window: NSWindow?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.perol.pixez/file_access",
            binaryMessenger: registrar.messenger
        )
        let instance = FileAccessPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // 获取主窗口
        if window == nil {
            window = NSApplication.shared.windows.first
        }
        
        switch call.method {
        case "requestDirectoryAccess":
            handleRequestDirectoryAccess(result: result)
            
        case "startAccessingPath":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing path argument", details: nil))
                return
            }
            handleStartAccessingPath(path: path, result: result)
            
        case "stopAccessingPath":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing path argument", details: nil))
                return
            }
            handleStopAccessingPath(path: path, result: result)
            
        case "hasBookmark":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing path argument", details: nil))
                return
            }
            handleHasBookmark(path: path, result: result)
            
        case "clearBookmark":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing path argument", details: nil))
                return
            }
            handleClearBookmark(path: path, result: result)
            
        case "clearAllBookmarks":
            handleClearAllBookmarks(result: result)
            
        case "getAllBookmarkedPaths":
            handleGetAllBookmarkedPaths(result: result)
            
        case "saveBookmark":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing path argument", details: nil))
                return
            }
            handleSaveBookmark(path: path, result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleRequestDirectoryAccess(result: @escaping FlutterResult) {
        let (success, path) = FileAccessManager.shared.requestDirectoryAccess(window: window)
        if success {
            result([
                "success": true,
                "path": path ?? ""
            ])
        } else {
            result([
                "success": false,
                "path": ""
            ])
        }
    }
    
    private func handleStartAccessingPath(path: String, result: @escaping FlutterResult) {
        let success = FileAccessManager.shared.startAccessingPath(path)
        result(success)
    }
    
    private func handleStopAccessingPath(path: String, result: @escaping FlutterResult) {
        FileAccessManager.shared.stopAccessingPath(path)
        result(true)
    }
    
    private func handleHasBookmark(path: String, result: @escaping FlutterResult) {
        let hasBookmark = FileAccessManager.shared.hasBookmark(for: path)
        result(hasBookmark)
    }
    
    private func handleClearBookmark(path: String, result: @escaping FlutterResult) {
        FileAccessManager.shared.clearBookmark(for: path)
        result(true)
    }
    
    private func handleClearAllBookmarks(result: @escaping FlutterResult) {
        FileAccessManager.shared.clearAllBookmarks()
        result(true)
    }
    
    private func handleGetAllBookmarkedPaths(result: @escaping FlutterResult) {
        let paths = FileAccessManager.shared.getAllBookmarkedPaths()
        result(paths)
    }
    
    private func handleSaveBookmark(path: String, result: @escaping FlutterResult) {
        guard let url = URL(string: "file://\(path)") else {
            result(false)
            return
        }
        let success = FileAccessManager.shared.saveBookmark(for: url)
        result(success)
    }
}
