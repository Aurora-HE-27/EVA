import Foundation

enum VoiceResponsePolicy {
    /// Produces a complete, speakable reply. Short turns retain their full prosody
    /// context; SpokenReplySegmenter may split longer turns at complete sentences,
    /// never at commas or individual language-model tokens.
    static func continuousUtterance(
        generatedText: String,
        fallback: String,
        move: ConversationMove = .react
    ) -> String {
        let normalized = CompanionResponseSanitizer.normalize(generatedText)
        if normalized.contains(where: { !$0.isWhitespace }) {
            return sentenceLimited(normalized, maximumSentences: maximumSentences(for: move))
        }
        return CompanionResponseSanitizer.normalize(fallback)
    }

    private static func maximumSentences(for move: ConversationMove) -> Int {
        move == .answerDirectly ? 3 : 2
    }

    private static func sentenceLimited(
        _ text: String,
        maximumSentences: Int
    ) -> String {
        var result = ""
        var sentenceCount = 0
        let terminators: Set<Character> = ["。", "！", "？", "!", "?"]

        for character in text {
            result.append(character)
            if terminators.contains(character) {
                sentenceCount += 1
                if sentenceCount >= maximumSentences {
                    break
                }
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
