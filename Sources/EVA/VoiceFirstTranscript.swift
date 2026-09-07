import Foundation

/// Tracks which replies the user has actually heard. Pending text is neither
/// presented nor restored from disk if the app exits before playback starts.
struct VoiceFirstTranscript {
    private(set) var concealedIDs: Set<UUID> = []
    private var startedIDs: Set<UUID> = []

    mutating func prepare(_ id: UUID) {
        concealedIDs.insert(id)
    }

    mutating func playbackStarted(_ id: UUID) {
        startedIDs.insert(id)
    }

    mutating func reveal(_ id: UUID) {
        guard startedIDs.contains(id) else { return }
        concealedIDs.remove(id)
    }

    /// Returns true only when an unheard, newly generated reply must be removed.
    mutating func finish(_ id: UUID) -> Bool {
        let discard = concealedIDs.contains(id) && !startedIDs.contains(id)
        concealedIDs.remove(id)
        startedIDs.remove(id)
        return discard
    }

    func restorableMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { !concealedIDs.contains($0.id) || startedIDs.contains($0.id) }
    }
}
