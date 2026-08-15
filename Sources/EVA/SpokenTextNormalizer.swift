import Foundation

enum SpokenTextNormalizer {
    private static let stageDirectionPattern =
        #"[（(\[【]\s*(?:微笑|笑|大笑|开心|难过|哭|流泪|拥抱|抱抱|叹气|害羞|眨眼|点头|摇头|沉思|惊讶|爱心|比心)\s*[）)\]】]"#

    static func normalize(_ input: String) -> String {
        var text = input
        text = replacing(
            #"\[([^\]]+)\]\(https?://[^\s)]+\)"#,
            in: text,
            with: "$1"
        )
        text = replacing(#"https?://\S+"#, in: text, with: "")
        text = replacing(stageDirectionPattern, in: text, with: "")
        text = String(text.filter { !isEmoji($0) })
        text = text.replacingOccurrences(of: "```", with: "")
        text = text.replacingOccurrences(
            of: #"[*_~`#>]"#,
            with: "",
            options: .regularExpression
        )
        text = replacing(#"[ \t]+"#, in: text, with: " ")
        text = replacing(#"\s*\n+\s*"#, in: text, with: "。")
        text = replacing(#"([。！？？，、])\1+"#, in: text, with: "$1")
        text = replacing(#"\s+([。！？？，、])"#, in: text, with: "$1")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(
        _ pattern: String,
        in text: String,
        with replacement: String
    ) -> String {
        text.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func isEmoji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || scalar.value == 0xFE0F
                || scalar.value == 0x200D
                || (0x1F000...0x1FAFF).contains(scalar.value)
                || (0x2600...0x27BF).contains(scalar.value)
                || (0x1F1E6...0x1F1FF).contains(scalar.value)
                || (0x1F3FB...0x1F3FF).contains(scalar.value)
                || scalar.value == 0x20E3
        }
    }
}
