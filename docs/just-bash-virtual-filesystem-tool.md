# just-bash: Virtual Filesystem Tool for Sovereign Agents

> **Origin:** Conversation analyzing Mintlify's ChromaFs virtual filesystem, `just-bash` by Vercel Labs, `js-ipfs-unixfs`, dPIDs, and how they map onto the Haven sovereign agent architecture.

> **Core thesis:** `just-bash` is a **Layer 5 Tool Extension** that gives the sovereign agent a Unix shell interface to its own persistent memory. It registers with `ToolExecutor` via `eToolRegister`, implements `just-bash`'s pluggable `IFileSystem` interface backed by the agent's IPLD conversation DAG, and lets the agent explore its memory using standard Unix commands (`ls`, `cat`, `grep`, `find`, `cd`).

---

## Table of Contents

1. [Background](#1-background)
2. [Where just-bash Sits in the Architecture](#2-where-just-bash-sits-in-the-architecture)
3. [SALM Layer Placement](#3-salm-layer-placement)
4. [Relationship to Existing Spec](#4-relationship-to-existing-spec)
5. [How It Works](#5-how-it-works)
6. [Integration Points](#6-integration-points)
7. [Implementation Plan](#7-implementation-plan)
8. [What just-bash Is](#8-what-just-bash-is)
9. [Open Questions](#9-open-questions)

---

## 1. Background

### The Mintlify Inspiration

Mintlify built **ChromaFs** — a virtual filesystem that intercepts Unix commands and translates them into queries against a Chroma vector database. Their assistant could explore documentation using `grep`, `cat`, `ls`, and `find` as if it were a real filesystem. Key properties:

- Session creation: ~100ms (vs ~46s for sandbox containers)
- Zero marginal compute cost (reuses existing DB)
- Built on `just-bash` by Vercel Labs — a TypeScript bash reimplementation with a pluggable `IFileSystem` interface
- Agent explores docs by running shell commands, not by querying a vector database API

### The Sovereign Agent Application

For a sovereign agent, the same pattern applies but with a critical difference: instead of querying a documentation database, the agent queries **its own persistent memory** stored as an IPLD DAG on IPFS, addressed by its dPID.

The agent doesn't need to learn a new API to search its memory. It already knows how to use Unix commands (LLMs are trained on vast amounts of shell interaction). By mounting its memory as a virtual filesystem, the agent can:

- `ls /memory/sessions/` — list past conversation sessions
- `cat /memory/sessions/session_0x123/conversations/0.json` — read a specific conversation
- `grep -ri "deploy contract" /memory/sessions/` — search across all memory
- `find /memory/ -name "*.json" -newer /memory/sessions/session_0x100/` — find recent conversations

### The just-bash Package

`just-bash` (from Vercel Labs) is a TypeScript reimplementation of bash that:

- Supports `grep`, `cat`, `ls`, `find`, `cd`, and ~79 other commands
- Exposes a pluggable `IFileSystem` interface — you provide the filesystem, it handles parsing, piping, and flag logic
- Runs entirely in-memory with no real filesystem access (sandboxed)
- Has a comprehensive security model (see `THREAT_MODEL.md`)
- All writes throw `EROFS` (Read-Only File System) by default — stateless, no corruption risk

The `IFileSystem` interface is the key integration point. We implement it to translate filesystem calls into IPLD DAG queries via `js-ipfs-unixfs`.

---

## 2. Where just-bash Sits in the Architecture

### In the Spec: Layer 5 Tool Extension

`just-bash` is a **tool extension** that registers with the core `ToolExecutor` machine. It is NOT a core machine — the kernel's 5 core machines don't change.

```
Core Kernel (unchanged):
  ┌──────────────────────────────────────────────────────┐
  │  WalletIdentity ←→ Treasury ←→ AgentLoop            │
  │                                    ↕                  │
  │               MessageBus ←→ ToolExecutor             │
  └──────────────────────────────────────────────────────┘
                                    ↕
                         eToolRegister / eExecuteTool
                                    ↕
  ┌──────────────────────────────────────────────────────┐
  │  Extension: JustBashTool                              │
  │    - Implements IFileSystem backed by IPLD DAG        │
  │    - Translates shell commands to DAG queries          │
  │    - Returns results via eToolResult                   │
  └──────────────────────────────────────────────────────┘
```

### In the Code: Phase D Implementation

From `docs/09-dpid-ipfs-memory-layer-plan.md`, Section 11 (Implementation Sequence):

> **Phase D: Real Integration**
> 4. Implement `just-bash` virtual filesystem tool

The implementation would be a new file (e.g., `src/machines/tools/JustBashTool.ts` or in `haven-adapters-main/`).

### In the README Repository Structure

The README's repository structure shows tools register through the extension layer:

```
haven-core/
├── implementation/
│   └── src/
│       └── machines/
│           └── ToolExecutor.ts    ← dispatches to registered tools
└── extensions/                     ← just-bash tool lives here conceptually
```

---

## 3. SALM Layer Placement

From the Sovereign Agent Layer Model (`docs/00-layer-model.md`):

| Layer | Role | just-bash Relevance |
|-------|------|-------------------|
| **Layer 7: Autonomy** | Self-directed goals | Agent uses memory search for reflection and planning |
| **Layer 6: Reasoning** | LLM inference, decision making | AgentLoop decides to search memory, calls tool |
| **Layer 5: Orchestration** | **Tool registration and dispatch** | **just-bash registers here via `eToolRegister`** |
| Layer 4: Messaging | Message routing | (not involved) |
| Layer 3: Economic | Treasury, cost gating | Tool execution cost-gated by Treasury |
| Layer 2: Identity & Persistence | Wallet, storage, dPID | IPLD DAG storage, dPID resolution for memory root |
| Layer 1: Infrastructure | Compute, IPFS node | IPFS connectivity |

**Primary placement: Layer 5 (Orchestration)**

The `docs/09-dpid-ipfs-memory-layer-plan.md` confirms this in its SALM mapping:

```
Layer 5: ORCHESTRATION → Virtual filesystem tool (just-bash mount of /memory/)
```

And in the "What Goes Where" table:

| If you're building... | It belongs in... |
|----------------------|-----------------|
| Virtual filesystem tool (`just-bash`) | Layer 5 — Tool extension (registers via `eToolRegister`) |

---

## 4. Relationship to Existing Spec

### What Already Exists

The following spec documents and code already reference or accommodate just-bash:

| Document | Reference |
|----------|-----------|
| `docs/09-dpid-ipfs-memory-layer-plan.md` §5 | "Layer 5: ORCHESTRATION → Virtual filesystem tool (just-bash mount of /memory/)" |
| `docs/09-dpid-ipfs-memory-layer-plan.md` §9 | "The `just-bash` virtual filesystem is a tool that registers via `eToolRegister`. No core changes needed." |
| `docs/09-dpid-ipfs-memory-layer-plan.md` §11 Phase D | "4. Implement `just-bash` virtual filesystem tool" |
| `docs/00-layer-model.md` | "A new tool (web search, code execution, etc.) → Layer 5 — Tool extension (registers via `eToolRegister`)" |
| `docs/01-extension-guide.md` | Full pattern for building tool extensions |
| `spec/core/machines/ToolExecutor.p` | The core machine that dispatches to all registered tools |

### What Doesn't Need to Change

- **Core machine count stays at 5.** just-bash is an extension.
- **ToolExecutor.p** — No changes. just-bash registers via the existing `eToolRegister` event.
- **AgentLoop.p** — No changes. It calls tools via `eExecuteTool` as usual.
- **Treasury.p** — No changes. Tool cost gating works via existing `eCostAuthorize` flow.
- **MessageBus.p** — No changes.
- **WalletIdentity.p** — No changes (dPID already added per the memory plan).

---

## 5. How It Works

### The Full Data Flow

```
AgentLoop (L6) decides "I need to recall a past conversation about deploying a contract"
    │
    ▼
AgentLoop sends eExecuteTool: { name: "bash", arguments: { command: 'grep -ri "deploy contract" /memory/sessions/' } }
    │
    ▼
ToolExecutor (L5) looks up "bash" in registered tools
    │
    ▼
ToolExecutor sends eCostAuthorize to Treasury (L3)
    │  (cost: zero or minimal — off-chain, in-memory operation)
    ▼
Treasury approves → ToolExecutor dispatches to JustBashTool
    │
    ▼
JustBashTool:
    1. Parses the bash command via just-bash's parser
    2. just-bash intercepts the `grep` command
    3. IFileSystem adapter translates `/memory/sessions/` to IPLD DAG traversal:
       a. Resolve agent's dPID → root CID (cached from boot)
       b. Walk the SessionDAGNode links using js-ipfs-unixfs-exporter
       c. For grep: use ConversationIndex as coarse filter (which CIDs contain "deploy contract"?)
       d. Fetch only matching conversation nodes
       e. Run fine-filter regex in memory via just-bash's grep implementation
    4. Returns results as string
    │
    ▼
ToolExecutor receives result → sends eToolResult to AgentLoop
    │
    ▼
AgentLoop incorporates the memory search results into its reasoning context
```

### IFileSystem Implementation

The `just-bash` `IFileSystem` interface requires these methods:

| Method | IPLD DAG Mapping |
|--------|-----------------|
| `readdir(path)` | Walk DAG links at the given path. Return child names. |
| `readFile(path)` | Resolve path → CID → fetch and reassemble via `ipfs-unixfs-exporter` |
| `stat(path)` | Check if path exists in the in-memory path tree |
| `exists(path)` | Lookup in `Set<string>` of known paths |

### Virtual Filesystem Layout

The agent's memory is exposed as:

```
/memory/
├── sessions/
│   ├── session_<id_1>/
│   │   ├── meta.json              ← SessionStatistics
│   │   └── conversations/
│   │       ├── 0.json             ← First ConversationNode
│   │       ├── 1.json             ← Second ConversationNode
│   │       └── ...
│   ├── session_<id_2>/
│   │   └── ...
│   └── ...
├── index/
│   ├── by-model.json              ← ConversationIndex filtered by model
│   ├── by-date.json               ← ConversationIndex filtered by timestamp
│   └── by-topic.json              ← ConversationIndex by first user message
└── identity/
    ├── address.txt                ← Agent's wallet address
    ├── dpid.txt                   ← Agent's dPID
    └── root-cid.txt               ← Current root CID
```

### Bootstrapping (On Agent Boot)

1. `WalletIdentity` resolves dPID → root CID (per the memory plan)
2. `PersistenceMiddleware` walks the IPLD DAG and builds in-memory structures:
   - `Set<string>` of all file paths
   - `Map<string, string[]>` mapping directories to children
   - `ConversationIndex` for efficient search
3. `JustBashTool` receives these structures (or a reference to the persistence middleware)
4. `ls`, `cd`, and `find` resolve in local memory with **no network calls**
5. `cat` lazily fetches from IPFS only when content is requested
6. `grep` uses ConversationIndex as coarse filter, then fetches only matching CIDs

This mirrors exactly how Mintlify's ChromaFs works — tree in memory, content fetched on demand.

---

## 6. Integration Points

### Dependencies

| Component | Role | Package |
|-----------|------|---------|
| `just-bash` | Bash parser/interpreter with IFileSystem | `just-bash` npm package |
| `js-ipfs-unixfs-exporter` | Fetch and reassemble files from IPLD DAGs | `ipfs-unixfs-exporter` |
| `js-ipfs-unixfs-importer` | Write files to IPLD DAGs | `ipfs-unixfs-importer` (used by PersistenceMiddleware) |
| `PersistenceMiddleware` | Provides the IPLD DAG that just-bash reads | Haven extension (from memory plan) |
| `CIDRecorderMiddleware` | Provides the ConversationIndex for grep optimization | Haven extension (from memory plan) |
| `WalletIdentity` | Provides the dPID → root CID resolution | Haven core machine |

### Event Flow

```
Registration:
  JustBashTool ──eToolRegister──▶ ToolExecutor
    { name: "bash", description: "Virtual filesystem shell for agent memory", estimatedCost: { amounts: [], category: TOOLS } }

Execution:
  AgentLoop ──eExecuteTool──▶ ToolExecutor ──eExecuteTool──▶ JustBashTool
  JustBashTool ──eToolResult──▶ ToolExecutor ──eToolResult──▶ AgentLoop
```

### Access Control

Following the Mintlify ChromaFs pattern:
- The filesystem is **read-only** (`EROFS` on write attempts) — the agent explores freely but never mutates its memory through the shell
- Memory writing happens exclusively through the `PersistenceMiddleware` (which formats, encrypts, and uploads via the inference pipeline)
- Path-level access control can prune the filesystem tree before the agent sees it (useful for multi-tenant or permission-scoped scenarios)

---

## 7. Implementation Plan

### Phase D.4 (from docs/09-dpid-ipfs-memory-layer-plan.md)

| Step | Description | Dependencies |
|------|-------------|-------------|
| 1. Create `IPFSFileSystem` class | Implements `just-bash`'s `IFileSystem` interface. Backed by in-memory path tree + lazy IPLD fetching. | `js-ipfs-unixfs-exporter`, `PersistenceMiddleware` memory structures |
| 2. Create `JustBashTool` machine | Wraps `just-bash`'s `Bash` class with the `IPFSFileSystem`. Registers as tool. Handles `eExecuteTool`. | `just-bash` package, `IPFSFileSystem` |
| 3. Optimize grep | Intercept `grep` commands. Use `ConversationIndex` as coarse filter. Bulk-prefetch matching CIDs. Hand filtered file list back to just-bash for fine-filter regex. | `CIDRecorderMiddleware` index |
| 4. Wire into kernel | Register `JustBashTool` during boot. Ensure it initializes after `PersistenceMiddleware` has built the path tree. | `kernel.ts` boot sequence |
| 5. Test end-to-end | Agent boots → memory restored → runs `grep` on memory → gets results → incorporates into reasoning | All above |

### File Locations

| File | Location | Rationale |
|------|----------|-----------|
| `IPFSFileSystem.ts` | `haven-adapters-main/src/filesystem/` | Adapter — depends on IPFS libraries |
| `JustBashTool.ts` | `haven-adapters-main/src/tools/` or `src/machines/tools/` | Tool extension — registers with ToolExecutor |
| `JustBashTool.p` | `spec/extensions/machines/` | P-language formal spec (optional, for model checking) |

---

## 8. What just-bash Is

### Package Overview

`just-bash` is a Vercel Labs project — a TypeScript implementation of a bash interpreter with an in-memory virtual filesystem. Key properties:

- **~79 built-in commands** including `grep`, `cat`, `ls`, `find`, `cd`, `head`, `tail`, `wc`, `sort`, `uniq`, `awk`, `sed`, `jq`, `python3` (via WASM)
- **Pluggable `IFileSystem`** — the critical integration point for Haven
- **Security-first design** — comprehensive threat model, defense-in-depth, no child_process spawning, no eval, sandboxed execution
- **No WASM dependencies** (except optional Python3 and SQLite)
- **Read-only by default** — `OverlayFs` writes to memory only, never touches real filesystem

### Monorepo Structure

```
just-bash-main/
├── packages/just-bash/          ← The core package (npm: just-bash)
│   └── src/
│       ├── parser/              ← Recursive descent bash parser
│       ├── interpreter/         ← AST execution engine
│       ├── commands/            ← ~79 command implementations
│       ├── fs.ts                ← IFileSystem interface
│       └── overlay-fs/          ← In-memory VFS with overlay
├── examples/
│   ├── bash-agent/              ← AI agent using bash-tool
│   ├── custom-command/          ← Custom command registration
│   └── website/                 ← Web-based shell demo
└── THREAT_MODEL.md              ← Comprehensive security analysis
```

### Why just-bash (Not a Real Shell)

| Approach | Boot Time | Cost | Security | Agent Compatibility |
|----------|-----------|------|----------|-------------------|
| Real sandbox (container) | ~46s | ~$0.014/conversation | High (isolated) | High |
| ChromaFs (Chroma DB) | ~100ms | ~$0 (reuses DB) | High (read-only) | High |
| **just-bash + IPLD** | **~100ms** | **~$0 (reuses IPFS)** | **High (sandboxed, read-only)** | **High** |

The agent doesn't need a real filesystem. It needs the **illusion** of one — the same insight Mintlify had. `just-bash` provides that illusion with zero infrastructure overhead.

---

## 9. Open Questions

| # | Question | Impact | Recommendation |
|---|----------|--------|----------------|
| 1 | **Should `JustBashTool` live in `haven-core` or `haven-adapters`?** | If core, it's always available. If adapter, it's opt-in. | **Adapter.** It depends on `just-bash` npm package and `js-ipfs-unixfs`, which are runtime dependencies. Core has zero runtime dependencies. |
| 2 | **Should there be a single "bash" tool or separate tools per command?** | Single tool = one registration, flexible. Per-command = more granular cost control. | **Single "bash" tool.** The agent sends arbitrary bash commands. Parsing and dispatch is just-bash's job, not ToolExecutor's. |
| 3 | **How does the agent discover the `bash` tool's capabilities?** | The agent needs to know what commands are available. | **Tool description + system prompt.** The `ToolDefinition.description` lists available commands. The system prompt explains the `/memory/` filesystem structure. |
| 4 | **Should grep optimization be transparent or explicit?** | Transparent = just-bash handles it. Explicit = agent calls a separate search tool. | **Transparent.** The agent runs `grep` and the IFileSystem adapter optimizes under the hood using ConversationIndex. The agent doesn't need to know about the optimization. |
| 5 | **Should the virtual filesystem support writes for note-taking?** | Allowing writes to `/memory/notes/` could let the agent create persistent scratchpads. | **Defer.** Start read-only (matching Mintlify's EROFS pattern). Writing requires a separate persistence flow and opens mutation concerns. |
| 6 | **How does caching work across sessions?** | The in-memory path tree and fetched content should be cached. | **Cache on boot, invalidate on dPID update.** When `eDPIDUpdated` fires (new content persisted), refresh the path tree. Content cache uses LRU with configurable size. |

---

## References

- **Conversation:** `convo.txt` — Full discussion of ChromaFs, IPFS, dPIDs, IPLD schemas, and sovereign agent architecture
- **just-bash:** `just-bash-main/` — The Vercel Labs bash reimplementation
  - `just-bash-main/packages/just-bash/src/fs.ts` — `IFileSystem` interface
  - `just-bash-main/CLAUDE.md` — Architecture overview
  - `just-bash-main/THREAT_MODEL.md` — Security analysis
- **Memory Plan:** `docs/09-dpid-ipfs-memory-layer-plan.md` — Inference pipeline + dPID + persistent memory plan
- **SALM:** `docs/00-layer-model.md` — 7-layer architecture model
- **Extension Guide:** `docs/01-extension-guide.md` — How to build tool extensions
- **ToolExecutor Spec:** `spec/core/machines/ToolExecutor.p` — Core tool dispatch machine
- [Mintlify ChromaFs Blog Post](https://mintlify.com/blog/chromafs) — Virtual filesystem inspiration
- [js-ipfs-unixfs](https://github.com/ipfs/js-ipfs-unixfs) — IPFS UnixFS for JavaScript
- [dPID](https://dpid.org) — Decentralized Persistent Identifiers
