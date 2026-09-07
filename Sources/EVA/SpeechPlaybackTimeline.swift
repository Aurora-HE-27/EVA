import Foundation

/// One sample clock for an entire reply. A late producer may leave a gap, but
/// must never make a queued segment appear to have played during that gap.
struct SpeechPlaybackTimeline {
    struct Segment {
        let index: Int
        let text: String
        let startFrame: Int64
        let audibleFrame: Int64
        let endFrame: Int64
    }

    private(set) var segments: [Segment] = []
    private var announced: Set<Int> = []

    mutating func append(
        index: Int,
        text: String,
        frameCount: Int64,
        firstAudibleFrame: Int64,
        currentFrame: Int64?,
        lateSchedulingLead: Int64
    ) -> Segment {
        let previousEnd = segments.last?.endFrame ?? 0
        let earliestStart = currentFrame.map { max(0, $0) + lateSchedulingLead } ?? 0
        let start = max(previousEnd, earliestStart)
        let segment = Segment(
            index: index,
            text: text,
            startFrame: start,
            audibleFrame: start + max(0, min(firstAudibleFrame, frameCount - 1)),
            endFrame: start + frameCount
        )
        segments.append(segment)
        return segment
    }

    mutating func newlyStarted(at frame: Int64) -> [Segment] {
        let started = segments.filter { frame >= $0.audibleFrame && !announced.contains($0.index) }
        announced.formUnion(started.map(\.index))
        return started
    }

    func isPlaying(at frame: Int64) -> Bool {
        segments.contains { frame >= $0.audibleFrame && frame < $0.endFrame }
    }
}
