import SwiftUI

// MARK: - ConnectionStatusCenterView

struct ConnectionStatusCenterView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @EnvironmentObject private var tabViewModel: QueryTabViewModel
    @Binding var showServerInfo: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Button(action: { showServerInfo.toggle() }) {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .help("Server Information")
                .popover(isPresented: $showServerInfo, arrowEdge: .bottom) {
                    ServerInfoPopoverView()
                }

                Text(sessionViewModel.connectionName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 12)

            if tabViewModel.isLoading || tabViewModel.lastQueryDuration != nil {
                HStack(spacing: 8) {
                    Divider().frame(height: 14)

                    if tabViewModel.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12, height: 12)
                            .fixedSize()
                            .opacity(tabViewModel.isLoading ? 1 : 0)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(tabViewModel.lastQueryDuration.map { formattedDuration($0) } ?? "0ms")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 260, alignment: .center)
        .padding(.horizontal, 12)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return "\(Int(seconds * 1000))ms"
        } else {
            return String(format: "%.2fs", seconds)
        }
    }
}

// MARK: - ErrorBannerView

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}
