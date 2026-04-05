/**
 * Machine: ToolExecutor
 * Role: CORE — Pluggable tool execution with cost gating.
 *
 * Tools are the agent's hands. Every tool is registered dynamically via
 * eToolRegister events — there are NO hardcoded tools in the core. The
 * executor validates that the tool exists, requests cost authorization
 * from Treasury, and then delegates to the tool's handler.
 *
 * Design principle: The executor is a registry + cost gate + dispatcher.
 * It knows nothing about what tools do. File I/O, web search, on-chain
 * transactions, memory operations — all are extensions that register
 * themselves. This follows pi-mono's philosophy: if it doesn't belong
 * in the core, it's an extension.
 */

machine ToolExecutor {
    // Registered tool definitions.
    var tools: map[ToolName, ToolDefinition];

    // Tool handler machines (the actual executors).
    var handlers: map[ToolName, machine];

    // Reference to treasury for cost authorization.
    var treasury: machine;

    // Reference to agent for returning results.
    var agent: machine;

    // Pending cost authorization requests.
    var pendingAuths: map[string, (call: ToolCall, sessionKey: SessionKey)];

    start state Init {
        entry (payload: (treasury: machine, agent: machine)) {
            treasury = payload.treasury;
            agent = payload.agent;
            tools = default(map[ToolName, ToolDefinition]);
            handlers = default(map[ToolName, machine]);
            pendingAuths = default(map[string, (call: ToolCall, sessionKey: SessionKey)]);

            print "ToolExecutor: Initialized — no tools registered (extensions provide tools)";
            goto Ready;
        }
    }

    state Ready {
        entry {
            // Deliberately empty — just waiting for events.
        }

        // --- Tool registration (extension plug-in point) ---

        on eToolRegister do (def: ToolDefinition) {
            tools[def.name] = def;
            // Handler registration happens via a separate mechanism:
            // the extension sends eToolRegister and then handles eExecuteTool
            // for its own tools. For model checking, we use self as handler.
            handlers[def.name] = this;
            print format("ToolExecutor: Tool registered — {0}", def.name);
        }

        on eToolUnregister do (name: ToolName) {
            if (name in tools) {
                tools -= (name);
                handlers -= (name);
                print format("ToolExecutor: Tool unregistered — {0}", name);
            }
        }

        // --- Tool execution request (from AgentLoop) ---

        on eExecuteTool do (req: (call: ToolCall, sessionKey: SessionKey)) {
            var toolName: ToolName;
            toolName = req.call.name;

            // Check if tool is registered.
            if (!(toolName in tools)) {
                var result: ToolResult;
                result = (
                    callId = req.call.id,
                    status = NOT_FOUND,
                    result = format("Tool '{0}' not registered", toolName)
                );
                send agent, eToolResult, result;
                return;
            }

            // Request cost authorization from Treasury.
            var costEstimate: CostEstimate;
            costEstimate = tools[toolName].estimatedCost;

            var authId: string;
            authId = format("tool:{0}:{1}", toolName, req.call.id);

            // Store pending request.
            pendingAuths[authId] = req;

            send treasury, eCostAuthorize, (
                requestId = authId,
                estimate = costEstimate,
                requestor = this
            );
        }

        // --- Cost authorization response ---

        on eCostAuthorized do (auth: (requestId: string, approved: bool, reason: string)) {
            if (!(auth.requestId in pendingAuths)) {
                return;  // Stale or unknown authorization
            }

            var req: (call: ToolCall, sessionKey: SessionKey);
            req = pendingAuths[auth.requestId];
            pendingAuths -= (auth.requestId);

            if (!auth.approved) {
                // Cost denied — return INSUFFICIENT_FUNDS.
                var result: ToolResult;
                result = (
                    callId = req.call.id,
                    status = INSUFFICIENT_FUNDS,
                    result = format("Cost denied: {0}", auth.reason)
                );
                send agent, eToolResult, result;
                return;
            }

            // Authorized — execute the tool.
            goto Executing, req;
        }

        on eError do (err: string) {
            print format("ToolExecutor: Error — {0}", err);
        }
    }

    state Executing {
        var currentCall: ToolCall;
        var currentSessionKey: SessionKey;

        entry (req: (call: ToolCall, sessionKey: SessionKey)) {
            currentCall = req.call;
            currentSessionKey = req.sessionKey;

            print format("ToolExecutor: Executing {0}", currentCall.name);

            // Execute tool logic.
            // In reality, this delegates to the handler machine.
            // For model checking, simulate execution.
            var execResult: string;
            execResult = SimulateToolExecution(currentCall);

            var result: ToolResult;
            result = (
                callId = currentCall.id,
                status = SUCCESS,
                result = execResult
            );

            send agent, eToolResult, result;

            // Record expense.
            if (currentCall.name in tools) {
                var def: ToolDefinition;
                def = tools[currentCall.name];
                var i: int;
                i = 0;
                while (i < sizeof(def.estimatedCost.amounts)) {
                    var expense: Expense;
                    expense = (
                        timestamp = 0,
                        category = def.estimatedCost.category,
                        token = def.estimatedCost.amounts[i].token,
                        amount = def.estimatedCost.amounts[i].amount,
                        description = format("Tool: {0}", currentCall.name)
                    );
                    send treasury, eExpenseRecord, expense;
                    i = i + 1;
                }
            }

            goto Ready;
        }
    }

    fun SimulateToolExecution(call: ToolCall): string {
        // Placeholder for model checking.
        return format("Executed {0}", call.name);
    }
}
