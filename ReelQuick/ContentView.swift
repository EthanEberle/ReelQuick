//
//  ContentView.swift
//  ReelQuick
//
//  Main view controller orchestrating the photo swiping interface
//

import SwiftUI
import SwiftData
import Photos

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var photoLib = PhotoLibrary()
    
    // UI State
    @AppStorage("shakeToUndoEnabled") private var shakeToUndoEnabled = true
    @State private var showSettings = false
    @State private var undoTrigger = false
    @State private var swipeRightTrigger = false
    @State private var lastAction: SwipeAction? = nil
    
    // Album move state
    @State private var showMoveSheet = false
    @State private var pendingMoveIndex: Int? = nil
    @State private var pendingMoveAlbumId: String? = nil
    
    // Progress bar state
    @State private var mediaState: MediaState = .photos
    @State private var counts = MediaCounts()
    
    // Deletion queue state
    @State private var deletionQueueCount = 0
    @State private var showDeletionAlert = false
    @AppStorage("autoBatchDeletions") private var autoBatchDeletions = true
    @AppStorage("batchDeletionSize") private var batchDeletionSize = 10
    
    // Loading state
    @State private var showStartupSpinner = true
    @State private var stateChangeToken = 0
    
    enum SwipeAction {
        case left(index: Int, item: PhotoItem)
        case right(index: Int, item: PhotoItem)
        case move(index: Int, item: PhotoItem, albumID: String)
    }
    
    private var progressBarHeight: CGFloat { 120 }
    private var bottomReserve: CGFloat { progressBarHeight + 12 }
    
    var body: some View {
        NavigationStack {
            Group {
                if photoLib.items.isEmpty {
                    Text("No \(mediaState == .flagged ? "flagged content" : mediaState.rawValue.lowercased()) 🎉")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                } else {
                    CardStackView(
                        items: photoLib.items,
                        onLeftSwipe: handleLeftSwipe,
                        onRightSwipe: handleRightSwipe,
                        undoTrigger: $undoTrigger,
                        swipeRightTrigger: $swipeRightTrigger
                    )
                    .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, bottomReserve)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings.toggle() } label: {
                        Image(systemName: "gear")
                            .foregroundColor(AppColors.primary)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Batch delete button with count badge
                    if deletionQueueCount > 0 {
                        Button { 
                            showDeletionAlert = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.red)
                                
                                // Badge showing count
                                Text("\(deletionQueueCount)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(3)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .offset(x: 8, y: -8)
                            }
                        }
                        .accessibilityLabel("Delete \(deletionQueueCount) items")
                    }
                    
                    Button { 
                        guard !photoLib.items.isEmpty else { return }
                        pendingMoveIndex = 0
                        print("[ContentView] Set pendingMoveIndex to 0, items count: \(photoLib.items.count)")
                        // Small delay to ensure state is updated
                        DispatchQueue.main.async {
                            self.showMoveSheet = true
                            print("[ContentView] Showing sheet with pendingMoveIndex: \(String(describing: self.pendingMoveIndex))")
                        }
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(AppColors.primary)
                    }
                    .accessibilityLabel("Move to album")
                    .disabled(photoLib.items.isEmpty)
                    
                    Button(action: performUndo) {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundColor(AppColors.primary)
                    }
                    .disabled(lastAction == nil)
                    .padding(.leading, 8)
                }
            }
            .background(
                ShakeDetectorView { if shakeToUndoEnabled { performUndo() } }
                    .frame(width: 0, height: 0)
            )
            .sheet(isPresented: $showSettings) {
                SettingsView(shakeToUndoEnabled: $shakeToUndoEnabled, photoLibrary: photoLib)
            }
            .sheet(isPresented: $showMoveSheet) {
                albumPickerSheet
            }
            .alert("Delete \(deletionQueueCount) Photos?", isPresented: $showDeletionAlert) {
                Button("Cancel", role: .cancel) {
                    // Clear the queue and restore photos
                    photoLib.clearDeletionQueue()
                    deletionQueueCount = 0
                }
                Button("Delete", role: .destructive) {
                    Task {
                        let result = await photoLib.processDeletionQueue()
                        if result.success {
                            deletionQueueCount = 0
                            await refreshCounts()
                        }
                    }
                }
            } message: {
                Text("This will delete all \(deletionQueueCount) queued photos. You'll see one confirmation dialog from iOS.")
            }
            .task {
                if photoLib.context == nil {
                    photoLib.setContext(modelContext)
                    Task { 
                        await reloadForCurrentState()
                        await refreshCounts()
                    }
                }
            }
            .onChange(of: mediaState) { oldValue, newValue in
                stateChangeToken &+= 1
                let myToken = stateChangeToken
                Task {
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    guard myToken == stateChangeToken else { return }
                    await reloadForCurrentState()
                    await refreshCounts()
                }
            }
            .onChange(of: photoLib.countsVersion) { oldValue, newValue in
                Task { await refreshCounts() }
            }
            .onChange(of: photoLib.isScanningContent) { oldValue, newValue in
                if !newValue && mediaState == .flagged {
                    Task { await reloadForCurrentState() }
                }
            }
            .onChange(of: photoLib.isLoading) { oldValue, newValue in
                if !newValue { showStartupSpinner = false }
            }
            .onChange(of: photoLib.items.count) { oldValue, newValue in
                if newValue > 0 { showStartupSpinner = false }
            }
            .overlay {
                if photoLib.items.isEmpty && (showStartupSpinner || photoLib.isLoading) {
                    if mediaState == .flagged && photoLib.isScanningContent {
                        LoadingOverlayView(
                            message: "Scanning your photos...\n\nAll analysis happens privately on your device.\n\nKeep the app open for fastest scanning.\n\nProgress: \(Int(photoLib.scanProgress * 100))%"
                        )
                    } else {
                        LoadingOverlayView(message: "Loading \(mediaState == .flagged ? "flagged content" : "your \(mediaState.rawValue)")...")
                    }
                }
            }
            .overlay(alignment: .top) {
                // Show deletion queue status
                if deletionQueueCount > 0 {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.white)
                        Text("\(deletionQueueCount) photo\(deletionQueueCount == 1 ? "" : "s") queued for deletion")
                            .foregroundColor(.white)
                            .font(.callout)
                            .fontWeight(.medium)
                        Spacer()
                        Button("Delete Now") {
                            showDeletionAlert = true
                        }
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(8)
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.red.opacity(0.9), Color.red.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    .padding()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(), value: deletionQueueCount)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            StepProgressBar(
                selection: $mediaState,
                counts: counts,
                isScanning: photoLib.isScanningContent,
                scanProgress: photoLib.scanProgress
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Album Picker Sheet
    
    @ViewBuilder
    private var albumPickerSheet: some View {
        let currentIndex = pendingMoveIndex ?? 0
        let hasItems = !photoLib.items.isEmpty && currentIndex < photoLib.items.count
        
        let _ = print("[ContentView] albumPickerSheet - pendingMoveIndex: \(String(describing: pendingMoveIndex)), currentIndex: \(currentIndex), items count: \(photoLib.items.count), hasItems: \(hasItems)")
        
        if hasItems {
            AlbumPickerView(
                asset: photoLib.items[currentIndex].asset,
                albums: photoLib.fetchAlbums(),
                onSelection: { albumId in
                    if let albumId = albumId {
                        _ = photoLib.items[currentIndex]
                        // Store the album ID for the swipe handler to use
                        pendingMoveAlbumId = albumId
                        // Trigger swipe right animation which will call handleRightSwipe
                        swipeRightTrigger = true
                    }
                    showMoveSheet = false
                    pendingMoveIndex = nil
                },
                onCreate: { albumName in
                    // Create album and move asset
                    Task { @MainActor in
                        await createAlbumAndMove(named: albumName, assetIndex: currentIndex)
                    }
                }
            )
        } else {
            NavigationStack {
                Text("No photo selected")
                    .foregroundColor(.secondary)
                    .navigationTitle("Move to Album")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showMoveSheet = false
                                pendingMoveIndex = nil
                            }
                        }
                    }
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleLeftSwipe(_ index: Int, _ item: PhotoItem) {
        lastAction = .left(index: index, item: item)
        // Queue for deletion instead of immediate delete
        photoLib.queueForDeletion(item.asset)
        deletionQueueCount = photoLib.getDeletionQueueCount()
        // Immediately decrement the count for current media type
        decrementCurrentCount()
        
        // Auto-process batch if enabled and batch size reached
        if autoBatchDeletions && deletionQueueCount >= batchDeletionSize {
            Task {
                let result = await photoLib.processDeletionQueue()
                if result.success {
                    deletionQueueCount = 0
                    await refreshCounts()
                }
            }
        }
    }
    
    private func handleRightSwipe(_ index: Int, _ item: PhotoItem) {
        // Check if this is a move to album operation
        if let albumId = pendingMoveAlbumId {
            lastAction = .move(index: index, item: item, albumID: albumId)
            // Immediately decrement the count for current media type
            decrementCurrentCount()
            Task { @MainActor in
                await photoLib.moveAsset(item.asset, to: albumId)
            }
            pendingMoveAlbumId = nil
        } else {
            lastAction = .right(index: index, item: item)
            // Immediately decrement the count for current media type
            decrementCurrentCount()
            Task { @MainActor in
                await photoLib.keepAsset(item.asset)
            }
        }
    }
    
    
    private func performUndo() {
        guard lastAction != nil else { return }
        undoTrigger = true
        lastAction = nil
    }
    
    private func reloadForCurrentState() async {
        await photoLib.loadItems(for: mediaState)
    }
    
    private func refreshCounts() async {
        counts = await photoLib.getCounts()
    }
    
    private func decrementCurrentCount() {
        // Immediately update the UI count for the current media type
        switch mediaState {
        case .photos:
            counts.photos = max(0, counts.photos - 1)
        case .screenshots:
            counts.screenshots = max(0, counts.screenshots - 1)
        case .videos:
            counts.videos = max(0, counts.videos - 1)
        case .flagged:
            counts.flagged = max(0, counts.flagged - 1)
        }
    }
    
    private func createAlbumAndMove(named name: String, assetIndex: Int) async {
        guard assetIndex < photoLib.items.count else { return }
        
        // Create the album
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            }) { success, error in
                continuation.resume()
            }
        }
        
        // Fetch the newly created album
        let albums = photoLib.fetchAlbums()
        if let newAlbum = albums.first(where: { $0.title == name }) {
            // Store the album ID for the swipe handler to use
            pendingMoveAlbumId = newAlbum.id
            // Trigger swipe right animation which will call handleRightSwipe
            swipeRightTrigger = true
        }
        
        showMoveSheet = false
        pendingMoveIndex = nil
    }
}

// MARK: - Loading Overlay

struct LoadingOverlayView: View {
    let message: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(AppColors.primary)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [KeptAsset.self, SensitiveAsset.self], inMemory: true)
}
