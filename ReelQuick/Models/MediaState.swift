//
//  MediaState.swift
//  ReelQuick
//
//  Media state and counts for the stepped progress bar
//

import Foundation

enum MediaState: String, CaseIterable, Identifiable, Equatable {
    case flagged = "Flagged"
    case photos = "Photos"
    case screenshots = "Screenshots"
    case videos = "Videos"
    
    var id: String { rawValue }
}

struct MediaCounts: Equatable {
    var photos: Int = 0
    var screenshots: Int = 0
    var videos: Int = 0
    var flagged: Int = 0
    
    func count(for state: MediaState) -> Int {
        switch state {
        case .photos:      return photos
        case .screenshots: return screenshots
        case .videos:      return videos
        case .flagged:     return flagged
        }
    }
}