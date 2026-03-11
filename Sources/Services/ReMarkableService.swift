import Foundation

enum ReMarkableError: LocalizedError {
    case rmapiBinaryNotFound
    case notAuthenticated
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .rmapiBinaryNotFound:
            return "rmapi not found. Install via: brew install io41/tap/rmapi"
        case .notAuthenticated:
            return "Not authenticated with reMarkable Cloud. Run 'rmapi' in Terminal to set up."
        case .uploadFailed(let msg):
            return "Upload failed: \(msg)"
        }
    }
}

actor ReMarkableService {

    static let shared = ReMarkableService()

    /// Target folder on reMarkable. Created automatically if missing.
    private let remarkableFolder = "/Notero"

    // MARK: - Binary Discovery

    func findRmapiBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/rmapi",
            "/usr/local/bin/rmapi",
            "\(NSHomeDirectory())/go/bin/rmapi",
            "\(NSHomeDirectory())/.local/bin/rmapi"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        let result = shell("which rmapi")
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0 && !path.isEmpty {
            return path
        }

        return nil
    }

    // MARK: - Authentication

    func isAuthenticated() -> Bool {
        let home = NSHomeDirectory()
        let configPaths = [
            "\(home)/Library/Application Support/rmapi/rmapi.conf",
            "\(home)/.rmapi",
            "\(home)/.config/rmapi/.rmapi",
            "\(home)/.config/rmapi/rmapi.conf"
        ]
        return configPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Upload

    func uploadPDF(at pdfPath: URL, name: String) async throws {
        guard let binary = findRmapiBinary() else {
            throw ReMarkableError.rmapiBinaryNotFound
        }

        guard isAuthenticated() else {
            throw ReMarkableError.notAuthenticated
        }

        // Ensure /Notero folder exists (exit code 1 if already exists — OK)
        _ = shell("\(binary) mkdir \(remarkableFolder)")

        // Remove existing file so re-upload works (exit code 1 if not found — OK)
        _ = shell("\(binary) rm \"\(remarkableFolder)/\(name)\"")

        let result = shell("\(binary) put \"\(pdfPath.path)\" \"\(remarkableFolder)\"")

        if result.exitCode != 0 {
            let message = result.error.isEmpty ? result.output : result.error
            throw ReMarkableError.uploadFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Shell Helper

    private func shell(_ command: String) -> (output: String, error: String, exitCode: Int32) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(existingPath)"
        } else {
            env["PATH"] = extraPaths
        }
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ("", error.localizedDescription, -1)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        return (
            String(data: outputData, encoding: .utf8) ?? "",
            String(data: errorData, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }
}
