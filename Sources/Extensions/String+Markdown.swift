import Foundation

extension String {
    var markdownTitle: String? {
        let lines = components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2))
            }
        }
        return nil
    }

    func wikilinks() -> [(fullMatch: String, linkName: String, displayText: String?)] {
        let pattern = "\\[\\[([^\\]|]+)(?:\\|([^\\]]+))?\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..., in: self)
        let matches = regex.matches(in: self, range: range)

        return matches.compactMap { match in
            guard let fullRange = Range(match.range, in: self),
                  let linkRange = Range(match.range(at: 1), in: self)
            else { return nil }

            let fullMatch = String(self[fullRange])
            let linkName = String(self[linkRange])
            let displayText: String?
            if match.numberOfRanges > 2, let displayRange = Range(match.range(at: 2), in: self) {
                displayText = String(self[displayRange])
            } else {
                displayText = nil
            }
            return (fullMatch, linkName, displayText)
        }
    }

    func insertingMarkdown(_ wrapper: String, at range: Range<String.Index>?) -> String {
        guard let range = range else {
            return wrapper + self + wrapper
        }
        var result = self
        result.insert(contentsOf: wrapper, at: range.upperBound)
        result.insert(contentsOf: wrapper, at: range.lowerBound)
        return result
    }
}
