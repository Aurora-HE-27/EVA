import Foundation

struct PersistedSettings: Codable, Equatable, Sendable {
    var voiceIdentifier: String
    var voiceRate: Double
    var voicePitch: Double
}

struct SettingsStore {
    private let fileURL: URL

    init(fileURL: URL = ProjectPaths.dataURL.appending(path: "settings.json")) {
        self.fileURL = fileURL
    }

    func load() -> PersistedSettings? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedSettings.self, from: data)
    }

    func save(_ settings: PersistedSettings) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
