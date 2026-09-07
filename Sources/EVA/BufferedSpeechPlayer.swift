import AVFoundation
import Foundation

/// Buffers complete semantic utterances on one audio node. Model inference can
/// prepare the next utterance while this node plays; no per-sentence player
/// teardown or artificial post-utterance delay is inserted.
@MainActor
final class BufferedSpeechPlayer {
    var onSegmentStarted: ((UUID, Int, String) -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?
    var onFinished: ((UUID) -> Void)?

    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    private var requestID: UUID?
    private var generation = UUID()
    private var timeline = SpeechPlaybackTimeline()
    private var scheduledCount = 0
    private var playedCount = 0
    private var schedulingFinished = false
    private var monitor: Task<Void, Never>?
    private var isPlaying = false
    private let volume: Float

    init(volume: Float = 1) {
        self.volume = min(max(volume, 0), 1)
    }

    deinit { monitor?.cancel() }

    func begin(_ id: UUID) {
        stop()
        generation = UUID()
        requestID = id
    }

    func append(_ audio: NeuralSpeechAudio, index: Int, text: String, requestID id: UUID) throws {
        guard requestID == id else { throw CancellationError() }
        guard !audio.samples.isEmpty, audio.sampleRate > 0 else { throw SpeechPlaybackError.invalidAudio }

        if engine == nil {
            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            node.volume = volume
            guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(audio.sampleRate), channels: 1)
            else { throw SpeechPlaybackError.invalidAudio }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.prepare()
            try engine.start()
            self.engine = engine
            self.node = node
            self.format = format
        }

        guard let node, let format, format.sampleRate == Double(audio.sampleRate),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.samples.count)),
              let destination = buffer.floatChannelData?[0]
        else { throw SpeechPlaybackError.invalidAudio }
        buffer.frameLength = buffer.frameCapacity
        audio.samples.withUnsafeBufferPointer { samples in
            if let source = samples.baseAddress { destination.update(from: source, count: samples.count) }
        }

        let audibleOffset = audio.samples.firstIndex(where: { abs($0) > 0.002 }) ?? 0
        let segment = timeline.append(
            index: index,
            text: text,
            frameCount: Int64(audio.samples.count),
            firstAudibleFrame: Int64(audibleOffset),
            currentFrame: currentFrame,
            lateSchedulingLead: Int64(format.sampleRate * 0.05)
        )
        scheduledCount += 1
        let generation = generation
        node.scheduleBuffer(
            buffer,
            at: AVAudioTime(sampleTime: segment.startFrame, atRate: format.sampleRate),
            options: [],
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.requestID == id, self.generation == generation else { return }
                self.updatePlaybackClock()
                self.playedCount += 1
                self.finishIfDrained()
            }
        }
        if !node.isPlaying { node.play() }
        startMonitoringIfNeeded()
    }

    func finishScheduling(requestID id: UUID) {
        guard requestID == id else { return }
        schedulingFinished = true
        finishIfDrained()
    }

    func stop() {
        requestID = nil // Invalidate callbacks before stopping scheduled buffers.
        generation = UUID()
        monitor?.cancel()
        monitor = nil
        node?.stop()
        engine?.stop()
        node = nil
        engine = nil
        format = nil
        timeline = SpeechPlaybackTimeline()
        scheduledCount = 0
        playedCount = 0
        schedulingFinished = false
        setPlaying(false)
    }

    private var currentFrame: Int64? {
        guard let node, node.isPlaying, let renderTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: renderTime) else { return nil }
        return playerTime.sampleTime
    }

    private func startMonitoringIfNeeded() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                self?.updatePlaybackClock()
                do { try await Task.sleep(for: .milliseconds(20)) }
                catch { break }
            }
        }
    }

    private func updatePlaybackClock() {
        guard let id = requestID, let currentFrame else { return }
        for segment in timeline.newlyStarted(at: currentFrame) {
            onSegmentStarted?(id, segment.index, segment.text)
        }
        setPlaying(timeline.isPlaying(at: currentFrame))
    }

    private func finishIfDrained() {
        guard schedulingFinished, playedCount == scheduledCount, let id = requestID else { return }
        stop()
        onFinished?(id)
    }

    private func setPlaying(_ value: Bool) {
        guard isPlaying != value else { return }
        isPlaying = value
        onPlayingChanged?(value)
    }
}

enum SpeechPlaybackError: LocalizedError {
    case invalidAudio

    var errorDescription: String? { "EVA 的音频无法播放，请重试。" }
}
