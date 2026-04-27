/**
 * Machine: AgentLoop
 * Role: CORE — The cost-aware reasoning engine.
 * 
 * Direct TypeScript translation of src/machines/AgentLoop.p
 * 
 * Processes inbound messages, interacts with LLM providers (via events),
 * executes tools (via ToolExecutor), and manages the iterative
 * think→tool→think loop. Every LLM call and tool call is cost-gated
 * through Treasury.
 * 
 * The optional InferencePipeline sits between AgentLoop and the provider.
 * If registered, all eLLMRequest events route through it for middleware
 * processing (logging, compression, encryption, persistence). If not
 * registered, AgentLoop talks directly to the provider (backward compatible).
 * 
 * Extension points (pi-mono patterns):
 *   - transformContext: Rewrite the message array before each LLM call
 *     (context window management, injection, pruning)
 *   - AbortController/signal: Cancel in-flight operations
 *   - pipeline: Optional InferencePipeline for middleware interception
 * 
 * States: Init → Idle → CostChecking → Iterating → Responding → Idle
 */

import { Machine, MachineRegistry } from "../machine.js";
import type { ToolExecutor } from "./ToolExecutor.js";
import {
  type InboundMessage,
  type OutboundMessage,
  type SessionKey,
  type ToolResult,
  type CostEstimate,
  type Expense,
  type LLMResponse,
  LLMResponseType,
  BudgetCategory,
} from "../types.js";
import { isSlashCommand, parseCommand } from "../interfaces.js";

/** Message in conversation context. */
export interface ContextMessage {
  role: string;
  content: string;
}

/**
 * Transform the context before sending to the LLM.
 * Can prune, summarize, inject system prompts, manage context windows.
 * Similar to pi-mono's transformContext.
 */
export type TransformContextFn = (
  messages: ContextMessage[],
  sessionKey: SessionKey
) => ContextMessage[] | Promise<ContextMessage[]>;

export class AgentLoop extends Machine {
  // Direct machine references (injected at creation).
  private bus: Machine;
  private provider: Machine;
  private toolExecutor: Machine;
  private treasury: Machine;
  private wallet: Machine;

  // Optional inference pipeline (extension-provided).
  // If set, eLLMRequest routes through the pipeline instead of directly
  // to the provider. The pipeline is a transparent proxy.
  private pipeline: Machine | null = null;
  private hasPipeline = false;

  // Configuration.
  private maxIterations = 40;

  // Runtime state.
  private running = false;
  private activeSessions = new Set<SessionKey>();
  private memoryAvailable = false;

  // State for CostChecking
  private costCheckMessage: InboundMessage | null = null;
  private costAuthId = "";

  // State for Iterating
  private iteratingMessage: InboundMessage | null = null;
  private iteration = 0;
  private toolsUsed: string[] = [];
  private pendingToolResults = 0;
  private toolResultsCollected: ToolResult[] = [];

  // Conversation context per session.
  private sessionMessages = new Map<SessionKey, ContextMessage[]>();

  // Extension: context transform (pi-mono pattern).
  private _transformContext: TransformContextFn | null = null;

  constructor(
    registry: MachineRegistry,
    deps: {
      bus: Machine;
      provider: Machine;
      toolExecutor: Machine;
      treasury: Machine;
      wallet: Machine;
    },
    id?: string
  ) {
    super("AgentLoop", registry, id);
    this.bus = deps.bus;
    this.provider = deps.provider;
    this.toolExecutor = deps.toolExecutor;
    this.treasury = deps.treasury;
    this.wallet = deps.wallet;
    this.defineStates();
  }

  async initialize(): Promise<void> {
    await this.init("Init");
  }

  private defineStates(): void {
    // ========================================================================
    // INIT
    // ========================================================================
    this.defineState("Init")
      .onEntry(() => {
        this.log("Initialized");
        this.goto("Idle");
      });

    // ========================================================================
    // IDLE — Waiting for messages
    // ========================================================================
    this.defineState("Idle")
      .onEntry(() => {
        this.running = true;
        this.log("Waiting for messages");
      })
      .on("eStart", () => {
        this.running = true;
      })
      .on("eStop", () => {
        this.running = false;
        this.abortController.abort();
        this.halt();
      })
      .on("eInboundMessage", (msg: InboundMessage) => {
        this.log(`Received from ${msg.channel}:${msg.senderId}`);

        // The only slash command the core handles is /stop (emergency brake).
        if (isSlashCommand(msg.content)) {
          const cmd = parseCommand(msg.content);
          if (cmd === "/stop") {
            this.sendSelf("eStopProcessing", msg.sessionKey);
            return;
          }
        }

        // Fresh abort controller for this processing cycle.
        this.abortController = new AbortController();

        this.activeSessions.add(msg.sessionKey);

        if (!this.sessionMessages.has(msg.sessionKey)) {
          this.sessionMessages.set(msg.sessionKey, []);
        }
        this.sessionMessages.get(msg.sessionKey)!.push({
          role: "user",
          content: msg.content,
        });

        this.goto("CostChecking", msg);
      })
      .on("eStopProcessing", (sessionKey: SessionKey) => {
        this.activeSessions.delete(sessionKey);
        this.log(`Stopped processing ${sessionKey}`);
      })
      // --- Pipeline registration (extension plug-in point) ---
      .on("eRegisterMiddleware", (reg) => {
        // Forward middleware registration to the pipeline if it exists.
        if (this.hasPipeline && this.pipeline) {
          this.sendTo(this.pipeline, "eRegisterMiddleware", reg);
        }
      })
      // --- Memory restoration (boot-time) ---
      .on("eMemoryRestored", (result: { success: boolean; sessionCount: number }) => {
        this.memoryAvailable = result.success;
        if (result.success) {
          this.log(`Memory restored — ${result.sessionCount} sessions available`);
        } else {
          this.log("Memory restoration failed — continuing without history");
        }
      })
      .on("eError", (err: string) => {
        this.log(`Error — ${err}`);
      });

    // ========================================================================
    // CostChecking — Ask treasury if we can afford an LLM call
    // ========================================================================
    this.defineState("CostChecking")
      .onEntry((msg: InboundMessage) => {
        this.costCheckMessage = msg;

        const estimate: CostEstimate = {
          amounts: [{ token: "USDC", amount: 5000 }],
          category: BudgetCategory.INFERENCE,
        };

        this.costAuthId = `llm:${msg.id}`;

        this.sendTo(this.treasury, "eCostAuthorize", {
          requestId: this.costAuthId,
          estimate,
          requestor: this.id,
        });
      })
      .on("eCostAuthorized", (auth) => {
        if (auth.requestId !== this.costAuthId) return;

        if (!auth.approved) {
          this.log(`Inference denied — ${auth.reason}`);
          const lowFundsResponse: OutboundMessage = {
            channel: this.costCheckMessage!.channel,
            chatId: this.costCheckMessage!.chatId,
            content: "I'm currently low on funds and cannot process this request.",
            replyTo: this.costCheckMessage!.id,
            metadata: {},
          };
          this.sendTo(this.bus, "ePublishOutbound", lowFundsResponse);
          this.activeSessions.delete(this.costCheckMessage!.sessionKey);
          this.goto("Idle");
          return;
        }

        this.goto("Iterating", this.costCheckMessage);
      })
      .on("eStopProcessing", (sessionKey: SessionKey) => {
        this.activeSessions.delete(sessionKey);
        this.abortController.abort();
        this.goto("Idle");
      });

    // ========================================================================
    // Iterating — The LLM tool-call loop
    // ========================================================================
    this.defineState("Iterating")
      .onEntry((msg: InboundMessage) => {
        this.iteratingMessage = msg;
        this.iteration = 0;
        this.toolsUsed = [];
        this.pendingToolResults = 0;
        this.toolResultsCollected = [];

        this.sendLLMRequest();
      })
      .on("eLLMResponse", (resp: { sessionKey: SessionKey; response: LLMResponse }) => {
        // Check if aborted.
        if (this.signal.aborted) {
          this.goto("Idle");
          return;
        }

        if (resp.response.responseType === LLMResponseType.TOOL_CALLS) {
          this.iteration++;

          if (this.iteration >= this.maxIterations) {
            this.log("Max iterations reached");
            this.sendSelf("eMaxIterationsReached", this.iteratingMessage!.sessionKey);
            this.goto("Responding", "Maximum iterations reached. Please try a simpler request.");
            return;
          }

          const toolCalls = resp.response.toolCalls;
          this.pendingToolResults = toolCalls.length;
          this.toolResultsCollected = [];

          for (const tc of toolCalls) {
            this.toolsUsed.push(tc.name);
            this.sendTo(this.toolExecutor, "eExecuteTool", {
              call: tc,
              sessionKey: this.iteratingMessage!.sessionKey,
            });
          }
        } else if (resp.response.responseType === LLMResponseType.CONTENT) {
          const sessionKey = this.iteratingMessage!.sessionKey;
          if (this.sessionMessages.has(sessionKey)) {
            this.sessionMessages.get(sessionKey)!.push({
              role: "assistant",
              content: resp.response.content,
            });
          }
          this.goto("Responding", resp.response.content);
        } else if (resp.response.responseType === LLMResponseType.ERROR) {
          this.goto("Responding", "An error occurred while processing your request.");
        } else if (resp.response.responseType === LLMResponseType.RATE_LIMITED) {
          this.goto("Responding", "I'm currently rate limited. Please try again shortly.");
        }
      })
      .on("eToolResult", (result: ToolResult) => {
        this.log(`Tool ${result.callId} → ${result.status}`);
        this.toolResultsCollected.push(result);
        this.pendingToolResults--;

        if (this.pendingToolResults <= 0) {
          const sessionKey = this.iteratingMessage!.sessionKey;
          if (this.sessionMessages.has(sessionKey)) {
            for (const tr of this.toolResultsCollected) {
              this.sessionMessages.get(sessionKey)!.push({
                role: "tool",
                content: `[${tr.callId}] ${tr.status}: ${tr.result}`,
              });
            }
          }
          this.sendLLMRequest();
        }
      })
      .on("eStopProcessing", (sessionKey: SessionKey) => {
        this.activeSessions.delete(sessionKey);
        this.abortController.abort();
        this.goto("Idle");
      });

    // ========================================================================
    // Responding — Send the final response and return to idle
    // ========================================================================
    this.defineState("Responding")
      .onEntry((content: string) => {
        if (!this.iteratingMessage && !this.costCheckMessage) {
          this.goto("Idle");
          return;
        }

        const currentMessage = this.iteratingMessage || this.costCheckMessage!;

        const response: OutboundMessage = {
          channel: currentMessage.channel,
          chatId: currentMessage.chatId,
          content,
          replyTo: currentMessage.id,
          metadata: {},
        };

        this.sendTo(this.bus, "ePublishOutbound", response);

        const expense: Expense = {
          timestamp: Date.now(),
          category: BudgetCategory.INFERENCE,
          token: "USDC",
          amount: 5000,
          description: `LLM response for ${currentMessage.sessionKey}`,
        };
        this.sendTo(this.treasury, "eExpenseRecord", expense);

        this.sendSelf("eMessageProcessed", response);

        this.activeSessions.delete(currentMessage.sessionKey);
        this.goto("Idle");
      });
  }

  // ==========================================================================
  // Internal helpers
  // ==========================================================================

  private async sendLLMRequest(): Promise<void> {
    const sessionKey = this.iteratingMessage!.sessionKey;
    let messages = this.sessionMessages.get(sessionKey) || [];

    // Apply transformContext if set (pi-mono pattern).
    if (this._transformContext) {
      try {
        messages = await this._transformContext([...messages], sessionKey);
      } catch (err) {
        this.log(`transformContext error: ${err}`);
      }
    }

    const msgPayloads: Record<string, string>[] = messages.map((m) => ({
      role: m.role,
      content: m.content,
    }));

    // Populate tools from ToolExecutor so the LLM provider knows what tools are available.
    const toolDefs = (this.toolExecutor as ToolExecutor).getToolDefinitions
      ? (this.toolExecutor as ToolExecutor).getToolDefinitions()
      : [];

    const llmReq = {
      sessionKey,
      messages: msgPayloads,
      tools: toolDefs,
      requestor: this.id,
      estimatedCost: {
        amounts: [] as { token: string; amount: number }[],
        category: BudgetCategory.INFERENCE,
      },
    };

    // Route through pipeline if registered, else direct to provider.
    // This is the ONE line that changes the inference path — everything
    // else in AgentLoop remains identical.
    if (this.hasPipeline && this.pipeline) {
      this.sendTo(this.pipeline, "eLLMRequest", llmReq);
    } else {
      this.sendTo(this.provider, "eLLMRequest", llmReq);
    }
  }

  // ==========================================================================
  // Public API
  // ==========================================================================

  /** Update the bus reference (for late wiring). */
  setBus(bus: Machine): void { this.bus = bus; }

  /** Update the provider reference. */
  setProvider(provider: Machine): void { this.provider = provider; }

  /**
   * Set the inference pipeline (extension plug-in point).
   * When set, eLLMRequest routes through the pipeline instead of
   * directly to the provider. The pipeline is a transparent proxy.
   */
  setPipeline(pipeline: Machine): void {
    this.pipeline = pipeline;
    this.hasPipeline = true;
    this.log("InferencePipeline wired — LLM requests will route through middleware");
  }

  /**
   * Set a context transform function.
   * Called before every LLM request to manage the context window.
   * Similar to pi-mono's transformContext.
   * 
   * Use for: context pruning, system prompt injection, 
   * memory consolidation, token budget management.
   */
  setTransformContext(fn: TransformContextFn): void {
    this._transformContext = fn;
  }

  getActiveSessionCount(): number {
    return this.activeSessions.size;
  }

  isRunning(): boolean {
    return this.running;
  }
}
