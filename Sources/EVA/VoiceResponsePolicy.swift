import Foundation

enum VoiceResponsePolicy {
    /// Produces exactly one complete utterance for one assistant turn.
    /// Punctuation remains inside the utterance as prosody context; callers must not
    /// split the result into independently synthesized sentences.
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
