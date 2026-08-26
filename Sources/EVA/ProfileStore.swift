import Foundation

struct ProfileStore {
    private let fileURL: URL

    init(fileURL: URL = ProjectPaths.dataURL.appending(path: "profile.json")) {
        self.fileURL = fileURL
    }

    func load() -> CompanionProfile? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CompanionProfile.self, from: data)
    }

    func save(_ profile: CompanionProfile) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
