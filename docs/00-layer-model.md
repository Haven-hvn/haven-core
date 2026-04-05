# The Sovereign Agent Layer Model (SALM)

## Why a Layer Model?

The OSI model gave network engineers a shared vocabulary: "that's a Layer 3 problem" immediately tells you it's about routing, not about physical cables or application logic. The Sovereign Agent needs the same kind of framework.

Without it, developers will ask:
- "Where does wallet signing belong?" (Identity layer, not the agent loop)
- "Should the CronService know about Filecoin?" (No — scheduling is Layer 5, storage is Layer 2)
- "Who pays for this inference call?" (The Economic layer gates it before it reaches the Reasoning layer)

The **Sovereign Agent Layer Model (SALM)** answers these questions by defining 7 layers, from physical infrastructure up to autonomous behavior.

## The 7 Layers

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Layer 7 │ AUTONOMY        │ Self-directed goals, survival,        │
│          │                 │ revenue generation, self-improvement   │
│──────────┼─────────────────┼───────────────────────────────────────│
│  Layer 6 │ REASONING       │ LLM inference, tool calling,          │
│          │                 │ context management, decision making    │
│──────────┼─────────────────┼───────────────────────────────────────│
│  Layer 5 │ ORCHESTRATION   │ Scheduling, heartbeats, subagents,    │
│          │                 │ session management, extensions         │
│──────────┼─────────────────┼───────────────────────────────────────│
│  Layer 4 │ MESSAGING       │ Message bus, channels, routing,       │
│          │                 │ protocol adaptation                    │
│──────────┼─────────────────┼───────────────────────────────────────│
│  Layer 3 │ ECONOMIC        │ Treasury, budgets, cost gating,       │
│          │                 │ expense tracking, survival states      │
│──────────┼─────────────────┼───────────────────────────────────────│
│  Layer 2 │ IDENTITY &      │ Wallet, signing, storage backends,    │
│          │ PERSISTENCE     │ session persistence, state recovery   │
│──────────┼─────────────────┼───────────────────────────────────────│
│  Layer 1 │ INFRASTRUCTURE  │ Compute, networking, deployment,      │
│          │                 │ lease management, health monitoring    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Layer Details

### Layer 1: Infrastructure

**What it is:** The physical (or virtual) substrate the agent runs on.

**Responsibilities:**
- Compute provisioning (Akash, Phala, Flux, or local dev machine)
- Container deployment and lifecycle
- Network connectivity
- Lease management and renewal
- Health monitoring and migration
- TEE enclave management (when applicable)

**P machines:** `InfrastructureManager` (extension)

**Key events:** `eHealthCheck`, `eLeaseRenew`, `eLeaseMigrate`

**Analogy to OSI:** Like the Physical + Data Link layers — you need this to exist at all, but everything above is agnostic to whether you're on Akash or running locally.

**Rule:** Nothing above Layer 1 knows which compute provider is being used. If you're writing code that imports `akash-sdk`, it belongs here.

---

### Layer 2: Identity & Persistence

**What it is:** The agent's cryptographic identity and its ability to persist state.

**Responsibilities:**
- Private key management (lock/unlock/sign)
- Address derivation (Ethereum, Solana, etc.)
- Cryptographic signing for all external interactions
- State persistence (local, Filecoin, Arweave)
- State recovery after migration or restart
- Key security (TEE, HSM, keystore)

**P machines:** `WalletIdentity` (core), `SessionManager` (extension), decentralized storage (extension)

**Key events:** `eUnlockWallet`, `eSignRequest`, `eSignResult`, `eStoreData`, `eRetrieveData`

**Analogy to OSI:** Like the Network layer — it provides addressing (wallet addresses) and ensures data can be stored and retrieved regardless of the underlying infrastructure.

**Rule:** The private key NEVER leaves this layer. Other layers request signatures; they don't access keys. If you're writing code that touches `privateKey`, it belongs here and only here.

---

### Layer 3: Economic

**What it is:** The agent's financial survival system.

**Responsibilities:**
- Balance tracking across chains and tokens
- Budget allocation and enforcement
- Cost authorization (every costly action must be approved)
- Expense recording and ledger maintenance
- Runway calculation and survival state transitions
- Treasury state machine (Funded → Low → Critical → Depleted)

**P machines:** `Treasury` (core)

**Key events:** `eCostAuthorize`, `eCostAuthorized`, `eExpenseRecord`, `eBalanceUpdate`, `eTreasuryStateChanged`

**Analogy to OSI:** No direct OSI analog — this is unique to sovereign agents. Think of it as a "billing layer" that every operation must pass through, like a prepaid network where every packet costs money.

**Rule:** No action above this layer that costs resources (inference, gas, storage) can proceed without `eCostAuthorize → eCostAuthorized(approved=true)`. This is the universal constraint.

---

### Layer 4: Messaging

**What it is:** The communication backbone — routing messages between the agent and the outside world.

**Responsibilities:**
- Message bus (inbound/outbound routing)
- Channel registration and management
- Protocol adaptation (XMTP → InboundMessage, Solana memo → InboundMessage)
- Message format normalization
- Channel health and reconnection

**P machines:** `MessageBus` (core), `ChatChannel` (extension, one per protocol)

**Key events:** `ePublishInbound`, `ePublishOutbound`, `eRegisterChannel`, `eInboundMessage`, `eOutboundMessage`

**Analogy to OSI:** Like the Transport layer — it ensures messages get from source to destination reliably, regardless of the underlying protocol (XMTP, Solana, webhooks, etc.).

**Rule:** Channels are protocol-specific adapters. The bus and everything above it only deal with `InboundMessage` and `OutboundMessage` — they never touch protocol-specific types. If you're importing `@xmtp/node-sdk`, it belongs in a channel extension, not in the bus or agent.

---

### Layer 5: Orchestration

**What it is:** Coordination of the agent's activities over time.

**Responsibilities:**
- Scheduled task execution (CronService)
- Periodic self-activation (HeartbeatService)
- Parallel task management (SubagentManager)
- Tool registration and dispatch (ToolExecutor)
- Extension lifecycle management

**P machines:** `ToolExecutor` (core), `CronService` (extension), `HeartbeatService` (extension), `SubagentManager` (extension)

**Key events:** `eToolRegister`, `eExecuteTool`, `eCronTrigger`, `eHeartbeatTick`, `eSubagentSpawn`

**Analogy to OSI:** Like the Session layer — it manages the lifecycle and coordination of conversations and tasks over time.

**Rule:** Orchestration machines don't reason. They schedule, dispatch, and coordinate. If you're writing code that decides WHAT to do (as opposed to WHEN to do it), it belongs in Layer 6.

---

### Layer 6: Reasoning

**What it is:** The agent's brain — LLM inference, tool selection, and response generation.

**Responsibilities:**
- LLM request/response cycle
- Tool call loop (think → call → observe → think)
- Context management and prompt construction
- Provider selection and failover
- Cost-aware inference (cheaper models in low-fund states)
- Response quality and format

**P machines:** `AgentLoop` (core), `ProviderManager` (extension)

**Key events:** `eLLMRequest`, `eLLMResponse`, `eProcessMessage`, `eMessageProcessed`

**Analogy to OSI:** Like the Presentation layer — it transforms raw data (messages) into meaningful actions (responses, tool calls) through the LLM.

**Rule:** The reasoning layer decides WHAT to do but never HOW to do it at the protocol level. It says "sign this transaction" (which Layer 2 handles) or "send this message to XMTP" (which Layer 4 handles). It never imports `viem` or `@xmtp/node-sdk` directly.

---

### Layer 7: Autonomy

**What it is:** Self-directed behavior — what makes this a sovereign agent rather than a chatbot.

**Responsibilities:**
- Survival strategy (what to do when funds are low)
- Revenue generation (earning to sustain existence)
- Self-improvement (updating own prompts, strategies)
- Goal management (long-term objectives)
- DAO participation and governance
- Reputation management

**P machines:** Not directly modeled (emergent from Layer 5+6 coordination). Future extensions may formalize goal management.

**Key events:** Composed from lower layers — `eTreasuryStateChanged` triggers survival behaviors, `eHeartbeatTick` triggers proactive actions.

**Analogy to OSI:** Like the Application layer — it's where the agent's "personality" and purpose live. Everything below exists to support this layer's goals.

**Rule:** Autonomy emerges from the interaction of lower layers. It's not a single machine — it's the agent's system prompt, configured heartbeat behaviors, cron jobs, and treasury responses working together. Don't try to put "be autonomous" into a single state machine.

---

## Layer Interaction Rules

### The Cardinal Rule: Layers Only Talk Down (Or Through Events)

Like OSI, each layer provides services to the layer above and consumes services from the layer below. Cross-layer communication happens through the event system, not through direct machine references.

```
Layer 7 (Autonomy)     uses → Layer 6 (Reasoning) + Layer 5 (Orchestration)
Layer 6 (Reasoning)    uses → Layer 5 (Orchestration) + Layer 4 (Messaging)
Layer 5 (Orchestration) uses → Layer 4 (Messaging) + Layer 3 (Economic)
Layer 4 (Messaging)    uses → Layer 2 (Identity) for signing
Layer 3 (Economic)     uses → Layer 2 (Identity) for balance queries
Layer 2 (Identity)     uses → Layer 1 (Infrastructure) for persistence
Layer 1 (Infrastructure) is the foundation
```

### What Goes Where — Decision Guide

| If you're building... | It belongs in... |
|----------------------|-----------------|
| A new chat platform adapter (Matrix, Discord, etc.) | Layer 4 — Channel extension |
| A new LLM provider (local model, new API) | Layer 6 — Provider extension |
| A new storage backend (S3, IPFS, etc.) | Layer 2 — Storage extension |
| A new tool (web search, code execution, etc.) | Layer 5 — Tool extension (registers via `eToolRegister`) |
| A new scheduled behavior | Layer 5 — Cron job or heartbeat task |
| A new compute provider (AWS, Fly.io) | Layer 1 — Infrastructure extension |
| Budget/cost logic changes | Layer 3 — Treasury modification |
| Survival behavior changes | Layer 7 — System prompt + heartbeat configuration |
| A new signing scheme (multi-sig, MPC) | Layer 2 — WalletIdentity extension |

### Anti-Patterns

| Anti-Pattern | Why It's Wrong | Fix |
|-------------|---------------|-----|
| AgentLoop imports `@xmtp/node-sdk` | Layer 6 reaching into Layer 4 specifics | Use channel extension, communicate via events |
| ChatChannel checks Treasury balance | Layer 4 reaching into Layer 3 | Treasury gates actions at Layer 5/6, not Layer 4 |
| ToolExecutor holds the private key | Layer 5 reaching into Layer 2 | Tools request signatures via `eSignRequest` |
| HeartbeatService calls LLM directly | Layer 5 bypassing Layer 6 | Heartbeat injects messages into the bus, AgentLoop processes them |
| Treasury imports `viem` for balance queries | Layer 3 doing Layer 2's job | Balance queries are Layer 2 extensions that emit `eBalanceUpdate` |

## Core vs Extension at Each Layer

```
Layer 7: AUTONOMY        → All extension (emergent behavior)
Layer 6: REASONING       → Core: AgentLoop    │ Ext: ProviderManager
Layer 5: ORCHESTRATION   → Core: ToolExecutor  │ Ext: Cron, Heartbeat, Subagent
Layer 4: MESSAGING       → Core: MessageBus    │ Ext: ChatChannel (per protocol)
Layer 3: ECONOMIC        → Core: Treasury      │ Ext: Balance query providers
Layer 2: IDENTITY/PERSIST → Core: WalletIdentity │ Ext: Storage, SessionManager
Layer 1: INFRASTRUCTURE  → All extension       │ Ext: InfrastructureManager
```

Note: Layer 1 and Layer 7 are entirely extension-driven. The core kernel spans Layers 2-6 with exactly 5 machines.

## Using This Model

When a developer asks "where does X go?", walk the layers:

1. **Does it involve physical compute or networking?** → Layer 1
2. **Does it involve keys, signing, or persistent storage?** → Layer 2
3. **Does it involve money, budgets, or cost decisions?** → Layer 3
4. **Does it involve message routing or protocol adaptation?** → Layer 4
5. **Does it involve scheduling, coordination, or tool dispatch?** → Layer 5
6. **Does it involve LLM inference or decision-making?** → Layer 6
7. **Does it involve self-directed goals or survival strategy?** → Layer 7

If the answer spans multiple layers, break it into components. A "send signed XMTP message" operation involves Layer 2 (signing), Layer 4 (XMTP channel), and possibly Layer 3 (cost of sending). Each layer handles its part.
