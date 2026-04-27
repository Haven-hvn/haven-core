/**
 * Extension: CIDRecorderMiddleware
 * Role: REFERENCE EXTENSION — Inference pipeline middleware.
 * Layer: L2 (Identity & Persistence) — conversation index maintenance.
 *
 * Response-stage middleware that records conversation CIDs and maintains
 * the ConversationIndex IPLD structure. This index enables efficient
 * lookup of conversations without walking the entire DAG — it's the
 * "table of contents" for the agent's memory.
 *
 * The CIDRecorder does NOT participate in the middleware pipeline's
 * eMiddlewareRequest/eMiddlewareResponse flow directly for its index work.
 * Instead, it listens for eConversationStored events emitted by
 * PersistenceMiddleware. However, it IS registered as a pipeline middleware
 * to observe the response stage and extract metadata for index entries
 * (model name, first user message, token count).
 *
 * Mirrors lmstudio-bridge's cid-recorder.ts middleware.
 *
 * Context metadata keys read:
 *   - "logger:messageCount" (from LoggerMiddleware)
 *
 * Extension events consumed:
 *   - eConversationCaptured (from PersistenceMiddleware)
 *   - eConversationStored (from PersistenceMiddleware)
 *
 * States: Init → Ready
 */

machine CIDRecorderMiddleware {
    var pipeline: machine;
    var bus: machine;
    var middlewareName: MiddlewareName;

    // The conversation index — maps session keys to ordered index entries.
    var index: seq[ConversationIndexEntry];
    var totalRecorded: int;

    start state Init {
        entry (payload: (pipeline: machine, bus: machine)) {
            pipeline = payload.pipeline;
            bus = payload.bus;
            middlewareName = "cid-recorder";
            index = default(seq[ConversationIndexEntry]);
            totalRecorded = 0;

            // Priority 50 — runs last on request, first on response.
            // Response chain: cid-recorder(50) → persist(40) → encrypt(30) → compress(20) → logger(10)
            // CID recorder sees the response first and can prepare index metadata
            // before persistence writes to IPFS.
            send pipeline, eRegisterMiddleware, (
                name = middlewareName,
                handler = this,
                priority = 50
            );

            print "CIDRecorderMiddleware: Initialized — registered with pipeline (priority 50)";
            goto Ready;
        }
    }

    state Ready {
        // ================================================================
        // Request stage — no-op for CID recording
        // ================================================================
        on eMiddlewareRequest do (payload: (context: PipelineContext, request: (
                sessionKey: SessionKey, messages: seq[map[string, string]],
                tools: seq[ToolDefinition], requestor: machine,
                estimatedCost: CostEstimate))) {

            // CID recording only operates on the response stage.
            send pipeline, eMiddlewareNext, payload.context;
        }

        // ================================================================
        // Response stage — extract metadata for future index entries
        // ================================================================
        on eMiddlewareResponse do (payload: (context: PipelineContext, response: (
                sessionKey: SessionKey, response: LLMResponse))) {

            var ctx: PipelineContext;
            ctx = payload.context;

            // Store response metadata in context for index entry creation.
            // When eConversationStored arrives with a CID, we'll have all
            // the metadata needed to create the index entry.
            ctx.metadata["cidrecorder:sessionKey"] = payload.response.sessionKey;
            ctx.metadata["cidrecorder:responseType"] = format("{0}", payload.response.response.responseType);
            ctx.metadata["cidrecorder:contentLength"] = format("{0}", sizeof(payload.response.response.content));

            // Extract first user message for search index (if available in captured request).
            // In real implementation, this would parse the messages array.
            ctx.metadata["cidrecorder:prepared"] = "true";

            print format("CIDRecorderMiddleware: [RESP {0}] Prepared index metadata",
                         ctx.requestId);

            send pipeline, eMiddlewareNext, ctx;
        }

        // ================================================================
        // Listen for eConversationStored from PersistenceMiddleware
        // ================================================================
        on eConversationStored do (stored: (sessionKey: SessionKey, cid: CID)) {
            // Create an index entry for this conversation.
            var entry: ConversationIndexEntry;
            entry = (
                conversationCid = stored.cid,
                timestamp = 0,           // Real impl would use actual timestamp
                model = "",              // Real impl would extract from stored request
                firstUserMessage = "",   // Real impl would extract first user msg
                tokenCount = 0           // Real impl would extract from response usage
            );

            index += (entry);
            totalRecorded = totalRecorded + 1;

            print format("CIDRecorderMiddleware: Recorded CID {0} — total={1}",
                         stored.cid, totalRecorded);
        }

        // ================================================================
        // Listen for eConversationCaptured to gather pre-storage metadata
        // ================================================================
        on eConversationCaptured do (captured: (sessionKey: SessionKey, node: ConversationNode)) {
            // We can use the node's metadata to enrich future index entries.
            // This event arrives before eConversationStored (captured → stored sequence).
            print format("CIDRecorderMiddleware: Conversation captured for session {0}",
                         captured.sessionKey);
        }
    }
}
