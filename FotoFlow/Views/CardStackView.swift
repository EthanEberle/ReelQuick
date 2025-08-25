//
//  CardStackView.swift
//  FotoFlow
//
//  Tinder-style card swiping interface using Shuffle framework
//

import SwiftUI
import Shuffle
import UIKit
import Photos
import AVKit

// MARK: - Photo Card View

private final class PhotoSwipeCard: SwipeCard {
    init(image: UIImage, isVideo: Bool) {
        super.init(frame: .zero)
        layer.cornerRadius = 12
        layer.masksToBounds = true
        backgroundColor = .systemBackground
        
        let container = UIView()
        container.backgroundColor = .clear
        
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = container.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.layer.cornerRadius = 12
        container.addSubview(imageView)
        
        // Add bezel effect
        let bezelLayer = CAGradientLayer()
        bezelLayer.frame = container.bounds
        bezelLayer.colors = [
            UIColor.black.withAlphaComponent(0.06).cgColor,
            UIColor.black.withAlphaComponent(0.01).cgColor
        ]
        bezelLayer.startPoint = CGPoint(x: 0, y: 0)
        bezelLayer.endPoint = CGPoint(x: 1, y: 1)
        bezelLayer.cornerRadius = 12
        container.layer.addSublayer(bezelLayer)
        
        if isVideo {
            let playBackdrop = UIView()
            playBackdrop.translatesAutoresizingMaskIntoConstraints = false
            playBackdrop.backgroundColor = UIColor.black.withAlphaComponent(0.35)
            playBackdrop.layer.cornerRadius = 28
            playBackdrop.layer.masksToBounds = true
            
            let playIcon = UIImageView(image: UIImage(systemName: "play.fill"))
            playIcon.translatesAutoresizingMaskIntoConstraints = false
            playIcon.tintColor = .white
            playIcon.contentMode = .scaleAspectFit
            
            playBackdrop.addSubview(playIcon)
            container.addSubview(playBackdrop)
            
            NSLayoutConstraint.activate([
                playBackdrop.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                playBackdrop.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                playBackdrop.widthAnchor.constraint(equalToConstant: 56),
                playBackdrop.heightAnchor.constraint(equalToConstant: 56),
                
                playIcon.centerXAnchor.constraint(equalTo: playBackdrop.centerXAnchor),
                playIcon.centerYAnchor.constraint(equalTo: playBackdrop.centerYAnchor),
                playIcon.widthAnchor.constraint(equalToConstant: 24),
                playIcon.heightAnchor.constraint(equalToConstant: 24)
            ])
        }
        
        container.frame = bounds
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(container)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - SwiftUI Bridge

struct CardStackView: UIViewControllerRepresentable {
    let items: [PhotoItem]
    let onLeftSwipe: (Int, PhotoItem) -> Void
    let onRightSwipe: (Int, PhotoItem) -> Void
    let onUpSwipe: (Int, PhotoItem) -> Void
    @Binding var undoTrigger: Bool
    
    func makeUIViewController(context: Context) -> CardStackViewController {
        let controller = CardStackViewController()
        controller.coordinator = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CardStackViewController, context: Context) {
        uiViewController.updateItems(items)
        
        if undoTrigger {
            uiViewController.undoLastSwipe()
            DispatchQueue.main.async {
                undoTrigger = false
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, SwipeCardStackDataSource, SwipeCardStackDelegate {
        var parent: CardStackView
        var currentIndex = 0
        
        init(_ parent: CardStackView) {
            self.parent = parent
        }
        
        func cardStack(_ cardStack: SwipeCardStack, cardForIndexAt index: Int) -> SwipeCard {
            let item = parent.items[index]
            let isVideo = item.asset.mediaType == .video
            return PhotoSwipeCard(image: item.image, isVideo: isVideo)
        }
        
        func numberOfCards(in cardStack: SwipeCardStack) -> Int {
            return parent.items.count
        }
        
        func cardStack(_ cardStack: SwipeCardStack, didSwipeCardAt index: Int, with direction: SwipeDirection) {
            guard index < parent.items.count else { return }
            let item = parent.items[index]
            
            switch direction {
            case .left:
                parent.onLeftSwipe(index, item)
            case .right:
                parent.onRightSwipe(index, item)
            case .up:
                parent.onUpSwipe(index, item)
            default:
                break
            }
            
            currentIndex = min(index + 1, parent.items.count - 1)
        }
        
        func cardStack(_ cardStack: SwipeCardStack, didUndoCardAt index: Int, from direction: SwipeDirection) {
            currentIndex = index
        }
    }
}

// MARK: - UIKit Controller

class CardStackViewController: UIViewController {
    private var cardStack: SwipeCardStack!
    weak var coordinator: CardStackView.Coordinator?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        cardStack = SwipeCardStack()
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardStack)
        
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cardStack.topAnchor.constraint(equalTo: view.topAnchor),
            cardStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        cardStack.dataSource = coordinator
        cardStack.delegate = coordinator
    }
    
    func updateItems(_ items: [PhotoItem]) {
        cardStack.reloadData()
    }
    
    func undoLastSwipe() {
        cardStack.undoLastSwipe(animated: true)
    }
}