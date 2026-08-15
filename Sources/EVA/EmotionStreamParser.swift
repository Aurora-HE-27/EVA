import Foundation

struct EmotionStreamParser {
    private static let directivePrefix = "[[EVA "
    private(set) var directive: EmotionDirective?
    private var prefixBuffer = ""
    private var resolvedPrefix = false

    mutating func append(_ fragment: String) -> String {
        guard !resolvedPrefix else { return fragment }
        prefixBuffer += fragment

        if !prefixBuffer.hasPrefix(Self.directivePrefix) {
            // Keep buffering only while the fragment can still become the
            // optional legacy directive prefix. Ordinary text streams at once.
            if Self.directivePrefix.hasPrefix(prefixBuffer) {
                return ""
            }
            resolvedPrefix = true
            let visible = prefixBuffer
            prefixBuffer = ""
            return visible
        }

        if let newline = prefixBuffer.firstIndex(of: "\n") {
            let firstLine = String(prefixBuffer[..<newline])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let remainderStart = prefixBuffer.index(after: newline)
            let remainder = String(prefixBuffer[remainderStart...])
            resolvedPrefix = true

            if let parsed = Self.parseDirective(firstLine) {
                directive = parsed
                prefixBuffer = ""
                return remainder
            }

            let visible = prefixBuffer
            prefixBuffer = ""
            return visible
        }

        if prefixBuffer.count > 420 {
            resolvedPrefix = true
            let visible = prefixBuffer
            prefixBuffer = ""
            return visible
        }
        return ""
    }

    mutating func flush() -> String? {
        guard !prefixBuffer.isEmpty else { return nil }
        defer {
            prefixBuffer = ""
            resolvedPrefix = true
        }
        let candidate = prefixBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = Self.parseDirective(candidate) {
            directive = parsed
            return nil
        }
        return prefixBuffer
    }

    private static func parseDirective(_ line: String) -> EmotionDirective? {
        guard line.hasPrefix("[[EVA "), line.hasSuffix("]]"), line.count < 360 else {
            return nil
        }

        let start = line.index(line.startIndex, offsetBy: 6)
        let end = line.index(line.endIndex, offsetBy: -2)
        let fields = line[start..<end]
            .split(separator: " ")
            .reduce(into: [String: String]()) { result, field in
                let pair = field.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2 {
                    result[pair[0]] = pair[1]
                }
            }

        guard let rawEmotion = fields["emotion"],
              let emotion = EVAEmotion(rawValue: rawEmotion),
              let valence = fields["valence"].flatMap(Double.init),
              let arousal = fields["arousal"].flatMap(Double.init),
              let intensity = fields["intensity"].flatMap(Double.init) else {
            return nil
        }

        return EmotionDirective(
            emotion: emotion,
            valence: valence,
            arousal: arousal,
            intensity: intensity
        )
    }
}
