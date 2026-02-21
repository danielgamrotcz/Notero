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
        context.coordinator.applyFullHighlighting()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.applyFullHighlighting()
        }

        context.coordinator.updateFontSize(fontSize)
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
        private var highlighter: MarkdownHighlighter

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
            self.highlighter = MarkdownHighlighter(fontSize: parent.fontSize)
        }

        func updateFontSize(_ size: CGFloat) {
            highlighter = MarkdownHighlighter(fontSize: size)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            parent.text = newText
            parent.onTextChange?(newText)
            applyEditHighlighting()
        }

        func applyFullHighlighting() {
            guard let textView = textView,
                  let storage = textView.textStorage else { return }
            guard !textView.string.isEmpty else { return }

            let selectedRanges = textView.selectedRanges
            storage.beginEditing()
            highlighter.highlightFull(storage: storage)
            storage.endEditing()
            textView.selectedRanges = selectedRanges
        }

        private func applyEditHighlighting() {
            guard let textView = textView,
                  let storage = textView.textStorage else { return }
            guard !textView.string.isEmpty else { return }

            let selectedRanges = textView.selectedRanges
            let fullString = textView.string as NSString
            let fullRange = NSRange(location: 0, length: fullString.length)

            storage.beginEditing()
            highlighter.highlight(storage: storage, in: fullRange, fullString: fullString)
            storage.endEditing()
            textView.selectedRanges = selectedRanges
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
