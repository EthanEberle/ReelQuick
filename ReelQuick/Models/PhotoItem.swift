//
//  PhotoItem.swift
//  FotoFlow
//
//  Model representing a single photo/video card in the swipe interface
//

import Foundation
import Photos
import UIKit

struct PhotoItem: Identifiable {
    let id = UUID()
    let asset: PHAsset
    let image: UIImage
}
