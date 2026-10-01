import SwiftUI
import Photos

/// Manage albums in one place: create, rename and delete, and hold one to select several
/// and delete them together behind a single iOS prompt.
struct AlbumsView: View {
    @EnvironmentObject private var library: LibraryStore

    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var isDeleting = false

    // Alerts and dialogs
    @State private var showNewAlbum = false
    @State private var newAlbumName = ""
    @State private var showRename = false
    @State private var renameTarget: PHAssetCollection?
    @State private var renameText = ""
    @State private var actionTarget: PHAssetCollection?
    @State private var showBatchDeleteConfirm = false

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 14)]

    /// Alphabetical, so albums are easy to find when managing them.
    private var albums: [PHAssetCollection] {
        library.albums.sorted {
            ($0.localizedTitle ?? "").localizedStandardCompare($1.localizedTitle ?? "") == .orderedAscending
        }
    }

    private var selectedAlbums: [PHAssetCollection] {
        albums.filter { selection.contains($0.localIdentifier) }
    }

    var body: some View {
        Group {
            if albums.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .navigationTitle(isSelecting ? selectionTitle : "Albums")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                deleteBar
            }
        }
        .onChange(of: library.albums.map(\.localIdentifier)) { _, ids in
            // Drop albums that vanished, e.g. deleted in the Photos app meanwhile.
            selection.formIntersection(ids)
        }
        .alert("New album", isPresented: $showNewAlbum) {
            TextField("Album name", text: $newAlbumName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newAlbumName
                Task {
                    if await library.createAlbum(named: name) != nil {
                        Haptics.done()
                    }
                }
            }
            .disabled(newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Rename album", isPresented: $showRename) {
            TextField("Album name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
            Button("Save") {
                guard let album = renameTarget else { return }
                let name = renameText
                renameTarget = nil
                Task { await library.rename(album, to: name) }
            }
        }
        .confirmationDialog(
            actionTarget?.localizedTitle ?? "Album",
            isPresented: Binding(
                get: { actionTarget != nil },
                set: { if !$0 { actionTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: actionTarget
        ) { album in
            Button("Rename") {
                startRename(album)
            }
            Button("Select") {
                startSelecting(with: album)
            }
            Button("Delete Album", role: .destructive) {
                delete([album])
            }
        } message: { _ in
            Text("Deleting an album keeps its photos and videos in your library.")
        }
        .confirmationDialog(
            selectedAlbums.count == 1 ? "Delete 1 album?" : "Delete \(selectedAlbums.count) albums?",
            isPresented: $showBatchDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(selectedAlbums.count == 1 ? "Delete Album" : "Delete \(selectedAlbums.count) Albums", role: .destructive) {
                delete(selectedAlbums)
            }
        } message: {
            Text("The photos and videos in them stay in your library and come back to be sorted.")
        }
        .libraryErrorAlert()
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(albums, id: \.localIdentifier) { album in
                    AlbumCard(
                        album: album,
                        version: library.libraryVersion,
                        isSelecting: isSelecting,
                        isSelected: selection.contains(album.localIdentifier)
                    )
                    .onTapGesture {
                        tapped(album)
                    }
                    .onLongPressGesture(minimumDuration: 0.35) {
                        held(album)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(selection.contains(album.localIdentifier) ? .isSelected : [])
                }
            }
            .padding(16)

            if !isSelecting {
                Text("Hold an album to select several.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No albums yet")
                .font(.title3.weight(.semibold))
            Button("New Album") {
                startNewAlbum()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deleteBar: some View {
        Button(role: .destructive) {
            showBatchDeleteConfirm = true
        } label: {
            Group {
                if isDeleting {
                    ProgressView()
                } else {
                    Text(selection.isEmpty ? "Delete" : "Delete \(selection.count)")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
        .disabled(selection.isEmpty || isDeleting)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    stopSelecting()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(selection.count == albums.count ? "Deselect All" : "Select All") {
                    if selection.count == albums.count {
                        selection.removeAll()
                    } else {
                        selection = Set(albums.map(\.localIdentifier))
                    }
                    Haptics.tap()
                }
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !albums.isEmpty {
                    Button("Select") {
                        withAnimation(.snappy) { isSelecting = true }
                    }
                }
                Button {
                    startNewAlbum()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New album")
            }
        }
    }

    private var selectionTitle: String {
        switch selection.count {
        case 0: return "Select Albums"
        case 1: return "1 Selected"
        default: return "\(selection.count) Selected"
        }
    }

    // MARK: - Actions

    private func tapped(_ album: PHAssetCollection) {
        if isSelecting {
            toggle(album)
        } else {
            actionTarget = album
        }
    }

    private func held(_ album: PHAssetCollection) {
        if isSelecting {
            toggle(album)
        } else {
            startSelecting(with: album)
        }
    }

    private func toggle(_ album: PHAssetCollection) {
        let id = album.localIdentifier
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        Haptics.tap()
    }

    private func startSelecting(with album: PHAssetCollection) {
        Haptics.bump()
        withAnimation(.snappy) {
            isSelecting = true
            selection = [album.localIdentifier]
        }
    }

    private func stopSelecting() {
        withAnimation(.snappy) {
            isSelecting = false
            selection.removeAll()
        }
    }

    private func startNewAlbum() {
        newAlbumName = ""
        showNewAlbum = true
    }

    private func startRename(_ album: PHAssetCollection) {
        renameTarget = album
        renameText = album.localizedTitle ?? ""
        showRename = true
    }

    private func delete(_ targets: [PHAssetCollection]) {
        guard !targets.isEmpty else { return }
        isDeleting = true
        Task {
            let deleted = await library.deleteAlbums(targets)
            isDeleting = false
            if deleted {
                Haptics.done()
                stopSelecting()
            }
        }
    }
}

/// A large album cover with its name, item count and, while selecting, a checkmark.
private struct AlbumCard: View {
    let album: PHAssetCollection
    /// Changes whenever the library changes, so covers and counts refresh.
    let version: Int
    let isSelecting: Bool
    let isSelected: Bool

    @Environment(\.displayScale) private var displayScale
    @StateObject private var loader = AssetImageLoader()
    @State private var isEmpty = false
    @State private var count: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color(.tertiarySystemFill)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image = loader.image, !isEmpty {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if isEmpty {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, isSelected ? Color.accentColor : Color.black.opacity(0.25))
                            .shadow(radius: 2)
                            .padding(6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .scaleEffect(isSelected ? 0.94 : 1)
                .animation(.snappy(duration: 0.2), value: isSelected)

            VStack(alignment: .leading, spacing: 1) {
                Text(album.localizedTitle ?? "Untitled")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .task(id: "\(album.localIdentifier)#\(version)") {
            load()
        }
    }

    private var countText: String {
        guard let count else { return " " }
        return count == 1 ? "1 item" : "\(count.formatted()) items"
    }

    private func load() {
        count = PHAsset.fetchAssets(in: album, options: nil).count
        guard let key = PHAsset.fetchKeyAssets(in: album, options: nil)?.firstObject else {
            isEmpty = true
            return
        }
        isEmpty = false
        let side = 140 * displayScale
        loader.load(key, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, allowNetwork: false)
    }
}
