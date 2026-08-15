import Foundation

enum CompanionResponseSanitizer {
    private static let leadingDirectionPattern =
        #"^\s*[（(\[【][^）)\]】\n]{0,60}[）)\]】]\s*"#
    private static let inlineDirectionPattern =
        #"[（(\[【][^）)\]】\n]{0,28}(?:拍|摸|抱|拥抱|微笑|笑|叹气|点头|摇头|眨眼|握住|靠近|看着|沉默|轻轻)[^）)\]】\n]{0,28}[）)\]】]"#

    static func normalize(_ input: String) -> String {
        var text = input
        while text.range(of: leadingDirectionPattern, options: .regularExpression) != nil {
            text = text.replacingOccurrences(
                of: leadingDirectionPattern,
                with: "",
                options: .regularExpression
            )
        }
        text = text.replacingOccurrences(
            of: inlineDirectionPattern,
            with: "",
            options: .regularExpression
        )
        return SpokenTextNormalizer.normalize(text)
    }
}
