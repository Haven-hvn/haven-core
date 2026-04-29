# Plan: Compose Haven with DeepAgentsJS Worker Harness

## Goal

Adopt `deepagentsjs` as a delegated worker harness for research/coding tasks while preserving Haven's sovereignty model:

- Haven remains the system of record for identity, economics, policy, and orchestration.
- DeepAgents runs as a bounded worker runtime for scoped tasks.
- Integration is swappable so harness choice never becomes a core lock-in.

---

## Why This Plan

This approach aligns with Haven's architecture direction:

- Harnesses should be replaceable.
- Session, harness, and sandbox should be decoupled.
- Sovereign controls (wallet boundary, treasury gates, policy) must stay outside untrusted execution.

Open SWE-style composition is useful here, but only at the worker layer, not as a replacement for Haven core machines.

---

## Scope

### In scope (v1)

1. Add a Haven extension that runs DeepAgents as a delegated worker.
2. Gate worker invocation and tools through Treasury + policy.
3. Return structured artifacts/events back into Haven.
4. Add deterministic auditability (task id, spend, tool trace, artifact digest).

### Out of scope (v1)

1. Replacing `AgentLoop` with DeepAgents for all reasoning.
2. Exposing wallet signing/private key material to worker runtime.
3. Full on-chain worker marketplace dispatch.

---

## Architecture Position

### Boundary model

- **Haven core owns:**
  - `WalletIdentity` (Layer 2)
  - `Treasury` (Layer 3)
  - `MessageBus` routing and outward publication (Layer 4)
  - `ToolExecutor` authority for approved actions (Layer 5)
- **DeepAgents worker owns:**
  - task decomposition/planning
  - context management for delegated task
  - subagent fanout internal to the worker sandbox
- **Haven policy proxy sits between them:**
  - allowlisted tools only
  - cost checks for expensive operations
  - timeout and output-size limits
  - egress constraints

### Core rule

DeepAgents may propose and prepare; Haven decides and executes sovereign actions.

---

## Proposed Components

1. **`DeepAgentWorkerManager` (new extension machine)**
   - accepts worker task requests from orchestration layer
   - creates run record and lifecycle state
   - handles timeout, cancellation, and retries

2. **`DeepAgentWorkerAdapter` (new TypeScript adapter/service)**
   - wraps `createDeepAgent(...)` API
   - injects constrained tools and system prompt contract
   - normalizes outputs into Haven artifact schema

3. **`WorkerPolicyProxy` (new extension middleware/service)**
   - enforces tool allowlist and arg schema
   - optionally routes tool actions via `ToolExecutor`
   - rejects calls that bypass budget/policy

4. **`WorkerArtifactStore` (new extension service)**
   - stores output artifacts (report, patch, metadata)
   - hashes and records provenance for replay/audit

---

## Data Flow (v1)

1. Haven receives a task requiring deep research/coding analysis.
2. Haven requests `eCostAuthorize` for worker budget.
3. On approval, `DeepAgentWorkerManager` starts worker run.
4. Worker executes with constrained tools via `WorkerPolicyProxy`.
5. Worker emits structured artifacts + completion status.
6. Haven validates artifacts, records spend, and decides next action.
7. If sovereign action is needed (sign/pay/publish), Haven executes through core boundaries.

---

## Implementation Phases

### Phase 0: Contracts and guardrails

- Define worker task contract:
  - task type (`research`, `code-analysis`, `draft-patch`, etc.)
  - budget ceiling
  - tool profile
  - output schema
- Define worker result contract:
  - status, summary, artifact list, trace metadata, spend estimate
- Add policy defaults: max duration, max tool calls, max artifact size.

Exit criteria:
- interfaces/types compile
- schema validation and negative-path tests pass

### Phase 1: DeepAgents adapter MVP

- Implement `DeepAgentWorkerAdapter` using DeepAgents JS library API.
- Build minimal curated toolset for research tasks first.
- Add deterministic run metadata (run id, start/end, model, tool profile).

Exit criteria:
- can run a scoped research task end-to-end locally
- no privileged tools exposed

### Phase 2: Haven orchestration wiring

- Add `DeepAgentWorkerManager` machine and events.
- Wire invocation from orchestration layer.
- Add treasury pre-authorization and run-state transitions.

Exit criteria:
- unauthorized budgets cannot start worker runs
- cancellations/timeouts cleanly terminate runs

### Phase 3: Policy proxy + artifact pipeline

- Route worker tool calls through `WorkerPolicyProxy`.
- Store artifacts in `WorkerArtifactStore` with digests.
- Add post-run validator for artifact schema and policy compliance.

Exit criteria:
- disallowed tool call attempts are blocked + audited
- artifacts are reproducible and traceable

### Phase 4: CLI fallback backend (optional)

- Add execution backend interface:
  - `deepagents-library` (default)
  - `deepagents-cli` (fallback/operator mode)
- Keep identical policy and result contracts across both backends.

Exit criteria:
- backend swap does not alter Haven semantics

---

## Security and Sovereignty Requirements

1. Worker runtime never receives raw private keys or signing authority.
2. Any costly operation must remain subject to Haven treasury gate.
3. Tool access is deny-by-default; explicit allowlist per task profile.
4. Worker outputs are treated as untrusted until schema + policy validation.
5. Side effects with external systems require Haven-mediated execution path.

---

## Testing Strategy

1. Unit tests for adapter mapping, policy proxy, and manager state transitions.
2. Negative tests:
   - blocked tool
   - over-budget task
   - malformed artifact
   - timeout/cancellation
3. Integration tests:
   - research task success path
   - artifact handoff to Haven decision layer
4. Contract tests to ensure backend parity (library vs CLI, if enabled).

Target: 100% coverage for new/changed files in this plan's implementation scope.

---

## Risks and Mitigations

1. **Risk:** DeepAgents built-ins exceed desired authority.
   - **Mitigation:** strict tool curation + proxy enforcement + sandbox constraints.

2. **Risk:** Architecture drift toward worker-managed sovereignty logic.
   - **Mitigation:** codify hard boundaries in contracts and review checklist.

3. **Risk:** Operational complexity from async worker lifecycle.
   - **Mitigation:** explicit run state machine + idempotent retries + standardized telemetry.

4. **Risk:** Cost variance from long worker sessions.
   - **Mitigation:** budget ceilings, intermediate checkpoints, auto-stop thresholds.

---

## Open Decisions

1. Should worker spend be pre-authorized only, or also micro-authorized per tool class?
2. Should first release support only `research` tasks, or include `draft-patch`?
3. Should artifact persistence be local-only first, or immediately storage-adapter backed?
4. Do we require human approval before any external publication action?

---

## Success Criteria

1. Haven can delegate bounded research tasks to DeepAgents end-to-end.
2. No sovereignty boundary regressions (wallet/economics/policy remain Haven-owned).
3. Worker backend remains swappable without kernel contract changes.
4. Audit trail can reconstruct who started a run, what tools were used, and what artifacts were produced.
