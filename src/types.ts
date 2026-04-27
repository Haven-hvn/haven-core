/**
 * Core type definitions for the Sovereign Agent kernel.
 * 
 * Direct TypeScript translation of src/Types.p
 * 
 * Design principle: Only types required by the 5 core machines live here.
 * Extension-specific types belong in their own modules.
 */

// ============================================================================
// TYPE ALIASES — Semantic wrappers for readability
// ============================================================================

export type MessageId = string;
export type SessionKey = string;
export type ToolName = string;
export type ChannelName = string;
export type TokenSymbol = string;  // "ETH", "USDC", "AKT", "FIL", etc.
export type Address = string;      // Hex-encoded wallet address (0x...)
export type Signature = string;    // Hex-encoded cryptographic signature
export type ChainId = string;      // "ethereum", "solana", "akash", etc.
export type CID = string;          // Content identifier (IPFS/IPLD content-addressed hash)
export type DPID = string;         // Decentralized Persistent Identifier (versioned, resolvable)
export type MiddlewareName = string; // Human-readable middleware identifier

// ============================================================================
// ENUMS
// ============================================================================

/** Tool execution outcome. */
export enum ToolStatus {
  SUCCESS = "SUCCESS",
  ERROR = "ERROR",
  TIMEOUT = "TIMEOUT",
  NOT_FOUND = "NOT_FOUND",
  INSUFFICIENT_FUNDS = "INSUFFICIENT_FUNDS",
}

/** LLM response shape. */
export enum LLMResponseType {
  CONTENT = "CONTENT",
  TOOL_CALLS = "TOOL_CALLS",
  ERROR = "ERROR",
  RATE_LIMITED = "RATE_LIMITED",
}

/** Treasury health — the survival gradient. */
export enum TreasuryState {
  FUNDED = "FUNDED",       // Runway > 30 days — normal operation
  LOW = "LOW",             // Runway 7-30 days — cost-conscious mode
  CRITICAL = "CRITICAL",   // Runway < 7 days — survival mode
  DEPLETED = "DEPLETED",   // Cannot pay for next fixed cost cycle
}

/** Wallet state — key lifecycle. */
export enum WalletState {
  LOCKED = "LOCKED",       // Key exists but not loaded
  UNLOCKED = "UNLOCKED",   // Key loaded, ready to sign
  SIGNING = "SIGNING",     // Actively signing a payload
}

/** Signing request type. */
export enum SigningType {
  MESSAGE = "MESSAGE",         // Arbitrary message signing (EIP-191)
  TYPED_DATA = "TYPED_DATA",   // Structured data signing (EIP-712)
  TRANSACTION = "TRANSACTION", // Raw transaction signing
}

/** Budget category for expense tracking. */
export enum BudgetCategory {
  INFERENCE = "INFERENCE",             // LLM calls
  TOOLS = "TOOLS",                     // On-chain tool execution (gas)
  INFRASTRUCTURE = "INFRASTRUCTURE",   // Compute leases
  STORAGE = "STORAGE",                 // IPFS pinning, Filecoin deals, persistence costs
  MESSAGING = "MESSAGING",             // Channel-specific costs
  RESERVE = "RESERVE",                 // Emergency funds — untouched except in CRITICAL
}

/** Which stage of the inference pipeline a middleware event relates to. */
export enum MiddlewareStage {
  REQUEST = "REQUEST",     // Before LLM call (forward order)
  RESPONSE = "RESPONSE",  // After LLM response (reverse order)
}

// ============================================================================
// CORE RECORDS
// ============================================================================

/** Inbound message from any channel (extension-provided). */
export interface InboundMessage {
  id: MessageId;
  channel: ChannelName;
  senderId: string;
  chatId: string;
  content: string;
  timestamp: number;
  sessionKey: SessionKey;
  metadata: Record<string, string>;
}

/** Outbound message to any channel. */
export interface OutboundMessage {
  channel: ChannelName;
  chatId: string;
  content: string;
  replyTo: MessageId;
  metadata: Record<string, string>;
}

/** Tool call from LLM. */
export interface ToolCall {
  id: string;
  name: ToolName;
  arguments: Record<string, string>;
}

/** Tool execution result. */
export interface ToolResult {
  callId: string;
  status: ToolStatus;
  result: string;
}

/** Tool definition — what the ToolExecutor knows about a registered tool. */
export interface ToolDefinition {
  name: ToolName;
  description: string;
  estimatedCost: CostEstimate;
}

/** LLM response structure. */
export interface LLMResponse {
  responseType: LLMResponseType;
  content: string;
  toolCalls: ToolCall[];
  reasoning: string;
}

/** A cost in a specific token. */
export interface TokenAmount {
  token: TokenSymbol;
  amount: number;  // In smallest unit (wei, lamports, etc.)
}

/** Cost estimate for a pending action. */
export interface CostEstimate {
  amounts: TokenAmount[];
  category: BudgetCategory;
}

/** Balance on a single chain. */
export interface ChainBalance {
  chain: ChainId;
  token: TokenSymbol;
  amount: number;
  usdEstimate: number;  // Approximate USD value × 1e6 for precision
}

/** Budget allocation — percentage caps per category. */
export interface BudgetAllocation {
  inference: number;       // Percentage (0-100)
  tools: number;
  infrastructure: number;
  storage: number;         // IPFS pinning, Filecoin deals
  messaging: number;
  reserve: number;         // Emergency reserve, untouched in FUNDED/LOW
}

/** Expense record for the ledger. */
export interface Expense {
  timestamp: number;
  category: BudgetCategory;
  token: TokenSymbol;
  amount: number;
  description: string;
}

/** Signing request — what needs to be signed. */
export interface SigningRequest {
  id: string;
  signingType: SigningType;
  payload: string;       // Hex-encoded data to sign
  chain: ChainId;
  requestor: string;     // Machine ID of who asked for the signature
}

/** Signing result — the signature. */
export interface SigningResult {
  requestId: string;
  signature: Signature;
  success: boolean;
  error: string;
}

/** Treasury report — snapshot of economic state. */
export interface TreasuryReport {
  state: TreasuryState;
  balances: ChainBalance[];
  totalValueUsd: number;      // USD × 1e6
  dailyBurnUsd: number;       // USD × 1e6
  runwayDays: number;
  budget: BudgetAllocation;
  recentExpenses: Expense[];
}

// ============================================================================
// MIDDLEWARE PIPELINE RECORDS
// ============================================================================

/**
 * Shared mutable context flowing through the middleware chain.
 * Mirrors lmstudio-bridge's ShimContext. The metadata map is the
 * inter-middleware communication channel — one middleware writes a key,
 * the next reads it (e.g., "compressedBuffer", "encryptedBuffer").
 */
export interface PipelineContext {
  requestId: string;                    // Unique per inference call
  sessionKey: SessionKey;               // Session this inference belongs to
  timestamp: number;                    // When the pipeline was entered
  metadata: Record<string, string>;     // Inter-middleware data channel
}

/**
 * A specific version of the agent's dPID pointing to a CID.
 * Used in dPID resolution and update events.
 */
export interface DPIDVersion {
  dpid: DPID;
  cid: CID;
  version: number;
  timestamp: number;
}
