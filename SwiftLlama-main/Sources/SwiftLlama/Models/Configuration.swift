import Foundation
import llama
import Metal

public struct Configuration {
    public static let historySize = 20
    public let seed: Int
    public let topK: Int
    public let topP: Float
    public let nCTX: Int
    public let temperature: Float
    public let maxTokenCount: Int
    public let batchSize: Int
    public let stopTokens: [String]
    /// Number of model layers to offload to the GPU via Metal.
    /// On A14+ (MTLGPUFamilyApple7) this is 99. On A13 (iPhone 11) or older,
    /// llama.cpp's Metal kernels are not supported and offloading causes 300+ CPU/GPU graph splits;
    /// on those devices, setting 0 runs pure ARM NEON at full speed.
    public let nGpuLayers: Int32
    public let threads: Int32?
    public let batchThreads: Int32?
    public let flashAttn: Bool

    public init(seed: Int = 1234,
                topK: Int = 40,
                topP: Float = 0.9,
                nCTX: Int = 2048,
                temperature: Float = 0.2,
                batchSize: Int = 512,
                stopSequence: String? = nil,
                maxTokenCount: Int = 1024,
                stopTokens: [String] = [],
                nGpuLayers: Int32 = Configuration.optimalGpuLayers,
                threads: Int32? = nil,
                batchThreads: Int32? = nil,
                flashAttn: Bool = true) {
        self.seed = seed
        self.topK = topK
        self.topP = topP
        self.nCTX = nCTX
        self.batchSize = batchSize
        self.temperature = temperature
        self.maxTokenCount = maxTokenCount
        self.stopTokens = stopTokens
        self.nGpuLayers = nGpuLayers
        self.threads = threads
        self.batchThreads = batchThreads
        self.flashAttn = flashAttn
    }
}

extension Configuration {
    /// Determines whether the device GPU supports the Metal feature set required by llama.cpp.
    /// In llama.cpp, Metal matrix-multiplication kernels require simdgroup reduction operations,
    /// which are only supported on MTLGPUFamily.apple7 (Apple A14 / M1 and newer).
    /// On Apple6 devices (iPhone 11 / A13), attempting to offload to Metal causes llama.cpp to skip
    /// all matrix kernels, producing 300+ CPU/GPU graph splits per token and dropping speed to ~1.4 tok/s.
    public static var optimalGpuLayers: Int32 {
        #if targetEnvironment(simulator)
        return 0
        #else
        guard let device = MTLCreateSystemDefaultDevice() else { return 0 }
        if device.supportsFamily(.apple7) {
            print("[SwiftLlama] Metal GPU offload fully supported (Apple7+ detected). Offloading 99 layers.")
            return 99
        } else {
            print("[SwiftLlama] Device is \(device.name) (pre-Apple7). Using 0 GPU layers (pure ARM NEON) to eliminate graph splits and achieve maximum inference speed.")
            return 0
        }
        #endif
    }

    /// Calculate optimal CPU threads for generation on Apple Silicon.
    /// Heterogeneous A-series/M-series chips have Performance and Efficiency cores.
    /// In llama.cpp, spanning threads onto Efficiency cores causes severe thread-barrier stalls
    /// where fast cores sit idle waiting for slow cores.
    public static var optimalThreadCount: Int32 {
        var perfCores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &perfCores, &size, nil, 0) == 0, perfCores > 0 {
            if optimalGpuLayers == 0 {
                // On pure CPU mode (A13), 3 threads keeps the dual memory channels fully saturated
                return min(perfCores + 1, 4)
            }
            return min(perfCores, 4)
        }
        let total = ProcessInfo.processInfo.activeProcessorCount
        if total > 4 {
            return optimalGpuLayers == 0 ? 3 : 2
        } else {
            return Int32(max(1, total))
        }
    }

    /// Calculate optimal threads for batch/prompt processing.
    public static var optimalBatchThreadCount: Int32 {
        let total = ProcessInfo.processInfo.activeProcessorCount
        return Int32(min(4, max(2, total > 4 ? 4 : total)))
    }

    var contextParameters: ContextParameters {
        var params = llama_context_default_params()
        params.n_ctx = max(8, UInt32(self.nCTX))
        params.n_batch = UInt32(self.batchSize)
        params.n_ubatch = UInt32(min(512, self.batchSize))
        params.n_threads = self.threads ?? Configuration.optimalThreadCount
        params.n_threads_batch = self.batchThreads ?? Configuration.optimalBatchThreadCount
        params.offload_kqv = (self.nGpuLayers > 0)
        params.flash_attn = self.flashAttn
        params.no_perf = true
        return params
    }
}


