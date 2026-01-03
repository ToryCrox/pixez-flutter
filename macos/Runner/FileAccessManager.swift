import Cocoa
import FlutterMacOS

/// 文件访问管理器，负责处理 Security-Scoped Bookmark
class FileAccessManager {
    static let shared = FileAccessManager()
    
    private let bookmarkKey = "securityScopedBookmark"
    private var accessedURLs: [URL: Bool] = [:]
    
    private init() {}
    
    /// 请求用户选择目录并创建 bookmark
    /// - Parameter window: 父窗口
    /// - Returns: (是否成功, 选择的路径)
    func requestDirectoryAccess(window: NSWindow?) -> (Bool, String?) {
        let openPanel = NSOpenPanel()
        openPanel.message = "请选择下载目录以授权访问"
        openPanel.prompt = "授权访问"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        
        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return (false, nil)
        }
        
        // 创建 bookmark
        if saveBookmark(for: url) {
            return (true, url.path)
        } else {
            return (false, nil)
        }
    }
    
    /// 保存 Security-Scoped Bookmark
    /// - Parameter url: 需要保存的 URL
    /// - Returns: 是否成功
    func saveBookmark(for url: URL) -> Bool {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            // 保存多个 bookmark（以路径为 key）
            var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: Data] ?? [:]
            bookmarks[url.path] = bookmarkData
            UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
            UserDefaults.standard.synchronize()
            
            print("✅ Bookmark saved for: \(url.path)")
            return true
        } catch {
            print("❌ Failed to create bookmark: \(error)")
            return false
        }
    }
    
    /// 从保存的 bookmark 恢复访问权限
    /// - Parameter path: 文件路径
    /// - Returns: 是否成功
    func startAccessingPath(_ path: String) -> Bool {
        // 检查是否已经在访问中
        if let url = URL(string: "file://\(path)"), accessedURLs[url] == true {
            return true
        }
        
        // 尝试从 bookmark 恢复
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: Data] else {
            print("⚠️ No bookmarks found")
            return false
        }
        
        // 查找匹配的 bookmark（支持父目录）
        var matchedURL: URL?
        var matchedBookmarkData: Data?
        
        for (bookmarkedPath, bookmarkData) in bookmarks {
            if path.hasPrefix(bookmarkedPath) {
                // 找到父目录或完全匹配的 bookmark
                if matchedURL == nil || bookmarkedPath.count > matchedURL!.path.count {
                    do {
                        var isStale = false
                        let url = try URL(
                            resolvingBookmarkData: bookmarkData,
                            options: .withSecurityScope,
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale
                        )
                        
                        if isStale {
                            print("⚠️ Bookmark is stale, need to recreate")
                            continue
                        }
                        
                        matchedURL = url
                        matchedBookmarkData = bookmarkData
                    } catch {
                        print("❌ Failed to resolve bookmark: \(error)")
                    }
                }
            }
        }
        
        guard let url = matchedURL else {
            print("⚠️ No matching bookmark found for: \(path)")
            return false
        }
        
        // 开始访问
        if url.startAccessingSecurityScopedResource() {
            accessedURLs[url] = true
            print("✅ Started accessing: \(url.path)")
            return true
        } else {
            print("❌ Failed to start accessing: \(url.path)")
            return false
        }
    }
    
    /// 停止访问 Security-Scoped Resource
    /// - Parameter path: 文件路径
    func stopAccessingPath(_ path: String) {
        guard let url = URL(string: "file://\(path)"), accessedURLs[url] == true else {
            return
        }
        
        url.stopAccessingSecurityScopedResource()
        accessedURLs.removeValue(forKey: url)
        print("🛑 Stopped accessing: \(path)")
    }
    
    /// 检查路径是否已有 bookmark
    /// - Parameter path: 文件路径
    /// - Returns: 是否存在
    func hasBookmark(for path: String) -> Bool {
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: Data] else {
            return false
        }
        
        // 检查是否有完全匹配或父目录的 bookmark
        for bookmarkedPath in bookmarks.keys {
            if path.hasPrefix(bookmarkedPath) {
                return true
            }
        }
        
        return false
    }
    
    /// 清除指定路径的 bookmark
    /// - Parameter path: 文件路径
    func clearBookmark(for path: String) {
        var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: Data] ?? [:]
        bookmarks.removeValue(forKey: path)
        UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
        UserDefaults.standard.synchronize()
        print("🗑️ Bookmark cleared for: \(path)")
    }
    
    /// 清除所有 bookmarks
    func clearAllBookmarks() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.synchronize()
        
        // 停止所有访问
        for (url, _) in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessedURLs.removeAll()
        
        print("🗑️ All bookmarks cleared")
    }
    
    /// 获取所有已保存的 bookmark 路径
    /// - Returns: 路径列表
    func getAllBookmarkedPaths() -> [String] {
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) as? [String: Data] else {
            return []
        }
        return Array(bookmarks.keys)
    }
}
