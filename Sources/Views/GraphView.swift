import SwiftUI
import WebKit

struct GraphView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var showOrphans = true
    @State private var showLabels = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                TextField("Search nodes...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Toggle("Orphans", isOn: $showOrphans)
                    .toggleStyle(.checkbox)
                Toggle("Labels", isOn: $showLabels)
                    .toggleStyle(.checkbox)

                Button("Reset Layout") {
                    NotificationCenter.default.post(name: .graphResetLayout, object: nil)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(8)
            .background(.ultraThinMaterial)

            Divider()

            GraphWebView(
                appState: appState,
                searchText: searchText,
                showOrphans: showOrphans,
                showLabels: showLabels
            )
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct GraphWebView: NSViewRepresentable {
    let appState: AppState
    let searchText: String
    let showOrphans: Bool
    let showLabels: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "nodeClick")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        let html = buildGraphHTML()
        webView.loadHTMLString(html, baseURL: nil)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.resetLayout),
            name: .graphResetLayout,
            object: nil
        )

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let js = "updateFilter('\(searchText.replacingOccurrences(of: "'", with: "\\'"))', \(showOrphans), \(showLabels));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        let appState: AppState
        weak var webView: WKWebView?

        init(appState: AppState) {
            self.appState = appState
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "nodeClick", let path = message.body as? String else { return }
            let url = appState.vaultManager.vaultURL.appendingPathComponent(path)
            Task { @MainActor in
                appState.openNote(url: url)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }

        @objc func resetLayout() {
            webView?.evaluateJavaScript("resetLayout();", completionHandler: nil)
        }
    }

    @MainActor
    private func buildGraphHTML() -> String {
        let graphJSON = GraphDataProvider.graphDataJSON(
            vaultManager: appState.vaultManager,
            pinnedManager: appState.pinnedNotesManager,
            favoritesManager: appState.favoritesManager
        )

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        * { margin: 0; padding: 0; }
        body { background: #0D0A14; overflow: hidden; }
        svg { width: 100vw; height: 100vh; }
        </style>
        <script src="https://d3js.org/d3.v7.min.js"></script>
        </head>
        <body>
        <svg></svg>
        <script>
        const data = \(graphJSON);
        const width = window.innerWidth;
        const height = window.innerHeight;

        const svg = d3.select("svg")
            .attr("width", width)
            .attr("height", height);

        const g = svg.append("g");

        const zoom = d3.zoom()
            .scaleExtent([0.1, 5])
            .on("zoom", (event) => g.attr("transform", event.transform));
        svg.call(zoom);

        const simulation = d3.forceSimulation(data.nodes)
            .force("link", d3.forceLink(data.edges).id(d => d.id).distance(120))
            .force("charge", d3.forceManyBody().strength(-200))
            .force("center", d3.forceCenter(width/2, height/2))
            .force("collision", d3.forceCollide().radius(d => nodeRadius(d) + 2));

        const link = g.append("g")
            .selectAll("line")
            .data(data.edges)
            .join("line")
            .attr("stroke", "white")
            .attr("stroke-opacity", 0.15)
            .attr("stroke-width", 1);

        const node = g.append("g")
            .selectAll("circle")
            .data(data.nodes)
            .join("circle")
            .attr("r", d => nodeRadius(d))
            .attr("fill", d => nodeColor(d))
            .attr("opacity", d => isOrphan(d) ? 0.6 : 1)
            .call(d3.drag()
                .on("start", dragstarted)
                .on("drag", dragged)
                .on("end", dragended))
            .on("click", (event, d) => {
                window.webkit.messageHandlers.nodeClick.postMessage(d.path);
            });

        const label = g.append("g")
            .selectAll("text")
            .data(data.nodes)
            .join("text")
            .text(d => d.label)
            .attr("fill", "white")
            .attr("font-size", "11px")
            .attr("font-family", "-apple-system, sans-serif")
            .attr("dx", d => nodeRadius(d) + 4)
            .attr("dy", 4)
            .attr("opacity", 0);

        node.on("mouseenter", (event, d) => {
            const neighbors = new Set();
            data.edges.forEach(e => {
                if (e.source.id === d.id) neighbors.add(e.target.id);
                if (e.target.id === d.id) neighbors.add(e.source.id);
            });
            neighbors.add(d.id);

            node.attr("opacity", n => neighbors.has(n.id) ? 1 : 0.15);
            link.attr("stroke-opacity", l =>
                (l.source.id === d.id || l.target.id === d.id) ? 0.6 : 0.05);
            label.attr("opacity", n => neighbors.has(n.id) ? 1 : 0);
        }).on("mouseleave", () => {
            node.attr("opacity", d => isOrphan(d) ? 0.6 : 1);
            link.attr("stroke-opacity", 0.15);
            label.attr("opacity", _showLabels ? 1 : 0);
        });

        simulation.on("tick", () => {
            link.attr("x1", d => d.source.x).attr("y1", d => d.source.y)
                .attr("x2", d => d.target.x).attr("y2", d => d.target.y);
            node.attr("cx", d => d.x).attr("cy", d => d.y);
            label.attr("x", d => d.x).attr("y", d => d.y);
        });

        function nodeRadius(d) {
            return Math.max(6, Math.min(22, 6 + Math.sqrt(d.wordCount) * 0.3));
        }

        function nodeColor(d) {
            if (d.isFavorite) return "#FFD60A";
            if (d.isPinned) return "#007AFF";
            return "white";
        }

        function isOrphan(d) {
            return !data.edges.some(e => e.source.id === d.id || e.target.id === d.id ||
                e.source === d.id || e.target === d.id);
        }

        let _showLabels = false;

        function updateFilter(search, showOrphans, showLabels) {
            _showLabels = showLabels;
            const lowerSearch = search.toLowerCase();
            node.attr("opacity", d => {
                if (!showOrphans && isOrphan(d)) return 0;
                if (search && !d.label.toLowerCase().includes(lowerSearch)) return 0.1;
                return isOrphan(d) ? 0.6 : 1;
            });
            label.attr("opacity", d => {
                if (!showOrphans && isOrphan(d)) return 0;
                if (search && !d.label.toLowerCase().includes(lowerSearch)) return 0;
                return showLabels ? 1 : 0;
            });
        }

        function resetLayout() {
            data.nodes.forEach(d => { d.fx = null; d.fy = null; });
            simulation.alpha(1).restart();
        }

        function dragstarted(event, d) {
            if (!event.active) simulation.alphaTarget(0.3).restart();
            d.fx = d.x; d.fy = d.y;
        }
        function dragged(event, d) {
            d.fx = event.x; d.fy = event.y;
        }
        function dragended(event, d) {
            if (!event.active) simulation.alphaTarget(0);
        }
        </script>
        </body>
        </html>
        """
    }
}

extension Notification.Name {
    static let graphResetLayout = Notification.Name("graphResetLayout")
}
