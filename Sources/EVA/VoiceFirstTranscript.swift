import Foundation

/// Tracks which replies the user has actually heard. Pending text is neither
/// presented nor restored from disk if the app exits before playback starts.
struct VoiceFirstTranscript {
    private(set) var concealedIDs: Set<UUID> = []
    private var startedIDs: Set<UUID> = []
    private struct Plan {
        let segments: [String]
        var startedThrough = -1
        var revealedThrough = -1

        var heardText: String { segments.prefix(startedThrough + 1).joined() }
    }
    private var plans: [UUID: Plan] = [:]

    mutating func prepare(_ id: UUID) {
        concealedIDs.insert(id)
        startedIDs.remove(id)
        plans[id] = nil
    }

    mutating func plan(_ segments: [String], for id: UUID) {
        guard concealedIDs.contains(id), !startedIDs.contains(id) else { return }
        plans[id] = Plan(segments: segments)
    }

    @discardableResult
    mutating func playbackStarted(_ id: UUID, segmentIndex: Int = 0) -> Bool {
        if var plan = plans[id] {
            guard segmentIndex == plan.startedThrough + 1,
                  plan.segments.indices.contains(segmentIndex) else { return false }
            plan.startedThrough = segmentIndex
            plans[id] = plan
        } else {
            // A replay is already in history, not a newly generated reply.
            guard concealedIDs.contains(id), !startedIDs.contains(id) else { return false }
        }
        startedIDs.insert(id)
        return true
    }

    @discardableResult
    mutating func reveal(_ id: UUID, through segmentIndex: Int? = nil) -> String? {
        guard startedIDs.contains(id) else { return nil }
        var content: String?
        if var plan = plans[id] {
            let through = segmentIndex ?? plan.startedThrough
            guard through >= 0, through <= plan.startedThrough else { return nil }
            plan.revealedThrough = max(plan.revealedThrough, through)
            content = plan.segments.prefix(plan.revealedThrough + 1).joined()
            plans[id] = plan
        }
        concealedIDs.remove(id)
        return content
    }

    func heardContent(for id: UUID) -> String? {
        plans[id]?.heardText
    }

    /// Returns true only when an unheard, newly generated reply must be removed.
    mutating func finish(_ id: UUID) -> Bool {
        let discard = concealedIDs.contains(id) && !startedIDs.contains(id)
        concealedIDs.remove(id)
        startedIDs.remove(id)
        plans[id] = nil
        return discard
    }

    func restorableMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.compactMap { message in
            if let plan = plans[message.id] {
                guard plan.startedThrough >= 0 else { return nil }
                var heard = message
                heard.content = plan.heardText
                return heard
            }
            return !concealedIDs.contains(message.id) || startedIDs.contains(message.id) ? message : nil
        }
    }
}
