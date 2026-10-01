import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.useSortedAlbum) private var useSortedAlbum = false
    @AppStorage(SettingsKey.downloadPolicy) private var downloadPolicy: DownloadPolicy = .wifiOnly
    @AppStorage(SettingsKey.newestFirst) private var newestFirst = true

    @State private var offerBackfill = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Add kept items to a \u{201C}Sorted\u{201D} album", isOn: $useSortedAlbum)
                } footer: {
                    Text("Items you keep without filing also go into a \u{201C}Sorted\u{201D} album in Photos. Anything in it counts as done, so a reinstall picks up where you left off.")
                }

                Section {
                    Picker("Download originals", selection: $downloadPolicy) {
                        ForEach(DownloadPolicy.allCases) { policy in
                            Text(policy.label).tag(policy)
                        }
                    }
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("When allowed, originals load as you open or play something, like the Photos app. Otherwise you see the copy on your phone, with a cloud badge when the original isn't here.")
                }

                Section {
                    Picker("Order", selection: $newestFirst) {
                        Text("Newest first").tag(true)
                        Text("Oldest first").tag(false)
                    }
                } footer: {
                    Text("By date taken.")
                }

                Section {
                    Button("Reset Kept Memory", role: .destructive) {
                        confirmReset = true
                    }
                    .disabled(library.keptCount == 0)
                } footer: {
                    Text("\(library.keptCount.formatted()) kept items are remembered on this phone.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: useSortedAlbum) { _, isOn in
                if isOn && library.keptCount > 0 {
                    offerBackfill = true
                }
            }
            .onChange(of: newestFirst) { _, _ in
                // Start from the top of the new order.
                Task { await library.reload(resetPosition: true) }
            }
            .alert("Add \(library.keptCount.formatted()) kept items to \u{201C}Sorted\u{201D}?", isPresented: $offerBackfill) {
                Button("Not Now", role: .cancel) {}
                Button("Add") {
                    library.addKeptItemsToSortedAlbum()
                }
            } message: {
                Text("These are items you kept before the album was switched on.")
            }
            .confirmationDialog("Reset kept memory?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    Task { await library.resetKeptMemory() }
                }
            } message: {
                Text("Kept items that aren't in an album come back to be sorted.")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
