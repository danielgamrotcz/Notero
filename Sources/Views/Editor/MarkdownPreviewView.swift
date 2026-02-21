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
        context.coordinator.webView = webView

        let html = MarkdownRenderer.renderHTML(from: content)
        webView.loadHTMLString(html, baseURL: nil)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = MarkdownRenderer.renderHTML(from: content)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: MarkdownPreviewView
        weak var webView: WKWebView?

        init(_ parent: MarkdownPreviewView) {
            self.parent = parent
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
