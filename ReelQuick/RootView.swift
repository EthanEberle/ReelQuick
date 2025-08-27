//
//  RootView.swift
//  ReelQuick
//
//  Root view that manages onboarding and main app flow
//

import SwiftUI
import Photos

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var photoAuthStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    
    var body: some View {
        Group {
            if hasCompletedOnboarding && (photoAuthStatus == .authorized || photoAuthStatus == .limited) {
                ContentView()
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                    photoAuthStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                }
            }
        }
        .onAppear {
            checkPhotoAuthorization()
        }
    }
    
    private func checkPhotoAuthorization() {
        photoAuthStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if photoAuthStatus == .authorized || photoAuthStatus == .limited {
            hasCompletedOnboarding = true
        }
    }
}