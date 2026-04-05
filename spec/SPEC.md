# Sovereign Agent P Language Specification

A formal state machine specification for autonomous, wallet-native AI agents using the **P programming language** — designed for modeling communicating state machines in distributed systems.

## Design Philosophy

**Minimal core, maximal extensibility.**

Inspired by pi-mono's design principles: the core is small and opinionated about very few things. If a capability doesn't belong in the kernel, it's an extension. This spec defines the thinnest possible sovereign agent kernel — the 5 machines without which the agent cannot function — and provides clean extension interfaces for everything else.

### What's Core (and Why)

| Machine | Why It's Core |
|---------|---------------|
| **AgentLoop** | The reasoning kernel. Without it, no agent. |
| **MessageBus** | Event routing. Without it, machines can't communicate. |
| **WalletIdentity** | Identity IS the wallet. This is the foundational primitive. |
| **Treasury** | Survival depends on economic state. No funds = no agent. |
| **ToolExecutor** | Agents act through tools. Execution is core; specific tools are not. |

### What's an Extension (and Why)

Everything else. Specific channels (XMTP, Solana), specific LLM providers (Gonka, Ritual, OpenRouter), specific storage backends (Filecoin, Arweave), scheduled tasks, parallel execution, infrastructure management — all extensions.

The core doesn't know about XMTP. It knows about "channels." The core doesn't know about Filecoin. It knows about "storage backends." The core doesn't know about Akash. It knows about "infrastructure providers."

```
Core Kernel (5 machines):
  ┌──────────────────────────────────────────────────────┐
  │  WalletIdentity ←→ Treasury ←→ AgentLoop            │
  │                                    ↕                  │
  │               MessageBus ←→ ToolExecutor             │
  └──────────────────────────────────────────────────────┘

Extension Layer (plug in via interfaces):
  ┌──────────────────────────────────────────────────────┐
  │  Channels: XMTP, Solana, Waku, Webhook, ...         │
  │  Providers: Gonka, Ritual, Centralized, ...          │
  │  Storage: Filecoin, Arweave, Local, ...              │
  │  Scheduling: CronService, HeartbeatService           │
  │  Execution: SubagentManager                          │
  │  Infrastructure: Akash, Phala, Flux, ...             │
  └──────────────────────────────────────────────────────┘
```

## Structure

```
sovereign-agent-p-lang-spec/
├── sovereign-agent.pproj      # P project configuration
├── README.md                  # This file
├── src/
│   ├── Types.p                # Core type definitions
│   ├── Events.p               # Core event declarations
│   ├── Interfaces.p           # Shared functions + extension point interfaces
│   ├── Main.p                 # Entry point, kernel instantiation
│   └── machines/
│       ├── AgentLoop.p        # Core: cost-aware reasoning engine
│       ├── MessageBus.p       # Core: async event routing
│       ├── WalletIdentity.p   # Core: crypto wallet identity
│       ├── Treasury.p         # Core: economic state machine
│       └── ToolExecutor.p     # Core: pluggable tool execution
├── extensions/
│   ├── Types.p                # Extension-specific types
│   ├── Events.p               # Extension-specific events
│   └── machines/
│       ├── ChatChannel.p              # Reference: generic channel adapter
│       ├── ProviderManager.p          # Reference: LLM provider with failover
│       ├── SessionManager.p           # Reference: session persistence
│       ├── CronService.p             # Reference: scheduled tasks
│       ├── HeartbeatService.p        # Reference: periodic self-checks
│       ├── SubagentManager.p         # Reference: parallel execution
│       └── InfrastructureManager.p   # Reference: compute lease management
└── spec/
    └── Specifications.p       # Safety and liveness specifications
```

## Core vs Extension Boundary

The core defines **events and interfaces** that extensions implement. Extensions never modify core machines — they communicate through the MessageBus using well-defined events.

### Extension Points

1. **Channels** — Any messaging transport. Implements `eRegisterChannel` / `eInboundMessage` / `eOutboundMessage`.
2. **Providers** — Any LLM inference source. Implements `eLLMRequest` / `eLLMResponse`.
3. **Storage** — Any persistence backend. Implements `eStoreData` / `eRetrieveData`.
4. **Schedulers** — Any time-based trigger. Implements `eCronTrigger` / `eHeartbeatTick`.
5. **Infrastructure** — Any compute provider. Implements `eLeaseRenew` / `eHealthCheck`.
6. **Tools** — Any agent capability. Registers via `eToolRegister` event.

## Formal Verification

Safety properties (verified by model checking):
- **WalletKeySafety**: Private key never leaves WalletIdentity boundary
- **TreasuryBudgetSafety**: Agent never spends more than allocated budget
- **MessageProcessingSafety**: No message processed twice, no message lost
- **ToolExecutionSafety**: No tool executes without cost check

Liveness properties:
- **ResponseLiveness**: Every inbound message eventually gets a response (or explicit error)
- **TreasuryMonitorLiveness**: Balance is checked periodically
- **SigningLiveness**: Every signing request eventually completes or fails

## Planning Docs

For developers building on this spec, the `docs/` directory provides mental models and guidance:

| Document | What It Covers |
|----------|----------------|
| **[00-layer-model.md](docs/00-layer-model.md)** | The **SALM** (Sovereign Agent Layer Model) — an OSI-like 7-layer framework mapping every component to its architectural layer |
| **[01-extension-guide.md](docs/01-extension-guide.md)** | How to build channels, tools, providers, storage backends, and other extensions |
| **[02-data-flow.md](docs/02-data-flow.md)** | Detailed traces of how data flows through the layers for 5 key scenarios |
| **[03-implementation-roadmap.md](docs/03-implementation-roadmap.md)** | Phased build plan from spec to running sovereign agent (7 phases, ~8-13 weeks) |

## Running

```bash
# Install P compiler: https://github.com/p-org/P
pc -proj:sovereign-agent.pproj
pmc SovereignAgent.dll -m<N>
```

## Relationship to p_model

This spec evolves the [p_model](../p_model/) nanobot specification. The 5 core machines descend from p_model originals (AgentLoop, MessageBus, ToolExecutor) plus 2 new ones (WalletIdentity, Treasury). The 7 extension machines carry forward p_model machines (ChatChannel, ProviderManager, SessionManager, CronService, HeartbeatService, SubagentManager) plus 1 new one (InfrastructureManager).

Key differences from p_model:
- Wallet identity is the foundational primitive (not string usernames)
- Every action has a cost (Treasury gates all resource consumption)
- Extension interfaces replace hardcoded implementations
- Core is 5 machines, not 9 — the rest are opt-in extensions
