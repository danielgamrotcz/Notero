import Foundation

enum MarkdownRenderer {
    /// Returns only the converted markdown HTML (no wrapper, no scripts).
    static func renderBodyHTML(from markdown: String) -> String {
        var html = markdown
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        html = processCodeBlocks(html)
        html = processBlockquotes(html)
        html = processHeadings(html)
        html = processHorizontalRules(html)
        html = processLists(html)
        html = processTaskLists(html)
        html = processTables(html)
        html = processParagraphs(html)

        html = processBold(html)
        html = processItalic(html)
        html = processInlineCode(html)
        html = processLinks(html)
        html = processWikilinks(html)
        html = processImages(html)

        return html
    }

    static func renderHTML(from markdown: String, cssPath: String? = nil) -> String {
        let bodyHTML = renderBodyHTML(from: markdown)

        let css: String
        if let cssPath = cssPath {
            css = "<link rel='stylesheet' href='\(cssPath)'>"
        } else {
            css = "<style>\(defaultCSS)</style>"
        }

        let hljsScript = Self.bundledResource("highlight.min", ext: "js") ?? ""
        let hljsDarkCSS = Self.bundledResource("github-dark.min", ext: "css") ?? ""
        let hljsLightCSS = Self.bundledResource("github.min", ext: "css") ?? ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(css)
        <style media="(prefers-color-scheme: dark)">\(hljsDarkCSS)</style>
        <style media="(prefers-color-scheme: light)">\(hljsLightCSS)</style>
        <script>\(hljsScript)</script>
        </head>
        <body>
        <div id="content">\(bodyHTML)</div>
        <script>
        function attachListeners() {
            document.querySelectorAll('input[type="checkbox"]').forEach(function(cb, i) {
                cb.addEventListener('change', function() {
                    window.webkit.messageHandlers.checkboxToggle.postMessage(i);
                });
            });
            document.querySelectorAll('a[data-wikilink]').forEach(function(a) {
                a.addEventListener('click', function(e) {
                    e.preventDefault();
                    window.webkit.messageHandlers.wikilinkClick.postMessage(a.dataset.wikilink);
                });
            });
        }
        attachListeners();
        hljs.highlightAll();
        </script>
        </body>
        </html>
        """
    }

    private static func bundledResource(_ name: String, ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Block Elements

    private static func processCodeBlocks(_ html: String) -> String {
        let pattern = "```(\\w*)\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(in: html, range: range,
            withTemplate: "<pre><code class=\"language-$1\">$2</code></pre>")
    }

    private static func processBlockquotes(_ html: String) -> String {
        html.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("&gt; ") {
                return "<blockquote>\(String(trimmed.dropFirst(5)))</blockquote>"
            }
            return line
        }.joined(separator: "\n")
    }

    private static func processHeadings(_ html: String) -> String {
        html.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#### ") { return "<h4>\(String(trimmed.dropFirst(5)))</h4>" }
            if trimmed.hasPrefix("### ") { return "<h3>\(String(trimmed.dropFirst(4)))</h3>" }
            if trimmed.hasPrefix("## ") { return "<h2>\(String(trimmed.dropFirst(3)))</h2>" }
            if trimmed.hasPrefix("# ") { return "<h1>\(String(trimmed.dropFirst(2)))</h1>" }
            return line
        }.joined(separator: "\n")
    }

    private static func processHorizontalRules(_ html: String) -> String {
        html.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                return "<hr>"
            }
            return line
        }.joined(separator: "\n")
    }

    private static func processLists(_ html: String) -> String {
        var result: [String] = []
        var inList = false
        var listType = ""

        for line in html.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isUnordered = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
            let isOrdered = trimmed.range(of: "^\\d+\\. ", options: .regularExpression) != nil
            let isTaskItem = trimmed.hasPrefix("- [")

            if isTaskItem {
                result.append(line)
                continue
            }

            if isUnordered && !inList {
                inList = true; listType = "ul"
                result.append("<ul>")
            } else if isOrdered && !inList {
                inList = true; listType = "ol"
                result.append("<ol>")
            }

            if inList {
                if isUnordered || isOrdered {
                    let content = isUnordered ? String(trimmed.dropFirst(2)) :
                        trimmed.replacingOccurrences(of: "^\\d+\\. ", with: "", options: .regularExpression)
                    result.append("<li>\(content)</li>")
                } else {
                    result.append("</\(listType)>")
                    inList = false
                    result.append(line)
                }
            } else {
                result.append(line)
            }
        }
        if inList { result.append("</\(listType)>") }

        return result.joined(separator: "\n")
    }

    private static func processTaskLists(_ html: String) -> String {
        let lines = html.components(separatedBy: "\n")
        var result: [String] = []
        var index = 0
        var inTaskList = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isTask = trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") || trimmed.hasPrefix("- [ ] ")

            if isTask {
                if !inTaskList {
                    result.append("")
                    result.append("<div class='task-list'>")
                    inTaskList = true
                }
                let checked = trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ")
                let content = String(trimmed.dropFirst(6))
                let checkedAttr = checked ? " checked" : ""
                result.append("<label><input type='checkbox'\(checkedAttr) data-index='\(index)'> \(content)</label><br>")
                index += 1
            } else {
                if inTaskList {
                    result.append("</div>")
                    result.append("")
                    inTaskList = false
                }
                result.append(line)
            }
        }

        if inTaskList {
            result.append("</div>")
        }

        return result.joined(separator: "\n")
    }

    private static func processTables(_ html: String) -> String {
        let lines = html.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.contains("|") && i + 1 < lines.count {
                let nextLine = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if nextLine.contains("---") && nextLine.contains("|") {
                    // Table header
                    result.append("<table><thead><tr>")
                    let headers = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    for h in headers where !h.isEmpty {
                        result.append("<th>\(h)</th>")
                    }
                    result.append("</tr></thead><tbody>")
                    i += 2

                    // Table rows
                    while i < lines.count {
                        let rowLine = lines[i].trimmingCharacters(in: .whitespaces)
                        guard rowLine.contains("|") else { break }
                        result.append("<tr>")
                        let cells = rowLine.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                        for c in cells where !c.isEmpty {
                            result.append("<td>\(c)</td>")
                        }
                        result.append("</tr>")
                        i += 1
                    }
                    result.append("</tbody></table>")
                    continue
                }
            }
            result.append(lines[i])
            i += 1
        }

        return result.joined(separator: "\n")
    }

    private static func processParagraphs(_ html: String) -> String {
        html.components(separatedBy: "\n\n").map { block in
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "" }
            if trimmed.hasPrefix("<") { return trimmed }
            return "<p>\(trimmed)</p>"
        }.joined(separator: "\n")
    }

    // MARK: - Inline Elements

    private static func processBold(_ html: String) -> String {
        replacePattern("\\*\\*(.+?)\\*\\*", in: html, with: "<strong>$1</strong>")
    }

    private static func processItalic(_ html: String) -> String {
        replacePattern("(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", in: html, with: "<em>$1</em>")
    }

    private static func processInlineCode(_ html: String) -> String {
        replacePattern("`([^`]+)`", in: html, with: "<code>$1</code>")
    }

    private static func processLinks(_ html: String) -> String {
        replacePattern("\\[([^\\]]+)\\]\\(([^)]+)\\)", in: html, with: "<a href='$2'>$1</a>")
    }

    private static func processWikilinks(_ html: String) -> String {
        let pattern = "\\[\\[([^\\]|]+)(?:\\|([^\\]]+))?\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let range = NSRange(html.startIndex..., in: html)
        var result = html

        let matches = regex.matches(in: html, range: range).reversed()
        for match in matches {
            guard let fullRange = Range(match.range, in: result),
                  let linkRange = Range(match.range(at: 1), in: result)
            else { continue }

            let linkName = String(result[linkRange])
            let displayText: String
            if match.numberOfRanges > 2, let displayRange = Range(match.range(at: 2), in: result) {
                displayText = String(result[displayRange])
            } else {
                displayText = linkName
            }
            let replacement = "<a href='#' data-wikilink='\(linkName)'>\(displayText)</a>"
            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    private static func processImages(_ html: String) -> String {
        replacePattern("!\\[([^\\]]*)\\]\\(([^)]+)\\)", in: html, with: "<img src='$2' alt='$1'>")
    }

    private static func replacePattern(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    // MARK: - Default CSS

    static let defaultCSS = """
    :root {
        color-scheme: light dark;
    }
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
        font-size: 16px;
        line-height: 1.7;
        max-width: 700px;
        margin: 0 auto;
        padding: 20px 40px;
    }
    @media (prefers-color-scheme: dark) {
        body { background: transparent; color: #F5F5F7; }
        a { color: #6CB4EE; }
        blockquote { border-color: #555; color: #aaa; }
        code { background: #2C2C2E; }
        pre { background: #2C2C2E; }
        table { border-color: #444; }
        th, td { border-color: #444; }
        hr { border-color: #444; }
    }
    @media (prefers-color-scheme: light) {
        body { background: transparent; color: #1D1D1F; }
        a { color: #0066CC; }
        blockquote { border-color: #ddd; color: #666; }
        code { background: #f4f4f4; }
        pre { background: #f4f4f4; }
        table { border-color: #ddd; }
        th, td { border-color: #ddd; }
    }
    h1, h2, h3 { font-weight: 600; margin-top: 1.5em; }
    h1 { font-size: 1.8em; }
    h2 { font-size: 1.4em; }
    h3 { font-size: 1.2em; }
    code { font-family: 'SF Mono', Menlo, monospace; padding: 2px 6px; border-radius: 4px; font-size: 0.9em; }
    pre { padding: 16px; border-radius: 8px; overflow-x: auto; }
    pre code { padding: 0; background: none; }
    blockquote { border-left: 3px solid; padding-left: 16px; margin-left: 0; font-style: italic; }
    img { max-width: 100%; border-radius: 8px; }
    table { border-collapse: collapse; width: 100%; margin: 1em 0; }
    th, td { border: 1px solid; padding: 8px 12px; text-align: left; }
    th { font-weight: 600; }
    hr { border: none; border-top: 1px solid; margin: 2em 0; }
    input[type="checkbox"] { margin-right: 6px; }
    label { cursor: pointer; }
    a[data-wikilink] { text-decoration: underline dotted; }
    """
}
