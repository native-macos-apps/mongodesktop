import SwiftUI

// MARK: - TabPill

struct TabPill: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(isHovered ? Color.primary.opacity(0.1) : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isSelected ? 1 : 0)

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .background(
            ZStack {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                } else if isHovered {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }
        )
        .contentShape(Capsule())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
    }
}
