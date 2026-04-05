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
