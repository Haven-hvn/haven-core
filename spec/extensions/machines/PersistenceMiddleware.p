/**
 * Extension: PersistenceMiddleware
 * Role: REFERENCE EXTENSION — Inference pipeline middleware.
 * Layer: L2 (Identity & Persistence) — IPFS upload + dPID update.
 *
 * The most complex middleware. On the response stage, it:
 * 1. Reads the encrypted buffer (or compressed, or raw) from context metadata
 * 2. Formats an IPLD ConversationNode with linked-list backpointers
 * 3. Adds the node to an internal batch buffer
 * 4. When the batch is full (or on explicit flush), uploads to IPFS
 * 5. Updates the agent's dPID via WalletIdentity (eUpdateDPID)
 *
 * **Security check (fail-closed):** If EncryptionMiddleware is registered
 * (indicated by "encryption:algorithm" in context metadata) but no
 * "encryptedBuffer" exists, persistence ABORTS. This prevents writing
 * plaintext when encryption was expected. Mirrors lmstudio-bridge's
 * upload.ts security check.
 *
 * **Non-blocking:** The pipeline returns the response to AgentLoop
 * immediately. IPFS upload and dPID update happen asynchronously via
 * the batch queue (fire-and-forget from the pipeline's perspective).
 *
 * Also handles eMemoryRestore on boot — walks the IPLD DAG from a root
 * CID to restore the agent's conversation history.
 *
 * Mirrors lmstudio-bridge's upload.ts middleware.
 *
 * Context metadata keys read:
 *   - "encryptedBuffer" (from EncryptionMiddleware)
 *   - "compressedBuffer" (from CompressionMiddleware)
 *   - "encryption:algorithm" (presence indicates encryption was expected)
 *   - "compression:algorithm", "compression:originalSize"
 *
 * Emits extension events:
 *   - eConversationCaptured, eConversationStored, eSessionDAGUpdated
 *   - eUpdateDPID (core event, to WalletIdentity)
 *   - eMemoryRestored (core event, to AgentLoop)
 *
 * States: Init → Ready → Flushing → Ready
 *         Init → Ready → Restoring → Ready
 */

machine PersistenceMiddleware {
    var pipeline: machine;
    var walletIdentity: machine;
    var bus: machine;
    var middlewareName: MiddlewareName;

    // Batch buffer — accumulates conversation nodes before IPFS upload.
    var batchBuffer: seq[ConversationNode];
    var batchSize: int;          // Max conversations per batch before auto-flush
    var batchCount: int;         // Current count in buffer

    // Session tracking — per-session previous conversation CID for DAG linking.
    var sessionLastCid: map[string, CID];

    // Total conversations persisted (lifetime counter).
    var totalPersisted: int;

    start state Init {
        entry (payload: (pipeline: machine, walletIdentity: machine, bus: machine, batchSize: int)) {
            pipeline = payload.pipeline;
            walletIdentity = payload.walletIdentity;
            bus = payload.bus;
            batchSize = payload.batchSize;
            middlewareName = "persist";
            batchBuffer = default(seq[ConversationNode]);
            batchCount = 0;
            sessionLastCid = default(map[string, CID]);
            totalPersisted = 0;

            // Priority 40 — runs after encrypt (30) on request,
            // runs before encrypt on response (reverse order).
            // Response chain: persist(40) → encrypt(30) → compress(20) → logger(10)
            // So persist sees the encryptedBuffer already set by encrypt.
            send pipeline, eRegisterMiddleware, (
                name = middlewareName,
                handler = this,
                priority = 40
            );

            print format("PersistenceMiddleware: Initialized — batchSize={0}", batchSize);
            goto Ready;
        }
    }

    // ========================================================================
    // Ready — Accepting middleware events and memory restore requests
    // ========================================================================
    state Ready {
        // ================================================================
        // Request stage — no-op for persistence
        // ================================================================
        on eMiddlewareRequest do (payload: (context: PipelineContext, request: (
                sessionKey: SessionKey, messages: seq[map[string, string]],
                tools: seq[ToolDefinition], requestor: machine,
                estimatedCost: CostEstimate))) {

            // Persistence only operates on the response stage.
            send pipeline, eMiddlewareNext, payload.context;
        }

        // ================================================================
        // Response stage — capture, format, batch, and (maybe) flush
        // ================================================================
        on eMiddlewareResponse do (payload: (context: PipelineContext, response: (
                sessionKey: SessionKey, response: LLMResponse))) {

            var ctx: PipelineContext;
            ctx = payload.context;

            // --- Security check: fail-closed encryption boundary ---
            // If encryption was expected (algorithm metadata present) but
            // no encrypted buffer exists, abort persistence.
            if ("encryption:algorithm" in ctx.metadata) {
                if (!("encryptedBuffer" in ctx.metadata)) {
                    print format("PersistenceMiddleware: [RESP {0}] ABORT — encryption expected but no encryptedBuffer (fail-closed)",
                                 ctx.requestId);
                    // Emit error but still call next — the response goes to AgentLoop,
                    // we just don't persist this conversation.
                    send pipeline, eMiddlewareError, (
                        middleware = middlewareName,
                        error = "Encryption was expected but encryptedBuffer is missing — refusing to persist plaintext",
                        context = ctx
                    );
                    return;
                }
            }

            // --- Build the ConversationNode ---
            var encConfig: EncryptionConfig;
            if ("encryption:algorithm" in ctx.metadata) {
                encConfig = (
                    encrypted = true,
                    algorithm = ctx.metadata["encryption:algorithm"],
                    publicKeyFingerprint = ctx.metadata["encryption:publicKeyFingerprint"]
                );
            } else {
                encConfig = (encrypted = false, algorithm = "", publicKeyFingerprint = "");
            }

            var compConfig: CompressionConfig;
            if ("compression:algorithm" in ctx.metadata) {
                compConfig = (
                    compressed = true,
                    algorithm = ctx.metadata["compression:algorithm"],
                    originalSize = 0  // In real impl, parse from metadata string
                );
            } else {
                compConfig = (compressed = false, algorithm = "", originalSize = 0);
            }

            // Build request record from captured metadata.
            var convRequest: ConversationRequest;
            convRequest = (
                model = "",   // Would be extracted from the actual request in real impl
                messages = payload.response.response.toolCalls,  // Placeholder — real impl uses captured request
                parameters = default(map[string, string])
            );

            // Build response record.
            var convResponse: ConversationResponse;
            convResponse = (
                id = ctx.requestId,
                model = "",
                choices = default(seq[map[string, string]]),
                usage = default(map[string, int]),
                created = ctx.timestamp
            );

            // Get previous conversation CID for this session (linked list).
            var prevCid: CID;
            if (payload.response.sessionKey in sessionLastCid) {
                prevCid = sessionLastCid[payload.response.sessionKey];
            } else {
                prevCid = "";
            }

            var convMetadata: ConversationMetadata;
            convMetadata = (
                shimVersion = "1.0.0",
                captureTimestamp = ctx.timestamp,
                encryption = encConfig,
                compression = compConfig
            );

            var node: ConversationNode;
            node = (
                version = "1.0.0",
                request = convRequest,
                response = convResponse,
                metadata = convMetadata,
                timestamp = ctx.timestamp,
                previousConversationCid = prevCid
            );

            // Emit eConversationCaptured for CIDRecorderMiddleware and other consumers.
            send bus, eConversationCaptured, (
                sessionKey = payload.response.sessionKey,
                node = node
            );

            // Add to batch buffer.
            batchBuffer += (node);
            batchCount = batchCount + 1;

            print format("PersistenceMiddleware: [RESP {0}] Captured conversation — batch {1}/{2}",
                         ctx.requestId, batchCount, batchSize);

            // Auto-flush if batch is full.
            if (batchCount >= batchSize) {
                print format("PersistenceMiddleware: Batch full — flushing {0} conversations", batchCount);
                // Call next first — return response to AgentLoop immediately.
                // Flush happens asynchronously (non-blocking persistence).
                send pipeline, eMiddlewareNext, ctx;
                goto Flushing;
                return;
            }

            // Batch not full — call next and stay in Ready.
            send pipeline, eMiddlewareNext, ctx;
        }

        // ================================================================
        // Memory restore — walk IPLD DAG from root CID on boot
        // ================================================================
        on eMemoryRestore do (rootCid: CID) {
            print format("PersistenceMiddleware: Memory restore requested — rootCid={0}", rootCid);
            goto Restoring;
        }
    }

    // ========================================================================
    // Flushing — Upload batch to IPFS and update dPID
    // ========================================================================
    state Flushing {
        entry {
            // In a real implementation:
            //   1. Serialize batch as IPLD DAG
            //   2. Upload to IPFS via storage adapter
            //   3. Get root CID of the batch
            //   4. Request dPID update via WalletIdentity

            // Simulate: generate a CID for the batch.
            var batchCid: CID;
            batchCid = format("bafy:batch:{0}", totalPersisted + batchCount);

            // Update per-session last CID tracking.
            // (In real impl, each conversation in the batch gets its own CID)
            var i: int;
            i = 0;
            while (i < sizeof(batchBuffer)) {
                totalPersisted = totalPersisted + 1;
                i = i + 1;
            }

            // Emit eConversationStored for each conversation in the batch.
            // (Simplified — real impl would emit per-conversation CIDs)
            send bus, eConversationStored, (
                sessionKey = "batch",
                cid = batchCid
            );

            // Request dPID update — WalletIdentity signs, registry updates.
            send walletIdentity, eUpdateDPID, (
                newCid = batchCid,
                requestor = this
            );

            print format("PersistenceMiddleware: Flushed batch — cid={0} total={1}",
                         batchCid, totalPersisted);

            // Clear the batch buffer.
            batchBuffer = default(seq[ConversationNode]);
            batchCount = 0;

            goto Ready;
        }

        // Handle dPID update confirmation (may arrive while still in Flushing
        // or after returning to Ready — either is fine).
        on eDPIDUpdated do (version: DPIDVersion) {
            print format("PersistenceMiddleware: dPID updated — version={0} cid={1}",
                         version.version, version.cid);
        }
    }

    // ========================================================================
    // Restoring — Walk IPLD DAG from root CID to rebuild conversation history
    // ========================================================================
    state Restoring {
        entry {
            // In a real implementation:
            //   1. Fetch root CID from IPFS
            //   2. Walk the SessionDAGNode chain (following previousSessionCid)
            //   3. For each session, walk the ConversationNode chain
            //   4. Rebuild sessionLastCid map
            //   5. Optionally decrypt/decompress if encryption/compression metadata present

            // Simulate: pretend we restored some sessions.
            var restoredSessions: int;
            restoredSessions = 1;  // Stub

            print format("PersistenceMiddleware: Memory restored — {0} sessions", restoredSessions);

            // Emit eMemoryRestored so AgentLoop knows memory is available.
            send bus, eMemoryRestored, (
                success = true,
                sessionCount = restoredSessions
            );

            goto Ready;
        }
    }
}
