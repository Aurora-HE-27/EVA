import AppKit
import Foundation

@MainActor
final class ProjectAccessCoordinator {
    static let shared = ProjectAccessCoordinator()

    private let bookmarkKey = "evaProjectRootBookmark.v1"
    private var accessedURL: URL?

    private init() {
        restoreAccess()
    }

    var hasAccess: Bool {
        guard let accessedURL else { return false }
        return accessedURL.standardizedFileURL == ProjectPaths.rootURL.standardizedFileURL
    }

    func requestAccessIfNeeded() -> Bool {
        if hasAccess { return true }

        let panel = NSOpenPanel()
        panel.title = "选择 EVA 项目文件夹"
        panel.message = "请选择“虚拟伴侣”文件夹。EVA 会把聊天、设置和状态保存在其中的 .eva-data 目录。"
        panel.prompt = "使用此文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = ProjectPaths.rootURL

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return false
        }
        guard isEVAProjectRoot(selectedURL) else {
            return false
        }

        do {
            let bookmark = try selectedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            beginAccessing(selectedURL)
            return hasAccess
        } catch {
            return false
        }
    }

    private func restoreAccess() {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return
        }

        beginAccessing(url)
        if isStale,
           let refreshed = try? url.bookmarkData(
               options: .withSecurityScope,
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           ) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
    }

    private func beginAccessing(_ url: URL) {
        accessedURL?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else {
            accessedURL = nil
            return
        }
        accessedURL = url
    }

    private func isEVAProjectRoot(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        guard standardized == ProjectPaths.rootURL.standardizedFileURL else { return false }
        return FileManager.default.fileExists(
            atPath: standardized.appending(path: "project.yml").path
        ) && FileManager.default.fileExists(
            atPath: standardized.appending(path: "Sources/EVA", directoryHint: .isDirectory).path
        )
    }
}
