//
//  LocalImageModelService.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//  Ported from ModeAI reference implementation.
//

import Foundation
import Combine
import UIKit
import SwiftUI

#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

public final class LocalImageModelService: ObservableObject {
    public static let shared = LocalImageModelService()

    // MARK: - Published State

    @Published public var availableModels: [ImageModelInfo] = ModelCatalogue.imageModels
    @Published public var selectedModelId: String = ModelCatalogue.imageModels.first?.id ?? "sd15-palettized"

    @Published public var downloadingModelId: String? = nil
    @Published public var downloadProgress: Double = 0.0
    @Published public var isUnzipping: Bool = false
    @Published public var downloadError: String? = nil
    @Published public var downloadSpeedString: String = ""

    public var selectedModel: ImageModelInfo? {
        availableModels.first(where: { $0.id == selectedModelId })
    }

    // MARK: - Private

    private var currentDownloadTask: Task<Void, Never>? = nil

    private init() {}

    // MARK: - Public API

    /// Returns the resources URL if the model is fully extracted and ready, nil otherwise.
    public func modelResourcesURL(for model: ImageModelInfo) -> URL? {
        let resourcesDir = storageDir(for: model)
        guard FileManager.default.fileExists(atPath: resourcesDir.path) else { return nil }
        return detectResourcesDirectory(in: resourcesDir)
    }

    public func isModelDownloaded(_ model: ImageModelInfo) -> Bool {
        modelResourcesURL(for: model) != nil
    }

    public func isModelDownloading(_ model: ImageModelInfo) -> Bool {
        downloadingModelId == model.id
    }

    public func startDownload(model: ImageModelInfo) {
        guard downloadingModelId == nil else {
            downloadError = "Another model is already downloading."
            return
        }
        guard hasSufficientDiskSpace(required: model.requiredBytes) else {
            downloadError = "Insufficient disk space. Please free up at least \(model.sizeDisplay)."
            return
        }
        guard !isModelDownloaded(model) else { return }

        downloadingModelId = model.id
        downloadError = nil
        downloadProgress = 0.0
        downloadSpeedString = ""
        isUnzipping = false

        print("[Download] Starting \(model.displayName) from \(model.downloadURL)")

        currentDownloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resourcesURL = try await self.ensureResourcesPresent(for: model)
                print("[Download] Ready at \(resourcesURL.path)")
                await MainActor.run {
                    self.downloadingModelId = nil
                    self.downloadProgress = 1.0
                    self.isUnzipping = false
                    self.downloadSpeedString = ""
                    self.objectWillChange.send()
                }
            } catch is CancellationError {
                print("[Download] Cancelled")
                await MainActor.run {
                    self.downloadingModelId = nil
                    self.downloadProgress = 0.0
                    self.isUnzipping = false
                    self.downloadSpeedString = ""
                    self.objectWillChange.send()
                }
            } catch {
                print("[Download] Failed: \(error)")
                await MainActor.run {
                    self.downloadingModelId = nil
                    self.downloadProgress = 0.0
                    self.isUnzipping = false
                    self.downloadSpeedString = ""
                    self.downloadError = error.localizedDescription
                    self.objectWillChange.send()
                }
            }
        }
    }

    public func pauseDownload(model: ImageModelInfo) {
        guard downloadingModelId == model.id else { return }
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        downloadingModelId = nil
        downloadProgress = 0.0
        downloadSpeedString = ""
        isUnzipping = false
        self.objectWillChange.send()
    }

    public func cancelDownload(model: ImageModelInfo) {
        guard downloadingModelId == model.id else { return }
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        let dest = storageDir(for: model)
        try? FileManager.default.removeItem(at: dest)
        downloadingModelId = nil
        downloadProgress = 0.0
        downloadSpeedString = ""
        isUnzipping = false
        self.objectWillChange.send()
    }

    @MainActor
    public func deleteModel(_ model: ImageModelInfo) {
        let dir = modelBaseDir(for: model)
        print("[Model] Deleting \(model.displayName) at \(dir.path)")

        Task {
            do {
                if FileManager.default.fileExists(atPath: dir.path) {
                    try FileManager.default.removeItem(at: dir)
                    print("[Model] Successfully deleted model files")
                }
            } catch {
                print("[Model] Failed to delete model files: \(error)")
                self.downloadError = "Failed to delete model: \(error.localizedDescription)"
            }

            self.downloadProgress = 0.0
            if self.downloadingModelId == model.id {
                self.downloadingModelId = nil
            }
            self.objectWillChange.send()
        }
    }

    // MARK: - Resource Detection

    public func detectResourcesDirectory(in root: URL) -> URL? {
        if isResourcesDirectory(root) { return root }
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            return nil
        }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isDirectory == true else { continue }
            if isResourcesDirectory(url) { return url }
        }
        return nil
    }

    private func isResourcesDirectory(_ url: URL) -> Bool {
        let fm = FileManager.default
        for name in ["merges.txt", "vocab.json", "TextEncoder.mlmodelc", "VAEDecoder.mlmodelc"] {
            guard fm.fileExists(atPath: url.appendingPathComponent(name).path) else { return false }
        }
        let single  = fm.fileExists(atPath: url.appendingPathComponent("Unet.mlmodelc").path)
        let chunked = fm.fileExists(atPath: url.appendingPathComponent("UnetChunk1.mlmodelc").path)
                   && fm.fileExists(atPath: url.appendingPathComponent("UnetChunk2.mlmodelc").path)
        return single || chunked
    }

    // MARK: - Internal Helpers

    public func applicationSupportDir() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    public func modelBaseDir(for model: ImageModelInfo) -> URL {
        (try? applicationSupportDir())?
            .appendingPathComponent("StableDiffusion", isDirectory: true)
            .appendingPathComponent(model.folderName, isDirectory: true)
        ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(model.folderName, isDirectory: true)
    }

    public func storageDir(for model: ImageModelInfo) -> URL {
        modelBaseDir(for: model).appendingPathComponent("resources", isDirectory: true)
    }

    private func ensureResourcesPresent(for model: ImageModelInfo) async throws -> URL {
        let fm = FileManager.default
        let baseDir = modelBaseDir(for: model)
        let resourcesDir = storageDir(for: model)

        if fm.fileExists(atPath: resourcesDir.path),
           let detected = detectResourcesDirectory(in: resourcesDir) {
            print("[Model] Already extracted at \(detected.path)")
            return detected
        }

        try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let tmpZip = baseDir.appendingPathComponent("model.zip")
        if fm.fileExists(atPath: tmpZip.path) {
            try? fm.removeItem(at: tmpZip)
        }

        print("[Download] Downloading zip…")
        let downloader = ImageModelZipDownloader()
        try await downloader.download(from: model.downloadURL, to: tmpZip) { [weak self] written, total in
            guard let self else { return }
            if total > 0 {
                let frac = min(max(Double(written) / Double(total), 0), 1)
                Task { @MainActor in
                    self.downloadProgress = frac * 0.9
                    let dlMB = Double(written) / (1024 * 1024)
                    let totMB = Double(total) / (1024 * 1024)
                    self.downloadSpeedString = String(format: "%.1f / %.1f MB", dlMB, totMB)
                }
            }
        } log: { message in
            print(message)
        }

        await MainActor.run { [weak self] in
            self?.isUnzipping = true
            self?.downloadProgress = 0.9
            self?.downloadSpeedString = "Extracting CoreML weights…"
        }
        print("[Download] Finished downloading, starting extraction…")

        try await unzipModel(from: tmpZip, to: resourcesDir, model: model)

        if let detected = detectResourcesDirectory(in: resourcesDir) {
            return detected
        }
        throw NSError(domain: "LocalImageModelService", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Extraction completed, but CoreML resources were not found in archive."])
    }

    private func unzipModel(from zipURL: URL, to destinationDir: URL, model: ImageModelInfo) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationDir.path) {
            try? fm.removeItem(at: destinationDir)
        }
        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        #if canImport(ZIPFoundation)
        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            throw NSError(domain: "LocalImageModelService", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to open zip archive"])
        }

        let total = max(countEntries(in: archive), 1)
        var extracted = 0

        for entry in archive {
            if Task.isCancelled { throw CancellationError() }

            let outURL = destinationDir.appendingPathComponent(entry.path)
            if entry.type == .directory {
                try fm.createDirectory(at: outURL, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try archive.extract(entry, to: outURL)
            }

            extracted += 1
            let frac = 0.9 + (Double(extracted) / Double(total)) * 0.1

            await MainActor.run { [weak self] in
                if self?.downloadingModelId == model.id {
                    self?.downloadProgress = frac
                    self?.downloadSpeedString = "Extracting (\(Int(Double(extracted) / Double(total) * 100))%)..."
                }
            }
        }

        try? fm.removeItem(at: zipURL)
        print("[Unzip] completed")

        await MainActor.run { [weak self] in
            self?.isUnzipping = false
        }
        #else
        throw NSError(domain: "LocalImageModelService", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "ZIPFoundation is not available to extract the archive."])
        #endif
    }

    #if canImport(ZIPFoundation)
    private func countEntries(in archive: Archive) -> Int {
        var total = 0
        for _ in archive { total += 1 }
        return total
    }
    #endif

    private func hasSufficientDiskSpace(required: Int64) -> Bool {
        guard let dir = try? applicationSupportDir(),
              let values = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else { return true }
        return available >= required
    }
}

// MARK: - ImageModelZipDownloader

final class ImageModelZipDownloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var destinationURL: URL?
    private var onProgress: ((Int64, Int64) -> Void)?
    private var log: ((String) -> Void)?

    func download(
        from url: URL,
        to destinationURL: URL,
        onProgress: @escaping (Int64, Int64) -> Void,
        log: @escaping (String) -> Void
    ) async throws {
        self.destinationURL = destinationURL
        self.onProgress = onProgress
        self.log = log

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let destinationURL else {
            continuation?.resume(throwing: URLError(.badURL))
            continuation = nil
            return
        }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            // Synchronously move the file to permanent destination BEFORE delegate returns!
            try fm.moveItem(at: location, to: destinationURL)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
