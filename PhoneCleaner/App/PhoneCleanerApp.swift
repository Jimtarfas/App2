import SwiftUI

@main
struct PhoneCleanerApp: App {
    @State private var cleaner = Cleaner()
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(cleaner)
                .environment(store)
        }
    }
}

struct RootView: View {
    @Environment(Cleaner.self) private var cleaner
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        Group {
            if !onboarded {
                OnboardingView { onboarded = true }
            } else {
                switch cleaner.authorization {
                case .notDetermined:
                    PermissionView()
                case .authorized, .limited:
                    HomeView()
                default:
                    AccessDeniedView()
                }
            }
        }
        .animation(.default, value: onboarded)
        .animation(.default, value: cleaner.authorization)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { cleaner.refresh() }
        }
    }
}
