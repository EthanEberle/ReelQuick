//
//  SensitiveAssetTests.swift
//  FotoFlowTests
//
//  Test-driven development for SensitiveAsset model
//

import Testing
import SwiftData
@testable import FotoFlow

struct SensitiveAssetTests {
    
    @Test func testSensitiveAssetCreation() async throws {
        // Given an asset ID
        let assetId = "sensitive-asset-456"
        
        // When creating a SensitiveAsset
        let sensitiveAsset = SensitiveAsset(id: assetId)
        
        // Then it should have the correct ID
        #expect(sensitiveAsset.id == assetId)
    }
    
    @Test func testSensitiveAssetPersistence() async throws {
        // Given
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SensitiveAsset.self, configurations: config)
        let context = ModelContext(container)
        
        // When adding multiple SensitiveAssets
        let asset1 = SensitiveAsset(id: "nsfw-001")
        let asset2 = SensitiveAsset(id: "nsfw-002")
        context.insert(asset1)
        context.insert(asset2)
        try context.save()
        
        // Then they should all be retrievable
        let descriptor = FetchDescriptor<SensitiveAsset>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 2)
        
        let ids = fetched.map { $0.id }.sorted()
        #expect(ids == ["nsfw-001", "nsfw-002"])
    }
}