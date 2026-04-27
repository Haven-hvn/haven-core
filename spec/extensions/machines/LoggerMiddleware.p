/**
 * Extension: LoggerMiddleware
 * Role: REFERENCE EXTENSION — Inference pipeline middleware.
 * Layer: L6 (Reasoning) — observes inference payloads.
 *
 * The simplest middleware. Logs request model, message count on the request
 * stage, and response token count, latency on the response stage. Does not
 * transform any data — purely observational.
 *
 * Mirrors lmstudio-bridge's logger.ts middleware.
 *
 * Registers with InferencePipeline via eRegisterMiddleware.
 * Handles: eMiddlewareRequest (request stage), eMiddlewareResponse (response stage).
 * Always calls next() — never short-circuits.
 *
 * States: Init → Ready (handles both request and response events)
 */

machine LoggerMiddleware {
    var pipeline: machine;
    var middlewareName: MiddlewareName;

    // Stats counters
    var totalRequests: int;
    var totalResponses: int;

    start state Init {
        entry (payload: (pipeline: machine)) {
            pipeline = payload.pipeline;
            middlewareName = "logger";
            totalRequests = 0;
            totalResponses = 0;

            // Register with the pipeline at highest priority (runs first on request,
            // last on response — sees everything before and after all other middleware).
            send pipeline, eRegisterMiddleware, (
                name = middlewareName,
                handler = this,
                priority = 10
            );

            print "LoggerMiddleware: Initialized — registered with pipeline (priority 10)";
            goto Ready;
        }
    }

    state Ready {
        // ================================================================
        // Request stage — log what's being sent to the LLM
        // ================================================================
        on eMiddlewareRequest do (payload: (context: PipelineContext, request: (
                sessionKey: SessionKey, messages: seq[map[string, string]],
                tools: seq[ToolDefinition], requestor: machine,
                estimatedCost: CostEstimate))) {

            totalRequests = totalRequests + 1;

            // Log request details: session, message count, tool count.
            print format("LoggerMiddleware: [REQ {0}] session={1} messages={2} tools={3}",
                         payload.context.requestId,
                         payload.request.sessionKey,
                         sizeof(payload.request.messages),
                         sizeof(payload.request.tools));

            // Store the request timestamp in context metadata for latency calculation.
            // Other middleware can read this if needed.
            var ctx: PipelineContext;
            ctx = payload.context;
            ctx.metadata["logger:requestTimestamp"] = format("{0}", ctx.timestamp);
            ctx.metadata["logger:messageCount"] = format("{0}", sizeof(payload.request.messages));

            // Always call next — logger never blocks.
            send pipeline, eMiddlewareNext, ctx;
        }

        // ================================================================
        // Response stage — log what came back from the LLM
        // ================================================================
        on eMiddlewareResponse do (payload: (context: PipelineContext, response: (
                sessionKey: SessionKey, response: LLMResponse))) {

            totalResponses = totalResponses + 1;

            // Log response details: type, content length, tool call count.
            var toolCallCount: int;
            toolCallCount = sizeof(payload.response.response.toolCalls);

            print format("LoggerMiddleware: [RESP {0}] type={1} contentLen={2} toolCalls={3}",
                         payload.context.requestId,
                         payload.response.response.responseType,
                         sizeof(payload.response.response.content),
                         toolCallCount);

            print format("LoggerMiddleware: Totals — requests={0} responses={1}",
                         totalRequests, totalResponses);

            // Always call next — logger never blocks.
            send pipeline, eMiddlewareNext, payload.context;
        }
    }
}
