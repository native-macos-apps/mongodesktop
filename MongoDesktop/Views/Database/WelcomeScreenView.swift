import SwiftUI

// MARK: - WelcomeScreenView

struct WelcomeScreenView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(isAnimating ? 0.3 : 0.15), Color.mint.opacity(isAnimating ? 0.15 : 0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(isAnimating ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isAnimating)
                
                Image(systemName: "leaf.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .green.opacity(0.4), radius: 12, y: 6)
            }
            .onAppear { isAnimating = true }
            
            VStack(spacing: 12) {
                if let db = sessionViewModel.selectedDatabase, !db.isEmpty {
                    Text("Viewing Database: \(db)")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("Select a collection from the sidebar to continue")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Text("Welcome to MongoDesktop")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("Select a database and a collection to start exploring")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Color.clear
                RadialGradient(
                    gradient: Gradient(colors: [Color.green.opacity(0.05), Color.clear]),
                    center: .center,
                    startRadius: 50,
                    endRadius: 400
                )
            }
        )
    }
}
