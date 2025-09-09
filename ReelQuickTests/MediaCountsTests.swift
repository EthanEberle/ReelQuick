//
//  MediaCountsTests.swift
//  ReelQuickTests
//
//  Tests for MediaCounts functionality
//

import Testing
@testable import ReelQuick

struct MediaCountsTests {
    
    @Test func testInitialCounts() {
        let counts = MediaCounts()
        #expect(counts.photos == 0)
        #expect(counts.screenshots == 0)
        #expect(counts.videos == 0)
        #expect(counts.flagged == 0)
    }
    
    @Test func testCountForState() {
        var counts = MediaCounts()
        counts.photos = 10
        counts.screenshots = 5
        counts.videos = 3
        counts.flagged = 2
        
        #expect(counts.count(for: .photos) == 10)
        #expect(counts.count(for: .screenshots) == 5)
        #expect(counts.count(for: .videos) == 3)
        #expect(counts.count(for: .flagged) == 2)
    }
    
    @Test func testCountsEquality() {
        let counts1 = MediaCounts(photos: 10, screenshots: 5, videos: 3, flagged: 2)
        let counts2 = MediaCounts(photos: 10, screenshots: 5, videos: 3, flagged: 2)
        let counts3 = MediaCounts(photos: 10, screenshots: 5, videos: 3, flagged: 1)
        
        #expect(counts1 == counts2)
        #expect(counts1 != counts3)
    }
}