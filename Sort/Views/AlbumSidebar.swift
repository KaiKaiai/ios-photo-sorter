import SwiftUI
import Photos

/// The album list on the right. Tap to file; long-press to rename or delete.
struct AlbumSidebar: View {
    @EnvironmentObject private var library: LibraryStore

    let onFile: (PHAssetCollection) -> Void
    let onNew: () -> Void
    let onRename: (PHAssetCollection) -> Void
    let onDelete: (PHAssetCollection) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 14) {
                Button(action: onNew) {
                    newAlbumTile
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New album")

                ForEach(library.albums, id: \.localIdentifier) { album in
                    Button {
                        onFile(album)
                    } label: {
                        AlbumTile(album: album, version: library.libraryVersion)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            onRename(album)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            onDelete(album)
                        } label: {
                            Label("Delete Album", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .frame(width: 90)
        .background(Color(.secondarySystemBackground).opacity(0.6))
    }

    private var newAlbumTile: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            Text("New")
                .font(.caption2.weight(.medium))
        }
        .contentShape(Rectangle())
    }
}

/// An album's cover (the same key photo the Photos app shows) with its name underneath.
struct AlbumTile: View {
    let album: PHAssetCollection
    /// Changes whenever the library changes, so covers refresh after filing.
    let version: Int

    @Environment(\.displayScale) private var displayScale
    @StateObject private var loader = AssetImageLoader()
    @State private var isEmpty = false

    var body: some View {
        VStack(spacing: 6) {
            Color(.tertiarySystemFill)
                .overlay {
                    if let image = loader.image, !isEmpty {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if isEmpty {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(album.localizedTitle ?? "Untitled")
                .font(.caption2.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 82)
        }
        .contentShape(Rectangle())
        .task(id: "\(album.localIdentifier)#\(version)") {
            loadCover()
        }
    }

    private func loadCover() {
        guard let key = PHAsset.fetchKeyAssets(in: album, options: nil)?.firstObject else {
            isEmpty = true
            return
        }
        isEmpty = false
        let side = 64 * displayScale
        loader.load(key, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, allowNetwork: false)
    }
}
