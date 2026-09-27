//
//  ImageModels.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import Foundation
import UIKit
import Combine
import SwiftUI

public struct ImageGenerationConfig: Codable, Equatable {
    public var prompt: String
    public var negativePrompt: String
    public var steps: Int
    public var guidanceScale: Float
    public var seed: UInt32
    public var modelId: String

    public init(
        prompt: String = "",
        negativePrompt: String = "low quality, blurry, distorted, bad anatomy, worst quality, artifacts",
        steps: Int = 20,
        guidanceScale: Float = 7.5,
        seed: UInt32 = UInt32.random(in: 0...UInt32.max),
        modelId: String = "sd15-palettized"
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.seed = seed
        self.modelId = modelId
    }
}

public struct GeneratedImageItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public let filename: String
    public let prompt: String
    public let negativePrompt: String
    public let steps: Int
    public let guidanceScale: Float
    public let seed: UInt32
    public let createdAt: Date
    public let generationDuration: TimeInterval
    public let modelName: String

    public init(
        id: UUID = UUID(),
        filename: String,
        prompt: String,
        negativePrompt: String,
        steps: Int,
        guidanceScale: Float,
        seed: UInt32,
        createdAt: Date = Date(),
        generationDuration: TimeInterval,
        modelName: String
    ) {
        self.id = id
        self.filename = filename
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.seed = seed
        self.createdAt = createdAt
        self.generationDuration = generationDuration
        self.modelName = modelName
    }

    public var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesDir = documents.appendingPathComponent("GeneratedImages", isDirectory: true)
        return imagesDir.appendingPathComponent(filename)
    }

    public var uiImage: UIImage? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return UIImage(contentsOfFile: fileURL.path)
    }
}
