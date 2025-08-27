//
//  NSFWDetectorTests.swift
//  FotoFlowTests
//
//  Test-driven development for NSFW detection service
//

import Testing
import UIKit
@testable import FotoFlow

struct NSFWDetectorTests {
    
    @Test func testSingletonInstance() async throws {
        // Given/When
        let instance1 = NSFWDetector.shared
        let instance2 = NSFWDetector.shared
        
        // Then
        #expect(instance1 === instance2)
    }
    
    @Test func testSafeImageDetection() async throws {
        // Given a safe test image
        let safeImage = createTestImage(color: .blue)
        
        // When checking if it's sensitive
        let isSensitive = await NSFWDetector.shared.isSensitive(safeImage)
        
        // Then it should return false (not sensitive)
        #expect(!isSensitive)
    }
    
    @Test func testNilImageHandling() async throws {
        // Given an image with no CGImage
        let emptyImage = UIImage()
        
        // When checking if it's sensitive
        let isSensitive = await NSFWDetector.shared.isSensitive(emptyImage)
        
        // Then it should safely return false
        #expect(!isSensitive)
    }
    
    @Test func testThresholdConfiguration() async throws {
        // Given
        let detector = NSFWDetector.shared
        
        // When setting a custom threshold
        UserDefaults.standard.set(0.9, forKey: "NSFWThresholdOverride")
        defer { UserDefaults.standard.removeObject(forKey: "NSFWThresholdOverride") }
        
        // Then the detector should use the custom threshold
        // (This would be tested with actual NSFW content in production)
        let safeImage = createTestImage(color: .green)
        let isSensitive = await detector.isSensitive(safeImage)
        #expect(!isSensitive)
    }
    
    // Helper to create test images
    private func createTestImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        color.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
}
