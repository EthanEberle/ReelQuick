//
//  AlbumRefTests.swift
//  ReelQuickTests
//
//  Test-driven development for AlbumRef model
//

import Testing
import Photos
@testable import ReelQuick

struct AlbumRefTests {
    
    @Test func testAlbumRefCreation() async throws {
        // Given
        let albumId = "album-123"
        let albumTitle = "My Photos"
        let mockCollection = MockPHAssetCollection(identifier: albumId, title: albumTitle)
        
        // When creating an AlbumRef
        let albumRef = AlbumRef(
            id: albumId,
            title: albumTitle,
            collection: mockCollection
        )
        
        // Then it should have the correct properties
        #expect(albumRef.id == albumId)
        #expect(albumRef.title == albumTitle)
        #expect(albumRef.collection === mockCollection)
    }
    
    @Test func testAlbumRefHashable() async throws {
        // Given two album refs
        let collection1 = MockPHAssetCollection(identifier: "id1", title: "Album 1")
        let collection2 = MockPHAssetCollection(identifier: "id2", title: "Album 2")
        
        let ref1 = AlbumRef(id: "id1", title: "Album 1", collection: collection1)
        let ref2 = AlbumRef(id: "id2", title: "Album 2", collection: collection2)
        
        // When adding to a Set
        var albumSet = Set<AlbumRef>()
        albumSet.insert(ref1)
        albumSet.insert(ref2)
        
        // Then the set should contain both
        #expect(albumSet.count == 2)
        #expect(albumSet.contains(ref1))
        #expect(albumSet.contains(ref2))
    }
}

// Mock PHAssetCollection for testing
class MockPHAssetCollection: PHAssetCollection {
    private let mockIdentifier: String
    private let mockTitle: String
    
    init(identifier: String, title: String) {
        self.mockIdentifier = identifier
        self.mockTitle = title
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var localIdentifier: String {
        return mockIdentifier
    }
    
    override var localizedTitle: String? {
        return mockTitle
    }
}