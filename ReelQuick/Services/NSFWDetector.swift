//
//  NSFWDetector.swift
//  FotoFlow
//
//  CoreML-based NSFW content detection service
//

import Foundation
import UIKit
import CoreML
import Vision

final class NSFWDetector {
    
    static let shared = NSFWDetector()
    
    private let logEnabled = true
    private var vnModel: VNCoreMLModel?
    private var didWarnMissingModel = false
    
    private var nsfwThreshold: Double {
        let override = UserDefaults.standard.double(forKey: "NSFWThresholdOverride")
        return override > 0 ? override : 0.8
    }
    
    private init() {}
    
    func isSensitive(_ uiImage: UIImage) async -> Bool {
        guard let cgImage = uiImage.cgImage else { return false }
        
        guard let model = try? loadModelIfNeeded() else {
            if !didWarnMissingModel {
                didWarnMissingModel = true
                if logEnabled {
                    print("⚠️ [NSFWDetector] Model not found. All detections will be SFW.")
                }
            }
            return false
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        var nsfwProbability: Double = 0.0
        var topClass: String = ""
        
        let request = VNCoreMLRequest(model: model) { request, _ in
            if let observations = request.results as? [VNClassificationObservation], !observations.isEmpty {
                let (prob, top) = self.extractNSFWProbability(from: observations)
                nsfwProbability = prob
                topClass = top
            } else if let features = request.results as? [VNCoreMLFeatureValueObservation],
                      let firstFeature = features.first?.featureValue.multiArrayValue {
                nsfwProbability = self.extractProbabilityFromMultiArray(firstFeature)
            }
        }
        request.imageCropAndScaleOption = .scaleFit
        
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    nsfwProbability = 0.0
                }
                continuation.resume()
            }
        }
        
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        let isNSFW = nsfwProbability >= nsfwThreshold
        
        if logEnabled {
            print("[NSFWDetector] class=\(topClass) prob=\(String(format: "%.3f", nsfwProbability)) threshold=\(nsfwThreshold) time=\(elapsedMs)ms result=\(isNSFW ? "NSFW" : "SFW")")
        }
        
        return isNSFW
    }
    
    private func loadModelIfNeeded() throws -> VNCoreMLModel {
        if let model = vnModel { return model }
        
        let modelNames = ["NSFWLite", "OpenNSFW2", "NSFWDetector"]
        
        for name in modelNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodel") ??
                        Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                do {
                    let mlModel = try MLModel(contentsOf: url)
                    let vnModel = try VNCoreMLModel(for: mlModel)
                    self.vnModel = vnModel
                    if logEnabled {
                        print("[NSFWDetector] Loaded model: \(name)")
                    }
                    return vnModel
                } catch {
                    if logEnabled {
                        print("[NSFWDetector] Failed to load \(name): \(error)")
                    }
                }
            }
        }
        
        throw NSError(domain: "NSFWDetector", code: 1, userInfo: [NSLocalizedDescriptionKey: "No model found"])
    }
    
    private func extractNSFWProbability(from observations: [VNClassificationObservation]) -> (Double, String) {
        var nsfwProb = 0.0
        var topClass = ""
        
        for obs in observations {
            let label = obs.identifier.lowercased()
            if label.contains("nsfw") || label.contains("porn") || label.contains("explicit") {
                nsfwProb = max(nsfwProb, Double(obs.confidence))
            }
            if topClass.isEmpty {
                topClass = obs.identifier
            }
        }
        
        return (nsfwProb, topClass)
    }
    
    private func extractProbabilityFromMultiArray(_ multiArray: MLMultiArray) -> Double {
        guard multiArray.count == 2 else { return 0.0 }
        return multiArray[1].doubleValue
    }
}