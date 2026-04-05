# Implementation Roadmap

## From Spec to Running Agent

This P language specification is a formal model. Turning it into a running sovereign agent means implementing these state machines in TypeScript, wiring them to real infrastructure, and progressively adding extensions. This roadmap is phased so that each phase produces a working (increasingly capable) agent.

## Phase Overview

```
Phase 0: Kernel + Stubs         (1 week)      → Agent can process messages locally
Phase 1: Identity + Messaging   (1-2 weeks)   → Agent has a wallet, talks via XMTP
Phase 2: Economic Awareness     (1 week)       → Agent tracks costs, adjusts behavior
Phase 3: Persistence            (1-2 weeks)    → Agent remembers conversations, survives restarts
Phase 4: Autonomous Operation   (1-2 weeks)    → Agent acts without being asked
Phase 5: Decentralized Infra    (2-3 weeks)    → Agent manages its own compute and storage
Phase 6: Decentralized Inference (1-2 weeks)   → Agent uses on-chain LLM providers
```

**Total estimated time: 8-13 weeks to full sovereignty.**

Each phase builds on the previous one. Skip phases you don't need (e.g., skip Phase 5 if you're fine running on a VPS).

---

## Phase 0: Kernel + Stubs

**Goal:** The 5 core machines running in TypeScript, processing messages via a test harness.

**What to build:**
- TypeScript project structure (monorepo or single package)
- Event system (typed event bus between machines)
- `WalletIdentity` — stub that returns a hardcoded address
- `Treasury` — stub that always approves costs
- `MessageBus` — route InboundMessage/OutboundMessage
- `ToolExecutor` — registry + dispatch, no real tools
- `AgentLoop` — LLM iteration loop with cost checking
- `ProviderStub` → wraps `pi-ai` for Anthropic/OpenAI
- Test harness that sends a message and gets a response

**Milestone:** Run `npm start`, send a message, get an LLM response back. No wallet, no cost tracking, no persistence — just the core loop.

**SALM layers active:** L4 (stub), L5, L6

**Key dependencies:**
- `@mariozechner/pi-ai` (LLM streaming)
- `@sinclair/typebox` (tool schema validation)

---

## Phase 1: Identity + Messaging

**Goal:** The agent has a real crypto wallet and communicates via XMTP.

**What to build:**
- `WalletIdentity` — real implementation using `viem` for Ethereum signing
- Key loading from environment variable (`SOVEREIGN_AGENT_PRIVATE_KEY`)
- XMTP ChatChannel extension (adapt from shoutbox-bot code)
- Channel registration flow (channel → bus → agent)
- Multi-room support (one session per XMTP group)

**Milestone:** Agent joins an XMTP group, responds to messages, signs messages with its wallet. Identity is the wallet address.

**SALM layers active:** L2, L4, L5, L6

**Key dependencies:**
- `viem` (Ethereum wallet, signing)
- `@xmtp/node-sdk` (messaging)
- Existing shoutbox-bot code (xmtpMessaging, xmtpFactory, groupSubscription)

**What to reuse from shoutbox-bot:**
- `xmtpSigner.ts` → adapt for WalletIdentity
- `xmtpFactory.ts` → adapt for ChatChannel extension
- `groupSubscription.ts` → message stream → ePublishInbound
- `presence.ts` → optional, for room presence

---

## Phase 2: Economic Awareness

**Goal:** The agent tracks real costs and adjusts behavior based on balance.

**What to build:**
- `Treasury` — real implementation with multi-chain balance queries
- Balance query extension (uses `viem` to read ERC-20 balances)
- Cost estimation for LLM calls (model pricing lookup)
- Budget allocation system
- Treasury state transitions (Funded → Low → Critical → Depleted)
- Cost-gated AgentLoop (check Treasury before each LLM call)
- Cost-gated ToolExecutor (check Treasury before each tool)
- Treasury report injection into system prompt

**Milestone:** Agent shows its balance in responses, switches to cheaper models when funds are low, refuses expensive operations in CRITICAL state.

**SALM layers active:** L2, L3, L4, L5, L6

**Key dependencies:**
- `viem` (balance queries, multicall)
- Price feeds (CoinGecko API or on-chain oracle)

**Design decisions:**
- How often to check balances (every heartbeat? every N messages?)
- Budget percentages (40/15/30/10/5 default, configurable)
- Which model to use in each treasury state

---

## Phase 3: Persistence

**Goal:** The agent remembers conversations and survives restarts.

**What to build:**
- `SessionManager` extension — JSONL persistence (from p_model design)
- Local file storage backend (development)
- Session load/save integrated with AgentLoop
- Memory consolidation (summarize old context)
- State recovery on boot (load last known state)

**Milestone:** Restart the agent, it picks up conversations where it left off. MEMORY.md-style summaries keep context windows manageable.

**SALM layers active:** L2, L3, L4, L5, L6

**Key dependencies:**
- Node.js `fs` module (local persistence)
- LLM calls for consolidation/summarization

**Optional (push to Phase 5):**
- Filecoin persistence
- Arweave permanent storage
- Cross-instance state sync

---

## Phase 4: Autonomous Operation

**Goal:** The agent acts without being asked — checks its own health, runs scheduled tasks.

**What to build:**
- `HeartbeatService` extension — periodic treasury checks
- `CronService` extension — scheduled task execution
- Survival alert injection (CRITICAL → inject alert message)
- Lease renewal reminder (if using managed infra)
- `SubagentManager` extension — parallel task execution
- Proactive behaviors (balance checks, health monitoring)

**Milestone:** Agent wakes up every 30 minutes, checks its balance, sends survival alerts if funds are low, runs scheduled cron jobs.

**SALM layers active:** L2, L3, L4, L5, L6, L7 (emergent)

**Key dependencies:**
- `node-cron` or simple `setInterval` for scheduling
- Treasury report as heartbeat input

**This is where the agent becomes sovereign.** Before Phase 4, it's a smart chatbot with a wallet. After Phase 4, it's an autonomous entity that monitors its own survival.

---

## Phase 5: Decentralized Infrastructure

**Goal:** The agent runs on decentralized compute and persists state to decentralized storage.

**What to build:**
- `InfrastructureManager` extension — Akash lease management
- Akash deployment manifest (Docker container)
- Lease renewal tool (sign + broadcast renewal tx)
- Filecoin storage extension (session sync)
- Arweave storage extension (permanent archives)
- State migration flow (save → deploy → recover)
- Health monitoring (compute, storage, messaging)

**Milestone:** Agent runs on Akash, renews its own lease, persists state to Filecoin, can migrate between providers.

**SALM layers active:** All 7 layers

**Key dependencies:**
- `@akashnetwork/akashjs` (lease management)
- Filecoin storage client
- Arweave client (`arweave-js`)
- Docker for containerization

**This is the hardest phase.** Decentralized infrastructure is less mature than centralized cloud. Expect rough edges, especially around Akash lease management and Filecoin deal negotiation.

---

## Phase 6: Decentralized Inference

**Goal:** The agent uses decentralized LLM providers, paying with crypto.

**What to build:**
- Gonka provider extension (wallet-signed inference requests)
- Ritual provider extension (on-chain inference)
- Market-based provider selection (cheapest viable provider)
- `ProviderManager` extension with failover chain:
  1. Decentralized (Gonka) — cheapest, wallet-signed
  2. Centralized (pi-ai) — reliable fallback
- Cost tracking in native tokens (not USD)

**Milestone:** Agent uses Gonka for inference when available, falls back to Anthropic via pi-ai, tracks costs in USDC/ETH.

**SALM layers active:** All 7 layers

**Key dependencies:**
- Gonka SDK (when available)
- Ritual SDK (for on-chain inference)
- `@mariozechner/pi-ai` (centralized fallback)

---

## Minimal Viable Sovereign Agent (MVSA)

If you want the shortest path to a "sovereign agent," here's the minimum:

```
Phase 0 (kernel)     — REQUIRED
Phase 1 (identity)   — REQUIRED (wallet + XMTP)
Phase 2 (economic)   — REQUIRED (cost awareness is what makes it sovereign)
Phase 4 (autonomous) — REQUIRED (self-directed behavior)
```

**Skip Phase 3** (use in-memory sessions, accept restart amnesia).
**Skip Phase 5** (run on a VPS, accept centralized compute).
**Skip Phase 6** (use pi-ai centralized providers, accept centralized inference).

**MVSA timeline: ~4-6 weeks.**

You get: an agent with a wallet identity, cost-aware reasoning, XMTP communication, and autonomous heartbeat monitoring. It's sovereign in identity and economics, even if its compute is centralized.

---

## Tech Stack Summary

| Component | Library | Phase |
|-----------|---------|-------|
| Runtime | Node.js + TypeScript | 0 |
| LLM (centralized) | `@mariozechner/pi-ai` | 0 |
| Tool schemas | `@sinclair/typebox` | 0 |
| Ethereum wallet | `viem` | 1 |
| XMTP messaging | `@xmtp/node-sdk` | 1 |
| Balance queries | `viem` multicall | 2 |
| Price feeds | CoinGecko API | 2 |
| Local persistence | Node.js `fs` | 3 |
| Scheduling | `node-cron` / `setInterval` | 4 |
| Akash compute | `@akashnetwork/akashjs` | 5 |
| Filecoin storage | Filecoin client | 5 |
| Arweave storage | `arweave-js` | 5 |
| Docker | `Dockerfile` | 5 |
| Gonka inference | Gonka SDK | 6 |

---

## Testing Strategy

### Per-Phase Testing

| Phase | Test Approach |
|-------|--------------|
| 0 | Unit tests: event routing, LLM loop, tool dispatch |
| 1 | Integration: wallet signing, XMTP message roundtrip |
| 2 | Scenario: treasury state transitions, cost denial in CRITICAL |
| 3 | Persistence: restart recovery, session continuity |
| 4 | Autonomy: heartbeat triggers, cron execution, survival alerts |
| 5 | Infrastructure: lease renewal, migration, state recovery |
| 6 | Provider: failover chain, cost comparison, wallet-signed inference |

### Model Checking

The P specification enables formal verification. Run the P model checker against the spec to verify:
- No message loss
- No double processing
- Budget enforcement holds across all states
- Treasury transitions are monotonic
- Signing requests always complete

This catches concurrency bugs that unit tests miss.

### Faux Provider Testing

Following pi-mono's approach: use faux providers (deterministic, no API calls) for testing the agent loop and tool execution. Reserve real provider tests for integration.

---

## What NOT to Build

Following the extensibility principle, explicitly avoid building:

| Don't Build | Why | Instead |
|------------|-----|---------|
| Custom LLM streaming | pi-ai already does this well | Use pi-ai as a library |
| Custom schema validation | TypeBox is proven | Use TypeBox |
| Custom XMTP wrapper | The SDK works | Adapt shoutbox-bot code |
| Monolithic agent class | Violates state machine model | Keep machines separate |
| Plugin marketplace | Premature | Extensions are just machines |
| Web UI for the agent | Not a priority for sovereignty | Use XMTP as the interface |
| Custom encryption | Dangerous | Use XMTP's MLS, viem's signing |
