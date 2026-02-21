import SwiftUI

extension Color {
    static let editorBackground = Color("EditorBackground")
    static let editorText = Color("EditorText")

    static let darkBackground = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
    static let darkText = Color(red: 0xF5/255, green: 0xF5/255, blue: 0xF7/255)
    static let lightBackground = Color(red: 0xF5/255, green: 0xF5/255, blue: 0xF0/255)
    static let lightText = Color(red: 0x1D/255, green: 0x1D/255, blue: 0x1F/255)
}

extension NSColor {
    static let editorDarkBackground = NSColor(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255, alpha: 1)
    static let editorDarkText = NSColor(red: 0xF5/255, green: 0xF5/255, blue: 0xF7/255, alpha: 1)
    static let editorLightBackground = NSColor.white
    static let editorLightText = NSColor(red: 0x1D/255, green: 0x1D/255, blue: 0x1F/255, alpha: 1)

    static let headingColor = NSColor.secondaryLabelColor
    static let linkColor = NSColor.controlAccentColor
    static let codeBackground = NSColor.quaternaryLabelColor
}
