//
//  ModelCatalogue.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import Foundation
import Combine
import SwiftUI

// MARK: - LLM Model Information

public struct LLMModelInfo: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let filename: String
    public let downloadURL: URL
    public let sha256: String?
    public let sizeDisplay: String
    public let promptType: String // "chatML", "llama", "gemma", "phi"
    public let description: String
    public let isRecommended: Bool
    public let parameterCount: String

    public var stopTokens: [String] {
        switch promptType {
        case "gemma":
            return ["<end_of_turn>", "<eos>"]
        case "llama", "llama3":
            return ["<|eot_id|>", "<|end_of_text|>"]
        case "mistral":
            return ["[/INST]"]
        case "alpaca":
            return ["###"]
        case "phi":
            return ["<|end|>", "<|endoftext|>"]
        case "chatML":
            fallthrough
        default:
            return ["<|im_end|>", "<|endoftext|>"]
        }
    }
}

// MARK: - Image Model Information

public struct ImageModelInfo: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let displayName: String
    public let downloadURL: URL
    public let sizeDisplay: String
    public let folderName: String
    public let requiredBytes: Int64
    public let deviceRequirement: String
    public let description: String
    public let isRecommended: Bool
}

// MARK: - Built-in Model Catalogue

public struct ModelCatalogue {
    public static let textModels: [LLMModelInfo] = [
        LLMModelInfo(
            id: "Llama-3.2-1b-q4",
            name: "Llama 3.2 1B (Fastest)",
            filename: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf?download=true")!,
            sha256: nil,
            sizeDisplay: "807 MB",
            promptType: "llama3",
            description: "Fastest mobile LLM. Standard Q4_K_M with 100% Metal SIMDgroup GPU acceleration on iPhone.",
            isRecommended: true,
            parameterCount: "1.2B"
        ),
        LLMModelInfo(
            id: "Llama-3.2",
            name: "Llama 3.2 1B Instruct (Q5)",
            filename: "Llama-3.2-1B-Instruct-UD-Q5_K_XL.gguf",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-UD-Q5_K_XL.gguf?download=true")!,
            sha256: "183e5fe9a9afaaebe889832f9679473c0ae9120915e5f6e30b297475e55067ee",
            sizeDisplay: "877 MB",
            promptType: "llama3",
            description: "Ultra-compact 5-bit model. High precision reasoning with minimal memory footprint.",
            isRecommended: false,
            parameterCount: "1.2B"
        ),
        LLMModelInfo(
            id: "qwen2.5-1.5b",
            name: "Qwen 2.5 1.5B Instruct",
            filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
            sha256: "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
            sizeDisplay: "1.2 GB",
            promptType: "chatML",
            description: "Industry-leading small model with outstanding coding and mathematical reasoning.",
            isRecommended: true,
            parameterCount: "1.5B"
        ),
        LLMModelInfo(
            id: "qwen2.5-3b",
            name: "Qwen 2.5 3B Instruct",
            filename: "qwen2.5-3b-instruct-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf")!,
            sha256: nil,
            sizeDisplay: "2.0 GB",
            promptType: "chatML",
            description: "Powerful 3B reasoning model with superior coding, math, and long-context capabilities.",
            isRecommended: false,
            parameterCount: "3.0B"
        ),
        LLMModelInfo(
            id: "gemma-2-2B-it",
            name: "Gemma 2 2B IT",
            filename: "gemma-2-2b-it-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf?download=true")!,
            sha256: "e0aee85060f168f0f2d8473d7ea41ce2f3230c1bc1374847505ea599288a7787",
            sizeDisplay: "1.6 GB",
            promptType: "gemma",
            description: "Google's research-grade architecture with expressive, nuance-rich language outputs.",
            isRecommended: false,
            parameterCount: "2.0B"
        ),
        LLMModelInfo(
            id: "Phi-4-mini",
            name: "Phi-4-mini-instruct",
            filename: "Phi-4-mini-instruct-Q2_K_L.gguf",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q2_K_L.gguf?download=true")!,
            sha256: "70763e15ae749fdd746a3f7b74a9701d0c556b687f026bacaa028bebfcbfdc11",
            sizeDisplay: "1.57 GB",
            promptType: "phi",
            description: "Microsoft's dense reasoning architecture designed for complex question answering.",
            isRecommended: false,
            parameterCount: "1.6B"
        )
    ]

    public static let imageModels: [ImageModelInfo] = [
        ImageModelInfo(
            id: "sd15-palettized",
            name: "stable-diffusion-v1-5-palettized",
            displayName: "Stable Diffusion 1.5",
            downloadURL: URL(string: "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/main/coreml-stable-diffusion-v1-5-palettized_original_compiled.zip")!,
            sizeDisplay: "1.6 GB",
            folderName: "coreml_stable_diffusion_v1_5_palettized_original_compiled",
            requiredBytes: Int64(2.5 * 1024 * 1024 * 1024),
            deviceRequirement: "iPhone 11 or newer (Neural Engine / GPU)",
            description: "Official Apple CoreML Stable Diffusion 1.5 with 6-bit weight palettization for mobile generation.",
            isRecommended: true
        )
    ]
}
