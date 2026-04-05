/**
 * Machine: MessageBus
 * Role: CORE — The universal event routing layer.
 * 
 * Direct TypeScript translation of src/machines/MessageBus.p
 * 
 * Decouples all producers from all consumers. Channels publish inbound
 * messages; the agent loop consumes them. The agent loop publishes outbound
 * messages; channels consume them.
 * 
 * States: Init → Running
 */

import { Machine, MachineRegistry } from "../machine.js";
import type {
  ChannelName,
  InboundMessage,
  OutboundMessage,
} from "../types.js";

/** Callback for outbound message delivery (used by non-Machine channels like CLI). */
export type OutboundCallback = (msg: OutboundMessage) => void;

export class MessageBus extends Machine {
  /** Registered channel machine IDs, keyed by channel name. */
  private channels = new Map<ChannelName, string>();

  /** Callback-based channels (for non-Machine integrations like CLI). */
  private callbackChannels = new Map<ChannelName, OutboundCallback>();

  /** Direct reference to the agent loop machine. */
  private agent: Machine;

  /** Running flag. */
  private running = false;

  constructor(registry: MachineRegistry, agent: Machine, id?: string) {
    super("MessageBus", registry, id);
    this.agent = agent;
    this.defineStates();
  }

  async initialize(): Promise<void> {
    await this.init("Init");
  }

  private defineStates(): void {
    this.defineState("Init")
      .onEntry(() => {
        this.log("Initialized");
      })
      .on("eStart", () => {
        this.running = true;
        this.goto("Running");
      })
      .on("eRegisterChannel", (reg) => {
        this.channels.set(reg.name, reg.handler);
        this.log(`Channel pre-registered — ${reg.name}`);
      });

    this.defineState("Running")
      .onEntry(() => {
        this.log(`Running with ${this.channels.size + this.callbackChannels.size} channels`);
      })
      .on("eRegisterChannel", (reg) => {
        this.channels.set(reg.name, reg.handler);
        this.log(`Channel registered — ${reg.name}`);
      })
      .on("eUnregisterChannel", (name: ChannelName) => {
        if (this.channels.has(name)) {
          this.channels.delete(name);
          this.log(`Channel unregistered — ${name}`);
        }
        if (this.callbackChannels.has(name)) {
          this.callbackChannels.delete(name);
          this.log(`Callback channel unregistered — ${name}`);
        }
      })
      .on("ePublishInbound", (msg: InboundMessage) => {
        this.log(`Routing inbound from ${msg.channel}`);
        this.sendTo(this.agent, "eInboundMessage", msg);
      })
      .on("ePublishOutbound", (msg: OutboundMessage) => {
        // Try callback channels first (CLI, test harness)
        const callback = this.callbackChannels.get(msg.channel);
        if (callback) {
          callback(msg);
          this.log(`Routed outbound to ${msg.channel} (callback)`);
          return;
        }
        // Try machine-based channels
        if (this.channels.has(msg.channel)) {
          const handlerId = this.channels.get(msg.channel)!;
          this.sendById(handlerId, "eOutboundMessage", msg);
          this.log(`Routed outbound to ${msg.channel}`);
        } else {
          this.log(`No handler for channel ${msg.channel} — message dropped`);
        }
      })
      .on("eStop", () => {
        this.running = false;
        this.log("Stopping");
        this.halt();
      });
  }

  /** Register a callback-based channel (for CLI, test harness, etc.). */
  registerCallbackChannel(name: ChannelName, callback: OutboundCallback): void {
    this.callbackChannels.set(name, callback);
    this.log(`Callback channel registered — ${name}`);
  }

  /** Publish an inbound message directly (bypass channel machine). */
  publishInbound(msg: InboundMessage): void {
    this.enqueue("ePublishInbound", msg);
  }

  isRunning(): boolean {
    return this.running;
  }
}
