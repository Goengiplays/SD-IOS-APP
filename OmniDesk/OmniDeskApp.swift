import SwiftUI
import Clerk

@main
struct OmniDeskApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var workspace = UserWorkspace()

    init() {
        if let publishableKey = Bundle.main.object(forInfoDictionaryKey: "CLERK_PUBLISHABLE_KEY") as? String,
           !publishableKey.isEmpty {
            Clerk.shared.configure(publishableKey: publishableKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(auth)
                .environmentObject(workspace)
                .environment(Clerk.shared)
        }
    }
}

private struct AppRootView: View {
    @Environment(Clerk.self) private var clerk
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        Group {
            if clerk.user != nil || auth.isAuthenticated {
                DashboardView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                ShipDemonAuthView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: clerk.user?.id)
        .animation(.easeInOut(duration: 0.28), value: auth.isAuthenticated)
        .task {
            guard !clerk.isLoaded else { return }
            try? await clerk.load()
        }
    }
}
