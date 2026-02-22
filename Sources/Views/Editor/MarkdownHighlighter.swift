import AppKit

struct MarkdownHighlighter {
    let fontSize: CGFloat

    // Fonts
    private var bodyFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private var h1Font: NSFont {
        NSFont.systemFont(ofSize: 28, weight: .semibold)
    }

    private var h2Font: NSFont {
        NSFont.systemFont(ofSize: 22, weight: .semibold)
    }

    private var h3Font: NSFont {
        NSFont.systemFont(ofSize: 18, weight: .medium)
    }

    private var h4Font: NSFont {
        NSFont.systemFont(ofSize: 16, weight: .medium)
    }

    private var boldFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    }

    private var italicFont: NSFont {
        let desc = bodyFont.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: desc, size: fontSize) ?? bodyFont
    }

    private var boldItalicFont: NSFont {
        let desc = boldFont.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: desc, size: fontSize) ?? boldFont
    }

    private var codeFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    // Colors
    private let dimmedAlpha: CGFloat = 0.40
    private let blockquoteAlpha: CGFloat = 0.80

    private var markerColor: NSColor {
        NSColor.labelColor.withAlphaComponent(dimmedAlpha)
    }

    private var codeBlockBg: NSColor {
        NSColor.quaternaryLabelColor.withAlphaComponent(0.3)
    }

    private var inlineCodeBg: NSColor {
        NSColor.quaternaryLabelColor
    }

    // MARK: - Apply highlighting

    func highlight(storage: NSTextStorage, in editedRange: NSRange, fullString: NSString) {
        let fullRange = NSRange(location: 0, length: fullString.length)

        // Compute the paragraph range covering the edited area
        let paragraphRange = fullString.paragraphRange(for: editedRange)
        let workRange = paragraphRange

        // Default paragraph style
        let defaultParagraph = NSMutableParagraphStyle()
        defaultParagraph.lineHeightMultiple = 1.6

        // Reset attributes in work range
        storage.addAttributes([
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: defaultParagraph,
            .backgroundColor: NSColor.clear,
            .strikethroughStyle: 0
        ], range: workRange)

        // Apply patterns
        applyHeadings(storage: storage, string: fullString, range: workRange)
        applyBoldItalic(storage: storage, string: fullString, range: workRange)
        applyInlineCode(storage: storage, string: fullString, range: workRange)
        applyCodeBlocks(storage: storage, string: fullString, range: fullRange)
        applyBlockquotes(storage: storage, string: fullString, range: workRange)
        applyLists(storage: storage, string: fullString, range: workRange)
        applyLinks(storage: storage, string: fullString, range: workRange)
        applyWikilinks(storage: storage, string: fullString, range: workRange)
        applyHorizontalRules(storage: storage, string: fullString, range: workRange)
    }

    func highlightFull(storage: NSTextStorage) {
        let fullString = storage.string as NSString
        let fullRange = NSRange(location: 0, length: fullString.length)
        guard fullRange.length > 0 else { return }

        let defaultParagraph = NSMutableParagraphStyle()
        defaultParagraph.lineHeightMultiple = 1.6

        storage.addAttributes([
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: defaultParagraph,
            .backgroundColor: NSColor.clear,
            .strikethroughStyle: 0
        ], range: fullRange)

        applyHeadings(storage: storage, string: fullString, range: fullRange)
        applyBoldItalic(storage: storage, string: fullString, range: fullRange)
        applyInlineCode(storage: storage, string: fullString, range: fullRange)
        applyCodeBlocks(storage: storage, string: fullString, range: fullRange)
        applyBlockquotes(storage: storage, string: fullString, range: fullRange)
        applyLists(storage: storage, string: fullString, range: fullRange)
        applyLinks(storage: storage, string: fullString, range: fullRange)
        applyWikilinks(storage: storage, string: fullString, range: fullRange)
        applyHorizontalRules(storage: storage, string: fullString, range: fullRange)
    }

    // MARK: - Pattern Matchers

    private func applyHeadings(storage: NSTextStorage, string: NSString, range: NSRange) {
        applyRegex("^(#{1,6})\\s(.*)$", to: storage, string: string, range: range) { match in
            let hashRange = match.range(at: 1)
            let hashLength = hashRange.length
            let lineRange = match.range(at: 0)

            let font: NSFont
            let paragraphStyle = NSMutableParagraphStyle()
            let opacity: CGFloat

            switch hashLength {
            case 1:
                font = h1Font
                paragraphStyle.paragraphSpacingBefore = 8
                paragraphStyle.paragraphSpacing = 8
                paragraphStyle.lineHeightMultiple = 1.3
                opacity = 1.0
            case 2:
                font = h2Font
                paragraphStyle.paragraphSpacingBefore = 6
                paragraphStyle.paragraphSpacing = 6
                paragraphStyle.lineHeightMultiple = 1.3
                opacity = 1.0
            case 3:
                font = h3Font
                paragraphStyle.paragraphSpacingBefore = 4
                paragraphStyle.paragraphSpacing = 4
                paragraphStyle.lineHeightMultiple = 1.4
                opacity = 1.0
            default:
                font = h4Font
                paragraphStyle.lineHeightMultiple = 1.4
                opacity = 0.70
            }

            // Apply font to entire line
            storage.addAttributes([
                .font: font,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: NSColor.labelColor.withAlphaComponent(opacity)
            ], range: lineRange)

            // Dim the hash markers and trailing space
            let markerEnd = hashRange.location + hashRange.length + 1
            let markerRange = NSRange(location: hashRange.location,
                                       length: min(markerEnd - hashRange.location, lineRange.location + lineRange.length - hashRange.location))
            storage.addAttribute(.foregroundColor, value: markerColor, range: markerRange)
        }
    }

    private func applyBoldItalic(storage: NSTextStorage, string: NSString, range: NSRange) {
        // Bold italic ***text***
        applyRegex("\\*{3}(.+?)\\*{3}", to: storage, string: string, range: range) { match in
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)
            storage.addAttribute(.font, value: boldItalicFont, range: contentRange)
            // Dim markers
            let openMarker = NSRange(location: fullRange.location, length: 3)
            let closeMarker = NSRange(location: fullRange.location + fullRange.length - 3, length: 3)
            storage.addAttribute(.foregroundColor, value: markerColor, range: openMarker)
            storage.addAttribute(.foregroundColor, value: markerColor, range: closeMarker)
        }

        // Bold **text** or __text__
        applyRegex("(?<!\\*)\\*{2}(?!\\*)(.+?)(?<!\\*)\\*{2}(?!\\*)", to: storage, string: string, range: range) { match in
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)
            storage.addAttribute(.font, value: boldFont, range: contentRange)
            let openMarker = NSRange(location: fullRange.location, length: 2)
            let closeMarker = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
            storage.addAttribute(.foregroundColor, value: markerColor, range: openMarker)
            storage.addAttribute(.foregroundColor, value: markerColor, range: closeMarker)
        }

        applyRegex("(?<!_)__(?!_)(.+?)(?<!_)__(?!_)", to: storage, string: string, range: range) { match in
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)
            storage.addAttribute(.font, value: boldFont, range: contentRange)
            let openMarker = NSRange(location: fullRange.location, length: 2)
            let closeMarker = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
            storage.addAttribute(.foregroundColor, value: markerColor, range: openMarker)
            storage.addAttribute(.foregroundColor, value: markerColor, range: closeMarker)
        }

        // Italic *text* or _text_
        applyRegex("(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", to: storage, string: string, range: range) { match in
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)
            storage.addAttribute(.font, value: italicFont, range: contentRange)
            let openMarker = NSRange(location: fullRange.location, length: 1)
            let closeMarker = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
            storage.addAttribute(.foregroundColor, value: markerColor, range: openMarker)
            storage.addAttribute(.foregroundColor, value: markerColor, range: closeMarker)
        }

        applyRegex("(?<!_)_(?!_)(.+?)(?<!_)_(?!_)", to: storage, string: string, range: range) { match in
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)
            storage.addAttribute(.font, value: italicFont, range: contentRange)
            let openMarker = NSRange(location: fullRange.location, length: 1)
            let closeMarker = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
            storage.addAttribute(.foregroundColor, value: markerColor, range: openMarker)
            storage.addAttribute(.foregroundColor, value: markerColor, range: closeMarker)
        }
    }

    private func applyInlineCode(storage: NSTextStorage, string: NSString, range: NSRange) {
        applyRegex("(?<!`)`(?!`)([^`]+)(?<!`)`(?!`)", to: storage, string: string, range: range) { match in
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)
            storage.addAttribute(.font, value: codeFont, range: contentRange)
            storage.addAttribute(.backgroundColor, value: inlineCodeBg, range: fullRange)
            // Dim backticks
            let openMarker = NSRange(location: fullRange.location, length: 1)
            let closeMarker = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
            storage.addAttribute(.foregroundColor, value: markerColor, range: openMarker)
            storage.addAttribute(.foregroundColor, value: markerColor, range: closeMarker)
        }
    }

    private func applyCodeBlocks(storage: NSTextStorage, string: NSString, range: NSRange) {
        // Match ``` blocks across lines
        applyRegex("^```.*$[\\s\\S]*?^```\\s*$", to: storage, string: string, range: range) { match in
            let blockRange = match.range(at: 0)
            storage.addAttributes([
                .font: codeFont,
                .backgroundColor: codeBlockBg
            ], range: blockRange)

            // Find and dim fence lines
            let blockText = string.substring(with: blockRange)
            let lines = blockText.components(separatedBy: "\n")
            var offset = blockRange.location
            for line in lines {
                let lineLen = (line as NSString).length
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") {
                    let fenceRange = NSRange(location: offset, length: lineLen)
                    storage.addAttribute(.foregroundColor, value: markerColor, range: fenceRange)
                }
                offset += lineLen + 1 // +1 for \n
            }
        }
    }

    private func applyBlockquotes(storage: NSTextStorage, string: NSString, range: NSRange) {
        applyRegex("^(>)\\s+(.*)$", to: storage, string: string, range: range) { match in
            let lineRange = match.range(at: 0)
            let markerRange = match.range(at: 1)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = 16
            paragraphStyle.firstLineHeadIndent = 16
            paragraphStyle.lineHeightMultiple = 1.6

            storage.addAttributes([
                .paragraphStyle: paragraphStyle,
                .foregroundColor: NSColor.labelColor.withAlphaComponent(blockquoteAlpha)
            ], range: lineRange)

            storage.addAttribute(.foregroundColor, value: markerColor, range: markerRange)
        }
    }

    private func applyLists(storage: NSTextStorage, string: NSString, range: NSRange) {
        // Unordered lists: - or *
        applyRegex("^(\\s*)([-*])\\s", to: storage, string: string, range: range) { match in
            let markerRange = match.range(at: 2)
            storage.addAttribute(.foregroundColor, value: markerColor, range: markerRange)
        }

        // Ordered lists: 1.
        applyRegex("^(\\s*)(\\d+\\.)\\s", to: storage, string: string, range: range) { match in
            let markerRange = match.range(at: 2)
            storage.addAttribute(.foregroundColor, value: markerColor, range: markerRange)
        }

        // Task lists: - [ ] and - [x]
        applyRegex("^(\\s*-\\s\\[[ xX]\\])\\s", to: storage, string: string, range: range) { match in
            let markerRange = match.range(at: 1)
            storage.addAttribute(.foregroundColor, value: markerColor, range: markerRange)
        }
    }

    private func applyLinks(storage: NSTextStorage, string: NSString, range: NSRange) {
        // [text](url)
        applyRegex("(\\[)([^\\]]+)(\\])(\\()([^)]+)(\\))", to: storage, string: string, range: range) { match in
            let textRange = match.range(at: 2)
            let openBracket = match.range(at: 1)
            let closeBracket = match.range(at: 3)
            let openParen = match.range(at: 4)
            let urlRange = match.range(at: 5)
            let closeParen = match.range(at: 6)

            storage.addAttributes([
                .foregroundColor: NSColor.controlAccentColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: textRange)

            for r in [openBracket, closeBracket, openParen, urlRange, closeParen] {
                storage.addAttribute(.foregroundColor, value: markerColor, range: r)
            }
        }
    }

    private func applyWikilinks(storage: NSTextStorage, string: NSString, range: NSRange) {
        applyRegex("(\\[\\[)([^\\]|]+(?:\\|[^\\]]+)?)(\\]\\])", to: storage, string: string, range: range) { match in
            let contentRange = match.range(at: 2)
            let openRange = match.range(at: 1)
            let closeRange = match.range(at: 3)

            storage.addAttributes([
                .foregroundColor: NSColor.controlAccentColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: contentRange)

            storage.addAttribute(.foregroundColor, value: markerColor, range: openRange)
            storage.addAttribute(.foregroundColor, value: markerColor, range: closeRange)
        }
    }

    private func applyHorizontalRules(storage: NSTextStorage, string: NSString, range: NSRange) {
        applyRegex("^---\\s*$", to: storage, string: string, range: range) { match in
            let lineRange = match.range(at: 0)
            storage.addAttributes([
                .foregroundColor: markerColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: NSColor.separatorColor
            ], range: lineRange)
        }
    }

    // MARK: - Regex Helper

    private func applyRegex(
        _ pattern: String,
        to storage: NSTextStorage,
        string: NSString,
        range: NSRange,
        handler: (NSTextCheckingResult) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        let matches = regex.matches(in: string as String, range: range)
        for match in matches {
            handler(match)
        }
    }
}
