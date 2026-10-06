import SwiftUI
import AppKit

// MARK: - Minimal Clean Query Completion Overlay View

struct QueryCompletionOverlayView: View {
    @ObservedObject var viewModel: QueryCompletionViewModel
    let onSelect: (QueryCompletionItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: viewModel.items.count > 6) {
                VStack(spacing: 1) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        suggestionRow(item: item, index: index)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                if newIndex >= 0 && newIndex < viewModel.items.count {
                    let targetId = viewModel.items[newIndex].id
                    withAnimation(.easeInOut(duration: 0.08)) {
                        proxy.scrollTo(targetId, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 5)
    }

    // MARK: - Row

    private func suggestionRow(item: QueryCompletionItem, index: Int) -> some View {
        let isSelected = index == viewModel.selectedIndex

        return HStack(spacing: 7) {
            // Icon
            Image(systemName: item.kind.iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isSelected ? .white : item.kind.badgeColor)
                .frame(width: 14, height: 14)

            // Label with search match highlighting
            highlightedText(text: item.label, query: viewModel.query, isSelected: isSelected)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .lineLimit(1)

            Spacer(minLength: 4)

            // Subtle Badge
            Text(item.kind.title)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary.opacity(0.7))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.04))
                )
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(
            isSelected
                ? Color.accentColor
                : Color.clear
        )
        .foregroundColor(isSelected ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .id(item.id)
        .onHover { isHovering in
            if isHovering {
                viewModel.selectedIndex = index
            }
        }
        .onTapGesture {
            onSelect(item)
        }
    }

    // MARK: - Highlighted Text

    private func highlightedText(text: String, query: String, isSelected: Bool) -> some View {
        let cleanQuery = query.replacingOccurrences(of: "\"", with: "").lowercased()

        if cleanQuery.isEmpty {
            return Text(text)
                .foregroundColor(isSelected ? .white : .primary)
        }

        let lowerText = text.lowercased()

        // 1. Direct match (e.g. "$gt" or "metadata")
        if let matchRange = lowerText.range(of: cleanQuery) {
            let prefix = String(text[..<matchRange.lowerBound])
            let match = String(text[matchRange])
            let suffix = String(text[matchRange.upperBound...])

            return Text(prefix)
                .foregroundColor(isSelected ? .white.opacity(0.85) : .primary)
                + Text(match)
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? .white : .accentColor)
                + Text(suffix)
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .primary)
        }

        // 2. Fallback match stripping leading "$" if user typed without "$" (e.g. "gt" matching "$gt")
        let stripped = cleanQuery.replacingOccurrences(of: "$", with: "")
        if !stripped.isEmpty, let matchRange = lowerText.range(of: stripped) {
            let prefix = String(text[..<matchRange.lowerBound])
            let match = String(text[matchRange])
            let suffix = String(text[matchRange.upperBound...])

            return Text(prefix)
                .foregroundColor(isSelected ? .white.opacity(0.85) : .primary)
                + Text(match)
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? .white : .accentColor)
                + Text(suffix)
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .primary)
        }

        return Text(text)
            .foregroundColor(isSelected ? .white : .primary)
    }
}
