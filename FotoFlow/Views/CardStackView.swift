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
    var videoAsset: PHAsset?
    var onTap: (() -> Void)?
    
    init(image: UIImage, isVideo: Bool, asset: PHAsset? = nil) {
        super.init(frame: .zero)
        layer.cornerRadius = 12
        layer.masksToBounds = true
        backgroundColor = .systemBackground
        
        // Only allow left and right swipes
        swipeDirections = [.left, .right]
        
        if isVideo {
            self.videoAsset = asset
        }
        
        // Set up overlays for swipe feedback
        setupOverlays()
        
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
    
    override func didTap(_ recognizer: UITapGestureRecognizer) {
        super.didTap(recognizer)
        if videoAsset != nil {
            onTap?()
        }
    }
    
    private func setupOverlays() {
        // Left swipe overlay (Delete - Red)
        let leftOverlay = createOverlayView(
            color: UIColor.systemRed.withAlphaComponent(0.8),
            icon: "trash.fill",
            iconColor: .white
        )
        
        // Right swipe overlay (Keep - Green)
        let rightOverlay = createOverlayView(
            color: UIColor.systemGreen.withAlphaComponent(0.8),
            icon: "checkmark.circle.fill",
            iconColor: .white
        )
        
        // Set the overlays using Shuffle's built-in method
        setOverlay(leftOverlay, forDirection: .left)
        setOverlay(rightOverlay, forDirection: .right)
    }
    
    private func createOverlayView(color: UIColor, icon: String, iconColor: UIColor) -> UIView {
        let overlayView = UIView()
        overlayView.backgroundColor = color
        overlayView.layer.cornerRadius = 12
        
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(systemName: icon)
        iconImageView.tintColor = iconColor
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        overlayView.addSubview(iconImageView)
        
        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 100),
            iconImageView.heightAnchor.constraint(equalToConstant: 100)
        ])
        
        return overlayView
    }
}

// MARK: - SwiftUI Bridge

struct CardStackView: UIViewControllerRepresentable {
    let items: [PhotoItem]
    let onLeftSwipe: (Int, PhotoItem) -> Void
    let onRightSwipe: (Int, PhotoItem) -> Void
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
        weak var viewController: UIViewController?
        
        init(_ parent: CardStackView) {
            self.parent = parent
        }
        
        func cardStack(_ cardStack: SwipeCardStack, cardForIndexAt index: Int) -> SwipeCard {
            let item = parent.items[index]
            let isVideo = item.asset.mediaType == .video
            let card = PhotoSwipeCard(image: item.image, isVideo: isVideo, asset: isVideo ? item.asset : nil)
            
            if isVideo {
                card.onTap = { [weak self] in
                    self?.playVideo(asset: item.asset)
                }
            }
            
            return card
        }
        
        private func playVideo(asset: PHAsset) {
            guard let viewController = viewController else { return }
            
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
                guard let playerItem = playerItem else { return }
                
                DispatchQueue.main.async {
                    let player = AVPlayer(playerItem: playerItem)
                    let playerViewController = AVPlayerViewController()
                    playerViewController.player = player
                    
                    viewController.present(playerViewController, animated: true) {
                        player.play()
                    }
                }
            }
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
    private var lastItemCount: Int = 0
    private var hasInitialized = false
    
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
        coordinator?.viewController = self
    }
    
    func updateItems(_ items: [PhotoItem]) {
        // Only reload if this is the first load or if items were added (not removed by swipe)
        if !hasInitialized || items.count > lastItemCount {
            cardStack.reloadData()
            hasInitialized = true
        }
        lastItemCount = items.count
    }
    
    func undoLastSwipe() {
        cardStack.undoLastSwipe(animated: true)
    }
}
