import SwiftUI

/// Opens first: how much is left, what's in the Trash, and Start.
struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var isSorting = false
    @State private var showSettings = false
    @State private var showTrash = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                countBlock
                trashButton
                Spacer(minLength: 0)
                startButton
            }
            .padding(24)
            .libraryErrorAlert(isEnabled: !isSorting && !showSettings && !showTrash)
            .navigationTitle("Sort")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .fullScreenCover(isPresented: $isSorting) {
            SortView()
                .environmentObject(library)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(library)
        }
        .sheet(isPresented: $showTrash) {
            TrashReviewView()
                .environmentObject(library)
        }
    }

    @ViewBuilder
    private var countBlock: some View {
        if !library.hasLoaded {
            ProgressView("Reading your library\u{2026}")
        } else if library.remainingCount == 0 {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("All sorted")
                    .font(.title.weight(.bold))
                Text("New photos and videos will show up here.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            VStack(spacing: 4) {
                Text(library.remainingCount, format: .number)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(library.remainingCount == 1 ? "item left to sort" : "items left to sort")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trashButton: some View {
        Button {
            showTrash = true
        } label: {
            Label(
                library.trashAssets.count == 1 ? "1 item in Trash" : "\(library.trashAssets.count) items in Trash",
                systemImage: library.trashAssets.isEmpty ? "trash" : "trash.fill"
            )
            .font(.body.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(library.trashAssets.isEmpty ? Color.secondary : Color.red)
        .disabled(library.trashAssets.isEmpty)
    }

    private var startButton: some View {
        Button {
            isSorting = true
        } label: {
            Text("Start")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!library.hasLoaded || library.remainingCount == 0)
    }
}
