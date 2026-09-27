import Foundation
import llama

class LlamaModel {
    private let model: Model
    private let configuration: Configuration
    private let context: OpaquePointer
    private let sampler: UnsafeMutablePointer<llama_sampler>
    private var batch: Batch
    private var tokens: [Token]
    private var generatedTokenAccount: Int32 = 0
    private var generatedCount: Int32 = 0
    private var ended = false

    var shouldContinue: Bool {
        generatedCount < Int32(configuration.maxTokenCount) && generatedTokenAccount < Int32(llama_n_ctx(context)) && !ended
    }

    init(path: String, configuration: Configuration = .init()) throws {
        self.configuration = configuration

        llama_log_set({ level, text, _ in
            if let text = text {
                let str = String(cString: text)
                print("[llama.cpp] \(str)", terminator: "")
            }
        }, nil)

        llama_backend_init()
        llama_numa_init(GGML_NUMA_STRATEGY_DISABLED)

        var model_params = llama_model_default_params()

        // Offload layers to Metal GPU on real devices.
        // In the simulator Metal is unavailable, so keep CPU-only there.
        #if targetEnvironment(simulator)
        model_params.n_gpu_layers = 0
        #else
        model_params.n_gpu_layers = configuration.nGpuLayers
        #endif
        model_params.use_mmap = true

        print("[SwiftLlama] Initializing model with GPU offload support: \(llama_supports_gpu_offload()), target GPU layers: \(model_params.n_gpu_layers), optimal threads: \(configuration.contextParameters.n_threads)")

        guard let model = llama_load_model_from_file(path, model_params) else {
            throw SwiftLlamaError.others("Cannot load model at path \(path)")
        }
        self.model = model

        guard let context = llama_new_context_with_model(model, configuration.contextParameters) else {
            throw SwiftLlamaError.others("Cannot load model context")
        }
        self.context = context

        self.tokens = []
        self.batch = llama_batch_init(Int32(configuration.batchSize), 0, 1)

        self.sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(configuration.temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_softmax())
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(1234))

        try checkContextLength(context: context, model: model)
    }

    private func checkContextLength(context: Context, model: Model) throws {
        let n_ctx = llama_n_ctx(context)
        let n_ctx_train = llama_n_ctx_train(model)
        if n_ctx > n_ctx_train {
            throw SwiftLlamaError.others("Model was trained on \(n_ctx_train) context but tokens \(n_ctx) specified")
        }
    }

    func start(for prompt: Prompt) throws {
        ended = false
        generatedCount = 0
        tokens = tokenize(text: prompt.prompt, addBos: true)

        let nCtx = Int(llama_n_ctx(context))
        if tokens.count >= nCtx {
            let keepCount = max(1, nCtx - 64)
            tokens = Array(tokens.suffix(keepCount))
        }

        let totalTokens = tokens.count
        guard totalTokens > 0 else {
            ended = true
            return
        }

        let maxBatchSize = Int(configuration.batchSize)
        var offset = 0

        while offset < totalTokens {
            let chunkSize = min(maxBatchSize, totalTokens - offset)
            let isLastChunk = (offset + chunkSize == totalTokens)

            batch.clear()
            for i in 0..<chunkSize {
                let tokenIndex = offset + i
                let isLastToken = isLastChunk && (i == chunkSize - 1)
                batch.add(
                    token: tokens[tokenIndex],
                    position: Int32(tokenIndex),
                    seqIDs: [0],
                    logit: isLastToken
                )
            }

            if llama_decode(context, batch) != 0 {
                throw SwiftLlamaError.decodeError
            }

            offset += chunkSize
        }

        generatedTokenAccount = Int32(totalTokens)
    }

    func `continue`() throws -> String {
        let maxCtx = Int32(llama_n_ctx(context))
        if generatedTokenAccount >= maxCtx {
            ended = true
            return ""
        }

        let newToken = llama_sampler_sample(sampler, context, batch.n_tokens - 1)

        if llama_token_is_eog(model, newToken) || generatedTokenAccount >= maxCtx {
            ended = true
            return ""
        }

        let piece = tokenToString(token: newToken)

        batch.clear()
        batch.add(token: newToken, position: generatedTokenAccount, seqIDs: [0], logit: true)
        generatedTokenAccount += 1
        generatedCount += 1

        if llama_decode(context, batch) != 0 {
            throw SwiftLlamaError.decodeError
        }
        return piece
    }

    // MARK: - Helpers

    /// Convert a sampled token to a Swift String (valid UTF-8, no interleaved \0 bytes).
    private func tokenToString(token: llama_token) -> String {
        var cap: Int32 = 32
        var buf = [CChar](repeating: 0, count: Int(cap))

        // First attempt
        var written = buf.withUnsafeMutableBufferPointer { bufferPointer -> Int32 in
            guard let base = bufferPointer.baseAddress else { return 0 }
            // Use the signature your llama module exposes (this matches your previous use: 6 args)
            return llama_token_to_piece(model, token, base, cap, 0, false)
        }

        // If negative, allocate required size and retry
        if written < 0 {
            cap = -written
            buf = [CChar](repeating: 0, count: Int(cap))
            written = buf.withUnsafeMutableBufferPointer { bufferPointer -> Int32 in
                guard let base = bufferPointer.baseAddress else { return 0 }
                return llama_token_to_piece(model, token, base, cap, 0, false)
            }
        }

        let count = Int(max(0, written))
        if count == 0 { return "" }

        // Decode exact byte count (no trailing NUL included)
        let bytes: [UInt8] = buf.prefix(count).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func tokenize(text: String, addBos: Bool) -> [Token] {
        let utf8Count = text.utf8.count
        let n_tokens = utf8Count + (addBos ? 1 : 0) + 128 // Add margin for special tokens

        return Array(unsafeUninitializedCapacity: n_tokens) { buffer, initializedCount in
            // Revert special=true to false to avoid EXC_BAD_ACCESS in llama_vocab
            // Llama 3 control tokens might not be parsed correctly as special tokens, 
            // but this prevents the crash on iPhone 11 (A13).
            let result = llama_tokenize(model, text, Int32(utf8Count), buffer.baseAddress, Int32(n_tokens), addBos, false)
            
            if result < 0 {
                print("Error: Tokenization buffer too small, needed \(-result)")
                initializedCount = 0
            } else {
                initializedCount = Int(result)
            }
        }
    }

    func clear() {
        tokens.removeAll()
        llama_kv_cache_clear(context)
    }

    deinit {
        llama_batch_free(batch)
        llama_free(context)
        llama_free_model(model)
        llama_backend_free()
    }
}
