/**
 * Machine: ToolExecutor
 * Role: CORE — Pluggable tool execution with cost gating.
 * 
 * Direct TypeScript translation of src/machines/ToolExecutor.p
 * 
 * Tools are the agent's hands. Every tool is registered dynamically via
 * eToolRegister events — there are NO hardcoded tools in the core. The
 * executor validates that the tool exists, requests cost authorization
 * from Treasury, and then delegates to the tool's handler.
 * 
 * Extension points (pi-mono pattern):
 *   - beforeToolCall: Can block a tool, inject logic, or modify args
 *   - afterToolCall: Can rewrite results, log, or trigger side effects
 * 
 * States: Init → Ready → Executing → Ready
 * (Executing is a real P spec state — events are queued while executing)
 */

import { Machine, MachineRegistry } from "../machine.js";
import {
  type ToolDefinition,
  type ToolCall,
  type ToolResult,
  type ToolName,
  type SessionKey,
  type Expense,
  ToolStatus,
} from "../types.js";

/** Tool handler function — actual implementation of a tool. */
export type ToolHandler = (call: ToolCall, signal: AbortSignal) => Promise<string> | string;

/**
 * Hook called before tool execution.
 * Return `false` to block execution (tool returns INSUFFICIENT_FUNDS).
 * Return `true` (or undefined) to proceed.
 * Can also modify the call arguments in-place.
 */
export type BeforeToolCallHook = (
  call: ToolCall,
  sessionKey: SessionKey,
  def: ToolDefinition
) => boolean | void | Promise<boolean | void>;

/**
 * Hook called after tool execution.
 * Can inspect or modify the result. Return a modified result or void.
 */
export type AfterToolCallHook = (
  call: ToolCall,
  result: ToolResult,
  sessionKey: SessionKey
) => ToolResult | void | Promise<ToolResult | void>;

export class ToolExecutor extends Machine {
  /** Registered tool definitions. */
  private tools = new Map<ToolName, ToolDefinition>();

  /** Tool handler functions (the actual executors). */
  private handlers = new Map<ToolName, ToolHandler>();

  /** Direct reference to treasury machine. */
  private treasury: Machine;

  /** Direct reference to agent machine. */
  private agent: Machine;

  /** Pending cost authorization requests. */
  private pendingAuths = new Map<string, { call: ToolCall; sessionKey: SessionKey }>();

  /** Execution queue — requests that arrive while in Executing state. */
  private executionQueue: Array<{ call: ToolCall; sessionKey: SessionKey }> = [];

  /** Current execution context. */
  private currentExecution: { call: ToolCall; sessionKey: SessionKey } | null = null;

  /** Extension hooks (pi-mono pattern). */
  private _beforeToolCall: BeforeToolCallHook[] = [];
  private _afterToolCall: AfterToolCallHook[] = [];

  constructor(
    registry: MachineRegistry,
    treasury: Machine,
    agent: Machine,
    id?: string
  ) {
    super("ToolExecutor", registry, id);
    this.treasury = treasury;
    this.agent = agent;
    this.defineStates();
  }

  async initialize(): Promise<void> {
    await this.init("Init");
  }

  private defineStates(): void {
    this.defineState("Init")
      .onEntry(() => {
        this.log("Initialized — no tools registered (extensions provide tools)");
        this.goto("Ready");
      });

    // ========================================================================
    // READY — Waiting for tool execution requests
    // ========================================================================
    this.defineState("Ready")
      .on("eToolRegister", (def: ToolDefinition) => {
        this.tools.set(def.name, def);
        this.log(`Tool registered — ${def.name}`);
      })
      .on("eToolUnregister", (name: ToolName) => {
        if (this.tools.has(name)) {
          this.tools.delete(name);
          this.handlers.delete(name);
          this.log(`Tool unregistered — ${name}`);
        }
      })
      .on("eExecuteTool", (req) => {
        const toolName = req.call.name;

        if (!this.tools.has(toolName)) {
          const result: ToolResult = {
            callId: req.call.id,
            status: ToolStatus.NOT_FOUND,
            result: `Tool '${toolName}' not registered`,
          };
          this.sendTo(this.agent, "eToolResult", result);
          return;
        }

        // Request cost authorization from Treasury.
        const costEstimate = this.tools.get(toolName)!.estimatedCost;
        const authId = `tool:${toolName}:${req.call.id}`;
        this.pendingAuths.set(authId, req);

        this.sendTo(this.treasury, "eCostAuthorize", {
          requestId: authId,
          estimate: costEstimate,
          requestor: this.id,
        });
      })
      .on("eCostAuthorized", (auth) => {
        if (!this.pendingAuths.has(auth.requestId)) return;

        const req = this.pendingAuths.get(auth.requestId)!;
        this.pendingAuths.delete(auth.requestId);

        if (!auth.approved) {
          const result: ToolResult = {
            callId: req.call.id,
            status: ToolStatus.INSUFFICIENT_FUNDS,
            result: `Cost denied: ${auth.reason}`,
          };
          this.sendTo(this.agent, "eToolResult", result);
          return;
        }

        // Authorized — transition to Executing state (P spec fidelity).
        this.goto("Executing", req);
      })
      .on("eError", (err: string) => {
        this.log(`Error — ${err}`);
      });

    // ========================================================================
    // EXECUTING — Active tool execution (P spec: distinct state)
    // Events that arrive here are queued, not processed concurrently.
    // ========================================================================
    this.defineState("Executing")
      .onEntry(async (req: { call: ToolCall; sessionKey: SessionKey }) => {
        this.currentExecution = req;
        await this.executeTool(req);
        
        // Process any queued requests that arrived during execution.
        if (this.executionQueue.length > 0) {
          const next = this.executionQueue.shift()!;
          this.goto("Executing", next);
        } else {
          this.currentExecution = null;
          this.goto("Ready");
        }
      })
      // Queue additional requests that arrive while executing.
      .on("eExecuteTool", (req) => {
        this.executionQueue.push(req);
      })
      .on("eCostAuthorized", (auth) => {
        // Handle authorization responses that arrive during execution.
        if (!this.pendingAuths.has(auth.requestId)) return;
        const req = this.pendingAuths.get(auth.requestId)!;
        this.pendingAuths.delete(auth.requestId);
        if (auth.approved) {
          this.executionQueue.push(req);
        } else {
          const result: ToolResult = {
            callId: req.call.id,
            status: ToolStatus.INSUFFICIENT_FUNDS,
            result: `Cost denied: ${auth.reason}`,
          };
          this.sendTo(this.agent, "eToolResult", result);
        }
      })
      .on("eToolRegister", (def: ToolDefinition) => {
        this.tools.set(def.name, def);
      });
  }

  /** Execute a tool with hooks and send back results. */
  private async executeTool(req: { call: ToolCall; sessionKey: SessionKey }): Promise<void> {
    this.log(`Executing ${req.call.name}`);
    const def = this.tools.get(req.call.name);

    // --- beforeToolCall hooks ---
    for (const hook of this._beforeToolCall) {
      try {
        const proceed = await hook(req.call, req.sessionKey, def!);
        if (proceed === false) {
          const result: ToolResult = {
            callId: req.call.id,
            status: ToolStatus.ERROR,
            result: "Blocked by beforeToolCall hook",
          };
          this.sendTo(this.agent, "eToolResult", result);
          return;
        }
      } catch (err) {
        this.log(`beforeToolCall hook error: ${err}`);
      }
    }

    try {
      const handler = this.handlers.get(req.call.name);
      let execResult: string;

      if (handler) {
        execResult = await handler(req.call, this.signal);
      } else {
        execResult = `Executed ${req.call.name} with args: ${JSON.stringify(req.call.arguments)}`;
      }

      let result: ToolResult = {
        callId: req.call.id,
        status: ToolStatus.SUCCESS,
        result: execResult,
      };

      // --- afterToolCall hooks ---
      for (const hook of this._afterToolCall) {
        try {
          const modified = await hook(req.call, result, req.sessionKey);
          if (modified) result = modified;
        } catch (err) {
          this.log(`afterToolCall hook error: ${err}`);
        }
      }

      this.sendTo(this.agent, "eToolResult", result);

      // Record expense.
      if (def) {
        for (const amount of def.estimatedCost.amounts) {
          const expense: Expense = {
            timestamp: Date.now(),
            category: def.estimatedCost.category,
            token: amount.token,
            amount: amount.amount,
            description: `Tool: ${req.call.name}`,
          };
          this.sendTo(this.treasury, "eExpenseRecord", expense);
        }
      }
    } catch (err) {
      let result: ToolResult = {
        callId: req.call.id,
        status: ToolStatus.ERROR,
        result: `Execution failed: ${err}`,
      };

      // Still run afterToolCall on errors.
      for (const hook of this._afterToolCall) {
        try {
          const modified = await hook(req.call, result, req.sessionKey);
          if (modified) result = modified;
        } catch { /* ignore hook errors on error path */ }
      }

      this.sendTo(this.agent, "eToolResult", result);
    }
  }

  // ==========================================================================
  // Public API
  // ==========================================================================

  /** Register a tool with its handler function. */
  registerTool(def: ToolDefinition, handler: ToolHandler): void {
    this.tools.set(def.name, def);
    this.handlers.set(def.name, handler);
    this.log(`Tool registered — ${def.name}`);
  }

  /** Get list of registered tool names. */
  getToolNames(): ToolName[] {
    return Array.from(this.tools.keys());
  }

  /** Get all registered tool definitions (for populating eLLMRequest.tools). */
  getToolDefinitions(): ToolDefinition[] {
    return Array.from(this.tools.values());
  }

  /** Update the agent reference (for late wiring). */
  setAgent(agent: Machine): void {
    this.agent = agent;
  }

  /**
   * Add a beforeToolCall hook.
   * Return false from the hook to block execution.
   * Similar to pi-mono's beforeToolCall.
   */
  beforeToolCall(hook: BeforeToolCallHook): void {
    this._beforeToolCall.push(hook);
  }

  /**
   * Add an afterToolCall hook.
   * Return a modified ToolResult to rewrite the result.
   * Similar to pi-mono's afterToolCall.
   */
  afterToolCall(hook: AfterToolCallHook): void {
    this._afterToolCall.push(hook);
  }
}
