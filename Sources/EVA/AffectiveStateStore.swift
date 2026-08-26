import Foundation

struct AffectiveStateStore {
    private let fileURL: URL

    init(fileURL: URL = ProjectPaths.dataURL.appending(path: "state.json")) {
        self.fileURL = fileURL
    }

    func load() -> AffectiveState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AffectiveState.self, from: data)
    }

    func save(_ state: AffectiveState) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
