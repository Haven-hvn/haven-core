/**
 * Extension: CompressionMiddleware
 * Role: REFERENCE EXTENSION — Inference pipeline middleware.
 * Layer: L6 (Reasoning) — transforms inference payloads.
 *
 * Response-stage middleware that combines the request and response payloads,
 * compresses them, and stores the compressed buffer in the pipeline context
 * metadata under "compressedBuffer". Downstream middleware (EncryptionMiddleware,
 * PersistenceMiddleware) read this key instead of the raw payload.
 *
 * Request stage: captures the raw request in context metadata for later use.
 * Response stage: combines request + response, compresses, stores buffer.
 *
 * Mirrors lmstudio-bridge's gzip.ts middleware.
 *
 * Context metadata keys written:
 *   - "capturedRequest": JSON-serialized request (written on request stage)
 *   - "compressedBuffer": compressed payload (written on response stage)
 *   - "compression:algorithm": "gzip"
 *   - "compression:originalSize": pre-compression size as string
 *
 * States: Init → Ready
 */

machine CompressionMiddleware {
    var pipeline: machine;
    var middlewareName: MiddlewareName;

    start state Init {
        entry (payload: (pipeline: machine)) {
            pipeline = payload.pipeline;
            middlewareName = "compress";

            // Priority 20 — runs after logger (10) on request,
            // runs before logger on response (reverse order).
            send pipeline, eRegisterMiddleware, (
                name = middlewareName,
                handler = this,
                priority = 20
            );

            print "CompressionMiddleware: Initialized — registered with pipeline (priority 20)";
            goto Ready;
        }
    }

    state Ready {
        // ================================================================
        // Request stage — capture the raw request for later combination
        // ================================================================
        on eMiddlewareRequest do (payload: (context: PipelineContext, request: (
                sessionKey: SessionKey, messages: seq[map[string, string]],
                tools: seq[ToolDefinition], requestor: machine,
                estimatedCost: CostEstimate))) {

            // Capture the request in context metadata so the response stage
            // can combine request + response for compression.
            // In a real implementation, this would be JSON.stringify(request).
            var ctx: PipelineContext;
            ctx = payload.context;
            ctx.metadata["capturedRequest"] = format("messages:{0}", sizeof(payload.request.messages));

            print format("CompressionMiddleware: [REQ {0}] Captured request ({1} messages)",
                         ctx.requestId, sizeof(payload.request.messages));

            send pipeline, eMiddlewareNext, ctx;
        }

        // ================================================================
        // Response stage — combine request + response, compress
        // ================================================================
        on eMiddlewareResponse do (payload: (context: PipelineContext, response: (
                sessionKey: SessionKey, response: LLMResponse))) {

            var ctx: PipelineContext;
            ctx = payload.context;

            // Combine captured request + response into a single payload.
            // In a real implementation: gzip(JSON.stringify({request, response}))
            var capturedRequest: string;
            if ("capturedRequest" in ctx.metadata) {
                capturedRequest = ctx.metadata["capturedRequest"];
            } else {
                capturedRequest = "";
            }

            // Calculate the "original size" of the combined payload.
            // In the P spec, we approximate with string lengths.
            var originalSize: int;
            originalSize = sizeof(capturedRequest) + sizeof(payload.response.response.content);

            // Store the "compressed" buffer in context metadata.
            // In a real implementation, this would be the actual gzip buffer.
            ctx.metadata["compressedBuffer"] = format("gzip:{0}:{1}",
                capturedRequest, payload.response.response.content);
            ctx.metadata["compression:algorithm"] = "gzip";
            ctx.metadata["compression:originalSize"] = format("{0}", originalSize);

            print format("CompressionMiddleware: [RESP {0}] Compressed — originalSize={1}",
                         ctx.requestId, originalSize);

            send pipeline, eMiddlewareNext, ctx;
        }
    }
}
