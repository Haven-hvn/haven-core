# Implementation Plan: haven-sdk (CDK-like, Web3-Provider Agnostic)

## Goal

Create `haven-sdk` under `haven-hvn` as a CDK-like control plane for confidential-agent infrastructure that is not coupled to any single Web3 stack.

The SDK should provide:
- provider-agnostic abstractions for deployment, identity, attestation, policy, and lifecycle
- pluggable adapters for specific environments (EigenCloud first, others later)
- typed contracts that can be consumed by `haven-core`, `haven-adapters`, and external apps

This document is the prerequisite plan referenced by:
- `06-tee-self-attesting-lineage-plan.md`

---

## Why This Exists

`haven-core` should remain a minimal sovereign-agent kernel, not an infrastructure orchestrator.

`haven-sdk` becomes the infra orchestration layer that:
- launches and manages TEE workloads
- normalizes attestation evidence across providers
- exposes stable contracts for enrollment, verification, and session lifecycle
- keeps provider-specific SDK usage out of core protocol docs and machine contracts

---

## Scope (v1)

v1 is a CDK-like foundation, not just an attestation helper:

1. **Project and environment model**
   - project manifests
   - environment-specific configs (dev/stage/prod)
2. **Deployment API**
   - define workloads, image policies, rollout windows
   - launch/update/terminate operations
3. **TEE identity and attestation API**
   - unified evidence envelope and verification contract
   - adapter interface for provider implementations
4. **Policy engine**
   - measurement pinning policy
   - freshness and replay policy
   - trust-root policy
5. **Lifecycle and observability**
   - status, health, re-attestation scheduling hooks
   - structured events/metrics surface

Out of scope for v1:
- decentralized governance and token economics
- full marketplace routing across providers

---

## Core Design Principles

1. **Provider-neutral contracts first**
   - public interfaces must not encode EigenCloud-specific field names
2. **Adapters at the edge**
   - provider SDKs are wrapped in dedicated adapter packages/modules
3. **Typed, versioned payloads**
   - request/response contracts include protocol and schema versioning
4. **Fail-closed security defaults**
   - invalid or unverifiable attestation never yields trusted sessions
5. **Composable with haven-core**
   - `haven-core` consumes SDK contracts/events without infra lock-in

---

## Proposed Package Layout

```text
haven-sdk/
  packages/
    core/                 # provider-agnostic contracts + policy engine
    deploy/               # CDK-like deployment orchestration APIs
    attest/               # attestation abstractions + verifiers
    runtime/              # lifecycle/session orchestration primitives
    adapters-eigencloud/  # EigenCloud implementation (first-class in v1)
    adapters-phala/       # future slot (not required for v1 release)
```

---

## Key Interfaces (Draft)

```ts
export interface TeeProviderAdapter {
  readonly providerId: string;
  getCapabilities(): ProviderCapabilities;

  requestEvidence(input: EvidenceRequest): Promise<EvidenceEnvelope>;
  verifyEvidence(input: VerifyEvidenceRequest): Promise<VerifyEvidenceResult>;

  deployWorkload?(input: DeployWorkloadRequest): Promise<DeployWorkloadResult>;
  getWorkloadStatus?(input: WorkloadStatusRequest): Promise<WorkloadStatusResult>;
}
```

```ts
export interface MeasurementPolicy {
  acceptedMeasurements: Array<{
    measurement: string;
    validFrom: string;
    validUntil: string;
    imageDigest?: string;
    deploymentId?: string;
  }>;
  freshnessWindowMs: number;
  replayNonceRequired: boolean;
}
```

---

## EigenCloud v1 Strategy

Use npm package:
- [@layr-labs/ecloud-sdk](https://www.npmjs.com/package/@layr-labs/ecloud-sdk)

Adapter responsibilities:
- wrap attest flow (`AttestClient`, `JwtProvider`) behind `TeeProviderAdapter`
- normalize JWT claims into provider-agnostic `EvidenceEnvelope`
- expose provider metadata in a namespaced map to avoid schema leakage

Non-goal:
- exposing raw EigenCloud claim schema as primary public interface

---

## Integration Contract with haven-core

`haven-core` should depend on `haven-sdk` contracts, not on provider SDKs.

Expected integration:
- `haven-core` extension machines consume `EvidenceEnvelope` and `VerifyEvidenceResult`
- enrollment/session state machines remain in `haven-core` extension space
- deployment and provider lifecycle remain in `haven-sdk`

---

## Implementation Phases

### Phase 0: Repository and contract baseline
- scaffold `haven-hvn/haven-sdk`
- publish initial `packages/core` and `packages/attest` contract packages
- define schema/version policy

Exit criteria:
- typed interfaces published
- provider-neutral attestation envelope approved

### Phase 1: EigenCloud adapter
- implement `adapters-eigencloud` using `@layr-labs/ecloud-sdk` from npm
- map evidence and verification outputs into SDK contracts
- include replay/freshness checks and reason codes

Exit criteria:
- can request + verify evidence through unified adapter interface
- contract tests pass against mocked provider responses

### Phase 2: Deployment orchestration (CDK-like core)
- add `packages/deploy` resource model
- support workload definitions, rollout policy, and status polling
- connect deployment records to measurement policy artifacts

Exit criteria:
- deterministic deployment manifest -> deployment record flow
- measurement policy generated per deployment

### Phase 3: Runtime lifecycle
- add re-attestation scheduling interfaces in `packages/runtime`
- implement session TTL integration hooks for consuming runtimes
- emit structured lifecycle events

Exit criteria:
- lifecycle hooks can drive trusted/untrusted session transitions

### Phase 4: Hardening and docs
- add threat model and security assumptions per provider
- add end-to-end examples with `haven-core`
- finalize operational runbooks

Exit criteria:
- documented production checklist
- examples demonstrate provider-agnostic usage with EigenCloud adapter

---

## Test Plan Requirements

1. Provider contract conformance tests for each adapter
2. Evidence verification negative-path tests (stale, mismatch, invalid signature)
3. Rollout policy tests for overlapping measurements
4. Backward compatibility tests for schema version bumps

---

## Decisions Locked for v1

1. `haven-sdk` is mandatory prerequisite for TEE lineage rollout.
2. EigenCloud is first adapter implementation, but not a hard-coded public contract.
3. Provider-specific details live in adapter modules only.
4. `haven-core` remains extension-first and infra-agnostic.

