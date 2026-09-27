//
//  LocalImageGeneratorService.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import Foundation
import UIKit
import CoreML
import Combine
import SwiftUI
import Darwin

#if canImport(StableDiffusion)
import StableDiffusion
#endif

@MainActor
public final class LocalImageGeneratorService: ObservableObject {
    public static let shared = LocalImageGeneratorService()

    // MARK: - Published State

    @Published public var isGenerating: Bool = false
    @Published public var generationProgress: Double = 0.0
    @Published public var currentStep: Int = 0
    @Published public var totalSteps: Int = 0
    @Published public var generationError: String? = nil
    @Published public var currentStageMessage: String = ""

    // MARK: - Private

    private var pipeline: Any? = nil // StableDiffusionPipeline type-erased
    private var loadedModelId: String? = nil
    private var currentTask: Task<Void, Never>? = nil

    private init() {}

    // MARK: - Public API

    public func generate(
        config: ImageGenerationConfig,
        model: ImageModelInfo
    ) async throws -> GeneratedImageItem {
        guard !isGenerating else {
            throw NSError(
                domain: "LocalImageGeneratorService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "An image generation is already in progress."]
            )
        }

        #if canImport(StableDiffusion)
        return try await executeGeneration(config: config, model: model)
        #else
        throw NSError(
            domain: "LocalImageGeneratorService",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "StableDiffusion CoreML framework is not linked in this build."]
        )
        #endif
    }

    public func cancelGeneration() {
        currentTask?.cancel()
        currentTask = nil
        isGenerating = false
        generationProgress = 0.0
        currentStep = 0
        currentStageMessage = ""
    }

    // MARK: - Internal Pipeline Execution

    #if canImport(StableDiffusion)
    private func executeGeneration(
        config: ImageGenerationConfig,
        model: ImageModelInfo
    ) async throws -> GeneratedImageItem {
        isGenerating = true
        generationProgress = 0.0
        currentStep = 0
        totalSteps = config.steps
        generationError = nil
        currentStageMessage = "Initializing Neural Pipeline…"

        let startTime = Date()

        defer {
            isGenerating = false
            currentStageMessage = ""
        }

        // 1. Prepare pipeline if needed
        if loadedModelId != model.id || pipeline == nil {
            currentStageMessage = "Loading CoreML model into Neural Engine…"
            guard let resourcesURL = LocalImageModelService.shared.modelResourcesURL(for: model) else {
                throw NSError(
                    domain: "LocalImageGeneratorService",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Model files not found. Please download the model first."]
                )
            }

            let mlConfig = MLModelConfiguration()

            #if targetEnvironment(simulator)
            mlConfig.computeUnits = .cpuAndNeuralEngine
            #else
            // cpuOnly on iPhone 11 (A13) and 4GB RAM devices to avoid ANE compiler buffer exceeding 2098MB limit
            let hw = HardwareModel.current
            if hw.isIPhone && hw.iPhoneMajorVersion <= 13 {
                mlConfig.computeUnits = .cpuOnly
            } else {
                mlConfig.computeUnits = .cpuOnly
            }
            #endif

            let sdPipeline = try await Task.detached(priority: .userInitiated) {
                return try StableDiffusionPipeline(
                    resourcesAt: resourcesURL,
                    controlNet: [],
                    configuration: mlConfig,
                    disableSafety: true, // Saves ~600MB RAM
                    reduceMemory: true   // Memory optimized component paging
                )
            }.value

            self.pipeline = sdPipeline
            self.loadedModelId = model.id
        }

        guard let sdPipeline = self.pipeline as? StableDiffusionPipeline else {
            throw NSError(
                domain: "LocalImageGeneratorService",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Could not initialize Stable Diffusion pipeline."]
            )
        }

        // 2. Configure Generation Parameters
        currentStageMessage = "Generating latent representations…"
        var pipelineConfig = PipelineConfiguration(prompt: config.prompt)
        pipelineConfig.negativePrompt = config.negativePrompt
        pipelineConfig.stepCount = config.steps
        pipelineConfig.guidanceScale = config.guidanceScale
        pipelineConfig.seed = config.seed
        pipelineConfig.schedulerType = .dpmSolverMultistepScheduler
        pipelineConfig.disableSafety = true

        // 3. Run Generation Loop
        let cgImage = try await Task.detached(priority: .userInitiated) { [weak self] in
            let images = try sdPipeline.generateImages(configuration: pipelineConfig) { progress in
                let stepCount = max(progress.stepCount, 1)
                let frac = Double(progress.step) / Double(stepCount)

                Task { @MainActor [weak self] in
                    self?.generationProgress = frac
                    self?.currentStep = progress.step
                    self?.currentStageMessage = "Denoising step \(progress.step) of \(progress.stepCount)…"
                }

                return !Task.isCancelled
            }
            return images.compactMap { $0 }.first
        }.value

        guard let rawCGImage = cgImage else {
            throw NSError(
                domain: "LocalImageGeneratorService",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Diffusion loop completed but no image was returned."]
            )
        }

        let uiImage = UIImage(cgImage: rawCGImage)
        let elapsed = Date().timeIntervalSince(startTime)

        // 4. Save to Disk
        let imageId = UUID()
        let filename = "\(imageId.uuidString).jpg"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesDir = docs.appendingPathComponent("GeneratedImages", isDirectory: true)
        let fileURL = imagesDir.appendingPathComponent(filename)

        if let jpegData = uiImage.jpegData(compressionQuality: 0.9) {
            try jpegData.write(to: fileURL)
        }

        let item = GeneratedImageItem(
            id: imageId,
            filename: filename,
            prompt: config.prompt,
            negativePrompt: config.negativePrompt,
            steps: config.steps,
            guidanceScale: config.guidanceScale,
            seed: config.seed,
            createdAt: Date(),
            generationDuration: elapsed,
            modelName: model.displayName
        )

        return item
    }
    #endif
}

// MARK: - Device chip detection

private struct HardwareModel {
    let raw: String

    static var current: HardwareModel {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return HardwareModel(raw: machine)
    }

    var isIPhone: Bool { raw.hasPrefix("iPhone") }

    /// The model number after "iPhone" — e.g. "iPhone12,1" (iPhone 11) → 12
    var iPhoneMajorVersion: Int {
        guard raw.hasPrefix("iPhone") else { return 0 }
        let rest = raw.dropFirst("iPhone".count)
        guard let major = rest.split(separator: ",").first.flatMap({ Int($0) }) else { return 0 }
        return major
    }
}
