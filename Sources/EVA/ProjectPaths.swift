import Foundation

enum ProjectPaths {
    static var rootURL: URL {
        if let configuredPath = ProcessInfo.processInfo.environment["EVA_PROJECT_ROOT"],
           !configuredPath.isEmpty {
            return URL(filePath: configuredPath, directoryHint: .isDirectory)
        }

        let bundleURL = Bundle.main.bundleURL
        let bundleParent = bundleURL.deletingLastPathComponent()
        if bundleURL.pathExtension == "app", bundleParent.lastPathComponent == "dist" {
            return bundleParent.deletingLastPathComponent()
        }

        return URL(filePath: #filePath, directoryHint: .notDirectory)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var dataURL: URL {
        rootURL.appending(path: ".eva-data", directoryHint: .isDirectory)
    }

    static var modelRootURL: URL {
        rootURL.appending(path: ".eva-models", directoryHint: .isDirectory)
    }

    static func prepareDataDirectory() throws {
        try FileManager.default.createDirectory(
            at: dataURL,
            withIntermediateDirectories: true
        )
    }
}
