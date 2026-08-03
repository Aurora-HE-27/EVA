import Foundation

actor ConversationStore {
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = support.appending(path: "EVA", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        fileURL = directory.appending(path: "conversation.json")

        let legacyURL = support.appending(
            path: "VirtualCompanion/conversation.json"
        )
        if !FileManager.default.fileExists(atPath: fileURL.path),
           FileManager.default.fileExists(atPath: legacyURL.path) {
            try? FileManager.default.copyItem(at: legacyURL, to: fileURL)
        }
    }

    func load() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([ChatMessage].self, from: data)) ?? []
    }

    func save(_ messages: [ChatMessage]) {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
