import SwiftUI
import Photos

/// Manage albums in one place: create, rename and delete, and hold one to select several
/// (or drag across them, like the Photos app) and delete them together behind a single iOS prompt.
struct AlbumsView: View {
    @EnvironmentObject private var library: LibraryStore

    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var isDeleting = false

    // Drag to select
    @State private var tileFrames: [String: CGRect] = [:]
    @State private var dragPhase: DragPhase = .idle
    @State private var lastDragIndex: Int?

    // Alerts and dialogs
    @State private var showNewAlbum = false
    @State private var newAlbumName = ""
    @State private var showRename = false
    @State private var renameTarget: PHAssetCollection?
    @State private var renameText = ""
    @State private var actionTarget: PHAssetCollection?
    @State private var showBatchDeleteConfirm = false

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 14)]
    private let gridSpace = "albumGrid"

    /// What the current drag is doing. A drag that starts sideways selects; one that starts
    /// up or down is left to the scroll view.
    private enum DragPhase {
        case idle
        case scrolling
        /// `adding` is false when the drag started on a ticked album, so it unticks instead.
        case selecting(anchor: Int, adding: Bool, base: Set<String>)
    }

    private var isDragSelecting: Bool {
        if case .selecting = dragPhase { return true }
        return false
    }

    /// Alphabetical, so albums are easy to find when managing them.
    private var albums: [PHAssetCollection] {
        library.albums.sorted {
            ($0.localizedTitle ?? "").localizedStandardCompare($1.localizedTitle ?? "") == .orderedAscending
        }
    }

    private var selectedAlbums: [PHAssetCollection] {
        albums.filter { selection.contains($0.localIdentifier) }
    }

    // The body is split into stages so the Swift compiler can type-check each one quickly.
    var body: some View {
        withDialogs(withAlerts(screen))
            .libraryErrorAlert()
    }

    private var screen: some View {
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
    }

    private func withAlerts(_ content: some View) -> some View {
        content
            .alert("New album", isPresented: $showNewAlbum) {
                TextField("Album name", text: $newAlbumName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    createAlbum()
                }
                .disabled(isNewAlbumNameBlank)
            }
            .alert("Rename album", isPresented: $showRename) {
                TextField("Album name", text: $renameText)
                Button("Cancel", role: .cancel) {
                    renameTarget = nil
                }
                Button("Save") {
                    renameAlbum()
                }
            }
    }

    private func withDialogs(_ content: some View) -> some View {
        content
            .confirmationDialog(
                actionTitle,
                isPresented: isShowingActions,
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
                batchDeleteTitle,
                isPresented: $showBatchDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(batchDeleteButtonTitle, role: .destructive) {
                    delete(selectedAlbums)
                }
            } message: {
                Text("The photos and videos in them stay in your library and come back to be sorted.")
            }
    }

    // MARK: - Dialog text

    private var actionTitle: String {
        actionTarget?.localizedTitle ?? "Album"
    }

    private var isShowingActions: Binding<Bool> {
        Binding(
            get: { actionTarget != nil },
            set: { shown in
                if !shown { actionTarget = nil }
            }
        )
    }

    private var batchDeleteTitle: String {
        let count = selectedAlbums.count
        return count == 1 ? "Delete 1 album?" : "Delete \(count) albums?"
    }

    private var batchDeleteButtonTitle: String {
        let count = selectedAlbums.count
        return count == 1 ? "Delete Album" : "Delete \(count) Albums"
    }

    private var isNewAlbumNameBlank: Bool {
        newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(albums, id: \.localIdentifier) { album in
                    cell(for: album)
                }
            }
            .coordinateSpace(name: gridSpace)
            .onPreferenceChange(TileFramesKey.self) { frames in
                tileFrames = frames
            }
            .simultaneousGesture(dragSelectGesture, including: isSelecting ? .all : .subviews)
            .padding(16)

            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
        .scrollDisabled(isDragSelecting)
    }

    private var hint: String {
        isSelecting ? "Drag sideways across albums to select several." : "Hold an album to select several."
    }

    private var dragSelectGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named(gridSpace))
            .onChanged { value in
                dragChanged(value)
            }
            .onEnded { _ in
                dragPhase = .idle
                lastDragIndex = nil
            }
    }

    private func cell(for album: PHAssetCollection) -> some View {
        let isSelected = selection.contains(album.localIdentifier)
        let traits: AccessibilityTraits = isSelected ? [.isButton, .isSelected] : [.isButton]
        return AlbumCard(
            album: album,
            version: library.libraryVersion,
            isSelecting: isSelecting,
            isSelected: isSelected
        )
        .onTapGesture {
            tapped(album)
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            held(album)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TileFramesKey.self,
                    value: [album.localIdentifier: proxy.frame(in: .named(gridSpace))]
                )
            }
        }
        .accessibilityAddTraits(traits)
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

    /// Holding only starts selecting. While selecting, a hold is usually the start of a drag,
    /// so toggling here would flip the album the drag then starts from.
    private func held(_ album: PHAssetCollection) {
        guard !isSelecting else { return }
        startSelecting(with: album)
    }

    private func dragChanged(_ value: DragGesture.Value) {
        let list = albums
        switch dragPhase {
        case .scrolling:
            return
        case .idle:
            let isSideways = abs(value.translation.width) > abs(value.translation.height)
            guard isSideways, let anchor = albumIndex(at: value.startLocation, in: list) else {
                dragPhase = .scrolling
                return
            }
            let adding = !selection.contains(list[anchor].localIdentifier)
            dragPhase = .selecting(anchor: anchor, adding: adding, base: selection)
            extendDragSelection(to: value.location, in: list)
        case .selecting:
            extendDragSelection(to: value.location, in: list)
        }
    }

    /// Selects (or unselects) every album between where the drag started and where the finger is,
    /// in grid order, on top of what was selected before the drag.
    private func extendDragSelection(to location: CGPoint, in list: [PHAssetCollection]) {
        guard case let .selecting(anchor, adding, base) = dragPhase,
              let current = albumIndex(at: location, in: list),
              current != lastDragIndex else { return }
        lastDragIndex = current
        let range = min(anchor, current)...max(anchor, current)
        let ids = Set(list[range].map(\.localIdentifier))
        selection = adding ? base.union(ids) : base.subtracting(ids)
        Haptics.tap()
    }

    private func albumIndex(at point: CGPoint, in list: [PHAssetCollection]) -> Int? {
        list.firstIndex { album in
            tileFrames[album.localIdentifier]?.contains(point) ?? false
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

    private func createAlbum() {
        let name = newAlbumName
        Task {
            if await library.createAlbum(named: name) != nil {
                Haptics.done()
            }
        }
    }

    private func renameAlbum() {
        guard let album = renameTarget else { return }
        let name = renameText
        renameTarget = nil
        Task { await library.rename(album, to: name) }
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

/// Each visible tile's frame in the grid, so a drag can tell which album is under the finger.
private struct TileFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
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
                            .foregroundStyle(Color.white, badgeFill)
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

    private var badgeFill: Color {
        isSelected ? Color.accentColor : Color.black.opacity(0.25)
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
