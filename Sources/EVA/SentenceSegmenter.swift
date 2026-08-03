import Foundation

struct SentenceSegmenter {
    private(set) var buffer = ""

    mutating func append(_ fragment: String) -> [String] {
        buffer += fragment
        var sentences: [String] = []

        while let boundary = buffer.firstIndex(where: Self.isBoundary) {
            let end = buffer.index(after: boundary)
            let sentence = String(buffer[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[end...])
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        return sentences
    }

    mutating func flush() -> String? {
        let remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return remainder.isEmpty ? nil : remainder
    }

    private static func isBoundary(_ character: Character) -> Bool {
        let boundaries = "。！？!?；;\n"
        return boundaries.contains(character)
    }
}
