//
//  KeptAsset.swift
//  ReelQuick
//
//  SwiftData model for tracking assets that user kept (right-swiped)
//

import Foundation
import SwiftData

@Model
final class KeptAsset {
    @Attribute(.unique) var id: String
    
    init(id: String) {
        self.id = id
    }
}