import SwiftUI
import AppKit

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let showLineNumbers: Bool
    let spellCheck: Bool
    var onTextChange: ((String) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = MarkdownTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = spellCheck
        textView.usesFindBar = true

        if let textContainer = textView.textContainer {
            textContainer.containerSize = NSSize(
                width: scrollView.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
            textContainer.widthTracksTextView = true
        }

        let defaultParagraphStyle = NSMutableParagraphStyle()
        defaultParagraphStyle.lineHeightMultiple = 1.6
        textView.defaultParagraphStyle = defaultParagraphStyle
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .paragraphStyle: defaultParagraphStyle,
            .foregroundColor: NSColor.labelColor
        ]

        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applyHighlighting()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.applyHighlighting()
        }

        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.isContinuousSpellCheckingEnabled = spellCheck

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.6
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        weak var textView: MarkdownTextView?

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            parent.text = newText
            parent.onTextChange?(newText)
            applyHighlighting()
        }

        func applyHighlighting() {
            guard let textView = textView else { return }
            let text = textView.string
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            guard let storage = textView.textStorage else { return }

            let selectedRanges = textView.selectedRanges

            storage.beginEditing()

            let defaultFont = NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = 1.6

            // Reset to default
            storage.addAttributes([
                .font: defaultFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ], range: fullRange)

            // Headings
            applyPattern("^#{1,6}\\s+.*$", to: storage, in: text, attributes: [
                .foregroundColor: NSColor.headingColor,
                .font: NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .semibold)
            ])

            // Bold
            applyPattern("\\*\\*[^*]+\\*\\*", to: storage, in: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .bold)
            ])

            // Italic
            applyPattern("(?<!\\*)\\*(?!\\*)[^*]+(?<!\\*)\\*(?!\\*)", to: storage, in: text, attributes: [
                .font: NSFont(descriptor: defaultFont.fontDescriptor.withSymbolicTraits(.italic), size: parent.fontSize) ?? defaultFont
            ])

            // Inline code
            applyPattern("`[^`]+`", to: storage, in: text, attributes: [
                .backgroundColor: NSColor.codeBackground
            ])

            // Code blocks
            applyPattern("```[\\s\\S]*?```", to: storage, in: text, attributes: [
                .backgroundColor: NSColor.codeBackground
            ])

            // Links [text](url)
            applyPattern("\\[([^\\]]+)\\]\\(([^)]+)\\)", to: storage, in: text, attributes: [
                .foregroundColor: NSColor.linkColor
            ])

            // Wikilinks [[text]]
            applyPattern("\\[\\[[^\\]]+\\]\\]", to: storage, in: text, attributes: [
                .foregroundColor: NSColor.linkColor
            ])

            // Blockquotes
            applyPattern("^>\\s+.*$", to: storage, in: text, attributes: [
                .foregroundColor: NSColor.secondaryLabelColor
            ])

            // Task checkboxes
            applyPattern("^-\\s+\\[[ xX]\\]", to: storage, in: text, attributes: [
                .foregroundColor: NSColor.controlAccentColor
            ])

            // URLs
            applyPattern("https?://\\S+", to: storage, in: text, attributes: [
                .foregroundColor: NSColor.linkColor
            ])

            storage.endEditing()

            textView.selectedRanges = selectedRanges
        }

        private func applyPattern(
            _ pattern: String,
            to storage: NSTextStorage,
            in text: String,
            attributes: [NSAttributedString.Key: Any]
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            let range = NSRange(location: 0, length: (text as NSString).length)
            for match in regex.matches(in: text, range: range) {
                storage.addAttributes(attributes, range: match.range)
            }
        }
    }
}

class MarkdownTextView: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string]
    }
}
