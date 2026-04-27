/**
 * Core event declarations for the Sovereign Agent kernel.
 * 
 * Direct TypeScript translation of src/Events.p
 * 
 * Design principle: Only events consumed or produced by the 5 core machines.
 * Extension events live in their own modules. The MessageBus routes all
 * events — core and extension — without knowing their semantics.
 */

import type {
  InboundMessage,
  OutboundMessage,
  ToolDefinition,
  ToolName,
  ToolCall,
  ToolResult,
  ToolStatus,
  SessionKey,
  CostEstimate,
  Expense,
  ChainBalance,
  TreasuryState,
  TreasuryReport,
  SigningRequest,
  SigningResult,
  Address,
  ChannelName,
  LLMResponse,
  MiddlewareName,
  PipelineContext,
  CID,
  DPID,
  DPIDVersion,
} from "./types.js";

// ============================================================================
// EVENT MAP — Type-safe event definitions
// ============================================================================

export interface EventMap {
  // --- Message Bus Events ---
  ePublishInbound: InboundMessage;
  ePublishOutbound: OutboundMessage;
  eInboundMessage: InboundMessage;
  eOutboundMessage: OutboundMessage;

  // --- Agent Loop Events ---
  eProcessMessage: InboundMessage;
  eMessageProcessed: OutboundMessage;
  eMaxIterationsReached: SessionKey;
  eStopProcessing: SessionKey;

  // --- Tool Execution Events ---
  eToolRegister: ToolDefinition;
  eToolUnregister: ToolName;
  eExecuteTool: { call: ToolCall; sessionKey: SessionKey };
  eToolResult: ToolResult;

  // --- LLM Provider Events ---
  eLLMRequest: {
    sessionKey: SessionKey;
    messages: Record<string, string>[];
    tools: ToolDefinition[];
    requestor: string;  // Machine ID
    estimatedCost: CostEstimate;
  };
  eLLMResponse: { sessionKey: SessionKey; response: LLMResponse };
  eLLMProviderError: { provider: string; error: string };

  // --- Wallet Identity Events ---
  eUnlockWallet: string;
  eLockWallet: void;
  eSignRequest: SigningRequest;
  eSignResult: SigningResult;
  eGetAddress: void;
  eAddressResult: Address;

  // --- Treasury Events ---
  eBalanceCheck: void;
  eBalanceUpdate: ChainBalance[];
  eCostAuthorize: { requestId: string; estimate: CostEstimate; requestor: string };
  eCostAuthorized: { requestId: string; approved: boolean; reason: string };
  eExpenseRecord: Expense;
  eTreasuryStateChanged: { previous: TreasuryState; current: TreasuryState };
  eTreasuryReportRequest: void;
  eTreasuryReport: TreasuryReport;

  // --- Middleware Pipeline Events ---
  // Abstract middleware pipeline — core knows inference CAN flow through
  // middleware, but knows nothing about what any specific middleware does.
  // Mirrors lmstudio-bridge's MiddlewareRunner pattern.
  eRegisterMiddleware: { name: MiddlewareName; handler: string; priority: number };
  eUnregisterMiddleware: MiddlewareName;
  eMiddlewareRequest: { context: PipelineContext; request: {
    sessionKey: SessionKey;
    messages: Record<string, string>[];
    tools: ToolDefinition[];
    requestor: string;
    estimatedCost: CostEstimate;
  }};
  eMiddlewareResponse: { context: PipelineContext; response: {
    sessionKey: SessionKey;
    response: LLMResponse;
  }};
  eMiddlewareNext: PipelineContext;
  eMiddlewareError: { middleware: MiddlewareName; error: string; context: PipelineContext };

  // --- dPID / Memory Events ---
  // Identity-bound persistent memory. Consumed by extensions (dPID resolver,
  // persistence middleware), with WalletIdentity participating for dPID
  // awareness and signing.
  eResolveDPID: DPID;
  eDPIDResolved: DPIDVersion;
  eUpdateDPID: { newCid: CID; requestor: string };
  eDPIDUpdated: DPIDVersion;
  eMemoryRestore: CID;
  eMemoryRestored: { success: boolean; sessionCount: number };

  // --- Storage Events (Layer 2) ---
  // StorageBackend machine at Layer 2 handles all IPFS/persistence I/O.
  // Higher-layer machines (PersistenceMiddleware, StoragePinManager) send
  // these events instead of holding keys or calling storage SDKs directly.
  eStoreData: { data: string; requestor: string; requestId: string };
  eDataStored: { cid: CID; requestId: string };
  eRetrieveData: { cid: CID; requestor: string; requestId: string };
  eDataRetrieved: { cid: CID; data: string; requestId: string };
  ePinCheck: { cid: CID; requestor: string; requestId: string };
  ePinStatus: { cid: CID; provider: string; expiresAt: number; redundancy: number; requestId: string };
  ePinRenew: { cid: CID; requestor: string; requestId: string };
  ePinRenewed: { cid: CID; provider: string; expiresAt: number; redundancy: number; requestId: string };
  ePinExpiring: { cid: CID; daysLeft: number };
  eConversationCaptured: { sessionKey: SessionKey; node: unknown };
  eConversationStored: { sessionKey: SessionKey; cid: CID };

  // --- Extension Registration Events ---
  eRegisterChannel: { name: ChannelName; handler: string };
  eUnregisterChannel: ChannelName;
  eRegisterProvider: { name: string; handler: string };
  eRegisterStorage: { name: string; handler: string };
  eRegisterInfrastructure: { name: string; handler: string };

  // --- Lifecycle Events ---
  eStart: void;
  eStop: void;
  eError: string;
  eShutdownComplete: void;
}

export type EventName = keyof EventMap;
