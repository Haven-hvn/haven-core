# Planned Spec Changes: Inference Middleware Pipeline, dPID, and Persistent Agent Memory

> **Origin:** Conversation exploring ChromaFs virtual filesystems, IPFS UnixFS, dPIDs, and IPLD schemas — combined with the middleware pipeline pattern from `lmstudio-bridge` — to give sovereign agents a generic, extensible inference pipeline with persistent, verifiable, self-owned memory as one of many pluggable middleware behaviors.

> **Core thesis:** The sovereign agent needs a **generic middleware pipeline** on its inference path. The `lmstudio-bridge` already implements this pattern: an onion-model pipeline where request and response payloads flow through ordered middleware that can observe, transform, compress, encrypt, persist, and record — all via a shared context. The P spec should formalize this as a core architectural primitive. IPFS persistence, dPID resolution, and conversation archival then become middleware extensions, not bespoke machines.

---

## Table of Contents

1. [Motivation](#1-motivation)
2. [The Middleware Pattern (from lmstudio-bridge)](#2-the-middleware-pattern)
3. [Architectural Overview](#3-architectural-overview)
4. [Spec Changes by File](#4-spec-changes-by-file)
   - 4.1 [Core Types (`spec/core/Types.p`)](#41-core-types)
   - 4.2 [Core Events (`spec/core/Events.p`)](#42-core-events)
   - 4.3 [Core Interfaces (`spec/core/Interfaces.p`)](#43-core-interfaces)
   - 4.4 [WalletIdentity Machine](#44-walletidentity-machine)
   - 4.5 [AgentLoop Machine](#45-agentloop-machine)
   - 4.6 [Treasury Machine](#46-treasury-machine)
   - 4.7 [Extension Types](#47-extension-types)
   - 4.8 [Extension Events](#48-extension-events)
   - 4.9 [New Extension Machines](#49-new-extension-machines)
5. [SALM Layer Mapping](#5-salm-layer-mapping)
6. [New Data Flows](#6-new-data-flows)
7. [IPLD Schema (Reference)](#7-ipld-schema-reference)
8. [Safety & Liveness Properties](#8-safety--liveness-properties)
9. [What Does NOT Change](#9-what-does-not-change)
10. [Open Questions](#10-open-questions)
11. [Implementation Sequence](#11-implementation-sequence)

---

## 1. Motivation

### Two problems, one solution

**Problem 1: No persistent memory.** The sovereign agent's conversations are ephemeral. When the process dies, context dies. The `SessionManager` extension provides session persistence but has no defined storage backend, no cryptographic binding to the agent's identity, and no verifiability.

**Problem 2: No extensible inference pipeline.** Every LLM request/response flows directly from `AgentLoop` → provider → `AgentLoop`. There is no interception point for cross-cutting concerns like logging, compression, encryption, archival, or cost metering. Each new concern requires modifying the `AgentLoop` core — violating the "minimal core, maximal extensibility" principle.

### The `lmstudio-bridge` proof

The `lmstudio-bridge` project (included at `lmstudio-bridge-main/`) already solves Problem 2 with a clean middleware pipeline:

| Component | lmstudio-bridge | Haven Equivalent (proposed) |
|-----------|----------------|----------------------------|
| `Middleware` interface | `{ name, onRequest?, onResponse? }` | `InferenceMiddleware` machine pattern |
| `MiddlewareRunner` | Onion-model `executeChain` with `next()` | `InferencePipeline` extension machine |
| `ShimContext` | `{ requestId, receivedAt, metadata }` | `PipelineContext` type |
| `Engine` | Ties translator + pipeline + client | AgentLoop routes through pipeline |
| `logger` middleware | Logs request/response stats | Extension: `LoggerMiddleware` |
| `gzip` middleware | Compresses payload, stores in context | Extension: `CompressionMiddleware` |
| `taco-encrypt` middleware | AES-256-GCM + threshold encryption | Extension: `EncryptionMiddleware` |
| `upload` middleware | Batch archive → Filecoin upload | Extension: `PersistenceMiddleware` |
| `cid-recorder` middleware | Records CIDs to Parquet | Extension: `CIDRecorderMiddleware` |

By formalizing this pipeline in the P spec, we get both an extensible inference path (Problem 2) and persistent memory as a pluggable middleware (Problem 1) — without changing any core machine logic.

---

## 2. The Middleware Pattern

### From `lmstudio-bridge`

The bridge intercepts every LLM call at two stages:

```
 Request flow (forward order):   Response flow (reverse order):
 ┌─────────┐                     ┌─────────┐
 │ logger  │ ──────────────────▶ │ logger  │
 ├─────────┤                     ├─────────┤
 │ gzip    │ ──────────────────▶ │ gzip    │
 ├─────────┤                     ├─────────┤
 │ encrypt │ ──────────────────▶ │ encrypt │
 ├─────────┤                     ├─────────┤
 │ upload  │ ──────────────────▶ │ upload  │
 ├─────────┤                     ├─────────┤
 │ cid-rec │ ──────────────────▶ │ cid-rec │
 └─────────┘                     └─────────┘
      │                               ▲
      ▼                               │
 ┌──────────────────────────────────────┐
 │          LLM Provider                 │
 └──────────────────────────────────────┘
```

Each middleware:
- Has a `name` for logging/identification
- Optionally implements `onRequest(payload, next)` — intercept before LLM call
- Optionally implements `onResponse(payload, next)` — intercept after LLM response
- Communicates with other middleware via `context.metadata` (shared mutable map)
- Must call `next()` to advance the chain (or skip to short-circuit)

Key behaviors observed in lmstudio-bridge middleware:
- **`gzip.onRequest`**: Captures the request in `context.metadata.capturedRequest`
- **`gzip.onResponse`**: Combines request+response, compresses, stores buffer in `context.metadata.gzipBuffer`
- **`taco-encrypt.onResponse`**: Reads `context.metadata.gzipBuffer` (if present), encrypts it, stores `context.metadata.encryptedBuffer`
- **`upload.onResponse`**: Reads encrypted buffer (or raw), batches conversations, flushes to Filecoin in background
- **`upload` security check**: Verifies that if `taco-encrypt` is registered, an encrypted buffer exists — **fail-closed** pattern

This is the exact pattern the P spec should formalize.

### Abstracted for P Spec

In P terms, the pipeline becomes:

```
AgentLoop                  InferencePipeline              Provider
    │                            │                            │
    │── eLLMRequest ───────────▶│                            │
    │                            │── onRequest(mw[0]) ──▶    │
    │                            │── onRequest(mw[1]) ──▶    │
    │                            │── onRequest(mw[N]) ──▶    │
    │                            │── eLLMRequest ───────────▶│
    │                            │                            │
    │                            │◀── eLLMResponse ──────────│
    │                            │◀── onResponse(mw[N]) ──   │
    │                            │◀── onResponse(mw[1]) ──   │
    │                            │◀── onResponse(mw[0]) ──   │
    │◀── eLLMResponse ──────────│                            │
    │                            │                            │
```

The `InferencePipeline` is an **extension machine** that:
1. Receives `eLLMRequest` from `AgentLoop`
2. Runs request middleware in registration order
3. Forwards to the actual LLM provider
4. Receives `eLLMResponse` from the provider
5. Runs response middleware in reverse order
6. Forwards the (possibly transformed) response back to `AgentLoop`

If no pipeline is registered, `AgentLoop` talks directly to the provider (backward compatible).

---

## 3. Architectural Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Agent Runtime                                  │
│                                                                      │
│  ┌─────────────┐    ┌────────────────────────────────┐              │
│  │ AgentLoop   │───▶│     InferencePipeline (ext)     │              │
│  │ (L6, core)  │    │                                │              │
│  │             │    │  ┌────────┐  ┌────────────┐    │              │
│  │             │    │  │ logger │  │ compressor │    │              │
│  │             │    │  └────────┘  └────────────┘    │              │
│  │             │    │  ┌──────────┐  ┌───────────┐   │              │
│  │             │    │  │ encrypt  │  │ persist   │   │              │
│  │             │    │  └──────────┘  └───────────┘   │              │
│  │             │    │  ┌─────────────┐               │              │
│  │             │    │  │ cid-recorder│               │              │
│  │             │◀───│  └─────────────┘               │              │
│  └─────────────┘    └──────────────┬─────────────────┘              │
│                                     │                                │
│                                     ▼                                │
│                          ┌──────────────────┐                       │
│                          │  LLM Provider     │                       │
│                          │  (L6, ext)        │                       │
│                          └──────────────────┘                       │
│                                                                      │
│  ┌──────────────┐    ┌────────────────────┐                         │
│  │WalletIdentity│    │ dPID Registry       │                         │
│  │ (L2, core)   │───▶│ (on-chain, ext)     │                         │
│  └──────────────┘    └────────────────────┘                         │
│                                                                      │
│  ┌──────────────┐    ┌─────────────────────┐                        │
│  │ Treasury     │    │ StoragePinManager    │                        │
│  │ (L3, core)   │───▶│ (L2, ext)            │                        │
│  └──────────────┘    └─────────────────────┘                        │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 4. Spec Changes by File

### 4.1 Core Types

**File:** `spec/core/Types.p`

#### New type aliases

| Type | Definition | Rationale |
|------|-----------|-----------|
| `CID` | `string` | Content identifier. Used by persistence middleware and WalletIdentity. Core needs this to reference content-addressed data without knowing IPFS internals. |
| `DPID` | `string` | Decentralized Persistent Identifier. The agent's resolvable memory pointer. |
| `MiddlewareName` | `string` | Human-readable middleware identifier (like `ToolName` for tools). |

#### New enum

| Enum | Values | Rationale |
|------|--------|-----------|
| `MiddlewareStage` | `REQUEST, RESPONSE` | Which stage of the pipeline a middleware event relates to. |

#### New records

| Record | Fields | Rationale |
|--------|--------|-----------|
| `PipelineContext` | `requestId: string, sessionKey: SessionKey, timestamp: int, metadata: map[string, string]` | Shared mutable context flowing through the middleware chain. Mirrors `lmstudio-bridge`'s `ShimContext`. The `metadata` map is the communication channel between middleware — one writes a key, the next reads it. |
| `DPIDVersion` | `dpid: DPID, cid: CID, version: int, timestamp: int` | A specific version of the agent's dPID pointing to a CID. Used in dPID update events. |

#### Modified enum

| Enum | Change | Rationale |
|------|--------|-----------|
| `BudgetCategory` | Add `STORAGE` | Memory persistence (IPFS pinning, Filecoin deals) needs its own budget category, distinct from `INFRASTRUCTURE` (compute) and `TOOLS` (gas). |

### 4.2 Core Events

**File:** `spec/core/Events.p`

#### Middleware Pipeline Events (new section)

These events define the **abstract pipeline** — the core knows that inference flows through middleware, but knows nothing about what any specific middleware does.

| Event | Payload | Rationale |
|-------|---------|-----------|
| `eRegisterMiddleware` | `(name: MiddlewareName, handler: machine, priority: int)` | Register a middleware with the pipeline. `priority` determines execution order (lower = earlier in request chain, later in response chain). Mirrors `MiddlewareRunner.use()`. |
| `eUnregisterMiddleware` | `MiddlewareName` | Remove a middleware. |
| `eMiddlewareRequest` | `(context: PipelineContext, request: eLLMRequest_payload)` | Dispatched to each middleware's `onRequest` handler in priority order. Middleware can mutate the context metadata. |
| `eMiddlewareResponse` | `(context: PipelineContext, response: eLLMResponse_payload)` | Dispatched to each middleware's `onResponse` handler in reverse priority order. Middleware can mutate the context metadata. |
| `eMiddlewareNext` | `PipelineContext` | Middleware signals it's done — advance to the next middleware in the chain. Equivalent to calling `next()` in lmstudio-bridge. |
| `eMiddlewareError` | `(middleware: MiddlewareName, error: string, context: PipelineContext)` | A middleware failed. The pipeline decides whether to continue or abort. |

#### dPID / Memory Events (new section)

These events support the identity-bound persistence layer. They are **consumed by extensions**, not by core machines (except WalletIdentity for dPID awareness).

| Event | Payload | Rationale |
|-------|---------|-----------|
| `eResolveDPID` | `DPID` | Resolve the agent's dPID to get the current root CID on boot. |
| `eDPIDResolved` | `DPIDVersion` | Response carrying the current CID and version. |
| `eUpdateDPID` | `(newCid: CID, requestor: machine)` | Request to update the agent's dPID to a new root CID. Requires WalletIdentity signature. |
| `eDPIDUpdated` | `DPIDVersion` | Confirmation that the dPID was updated. |
| `eMemoryRestore` | `CID` | Request to restore agent state from a specific CID. Used during boot. |
| `eMemoryRestored` | `(success: bool, sessionCount: int)` | Confirmation that memory was restored. |

### 4.3 Core Interfaces

**File:** `spec/core/Interfaces.p`

| Function | Signature | Rationale |
|----------|-----------|-----------|
| `DeriveDPID` | `(address: Address): DPID` | Deterministically derive the agent's dPID namespace from its Ethereum address. Pure function — actual registry lookup is an extension concern. |
| `DefaultBudgetAllocation` | *(modify)* | Add `storage: int` field (5%), redistribute: inference=38, tools=14, infrastructure=28, messaging=10, storage=5, reserve=5. |
| `IsBudgetAvailable` | *(modify)* | Handle the new `STORAGE` category. |

### 4.4 WalletIdentity Machine

**File:** `spec/core/machines/WalletIdentity.p`

WalletIdentity gains awareness of the agent's dPID as part of its identity. The wallet address is the agent's identity; the dPID is the agent's **resolvable state pointer**. Together they form: "I am `0xAgent...`, my state lives at `dpid:XYZ`."

| Change | Description |
|--------|-------------|
| Add `var dpid: DPID` | The agent's dPID, derived from its address. |
| Add `var rootCid: CID` | Current root CID of the agent's memory (resolved on boot). |
| Modify `Unlocked.entry` | After `DeriveAddress`, call `DeriveDPID(address)` and emit `eResolveDPID`. |
| Add `eDPIDResolved` handler in `Unlocked` | Store `rootCid`. Emit `eMemoryRestore` so extensions can load state. |
| Add `eUpdateDPID` handler in `Unlocked` | Sign a dPID version update (via existing `PerformSign`), emit signed update. |
| Add `eDPIDUpdated` handler in `Unlocked` | Update local `rootCid`. |
| Add `DeriveDPID` stub | Implementation placeholder, like `DeriveAddress`. |

**What stays the same:** `Locked`, `Signing` states, private key boundary, `eSignRequest`/`eSignResult` flow.

### 4.5 AgentLoop Machine

**File:** `spec/core/machines/AgentLoop.p`

The AgentLoop gains the ability to route inference through an optional middleware pipeline. This is the **only core change to the reasoning path** — everything else is extension-level.

| Change | Description |
|--------|-------------|
| Add `var pipeline: machine` to dependencies | Optional reference to an `InferencePipeline` extension. If absent, AgentLoop talks directly to the provider (backward compatible). |
| Modify `Init.entry` payload | Accept optional `pipeline` machine reference. |
| Modify `SendLLMRequest()` in `Iterating` | If `pipeline` is set, send `eLLMRequest` to `pipeline` instead of directly to `provider`. The pipeline handles middleware execution and forwards to the provider. |
| Add `eMemoryRestored` handler in `Idle` | On boot, when memory restoration completes, the agent knows session count. Can pre-populate context. |

**What stays the same:** CostChecking → Iterating → Responding flow. The pipeline is a transparent proxy — from the AgentLoop's perspective, it still sends `eLLMRequest` and receives `eLLMResponse`. The pipeline just intercepts in between.

**Design principle preserved:** AgentLoop knows nothing about IPFS, encryption, compression, or dPIDs. It only knows "I have an optional pipeline I route inference through."

### 4.6 Treasury Machine

**File:** `spec/core/machines/Treasury.p`

| Change | Description |
|--------|-------------|
| Handle `STORAGE` in `BudgetCategory` | Storage costs flow through the existing `eCostAuthorize` → `eCostAuthorized` pattern. |
| `Critical` state: approve `STORAGE` | Like `INFRASTRUCTURE`, storage is survival-critical. Without memory persistence, the agent loses continuity on restart. |

**What stays the same:** The Funded → Low → Critical → Depleted state machine. All cost authorization patterns.

### 4.7 Extension Types

**File:** `spec/extensions/Types.p`

#### Pipeline Types

| Type | Fields | Rationale |
|------|--------|-----------|
| `MiddlewareEntry` | `name: MiddlewareName, handler: machine, priority: int` | Registered middleware in the pipeline. |

#### IPLD Conversation Types (for persistence middleware)

These mirror the IPLD schema from `lmstudio-bridge-main/schemas/conversation.ipldsch` as P records. They are used by the persistence middleware, not by core.

| Type | Fields | Rationale |
|------|--------|-----------|
| `ConversationNode` | `version: string, request: ConversationRequest, response: ConversationResponse, metadata: ConversationMetadata, timestamp: int, previousConversationCid: CID` | Mirrors IPLD `Conversation`. |
| `ConversationRequest` | `model: string, messages: seq[map[string, string]], parameters: map[string, string]` | The LLM request that was sent. |
| `ConversationResponse` | `id: string, model: string, choices: seq[map[string, string]], usage: map[string, int], created: int` | The LLM response received. |
| `ConversationMetadata` | `shimVersion: string, captureTimestamp: int, encryption: EncryptionConfig, compression: CompressionConfig` | Metadata about the capture. |
| `SessionDAGNode` | `sessionId: string, timestamp: int, conversations: seq[CID], statistics: SessionStatistics, previousSessionCid: CID` | Mirrors IPLD `SessionNode`. |
| `SessionStatistics` | `totalRequests: int, totalTokens: int, totalSize: int, duration: int` | Aggregate session stats. |
| `ConversationIndexEntry` | `conversationCid: CID, timestamp: int, model: string, firstUserMessage: string, tokenCount: int` | For efficient lookup without walking the full DAG. |
| `EncryptionConfig` | `encrypted: bool, algorithm: string, publicKeyFingerprint: string` | Encryption state. |
| `CompressionConfig` | `compressed: bool, algorithm: string, originalSize: int` | Compression state. |
| `PinStatus` | `cid: CID, provider: string, expiresAt: int, redundancy: int` | IPFS pin status for StoragePinManager. |

#### Pin/Storage enums

| Enum | Values | Rationale |
|------|--------|-----------|
| `PinState` | `PINNED, EXPIRING, EXPIRED, UNPINNED` | Pin lifecycle. |

### 4.8 Extension Events

**File:** `spec/extensions/Events.p`

#### Persistence Middleware Events

| Event | Payload | Rationale |
|-------|---------|-----------|
| `eConversationCaptured` | `(sessionKey: SessionKey, node: ConversationNode)` | Persistence middleware formatted a conversation node. |
| `eConversationStored` | `(sessionKey: SessionKey, cid: CID)` | Conversation uploaded to IPFS. |
| `eSessionDAGUpdated` | `SessionDAGNode` | Session DAG updated with new conversation link. |

#### Storage Pin Events

| Event | Payload | Rationale |
|-------|---------|-----------|
| `ePinCheck` | `CID` | Request pin status. |
| `ePinStatus` | `PinStatus` | Pin status response. |
| `ePinRenew` | `(cid: CID, provider: string)` | Request pin renewal. |
| `ePinRenewed` | `PinStatus` | Pin renewed confirmation. |
| `ePinExpiring` | `(cid: CID, daysLeft: int)` | Alert from HeartbeatService. |

#### Adapter Discovery Events

| Event | Payload | Rationale |
|-------|---------|-----------|
| `eAdapterRegistryQuery` | `(capability: string)` | Query on-chain adapter registry. |
| `eAdapterRegistryResult` | `(capability: string, dpid: DPID, cid: CID, reputation: int)` | Registry query result. |

### 4.9 New Extension Machines

#### `InferencePipeline` — The Middleware Runner

**File:** `spec/extensions/machines/InferencePipeline.p` (new)

**Layer:** L6 (Reasoning) — it sits on the inference path.

**Role:** Manages an ordered list of middleware machines and orchestrates the onion-model execution for every LLM request/response cycle. This is the P-language formalization of `lmstudio-bridge`'s `MiddlewareRunner` + `Engine`.

**States:**

| State | Description |
|-------|-------------|
| `Init` | Accept references to AgentLoop and provider. Initialize empty middleware list. |
| `Ready` | Accept `eRegisterMiddleware` / `eUnregisterMiddleware`. Accept `eLLMRequest` from AgentLoop. |
| `RunningRequestChain` | Walk middleware list in priority order, sending `eMiddlewareRequest` to each. Wait for `eMiddlewareNext` before advancing. |
| `AwaitingProvider` | All request middleware done. Forward `eLLMRequest` to actual provider. Wait for `eLLMResponse`. |
| `RunningResponseChain` | Walk middleware list in **reverse** priority order, sending `eMiddlewareResponse` to each. Wait for `eMiddlewareNext`. |
| `Complete` | All response middleware done. Forward `eLLMResponse` to AgentLoop. Return to `Ready`. |

**Key design decisions:**

- **Transparent proxy:** AgentLoop sends `eLLMRequest` to the pipeline and receives `eLLMResponse` — identical interface to talking directly to a provider.
- **Shared context:** A `PipelineContext` is created per request. Its `metadata` map is the inter-middleware communication channel (same as lmstudio-bridge's `context.metadata`).
- **Fail-closed security:** If a middleware marked as `required` fails (e.g., encryption middleware can't encrypt), the pipeline aborts and returns an error response. This mirrors lmstudio-bridge's `upload` middleware checking for `taco-encrypt`.
- **Non-blocking persistence:** Response middleware that performs I/O (IPFS upload, Filecoin flush) should use fire-and-forget patterns. The pipeline returns the response to AgentLoop immediately; persistence happens in background (matching lmstudio-bridge's batch flush queue).

#### Concrete Middleware Extensions (Reference Implementations)

Each of these is a simple machine that handles `eMiddlewareRequest` and/or `eMiddlewareResponse` and emits `eMiddlewareNext` when done.

| Machine | File | Stage | Behavior | lmstudio-bridge Equivalent |
|---------|------|-------|----------|---------------------------|
| `LoggerMiddleware` | `spec/extensions/machines/LoggerMiddleware.p` | Request + Response | Logs request model, message count, response tokens, latency. | `logger.ts` |
| `CompressionMiddleware` | `spec/extensions/machines/CompressionMiddleware.p` | Response | Combines request+response, compresses, stores in `context.metadata["compressedBuffer"]`. | `gzip.ts` |
| `EncryptionMiddleware` | `spec/extensions/machines/EncryptionMiddleware.p` | Response | Reads compressed buffer (or raw), encrypts with agent's public key, stores in `context.metadata["encryptedBuffer"]`. | `taco-encrypt.ts` |
| `PersistenceMiddleware` | `spec/extensions/machines/PersistenceMiddleware.p` | Response | Reads encrypted/compressed/raw payload. Formats as IPLD `ConversationNode`. Batches. Flushes to IPFS. Updates dPID via WalletIdentity. | `upload.ts` |
| `CIDRecorderMiddleware` | `spec/extensions/machines/CIDRecorderMiddleware.p` | Response | Records conversation CIDs and batch root CIDs. Maintains the `ConversationIndex` IPLD structure. | `cid-recorder.ts` |

#### `StoragePinManager` — Self-Sustaining Persistence

**File:** `spec/extensions/machines/StoragePinManager.p` (new)

**Layer:** L2 (Identity & Persistence)

**Role:** Monitors IPFS pin status and autonomously renews pins before they expire, funded by Treasury.

**States:**

| State | Description |
|-------|-------------|
| `Init` | Register with HeartbeatService. |
| `Monitoring` | On heartbeat tick, check pin status of critical CIDs (root memory CID). |
| `Renewing` | Pin expiring. `eCostAuthorize` from Treasury (category: `STORAGE`). If approved, renew. |

---

## 5. SALM Layer Mapping

```
Layer 7: AUTONOMY        → Memory-based reflection via grep/cat on persisted DAG
Layer 6: REASONING       → AgentLoop routes through InferencePipeline
                           InferencePipeline runs middleware chain
                           LoggerMiddleware, CompressionMiddleware (observe/transform)
Layer 5: ORCHESTRATION   → ToolExecutor discovers adapters via dPID registry
                           Virtual filesystem tool (just-bash mount of /memory/)
Layer 4: MESSAGING       → (unchanged)
Layer 3: ECONOMIC        → Treasury gates STORAGE expenses, pin renewals
Layer 2: IDENTITY/PERSIST → WalletIdentity manages dPID
                           EncryptionMiddleware (uses agent key)
                           PersistenceMiddleware (IPFS upload + dPID update)
                           CIDRecorderMiddleware (index maintenance)
                           StoragePinManager (pin lifecycle)
Layer 1: INFRASTRUCTURE  → IPFS node connectivity
```

**Updated "What Goes Where" for `00-layer-model.md`:**

| If you're building... | It belongs in... |
|----------------------|-----------------|
| A middleware that observes/transforms inference payloads | Layer 6 — Middleware extension (registers via `eRegisterMiddleware`) |
| A middleware that persists data to storage | Layer 2 — Persistence middleware (response stage, fire-and-forget) |
| A middleware that encrypts payloads | Layer 2 — Encryption middleware (response stage, before persistence) |
| The middleware pipeline runner itself | Layer 6 — InferencePipeline extension |
| dPID resolution logic | Layer 2 — WalletIdentity or dPID resolver extension |
| IPFS upload/download | Layer 2 — Storage extension (implements `eStoreData`/`eRetrieveData`) |
| IPFS pin monitoring and renewal | Layer 2 — StoragePinManager extension |
| Virtual filesystem tool (`just-bash`) | Layer 5 — Tool extension (registers via `eToolRegister`) |

---

## 6. New Data Flows

### Flow 6: Inference with Middleware Pipeline

```
AgentLoop needs LLM response
        │
        ▼
┌─────────────────────────────────┐
│ L6: AgentLoop (core)            │  Send eLLMRequest to pipeline
│     (identical to current flow  │  (or directly to provider if
│      — just different target)   │   no pipeline registered)
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L6: InferencePipeline (ext)     │  Create PipelineContext
│     Run request middleware:     │
│       → logger.onRequest        │  (logs model, msg count)
│       → [others].onRequest      │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L6: LLM Provider (ext)          │  Actual inference
│     Returns eLLMResponse        │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L6: InferencePipeline (ext)     │  Run response middleware (reverse):
│       → cid-recorder.onResponse │  (records CID)
│       → persist.onResponse      │  (batches for IPFS upload)
│       → encrypt.onResponse      │  (encrypts payload)
│       → compress.onResponse     │  (compresses req+resp)
│       → logger.onResponse       │  (logs tokens, latency)
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L6: AgentLoop (core)            │  Receives eLLMResponse
│     (unchanged from current)    │  Continues reasoning loop
└─────────────────────────────────┘
```

**Layers touched:** L6 → L6 → L6 → L6 → L6

**Key insight:** From AgentLoop's perspective, nothing changed. It sent a request and got a response. The pipeline and all its middleware are invisible to core.

### Flow 7: Persistence Middleware → IPFS → dPID Update

This happens **inside** the persistence middleware's `onResponse`, triggered by Flow 6. It runs in the background (fire-and-forget) so Flow 6 completes immediately.

```
PersistenceMiddleware.onResponse fires
        │
        ▼
┌─────────────────────────────────┐
│ L2: PersistenceMiddleware       │  Format IPLD ConversationNode
│     Read context.metadata keys: │  from pipeline context
│       encryptedBuffer (if any)  │
│       compressedBuffer (if any) │
│     Link to previousConversation│
│     Add to batch buffer         │
└────────────────┬────────────────┘
                 │  (batch full?)
                 ▼
┌─────────────────────────────────┐
│ L2: IPFS Storage (ext)          │  Upload batch archive
│     Return new root CID         │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L2: WalletIdentity (core)       │  Sign dPID version update
│     PerformSign(dPID update tx) │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L2: dPID Registry (ext/on-chain)│  Update pointer
│     Emit eDPIDUpdated           │
└─────────────────────────────────┘
```

**Layers touched:** L2 → L2 → L2 → L2

### Flow 8: Agent Boot with Memory Restoration

```
Kernel starts, WalletIdentity unlocks
        │
        ▼
┌─────────────────────────────────┐
│ L2: WalletIdentity (core)       │  Derive address + dPID
│     Emit eResolveDPID           │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L2: dPID Resolver (ext)         │  Query registry → CID+version
│     Emit eDPIDResolved          │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L2: WalletIdentity (core)       │  Store rootCid
│     Emit eMemoryRestore         │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L2: PersistenceMiddleware (ext) │  Walk IPLD DAG from root CID
│     Build in-memory session map │
│     Build ConversationIndex     │
│     Emit eMemoryRestored        │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L6: AgentLoop (core)            │  Memory available
│     Agent has full history       │
└─────────────────────────────────┘
```

### Flow 9: Autonomous Pin Renewal

```
HeartbeatService ticks
        │
        ▼
┌─────────────────────────────────┐
│ L2: StoragePinManager (ext)     │  Check pin status
│     Root CID pin expires in 3d  │
│     send treasury, eCostAuth    │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L3: Treasury (core)             │  STORAGE = survival-critical
│     Approve                     │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L2: StoragePinManager (ext)     │  Renew pin via storage extension
│     Record expense              │
└─────────────────────────────────┘
```

---

## 7. IPLD Schema (Reference)

The full IPLD schema lives in `lmstudio-bridge-main/schemas/conversation.ipldsch`. It defines the data format for persisted conversations. The PersistenceMiddleware extension must implement this schema when writing to IPFS.

This is **not** a P spec — it is the external serialization format. The P-language equivalents are in `spec/extensions/Types.p` (Section 4.7).

---

## 8. Safety & Liveness Properties

New properties for `spec/safety/Specifications.p`:

### Safety

| Property | Description |
|----------|-------------|
| **PipelineTransparencySafety** | If no middleware is registered, the pipeline passes `eLLMRequest` and `eLLMResponse` through unmodified. The presence of a pipeline never alters the semantic content of inference unless a middleware explicitly does so. |
| **MiddlewareOrderSafety** | Request middleware executes in priority order. Response middleware executes in reverse priority order. No middleware is skipped unless it short-circuits via not calling `next`. |
| **EncryptionBoundarySafety** | If EncryptionMiddleware is registered and PersistenceMiddleware is registered, persistence never writes plaintext. Fail-closed: if encryption fails, persistence aborts. (Mirrors lmstudio-bridge's security check in `upload.ts`.) |
| **DPIDOwnershipSafety** | Only the agent's own WalletIdentity can sign dPID updates. |
| **PinBudgetSafety** | StoragePinManager never renews a pin without Treasury authorization. |

### Liveness

| Property | Description |
|----------|-------------|
| **PipelineCompletionLiveness** | Every `eLLMRequest` entering the pipeline eventually results in an `eLLMResponse` (or `eMiddlewareError`) reaching AgentLoop. |
| **MemoryRestorationLiveness** | On boot, if the agent's dPID resolves to a valid CID, `eMemoryRestored` is eventually emitted. |
| **PinRenewalLiveness** | If a pin is expiring and Treasury is not `DEPLETED`, a renewal is eventually attempted. |
| **DPIDUpdateLiveness** | Every successful IPFS upload eventually results in a dPID update (or explicit error). |

---

## 9. What Does NOT Change

- **Core machine count stays at 5.** `InferencePipeline`, all middleware, and `StoragePinManager` are extensions.
- **MessageBus routing.** No changes.
- **AgentLoop reasoning logic.** The only change is *where* it sends `eLLMRequest` (pipeline vs. direct provider). The think → tool → think loop is unchanged.
- **ToolExecutor execution flow.** Unchanged. Adapter discovery via dPID is additive.
- **Treasury state machine.** Funded → Low → Critical → Depleted gradient unchanged. `STORAGE` is a new budget category following existing patterns.
- **The private key boundary.** Key never leaves WalletIdentity. dPID signing uses existing `PerformSign`.
- **The `just-bash` virtual filesystem** is a tool that registers via `eToolRegister`. No core changes needed.

---

## 10. Open Questions

| # | Question | Impact | Recommendation |
|---|----------|--------|----------------|
| 1 | **Should the `InferencePipeline` be a core machine or extension?** | If core, it's always present (even empty). If extension, it's opt-in. | **Extension.** Backward compatible — agents without middleware skip the pipeline entirely. Follows "minimal core" principle. |
| 2 | **Should `STORAGE` be a core budget category?** | If core, it's in `Types.p`. If extension, Treasury doesn't know about it. | **Core.** Memory persistence is as fundamental as inference. An agent without memory isn't sovereign. |
| 3 | **Should middleware `onRequest`/`onResponse` be separate events or a single `eMiddlewareProcess` with a stage field?** | Separate events are clearer in P but require more event declarations. Single event is more compact. | **Separate events.** Clarity > compactness in a formal spec. Each handler only receives the stage it cares about. |
| 4 | **How should the pipeline handle middleware timeout?** | A stuck middleware blocks the entire inference path. | **Timeout per middleware with configurable deadline.** If a middleware doesn't emit `eMiddlewareNext` within its deadline, the pipeline skips it and logs `eMiddlewareError`. |
| 5 | **Should response middleware be allowed to mutate the `eLLMResponse` payload?** | In lmstudio-bridge, middleware can mutate `openaiResponse`. This is powerful but dangerous. | **Yes, via the `PipelineContext.metadata` map.** Middleware can add/transform metadata freely. Direct mutation of the response content should be opt-in and logged. |
| 6 | **What happens to the existing `SessionManager` extension?** | Its `Session` type overlaps with the new `SessionDAGNode`. | **SessionManager becomes a consumer of the PersistenceMiddleware.** It reads from the IPLD DAG instead of maintaining its own store. If no persistence middleware is present, it falls back to current behavior. |
| 7 | **How does `grep` work without a vector database?** | IPFS has no built-in text search. | **`ConversationIndex` + in-memory search.** The CIDRecorderMiddleware maintains the index. `grep` queries the index first (coarse filter), then fetches only matching CIDs (fine filter). Mirrors ChromaFs's two-pass approach. |
| 8 | **Should the pipeline support streaming (`AsyncGenerator` in lmstudio-bridge)?** | The bridge has `handleChatCompletionStream` that yields chunks. | **Defer to Phase C.** The P spec models non-streaming first. Streaming middleware is an implementation optimization — the formal properties are the same. |

---

## 11. Implementation Sequence

### Phase A: Core Spec Changes

1. Add `CID`, `DPID`, `MiddlewareName`, `PipelineContext`, `DPIDVersion` to `spec/core/Types.p`
2. Add `STORAGE` to `BudgetCategory`, add `MiddlewareStage` enum
3. Add pipeline events and dPID events to `spec/core/Events.p`
4. Add `DeriveDPID` to `spec/core/Interfaces.p`, update `DefaultBudgetAllocation`
5. Update `WalletIdentity.p` with dPID state and handlers
6. Modify `AgentLoop.p` to accept optional `pipeline` and route `eLLMRequest` through it
7. Add new safety/liveness properties to `Specifications.p`

### Phase B: Extension Specs

1. Write `InferencePipeline.p` — the middleware runner state machine
2. Write `LoggerMiddleware.p` — simplest middleware, validates the pattern
3. Write `CompressionMiddleware.p` — response-stage payload compression
4. Write `EncryptionMiddleware.p` — response-stage encryption with fail-closed
5. Write `PersistenceMiddleware.p` — IPFS upload + dPID update + batch queue
6. Write `CIDRecorderMiddleware.p` — conversation index maintenance
7. Write `StoragePinManager.p` — autonomous pin renewal
8. Add extension types and events to `spec/extensions/Types.p` and `Events.p`

### Phase C: TypeScript Implementation

1. Add core types (`CID`, `DPID`, `PipelineContext`) to `src/types.ts`
2. Add pipeline + dPID events to `src/events.ts`
3. Implement `InferencePipeline.ts` — port `MiddlewareRunner` pattern from lmstudio-bridge
4. Implement `LoggerMiddleware.ts` — port `logger.ts`
5. Update `WalletIdentity.ts` with dPID derivation
6. Update `AgentLoop.ts` to route through pipeline
7. Implement persistence middleware with local-first stubs (write JSON to disk)
8. Wire into `kernel.ts` and `test-harness.ts`

### Phase D: Real Integration

1. Replace stubs with `js-ipfs-unixfs-importer`/`exporter`
2. Implement dPID registry resolver
3. Implement `EncryptionMiddleware.ts` (port taco-encrypt pattern)
4. Implement `just-bash` virtual filesystem tool
5. End-to-end: boot → converse → kill → re-boot → verify memory restored

---

## 12. Implementation Impact Assessment

### What changes in `haven-core` (this repo)

The changes are **minimal and additive** to the existing implementation. No existing behavior is broken.

#### `src/types.ts` — Small additions

| Change | Effort | Breaking? |
|--------|--------|-----------|
| Add `CID`, `DPID`, `MiddlewareName` type aliases | Trivial | No |
| Add `STORAGE` to `BudgetCategory` enum | Small | **Potentially** — any `switch` on `BudgetCategory` needs a new `case`. See below. |
| Add `PipelineContext`, `DPIDVersion` interfaces | Small | No |
| Add `storage: number` to `BudgetAllocation` interface | Small | **Yes** — existing code constructing `BudgetAllocation` objects must include the new field. |

**Breaking change mitigation:** The only place `BudgetAllocation` is constructed is `defaultBudgetAllocation()` in `interfaces.ts`. Update that one function and everything flows through.

#### `src/events.ts` — Additive only

| Change | Effort | Breaking? |
|--------|--------|-----------|
| Add middleware pipeline events to `EventMap` | Small | No — additive keys in a TypeScript interface |
| Add dPID/memory events to `EventMap` | Small | No |

No existing event shapes change. New events are simply new keys in the `EventMap` interface.

#### `src/interfaces.ts` — Two function updates

| Change | Effort | Breaking? |
|--------|--------|-----------|
| Add `deriveDPID(address: Address): DPID` function | Trivial | No |
| Update `defaultBudgetAllocation()` to include `storage` | Small | No — callers destructure the result |
| Update `isBudgetAvailable()` switch to handle `STORAGE` | Small | No |

#### `src/machines/AgentLoop.ts` — One-line routing change

| Change | Effort | Breaking? |
|--------|--------|-----------|
| Add optional `pipeline: Machine` to constructor deps | Small | No — optional field |
| In `sendLLMRequest()`, route to `pipeline` if set, else `provider` | **1 line change** | No — default behavior unchanged |
| Add `eMemoryRestored` handler in `Idle` state | Small | No |

The critical insight: `AgentLoop` already has `setProvider(provider: Machine)` which lets you swap the LLM target at runtime. The pipeline change is the same pattern — `sendTo(this.pipeline ?? this.provider, "eLLMRequest", ...)`. One line.

#### `src/machines/WalletIdentity.ts` — New state + handlers

| Change | Effort | Breaking? |
|--------|--------|-----------|
| Add `dpid: DPID` and `rootCid: CID` instance variables | Trivial | No |
| Call `deriveDPID()` in `Unlocked.onEntry` | Small | No |
| Add `eDPIDResolved`, `eUpdateDPID`, `eDPIDUpdated` handlers in `Unlocked` | Medium | No — new handlers on an existing state |
| Add `DeriveDPID` stub function | Trivial | No |

No changes to `Locked` or `Signing` states. No changes to the `CryptoAdapter` interface.

#### `src/machines/Treasury.ts` — Handle new budget category

| Change | Effort | Breaking? |
|--------|--------|-----------|
| Add `STORAGE` case in `Critical` state's `eCostAuthorize` handler (approve like `INFRASTRUCTURE`) | Small | No |

The existing `switch/if` chains in `Funded`, `Low`, `Critical`, `Depleted` states need to handle `BudgetCategory.STORAGE`. In `Critical`, storage is approved (survival-critical). In other states, it flows through the normal budget check.

#### `src/kernel.ts` — Optional pipeline wiring

| Change | Effort | Breaking? |
|--------|--------|-----------|
| Accept optional `pipeline` in constructor or via setter | Small | No — additive |
| Wire pipeline into `AgentLoop` if provided | Small | No |
| Add `pipeline` to `waitForIdle()` if present | Trivial | No |

The kernel already follows a "construct then wire" pattern (see `setBus()`, `setAgent()`, `setProvider()`). Adding `setPipeline()` is the same pattern.

#### New files in `src/` (all new, no modifications)

| File | Role |
|------|------|
| `src/machines/InferencePipeline.ts` | Middleware runner — port of `lmstudio-bridge`'s `MiddlewareRunner` + `Engine` |
| `src/machines/middleware/LoggerMiddleware.ts` | Reference: logs request/response (port `logger.ts`) |
| `src/machines/middleware/CompressionMiddleware.ts` | Reference: gzip payload (port `gzip.ts`) |
| `src/machines/middleware/EncryptionMiddleware.ts` | Reference: encrypt payload (port `taco-encrypt.ts`) |
| `src/machines/middleware/PersistenceMiddleware.ts` | Reference: IPFS upload + dPID update (port `upload.ts`) |
| `src/machines/middleware/CIDRecorderMiddleware.ts` | Reference: index maintenance (port `cid-recorder.ts`) |
| `src/machines/StoragePinManager.ts` | Autonomous pin renewal |

**Total haven-core changes: ~6 existing files modified (small changes each), ~7 new files.**

---

### What changes in `haven-adapters-main`

**Short answer: Nothing is required. Everything is additive.**

The haven-adapters repo currently has 3 adapters:
- `EthereumCryptoAdapter` — implements `CryptoAdapter` interface → **No change**
- `XmtpChannel` — messaging channel → **No change**
- `LmStudioProvider` — LLM provider (handles `eLLMRequest`) → **No change**

The middleware pipeline sits **between** `AgentLoop` and `LmStudioProvider`. Neither end changes its interface. The provider still receives `eLLMRequest` and sends `eLLMResponse` — it doesn't know or care that a pipeline intercepted the call.

#### Optional new adapters (additive, not required)

| Potential Adapter | Interface | Dependencies | When |
|------------------|-----------|--------------|------|
| `IPFSStorageAdapter` | `eStoreData`/`eRetrieveData` | `js-ipfs-unixfs` | Phase D |
| `DPIDResolverAdapter` | `eResolveDPID`/`eDPIDResolved` | `dpid.org` API or on-chain | Phase D |
| `FilecoinPinAdapter` | `ePinRenew`/`ePinRenewed` | `filecoin-pin` | Phase D |

These would be new files in `haven-adapters-main/src/` following the existing pattern:
```
haven-adapters-main/src/
├── ethereum/EthereumCryptoAdapter.ts    (unchanged)
├── providers/LmStudioProvider.ts        (unchanged)
├── xmtp/XmtpChannel.ts                 (unchanged)
├── ipfs/IPFSStorageAdapter.ts           (new, Phase D)
├── dpid/DPIDResolverAdapter.ts          (new, Phase D)
└── filecoin/FilecoinPinAdapter.ts       (new, Phase D)
```

#### Why `LmStudioProvider` doesn't change

The `LmStudioProvider` handles `eLLMRequest` and returns `eLLMResponse`. Today:

```
AgentLoop ──eLLMRequest──▶ LmStudioProvider ──eLLMResponse──▶ AgentLoop
```

After the pipeline:

```
AgentLoop ──eLLMRequest──▶ InferencePipeline ──eLLMRequest──▶ LmStudioProvider
                                                                    │
AgentLoop ◀──eLLMResponse── InferencePipeline ◀──eLLMResponse──────┘
```

`LmStudioProvider` still gets the same `eLLMRequest` event and returns the same `eLLMResponse`. The pipeline is transparent to it.

---

### Summary

| Repo | Existing files modified | New files | Breaking changes |
|------|------------------------|-----------|------------------|
| **haven-core** | 6 (types, events, interfaces, AgentLoop, WalletIdentity, Treasury) | ~7 | `BudgetAllocation.storage` field (1 constructor to update) |
| **haven-adapters** | 0 | 0 (Phase D: 3 optional new adapters) | None |

The middleware pipeline is the key architectural insight: by intercepting the inference path **between** AgentLoop and the provider, we avoid touching either endpoint. The `lmstudio-bridge` pattern proves this works — its middleware runs without modifying the LM Studio client or the OpenAI-compatible API surface.

---

## References

- **`lmstudio-bridge-main/`** — The middleware pipeline implementation this plan is based on
  - `src/types/middleware.ts` — `Middleware` interface, `ShimContext`, payloads
  - `src/pipeline/middleware-runner.ts` — Onion-model `MiddlewareRunner`
  - `src/pipeline/engine.ts` — `Engine` tying pipeline to client
  - `src/middleware/logger.ts` — Logger middleware (reference)
  - `src/middleware/gzip.ts` — Compression middleware
  - `src/middleware/taco-encrypt.ts` — Threshold encryption middleware
  - `src/middleware/upload.ts` — Filecoin persistence middleware with batch queue
  - `src/middleware/cid-recorder.ts` — CID recording middleware
  - `schemas/conversation.ipldsch` — IPLD conversation schema
- [Mintlify ChromaFs](https://mintlify.com/blog/chromafs) — Virtual filesystem inspiration
- [js-ipfs-unixfs](https://github.com/ipfs/js-ipfs-unixfs) — IPFS UnixFS for JavaScript
- [dPID](https://dpid.org) — Decentralized Persistent Identifiers
- [IPLD](https://ipld.io) — InterPlanetary Linked Data
- [Haven Sovereign Agent Kernel](../README.md) — This project
- [SALM Layer Model](00-layer-model.md) — 7-layer architecture
- [Sovereignty Roadmap](04-sovereignty-roadmap.md) — Phased roadmap
