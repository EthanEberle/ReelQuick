//
//  AlbumPickerView.swift
//  FotoFlow
//
//  Album selection sheet for moving photos
//

import SwiftUI
import Photos

struct AlbumPickerView: View {
    let asset: PHAsset
    let photoLibrary: PhotoLibrary
    let onSelection: (String?) -> Void
    
    @State private var albums: [AlbumRef] = []
    @State private var isCreatingAlbum = false
    @State private var newAlbumName = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Select Album") {
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
                
                Section {
                    Button(action: {
                        isCreatingAlbum = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(AppColors.primary)
                            Text("Create New Album")
                                .foregroundColor(AppColors.primary)
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
            .sheet(isPresented: $isCreatingAlbum) {
                CreateAlbumSheet(albumName: $newAlbumName) { name in
                    if !name.isEmpty {
                        createAlbum(named: name)
                    }
                    isCreatingAlbum = false
                }
            }
        }
        .onAppear {
            loadAlbums()
        }
    }
    
    private func loadAlbums() {
        albums = photoLibrary.fetchAlbums()
    }
    
    private func createAlbum(named name: String) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
        }) { success, error in
            if success {
                DispatchQueue.main.async {
                    loadAlbums()
                }
            }
        }
    }
}

struct CreateAlbumSheet: View {
    @Binding var albumName: String
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Album Name", text: $albumName)
                    .textFieldStyle(.roundedBorder)
            }
            .navigationTitle("New Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        onCreate(albumName)
                        dismiss()
                    }
                    .disabled(albumName.isEmpty)
                }
            }
        }
    }
}