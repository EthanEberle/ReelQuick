//
//  OnboardingView.swift
//  FotoFlow
//
//  Initial onboarding experience for new users
//

import SwiftUI
import Photos
import UserNotifications

struct OnboardingView: View {
    let onAuthorized: () -> Void
    
    @State private var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var isRequestingPhotos = false
    @State private var showDeniedHelp = false
    @State private var wantsNotifications = true
    @StateObject private var photoLibrary = PhotoLibrary()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)
                
                // App icon and title
                Image(systemName: "photo.stack")
                    .font(.system(size: 60))
                    .foregroundColor(AppColors.primary)
                    .padding(.bottom, 8)
                
                Text("FotoFlow")
                    .font(.largeTitle.bold())
                
                Text("Swipe through your camera roll.\nKeep the good ones. Archive the rest.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                // Feature highlights
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(
                        icon: "hand.thumbsup.fill",
                        title: "Swipe Right to Keep",
                        color: .green
                    )
                    FeatureRow(
                        icon: "trash.fill",
                        title: "Swipe Left to Archive",
                        color: .red
                    )
                    FeatureRow(
                        icon: "folder.badge.plus",
                        title: "Organize into Albums",
                        color: AppColors.primary
                    )
                    FeatureRow(
                        icon: "eye.slash.fill",
                        title: "Private Content Detection",
                        color: .purple
                    )
                    FeatureRow(
                        icon: "iphone.gen3",
                        title: "Shake to Undo",
                        color: .orange
                    )
                    FeatureRow(
                        icon: "lock.shield.fill",
                        title: "Your Media Stays Private",
                        color: .blue
                    )
                }
                .frame(maxWidth: 350, alignment: .leading)
                .padding(.vertical, 20)
                
                // Notification toggle
                Toggle(isOn: $wantsNotifications) {
                    Label("Weekly Cleanup Reminders", systemImage: "bell.badge")
                        .foregroundColor(.primary)
                }
                .toggleStyle(SwitchToggleStyle(tint: AppColors.primary))
                .padding(.horizontal, 40)
                
                // Get started button
                Button(action: requestPhotoAccess) {
                    HStack {
                        if isRequestingPhotos {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "photo.on.rectangle.angled")
                        }
                        Text("Grant Photo Access")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.primary)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .disabled(isRequestingPhotos)
                
                // Privacy note
                Text("FotoFlow never uploads your photos.\nAll processing happens on your device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer(minLength: 40)
            }
        }
        .alert("Photos Access Required", isPresented: $showDeniedHelp) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("FotoFlow needs access to your photos to help you organize them. Please enable access in Settings.")
        }
    }
    
    private func requestPhotoAccess() {
        isRequestingPhotos = true
        
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                self.photoStatus = status
                self.isRequestingPhotos = false
                
                switch status {
                case .authorized, .limited:
                    // Request notifications if wanted
                    if wantsNotifications {
                        requestNotificationPermission()
                    }
                    
                    // Start initial scan
                    photoLibrary.startManualScan()
                    
                    // Complete onboarding
                    onAuthorized()
                    
                case .denied, .restricted:
                    showDeniedHelp = true
                    
                default:
                    break
                }
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            if granted {
                scheduleWeeklyReminder()
            }
        }
    }
    
    private func scheduleWeeklyReminder() {
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 19   // 7 PM
        
        let content = UNMutableNotificationContent()
        content.title = "Time to tidy your camera roll"
        content.body = "A few quick swipes keeps things neat."
        content.sound = .default
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "fotoflow.weeklyReminder",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)
                .frame(width: 30)
            
            Text(title)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}
