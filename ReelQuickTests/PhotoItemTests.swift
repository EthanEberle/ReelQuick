//
//  PhotoItemTests.swift
//  FotoFlowTests
//
//  Test-driven development for PhotoItem model
//

import Testing
import Photos
import UIKit
@testable import FotoFlow

struct PhotoItemTests {
    
    @Test func testPhotoItemCreation() async throws {
        // Given a mock PHAsset and UIImage
        let mockAsset = PhotoItemMockPHAsset()
        let mockImage = UIImage(systemName: "photo")!
        
        // When creating a PhotoItem
        let photoItem = PhotoItem(asset: mockAsset, image: mockImage)
        
        // Then it should have the correct properties
        #expect(photoItem.asset === mockAsset)
        #expect(photoItem.image === mockImage)
        #expect(photoItem.id != UUID())  // Should have a unique ID
    }
    
    @Test func testPhotoItemIdentifiable() async throws {
        // Given two photo items
        let mockAsset = PhotoItemMockPHAsset()
        let mockImage = UIImage(systemName: "photo")!
        let item1 = PhotoItem(asset: mockAsset, image: mockImage)
        let item2 = PhotoItem(asset: mockAsset, image: mockImage)
        
        // Then they should have different IDs
        #expect(item1.id != item2.id)
    }
}

// Mock PHAsset for testing
class PhotoItemMockPHAsset: PHAsset {
    private let mockIdentifier = UUID().uuidString
    
    override var localIdentifier: String {
        return mockIdentifier
    }
}