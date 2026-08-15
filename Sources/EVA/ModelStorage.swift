import Foundation

enum ModelStorage {
    static let languageModelDirectoryName = "Qwen3.5-2B-MLX-4bit"
    static let speechModelDirectoryName = "Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit"

    static var rootURL: URL {
        if let configuredPath = ProcessInfo.processInfo.environment["EVA_MODEL_ROOT"],
           !configuredPath.isEmpty {
            return URL(filePath: configuredPath, directoryHint: .isDirectory)
                .deletingLastPathComponent()
        }

        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "EVA/Models", directoryHint: .isDirectory)
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

    static func speechModelURL(bundle: Bundle = .main) throws -> URL {
        if let bundledURL = bundle.url(
            forResource: speechModelDirectoryName,
            withExtension: nil,
            subdirectory: "Models"
        ) {
            return bundledURL
        }

        let developmentURL = huggingFaceURL
            .appending(path: "mlx-community", directoryHint: .isDirectory)
            .appending(path: speechModelDirectoryName, directoryHint: .isDirectory)
        if FileManager.default.fileExists(
            atPath: developmentURL.appending(path: "model.safetensors").path
        ), FileManager.default.fileExists(
            atPath: developmentURL.appending(path: "speech_tokenizer/model.safetensors").path
        ) {
            return developmentURL
        }

        throw NeuralSpeechError.modelMissing(developmentURL)
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
