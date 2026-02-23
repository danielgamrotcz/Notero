import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let content: String
    var onCheckboxToggle: ((Int) -> Void)?
    var onWikilinkClick: ((String) -> Void)?
    var initialScrollFraction: CGFloat = 0
    var scrollFractionWriter: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "checkboxToggle")
        config.userContentController.add(context.coordinator, name: "wikilinkClick")
        config.userContentController.add(context.coordinator, name: "scrollFraction")

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

        let coordinator = context.coordinator

        // If page hasn't finished loading yet, do a full load (no scroll to preserve)
        guard coordinator.pageLoaded else {
            let html = MarkdownRenderer.renderHTML(from: content)
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        // Page is loaded — update content via innerHTML + base64 to preserve scroll position
        let bodyHTML = MarkdownRenderer.renderBodyHTML(from: content)
        let base64 = Data(bodyHTML.utf8).base64EncodedString()

        let js = """
        (function() {
            var el = document.getElementById('content');
            if (!el) return false;
            var binary = atob('\(base64)');
            var bytes = new Uint8Array(binary.length);
            for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
            el.innerHTML = new TextDecoder().decode(bytes);
            attachListeners();
            hljs.highlightAll();
            return true;
        })();
        """

        webView.evaluateJavaScript(js) { result, error in
            // If JS update failed or content div not found, fall back to full page load
            if error != nil || result as? Bool != true {
                coordinator.pageLoaded = false
                let html = MarkdownRenderer.renderHTML(from: coordinator.lastContent)
                webView.loadHTMLString(html, baseURL: nil)
            }
        }
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
            let fraction = parent.initialScrollFraction
            if fraction > 0 {
                let js = "window.scrollTo(0, \(fraction) * (document.documentElement.scrollHeight - window.innerHeight));"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
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
            } else if message.name == "scrollFraction", let fraction = message.body as? Double {
                parent.scrollFractionWriter?(CGFloat(fraction))
            }
        }
    }
}
