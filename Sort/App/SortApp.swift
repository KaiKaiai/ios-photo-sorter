import SwiftUI
import Photos
import UIKit

@main
struct SortApp: App {
    @StateObject private var library = LibraryStore()

    init() {
        AudioSession.useAmbient()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
        }
    }
}

/// Chooses between the permission screens and the home screen.
struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch library.authorization {
            case .authorized:
                HomeView()
            case .notDetermined:
                PermissionView(kind: .ask)
            case .limited:
                PermissionView(kind: .limited)
            default:
                PermissionView(kind: .denied)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                library.refreshAuthorization()
            case .background:
                library.saveNow()
            default:
                break
            }
        }
    }
}

struct PermissionView: View {
    enum Kind {
        case ask, limited, denied
    }

    let kind: Kind

    @EnvironmentObject private var library: LibraryStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                performAction()
            } label: {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
    }

    private var title: String {
        switch kind {
        case .ask: return "Sort needs your photos"
        case .limited: return "Sort needs Full Access"
        case .denied: return "Photo access is off"
        }
    }

    private var message: String {
        switch kind {
        case .ask:
            return "Everything stays on your iPhone. Sort only reads your library so you can delete, keep and file your photos and videos."
        case .limited:
            return "With Limited access Sort can only see a few items. Choose Full Access in Settings \u{2192} Sort \u{2192} Photos."
        case .denied:
            return "Turn on Full Access in Settings \u{2192} Sort \u{2192} Photos to start sorting."
        }
    }

    private var buttonTitle: String {
        kind == .ask ? "Allow Access" : "Open Settings"
    }

    private func performAction() {
        switch kind {
        case .ask:
            Task { await library.requestAccess() }
        case .limited, .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }
    }
}
