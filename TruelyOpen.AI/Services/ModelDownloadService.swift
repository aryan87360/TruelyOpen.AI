//
//  ModelDownloadService.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import Foundation
import Combine
import SwiftUI

#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

@MainActor
public final class ModelDownloadService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = ModelDownloadService()

    // MARK: - Published State

    @Published public var downloadingModelId: String? = nil
    @Published public var downloadProgress: Double = 0.0
    @Published public var downloadSpeedString: String = ""
    @Published public var isExtracting: Bool = false
    @Published public var extractionProgress: Double = 0.0
    @Published public var downloadError: String? = nil

    // Cache of download states
    @Published public var downloadedTextModelIds: Set<String> = []
    @Published public var downloadedImageModelIds: Set<String> = []

    // MARK: - Private State

    private var currentDownloadTask: URLSessionDownloadTask?
    private var downloadStartTime: Date?
    private var bytesReceivedSinceStart: Int64 = 0
    private var lastSpeedCalculationTime: Date?
    private var lastSpeedBytes: Int64 = 0

    private var activeDownloadType: DownloadType?
    private var activeTextModel: LLMModelInfo?
    private var activeImageModel: ImageModelInfo?

    private enum DownloadType {
        case text(LLMModelInfo)
        case image(ImageModelInfo)
    }

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600 * 4 // Allow up to 4 hours for large weights
        return URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }()

    override private init() {
        super.init()
        refreshDownloadedStates()
    }

    // MARK: - State Refresh

    public func refreshDownloadedStates() {
        var textIds = Set<String>()
        for model in ModelCatalogue.textModels {
            if ModelStorageService.shared.isDownloaded(llm: model) {
                textIds.insert(model.id)
            }
        }
        self.downloadedTextModelIds = textIds

        var imgIds = Set<String>()
        for model in ModelCatalogue.imageModels {
            if ModelStorageService.shared.isDownloaded(imageModel: model) {
                imgIds.insert(model.id)
            }
        }
        self.downloadedImageModelIds = imgIds
    }

    public func isDownloaded(llmId: String) -> Bool {
        downloadedTextModelIds.contains(llmId)
    }

    public func isDownloaded(imageId: String) -> Bool {
        downloadedImageModelIds.contains(imageId)
    }

    // MARK: - Download LLM

    public func downloadTextModel(_ model: LLMModelInfo) {
        guard downloadingModelId == nil else {
            downloadError = "Another download is already in progress."
            return
        }

        downloadError = nil
        downloadingModelId = model.id
        downloadProgress = 0.0
        downloadSpeedString = ""
        isExtracting = false
        activeDownloadType = .text(model)
        activeTextModel = model
        downloadStartTime = Date()
        lastSpeedCalculationTime = Date()
        lastSpeedBytes = 0

        let task = urlSession.downloadTask(with: model.downloadURL)
        self.currentDownloadTask = task
        task.resume()
    }

    // MARK: - Download Image Model

    public func downloadImageModel(_ model: ImageModelInfo) {
        guard downloadingModelId == nil else {
            downloadError = "Another download is already in progress."
            return
        }

        guard ModelStorageService.shared.freeDiskSpaceBytes >= model.requiredBytes else {
            downloadError = "Insufficient storage space. Need at least \(model.sizeDisplay) free."
            return
        }

        downloadError = nil
        downloadingModelId = model.id
        downloadProgress = 0.0
        downloadSpeedString = ""
        isExtracting = false
        activeDownloadType = .image(model)
        activeImageModel = model
        downloadStartTime = Date()
        lastSpeedCalculationTime = Date()
        lastSpeedBytes = 0

        let task = urlSession.downloadTask(with: model.downloadURL)
        self.currentDownloadTask = task
        task.resume()
    }

    // MARK: - Cancel / Delete

    public func cancelDownload() {
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        downloadingModelId = nil
        downloadProgress = 0.0
        downloadSpeedString = ""
        isExtracting = false
        activeDownloadType = nil
        activeTextModel = nil
        activeImageModel = nil
    }

    public func deleteTextModel(_ model: LLMModelInfo) {
        do {
            try ModelStorageService.shared.delete(llm: model)
            refreshDownloadedStates()
        } catch {
            downloadError = "Failed to delete: \(error.localizedDescription)"
        }
    }

    public func deleteImageModel(_ model: ImageModelInfo) {
        do {
            try ModelStorageService.shared.delete(imageModel: model)
            refreshDownloadedStates()
        } catch {
            downloadError = "Failed to delete: \(error.localizedDescription)"
        }
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            // If image model, download is 85% of total time, unzipping is 15%
            if case .image = activeDownloadType {
                self.downloadProgress = progress * 0.85
            } else {
                self.downloadProgress = progress
            }
        }

        // Calculate download speed
        let now = Date()
        if let lastTime = lastSpeedCalculationTime, now.timeIntervalSince(lastTime) >= 0.5 {
            let duration = now.timeIntervalSince(lastTime)
            let bytesDelta = totalBytesWritten - lastSpeedBytes
            let speedBytesPerSec = Double(bytesDelta) / duration
            self.downloadSpeedString = String(format: "%.1f MB/s", speedBytesPerSec / (1024 * 1024))
            self.lastSpeedCalculationTime = now
            self.lastSpeedBytes = totalBytesWritten
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let type = activeDownloadType else { return }

        // Validate HTTP response code
        if let httpResponse = downloadTask.response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            self.downloadError = "Download failed: Server returned HTTP \(httpResponse.statusCode)."
            self.cancelDownload()
            return
        }

        switch type {
        case .text(let model):
            handleTextModelDownloadComplete(from: location, model: model)

        case .image(let model):
            handleImageModelDownloadComplete(from: location, model: model)
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            let nsError = error as NSError
            if nsError.code != NSURLErrorCancelled {
                self.downloadError = error.localizedDescription
            }
            self.cancelDownload()
        }
    }

    // MARK: - Complete Handlers

    private func handleTextModelDownloadComplete(from tempURL: URL, model: LLMModelInfo) {
        let destinationURL = ModelStorageService.shared.path(for: model)
        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: tempURL, to: destinationURL)
            self.downloadProgress = 1.0
            self.downloadingModelId = nil
            self.downloadSpeedString = ""
            self.activeDownloadType = nil
            self.refreshDownloadedStates()
        } catch {
            self.downloadError = "Failed to save model: \(error.localizedDescription)"
            self.cancelDownload()
        }
    }

    private func handleImageModelDownloadComplete(from tempURL: URL, model: ImageModelInfo) {
        self.isExtracting = true
        self.downloadSpeedString = "Extracting CoreML archive…"
        let destinationDir = ModelStorageService.shared.storageDir(for: model)
        let baseDir = ModelStorageService.shared.modelBaseDir(for: model)

        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
                let zipDest = baseDir.appendingPathComponent("model.zip")
                if fm.fileExists(atPath: zipDest.path) {
                    try? fm.removeItem(at: zipDest)
                }
                try fm.moveItem(at: tempURL, to: zipDest)

                if fm.fileExists(atPath: destinationDir.path) {
                    try? fm.removeItem(at: destinationDir)
                }
                try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)

                #if canImport(ZIPFoundation)
                guard let archive = Archive(url: zipDest, accessMode: .read) else {
                    throw NSError(domain: "ModelDownloadService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open zip archive"])
                }

                var totalEntries = 0
                for _ in archive { totalEntries += 1 }
                totalEntries = max(totalEntries, 1)

                var extractedCount = 0
                for entry in archive {
                    if Task.isCancelled { throw CancellationError() }
                    let outURL = destinationDir.appendingPathComponent(entry.path)
                    if entry.type == .directory {
                        try fm.createDirectory(at: outURL, withIntermediateDirectories: true)
                    } else {
                        try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        _ = try archive.extract(entry, to: outURL)
                    }
                    extractedCount += 1
                    let progress = 0.85 + (Double(extractedCount) / Double(totalEntries)) * 0.15
                    await MainActor.run {
                        ModelDownloadService.shared.downloadProgress = progress
                        ModelDownloadService.shared.extractionProgress = Double(extractedCount) / Double(totalEntries)
                    }
                }

                // Cleanup zip file to free space
                try? fm.removeItem(at: zipDest)
                #endif

                await MainActor.run {
                    self.downloadProgress = 1.0
                    self.isExtracting = false
                    self.downloadingModelId = nil
                    self.downloadSpeedString = ""
                    self.activeDownloadType = nil
                    self.refreshDownloadedStates()
                }
            } catch {
                await MainActor.run {
                    self.downloadError = "Extraction failed: \(error.localizedDescription)"
                    self.cancelDownload()
                }
            }
        }
    }
}
