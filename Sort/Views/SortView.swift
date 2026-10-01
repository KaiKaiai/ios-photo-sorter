import SwiftUI
import Photos

struct ViewerItem: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

enum SwipeIntent {
    case trash, keep, next, previous
}

/// A swipe or album tap whose card is still flying off. Its change runs when the animation
/// ends, or straight away if you start something else first, so fast swipes never get lost.
struct PendingCommit {
    let token: Int
    let run: () -> Void
}

/// The sorting screen: top bar, the card stack, albums on the right, Trash along the bottom.
struct SortView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // Finger
    @GestureState private var fingerDown = false
    @State private var touchActive = false
    @State private var isDragging = false
    @State private var pressStart: Date?
    @State private var holdTask: Task<Void, Never>?
    @State private var isHoldingLive = false
    @State private var dragOffset: CGSize = .zero

    // Card animation
    @State private var pending: PendingCommit?
    @State private var commitToken = 0
    @State private var committedIntent: SwipeIntent?
    @State private var showKeepTick = false
    @State private var fadeTopCard = false
    @State private var fileFlight = false

    // Sheets and alerts
    @State private var viewerItem: ViewerItem?
    @State private var showNewAlbum = false
    @State private var newAlbumName = ""
    @State private var newAlbumTarget: PHAsset?
    @State private var showRename = false
    @State private var renameTarget: PHAssetCollection?
    @State private var renameText = ""

    private let swipeThreshold: CGFloat = 100
    private let flickDistance: CGFloat = 320

    private enum CardRole {
        case top, next, previous
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                cardArea
                AlbumSidebar(
                    onFile: { album in fileCurrent(into: album) },
                    onNew: startNewAlbum,
                    onRename: startRename,
                    onDelete: { album in
                        flushPending()
                        Task { await library.deleteAlbum(album) }
                    }
                )
            }
            TrashTray(prepare: flushPending)
        }
        .background(Color(.systemBackground))
        .onAppear {
            library.beginSession()
        }
        .onDisappear {
            flushPending()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                flushPending()
                library.saveNow()
            }
        }
        .onChange(of: fingerDown) { _, down in
            if !down {
                touchLifted()
            }
        }
        .fullScreenCover(item: $viewerItem) { item in
            FullScreenViewer(asset: item.asset)
        }
        .alert("New album", isPresented: $showNewAlbum) {
            TextField("Album name", text: $newAlbumName)
            Button("Cancel", role: .cancel) {
                newAlbumTarget = nil
            }
            Button("Create") {
                createAlbum()
            }
            .disabled(newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(newAlbumTarget == nil ? "Creates an empty album." : "The current item goes straight into it.")
        }
        .alert("Rename album", isPresented: $showRename) {
            TextField("Album name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                renameAlbum()
            }
        }
        .libraryErrorAlert(isEnabled: viewerItem == nil)
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            HStack {
                Button {
                    flushPending()
                    dismiss()
                } label: {
                    Label("Home", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                Spacer()
                Button {
                    performUndo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(!library.canUndo && pending == nil)
            }
            Text("\(library.remainingCount.formatted()) left")
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    // MARK: - Cards

    private var cardArea: some View {
        GeometryReader { geo in
            let cardSize = CGSize(width: max(geo.size.width - 24, 1), height: max(geo.size.height - 24, 1))
            ZStack {
                if library.currentAsset == nil {
                    emptyState
                } else {
                    ForEach(library.cardStack, id: \.localIdentifier) { asset in
                        cardView(for: asset, size: cardSize)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(cardGesture)
        }
    }

    private func cardView(for asset: PHAsset, size: CGSize) -> some View {
        let role = cardRole(of: asset)
        let isTop = role == .top
        return CardView(
            asset: asset,
            isTop: isTop && viewerItem == nil,
            isHoldingLive: isTop && isHoldingLive
        )
        .frame(width: size.width, height: size.height)
        .overlay {
            if isTop {
                SwipeOverlay(
                    intent: committedIntent ?? liveIntent,
                    progress: committedIntent == nil ? dragProgress : 1,
                    showTick: showKeepTick
                )
            }
        }
        .scaleEffect(cardScale(for: role))
        .opacity(cardOpacity(for: role))
        .offset(cardOffset(for: role, size: size))
        .zIndex(cardZIndex(for: role))
        .allowsHitTesting(false)
    }

    private func cardRole(of asset: PHAsset) -> CardRole {
        let id = asset.localIdentifier
        if id == library.currentAsset?.localIdentifier { return .top }
        if id == library.nextAsset?.localIdentifier { return .next }
        return .previous
    }

    private func cardScale(for role: CardRole) -> CGFloat {
        switch role {
        case .top:
            if fileFlight { return 0.2 }
            return fadeTopCard ? 0.9 : 1
        case .next:
            // The card behind grows a little as you pull the top one away.
            return 0.94 + 0.04 * CGFloat(dragProgress)
        case .previous:
            return 1
        }
    }

    private func cardOpacity(for role: CardRole) -> Double {
        switch role {
        case .top:
            return (fadeTopCard || fileFlight) ? 0 : 1
        case .next, .previous:
            return 1
        }
    }

    private func cardOffset(for role: CardRole, size: CGSize) -> CGSize {
        switch role {
        case .top:
            if fileFlight { return CGSize(width: size.width * 0.7, height: 0) }
            return dampedOffset
        case .next:
            return .zero
        case .previous:
            // Parked off-screen to the left, ready to slide back in.
            return CGSize(width: -size.width * 1.6, height: 0)
        }
    }

    private func cardZIndex(for role: CardRole) -> Double {
        switch role {
        case .top: return 2
        case .next: return 1
        case .previous: return 0
        }
    }

    /// Follows your finger mostly along the direction you're swiping.
    private var dampedOffset: CGSize {
        if abs(dragOffset.width) > abs(dragOffset.height) {
            return CGSize(width: dragOffset.width, height: dragOffset.height * 0.2)
        }
        return CGSize(width: dragOffset.width * 0.2, height: dragOffset.height)
    }

    private var liveIntent: SwipeIntent? {
        guard isDragging, max(abs(dragOffset.width), abs(dragOffset.height)) > 12 else { return nil }
        if abs(dragOffset.width) > abs(dragOffset.height) {
            return dragOffset.width < 0 ? .next : .previous
        }
        return dragOffset.height < 0 ? .trash : .keep
    }

    private var dragProgress: Double {
        Double(min(1, max(abs(dragOffset.width), abs(dragOffset.height)) / swipeThreshold))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("All sorted")
                .font(.title2.weight(.bold))
            Text(library.trashAssets.isEmpty ? "Nothing left to sort." : "Empty the Trash below when you're ready.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Gesture

    /// One gesture on the card area handles tap (full screen), press and hold (Live Photo)
    /// and swipes. It lives on the area rather than a card, so it keeps working as cards change.
    private var cardGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($fingerDown) { _, state, _ in
                state = true
            }
            .onChanged { value in
                if !touchActive {
                    touchActive = true
                    // A card still flying off lands now, and this touch acts on the next one.
                    flushPending()
                    pressStart = Date()
                    startHoldTimer()
                }
                guard library.currentAsset != nil else { return }
                let width = value.translation.width
                let height = value.translation.height
                let distance = (width * width + height * height).squareRoot()
                if !isDragging && distance > 10 {
                    isDragging = true
                    cancelHold()
                }
                if isDragging {
                    dragOffset = value.translation
                }
            }
            .onEnded { value in
                let wasDragging = isDragging
                let wasHolding = isHoldingLive
                let pressedAt = pressStart
                endTouch()
                guard library.currentAsset != nil else { return }

                if wasDragging {
                    finishSwipe(value)
                } else if !wasHolding, let pressedAt, Date().timeIntervalSince(pressedAt) < 0.4,
                          let asset = library.currentAsset {
                    viewerItem = ViewerItem(asset: asset)
                }
            }
    }

    private func endTouch() {
        touchActive = false
        isDragging = false
        pressStart = nil
        cancelHold()
    }

    /// If iOS cancels a touch (a call comes in, say), onEnded never runs; this puts the card back.
    private func touchLifted() {
        Task { @MainActor in
            guard touchActive else { return }
            endTouch()
            if pending == nil {
                snapBack()
            }
        }
    }

    private func startHoldTimer() {
        guard let asset = library.currentAsset, asset.mediaSubtypes.contains(.photoLive) else { return }
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled, touchActive, !isDragging else { return }
            isHoldingLive = true
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        isHoldingLive = false
    }

    private func finishSwipe(_ value: DragGesture.Value) {
        let moved = value.translation
        let predicted = value.predictedEndTranslation
        if abs(moved.width) > abs(moved.height) {
            if moved.width < -swipeThreshold || predicted.width < -flickDistance {
                goNext()
            } else if moved.width > swipeThreshold || predicted.width > flickDistance {
                goPrevious()
            } else {
                snapBack()
            }
        } else {
            if moved.height < -swipeThreshold || predicted.height < -flickDistance {
                trash()
            } else if moved.height > swipeThreshold || predicted.height > flickDistance {
                keep()
            } else {
                snapBack()
            }
        }
    }

    // MARK: - Commits

    private func beginCommit(_ change: @escaping () -> Void) -> Int {
        let token = commitToken + 1
        commitToken = token
        pending = PendingCommit(token: token, run: change)
        return token
    }

    /// The fly-off finished: make the change and bring the next card forward.
    private func finishCommit(_ token: Int) {
        guard let commit = pending, commit.token == token else { return }
        pending = nil
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            commit.run()
        }
        resetCardState()
    }

    /// Makes a pending change straight away, because you've started something else.
    private func flushPending() {
        guard let commit = pending else { return }
        pending = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            commit.run()
            resetCardState()
        }
    }

    private func resetCardState() {
        dragOffset = .zero
        committedIntent = nil
        showKeepTick = false
        fadeTopCard = false
        fileFlight = false
    }

    // MARK: - Actions

    private func snapBack() {
        committedIntent = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            dragOffset = .zero
        }
    }

    private func trash() {
        guard let asset = library.currentAsset else { return snapBack() }
        Haptics.tap()
        committedIntent = .trash
        let token = beginCommit { library.trash(asset) }
        withAnimation(.easeIn(duration: 0.2)) {
            dragOffset = CGSize(width: dragOffset.width, height: -1400)
        } completion: {
            finishCommit(token)
        }
    }

    private func keep() {
        guard let asset = library.currentAsset else { return snapBack() }
        Haptics.tap()
        committedIntent = .keep
        let token = beginCommit { library.keep(asset) }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
            dragOffset = .zero
            showKeepTick = true
        } completion: {
            guard pending?.token == token else { return }
            withAnimation(.easeIn(duration: 0.16)) {
                fadeTopCard = true
            } completion: {
                finishCommit(token)
            }
        }
    }

    private func fileCurrent(into album: PHAssetCollection) {
        flushPending()
        guard let asset = library.currentAsset else { return }
        file(asset, into: album)
    }

    private func file(_ asset: PHAsset, into album: PHAssetCollection) {
        Haptics.tap()
        let token = beginCommit { library.file(asset, into: album) }
        withAnimation(.easeIn(duration: 0.22)) {
            fileFlight = true
        } completion: {
            finishCommit(token)
        }
    }

    private func goNext() {
        guard library.canBrowse else {
            Haptics.bump()
            return snapBack()
        }
        Haptics.tap()
        committedIntent = .next
        let token = beginCommit { library.showNext() }
        withAnimation(.easeIn(duration: 0.16)) {
            dragOffset = CGSize(width: -900, height: dragOffset.height)
        } completion: {
            finishCommit(token)
        }
    }

    private func goPrevious() {
        guard library.canBrowse else {
            Haptics.bump()
            return snapBack()
        }
        Haptics.tap()
        committedIntent = nil
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            library.showPrevious()
            dragOffset = .zero
        }
    }

    private func performUndo() {
        flushPending()
        guard library.canUndo else { return }
        Haptics.tap()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            library.undo()
        }
    }

    // MARK: - Albums

    private func startNewAlbum() {
        flushPending()
        newAlbumTarget = library.currentAsset
        newAlbumName = ""
        showNewAlbum = true
    }

    private func createAlbum() {
        let name = newAlbumName
        let target = newAlbumTarget
        newAlbumTarget = nil
        Task {
            guard let album = await library.createAlbum(named: name) else { return }
            // The new album also takes the item you were looking at.
            if let target, library.currentAsset?.localIdentifier == target.localIdentifier {
                file(target, into: album)
            }
        }
    }

    private func startRename(_ album: PHAssetCollection) {
        flushPending()
        renameTarget = album
        renameText = album.localizedTitle ?? ""
        showRename = true
    }

    private func renameAlbum() {
        guard let album = renameTarget else { return }
        let name = renameText
        renameTarget = nil
        Task { await library.rename(album, to: name) }
    }
}

/// The tint and label that appear on the top card as you swipe.
struct SwipeOverlay: View {
    let intent: SwipeIntent?
    let progress: Double
    let showTick: Bool

    var body: some View {
        ZStack {
            if let intent {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(tint(for: intent).opacity(0.28 * progress))
                label(for: intent)
                    .opacity(progress)
                    .scaleEffect(0.85 + 0.15 * progress)
            }
            if showTick {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 88, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
                    .shadow(color: .black.opacity(0.25), radius: 10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }

    private func tint(for intent: SwipeIntent) -> Color {
        switch intent {
        case .trash: return .red
        case .keep: return .green
        case .next, .previous: return .gray
        }
    }

    private func label(for intent: SwipeIntent) -> some View {
        let text: String
        let symbol: String
        switch intent {
        case .trash:
            text = "Delete"
            symbol = "trash.fill"
        case .keep:
            text = "Keep"
            symbol = "checkmark"
        case .next:
            text = "Next"
            symbol = "arrow.left"
        case .previous:
            text = "Back"
            symbol = "arrow.right"
        }
        return Label(text, systemImage: symbol)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(tint(for: intent).opacity(0.9), in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 6)
    }
}
