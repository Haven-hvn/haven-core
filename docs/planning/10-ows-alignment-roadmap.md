# OWS Alignment Roadmap for haven-core

## Goal

Define a phased roadmap to align the Haven architecture (`haven-core` + extension ecosystem) with the Open Wallet Standard (OWS) specification surface, without breaking the core SALM design principle that the kernel remains minimal and extension-first.

This roadmap treats OWS as a wallet/signing/policy standard at Layer 2, while preserving Haven's broader agent-kernel scope across Layers 1-7.

---

## Why This Roadmap Exists

Current planning correctly captures a sovereign-agent kernel, but OWS introduces concrete requirements that go beyond a drop-in signing library swap:

1. Vault storage formats and permission requirements.
2. Credential-tiered access model (owner vs API token).
3. Pre-decrypt policy evaluation model.
4. Wallet lifecycle operations (create/import/export/recover/backup/rotate).
5. Chain identifier canonicalization (CAIP) and multi-chain account semantics.
6. Key isolation and memory hardening expectations.

Replacing `viem` in one adapter addresses only part of OWS `02-signing-interface`. It does not complete OWS alignment.

---

## Architecture Positioning

### Haven Layer Responsibility

- `haven-core` remains the kernel contract and machine orchestration layer.
- OWS-aligned wallet behavior belongs primarily in Layer 2 extensions (identity/persistence boundary), not directly in core reasoning or messaging machines.
- `haven-adapters` (or a dedicated wallet module) can host concrete OWS-compatible implementations wired into kernel interfaces.

### Non-goal

- Do not collapse Haven into a wallet product. OWS alignment should strengthen Layer 2 and agent access boundaries, not replace SALM.

---

## OWS Coverage Baseline (Current)

1. `01-storage-format`: Missing in Haven spec and implementation.
2. `02-signing-interface`: Partial (`CryptoAdapter` abstraction present; operation set incomplete).
3. `03-policy-engine`: Missing at wallet-signing boundary.
4. `04-agent-access-layer`: Partial (extension architecture exists; OWS credential semantics not formalized).
5. `05-key-isolation`: Partial (boundary isolation intent exists; hardening semantics not fully specified).
6. `06-wallet-lifecycle`: Missing.
7. `07-supported-chains`: Partial (chain-agnostic design exists; CAIP canonicalization and lifecycle semantics incomplete).

---

## Roadmap Phases

### Phase 0: Contract and terminology alignment

Objective:

- Normalize Haven Layer 2 wallet contracts around OWS concepts without forcing immediate backend migration.

Work:

- Define OWS-facing types in extension space:
  - `WalletId`, `ApiKeyId`, `PolicyId`
  - CAIP `ChainId` / `AccountId`
  - normalized signing request/response envelopes
- Add explicit operation taxonomy:
  - `sign`
  - `signAndSend` (optional extension)
  - `signMessage`
  - `signTypedData`
  - `signHash`
  - `signAuthorization` (EIP-7702)
- Define error-code mapping strategy (OWS canonical errors to Haven event-level errors).

Exit criteria:

- Type contracts approved and referenced by extension docs.
- No `any` in new wallet contract types.

### Phase 1: OWS-aligned signing adapter path

Objective:

- Provide an OWS-backed signing path that can replace current `viem` signing implementation for Ethereum-compatible flows.

Work:

- Implement OWS-backed `CryptoAdapter` extension.
- Preserve existing kernel host wiring (`setCryptoAdapter(...)`).
- Add compatibility strategy for dual backends during migration window.

Exit criteria:

- Message and tx signing pass parity tests against current behavior.
- Integration path documented for host apps.

### Phase 2: Policy-gated agent signing model

Objective:

- Introduce OWS-style policy enforcement before decryption for agent-scoped credentials.

Work:

- Model owner vs token credential tiers at the access boundary.
- Add policy attachment and evaluation contract (AND semantics, fail-closed behavior).
- Support declarative rules first; executable policy bridge second.
- Ensure policy-denied flows never trigger signing/decrypt events.

Exit criteria:

- Tests prove deny-before-decrypt behavior.
- Policy evaluation traces are observable and auditable.

### Phase 3: Vault storage and audit semantics

Objective:

- Add OWS-compatible vault structure and file-permission guardrails in extension space.

Work:

- Define storage layout and schema contracts for wallet/key/policy artifacts.
- Enforce startup checks for insecure permissions.
- Add append-only audit log contract for signing and lifecycle operations.
- Define backward-compatible import/export behavior where applicable.

Exit criteria:

- Permission checks fail closed when vault permissions are unsafe.
- Audit records emitted for required operation categories.

### Phase 4: Wallet lifecycle completeness

Objective:

- Support lifecycle operations aligned with OWS expectations.

Work:

- Create/import/export/delete wallet flows.
- Backup/restore flow contracts.
- Recovery flow contracts (mnemonic/keystore-based).
- Key rotation flow for asset migration.
- Wallet discovery/filtering contracts for multi-tool coexistence.

Exit criteria:

- Lifecycle operations documented and integration-tested end-to-end.

### Phase 5: Chain canonicalization and multi-chain conformance

Objective:

- Make CAIP-first identifiers and supported-chain behavior explicit and testable.

Work:

- Require canonical CAIP chain/account IDs in persisted and policy contexts.
- Resolve aliases only at interface edges.
- Document per-chain derivation and signing behavior expectations for adapters.
- Add conformance suite for supported-chain ID normalization.

Exit criteria:

- Internal persisted artifacts use canonical CAIP IDs only.
- Alias handling is edge-only and deterministic.

### Phase 6: Key isolation hardening profile

Objective:

- Define and implement practical hardening profile consistent with OWS guidance.

Work:

- Zeroization semantics for sensitive buffers.
- Optional short-lived key cache with strict TTL and bounded size.
- Signal-based cleanup requirements.
- Document future subprocess-isolation profile for high-security mode.

Exit criteria:

- Hardening profile documented as normative for Haven OWS mode.
- Tests cover zeroization/cleanup control-flow guarantees where feasible.

---

## Deliverables

1. Updated Layer 2 extension contracts in Haven docs/spec.
2. OWS-backed signing adapter implementation.
3. Policy engine extension contract and reference implementation.
4. Vault/audit extension contract and reference implementation.
5. Lifecycle command/API contract docs.
6. Conformance test suite (operation, policy, storage, chain-ID canonicalization).

---

## Test Strategy Requirements

1. 100% unit test coverage for newly introduced OWS-alignment modules.
2. No untyped objects in new wallet/policy contract code.
3. Negative-path tests for all fail-closed behaviors:
  - policy deny
  - invalid chain ID
  - unsupported operation
  - missing wallet/key artifacts
  - insecure vault permissions
4. Backward compatibility tests for host integrations using existing kernel wiring.

---

## Open Decisions

1. Should OWS-aligned wallet lifecycle live in `haven-adapters` or a dedicated new package?
2. Should `signAndSend` live in wallet adapters or remain a higher-layer tool concern?
3. What minimum chain set is required for first-class Haven OWS mode?
4. What hardening profile is mandatory vs optional in local-dev environments?

---

## Definition of Done

- Haven has a documented, test-backed OWS alignment path across storage, signing, policy, lifecycle, chain identifiers, and key isolation.
- Core kernel boundaries stay intact (no chain/provider SDK leakage into core machines).
- Host apps can opt into OWS mode with minimal wiring changes.