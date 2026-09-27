//
//  ImageStudioView.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import SwiftUI
import Combine
import UIKit

public struct ImageStudioView: View {
    @ObservedObject var imageService = LocalImageGeneratorService.shared
    @ObservedObject var imageModelService = LocalImageModelService.shared

    @State private var config = ImageGenerationConfig()
    @State private var showAdvancedSettings = false
    @State private var galleryItems: [GeneratedImageItem] = []
    @State private var selectedDetailItem: GeneratedImageItem?
    @State private var errorMessage: String?
    @State private var selectedPresetId: String? = nil

    private let imageModel = ModelCatalogue.imageModels[0] // Stable Diffusion 1.5

    private struct StylePreset: Identifiable {
        let id: String
        let name: String
        let suffix: String
        let color: Color
    }

    private let stylePresets: [StylePreset] = [
        StylePreset(id: "cinematic", name: "Cinematic", suffix: ", cinematic lighting, 8k resolution, photorealistic, octane render, dramatic atmosphere", color: AppTheme.pastelBlue),
        StylePreset(id: "anime", name: "Anime", suffix: ", vibrant anime style, studio ghibli aesthetic, detailed line art, colorful", color: AppTheme.pastelPink),
        StylePreset(id: "cyberpunk", name: "Cyberpunk", suffix: ", cyberpunk neon aesthetic, glowing holograms, futuristic city, night rain", color: AppTheme.pastelPurple),
        StylePreset(id: "photoreal", name: "Photoreal", suffix: ", high detailed photography, 35mm lens, f/1.8, natural lighting, ultra realistic", color: AppTheme.pastelCream),
        StylePreset(id: "fantasy", name: "Fantasy", suffix: ", epic digital fantasy painting, magical aura, hyper-detailed, artstation trending", color: AppTheme.mintAccent),
        StylePreset(id: "minimal", name: "Minimal", suffix: ", clean minimalist graphic art, vector style, elegant composition, muted colors", color: AppTheme.mintSoft)
    ]

    public init() {}

    private var isModelReady: Bool {
        imageModelService.isModelDownloaded(imageModel)
    }

    public var body: some View {
        ZStack {
            AppTheme.backgroundDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    headerBar

                    if !isModelReady {
                        modelDownloadBanner
                    }

                    // Generation Studio Card
                    studioControlsCard

                    // Live Generation Progress Indicator
                    if imageService.isGenerating {
                        generationProgressCard
                    }

                    // Gallery Section
                    gallerySection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
        }
        .sheet(item: $selectedDetailItem) { item in
            ImageDetailSheet(item: item) { reusedPrompt in
                config.prompt = reusedPrompt
            }
        }
        .onAppear {
            imageModelService.objectWillChange.send()
            loadGalleryFromDisk()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("TrulyOpen")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Studio")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.mintAccent)
                }
                Text("CoreML Stable Diffusion • Neural Engine")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()

            // Status Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(isModelReady ? AppTheme.mintAccent : Color.orange)
                    .frame(width: 8, height: 8)
                Text(isModelReady ? "SD 1.5 Ready" : "Setup Needed")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(isModelReady ? AppTheme.mintAccent : .orange)
            }
            .tactilePill()
        }
        .padding(.top, 12)
    }

    // MARK: - Model Download Banner

    private var modelDownloadBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.mintAccent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.mintAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("CoreML Diffusion Model Required")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Stable Diffusion 1.5 Palettized (\(imageModel.sizeDisplay))")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
            }

            Text("Download Apple's official CoreML compiled model to generate stunning images directly on your device without an internet connection.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .lineSpacing(2)

            if imageModelService.downloadingModelId == imageModel.id {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(imageModelService.downloadSpeedString.isEmpty ? (imageModelService.isUnzipping ? "Extracting CoreML weights…" : "Downloading...") : imageModelService.downloadSpeedString)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(AppTheme.mintAccent)
                        Spacer()
                        Text("\(Int(imageModelService.downloadProgress * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    ProgressView(value: imageModelService.downloadProgress)
                        .tint(AppTheme.mintAccent)

                    Button("Cancel Download", role: .cancel) {
                        imageModelService.cancelDownload(model: imageModel)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.roseAccent)
                    .padding(.top, 4)
                }
            } else {
                Button(action: { imageModelService.startDownload(model: imageModel) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download Model (\(imageModel.sizeDisplay))")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 14/255, green: 16/255, blue: 19/255))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.mintAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(18)
        .tactileCard(cornerRadius: 24)
    }

    // MARK: - Studio Controls Card

    private var studioControlsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header Row
            HStack {
                Text("PROMPT")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(1)
                Spacer()
                Button(action: surpriseMe) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                        Text("Surprise Me")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.mintAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(AppTheme.elevatedCardDark)
                            .overlay(Capsule().stroke(AppTheme.mintAccent.opacity(0.25), lineWidth: 0.8))
                    )
                }
            }

            // Prompt Editor
            ZStack(alignment: .topLeading) {
                if config.prompt.isEmpty {
                    Text("Describe whatever you want to see...")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.top, 12)
                        .padding(.leading, 14)
                }

                TextEditor(text: $config.prompt)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 88)
                    .padding(10)
            }
            .background(AppTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            // Reference-inspired "CHOOSE A PRESET :"
            VStack(alignment: .leading, spacing: 10) {
                Text("CHOOSE A PRESET :")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(stylePresets) { preset in
                            Button(action: {
                                selectedPresetId = preset.id
                                applyStylePreset(preset.suffix)
                            }) {
                                HStack(spacing: 7) {
                                    // Circular color indicator
                                    ZStack {
                                        Circle()
                                            .fill(preset.color)
                                            .frame(width: 14, height: 14)
                                        if selectedPresetId == preset.id {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.black)
                                        }
                                    }

                                    Text(preset.name)
                                        .font(.system(size: 12, weight: selectedPresetId == preset.id ? .bold : .medium))
                                        .foregroundColor(selectedPresetId == preset.id ? .white : .white.opacity(0.75))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(selectedPresetId == preset.id ? AppTheme.elevatedCardDark : AppTheme.surfaceDark)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(
                                            selectedPresetId == preset.id ? AppTheme.mintAccent.opacity(0.5) : Color.white.opacity(0.06),
                                            lineWidth: 1
                                        )
                                )
                            }
                        }
                    }
                }
            }

            // Advanced Settings Accordion
            DisclosureGroup(isExpanded: $showAdvancedSettings) {
                VStack(alignment: .leading, spacing: 14) {
                    Divider().background(Color.white.opacity(0.06))

                    // Negative Prompt
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Negative Prompt")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))

                        TextField("What to avoid in image...", text: $config.negativePrompt)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(AppTheme.surfaceDark)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                    }

                    // Steps Slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Denoising Steps")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text("\(config.steps)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.mintAccent)
                        }
                        Slider(value: Binding(
                            get: { Double(config.steps) },
                            set: { config.steps = Int($0) }
                        ), in: 10...35, step: 1)
                        .tint(AppTheme.mintAccent)
                    }

                    // Guidance Scale Slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Guidance Scale")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text(String(format: "%.1f", config.guidanceScale))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.mintAccent)
                        }
                        Slider(value: Binding(
                            get: { Double(config.guidanceScale) },
                            set: { config.guidanceScale = Float($0) }
                        ), in: 1.0...15.0, step: 0.5)
                        .tint(AppTheme.mintAccent)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(AppTheme.mintAccent)
                    Text("Advanced Settings")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            // Reference-inspired Hero Action Button: "+ Generate Artwork" (matches "+ Create New Event")
            Button(action: startGeneration) {
                HStack(spacing: 8) {
                    if imageService.isGenerating {
                        ProgressView()
                            .tint(Color(red: 14/255, green: 16/255, blue: 19/255))
                        Text("Synthesizing on Neural Engine...")
                            .font(.system(size: 15, weight: .bold))
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                        Text("Generate Artwork")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundColor(canGenerate ? Color(red: 14/255, green: 16/255, blue: 19/255) : Color.white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    canGenerate ? AppTheme.mintAccent : AppTheme.cardDark
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(canGenerate ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: canGenerate ? AppTheme.mintAccent.opacity(0.3) : Color.clear, radius: 12, x: 0, y: 5)
            }
            .disabled(!canGenerate)

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.roseAccent)
            }
        }
        .padding(18)
        .tactileCard(cornerRadius: 24)
    }

    private var canGenerate: Bool {
        !config.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isModelReady &&
        !imageService.isGenerating
    }

    // MARK: - Generation Progress Card

    private var generationProgressCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(imageService.currentStageMessage.isEmpty ? "Generating on Apple Neural Engine…" : imageService.currentStageMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Text(imageService.totalSteps > 0 ? "Step \(imageService.currentStep) of \(imageService.totalSteps) (\(Int(imageService.generationProgress * 100))%)" : "Preparing CoreML pipeline...")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppTheme.mintAccent)
                }
                Spacer()

                Button(action: { imageService.cancelGeneration() }) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.roseAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(AppTheme.roseAccent.opacity(0.15)))
                }
            }

            ProgressView(value: imageService.generationProgress)
                .tint(AppTheme.mintAccent)
        }
        .padding(16)
        .tactileCard(cornerRadius: 20)
    }

    // MARK: - Gallery Section

    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("RECENT CREATIONS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(1)
                Spacer()
                Text("\(galleryItems.count) artworks")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            if galleryItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32))
                        .foregroundColor(AppTheme.mintAccent.opacity(0.5))
                    Text("No creations yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    Text("Your generated masterpieces will appear here.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .tactileCard(cornerRadius: 22)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(galleryItems) { item in
                        Button(action: { selectedDetailItem = item }) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let uiImage = item.uiImage {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(minWidth: 0, maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                } else {
                                    Rectangle()
                                        .fill(AppTheme.cardDark)
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }

                                Text(item.prompt)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 4)
                            }
                            .padding(8)
                            .tactileCard(cornerRadius: 22)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers & Actions

    private func applyStylePreset(_ suffix: String) {
        if !config.prompt.contains(suffix) {
            config.prompt += suffix
        }
        AppTheme.hapticImpact(.light)
    }

    private func surpriseMe() {
        let ideas = [
            "A solitary neon astronaut meditating on an asteroid overlooking Saturn's rings",
            "A cozy Japanese coffee shop on a rainy afternoon, warm ambient interior, watercolor style",
            "An ethereal glass dragon resting on crystalline mountain peaks, glowing bioluminescence",
            "Cyberpunk street market in futuristic Neo-Kyoto with flying lanterns and misty rain",
            "Portrait of an ancient bronze clockwork owl with illuminated sapphire eyes"
        ]
        config.prompt = ideas.randomElement() ?? ideas[0]
        AppTheme.hapticImpact(.light)
    }

    private func startGeneration() {
        errorMessage = nil
        AppTheme.hapticImpact(.medium)

        Task {
            do {
                let item = try await imageService.generate(config: config, model: imageModel)
                await MainActor.run {
                    self.galleryItems.insert(item, at: 0)
                    self.saveGalleryToDisk()
                    AppTheme.hapticNotification(.success)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    AppTheme.hapticNotification(.error)
                }
            }
        }
    }

    private func saveGalleryToDisk() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent("gallery_metadata.json")
        if let data = try? JSONEncoder().encode(galleryItems) {
            try? data.write(to: fileURL)
        }
    }

    private func loadGalleryFromDisk() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent("gallery_metadata.json")
        if let data = try? Data(contentsOf: fileURL),
           let items = try? JSONDecoder().decode([GeneratedImageItem].self, from: data) {
            self.galleryItems = items
        }
    }
}
