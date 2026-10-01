import SwiftUI
import Photos

/// The strip along the bottom of the sorting screen: what you've binned this time and before.
struct TrashTray: View {
    @EnvironmentObject private var library: LibraryStore
    /// Runs before any tap here, so a swipe that's still animating lands first.
    var prepare: () -> Void = {}

    @State private var isDeleting = false

    var body: some View {
        HStack(spacing: 12) {
            if library.trashAssets.isEmpty {
                Label("Swipe up to bin things", systemImage: "trash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(library.trashAssets.reversed(), id: \.localIdentifier) { asset in
                            Button {
                                prepare()
                                Haptics.tap()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                    library.rescue(asset)
                                }
                            } label: {
                                AssetThumbnail(asset: asset)
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top)
                                    .combined(with: .scale(scale: 0.5))
                                    .combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                            .accessibilityLabel("Rescue this item")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)

                Button(role: .destructive) {
                    emptyTrash()
                } label: {
                    Text("Delete \(library.trashAssets.count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isDeleting)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 74)
        .background(.bar)
    }

    private func emptyTrash() {
        prepare()
        isDeleting = true
        Task {
            let deleted = await library.emptyTrash()
            isDeleting = false
            if deleted {
                Haptics.done()
            }
        }
    }
}

/// The Trash, opened from the home screen: review, rescue, or delete everything.
struct TrashReviewView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleting = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    var body: some View {
        NavigationStack {
            Group {
                if library.trashAssets.isEmpty {
                    ContentUnavailableView(
                        "Trash is empty",
                        systemImage: "trash",
                        description: Text("Swipe up while sorting to bin something.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(library.trashAssets.reversed(), id: \.localIdentifier) { asset in
                                Button {
                                    Haptics.tap()
                                    withAnimation {
                                        library.rescue(asset)
                                    }
                                } label: {
                                    AssetThumbnail(asset: asset, pixelSide: 320)
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipped()
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Rescue this item")
                            }
                        }
                        .padding(4)

                        Text("Tap an item to rescue it. Deleted items stay in Recently Deleted in Photos for 30 days.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
            }
            .navigationTitle("Trash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    if !library.trashAssets.isEmpty {
                        Button(role: .destructive) {
                            emptyTrash()
                        } label: {
                            Text("Delete \(library.trashAssets.count) \(library.trashAssets.count == 1 ? "Item" : "Items")")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(isDeleting)
                    }
                }
            }
        }
        .libraryErrorAlert()
    }

    private func emptyTrash() {
        isDeleting = true
        Task {
            let deleted = await library.emptyTrash()
            isDeleting = false
            if deleted {
                Haptics.done()
            }
        }
    }
}
