import os

enum Log {
    static let general = os.Logger(subsystem: "cz.danielgamrot.Notero", category: "general")
    static let vault = os.Logger(subsystem: "cz.danielgamrot.Notero", category: "vault")
    static let search = os.Logger(subsystem: "cz.danielgamrot.Notero", category: "search")
    static let editor = os.Logger(subsystem: "cz.danielgamrot.Notero", category: "editor")
    static let ai = os.Logger(subsystem: "cz.danielgamrot.Notero", category: "ai")
    static let sync = os.Logger(subsystem: "cz.danielgamrot.Notero", category: "sync")
}
