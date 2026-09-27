//
//  ModelHubView.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import SwiftUI
import Combine

public struct ModelHubView: View {
    @ObservedObject var downloadService = ModelDownloadService.shared
    @ObservedObject var imageModelService = LocalImageModelService.shared

    @State private var selectedTab: HubTab = .text
    @State private var modelToDelete: (isText: Bool, id: String, name: String)? = nil
    @State private var showDeleteConfirmation = false

    public enum HubTab: String, CaseIterable {
        case text = "Text (LLMs)"
        case image = "Image Models"
    }

    public init() {}

    public var body: some View {
        ZStack {
            AppTheme.backgroundDark.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    headerBar

                    // Custom Segmented Selector
                    categorySelector

                    // Error Banner if any
                    if let error = downloadService.downloadError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppTheme.roseAccent)
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.roseAccent)
                            Spacer()
                            Button("Dismiss") {
                                downloadService.downloadError = nil
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        }
                        .padding(14)
                        .tactileCard(cornerRadius: 16, strokeColor: AppTheme.roseAccent.opacity(0.4))
                    }

                    // Model Cards List
                    if selectedTab == .text {
                        textModelsSection
                    } else {
                        imageModelsSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
        }
        .onAppear {
            downloadService.refreshDownloadedStates()
        }
        .confirmationDialog(
            "Delete Model Weights",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(modelToDelete?.name ?? "Model")", role: .destructive) {
                if let target = modelToDelete {
                    if target.isText, let model = ModelCatalogue.textModels.first(where: { $0.id == target.id }) {
                        downloadService.deleteTextModel(model)
                    } else if !target.isText, let model = ModelCatalogue.imageModels.first(where: { $0.id == target.id }) {
                        imageModelService.deleteModel(model)
                    }
                    AppTheme.hapticNotification(.warning)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the offline model weights from your device storage to free up space. You can re-download anytime.")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("TrulyOpen")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Hub")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.mintAccent)
                }
                Text("Manage weights & offline storage")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(.top, 12)
    }

    // MARK: - Category Selector

    private var categorySelector: some View {
        HStack(spacing: 6) {
            ForEach(HubTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                    AppTheme.hapticImpact(.light)
                }) {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium, design: .rounded))
                        .foregroundColor(selectedTab == tab ? Color(red: 14/255, green: 16/255, blue: 19/255) : .white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            ZStack {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(AppTheme.mintAccent)
                                        .shadow(color: AppTheme.mintAccent.opacity(0.3), radius: 8, x: 0, y: 3)
                                }
                            }
                        )
                }
            }
        }
        .padding(5)
        .background(AppTheme.cardDark)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Text Models

    private var textModelsSection: some View {
        VStack(spacing: 14) {
            ForEach(ModelCatalogue.textModels) { model in
                let isDownloaded = downloadService.isDownloaded(llmId: model.id)
                let isDownloading = downloadService.downloadingModelId == model.id

                ModelCardView(
                    title: model.name,
                    subtitle: model.description,
                    size: model.sizeDisplay,
                    parameterCount: model.parameterCount,
                    isRecommended: model.isRecommended,
                    isDownloaded: isDownloaded,
                    isDownloading: isDownloading,
                    downloadProgress: downloadService.downloadProgress,
                    speedText: downloadService.downloadSpeedString,
                    onDownload: { downloadService.downloadTextModel(model) },
                    onCancel: { downloadService.cancelDownload() },
                    onDelete: {
                        modelToDelete = (isText: true, id: model.id, name: model.name)
                        showDeleteConfirmation = true
                    }
                )
            }
        }
    }

    // MARK: - Image Models

    private var imageModelsSection: some View {
        VStack(spacing: 14) {
            ForEach(ModelCatalogue.imageModels) { model in
                let isDownloaded = imageModelService.isModelDownloaded(model)
                let isDownloading = imageModelService.downloadingModelId == model.id

                ModelCardView(
                    title: model.displayName,
                    subtitle: model.description,
                    size: model.sizeDisplay,
                    parameterCount: "860M",
                    isRecommended: model.isRecommended,
                    isDownloaded: isDownloaded,
                    isDownloading: isDownloading,
                    downloadProgress: imageModelService.downloadProgress,
                    speedText: imageModelService.downloadSpeedString,
                    onDownload: { imageModelService.startDownload(model: model) },
                    onCancel: { imageModelService.cancelDownload(model: model) },
                    onDelete: {
                        modelToDelete = (isText: false, id: model.id, name: model.displayName)
                        showDeleteConfirmation = true
                    }
                )
            }
        }
    }
}
