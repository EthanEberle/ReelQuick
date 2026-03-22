//
//  PhotoLibrary.swift
//  ReelQuick
//
//  Photo library management service with background scanning
//

@preconcurrency import Photos
import SwiftData
import SwiftUI
import UIKit
import BackgroundTasks

@MainActor
final class PhotoLibrary: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var items: [PhotoItem] = []
    @Published var isLoading = false
    @Published var isCounting = false
    @Published var countsVersion = 0
    @Published var isScanningContent = false
    @Published var scanProgress: Double = 0.0
    
    // MARK: - Storage
    @AppStorage("sensitivityScanCompleted") private var scanCompleted = false
    @AppStorage("sensitivityScanVersion") private var scanVersion = 0
    
    // MARK: - Private Properties
    private(set) var context: ModelContext?
    private var hasRegisteredBackgroundTask = false
    private var sensitivityScanStarted = false
    private let logEnabled = true

    private var imageCache = NSCache<NSString, UIImage>()
    private var currentFetchResult: PHFetchResult<PHAsset>?
    private var loadedAssetIds = Set<String>()
    private var deletionQueue: [String] = []
    private var pendingDeletionAssets: [PHAsset] = []
    private var lastLoadedState: MediaState?
    private var nextScanIndex = 0
    private var isPreloading = false
    private var loadGeneration = 0

    // Debouncing for count updates
    private var countUpdateTimer: Timer?
    private var pendingCountUpdate = false
    
    // MARK: - Constants
    private let pageSize = 48
    private let imageCacheMemoryLimit = 120_000_000 // 120MB

    /// Returns the image target size for the current app window.
    /// Uses key window bounds (not screen bounds) so Split View / Stage Manager
    /// on iPad request correctly-sized images for the actual allocated area.
    private var imageTargetSize: CGSize {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let bounds = windowScene?.keyWindow?.bounds ?? UIScreen.main.bounds
        let scale = windowScene?.screen.scale ?? UIScreen.main.scale
        return CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
    
    // MARK: - Initialization
    init() {
        setupImageCache()
    }

    // MARK: - Count Update Management

    private func triggerDebouncedCountUpdate() {
        // Cancel existing timer
        countUpdateTimer?.invalidate()

        // Set up new timer with 2.0 second delay for large libraries
        countUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.countsVersion += 1
            }
        }
    }

    // MARK: - Public Methods
    
    func setContext(_ ctx: ModelContext) {
        context = ctx
        startScanningIfNeeded()
    }
    
    func getCounts() async -> MediaCounts {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized ||
              PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited else {
            return MediaCounts()
        }

        var counts = MediaCounts()

        // Get kept asset IDs to exclude from counts
        var keptAssetIds = Set<String>()
        if let context = context {
            let keptDescriptor = FetchDescriptor<KeptAsset>()
            keptAssetIds = Set((try? context.fetch(keptDescriptor).map { $0.id }) ?? [])
        }

        // Combine kept and deletion-queued IDs — both represent "decided" assets
        // that should not appear in the remaining counts.
        let excludedIds = Array(keptAssetIds) + deletionQueue

        let screenshotOptions = PHFetchOptions()
        screenshotOptions.predicate = NSPredicate(format: "mediaSubtype = %d", PHAssetMediaSubtype.photoScreenshot.rawValue)
        let totalScreenshots = PHAsset.fetchAssets(with: screenshotOptions).count

        let photoOptions = PHFetchOptions()
        photoOptions.predicate = NSPredicate(format: "mediaType = %d AND NOT (mediaSubtype = %d)",
                                            PHAssetMediaType.image.rawValue,
                                            PHAssetMediaSubtype.photoScreenshot.rawValue)
        let totalPhotos = PHAsset.fetchAssets(with: photoOptions).count

        let videoOptions = PHFetchOptions()
        videoOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        let totalVideos = PHAsset.fetchAssets(with: videoOptions).count

        if excludedIds.isEmpty {
            counts.screenshots = totalScreenshots
            counts.photos = totalPhotos
            counts.videos = totalVideos
        } else {
            // Single indexed lookup for all excluded assets — fast regardless of count.
            // Enumerate to get accurate per-type breakdown for both kept and queued.
            let excludedResult = PHAsset.fetchAssets(withLocalIdentifiers: excludedIds, options: nil)
            var excludedPhotos = 0, excludedScreenshots = 0, excludedVideos = 0
            excludedResult.enumerateObjects { asset, _, _ in
                if asset.mediaType == .video {
                    excludedVideos += 1
                } else if asset.mediaSubtypes.contains(.photoScreenshot) {
                    excludedScreenshots += 1
                } else {
                    excludedPhotos += 1
                }
            }
            counts.screenshots = max(0, totalScreenshots - excludedScreenshots)
            counts.photos = max(0, totalPhotos - excludedPhotos)
            counts.videos = max(0, totalVideos - excludedVideos)
        }

        // Count flagged (excluding kept assets and deletion queue)
        if let context = context {
            let descriptor = FetchDescriptor<SensitiveAsset>()
            let sensitiveAssets = (try? context.fetch(descriptor)) ?? []
            let flaggedCount = sensitiveAssets.filter {
                !keptAssetIds.contains($0.id) && !deletionQueue.contains($0.id)
            }.count
            counts.flagged = flaggedCount
        }

        return counts
    }
    
    func loadItems(for state: MediaState) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        lastLoadedState = state
        defer { isLoading = false }

        let fetchResult = fetchAssets(for: state)
        currentFetchResult = fetchResult
        items.removeAll()
        loadedAssetIds.removeAll()
        nextScanIndex = 0

        var keptAssetIds = Set<String>()
        if let context = context {
            let keptDescriptor = FetchDescriptor<KeptAsset>()
            keptAssetIds = Set((try? context.fetch(keptDescriptor).map { $0.id }) ?? [])
        }
        var excludedIds = keptAssetIds
        excludedIds.formUnion(deletionQueue)

        let (newItems, nextIndex) = await fetchNextBatch(from: 0, fetchResult: fetchResult, excludedIds: excludedIds)
        guard generation == loadGeneration else { return }
        nextScanIndex = nextIndex
        for item in newItems { loadedAssetIds.insert(item.asset.localIdentifier) }
        items.append(contentsOf: newItems)
    }

    func loadMoreItems(for state: MediaState) async {
        guard !isLoading, !isPreloading else { return }
        guard let fetchResult = currentFetchResult, nextScanIndex < fetchResult.count else { return }

        let generation = loadGeneration
        isPreloading = true
        defer { isPreloading = false }

        var excludedIds = loadedAssetIds
        if let context = context {
            let keptDescriptor = FetchDescriptor<KeptAsset>()
            let keptIds = Set((try? context.fetch(keptDescriptor).map { $0.id }) ?? [])
            excludedIds.formUnion(keptIds)
        }
        excludedIds.formUnion(deletionQueue)

        let (newItems, nextIndex) = await fetchNextBatch(from: nextScanIndex, fetchResult: fetchResult, excludedIds: excludedIds)
        guard generation == loadGeneration else { return }
        nextScanIndex = nextIndex
        for item in newItems { loadedAssetIds.insert(item.asset.localIdentifier) }
        items.append(contentsOf: newItems)
    }

    private func fetchNextBatch(
        from startIndex: Int,
        fetchResult: PHFetchResult<PHAsset>,
        excludedIds: Set<String>
    ) async -> (items: [PhotoItem], nextScanIndex: Int) {
        var assetsToLoad: [PHAsset] = []
        var scanIndex = startIndex

        while assetsToLoad.count < pageSize && scanIndex < fetchResult.count {
            let asset = fetchResult.object(at: scanIndex)
            if !excludedIds.contains(asset.localIdentifier) {
                assetsToLoad.append(asset)
            }
            scanIndex += 1
        }

        guard !assetsToLoad.isEmpty else { return ([], scanIndex) }

        let targetSize = imageTargetSize

        // Separate cached from uncached
        var imageMap: [String: UIImage] = [:]
        var toFetch: [PHAsset] = []
        for asset in assetsToLoad {
            if let cached = imageCache.object(forKey: asset.localIdentifier as NSString) {
                imageMap[asset.localIdentifier] = cached
            } else {
                toFetch.append(asset)
            }
        }

        // Fetch uncached images concurrently
        let fetched: [(String, UIImage)] = await withTaskGroup(of: (String, UIImage)?.self) { group in
            for asset in toFetch {
                let localId = asset.localIdentifier
                group.addTask {
                    if let img = await PhotoLibrary.fetchImageData(for: asset, targetSize: targetSize) {
                        return (localId, img)
                    }
                    return nil
                }
            }
            var collected: [(String, UIImage)] = []
            for await pair in group { if let pair = pair { collected.append(pair) } }
            return collected
        }

        // Cache newly fetched images
        for (id, image) in fetched {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale) * 4
            imageCache.setObject(image, forKey: id as NSString, cost: cost)
            imageMap[id] = image
        }

        // Build items preserving original fetch order
        let newItems = assetsToLoad.compactMap { asset -> PhotoItem? in
            guard let image = imageMap[asset.localIdentifier] else { return nil }
            return PhotoItem(asset: asset, image: image)
        }

        return (newItems, scanIndex)
    }

    private nonisolated static func fetchImageData(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // iCloud photos may call back with a degraded placeholder first,
                // then again with the final image. Only resume on the final result
                // to avoid fatal "continuation resumed more than once" crashes.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isError = info?[PHImageErrorKey] != nil
                if isDegraded && !isError { return }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
    
    @MainActor
    func queueForDeletion(_ asset: PHAsset) {
        let assetId = asset.localIdentifier

        // Add to deletion queue if not already there
        if !deletionQueue.contains(assetId) {
            deletionQueue.append(assetId)
            pendingDeletionAssets.append(asset)
        }

        // Remove from current items immediately for better UX
        items.removeAll { $0.asset.localIdentifier == assetId }

        // Don't do any database operations here to avoid blocking
        // Just trigger debounced counts update
        triggerDebouncedCountUpdate()
    }
    
    @MainActor
    func processDeletionQueue() async -> (success: Bool, deletedCount: Int) {
        guard !pendingDeletionAssets.isEmpty else {
            return (true, 0)
        }
        
        let assetsToDelete = pendingDeletionAssets
        let count = assetsToDelete.count
        
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                // Batch delete all queued assets at once - only ONE confirmation dialog
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
            }) { [weak self] success, error in
                if success {
                    // Clear the queue on success
                    self?.deletionQueue.removeAll()
                    self?.pendingDeletionAssets.removeAll()
                    if self?.logEnabled ?? false {
                        print("[PhotoLibrary] Batch deleted \(count) assets successfully")
                    }
                } else if let error = error {
                    if self?.logEnabled ?? false {
                        print("[PhotoLibrary] Batch delete failed: \(error)")
                    }
                }
                continuation.resume(returning: (success, success ? count : 0))
            }
        }
    }
    
    @MainActor
    func getDeletionQueueCount() -> Int {
        return pendingDeletionAssets.count
    }
    
    @MainActor
    func removeFromDeletionQueue(_ asset: PHAsset) {
        let assetId = asset.localIdentifier
        if let index = deletionQueue.firstIndex(of: assetId) {
            deletionQueue.remove(at: index)
        }
        if let index = pendingDeletionAssets.firstIndex(where: { $0.localIdentifier == assetId }) {
            pendingDeletionAssets.remove(at: index)
        }
        // Trigger debounced counts update
        triggerDebouncedCountUpdate()
    }
    
    @MainActor
    func clearDeletionQueue() {
        deletionQueue.removeAll()
        pendingDeletionAssets.removeAll()
        // Reload items to show them again
        Task {
            if let state = lastLoadedState {
                await loadItems(for: state)
            }
        }
    }
    
    // Keep the old deleteAsset for compatibility but redirect to queue
    @MainActor
    func deleteAsset(_ asset: PHAsset) async {
        queueForDeletion(asset)
        // Let ContentView handle batch processing based on user preferences
    }
    
    @MainActor
    func keepAsset(_ asset: PHAsset) async {
        let assetId = asset.localIdentifier

        // Remove from current items immediately for responsive UI
        items.removeAll { $0.asset.localIdentifier == assetId }

        // Do the minimum database work needed, but don't block
        guard let context = context else { return }

        // Check if already kept to avoid duplicates (quick check)
        let descriptor = FetchDescriptor<KeptAsset>(
            predicate: #Predicate { $0.id == assetId }
        )

        if (try? context.fetch(descriptor).first) == nil {
            let keptAsset = KeptAsset(id: assetId)
            context.insert(keptAsset)
            do {
                try context.save()
            } catch {
                if logEnabled {
                    print("[PhotoLibrary] Failed to save kept asset: \(error)")
                }
                // Roll back: remove from context and reload so the asset reappears in UI
                context.delete(keptAsset)
                if let state = lastLoadedState {
                    await loadItems(for: state)
                }
            }
        }

        // Trigger debounced counts update
        triggerDebouncedCountUpdate()
    }
    
    @MainActor
    func removeKeptStatus(for asset: PHAsset) async {
        guard let context = context else { return }
        
        let assetId = asset.localIdentifier
        
        // Find and remove the kept asset from database
        let descriptor = FetchDescriptor<KeptAsset>(
            predicate: #Predicate { $0.id == assetId }
        )
        
        if let keptAsset = try? context.fetch(descriptor).first {
            context.delete(keptAsset)
            
            do {
                try context.save()
                if logEnabled {
                    print("[PhotoLibrary] Removed kept status for asset: \(assetId)")
                }
            } catch {
                if logEnabled {
                    print("[PhotoLibrary] Failed to remove kept status: \(error)")
                }
            }
        }

        // Trigger debounced counts update
        triggerDebouncedCountUpdate()
    }
    
    @MainActor
    func moveAsset(_ asset: PHAsset, to albumId: String) async {
        // Mark as kept (which removes from counts and current view)
        await keepAsset(asset)
        
        // Add to the specified album
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                if let album = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [albumId],
                    options: nil
                ).firstObject {
                    if let addRequest = PHAssetCollectionChangeRequest(for: album) {
                        addRequest.addAssets([asset] as NSArray)
                    }
                }
            }) { success, error in
                if !success, let error = error {
                    if self.logEnabled {
                        print("[PhotoLibrary] Failed to add to album: \(error)")
                    }
                }
                continuation.resume()
            }
        }

        // Trigger debounced counts update after move
        triggerDebouncedCountUpdate()
    }
    
    func startManualScan() {
        if logEnabled {
            print("[PhotoLibrary] Manual scan requested")
        }
        scanCompleted = false
        sensitivityScanStarted = false
        startScanningIfNeeded()
    }
    
    func fetchAlbums() -> [AlbumRef] {
        // Check authorization first
        let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authStatus == .authorized || authStatus == .limited else {
            if logEnabled {
                print("[PhotoLibrary] fetchAlbums: No photo library authorization, status: \(authStatus.rawValue)")
            }
            return []
        }
        
        var albums: [AlbumRef] = []
        
        // Create options object like ReelQuick does
        let options = PHFetchOptions()
        
        // Use albumRegular subtype to get only user-created albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: options
        )
        
        if logEnabled {
            print("[PhotoLibrary] fetchAlbums: Fetch result count: \(userAlbums.count)")
        }
        
        userAlbums.enumerateObjects { collection, index, _ in
            let title = collection.localizedTitle ?? "Untitled"
            albums.append(AlbumRef(
                id: collection.localIdentifier,
                title: title,
                collection: collection
            ))
            if self.logEnabled && index < 5 {
                print("[PhotoLibrary] fetchAlbums: Found album '\(title)'")
            }
        }
        
        if logEnabled {
            print("[PhotoLibrary] fetchAlbums: Total albums found: \(albums.count)")
        }
        
        return albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    
    // MARK: - Private Methods
    
    private func setupImageCache() {
        imageCache.totalCostLimit = imageCacheMemoryLimit
        imageCache.countLimit = 200
    }
    
    private func startScanningIfNeeded() {
        // Recovery mechanism: If scanning was started but app was killed, reset state
        if sensitivityScanStarted && !isScanningContent && !scanCompleted {
            if logEnabled {
                print("[PhotoLibrary] Detected interrupted scan, resetting state")
            }
            sensitivityScanStarted = false
            scanProgress = 0.0
        }
        
        guard !sensitivityScanStarted && !scanCompleted else { 
            if logEnabled {
                print("[PhotoLibrary] Scan not started: sensitivityScanStarted=\(sensitivityScanStarted), scanCompleted=\(scanCompleted)")
            }
            return 
        }
        
        if logEnabled {
            print("[PhotoLibrary] Starting sensitivity scan")
        }
        
        sensitivityScanStarted = true
        isScanningContent = true
        scanProgress = 0.0
        
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.performSensitivityScan()
            await MainActor.run {
                self.isScanningContent = false
                self.scanCompleted = true
                self.scanVersion += 1
                self.countsVersion += 1
                if self.logEnabled {
                    print("[PhotoLibrary] Scan finished and marked complete")
                }
            }
        }
    }
    
    private func performSensitivityScan() async {
        guard let context = context else { 
            if logEnabled { print("[PhotoLibrary] No context available for scan") }
            return 
        }
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Only scan photos, exclude screenshots
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d AND NOT (mediaSubtype = %d)", 
                                            PHAssetMediaType.image.rawValue,
                                            PHAssetMediaSubtype.photoScreenshot.rawValue)
        
        let allPhotos = PHAsset.fetchAssets(with: fetchOptions)
        let totalCount = allPhotos.count
        
        if logEnabled { 
            print("[PhotoLibrary] Starting sensitivity scan for \(totalCount) photos (excluding screenshots)")
        }
        
        var scannedCount = 0
        var flaggedCount = 0
        
        for index in 0..<totalCount {
            let asset = allPhotos.object(at: index)
            let assetId = asset.localIdentifier
            
            // Check if already scanned
            let descriptor = FetchDescriptor<SensitiveAsset>(
                predicate: #Predicate { $0.id == assetId }
            )
            if let existing = try? context.fetch(descriptor), !existing.isEmpty {
                if logEnabled && index < 10 { 
                    print("[PhotoLibrary] Asset \(index) already scanned, skipping")
                }
                continue
            }
            
            // Load and check image
            if let image = await loadImage(for: asset, targetSize: CGSize(width: 224, height: 224)) {
                let isSensitive = await NSFWDetector.shared.isSensitive(image)
                scannedCount += 1
                
                if isSensitive {
                    flaggedCount += 1
                    let sensitiveAsset = SensitiveAsset(id: asset.localIdentifier)
                    context.insert(sensitiveAsset)
                    try? context.save()
                    
                    if logEnabled {
                        print("[PhotoLibrary] ⚠️ Flagged image \(index) (total flagged: \(flaggedCount))")
                    }
                }
            } else {
                if logEnabled && index < 10 {
                    print("[PhotoLibrary] Failed to load image \(index)")
                }
            }
            
            // Update progress
            await MainActor.run {
                self.scanProgress = Double(index + 1) / Double(totalCount)
            }
            
            // Break if scanning was stopped
            if !self.isScanningContent { break }
        }
        
        if logEnabled {
            print("[PhotoLibrary] Scan complete: \(scannedCount) scanned, \(flaggedCount) flagged")
        }
    }
    
    private func fetchAssets(for state: MediaState) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        switch state {
        case .photos:
            options.predicate = NSPredicate(format: "mediaType = %d AND NOT (mediaSubtype = %d)",
                                           PHAssetMediaType.image.rawValue,
                                           PHAssetMediaSubtype.photoScreenshot.rawValue)
        case .screenshots:
            options.predicate = NSPredicate(format: "mediaSubtype = %d",
                                           PHAssetMediaSubtype.photoScreenshot.rawValue)
        case .videos:
            options.predicate = NSPredicate(format: "mediaType = %d",
                                           PHAssetMediaType.video.rawValue)
        case .flagged:
            if let context = context {
                // Get all sensitive assets
                let sensitiveDescriptor = FetchDescriptor<SensitiveAsset>()
                let sensitiveIds = Set((try? context.fetch(sensitiveDescriptor).map { $0.id }) ?? [])
                
                // Get kept assets to exclude
                let keptDescriptor = FetchDescriptor<KeptAsset>()
                let keptIds = Set((try? context.fetch(keptDescriptor).map { $0.id }) ?? [])
                
                // Filter out kept assets from sensitive assets
                let flaggedIds = sensitiveIds.subtracting(keptIds).subtracting(deletionQueue)
                
                if !flaggedIds.isEmpty {
                    return PHAsset.fetchAssets(withLocalIdentifiers: Array(flaggedIds), options: options)
                }
            }
            return PHFetchResult<PHAsset>()
        }
        
        return PHAsset.fetchAssets(with: options)
    }
    
    private func loadImage(for asset: PHAsset, targetSize: CGSize? = nil) async -> UIImage? {
        let cacheKey = asset.localIdentifier as NSString
        if let cached = imageCache.object(forKey: cacheKey) { return cached }

        let size = targetSize ?? imageTargetSize

        let image = await Self.fetchImageData(for: asset, targetSize: size)
        if let image = image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale) * 4
            imageCache.setObject(image, forKey: cacheKey, cost: cost)
        }
        return image
    }
    
    // MARK: - Background Task
    
    func registerAndScheduleBackgroundTaskIfNeeded() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        
        guard !hasRegisteredBackgroundTask else { return }
        hasRegisteredBackgroundTask = true
        
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppConstants.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let task = task as? BGProcessingTask else { return }
            self?.handleBackgroundTask(task)
        }
        
        scheduleBackgroundTask()
    }
    
    private func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: AppConstants.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        try? BGTaskScheduler.shared.submit(request)
    }
    
    private func handleBackgroundTask(_ task: BGProcessingTask) {
        scheduleBackgroundTask()
        
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        Task {
            if !self.scanCompleted {
                await self.performSensitivityScan()
            }
            task.setTaskCompleted(success: true)
        }
    }
}
