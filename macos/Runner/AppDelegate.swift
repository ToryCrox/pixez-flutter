import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
    var eventSink: FlutterEventSink?
    
    override func applicationDidFinishLaunching(_ notification: Notification) {
        // 注册文件访问插件
        if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
            let registrar = controller.registrar(forPlugin: "FileAccessPlugin")
            FileAccessPlugin.register(with: registrar)
        }
    }
    
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    override func application(_ application: NSApplication, open urls: [URL]) {
        print(urls)
        for i in urls {
            eventSink?(i.absoluteString)
        }
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
