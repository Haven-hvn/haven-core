/**
 * Extension: EncryptionMiddleware
 * Role: REFERENCE EXTENSION — Inference pipeline middleware.
 * Layer: L2 (Identity & Persistence) — uses agent's key for encryption.
 *
 * Response-stage middleware that encrypts the payload before persistence.
 * Reads the compressed buffer from context metadata if available (from
 * CompressionMiddleware), otherwise uses the raw response. Encrypts with
 * the agent's public key and stores the encrypted buffer in context metadata.
 *
 * **Fail-closed pattern:** If encryption fails, this middleware emits
 * eMiddlewareError. The InferencePipeline's response chain handles errors
 * as non-fatal (skips and continues), but the PersistenceMiddleware
 * downstream checks for "encryptedBuffer" and aborts if this middleware
 * was registered but the key is missing. This is the same pattern as
 * lmstudio-bridge's upload.ts security check.
 *
 * Request stage: no-op (passes through).
 * Response stage: encrypts compressed/raw payload, stores in context.
 *
 * Mirrors lmstudio-bridge's taco-encrypt.ts middleware.
 *
 * Context metadata keys read:
 *   - "compressedBuffer" (optional, from CompressionMiddleware)
 *
 * Context metadata keys written:
 *   - "encryptedBuffer": encrypted payload
 *   - "encryption:algorithm": "aes-256-gcm"
 *   - "encryption:publicKeyFingerprint": fingerprint of the encrypting key
 *
 * States: Init → Ready
 */

machine EncryptionMiddleware {
    var pipeline: machine;
    var middlewareName: MiddlewareName;

    // The agent's public key fingerprint (set during initialization).
    // In a real implementation, this comes from WalletIdentity.
    var publicKeyFingerprint: string;

    start state Init {
        entry (payload: (pipeline: machine, publicKeyFingerprint: string)) {
            pipeline = payload.pipeline;
            middlewareName = "encrypt";
            publicKeyFingerprint = payload.publicKeyFingerprint;

            // Priority 30 — runs after compress (20) on request,
            // runs before compress on response. This means on the response
            // chain: encrypt runs BEFORE compress sees the response, but
            // since compress runs on request to capture and on response to
            // compress, encrypt on response reads the compressed buffer.
            //
            // Response chain (reverse order): encrypt(30) → compress(20) → logger(10)
            // So encrypt sees compressedBuffer already set by compress.
            send pipeline, eRegisterMiddleware, (
                name = middlewareName,
                handler = this,
                priority = 30
            );

            print format("EncryptionMiddleware: Initialized — key fingerprint={0}",
                         publicKeyFingerprint);
            goto Ready;
        }
    }

    state Ready {
        // ================================================================
        // Request stage — no-op, pass through
        // ================================================================
        on eMiddlewareRequest do (payload: (context: PipelineContext, request: (
                sessionKey: SessionKey, messages: seq[map[string, string]],
                tools: seq[ToolDefinition], requestor: machine,
                estimatedCost: CostEstimate))) {

            // Encryption only operates on the response stage.
            send pipeline, eMiddlewareNext, payload.context;
        }

        // ================================================================
        // Response stage — encrypt the payload
        // ================================================================
        on eMiddlewareResponse do (payload: (context: PipelineContext, response: (
                sessionKey: SessionKey, response: LLMResponse))) {

            var ctx: PipelineContext;
            ctx = payload.context;

            // Determine what to encrypt: compressed buffer preferred, raw response as fallback.
            var plaintext: string;
            if ("compressedBuffer" in ctx.metadata) {
                plaintext = ctx.metadata["compressedBuffer"];
                print format("EncryptionMiddleware: [RESP {0}] Encrypting compressed buffer",
                             ctx.requestId);
            } else {
                plaintext = payload.response.response.content;
                print format("EncryptionMiddleware: [RESP {0}] Encrypting raw response (no compression)",
                             ctx.requestId);
            }

            // Simulate encryption. In a real implementation:
            //   const encrypted = await aes256gcm.encrypt(plaintext, agentPublicKey);
            // If encryption fails, we emit eMiddlewareError (fail-closed).
            if (publicKeyFingerprint == "") {
                // No key available — fail closed.
                print format("EncryptionMiddleware: [RESP {0}] FAILED — no public key, aborting",
                             ctx.requestId);
                send pipeline, eMiddlewareError, (
                    middleware = middlewareName,
                    error = "No public key available for encryption",
                    context = ctx
                );
                return;
            }

            // Store encrypted buffer in context metadata.
            ctx.metadata["encryptedBuffer"] = format("enc:aes-256-gcm:{0}", plaintext);
            ctx.metadata["encryption:algorithm"] = "aes-256-gcm";
            ctx.metadata["encryption:publicKeyFingerprint"] = publicKeyFingerprint;

            print format("EncryptionMiddleware: [RESP {0}] Encrypted — algo=aes-256-gcm fingerprint={1}",
                         ctx.requestId, publicKeyFingerprint);

            send pipeline, eMiddlewareNext, ctx;
        }
    }
}
