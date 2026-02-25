import SwiftUI
import AppKit

struct WikiLinkCompletionView: View {
    let results: [(name: String, url: URL)]
    let selectedIndex: Int
    let onSelect: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.offset) { offset, note in
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(note.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            offset == selectedIndex
                                ? Color.accentColor.opacity(0.2)
                                : Color.clear
                        )
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(note.name) }
                        .id(offset)
                    }
                }
                .padding(4)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(width: 260)
        .frame(maxHeight: 200)
        .background(.ultraThickMaterial)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

final class WikiLinkCompletionPanel {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<WikiLinkCompletionView>?

    func show(
        relativeTo rect: NSRect,
        in parentWindow: NSWindow,
        results: [(name: String, url: URL)],
        selectedIndex: Int,
        onSelect: @escaping (String) -> Void
    ) {
        let view = WikiLinkCompletionView(
            results: results,
            selectedIndex: selectedIndex,
            onSelect: onSelect
        )

        if panel == nil {
            let p = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            p.isFloatingPanel = true
            p.hasShadow = false
            p.backgroundColor = .clear
            p.level = .floating
            panel = p
        }

        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize
        panel?.contentView = hosting
        panel?.setContentSize(hosting.fittingSize)
        hostingView = hosting

        // Position below the cursor rect
        let screenRect = parentWindow.convertToScreen(rect)
        var origin = NSPoint(
            x: screenRect.origin.x,
            y: screenRect.origin.y - hosting.fittingSize.height - 4
        )

        // Flip above if would go off screen
        if let screen = parentWindow.screen, origin.y < screen.visibleFrame.origin.y {
            origin.y = screenRect.maxY + 4
        }

        panel?.setFrameOrigin(origin)

        if panel?.parent == nil {
            parentWindow.addChildWindow(panel!, ordered: .above)
        }
        panel?.orderFront(nil)
    }

    func update(
        results: [(name: String, url: URL)],
        selectedIndex: Int,
        onSelect: @escaping (String) -> Void
    ) {
        let view = WikiLinkCompletionView(
            results: results,
            selectedIndex: selectedIndex,
            onSelect: onSelect
        )
        hostingView?.rootView = view
        if let hosting = hostingView {
            let newSize = hosting.fittingSize
            panel?.setContentSize(newSize)
        }
    }

    func dismiss() {
        if let p = panel {
            p.parent?.removeChildWindow(p)
            p.orderOut(nil)
        }
        panel = nil
        hostingView = nil
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }
}
