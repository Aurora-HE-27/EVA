import Foundation

enum ModelStorage {
    static let languageModelDirectoryName = "Qwen3.5-0.8B-MLX-4bit"

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

    static func languageModelURL(bundle: Bundle = .main) throws -> URL {
        if let bundledURL = bundle.url(
            forResource: languageModelDirectoryName,
            withExtension: nil,
            subdirectory: "Models"
        ) {
            return bundledURL
        }

        let developmentURL = huggingFaceURL
            .appending(path: "mlx-community", directoryHint: .isDirectory)
            .appending(path: languageModelDirectoryName, directoryHint: .isDirectory)
        if FileManager.default.fileExists(
            atPath: developmentURL.appending(path: "config.json").path
        ) {
            return developmentURL
        }

        throw AppError.localModelMissing(developmentURL)
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
