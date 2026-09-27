//
//  ModelStorageService.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import Foundation
import Combine

public final class ModelStorageService {
    public static let shared = ModelStorageService()

    private let fileManager = FileManager.default

    private init() {
        createRequiredDirectories()
    }

    // MARK: - Directory Setup

    private func createRequiredDirectories() {
        let docs = documentsDirectory
        let imagesDir = docs.appendingPathComponent("GeneratedImages", isDirectory: true)
        try? fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        if let appSupport = try? applicationSupportDirectory() {
            let sdDir = appSupport.appendingPathComponent("StableDiffusion", isDirectory: true)
            try? fileManager.createDirectory(at: sdDir, withIntermediateDirectories: true)
        }

        // Clean up obsolete/incompatible files (e.g. Qwen 3.5 which is incompatible with llama.cpp)
        let obsoleteFiles = ["Qwen3.5-2B-Q4_K_M.gguf"]
        for obsolete in obsoleteFiles {
            let obsoleteURL = docs.appendingPathComponent(obsolete)
            if fileManager.fileExists(atPath: obsoleteURL.path) {
                try? fileManager.removeItem(at: obsoleteURL)
            }
        }
    }

    public var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public func applicationSupportDirectory() throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    // MARK: - LLM Paths

    public func path(for llm: LLMModelInfo) -> URL {
        documentsDirectory.appendingPathComponent(llm.filename)
    }

    public func isDownloaded(llm: LLMModelInfo) -> Bool {
        let fileURL = path(for: llm)
        guard fileManager.fileExists(atPath: fileURL.path) else { return false }
        // Verify file is non-empty (> 50MB to avoid aborted corrupt stubs)
        guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64, size > 50 * 1024 * 1024 else {
            return false
        }

        // Verify valid GGUF binary magic header ('G', 'G', 'U', 'F' = 0x47, 0x47, 0x55, 0x46)
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? fileHandle.close() }
        guard let headerData = try? fileHandle.read(upToCount: 4), headerData.count == 4 else { return false }
        let magic = [UInt8](headerData)
        return magic == [0x47, 0x47, 0x55, 0x46]
    }

    public func fileSize(for llm: LLMModelInfo) -> String? {
        let fileURL = path(for: llm)
        guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let bytes = attrs[.size] as? Int64 else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public func delete(llm: LLMModelInfo) throws {
        let fileURL = path(for: llm)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - Image Model Paths

    public func modelBaseDir(for imageModel: ImageModelInfo) -> URL {
        (try? applicationSupportDirectory())?
            .appendingPathComponent("StableDiffusion", isDirectory: true)
            .appendingPathComponent(imageModel.folderName, isDirectory: true)
        ?? documentsDirectory.appendingPathComponent(imageModel.folderName, isDirectory: true)
    }

    public func storageDir(for imageModel: ImageModelInfo) -> URL {
        modelBaseDir(for: imageModel).appendingPathComponent("resources", isDirectory: true)
    }

    public func detectResourcesDirectory(in root: URL) -> URL? {
        if isResourcesDirectory(root) { return root }
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isDirectory == true else { continue }
            if isResourcesDirectory(url) { return url }
        }
        return nil
    }

    public func isResourcesDirectory(_ url: URL) -> Bool {
        for name in ["merges.txt", "vocab.json", "TextEncoder.mlmodelc", "VAEDecoder.mlmodelc"] {
            guard fileManager.fileExists(atPath: url.appendingPathComponent(name).path) else { return false }
        }
        let single = fileManager.fileExists(atPath: url.appendingPathComponent("Unet.mlmodelc").path)
        let chunked = fileManager.fileExists(atPath: url.appendingPathComponent("UnetChunk1.mlmodelc").path)
            && fileManager.fileExists(atPath: url.appendingPathComponent("UnetChunk2.mlmodelc").path)
        return single || chunked
    }

    public func isDownloaded(imageModel: ImageModelInfo) -> Bool {
        let resourcesDir = storageDir(for: imageModel)
        guard fileManager.fileExists(atPath: resourcesDir.path) else { return false }
        return detectResourcesDirectory(in: resourcesDir) != nil
    }

    public func imageModelResourcesURL(for imageModel: ImageModelInfo) -> URL? {
        let resourcesDir = storageDir(for: imageModel)
        guard fileManager.fileExists(atPath: resourcesDir.path) else { return nil }
        return detectResourcesDirectory(in: resourcesDir)
    }

    public func delete(imageModel: ImageModelInfo) throws {
        let baseDir = modelBaseDir(for: imageModel)
        if fileManager.fileExists(atPath: baseDir.path) {
            try fileManager.removeItem(at: baseDir)
        }
    }

    // MARK: - Device Storage Checks

    public var freeDiskSpaceBytes: Int64 {
        let docPath = documentsDirectory.path
        if let attrs = try? fileManager.attributesOfFileSystem(forPath: docPath),
           let freeSize = attrs[.systemFreeSize] as? Int64 {
            return freeSize
        }
        return 0
    }

    public var freeDiskSpaceString: String {
        ByteCountFormatter.string(fromByteCount: freeDiskSpaceBytes, countStyle: .file)
    }
}
