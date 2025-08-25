//
//  ContentView.swift
//  FotoFlow
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
    @State private var lastAction: SwipeAction? = nil
    
    // Album move state
    @State private var showMoveSheet = false
    @State private var pendingMoveIndex: Int? = nil
    
    // Progress bar state
    @State private var mediaState: MediaState = .photos
    @State private var counts = MediaCounts()
    
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
                        onUpSwipe: handleUpSwipe,
                        undoTrigger: $undoTrigger
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
                    Button { showMoveSheet = true; pendingMoveIndex = 0 } label: {
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
                if let index = pendingMoveIndex, index < photoLib.items.count {
                    AlbumPickerView(
                        asset: photoLib.items[index].asset,
                        photoLibrary: photoLib
                    ) { albumId in
                        if let albumId = albumId {
                            Task {
                                await photoLib.moveAsset(photoLib.items[index].asset, to: albumId)
                            }
                        }
                        showMoveSheet = false
                        pendingMoveIndex = nil
                    }
                }
            }
            .task {
                if photoLib.context == nil {
                    photoLib.setContext(modelContext)
                    Task { await reloadForCurrentState() }
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
                if newValue { showStartupSpinner = false }
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
    
    // MARK: - Actions
    
    private func handleLeftSwipe(_ index: Int, _ item: PhotoItem) {
        lastAction = .left(index: index, item: item)
        Task {
            await photoLib.deleteAsset(item.asset)
        }
    }
    
    private func handleRightSwipe(_ index: Int, _ item: PhotoItem) {
        lastAction = .right(index: index, item: item)
        Task {
            await photoLib.keepAsset(item.asset)
        }
    }
    
    private func handleUpSwipe(_ index: Int, _ item: PhotoItem) {
        pendingMoveIndex = index
        showMoveSheet = true
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
