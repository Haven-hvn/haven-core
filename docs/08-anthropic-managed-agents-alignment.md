# Strategic alignment: haven-core direction and Anthropic Managed Agents

This document records how the direction described in this repository’s architecture and roadmaps relates to the design principles in Anthropic’s engineering article on Managed Agents. It is **not** a claim of API compatibility or feature parity with Anthropic’s hosted product; it is a **conceptual mapping** for strategic planning.

**Primary reference:** [Scaling Managed Agents: Decoupling the brain from the hands](https://www.anthropic.com/engineering/managed-agents) (Anthropic Engineering, 2026).

---

## What the Anthropic article argues

The [Managed Agents post](https://www.anthropic.com/engineering/managed-agents) makes several recurring points:

1. **Harnesses encode assumptions that go stale** as models improve; interfaces should outlive any one harness implementation.
2. **Virtualize agent components** analogously to OS abstractions: a **session** (durable, append-only event log), a **harness** (loop that calls the model and routes tool use), and a **sandbox** (execution environment). Implementations of each should be swappable without breaking the others.
3. **Avoid “pet” infrastructure** where one container couples session, harness, and workspace; prefer **cattle** that can fail and be replaced.
4. **Decouple the “brain”** (model + harness) from **“hands”** (tools/sandboxes) and from **session storage**, so each can fail or scale independently. The article describes hands behind a uniform tool shape (`execute(name, input) → string`), containers provisioned only when needed, and harness recovery via a durable session (`wake`, `getSession`, `emitEvent` in their design).
5. **Security:** credentials must not be reachable from the environment where **untrusted generated code** runs; patterns include resource-bound auth, vaults, and proxies (e.g. MCP) so the harness does not see raw secrets.
6. **Session ≠ context window:** the durable session is a **context object outside the model**; `getEvents()`-style slicing separates **recoverable storage** from **harness-side transforms** (compaction, cache-friendly layout, etc.).
7. **Many brains, many hands:** scale stateless harnesses; attach sandboxes and diverse tools only when needed; avoid coupling all “hands” to a single fragile unit.

The conclusion frames this as **meta-harness** design: stable interfaces around the model, not commitment to one harness or sandbox implementation. See the [full article](https://www.anthropic.com/engineering/managed-agents) for examples (TTFT, VPC connectivity, and “context anxiety” in older harnesses).

---

## How haven-core’s documented direction maps to those ideas

The following ties this repo’s **`docs/`** plans and the SALM model ([00-layer-model.md](./00-layer-model.md)) to the themes above. Related files: [03-implementation-roadmap.md](./03-implementation-roadmap.md), [04-sovereignty-roadmap.md](./04-sovereignty-roadmap.md), [06-tee-self-attesting-lineage-plan.md](./06-tee-self-attesting-lineage-plan.md), [07-haven-sdk-cdk-agnostic-plan.md](./07-haven-sdk-cdk-agnostic-plan.md).

| Anthropic theme | haven-core / docs expression |
|-----------------|------------------------------|
| Stable interfaces; swappable implementations | **SALM** separates layers (messaging, orchestration, reasoning, identity, economics). Extensions plug in via **events and contracts**; the kernel stays minimal. Same *spirit* as “opinionated about interface shape, not what runs behind it” ([Managed Agents](https://www.anthropic.com/engineering/managed-agents)). |
| Session vs harness vs sandbox | **AgentLoop** (L6) reasons; **ToolExecutor** (L5) dispatches tools; **WalletIdentity** / storage extensions (L2) hold persistence and signing. **04-sovereignty-roadmap** adds a **WASM sandbox** and **host-boundary credential injection**, aligning with **separate execution** from **identity**. |
| Cattle not pets | **03-implementation-roadmap** Phase 5: **InfrastructureManager**, Akash, Docker, lease renewal, **migration** (save → deploy → recover). **07-haven-sdk-cdk-agnostic-plan**: provider-agnostic **haven-sdk** keeps heavy orchestration out of the kernel—disposable workloads and adapter boundaries echo the article’s replaceable components ([Managed Agents](https://www.anthropic.com/engineering/managed-agents)). |
| Durable context outside the model | Phase 3 **SessionManager** + optional **Filecoin/Arweave** (Phases 3–5): trajectory toward **recoverable state** not tied to a single process. Anthropic’s **`getEvents()`**-style interrogation of an append-only log is a **specific product API**; our docs specify **persistence extensions** and consolidation—**same architectural intent**, different interface details. |
| Secrets off the untrusted execution surface | SALM explicitly forbids **ToolExecutor** holding private keys; signing via **WalletIdentity**. **04-sovereignty-roadmap**: WASM tools, **allowlists**, **leak detection**, later **KMS/TEE/smart contract wallet**. Parallel in motivation to the article’s **vault / proxy** patterns ([Managed Agents](https://www.anthropic.com/engineering/managed-agents)). |
| Many brains / many hands | **SubagentManager** (extension, Phase 4 in roadmap) models **parallel work**; **06-tee-self-attesting-lineage-plan** models **parent–child** TEE instances with **attestation** and **fail-closed** policy—**separate bootstrapped children** rather than one pet process holding every hand. Product direction may give **children their own wallets** (evolution beyond the current reference P spec). |
| Meta-harness / future-proofing | Formal **P spec** + typed TS kernel + **extension-first** design aim to **swap providers, channels, and storage** without rewriting core machines—consistent with the article’s warning that **harness assumptions go stale** as models improve ([Managed Agents](https://www.anthropic.com/engineering/managed-agents)). |

---

## Intentional differences (same direction, different product)

- **Sovereignty and economics** (Treasury, wallet-native identity, decentralized inference in Phase 6) are **first-class** here; the Anthropic article focuses on **reliability, scale, and security** of a hosted agent platform, not on **self-funding agents**.
- **Managed Agents** names concrete control-plane APIs (`emitEvent`, `wake`, `execute`, etc.). **haven-core** specifies **state machines and events** (`eExecuteTool`, `eLLMRequest`, future session events)—alignment is **architectural**, not a spec merge.
- **Lazy sandbox provisioning and TTFT** are **implementation outcomes** Anthropic reports after decoupling ([Managed Agents](https://www.anthropic.com/engineering/managed-agents)). Our docs describe **phased** delivery; similar **latency and scale** wins would follow if **inference and heavy execution** are provisioned **only when needed**, which matches the roadmap’s extension model in principle.

---

## Using this document

- **For investors or partners:** Shows that Haven’s **documented** architecture is **compatible in principle** with a **widely cited** industry framing for **long-horizon, secure, scalable agents**, while pursuing **decentralization and economic sovereignty**.
- **For implementers:** When adding **persistence**, **child agents**, or **sandboxed tools**, use the [Managed Agents](https://www.anthropic.com/engineering/managed-agents) article as a **checklist**: Is state **durable outside** the loop? Can the **harness** restart without losing the **session**? Are **secrets** outside **untrusted execution**? Can **hands** be **replaced** independently?

---

## Related internal docs

| Document | Relevance |
|----------|-----------|
| [00-layer-model.md](./00-layer-model.md) | Brain vs orchestration vs messaging vs identity; extension boundaries |
| [02-data-flow.md](./02-data-flow.md) | End-to-end flows through layers |
| [03-implementation-roadmap.md](./03-implementation-roadmap.md) | Phased persistence, autonomy, decentralized infra and inference |
| [04-sovereignty-roadmap.md](./04-sovereignty-roadmap.md) | WASM sandbox, host credential injection, on-chain trust boundary |
| [06-tee-self-attesting-lineage-plan.md](./06-tee-self-attesting-lineage-plan.md) | Attested parent–child lineage (cattle / replaceable instances) |
| [07-haven-sdk-cdk-agnostic-plan.md](./07-haven-sdk-cdk-agnostic-plan.md) | SDK as orchestration plane; kernel stays thin |

---

## Changelog

- **2026-04-11:** Initial version; maps `docs/` direction to [Anthropic Managed Agents engineering post](https://www.anthropic.com/engineering/managed-agents).
