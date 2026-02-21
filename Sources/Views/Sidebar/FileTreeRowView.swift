import SwiftUI

struct FileTreeRowView: View {
    let node: FileTreeNode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.isFolder ? "folder.fill" : "doc.text.fill")
                .foregroundColor(isSelected ? .white : (node.isFolder ? .accentColor : .secondary.opacity(0.6)))
                .font(.system(size: 13))
                .frame(width: 16, alignment: .center)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.system(size: 13, weight: node.isFolder ? .medium : .regular))
                .foregroundColor(isSelected ? .white : .primary)
            Spacer(minLength: 4)
            if case .folder(let folderNode) = node {
                Text("\(folderNode.noteCount)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}
