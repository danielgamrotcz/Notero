import SwiftUI

struct ReMarkableSettingsView: View {
    @State private var isConnected = false
    @State private var binaryPath = "Not found"

    var body: some View {
        Form {
            Section("Connection") {
                HStack {
                    Text("rmapi binary:")
                    Spacer()
                    Text(binaryPath)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Text("Status:")
                    Spacer()
                    if binaryPath == "Not found" {
                        Label("rmapi not installed", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    } else if isConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not authenticated", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            if binaryPath == "Not found" {
                Section("Setup") {
                    Text("Install rmapi to enable sending notes to reMarkable:")
                        .font(.callout)

                    Text("brew install io41/tap/rmapi")
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)

                    Text("Then run rmapi once in Terminal to authenticate with your reMarkable account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !isConnected {
                Section("Authentication") {
                    Text("Run rmapi in Terminal to authenticate:")
                        .font(.callout)

                    Text("rmapi")
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)

                    Text("You will need a one-time code from my.remarkable.com/connect/desktop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Info") {
                Text("Notes are uploaded as PDFs to the /Notero folder on your reMarkable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Use Cmd+Shift+R or File > Send to reMarkable to send the current note.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            let service = ReMarkableService.shared
            binaryPath = await service.findRmapiBinary() ?? "Not found"
            isConnected = await service.isAuthenticated()
        }
    }
}
