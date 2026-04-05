/**
 * Base Machine class — the runtime foundation for P language state machines.
 * 
 * In P, machines are communicating state machines that send/receive typed events.
 * This class provides:
 *   - State management with named states
 *   - Type-safe event send/receive with direct machine references
 *   - Asynchronous event queue (simulates P's async message passing)
 *   - Kernel-scoped registry (no globals)
 *   - External event observation via subscribe()
 *   - Abort/cancellation support
 *   - Logging with machine identity
 * 
 * Design: Construction is separate from initialization. `new Machine()` defines
 * states; `.init()` starts the machine. This follows pi-mono's pattern where
 * the constructor stores options and actual work happens later.
 */

import type { EventMap, EventName } from "./events.js";

/** A handler function for a specific event in a specific state. */
type EventHandler<E extends EventName = EventName> = (payload: EventMap[E]) => void | Promise<void>;

/** State definition: a map of event names to handlers, plus optional entry/exit. */
interface StateDefinition {
  entry?: (payload?: any) => void | Promise<void>;
  exit?: () => void | Promise<void>;
  handlers: Map<EventName, EventHandler<any>>;
}

/** Event observation record emitted to subscribers. */
export interface MachineEvent {
  source: string;       // Machine ID
  sourceName: string;   // Machine type name
  state: string;        // State when event was received
  event: EventName;
  payload: unknown;
  timestamp: number;
}

/** Subscriber callback for external event observation. */
export type MachineSubscriber = (evt: MachineEvent) => void;

/**
 * Kernel-scoped machine registry.
 * 
 * Each kernel instance creates its own registry. No globals.
 * Machines hold a reference to their registry, not to a global map.
 * Tests can run in parallel without collision.
 */
export class MachineRegistry {
  private machines = new Map<string, Machine>();
  private subscribers: MachineSubscriber[] = [];

  /** Register a machine. */
  register(machine: Machine): void {
    this.machines.set(machine.id, machine);
  }

  /** Unregister a machine. */
  unregister(id: string): void {
    this.machines.delete(id);
  }

  /** Get a machine by ID. */
  get(id: string): Machine | undefined {
    return this.machines.get(id);
  }

  /** Get all registered machines. */
  all(): Map<string, Machine> {
    return this.machines;
  }

  /** Clear all machines (for testing). */
  clear(): void {
    this.machines.clear();
  }

  /** Subscribe to all events across all machines in this registry. */
  subscribe(subscriber: MachineSubscriber): () => void {
    this.subscribers.push(subscriber);
    return () => {
      const idx = this.subscribers.indexOf(subscriber);
      if (idx >= 0) this.subscribers.splice(idx, 1);
    };
  }

  /** Notify subscribers of an event. */
  notify(evt: MachineEvent): void {
    for (const sub of this.subscribers) {
      try {
        sub(evt);
      } catch {
        // Subscribers must not crash the machine.
      }
    }
  }
}

/**
 * Base class for all P language state machines.
 * 
 * Subclasses define states using `defineState()` in the constructor.
 * Machines are initialized with `.init()` after construction, which
 * transitions to the start state. This separation makes testing easier.
 * 
 * Events are sent with `send()` using direct Machine references (type-safe)
 * or via the registry by ID (for late-bound references).
 */
export abstract class Machine {
  /** Unique identifier for this machine instance. */
  readonly id: string;

  /** Human-readable machine type name. */
  readonly typeName: string;

  /** The kernel-scoped registry this machine belongs to. */
  readonly registry: MachineRegistry;

  /** Whether this machine has been halted. */
  private _halted = false;

  /** Whether this machine has been initialized. */
  private _initialized = false;

  /** Current state name. */
  private _currentState: string = "";

  /** Defined states. */
  private _states = new Map<string, StateDefinition>();

  /** Event queue for async processing. */
  private _eventQueue: Array<{ event: EventName; payload: any }> = [];

  /** Whether we're currently processing the queue. */
  private _processing = false;

  /** Whether to suppress log output. */
  protected silent = false;

  /** Abort controller for cancellation support. */
  protected abortController = new AbortController();

  /** Local subscribers for this machine's events. */
  private _subscribers: MachineSubscriber[] = [];

  /** Idle resolution — resolves when event queue is empty. */
  private _idleResolvers: Array<() => void> = [];

  constructor(typeName: string, registry: MachineRegistry, id?: string) {
    this.typeName = typeName;
    this.registry = registry;
    this.id = id || `${typeName}_${Math.random().toString(36).slice(2, 8)}`;
    this.registry.register(this);
  }

  /** Get the current state name. */
  get currentState(): string {
    return this._currentState;
  }

  /** Whether this machine is halted. */
  get halted(): boolean {
    return this._halted;
  }

  /** Whether this machine has been initialized. */
  get initialized(): boolean {
    return this._initialized;
  }

  /** Get the abort signal for cancellation. */
  get signal(): AbortSignal {
    return this.abortController.signal;
  }

  // ==========================================================================
  // State Definition API (used by subclasses in constructor)
  // ==========================================================================

  /** Define a state with optional entry/exit and event handlers. */
  protected defineState(name: string): StateBuilder {
    const state: StateDefinition = {
      handlers: new Map(),
    };
    this._states.set(name, state);
    return new StateBuilder(state);
  }

  /** Transition to a new state, calling exit on current and entry on new. */
  protected async goto(stateName: string, payload?: any): Promise<void> {
    const newState = this._states.get(stateName);
    if (!newState) {
      throw new Error(`${this.typeName}: Unknown state '${stateName}'`);
    }

    // Exit current state
    const currentState = this._states.get(this._currentState);
    if (currentState?.exit) {
      await currentState.exit();
    }

    // Transition
    const prevState = this._currentState;
    this._currentState = stateName;

    if (prevState !== stateName || payload !== undefined) {
      // Entry on new state
      if (newState.entry) {
        await newState.entry(payload);
      }
    }
  }

  /** Halt this machine (P's `raise halt`). */
  protected halt(): void {
    this._halted = true;
    this.abortController.abort();
    this.registry.unregister(this.id);
    this.log("HALTED");
    this.resolveIdle();
  }

  /** Abort in-flight operations and reset the abort controller. */
  abort(): void {
    this.abortController.abort();
    this.abortController = new AbortController();
  }

  // ==========================================================================
  // Event Communication API — Direct typed references (preferred)
  // ==========================================================================

  /**
   * Send an event to another machine using a direct reference.
   * Type-safe at the communication boundary.
   */
  protected sendTo<E extends EventName>(
    target: Machine,
    event: E,
    ...args: EventMap[E] extends void ? [] : [EventMap[E]]
  ): void {
    target.enqueue(event, args[0]);
  }

  /**
   * Send an event to a machine by ID (for late-bound/dynamic references).
   * Falls back to registry lookup.
   */
  protected sendById<E extends EventName>(
    targetId: string,
    event: E,
    ...args: EventMap[E] extends void ? [] : [EventMap[E]]
  ): void {
    const target = this.registry.get(targetId);
    if (!target) {
      this.log(`WARNING: Target machine '${targetId}' not found for event '${event}'`);
      return;
    }
    target.enqueue(event, args[0]);
  }

  /** Send an event to self. */
  protected sendSelf<E extends EventName>(
    event: E,
    ...args: EventMap[E] extends void ? [] : [EventMap[E]]
  ): void {
    this.enqueue(event, args[0]);
  }

  /** Enqueue an event for processing. */
  enqueue<E extends EventName>(event: E, payload?: EventMap[E]): void {
    if (this._halted) return;
    this._eventQueue.push({ event, payload });
    this.processQueue();
  }

  /** Process queued events one at a time. */
  private async processQueue(): Promise<void> {
    if (this._processing) return;
    this._processing = true;

    while (this._eventQueue.length > 0) {
      if (this._halted) break;

      const item = this._eventQueue.shift()!;
      const state = this._states.get(this._currentState);

      if (state) {
        const handler = state.handlers.get(item.event);
        if (handler) {
          // Notify observers.
          const evt: MachineEvent = {
            source: this.id,
            sourceName: this.typeName,
            state: this._currentState,
            event: item.event,
            payload: item.payload,
            timestamp: Date.now(),
          };
          this.notifySubscribers(evt);
          this.registry.notify(evt);

          try {
            await handler(item.payload);
          } catch (err) {
            this.log(`ERROR handling ${item.event}: ${err}`);
          }
        }
        // Events without handlers in the current state are silently dropped
        // (consistent with P language semantics)
      }
    }

    this._processing = false;
    this.resolveIdle();
  }

  // ==========================================================================
  // Observation API — subscribe() for external observers
  // ==========================================================================

  /**
   * Subscribe to this machine's events.
   * Returns an unsubscribe function.
   * Similar to pi-mono's Agent.subscribe().
   */
  subscribe(subscriber: MachineSubscriber): () => void {
    this._subscribers.push(subscriber);
    return () => {
      const idx = this._subscribers.indexOf(subscriber);
      if (idx >= 0) this._subscribers.splice(idx, 1);
    };
  }

  private notifySubscribers(evt: MachineEvent): void {
    for (const sub of this._subscribers) {
      try {
        sub(evt);
      } catch {
        // Subscribers must not crash the machine.
      }
    }
  }

  // ==========================================================================
  // Synchronization — waitForIdle() replaces setTimeout hacks
  // ==========================================================================

  /**
   * Returns a promise that resolves when the machine's event queue is empty.
   * Replaces fragile `await sleep(50)` patterns.
   * Similar to pi-mono's `waitForIdle()`.
   */
  waitForIdle(): Promise<void> {
    if (this._eventQueue.length === 0 && !this._processing) {
      return Promise.resolve();
    }
    return new Promise((resolve) => {
      this._idleResolvers.push(resolve);
    });
  }

  private resolveIdle(): void {
    if (this._eventQueue.length === 0 && !this._processing) {
      const resolvers = this._idleResolvers.splice(0);
      for (const resolve of resolvers) {
        resolve();
      }
    }
  }

  // ==========================================================================
  // Logging
  // ==========================================================================

  protected log(message: string): void {
    if (!this.silent) {
      console.log(`[${this.typeName}] ${message}`);
    }
  }

  // ==========================================================================
  // Lifecycle — Construction is separate from initialization
  // ==========================================================================

  /**
   * Initialize the machine — transitions to the start state.
   * Call after construction. This separation makes testing easier:
   * you can construct a machine, inspect its state definitions,
   * and then initialize it when ready.
   */
  protected async init(initialState: string, payload?: any): Promise<void> {
    if (this._initialized) return;
    this._initialized = true;
    this._currentState = initialState;
    const state = this._states.get(initialState);
    if (state?.entry) {
      await state.entry(payload);
    }
  }
}

/**
 * Fluent builder for state definitions.
 */
class StateBuilder {
  private state: StateDefinition;

  constructor(state: StateDefinition) {
    this.state = state;
  }

  /** Set the entry action for this state. */
  onEntry(handler: (payload?: any) => void | Promise<void>): this {
    this.state.entry = handler;
    return this;
  }

  /** Set the exit action for this state. */
  onExit(handler: () => void | Promise<void>): this {
    this.state.exit = handler;
    return this;
  }

  /** Register a handler for a specific event in this state. */
  on<E extends EventName>(event: E, handler: (payload: EventMap[E]) => void | Promise<void>): this {
    this.state.handlers.set(event, handler as EventHandler);
    return this;
  }
}
