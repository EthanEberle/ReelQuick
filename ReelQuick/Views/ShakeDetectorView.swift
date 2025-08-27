//
//  ShakeDetectorView.swift
//  ReelQuick
//
//  Detects shake gestures for undo functionality
//

import SwiftUI
import UIKit

struct ShakeDetectorView: UIViewRepresentable {
    let onShake: () -> Void
    
    func makeUIView(context: Context) -> ShakeDetectorUIView {
        let view = ShakeDetectorUIView()
        view.onShake = onShake
        return view
    }
    
    func updateUIView(_ uiView: ShakeDetectorUIView, context: Context) {
        uiView.onShake = onShake
    }
}

class ShakeDetectorUIView: UIView {
    var onShake: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        becomeFirstResponder()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        becomeFirstResponder()
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            onShake?()
        }
    }
}