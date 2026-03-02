import SwiftUI

struct FindReplaceView: View {
    @Binding var content: String
    @Binding var isVisible: Bool
    @State var showReplace: Bool

    @State private var findText = ""
    @State private var replaceText = ""
    @State private var caseSensitive = false
    @State private var useRegex = false
    @State private var wholeWord = false
    @State private var currentMatch = 0
    @State private var totalMatches = 0
    @State private var regexError: String?

    var body: some View {
        VStack(spacing: 6) {
            // Find row
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    TextField("Find...", text: $findText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit { findNext() }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(regexError != nil ? Color.red : Color(nsColor: .separatorColor), lineWidth: 0.5)
                )

                if !findText.isEmpty {
                    Text("\(currentMatch) of \(totalMatches)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: 50)
                }

                // Options
                Toggle("Aa", isOn: $caseSensitive)
                    .toggleStyle(.button)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .help("Case sensitive")

                Toggle(".*", isOn: $useRegex)
                    .toggleStyle(.button)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .help("Regular expression")

                Toggle("ab", isOn: $wholeWord)
                    .toggleStyle(.button)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .help("Whole word")

                Button { findPrevious() } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .help("Previous match (Cmd+Shift+G)")

                Button { findNext() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .help("Next match (Cmd+G)")

                if !showReplace {
                    Button {
                        showReplace = true
                    } label: {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .help("Show replace")
                }

                Button {
                    isVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            // Replace row
            if showReplace {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                        TextField("Replace...", text: $replaceText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )

                    Button("Replace") {
                        replaceCurrent()
                    }
                    .buttonStyle(.bordered)
                    .disabled(totalMatches == 0)

                    Button("Replace All") {
                        replaceAll()
                    }
                    .buttonStyle(.bordered)
                    .disabled(totalMatches == 0)

                    Spacer()
                }
            }

            if let error = regexError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .onChange(of: findText) { _, _ in updateMatches() }
        .onChange(of: caseSensitive) { _, _ in updateMatches() }
        .onChange(of: useRegex) { _, _ in updateMatches() }
        .onChange(of: wholeWord) { _, _ in updateMatches() }
        .onChange(of: content) { _, _ in updateMatches() }
    }

    // MARK: - Find Logic

    private func buildRegex() -> NSRegularExpression? {
        regexError = nil
        var pattern = findText
        guard !pattern.isEmpty else { return nil }

        if !useRegex {
            pattern = NSRegularExpression.escapedPattern(for: pattern)
        }

        if wholeWord {
            pattern = "\\b\(pattern)\\b"
        }

        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }

        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            regexError = "Invalid regex: \(error.localizedDescription)"
            return nil
        }
    }

    private func allMatches() -> [NSTextCheckingResult] {
        guard let regex = buildRegex() else { return [] }
        let nsContent = content as NSString
        return regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
    }

    private func updateMatches() {
        let matches = allMatches()
        totalMatches = matches.count
        if currentMatch > totalMatches { currentMatch = totalMatches }
        if currentMatch == 0 && totalMatches > 0 { currentMatch = 1 }
        if totalMatches == 0 { currentMatch = 0 }
        scrollToCurrentMatch()
    }

    private func findNext() {
        guard totalMatches > 0 else { return }
        currentMatch = currentMatch < totalMatches ? currentMatch + 1 : 1
        scrollToCurrentMatch()
    }

    private func findPrevious() {
        guard totalMatches > 0 else { return }
        currentMatch = currentMatch > 1 ? currentMatch - 1 : totalMatches
        scrollToCurrentMatch()
    }

    private func scrollToCurrentMatch() {
        let matches = allMatches()
        guard currentMatch > 0, currentMatch <= matches.count else { return }
        let range = matches[currentMatch - 1].range
        NotificationCenter.default.post(
            name: .scrollToFindMatch, object: nil,
            userInfo: ["range": NSValue(range: range)]
        )
    }

    private func replaceCurrent() {
        let matches = allMatches()
        guard currentMatch > 0, currentMatch <= matches.count else { return }
        let match = matches[currentMatch - 1]
        guard let range = Range(match.range, in: content) else { return }

        var replacement = replaceText
        if useRegex {
            replacement = buildRegex()?.replacementString(
                for: match, in: content, offset: 0, template: replaceText
            ) ?? replaceText
        }

        content.replaceSubrange(range, with: replacement)
        updateMatches()
    }

    private func replaceAll() {
        guard let regex = buildRegex() else { return }
        let nsContent = content as NSString
        content = regex.stringByReplacingMatches(
            in: content,
            range: NSRange(location: 0, length: nsContent.length),
            withTemplate: replaceText
        )
        updateMatches()
    }
}
