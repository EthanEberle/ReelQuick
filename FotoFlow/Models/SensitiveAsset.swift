//
//  SensitiveAsset.swift
//  FotoFlow
//
//  SwiftData model for caching assets classified as sensitive content
//

import Foundation
import SwiftData

@Model
final class SensitiveAsset {
    @Attribute(.unique) var id: String
    
    init(id: String) {
        self.id = id
    }
}