/**
 * Machine: InferencePipeline
 * Role: EXTENSION — The middleware runner for the inference path.
 * Layer: L6 (Reasoning) — sits on the inference path between AgentLoop and provider.
 *
 * Manages an ordered list of middleware machines and orchestrates the
 * onion-model execution for every LLM request/response cycle. This is the
 * P-language formalization of lmstudio-bridge's MiddlewareRunner + Engine.
 *
 * The pipeline is a transparent proxy: AgentLoop sends eLLMRequest to
 * the pipeline and receives eLLMResponse — identical interface to talking
 * directly to a provider.
 *
 * Design principles:
 *   - Transparent proxy: AgentLoop doesn't know the pipeline exists.
 *   - Shared context: A PipelineContext is created per request. Its metadata
 *     map is the inter-middleware communication channel.
 *   - Fail-closed: If a required middleware fails, the pipeline aborts.
 *   - Non-blocking persistence: Response middleware that performs I/O should
 *     use fire-and-forget patterns. The pipeline returns the response to
 *     AgentLoop immediately.
 *
 * States:
 *   Init → Ready → RunningRequestChain → AwaitingProvider →
 *   RunningResponseChain → Complete → Ready
 */

machine InferencePipeline {
    // The agent loop — receives eLLMResponse when pipeline completes.
    var agentLoop: machine;

    // The actual LLM provider — receives eLLMRequest after request middleware.
    var provider: machine;

    // Registered middleware, ordered by priority (lower = earlier in request chain).
    var middleware: seq[(name: MiddlewareName, handler: machine, priority: int)];

    // Current pipeline context for the active request.
    var currentContext: PipelineContext;

    // Current request being processed through the pipeline.
    var currentRequest: (sessionKey: SessionKey, messages: seq[map[string, string]],
                         tools: seq[ToolDefinition], requestor: machine,
                         estimatedCost: CostEstimate);

    // Current response being processed through the pipeline.
    var currentResponse: (sessionKey: SessionKey, response: LLMResponse);

    // Index into the middleware list for chain walking.
    var chainIndex: int;

    // Request counter for unique pipeline context IDs.
    var requestCounter: int;

    start state Init {
        entry (payload: (agentLoop: machine, provider: machine)) {
            agentLoop = payload.agentLoop;
            provider = payload.provider;
            middleware = default(seq[(name: MiddlewareName, handler: machine, priority: int)]);
            requestCounter = 0;

            print "InferencePipeline: Initialized — no middleware registered";
            goto Ready;
        }
    }

    // ========================================================================
    // Ready — Accepting middleware registrations and LLM requests
    // ========================================================================
    state Ready {
        entry {
            print format("InferencePipeline: Ready with {0} middleware", sizeof(middleware));
        }

        // --- Middleware registration ---

        on eRegisterMiddleware do (reg: (name: MiddlewareName, handler: machine, priority: int)) {
            // Insert middleware in priority order (lower priority = earlier position).
            // This maintains the invariant that middleware[0] runs first on request,
            // middleware[N-1] runs first on response (onion model).
            var inserted: bool;
            inserted = false;
            var i: int;
            i = 0;

            var newList: seq[(name: MiddlewareName, handler: machine, priority: int)];
            newList = default(seq[(name: MiddlewareName, handler: machine, priority: int)]);

            while (i < sizeof(middleware)) {
                if (!inserted && reg.priority < middleware[i].priority) {
                    newList += ((name = reg.name, handler = reg.handler, priority = reg.priority));
                    inserted = true;
                }
                newList += (middleware[i]);
                i = i + 1;
            }

            if (!inserted) {
                newList += ((name = reg.name, handler = reg.handler, priority = reg.priority));
            }

            middleware = newList;
            print format("InferencePipeline: Middleware registered — {0} (priority {1})",
                         reg.name, reg.priority);
        }

        on eUnregisterMiddleware do (name: MiddlewareName) {
            var newList: seq[(name: MiddlewareName, handler: machine, priority: int)];
            newList = default(seq[(name: MiddlewareName, handler: machine, priority: int)]);
            var i: int;
            i = 0;
            while (i < sizeof(middleware)) {
                if (middleware[i].name != name) {
                    newList += (middleware[i]);
                }
                i = i + 1;
            }
            middleware = newList;
            print format("InferencePipeline: Middleware unregistered — {0}", name);
        }

        // --- LLM request from AgentLoop ---

        on eLLMRequest do (req: (sessionKey: SessionKey, messages: seq[map[string, string]],
                                  tools: seq[ToolDefinition], requestor: machine,
                                  estimatedCost: CostEstimate)) {
            currentRequest = req;

            // Create a fresh pipeline context for this request.
            requestCounter = requestCounter + 1;
            currentContext = (
                requestId = format("pipeline:{0}", requestCounter),
                sessionKey = req.sessionKey,
                timestamp = 0,  // Implementation fills real timestamp
                metadata = default(map[string, string])
            );

            print format("InferencePipeline: Processing request {0} for session {1}",
                         currentContext.requestId, req.sessionKey);

            // If no middleware registered, pass through directly.
            if (sizeof(middleware) == 0) {
                send provider, eLLMRequest, req;
                goto AwaitingProvider;
            }

            // Start the request middleware chain.
            chainIndex = 0;
            goto RunningRequestChain;
        }
    }

    // ========================================================================
    // RunningRequestChain — Walk middleware in priority order (forward)
    // ========================================================================
    state RunningRequestChain {
        entry {
            if (chainIndex >= sizeof(middleware)) {
                // All request middleware done — forward to provider.
                send provider, eLLMRequest, currentRequest;
                goto AwaitingProvider;
            }

            // Send eMiddlewareRequest to the current middleware handler.
            print format("InferencePipeline: Request chain [{0}/{1}] → {2}",
                         chainIndex + 1, sizeof(middleware), middleware[chainIndex].name);
            send middleware[chainIndex].handler, eMiddlewareRequest, (
                context = currentContext,
                request = currentRequest
            );
        }

        on eMiddlewareNext do (ctx: PipelineContext) {
            // Middleware called next() — update context and advance.
            currentContext = ctx;
            chainIndex = chainIndex + 1;

            if (chainIndex >= sizeof(middleware)) {
                // All request middleware done — forward to provider.
                send provider, eLLMRequest, currentRequest;
                goto AwaitingProvider;
            }

            // Send to the next middleware.
            print format("InferencePipeline: Request chain [{0}/{1}] → {2}",
                         chainIndex + 1, sizeof(middleware), middleware[chainIndex].name);
            send middleware[chainIndex].handler, eMiddlewareRequest, (
                context = currentContext,
                request = currentRequest
            );
        }

        on eMiddlewareError do (err: (middleware: MiddlewareName, error: string, context: PipelineContext)) {
            // Middleware failed — abort the pipeline and return error to AgentLoop.
            print format("InferencePipeline: Request middleware {0} failed — {1}",
                         err.middleware, err.error);

            var errorResponse: LLMResponse;
            errorResponse = (
                responseType = ERROR,
                content = format("Pipeline error in {0}: {1}", err.middleware, err.error),
                toolCalls = default(seq[ToolCall]),
                reasoning = ""
            );
            send agentLoop, eLLMResponse, (
                sessionKey = currentRequest.sessionKey,
                response = errorResponse
            );
            goto Ready;
        }
    }

    // ========================================================================
    // AwaitingProvider — Waiting for the actual LLM response
    // ========================================================================
    state AwaitingProvider {
        entry {
            print "InferencePipeline: Awaiting provider response";
        }

        on eLLMResponse do (resp: (sessionKey: SessionKey, response: LLMResponse)) {
            currentResponse = resp;

            // If no middleware registered, pass through directly.
            if (sizeof(middleware) == 0) {
                send agentLoop, eLLMResponse, resp;
                goto Ready;
            }

            // Start the response middleware chain in REVERSE order (onion model).
            chainIndex = sizeof(middleware) - 1;
            goto RunningResponseChain;
        }

        on eLLMProviderError do (err: (provider: string, error: string)) {
            // Provider failed — return error to AgentLoop.
            print format("InferencePipeline: Provider error — {0}: {1}",
                         err.provider, err.error);
            var errorResponse: LLMResponse;
            errorResponse = (
                responseType = ERROR,
                content = format("Provider error: {0}", err.error),
                toolCalls = default(seq[ToolCall]),
                reasoning = ""
            );
            send agentLoop, eLLMResponse, (
                sessionKey = currentRequest.sessionKey,
                response = errorResponse
            );
            goto Ready;
        }
    }

    // ========================================================================
    // RunningResponseChain — Walk middleware in REVERSE priority order
    // ========================================================================
    state RunningResponseChain {
        entry {
            if (chainIndex < 0) {
                // All response middleware done — forward to AgentLoop.
                goto Complete;
            }

            // Send eMiddlewareResponse to the current middleware handler.
            print format("InferencePipeline: Response chain [{0}/{1}] → {2}",
                         sizeof(middleware) - chainIndex, sizeof(middleware),
                         middleware[chainIndex].name);
            send middleware[chainIndex].handler, eMiddlewareResponse, (
                context = currentContext,
                response = currentResponse
            );
        }

        on eMiddlewareNext do (ctx: PipelineContext) {
            // Middleware called next() — update context and advance (reverse).
            currentContext = ctx;
            chainIndex = chainIndex - 1;

            if (chainIndex < 0) {
                // All response middleware done.
                goto Complete;
            }

            // Send to the next middleware (reverse order).
            print format("InferencePipeline: Response chain [{0}/{1}] → {2}",
                         sizeof(middleware) - chainIndex, sizeof(middleware),
                         middleware[chainIndex].name);
            send middleware[chainIndex].handler, eMiddlewareResponse, (
                context = currentContext,
                response = currentResponse
            );
        }

        on eMiddlewareError do (err: (middleware: MiddlewareName, error: string, context: PipelineContext)) {
            // Response middleware failed — log but still return the response.
            // Response middleware errors are non-fatal: the LLM already responded,
            // we just couldn't process it through all middleware.
            print format("InferencePipeline: Response middleware {0} failed — {1} (non-fatal)",
                         err.middleware, err.error);

            // Skip this middleware and continue the chain.
            chainIndex = chainIndex - 1;
            if (chainIndex < 0) {
                goto Complete;
            }
            send middleware[chainIndex].handler, eMiddlewareResponse, (
                context = currentContext,
                response = currentResponse
            );
        }
    }

    // ========================================================================
    // Complete — Forward final response to AgentLoop and return to Ready
    // ========================================================================
    state Complete {
        entry {
            print format("InferencePipeline: Complete — returning response for {0}",
                         currentResponse.sessionKey);
            send agentLoop, eLLMResponse, currentResponse;
            goto Ready;
        }
    }
}
