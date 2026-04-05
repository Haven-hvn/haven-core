/**
 * Machine: AgentLoop
 * Role: CORE — The cost-aware reasoning engine.
 *
 * Processes inbound messages, interacts with LLM providers (via events),
 * executes tools (via ToolExecutor), and manages the iterative
 * think→tool→think loop. Every LLM call and tool call is cost-gated
 * through Treasury.
 *
 * Design principle: The loop is minimal. It does not know about sessions,
 * memory consolidation, or scheduling — those are extension concerns
 * (SessionManager, CronService, HeartbeatService). The loop knows:
 *   1. Receive message
 *   2. Ask Treasury if we can afford inference
 *   3. Call LLM
 *   4. If tool calls → execute via ToolExecutor (which cost-gates)
 *   5. Repeat until content response or budget exhausted
 *   6. Publish response
 *
 * Session persistence, compaction, heartbeat tasks, and slash command
 * handling beyond /stop are all extension concerns. The core loop only
 * handles /stop because it's the emergency brake.
 */

machine AgentLoop {
    // Core dependencies (injected at creation).
    var bus: machine;
    var provider: machine;         // LLM provider (extension-provided)
    var toolExecutor: machine;
    var treasury: machine;
    var wallet: machine;

    // Configuration.
    var maxIterations: int;

    // Runtime state.
    var running: bool;
    var activeSessions: set[SessionKey];

    start state Init {
        entry (payload: (bus: machine, provider: machine, toolExecutor: machine,
                        treasury: machine, wallet: machine)) {
            bus = payload.bus;
            provider = payload.provider;
            toolExecutor = payload.toolExecutor;
            treasury = payload.treasury;
            wallet = payload.wallet;

            maxIterations = 40;
            running = false;
            activeSessions = default(set[SessionKey]);

            print "AgentLoop: Initialized";
            goto Idle;
        }
    }

    state Idle {
        entry {
            running = true;
            print "AgentLoop: Waiting for messages";
        }

        on eStart do {
            running = true;
        }

        on eStop do {
            running = false;
            raise halt;
        }

        on eInboundMessage do (msg: InboundMessage) {
            print format("AgentLoop: Received from {0}:{1}", msg.channel, msg.senderId);

            // The only slash command the core handles is /stop (emergency brake).
            // All other commands are extension concerns.
            if (IsSlashCommand(msg.content)) {
                var cmd: string;
                cmd = ParseCommand(msg.content);
                if (cmd == "/stop") {
                    send this, eStopProcessing, msg.sessionKey;
                    return;
                }
                // All other commands pass through to the LLM as normal messages.
                // Extensions can intercept via the bus if they want to handle them.
            }

            // Add to active sessions.
            activeSessions += (msg.sessionKey);

            // Transition to cost-checking before inference.
            goto CostChecking, msg;
        }

        on eStopProcessing do (sessionKey: SessionKey) {
            activeSessions -= (sessionKey);
            print format("AgentLoop: Stopped processing {0}", sessionKey);
        }

        on eError do (err: string) {
            print format("AgentLoop: Error — {0}", err);
        }
    }

    // ========================================================================
    // CostChecking — Ask treasury if we can afford an LLM call
    // ========================================================================
    state CostChecking {
        var currentMessage: InboundMessage;
        var costAuthId: string;

        entry (msg: InboundMessage) {
            currentMessage = msg;

            // Estimate inference cost.
            var estimate: CostEstimate;
            estimate = (
                amounts = default(seq[TokenAmount]),
                category = INFERENCE
            );
            // Add a nominal cost estimate (real implementation uses model pricing).
            var tokenCost: TokenAmount;
            tokenCost = (token = "USDC", amount = 5000);  // ~$0.005 in smallest units
            estimate.amounts += (tokenCost);

            costAuthId = format("llm:{0}", msg.id);

            send treasury, eCostAuthorize, (
                requestId = costAuthId,
                estimate = estimate,
                requestor = this
            );
        }

        on eCostAuthorized do (auth: (requestId: string, approved: bool, reason: string)) {
            if (auth.requestId != costAuthId) {
                return;  // Not our authorization
            }

            if (!auth.approved) {
                // Can't afford inference — send a degraded response.
                print format("AgentLoop: Inference denied — {0}", auth.reason);
                var lowFundsResponse: OutboundMessage;
                lowFundsResponse = (
                    channel = currentMessage.channel,
                    chatId = currentMessage.chatId,
                    content = "I'm currently low on funds and cannot process this request.",
                    replyTo = currentMessage.id,
                    metadata = default(map[string, string])
                );
                send bus, ePublishOutbound, lowFundsResponse;
                activeSessions -= (currentMessage.sessionKey);
                goto Idle;
            }

            // Authorized — proceed to LLM iteration.
            goto Iterating, currentMessage;
        }

        on eStopProcessing do (sessionKey: SessionKey) {
            activeSessions -= (sessionKey);
            goto Idle;
        }
    }

    // ========================================================================
    // Iterating — The LLM tool-call loop
    // ========================================================================
    state Iterating {
        var currentMessage: InboundMessage;
        var iteration: int;
        var toolsUsed: seq[ToolName];
        var pendingToolResults: int;

        entry (msg: InboundMessage) {
            currentMessage = msg;
            iteration = 0;
            toolsUsed = default(seq[ToolName]);
            pendingToolResults = 0;

            // Send LLM request.
            SendLLMRequest();
        }

        on eLLMResponse do (resp: (sessionKey: SessionKey, response: LLMResponse)) {
            if (resp.response.responseType == TOOL_CALLS) {
                iteration = iteration + 1;

                if (iteration >= maxIterations) {
                    print "AgentLoop: Max iterations reached";
                    send this, eMaxIterationsReached, currentMessage.sessionKey;
                    goto Responding, "Maximum iterations reached. Please try a simpler request.";
                }

                // Execute tool calls via ToolExecutor (which handles cost gating).
                var i: int;
                i = 0;
                pendingToolResults = sizeof(resp.response.toolCalls);
                while (i < sizeof(resp.response.toolCalls)) {
                    toolsUsed += (resp.response.toolCalls[i].name);
                    send toolExecutor, eExecuteTool, (
                        call = resp.response.toolCalls[i],
                        sessionKey = currentMessage.sessionKey
                    );
                    i = i + 1;
                }
            } else if (resp.response.responseType == CONTENT) {
                // Final content response.
                goto Responding, resp.response.content;
            } else if (resp.response.responseType == ERROR) {
                goto Responding, "An error occurred while processing your request.";
            } else if (resp.response.responseType == RATE_LIMITED) {
                // Rate limited — could retry or respond.
                goto Responding, "I'm currently rate limited. Please try again shortly.";
            }
        }

        on eToolResult do (result: ToolResult) {
            print format("AgentLoop: Tool {0} → {1}", result.callId, result.status);
            pendingToolResults = pendingToolResults - 1;

            // Once all tool results are in, do another LLM iteration.
            if (pendingToolResults <= 0) {
                SendLLMRequest();
            }
        }

        on eStopProcessing do (sessionKey: SessionKey) {
            activeSessions -= (sessionKey);
            goto Idle;
        }

        fun SendLLMRequest() {
            var estimate: CostEstimate;
            estimate = (
                amounts = default(seq[TokenAmount]),
                category = INFERENCE
            );

            send provider, eLLMRequest, (
                sessionKey = currentMessage.sessionKey,
                messages = default(seq[map[string, string]]),
                tools = default(seq[map[string, string]]),
                requestor = this,
                estimatedCost = estimate
            );
        }
    }

    // ========================================================================
    // Responding — Send the final response and return to idle
    // ========================================================================
    state Responding {
        var responseContent: string;
        var currentMessage: InboundMessage;

        entry (content: string) {
            responseContent = content;

            var response: OutboundMessage;
            response = (
                channel = currentMessage.channel,
                chatId = currentMessage.chatId,
                content = responseContent,
                replyTo = currentMessage.id,
                metadata = default(map[string, string])
            );

            send bus, ePublishOutbound, response;

            // Record inference expense.
            var expense: Expense;
            expense = (
                timestamp = 0,
                category = INFERENCE,
                token = "USDC",
                amount = 5000,
                description = format("LLM response for {0}", currentMessage.sessionKey)
            );
            send treasury, eExpenseRecord, expense;

            // Signal completion.
            send this, eMessageProcessed, response;

            activeSessions -= (currentMessage.sessionKey);
            goto Idle;
        }
    }
}
