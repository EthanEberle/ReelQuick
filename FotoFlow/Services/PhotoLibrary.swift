//
//  PhotoLibrary.swift
//  FotoFlow
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
    
    // MARK: - Constants
    private let pageSize = 48
    private let imageCacheMemoryLimit = 120_000_000 // 120MB
    
    // MARK: - Initialization
    init() {
        setupImageCache()
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
        
        // If there are no kept assets, use fast fetch methods
        if keptAssetIds.isEmpty {
            // Count screenshots
            let screenshotOptions = PHFetchOptions()
            screenshotOptions.predicate = NSPredicate(format: "mediaSubtype = %d", PHAssetMediaSubtype.photoScreenshot.rawValue)
            counts.screenshots = PHAsset.fetchAssets(with: screenshotOptions).count
            
            // Count photos (excluding screenshots)
            let photoOptions = PHFetchOptions()
            photoOptions.predicate = NSPredicate(format: "mediaType = %d AND NOT (mediaSubtype = %d)", 
                                                PHAssetMediaType.image.rawValue,
                                                PHAssetMediaSubtype.photoScreenshot.rawValue)
            counts.photos = PHAsset.fetchAssets(with: photoOptions).count
            
            // Count videos
            let videoOptions = PHFetchOptions()
            videoOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
            counts.videos = PHAsset.fetchAssets(with: videoOptions).count
        } else {
            // Need to exclude kept assets, so fetch and filter
            let allOptions = PHFetchOptions()
            let allAssets = PHAsset.fetchAssets(with: allOptions)
            
            allAssets.enumerateObjects { asset, _, _ in
                // Skip if kept
                if keptAssetIds.contains(asset.localIdentifier) {
                    return
                }
                
                // Categorize by type
                if asset.mediaType == .video {
                    counts.videos += 1
                } else if asset.mediaType == .image {
                    if asset.mediaSubtypes.contains(.photoScreenshot) {
                        counts.screenshots += 1
                    } else {
                        counts.photos += 1
                    }
                }
            }
        }
        
        // Count flagged (excluding kept assets and deletion queue)
        if let context = context {
            let descriptor = FetchDescriptor<SensitiveAsset>()
            let sensitiveAssets = (try? context.fetch(descriptor)) ?? []
            // Filter out any sensitive assets that have been kept or are pending deletion
            let flaggedCount = sensitiveAssets.filter { 
                !keptAssetIds.contains($0.id) && !deletionQueue.contains($0.id) 
            }.count
            counts.flagged = flaggedCount
        }
        
        return counts
    }
    
    func loadItems(for state: MediaState, page: Int = 0) async {
        isLoading = true
        defer { isLoading = false }
        
        let fetchResult = fetchAssets(for: state)
        currentFetchResult = fetchResult
        
        if page == 0 {
            items.removeAll()
            loadedAssetIds.removeAll()
        }
        
        // Get kept assets to exclude (for ALL states including flagged)
        var keptAssetIds = Set<String>()
        if let context = context {
            let keptDescriptor = FetchDescriptor<KeptAsset>()
            keptAssetIds = Set((try? context.fetch(keptDescriptor).map { $0.id }) ?? [])
        }
        
        // For flagged state, also exclude deleted assets from queue
        var excludedIds = keptAssetIds
        if state == .flagged {
            excludedIds.formUnion(deletionQueue)
        }
        
        let startIndex = page * pageSize
        var currentIndex = startIndex
        var endIndex = min(startIndex + pageSize, fetchResult.count)
        var newItems: [PhotoItem] = []
        var attempts = 0
        let maxAttempts = 10 // Prevent infinite loops
        
        // Continue loading until we have enough items or reach the end
        while newItems.count < pageSize && currentIndex < fetchResult.count && attempts < maxAttempts {
            attempts += 1
            
            for index in currentIndex..<min(endIndex, fetchResult.count) {
                let asset = fetchResult.object(at: index)
                let assetId = asset.localIdentifier
                
                // Skip if already loaded or excluded
                guard !loadedAssetIds.contains(assetId) && !excludedIds.contains(assetId) else { continue }
                
                if let image = await loadImage(for: asset) {
                    let item = PhotoItem(asset: asset, image: image)
                    newItems.append(item)
                    loadedAssetIds.insert(assetId)
                    
                    // Stop if we have enough items
                    if newItems.count >= pageSize {
                        break
                    }
                }
            }
            
            // If we haven't loaded enough items, try the next batch
            if newItems.count < pageSize && endIndex < fetchResult.count {
                currentIndex = endIndex
                endIndex = min(endIndex + pageSize, fetchResult.count)
            } else {
                break
            }
        }
        
        items.append(contentsOf: newItems)
    }
    
    func deleteAsset(_ asset: PHAsset) async {
        let assetId = asset.localIdentifier
        deletionQueue.append(assetId)
        
        // Also remove from sensitive assets if it exists
        if let context = context {
            let descriptor = FetchDescriptor<SensitiveAsset>(
                predicate: #Predicate { $0.id == assetId }
            )
            if let sensitiveAsset = try? context.fetch(descriptor).first {
                context.delete(sensitiveAsset)
                try? context.save()
            }
        }
        
        // Process deletion
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }) { success, error in
            if !success, let error = error {
                if self.logEnabled {
                    print("[PhotoLibrary] Delete failed: \(error)")
                }
            }
        }
        
        // Remove from current items
        items.removeAll { $0.asset.localIdentifier == asset.localIdentifier }
    }
    
    func keepAsset(_ asset: PHAsset) async {
        guard let context = context else { return }
        
        let assetId = asset.localIdentifier
        
        // Check if already kept to avoid duplicates
        let descriptor = FetchDescriptor<KeptAsset>(
            predicate: #Predicate { $0.id == assetId }
        )
        let existingKept = try? context.fetch(descriptor).first
        
        if existingKept == nil {
            let keptAsset = KeptAsset(id: assetId)
            context.insert(keptAsset)
            
            do {
                try context.save()
            } catch {
                if logEnabled {
                    print("[PhotoLibrary] Failed to save kept asset: \(error)")
                }
            }
        }
        
        // Remove from current items
        items.removeAll { $0.asset.localIdentifier == assetId }
    }
    
    func moveAsset(_ asset: PHAsset, to albumId: String) async {
        await keepAsset(asset)
        
        // Add to album
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
        }
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
            if await !self.isScanningContent { break }
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
        
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }
        
        let size = targetSize ?? CGSize(
            width: UIScreen.main.bounds.width * UIScreen.main.scale,
            height: UIScreen.main.bounds.height * UIScreen.main.scale
        )
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if let image = image {
                    self.imageCache.setObject(image, forKey: cacheKey, cost: image.pngData()?.count ?? 0)
                }
                continuation.resume(returning: image)
            }
        }
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
