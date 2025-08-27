//
//  ReelQuickApp.swift
//  ReelQuick
//
//  Created by Ethan Eberle on 8/23/25.
//

import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct ReelQuickApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [KeptAsset.self, SensitiveAsset.self])
    }
}
