/**
 * SovereignAgentKernel — Entry point for the Sovereign Agent system.
 * 
 * Direct TypeScript translation of the SovereignAgentKernel from src/Main.p
 * 
 * Creates and wires the 5 core kernel machines using direct references
 * (no string ID lookups at the kernel level). The kernel owns its own
 * MachineRegistry — no globals, tests can run in parallel.
 * 
 * Design principle: The kernel only knows about core machines. It does NOT
 * instantiate extensions — those are plugged in by the host environment.
 */

import { MachineRegistry, type MachineSubscriber } from "./machine.js";
import { WalletIdentity } from "./machines/WalletIdentity.js";
import { Treasury } from "./machines/Treasury.js";
import { MessageBus, type OutboundCallback } from "./machines/MessageBus.js";
import { ToolExecutor, type ToolHandler, type BeforeToolCallHook, type AfterToolCallHook } from "./machines/ToolExecutor.js";
import { AgentLoop, type TransformContextFn } from "./machines/AgentLoop.js";
import { ProviderStub } from "./machines/ProviderStub.js";
import type {
  InboundMessage,
  ToolDefinition,
  ChannelName,
} from "./types.js";
import { generateSessionKey } from "./interfaces.js";

export interface KernelConfig {
  /** Key source for wallet unlock (default: "env:SOVEREIGN_AGENT_PRIVATE_KEY"). */
  keySource?: string;
}

/**
 * The Sovereign Agent Kernel.
 * 
 * Encapsulates all 5 core machines with a kernel-scoped registry.
 * Provides a clean API for:
 * - Sending messages to the agent
 * - Registering channels, tools, and hooks
 * - Subscribing to machine events
 * - Querying agent state
 * - waitForIdle() synchronization
 */
export class SovereignAgentKernel {
  /** Kernel-scoped machine registry — no globals. */
  readonly registry: MachineRegistry;

  readonly wallet: WalletIdentity;
  readonly treasury: Treasury;
  readonly bus: MessageBus;
  readonly toolExecutor: ToolExecutor;
  readonly agent: AgentLoop;
  readonly provider: ProviderStub;

  private running = false;

  constructor() {
    console.log("=== Sovereign Agent Kernel — Boot Sequence ===");

    // Each kernel gets its own registry. No global state.
    this.registry = new MachineRegistry();

    // 1. WalletIdentity — must exist before anything else.
    this.wallet = new WalletIdentity(this.registry, "wallet");

    // 2. Treasury — economic survival depends on this.
    this.treasury = new Treasury(this.registry, "treasury");

    // 3. ProviderStub — placeholder for real LLM providers.
    this.provider = new ProviderStub(this.registry, "provider");

    // 4. ToolExecutor — needs treasury for cost gating.
    //    Agent ref will be set after AgentLoop creation via setAgent().
    this.toolExecutor = new ToolExecutor(
      this.registry,
      this.treasury,
      this.wallet, // Temporary — will be replaced with real agent
      "toolExecutor"
    );

    // 5. AgentLoop — the reasoning engine, wired to everything via direct refs.
    //    Bus ref will be set after MessageBus creation via setBus().
    this.agent = new AgentLoop(
      this.registry,
      {
        bus: this.wallet,       // Temporary — will be replaced
        provider: this.provider,
        toolExecutor: this.toolExecutor,
        treasury: this.treasury,
        wallet: this.wallet,
      },
      "agent"
    );

    // 6. MessageBus — routes messages between channels and agent.
    this.bus = new MessageBus(this.registry, this.agent, "bus");

    // Re-wire: Now that all machines exist, set the real references.
    this.agent.setBus(this.bus);
    this.toolExecutor.setAgent(this.agent);

    console.log("=== Kernel Ready — 5 core machines online ===");
    console.log(`  WalletIdentity: Locked (awaiting eUnlockWallet)`);
    console.log(`  Treasury:       Initialized (awaiting eBalanceUpdate)`);
    console.log(`  ToolExecutor:   Ready (no tools — extensions provide them)`);
    console.log(`  AgentLoop:      Idle (awaiting messages)`);
    console.log(`  MessageBus:     Initialized (no channels — extensions provide them)`);
  }

  /**
   * Start the kernel — initializes all machines and boots the system.
   * Uses waitForIdle() instead of fragile setTimeout.
   */
  async start(config: KernelConfig = {}): Promise<void> {
    if (this.running) return;

    console.log("\n=== Sovereign Agent Kernel — Starting ===");

    // Initialize all machines (construction was separate from init).
    await this.wallet.initialize();
    await this.treasury.initialize();
    await this.provider.initialize();
    await this.toolExecutor.initialize();
    await this.agent.initialize();
    await this.bus.initialize();

    // Start core machines.
    this.bus.enqueue("eStart");
    this.agent.enqueue("eStart");

    // Unlock wallet.
    const keySource = config.keySource || "env:SOVEREIGN_AGENT_PRIVATE_KEY";
    this.wallet.enqueue("eUnlockWallet", keySource);

    // Give balances for Phase 0 (simulated funded state).
    this.treasury.enqueue("eBalanceUpdate", [
      {
        chain: "ethereum",
        token: "USDC",
        amount: 1000_000000,
        usdEstimate: 1000_000000,
      },
      {
        chain: "ethereum",
        token: "ETH",
        amount: 500000000000000000,
        usdEstimate: 1000_000000,
      },
    ]);

    this.running = true;

    // Wait for all machines to finish processing startup events.
    await this.waitForIdle();

    console.log("\n=== Sovereign Agent Kernel — Running ===");
    console.log(`  Wallet Address: ${this.wallet.getAddress()}`);
    console.log(`  Treasury State: ${this.treasury.getTreasuryState()}`);
    console.log(`  Tools:          ${this.toolExecutor.getToolNames().length} registered`);
    console.log("");
  }

  /**
   * Stop the kernel — graceful shutdown.
   */
  async stop(): Promise<void> {
    if (!this.running) return;

    console.log("\n=== Sovereign Agent Kernel — Shutdown ===");
    this.agent.enqueue("eStop");
    this.bus.enqueue("eStop");
    this.wallet.enqueue("eLockWallet");
    this.running = false;

    await this.waitForIdle();
    console.log("=== Sovereign Agent Kernel — Shutdown Complete ===");
  }

  /**
   * Wait for all machines to be idle (event queues empty).
   * Replaces fragile setTimeout patterns.
   */
  async waitForIdle(): Promise<void> {
    await Promise.all([
      this.wallet.waitForIdle(),
      this.treasury.waitForIdle(),
      this.bus.waitForIdle(),
      this.toolExecutor.waitForIdle(),
      this.agent.waitForIdle(),
      this.provider.waitForIdle(),
    ]);
  }

  /**
   * Send a message to the agent via the message bus.
   */
  sendMessage(
    content: string,
    options: {
      channel?: ChannelName;
      senderId?: string;
      chatId?: string;
    } = {}
  ): void {
    const channel = options.channel || "cli";
    const chatId = options.chatId || "default";
    const senderId = options.senderId || "user";

    const msg: InboundMessage = {
      id: `msg_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
      channel,
      senderId,
      chatId,
      content,
      timestamp: Date.now(),
      sessionKey: generateSessionKey(channel, chatId),
      metadata: {},
    };

    this.bus.publishInbound(msg);
  }

  /**
   * Register a callback to receive outbound messages for a channel.
   */
  onMessage(channel: ChannelName, callback: OutboundCallback): void {
    this.bus.registerCallbackChannel(channel, callback);
  }

  /**
   * Register a tool with the executor.
   */
  registerTool(def: ToolDefinition, handler: ToolHandler): void {
    this.toolExecutor.registerTool(def, handler);
  }

  /**
   * Add a beforeToolCall hook.
   * Return false to block tool execution.
   */
  beforeToolCall(hook: BeforeToolCallHook): void {
    this.toolExecutor.beforeToolCall(hook);
  }

  /**
   * Add an afterToolCall hook.
   * Return a modified ToolResult to rewrite results.
   */
  afterToolCall(hook: AfterToolCallHook): void {
    this.toolExecutor.afterToolCall(hook);
  }

  /**
   * Set a context transform function on the agent loop.
   * Called before every LLM request.
   */
  setTransformContext(fn: TransformContextFn): void {
    this.agent.setTransformContext(fn);
  }

  /**
   * Subscribe to all machine events in this kernel.
   * Returns an unsubscribe function.
   */
  subscribe(subscriber: MachineSubscriber): () => void {
    return this.registry.subscribe(subscriber);
  }

  /**
   * Check if the kernel is running.
   */
  isRunning(): boolean {
    return this.running;
  }
}
