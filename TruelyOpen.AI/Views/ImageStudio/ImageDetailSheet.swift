//
//  ImageDetailSheet.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import SwiftUI
import Combine
import UIKit

public struct ImageDetailSheet: View {
    public let item: GeneratedImageItem
    public let onUsePrompt: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showSavedAlert = false

    public init(item: GeneratedImageItem, onUsePrompt: @escaping (String) -> Void = { _ in }) {
        self.item = item
        self.onUsePrompt = onUsePrompt
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundDark.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Image Display
                        if let uiImage = item.uiImage {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(AppTheme.borderSubtle, lineWidth: 1)
                                )
                                .shadow(color: AppTheme.purpleAccent.opacity(0.15), radius: 20, x: 0, y: 10)
                        } else {
                            Rectangle()
                                .fill(AppTheme.cardDark)
                                .aspectRatio(1, contentMode: .fit)
                                .cornerRadius(20)
                                .overlay(
                                    Text("Image file unavailable")
                                        .foregroundColor(.gray)
                                )
                        }

                        // Actions Row
                        HStack(spacing: 14) {
                            Button(action: saveToPhotos) {
                                Label("Save to Photos", systemImage: "square.and.arrow.down")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 14/255, green: 16/255, blue: 19/255))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(AppTheme.mintAccent)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .shadow(color: AppTheme.mintAccent.opacity(0.25), radius: 8, x: 0, y: 4)
                            }

                            if let uiImage = item.uiImage {
                                ShareLink(
                                    item: Image(uiImage: uiImage),
                                    preview: SharePreview(item.prompt, image: Image(uiImage: uiImage))
                                ) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 50, height: 50)
                                        .background(AppTheme.cardDark)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                }
                            }
                        }

                        // Metadata Card
                        VStack(alignment: .leading, spacing: 14) {
                            Text("GENERATION DETAILS")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.4))
                                .tracking(1)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Prompt")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(AppTheme.mintAccent)
                                Text(item.prompt)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .textSelection(.enabled)
                            }

                            if !item.negativePrompt.isEmpty {
                                Divider().background(Color.white.opacity(0.08))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Negative Prompt")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(AppTheme.roseAccent)
                                    Text(item.negativePrompt)
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.7))
                                        .textSelection(.enabled)
                                }
                            }

                            Divider().background(Color.white.opacity(0.08))

                            // Parameters Grid
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                paramCell(title: "Model", value: item.modelName)
                                paramCell(title: "Steps", value: "\(item.steps)")
                                paramCell(title: "Guidance Scale", value: String(format: "%.1f", item.guidanceScale))
                                paramCell(title: "Seed", value: "\(item.seed)")
                                paramCell(title: "Duration", value: String(format: "%.1fs", item.generationDuration))
                                paramCell(title: "Engine", value: "Neural Engine")
                            }

                            Button(action: {
                                onUsePrompt(item.prompt)
                                dismiss()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Use This Prompt in Studio")
                                }
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.mintAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(AppTheme.elevatedCardDark)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AppTheme.mintAccent.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .padding(.top, 4)
                        }
                        .padding(18)
                        .tactileCard(cornerRadius: 22)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Generated Artwork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.mintAccent)
                }
            }
            .alert("Saved to Photos", isPresented: $showSavedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your generated artwork has been saved to the device Photo Library.")
            }
        }
    }

    private func paramCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private func saveToPhotos() {
        guard let uiImage = item.uiImage else { return }
        UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
        AppTheme.hapticNotification(.success)
        showSavedAlert = true
    }
}
