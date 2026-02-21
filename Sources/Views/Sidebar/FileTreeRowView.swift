import SwiftUI

struct FileTreeRowView: View {
    let node: FileTreeNode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.isFolder ? "folder" : "doc.text")
                .foregroundColor(node.isFolder ? .accentColor : .secondary)
                .font(.system(size: 13))
            Text(node.name)
                .lineLimit(1)
                .font(.system(size: 13))
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
