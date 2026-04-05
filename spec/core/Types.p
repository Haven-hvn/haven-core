/**
 * Core type definitions for the Sovereign Agent kernel.
 *
 * Design principle: Only types required by the 5 core machines live here.
 * Extension-specific types belong in extensions/Types.p.
 */

// ============================================================================
// TYPE ALIASES — Semantic wrappers for readability
// ============================================================================

type MessageId   = string;
type SessionKey  = string;
type ToolName    = string;
type ChannelName = string;
type TokenSymbol = string;  // "ETH", "USDC", "AKT", "FIL", etc.
type Address     = string;  // Hex-encoded wallet address (0x...)
type Signature   = string;  // Hex-encoded cryptographic signature
type ChainId     = string;  // "ethereum", "solana", "akash", etc.

// ============================================================================
// ENUMS
// ============================================================================

// Tool execution outcome.
enum ToolStatus {
    SUCCESS,
    ERROR,
    TIMEOUT,
    NOT_FOUND,
    INSUFFICIENT_FUNDS  // Tool couldn't execute because cost check failed
}

// LLM response shape.
enum LLMResponseType {
    CONTENT,
    TOOL_CALLS,
    ERROR,
    RATE_LIMITED
}

// Treasury health — the survival gradient.
enum TreasuryState {
    FUNDED,     // Runway > 30 days — normal operation
    LOW,        // Runway 7-30 days — cost-conscious mode
    CRITICAL,   // Runway < 7 days — survival mode
    DEPLETED    // Cannot pay for next fixed cost cycle
}

// Wallet state — key lifecycle.
enum WalletState {
    LOCKED,     // Key exists but not loaded
    UNLOCKED,   // Key loaded, ready to sign
    SIGNING     // Actively signing a payload
}

// Signing request type.
enum SigningType {
    MESSAGE,      // Arbitrary message signing (EIP-191)
    TYPED_DATA,   // Structured data signing (EIP-712)
    TRANSACTION   // Raw transaction signing
}

// Budget category for expense tracking.
enum BudgetCategory {
    INFERENCE,       // LLM calls
    TOOLS,           // On-chain tool execution (gas)
    INFRASTRUCTURE,  // Compute, storage leases
    MESSAGING,       // Channel-specific costs (Solana memo fees, etc.)
    RESERVE          // Emergency funds — untouched except in CRITICAL
}

// ============================================================================
// CORE RECORDS
// ============================================================================

// Inbound message from any channel (extension-provided).
type InboundMessage = (
    id: MessageId,
    channel: ChannelName,
    senderId: string,
    chatId: string,
    content: string,
    timestamp: int,
    sessionKey: SessionKey,
    metadata: map[string, string]
);

// Outbound message to any channel.
type OutboundMessage = (
    channel: ChannelName,
    chatId: string,
    content: string,
    replyTo: MessageId,
    metadata: map[string, string]
);

// Tool call from LLM.
type ToolCall = (
    id: string,
    name: ToolName,
    arguments: map[string, string]
);

// Tool execution result.
type ToolResult = (
    callId: string,
    status: ToolStatus,
    result: string
);

// Tool definition — what the ToolExecutor knows about a registered tool.
type ToolDefinition = (
    name: ToolName,
    description: string,
    estimatedCost: CostEstimate  // How much this tool typically costs
);

// LLM response structure.
type LLMResponse = (
    responseType: LLMResponseType,
    content: string,
    toolCalls: seq[ToolCall],
    reasoning: string
);

// A cost in a specific token.
type TokenAmount = (
    token: TokenSymbol,
    amount: int           // In smallest unit (wei, lamports, etc.)
);

// Cost estimate for a pending action.
type CostEstimate = (
    amounts: seq[TokenAmount],
    category: BudgetCategory
);

// Balance on a single chain.
type ChainBalance = (
    chain: ChainId,
    token: TokenSymbol,
    amount: int,
    usdEstimate: int      // Approximate USD value × 1e6 for precision
);

// Budget allocation — percentage caps per category.
type BudgetAllocation = (
    inference: int,       // Percentage (0-100)
    tools: int,
    infrastructure: int,
    messaging: int,
    reserve: int          // Emergency reserve, untouched in FUNDED/LOW
);

// Expense record for the ledger.
type Expense = (
    timestamp: int,
    category: BudgetCategory,
    token: TokenSymbol,
    amount: int,
    description: string
);

// Signing request — what needs to be signed.
type SigningRequest = (
    id: string,
    signingType: SigningType,
    payload: string,       // Hex-encoded data to sign
    chain: ChainId,
    requestor: machine     // Who asked for the signature
);

// Signing result — the signature.
type SigningResult = (
    requestId: string,
    signature: Signature,
    success: bool,
    error: string
);

// Treasury report — snapshot of economic state.
type TreasuryReport = (
    state: TreasuryState,
    balances: seq[ChainBalance],
    totalValueUsd: int,       // USD × 1e6
    dailyBurnUsd: int,        // USD × 1e6
    runwayDays: int,
    budget: BudgetAllocation,
    recentExpenses: seq[Expense]
);
