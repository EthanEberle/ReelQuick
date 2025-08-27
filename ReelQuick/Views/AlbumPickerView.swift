//
//  AlbumPickerView.swift
//  ReelQuick
//
//  Album selection sheet for moving photos
//

import SwiftUI
import Photos

struct AlbumPickerView: View {
    let asset: PHAsset
    let albums: [AlbumRef]
    let onSelection: (String?) -> Void
    let onCreate: (String) -> Void
    
    @State private var newAlbumName = ""
    @Environment(\.dismiss) private var dismiss
    
    init(asset: PHAsset, albums: [AlbumRef], onSelection: @escaping (String?) -> Void, onCreate: @escaping (String) -> Void) {
        self.asset = asset
        self.albums = albums
        self.onSelection = onSelection
        self.onCreate = onCreate
        print("[AlbumPickerView] Initialized with \(albums.count) albums")
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Create new Album at the top
                Section("Create New Album") {
                    HStack {
                        TextField("Album name", text: $newAlbumName)
                            .textInputAutocapitalization(.words)
                    }
                    Button {
                        let name = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        onCreate(name)
                        dismiss()
                    } label: {
                        Label("Create & Move Here", systemImage: "plus")
                            .foregroundColor(AppColors.primary)
                    }
                    .disabled(newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                // Existing albums below
                if !albums.isEmpty {
                    Section("Your Albums") {
                        ForEach(albums) { album in
                            Button(action: {
                                onSelection(album.id)
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundColor(AppColors.primary)
                                    Text(album.title)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onSelection(nil)
                        dismiss()
                    }
                }
            }
        }
    }
}