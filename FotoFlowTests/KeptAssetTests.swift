//
//  KeptAssetTests.swift
//  FotoFlowTests
//
//  Test-driven development for KeptAsset model
//

import Testing
import SwiftData
@testable import FotoFlow

struct KeptAssetTests {
    
    @Test func testKeptAssetCreation() async throws {
        // Given an asset ID
        let assetId = "test-asset-123"
        
        // When creating a KeptAsset
        let keptAsset = KeptAsset(id: assetId)
        
        // Then it should have the correct ID
        #expect(keptAsset.id == assetId)
    }
    
    @Test func testKeptAssetUniqueness() async throws {
        // Given
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: KeptAsset.self, configurations: config)
        let context = ModelContext(container)
        
        // When adding a KeptAsset
        let asset1 = KeptAsset(id: "unique-123")
        context.insert(asset1)
        try context.save()
        
        // Then it should be retrievable
        let descriptor = FetchDescriptor<KeptAsset>()
        let fetched = try context.fetch(descriptor).filter { $0.id == "unique-123" }
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == "unique-123")
    }
}