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
