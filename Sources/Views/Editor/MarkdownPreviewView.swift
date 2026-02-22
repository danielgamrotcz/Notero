import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let content: String
    var onCheckboxToggle: ((Int) -> Void)?
    var onWikilinkClick: ((String) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "checkboxToggle")
        config.userContentController.add(context.coordinator, name: "wikilinkClick")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        context.coordinator.webView = webView
        webView.navigationDelegate = context.coordinator
        context.coordinator.lastContent = content

        let html = MarkdownRenderer.renderHTML(from: content)
        webView.loadHTMLString(html, baseURL: nil)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Skip update if content hasn't changed
        guard context.coordinator.lastContent != content else { return }
        context.coordinator.lastContent = content

        // If page hasn't finished loading yet, do a full load (no scroll to preserve)
        guard context.coordinator.pageLoaded else {
            let html = MarkdownRenderer.renderHTML(from: content)
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        // Page is loaded — update content via JS to preserve scroll position
        let html = MarkdownRenderer.renderHTML(from: content)

        // Escape the HTML for injection into a JS string literal
        let escaped = html
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")

        // Use a JS template literal to avoid quote escaping issues
        let js = "document.open(); document.write(`\(escaped)`); document.close();"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: MarkdownPreviewView
        weak var webView: WKWebView?
        var lastContent: String = ""
        var pageLoaded: Bool = false

        init(_ parent: MarkdownPreviewView) {
            self.parent = parent
        }

        // Called when initial page finishes loading
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "checkboxToggle", let index = message.body as? Int {
                parent.onCheckboxToggle?(index)
            } else if message.name == "wikilinkClick", let linkName = message.body as? String {
                parent.onWikilinkClick?(linkName)
            }
        }
    }
}
