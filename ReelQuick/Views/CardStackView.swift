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

// MARK: - BezelFramedImageView

private final class BezelFramedImageView: UIView {
    private let imageView = UIImageView()
    private let hairline = CAShapeLayer()
    private let bezelMask = CAShapeLayer()
    private let bezelGradient = CAGradientLayer()
    
    var corner: CGFloat = 16 { didSet { setNeedsLayout() } }
    var bezelWidth: CGFloat = 3.0 { didSet { setNeedsLayout() } }
    
    init(image: UIImage) {
        super.init(frame: .zero)
        clipsToBounds = true
        layer.cornerRadius = corner
        
        imageView.image = image
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        
        // Gradient bezel (diagonal for subtle dimensionality)
        bezelGradient.startPoint = CGPoint(x: 0.0, y: 0.0)
        bezelGradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        bezelMask.fillColor = UIColor.clear.cgColor
        bezelMask.lineJoin = .round
        bezelMask.lineCap = .round
        bezelGradient.mask = bezelMask
        layer.addSublayer(bezelGradient)
        
        // Hairline on the very edge (inside the clipping)
        hairline.fillColor = UIColor.clear.cgColor
        hairline.lineWidth = 1.0 / UIScreen.main.scale
        layer.addSublayer(hairline)
        
        applyAesthetics()
    }
    
    required init?(coder: NSCoder) { nil }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        bezelGradient.frame = bounds
        
        // Bail out safely on zero/invalid geometry
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else {
            hairline.path = nil
            bezelMask.path = nil
            return
        }
        
        // Hairline (outer)
        let corner = max(self.corner, 0)
        let hairlinePath = UIBezierPath(roundedRect: bounds, cornerRadius: corner)
        hairline.path = hairlinePath.cgPath
        if bounds.width > 32, bounds.height > 32 {
            hairline.strokeColor = UIColor.separator.withAlphaComponent(0.35).cgColor
            hairline.isHidden = false
        } else {
            hairline.path = nil
            hairline.isHidden = true
        }
        
        // Bezel ring (just inside the hairline)
        let inset = hairline.lineWidth + bezelWidth / 2
        let bezelRectW = max(bounds.width - inset * 2, 0)
        let bezelRectH = max(bounds.height - inset * 2, 0)
        if bezelRectW > 0, bezelRectH > 0 {
            let bezelRect = bounds.insetBy(dx: inset, dy: inset)
            let bezelCorner = max(min(corner - inset, min(bezelRectW, bezelRectH) / 2), 0)
            bezelMask.lineWidth = min(bezelWidth, min(bezelRectW, bezelRectH))
            let bezelPath = UIBezierPath(roundedRect: bezelRect, cornerRadius: bezelCorner)
            bezelMask.path = bezelPath.cgPath
            bezelGradient.isHidden = false
        } else {
            bezelMask.path = nil
            bezelGradient.isHidden = true
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            applyAesthetics()
        }
    }
    
    private func applyAesthetics() {
        if traitCollection.userInterfaceStyle == .dark {
            hairline.strokeColor = UIColor.white.withAlphaComponent(0.12).cgColor
            bezelGradient.colors = [UIColor.white.withAlphaComponent(0.10).cgColor,
                                    UIColor.white.withAlphaComponent(0.02).cgColor]
        } else {
            hairline.strokeColor = UIColor.black.withAlphaComponent(0.10).cgColor
            bezelGradient.colors = [UIColor.black.withAlphaComponent(0.06).cgColor,
                                    UIColor.black.withAlphaComponent(0.01).cgColor]
        }
    }
}

// MARK: - Photo Card View

private final class PhotoSwipeCard: SwipeCard {
    var videoAsset: PHAsset?
    var onTap: (() -> Void)?
    
    init(image: UIImage, isVideo: Bool, asset: PHAsset? = nil) {
        super.init(frame: .zero)
        layer.cornerRadius = 16
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
        
        // Use the BezelFramedImageView for better border shading
        let framedImageView = BezelFramedImageView(image: image)
        framedImageView.frame = container.bounds
        framedImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(framedImageView)
        
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
        // Left swipe overlay (Archive - Darker red)
        let leftOverlay = createOverlayView(
            text: "Archive",
            icon: "trash.fill",
            color: UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 0.7)
        )
        
        // Right swipe overlay (Keep - Darker green)
        let rightOverlay = createOverlayView(
            text: "Keep",
            icon: "hand.thumbsup.fill",
            color: UIColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 0.7)
        )
        
        // Set the overlays using Shuffle's built-in method
        setOverlay(leftOverlay, forDirection: .left)
        setOverlay(rightOverlay, forDirection: .right)
    }
    
    private func createOverlayView(text: String, icon: String, color: UIColor) -> UIView {
        // Container view
        let container = UIView()
        container.isUserInteractionEnabled = false
        
        // Blur effect background
        let blurEffect = UIBlurEffect(style: .systemThinMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 16
        blurView.clipsToBounds = true
        blurView.backgroundColor = color
        
        container.addSubview(blurView)
        
        // Icon
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(systemName: icon)
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Text label
        let label = UILabel()
        label.text = text
        label.font = .boldSystemFont(ofSize: 24)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // Stack view for icon and text
        let stackView = UIStackView(arrangedSubviews: [iconImageView, label])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        blurView.contentView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            // Blur view fills container
            blurView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: container.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            // Stack view centered
            stackView.centerXAnchor.constraint(equalTo: blurView.contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: blurView.contentView.centerYAnchor),
            
            // Icon size
            iconImageView.widthAnchor.constraint(equalToConstant: 60),
            iconImageView.heightAnchor.constraint(equalToConstant: 60)
        ])
        
        return container
    }
}

// MARK: - SwiftUI Bridge

struct CardStackView: UIViewControllerRepresentable {
    let items: [PhotoItem]
    let onLeftSwipe: (Int, PhotoItem) -> Void
    let onRightSwipe: (Int, PhotoItem) -> Void
    @Binding var undoTrigger: Bool
    @Binding var swipeRightTrigger: Bool
    
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
        
        if swipeRightTrigger {
            uiViewController.swipeRight()
            DispatchQueue.main.async {
                swipeRightTrigger = false
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
        
        // Adjust card size to better see images
        let screenWidth = UIScreen.main.bounds.width
        let cardWidth = screenWidth * 0.85 // Cards will be 85% of screen width
        let horizontalInset = (screenWidth - cardWidth) / 2
        
        let cardInsets = UIEdgeInsets(
            top: 0,
            left: horizontalInset,
            bottom: 0,  // No bottom inset to use full available height
            right: horizontalInset
        )
        cardStack.cardStackInsets = cardInsets
        
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
    
    func swipeRight() {
        cardStack.swipe(.right, animated: true)
    }
    
    func swipeLeft() {
        cardStack.swipe(.left, animated: true)
    }
}
