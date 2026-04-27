/**
 * Core event declarations for the Sovereign Agent kernel.
 *
 * Design principle: Only events consumed or produced by the 5 core machines.
 * Extension events live in extensions/Events.p. The MessageBus routes all
 * events — core and extension — without knowing their semantics.
 */

// ============================================================================
// MESSAGE BUS EVENTS — The universal routing layer
// ============================================================================

// Publish a message into the bus (from channels or internal sources).
event ePublishInbound: InboundMessage;

// Publish an outbound message (agent → channels).
event ePublishOutbound: OutboundMessage;

// Delivered to the agent loop when an inbound message is ready.
event eInboundMessage: InboundMessage;

// Delivered to a channel when an outbound message targets it.
event eOutboundMessage: OutboundMessage;

// ============================================================================
// AGENT LOOP EVENTS — Reasoning engine lifecycle
// ============================================================================

// Trigger the agent to process a message.
event eProcessMessage: InboundMessage;

// Agent finished processing — response ready.
event eMessageProcessed: OutboundMessage;

// Agent hit iteration limit for a session.
event eMaxIterationsReached: SessionKey;

// Agent explicitly stopped processing.
event eStopProcessing: SessionKey;

// ============================================================================
// TOOL EXECUTION EVENTS — Pluggable tool system
// ============================================================================

// Register a tool with the executor (extensions call this to add tools).
event eToolRegister: ToolDefinition;

// Unregister a tool.
event eToolUnregister: ToolName;

// Request tool execution (from AgentLoop).
event eExecuteTool: (call: ToolCall, sessionKey: SessionKey);

// Tool execution result (back to AgentLoop).
event eToolResult: ToolResult;

// ============================================================================
// LLM PROVIDER EVENTS — Extension-provided inference
// ============================================================================

// Request LLM completion (AgentLoop → any registered provider).
event eLLMRequest: (
    sessionKey: SessionKey,
    messages: seq[map[string, string]],
    tools: seq[ToolDefinition],
    requestor: machine,
    estimatedCost: CostEstimate
);

// LLM response (provider → AgentLoop).
event eLLMResponse: (sessionKey: SessionKey, response: LLMResponse);

// Provider failed — extension can emit this to signal degradation.
event eLLMProviderError: (provider: string, error: string);

// ============================================================================
// WALLET IDENTITY EVENTS — Crypto signing lifecycle
// ============================================================================

// Unlock the wallet (load private key from secure source).
event eUnlockWallet: string;  // Key source identifier

// Lock the wallet (clear key from memory).
event eLockWallet;

// Request a signature.
event eSignRequest: SigningRequest;

// Signature result.
event eSignResult: SigningResult;

// Get the wallet's public address.
event eGetAddress;

// Address response.
event eAddressResult: Address;

// ============================================================================
// TREASURY EVENTS — Economic lifecycle
// ============================================================================

// Periodic balance check trigger.
event eBalanceCheck;

// Balance update (from chain queries — provided by extensions).
event eBalanceUpdate: seq[ChainBalance];

// Request cost authorization before an action.
event eCostAuthorize: (requestId: string, estimate: CostEstimate, requestor: machine);

// Authorization response.
event eCostAuthorized: (requestId: string, approved: bool, reason: string);

// Record an expense after action completes.
event eExpenseRecord: Expense;

// Treasury state changed (threshold crossed).
event eTreasuryStateChanged: (previous: TreasuryState, current: TreasuryState);

// Request treasury report.
event eTreasuryReportRequest;

// Treasury report response.
event eTreasuryReport: TreasuryReport;

// ============================================================================
// MIDDLEWARE PIPELINE EVENTS — Generic inference interception
// ============================================================================
// These events define the abstract middleware pipeline. The core knows that
// inference can flow through middleware, but knows nothing about what any
// specific middleware does. Mirrors lmstudio-bridge's MiddlewareRunner pattern.

// Register a middleware with the inference pipeline.
// priority determines execution order (lower = earlier in request chain,
// later in response chain). Mirrors MiddlewareRunner.use().
event eRegisterMiddleware: (name: MiddlewareName, handler: machine, priority: int);

// Remove a middleware from the pipeline.
event eUnregisterMiddleware: MiddlewareName;

// Dispatched to each middleware's onRequest handler in priority order.
// Middleware can mutate the context metadata map.
event eMiddlewareRequest: (context: PipelineContext, request: (
    sessionKey: SessionKey,
    messages: seq[map[string, string]],
    tools: seq[ToolDefinition],
    requestor: machine,
    estimatedCost: CostEstimate
));

// Dispatched to each middleware's onResponse handler in reverse priority order.
// Middleware can mutate the context metadata map.
event eMiddlewareResponse: (context: PipelineContext, response: (
    sessionKey: SessionKey,
    response: LLMResponse
));

// Middleware signals it's done — advance to the next middleware in the chain.
// Equivalent to calling next() in lmstudio-bridge.
event eMiddlewareNext: PipelineContext;

// A middleware failed. The pipeline decides whether to continue or abort.
event eMiddlewareError: (middleware: MiddlewareName, error: string, context: PipelineContext);

// ============================================================================
// dPID / MEMORY EVENTS — Identity-bound persistent memory
// ============================================================================
// These events support the identity-bound persistence layer. They are consumed
// by extensions (dPID resolver, persistence middleware), with WalletIdentity
// participating for dPID awareness and signing.

// Resolve the agent's dPID to get the current root CID on boot.
event eResolveDPID: DPID;

// Response carrying the current CID and version.
event eDPIDResolved: DPIDVersion;

// Request to update the agent's dPID to a new root CID.
// Requires WalletIdentity signature.
event eUpdateDPID: (newCid: CID, requestor: machine);

// Confirmation that the dPID was updated.
event eDPIDUpdated: DPIDVersion;

// Request to restore agent state from a specific CID. Used during boot.
event eMemoryRestore: CID;

// Confirmation that memory was restored.
event eMemoryRestored: (success: bool, sessionCount: int);

// ============================================================================
// EXTENSION REGISTRATION EVENTS — Plugin system
// ============================================================================

// Register a channel with the message bus.
event eRegisterChannel: (name: ChannelName, handler: machine);

// Unregister a channel.
event eUnregisterChannel: ChannelName;

// Register an LLM provider.
event eRegisterProvider: (name: string, handler: machine);

// Register a storage backend (extension-defined semantics).
event eRegisterStorage: (name: string, handler: machine);

// Register an infrastructure provider.
event eRegisterInfrastructure: (name: string, handler: machine);

// ============================================================================
// LIFECYCLE EVENTS — System control
// ============================================================================

event eStart;
event eStop;
event eError: string;
event eShutdownComplete;
