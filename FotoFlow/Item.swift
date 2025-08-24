//
//  Item.swift
//  FotoFlow
//
//  Created by Ethan Eberle on 8/23/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
