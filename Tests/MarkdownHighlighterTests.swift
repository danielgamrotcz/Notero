import XCTest
import AppKit
@testable import Notero

final class MarkdownHighlighterTests: XCTestCase {
    private let highlighter = MarkdownHighlighter(fontSize: 14)

    private func makeStorage(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        storage.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.white
        ], range: NSRange(location: 0, length: storage.length))
        return storage
    }

    func testHighlightDoesNotMutateString() {
        let text = "# Hello\n\nThis is **bold** and *italic*."
        let storage = makeStorage(text)
        highlighter.highlightFull(storage: storage)
        XCTAssertEqual(storage.string, text, "Highlighting must not change text content")
    }

    func testHeadingGetsSemiboldFont() {
        let text = "# Title"
        let storage = makeStorage(text)
        highlighter.highlightFull(storage: storage)

        // Check that characters after "# " get a larger font
        let attrs = storage.attributes(at: 2, effectiveRange: nil)
        if let font = attrs[.font] as? NSFont {
            XCTAssertGreaterThan(font.pointSize, 14, "H1 should be larger than body")
        }
    }

    func testBoldGetsApplied() {
        let text = "Hello **bold** world"
        let storage = makeStorage(text)
        highlighter.highlightFull(storage: storage)

        // Check middle of "bold" (index 8)
        let attrs = storage.attributes(at: 8, effectiveRange: nil)
        if let font = attrs[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            XCTAssertTrue(traits.contains(.boldFontMask), "Text between ** should be bold")
        }
    }

    func testMarkersAreDimmed() {
        let text = "**bold**"
        let storage = makeStorage(text)
        highlighter.highlightFull(storage: storage)

        // Check first character (the opening **)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        if let color = attrs[.foregroundColor] as? NSColor {
            // Dimmed markers should have lower alpha than normal text
            XCTAssertLessThan(color.alphaComponent, 1.0, "Markers should be dimmed")
        }
    }

    func testInlineCodeGetsMonospacedFont() {
        let text = "Use `code` here"
        let storage = makeStorage(text)
        highlighter.highlightFull(storage: storage)

        // Check middle of "code" (index 5)
        let attrs = storage.attributes(at: 5, effectiveRange: nil)
        if let font = attrs[.font] as? NSFont {
            XCTAssertTrue(font.fontName.lowercased().contains("mono") ||
                          font.fontDescriptor.symbolicTraits.contains(.monoSpace),
                          "Code should use monospaced font")
        }
    }

    // Required tests from test suite spec

    func testHeading1FontSize() {
        let text = "# Title"
        let storage = makeStorage(text)
        highlighter.highlightFull(storage: storage)

        let attrs = storage.attributes(at: 2, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        XCTAssertNotNil(font)
        XCTAssertEqual(font?.pointSize, 28, "H1 should be 28pt")
    }

    func testHeading2FontSize() {
        let text = "## Subtitle"
        let storage = makeStorage(text)
        highlighter.highlightFull(storage: storage)

        let attrs = storage.attributes(at: 3, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        XCTAssertNotNil(font)
        XCTAssertEqual(font?.pointSize, 22, "H2 should be 22pt")
    }

    func testBoldAttribute() {
        let text = "Hello **bold** world"
        let storage = makeStorage(text)
        highlighter.highlightFull(storage: storage)

        let attrs = storage.attributes(at: 8, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        XCTAssertNotNil(font)
        let traits = NSFontManager.shared.traits(of: font!)
        XCTAssertTrue(traits.contains(.boldFontMask), "Text between ** should be bold")
    }

    func testItalicAttribute() {
        let text = "Hello *italic* world"
        let storage = makeStorage(text)
        highlighter.highlightFull(storage: storage)

        let attrs = storage.attributes(at: 7, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        XCTAssertNotNil(font)
        let traits = NSFontManager.shared.traits(of: font!)
        XCTAssertTrue(traits.contains(.italicFontMask), "Text between * should be italic")
    }

    func testMarkersAreNotRemoved() {
        let text = "**bold** and *italic*"
        let storage = makeStorage(text)
        highlighter.highlightFull(storage: storage)

        XCTAssertEqual(storage.string, text,
                       "Markers must remain in the string after highlighting")
    }

    func testCodeInlineBackground() {
        let text = "Use `code` here"
        let storage = makeStorage(text)
        highlighter.highlightFull(storage: storage)

        let attrs = storage.attributes(at: 5, effectiveRange: nil)
        let bg = attrs[.backgroundColor] as? NSColor
        XCTAssertNotNil(bg, "Inline code should have a background color")
    }

    func testCursorDoesNotShift() {
        let text = "# Hello **world** `code` *italic*"
        let storage = makeStorage(text)
        let originalLength = storage.length
        highlighter.highlightFull(storage: storage)

        XCTAssertEqual(storage.length, originalLength,
                       "Applying attributes must not change string length")
    }

    func testBlockquoteIndent() {
        let text = "> This is a quote"
        let storage = makeStorage(text)
        highlighter.highlightFull(storage: storage)

        let attrs = storage.attributes(at: 2, effectiveRange: nil)
        let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
        XCTAssertNotNil(paragraphStyle)
        XCTAssertGreaterThan(paragraphStyle?.headIndent ?? 0, 0,
                             "Blockquote should have paragraph indent")
    }

    func testNoStringMutationInProcessEditing() {
        let text = "# Test **bold** `code`"
        let storage = NSTextStorage(string: text)
        storage.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.white
        ], range: NSRange(location: 0, length: storage.length))

        let originalString = storage.string
        highlighter.highlightFull(storage: storage)

        XCTAssertEqual(storage.string, originalString,
                       "replaceCharacters should never be called — string must stay identical")
    }
}
