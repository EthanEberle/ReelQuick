//
//  Constants.swift
//  ReelQuick
//
//  App-wide constants and color definitions
//

import SwiftUI

struct AppColors {
    /// Primary brand color - Teal (#50A7B1)
    static let primary = Color(red: 0x50/255.0, green: 0xA7/255.0, blue: 0xB1/255.0)
    
    /// Primary brand color with custom opacity
    static func primary(_ opacity: Double) -> Color {
        return primary.opacity(opacity)
    }
}

struct AppConstants {
    static let backgroundTaskIdentifier = "com.reelquick.sensitivityScan"
    static let defaultPageSize = 48
    static let imageCacheMemoryLimit = 120_000_000 // 120MB
}