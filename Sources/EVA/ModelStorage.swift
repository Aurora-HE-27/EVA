import Foundation

enum ModelStorage {
    static var rootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "AI开发/ai模型", directoryHint: .isDirectory)
    }

    static var huggingFaceURL: URL {
        rootURL.appending(path: "huggingface", directoryHint: .isDirectory)
    }

    static var servicesURL: URL {
        rootURL.appending(path: "services", directoryHint: .isDirectory)
    }

    static func prepareDirectories() throws {
        try FileManager.default.createDirectory(
            at: huggingFaceURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: servicesURL,
            withIntermediateDirectories: true
        )
    }
}
