import Foundation

/// Plans a small number of complete utterances, never token-sized speech fragments.
/// Input is already cleaned by the caller. Joining the result preserves it exactly.
enum SpokenReplySegmenter {
    private static let shortReplyLimit = 60
    private static let minimumSpokenCharacters = 12
    private static let preferredFirstSegmentLength = 40

    static func segments(for text: String) -> [String] {
        guard text.contains(where: { !$0.isWhitespace }) else { return [] }

        let characters = Array(text)
        let lengths = prefixCounts(characters) { !$0.isWhitespace }
        let spokenLengths = prefixCounts(characters) { $0.isLetter || $0.isNumber }
        let totalLength = lengths[characters.count]
        guard totalLength > shortReplyLimit else { return [text] }

        let targetLength = min(preferredFirstSegmentLength, totalLength / 2)
        let candidates = sentenceBoundaries(in: characters).filter { boundary in
            spokenLengths[boundary] >= minimumSpokenCharacters
                && spokenLengths[characters.count] - spokenLengths[boundary] >= minimumSpokenCharacters
        }
        guard let split = candidates.min(by: {
            let firstDistance = abs(lengths[$0] - targetLength)
            let secondDistance = abs(lengths[$1] - targetLength)
            return firstDistance == secondDistance ? $0 < $1 : firstDistance < secondDistance
        }) else {
            // A long sentence is preferable to cutting at a comma, hesitation,
            // or an unfinished quoted thought. Very short reactions stay attached.
            return [text]
        }

        return [String(characters[..<split]), String(characters[split...])]
    }

    private static func prefixCounts(
        _ characters: [Character],
        matching predicate: (Character) -> Bool
    ) -> [Int] {
        var counts = [0]
        counts.reserveCapacity(characters.count + 1)
        for character in characters {
            counts.append(counts[counts.count - 1] + (predicate(character) ? 1 : 0))
        }
        return counts
    }

    private static let sentenceEnds: Set<Character> = ["。", "！", "？", "!", "?"]
    private static let pairedDelimiters: [Character: Character] = [
        "“": "”", "‘": "’", "「": "」", "『": "』", "«": "»",
        "（": "）", "(": ")", "【": "】", "[": "]", "《": "》"
    ]
    private static let closingDelimiters = Set(pairedDelimiters.values)

    private static func sentenceBoundaries(in characters: [Character]) -> [Int] {
        var boundaries: [Int] = []
        var expectedClosers: [Character] = []
        var index = 0

        func consumeDelimiter(_ character: Character) {
            if character == "\"" {
                if expectedClosers.last == character {
                    expectedClosers.removeLast()
                } else {
                    expectedClosers.append(character)
                }
            } else if let closer = pairedDelimiters[character] {
                expectedClosers.append(closer)
            } else if expectedClosers.last == character {
                expectedClosers.removeLast()
            }
        }

        while index < characters.count {
            let character = characters[index]
            consumeDelimiter(character)
            guard isSentenceEnd(at: index, in: characters) else {
                index += 1
                continue
            }

            var end = index + 1
            // Keep emphatic punctuation and its closing quotation/bracket on the
            // same side of a boundary: for example, “真的？！” must remain intact.
            while end < characters.count {
                let trailer = characters[end]
                if sentenceEnds.contains(trailer) || trailer == "…" || trailer == "." {
                    end += 1
                } else if closingDelimiters.contains(trailer)
                    || (trailer == "\"" && expectedClosers.last == "\"") {
                    consumeDelimiter(trailer)
                    end += 1
                } else {
                    break
                }
            }

            if expectedClosers.isEmpty {
                // Preserve whitespace rather than trimming each segment. It stays
                // with the preceding sentence and cannot be lost or duplicated.
                while end < characters.count && characters[end].isWhitespace {
                    end += 1
                }
                if end < characters.count {
                    boundaries.append(end)
                }
            }
            index = end
        }
        return boundaries
    }

    private static func isSentenceEnd(at index: Int, in characters: [Character]) -> Bool {
        let character = characters[index]
        if sentenceEnds.contains(character) { return true }
        guard character == "." else { return false }

        // Do not mistake a decimal, URL, or an ellipsis for a complete
        // sentence. Ambiguous unspaced Latin punctuation conservatively stays whole.
        if index > 0 && characters[index - 1] == "." { return false }
        guard index + 1 < characters.count else { return true }
        let next = characters[index + 1]
        return next.isWhitespace || closingDelimiters.contains(next) || next == "\""
    }
}
