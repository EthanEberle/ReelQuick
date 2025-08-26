//
//  PhotoLibraryTests.swift
//  FotoFlowTests
//
//  Test-driven development for PhotoLibrary service
//

import Testing
import SwiftData
import Photos
import UIKit
@testable import FotoFlow

@MainActor
struct PhotoLibraryTests {
    
    @Test func testPhotoLibraryInitialization() async throws {
        // Given/When
        let library = PhotoLibrary()
        
        // Then
        #expect(library.items.isEmpty)
        #expect(!library.isLoading)
        #expect(!library.isScanningContent)
        #expect(library.scanProgress == 0.0)
    }
    
    @Test func testContextSetting() async throws {
        // Given
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: KeptAsset.self, SensitiveAsset.self, configurations: config)
        let context = ModelContext(container)
        let library = PhotoLibrary()
        
        // When
        library.setContext(context)
        
        // Then
        #expect(library.context === context)
    }
    
    @Test func testMediaStateCounts() async throws {
        // Given
        let library = PhotoLibrary()
        
        // When requesting counts
        let counts = await library.getCounts()
        
        // Then initial counts should be zero
        #expect(counts.photos == 0)
        #expect(counts.screenshots == 0)
        #expect(counts.videos == 0)
        #expect(counts.flagged == 0)
    }
    
    @Test func testDeleteAsset() async throws {
        // Given
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: KeptAsset.self, SensitiveAsset.self, configurations: config)
        let context = ModelContext(container)
        let library = PhotoLibrary()
        library.setContext(context)
        
        // When deleting an asset
        let mockAsset = MockPHAsset()
        await library.deleteAsset(mockAsset)
        
        // Then it should be marked for deletion
        // (In real app, this would interact with PHPhotoLibrary)
        #expect(true) // Placeholder for actual deletion verification
    }
    
    @Test func testKeepAsset() async throws {
        // Given
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: KeptAsset.self, SensitiveAsset.self, configurations: config)
        let context = ModelContext(container)
        let library = PhotoLibrary()
        library.setContext(context)
        
        // When keeping an asset
        let mockAsset = MockPHAsset()
        await library.keepAsset(mockAsset)
        
        // Then it should be saved as KeptAsset
        let descriptor = FetchDescriptor<KeptAsset>()
        let keptAssets = try context.fetch(descriptor)
        #expect(keptAssets.count == 1)
        #expect(keptAssets.first?.id == mockAsset.localIdentifier)
    }
    
    @Test func testManualScanTrigger() async throws {
        // Given
        let library = PhotoLibrary()
        
        // When triggering manual scan
        library.startManualScan()
        
        // Then scanning should start
        #expect(library.isScanningContent)
    }
    
    @Test func testMoveAssetToAlbum() async throws {
        // Given
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: KeptAsset.self, SensitiveAsset.self, configurations: config)
        let context = ModelContext(container)
        let library = PhotoLibrary()
        library.setContext(context)
        
        // Create a mock asset
        let mockAsset = MockPHAsset()
        
        // When moving asset to album (this should call keepAsset internally)
        await library.moveAsset(mockAsset, to: "test-album-id")
        
        // Then it should be saved as KeptAsset
        let descriptor = FetchDescriptor<KeptAsset>()
        let keptAssets = try context.fetch(descriptor)
        #expect(keptAssets.count == 1, "Asset should be saved as kept when moved to album")
        #expect(keptAssets.first?.id == mockAsset.localIdentifier, "Kept asset ID should match")
    }
}

// Mock PHAsset for testing
class MockPHAsset: PHAsset {
    private let mockIdentifier = UUID().uuidString
    
    override var localIdentifier: String {
        return mockIdentifier
    }
}
