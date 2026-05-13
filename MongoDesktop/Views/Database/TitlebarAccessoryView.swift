import SwiftUI
import AppKit

// MARK: - TitlebarLeadingContent

struct TitlebarLeadingContent: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel

    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                WindowCoordinator.shared.showConnectionsWindow()
            }) {
                Image(systemName: "server.rack")
            }
            .help("Connections")

            DatabasePickerButton()
                .environmentObject(sessionViewModel)

            DatabaseCollectionInlineView()
                .environmentObject(sessionViewModel)
        }
        .padding(.leading, 6)
    }
}

// MARK: - TitlebarLeadingAccessoryHost

struct TitlebarLeadingAccessoryHost<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.hostingView == nil {
            context.coordinator.hostingView = NSHostingView(rootView: content)
        } else {
            context.coordinator.hostingView?.rootView = content
        }

        guard let window = nsView.window,
              let hostingView = context.coordinator.hostingView
        else { return }

        if context.coordinator.controller == nil {
            let controller = NSTitlebarAccessoryViewController()
            controller.view = hostingView
            controller.layoutAttribute = .leading
            window.addTitlebarAccessoryViewController(controller)
            context.coordinator.controller = controller
        } else if context.coordinator.controller?.view !== hostingView {
            context.coordinator.controller?.view = hostingView
        }
    }

    final class Coordinator {
        var controller: NSTitlebarAccessoryViewController?
        var hostingView: NSHostingView<Content>?
    }
}
