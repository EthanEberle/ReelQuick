//
//  SettingsView.swift
//  ReelQuick
//
//  Settings screen with app preferences and actions
//

import SwiftUI

struct SettingsView: View {
    @Binding var shakeToUndoEnabled: Bool
    let photoLibrary: PhotoLibrary
    
    @AppStorage("NSFWThresholdOverride") private var nsfwThreshold: Double = 0.8
    @AppStorage("autoBatchDeletions") private var autoBatchDeletions = true
    @AppStorage("batchDeletionSize") private var batchDeletionSize = 10
    @Environment(\.dismiss) private var dismiss
    @State private var showingThresholdInfo = false
    @State private var isScanning = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Preferences") {
                    Toggle(isOn: $shakeToUndoEnabled) {
                        Label("Shake to Undo", systemImage: "iphone.gen3")
                    }
                    .tint(AppColors.primary)
                }
                
                Section {
                    Toggle(isOn: $autoBatchDeletions) {
                        Label("Batch Deletions", systemImage: "trash.square.fill")
                    }
                    .tint(AppColors.primary)
                    
                    if autoBatchDeletions {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Delete after \(batchDeletionSize) swipes")
                                .font(.subheadline)
                            
                            Slider(value: Binding(
                                get: { Double(batchDeletionSize) },
                                set: { batchDeletionSize = Int($0) }
                            ), in: 5...30, step: 5)
                            .tint(AppColors.primary)
                            
                            Text("Photos will be queued and deleted together")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Deletion Settings")
                } footer: {
                    Text("When enabled, photos will be queued for batch deletion to minimize iOS confirmation prompts. You'll only see one prompt per batch.")
                        .font(.caption)
                }
                
                Section("Content Filtering") {
                    HStack {
                        Text("Sensitivity Threshold")
                        Spacer()
                        Text("\(Int(nsfwThreshold * 100))%")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $nsfwThreshold, in: 0.5...1.0, step: 0.05)
                        .tint(AppColors.primary)
                    
                    Button(action: {
                        showingThresholdInfo = true
                    }) {
                        Label("What is this?", systemImage: "questionmark.circle")
                            .font(.footnote)
                            .foregroundColor(AppColors.primary)
                    }
                    
                    Button(action: {
                        isScanning = true
                        photoLibrary.startManualScan()
                        dismiss()
                    }) {
                        HStack {
                            if isScanning && photoLibrary.isScanningContent {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                                Text("Scanning... \(Int(photoLibrary.scanProgress * 100))%")
                            } else {
                                Image(systemName: "magnifyingglass")
                                Text("Re-Scan for Sensitive Content")
                            }
                        }
                        .foregroundColor(AppColors.primary)
                    }
                    .disabled(photoLibrary.isScanningContent)
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "mailto:filtrapp@gmail.com")!) {
                        HStack {
                            Label("Contact Support", systemImage: "envelope")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(AppColors.primary)
                }
                
                Section {
                    Button(action: {
                        // Reset all preferences
                        UserDefaults.standard.removeObject(forKey: "NSFWThresholdOverride")
                        UserDefaults.standard.removeObject(forKey: "shakeToUndoEnabled")
                        UserDefaults.standard.removeObject(forKey: "sensitivityScanCompleted")
                        nsfwThreshold = 0.8
                        shakeToUndoEnabled = true
                        dismiss()
                    }) {
                        Text("Reset All Settings")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.primary)
                }
            }
            .alert("Sensitivity Threshold", isPresented: $showingThresholdInfo) {
                Button("OK") { }
            } message: {
                Text("Adjusts how sensitive the content detection is. Lower values flag more content, higher values are more permissive. All detection happens privately on your device.")
            }
        }
        .onChange(of: photoLibrary.isScanningContent) { oldValue, newValue in
            if !newValue {
                isScanning = false
            }
        }
    }
}
