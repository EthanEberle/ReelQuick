//
//  AlbumRef.swift
//  ReelQuick
//
//  Lightweight reference to a photo album
//

import Foundation
import Photos

struct AlbumRef: Identifiable, Hashable {
    let id: String  // PHAssetCollection.localIdentifier
    let title: String
    let collection: PHAssetCollection
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AlbumRef, rhs: AlbumRef) -> Bool {
        lhs.id == rhs.id
    }
}