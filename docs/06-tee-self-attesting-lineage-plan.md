# Implementation Plan: TEE Self-Attesting Lineage

## Goal

Establish a cryptographic parent-child trust handshake for infrastructure-launched agent instances without shared secrets. The parent trusts a child only if the child proves, via TEE attestation, that it is running the parent-approved image measurement.

Core idea:
- Parent controls image build and expected measurement (`M_expected`)
- Child generates its own key inside TEE (`pk_child`)
- TEE report binds `pk_child` to the measured image
- Parent accepts only if report signature is valid and measurement matches `M_expected`

This aligns with SALM's rule that trust anchors live in lower layers and are consumed upward through events.

---

## Mapping to SALM Layers

| SALM Layer | Responsibility in this protocol |
|---|---|
| Layer 1 (Infrastructure) | Build/deploy image, compute `M_expected`, launch TEE workload, collect attestation evidence |
| Layer 2 (Identity & Persistence) | Parent keypair lifecycle (`sk_parent`/`pk_parent`), child ephemeral key generation, attestation verification material persistence |
| Layer 3 (Economic) | Optional gating of bootstrap/renewal calls via `eCostAuthorize` before remote verification and secure channel establishment |
| Layer 4 (Messaging) | Transport for bootstrap handshake payloads (`pk_child`, report, nonce/challenge, verification result) |
| Layer 5 (Orchestration) | Retry/backoff, timeout handling, enrollment workflow state machine |
| Layer 6/7 | Consume verified child session only after lower-layer trust completes |

---

## Protocol: Self-Attesting Lineage

### Phase 1: Parent Preparation

1. Generate or load parent keypair in Layer 2:
   - `sk_parent` stays in `WalletIdentity` boundary
   - `pk_parent` is exportable for embed/distribution
2. Embed `pk_parent` into child image build artifacts.
3. Compute and persist image measurement:
   - `M_expected`
   - image metadata (tag, digest, build timestamp, build pipeline identity)
4. Launch child container in TEE-capable infrastructure and track expected measurement for that launch.

### Phase 2: Child TEE Bootstrap

1. Child boots and reads embedded `pk_parent`.
2. Child generates ephemeral keypair in TEE:
   - `(sk_child, pk_child)`
   - never exported outside enclave boundary
3. Child requests TEE attestation report with report data containing at least:
   - `pk_child`
   - parent challenge/nonce (or launch-bound nonce)
   - optional instance id
4. TEE returns signed report containing:
   - `measurement`
   - report data hash/value (binding `pk_child` and challenge)
   - signature chain to platform trust root

### Phase 3: Parent Verification and Channel Establishment

1. Child sends bootstrap payload to parent endpoint:
   - `pk_child`
   - attestation report (+ cert chain/collateral)
   - challenge response data
2. Parent verifies:
   - report signature chain anchors to trusted root
   - report freshness (nonce/challenge, timestamp validity)
   - `measurement == M_expected`
   - report data binds to received `pk_child`
3. On success:
   - mark child as trusted lineage instance
   - establish secure channel (session key encrypted to `pk_child` or ECDH)
4. On failure:
   - reject enrollment
   - emit security telemetry for policy and operator review

---

## haven-core Event-Level Integration Plan

This protocol should be extension-first, preserving the 5-machine core.

### Proposed extension events

- `eChildBootstrapRequest`
  - Child -> parent bootstrap payload arrival
- `eChildAttestationVerify`
  - Request verification against trust policy and `M_expected`
- `eChildAttestationVerified`
  - Verification result (`approved`, `reason`, `instanceId`, `measurement`)
- `eChildSessionEstablished`
  - Secure channel established and usable
- `eChildSessionRejected`
  - Rejected due to signature, measurement, freshness, or policy mismatch

These belong in extension event definitions and should route through `MessageBus` in Layer 4.

### Machine ownership

- `InfrastructureManager` extension (Layer 1)
  - launch, measurement tracking, attestation collection hooks
- `WalletIdentity` core + adapter extension (Layer 2)
  - parent key management, child ephemeral key creation APIs, verification helpers
- `MessageBus` core (Layer 4)
  - handshake event routing
- `HeartbeatService`/orchestrator extensions (Layer 5)
  - retries, periodic re-attestation, stale session invalidation

---

## Data Contracts (initial draft)

`ChildBootstrapPayload`:
- `childPublicKey: string`
- `attestationReport: bytes/base64`
- `attestationCollateral: object`
- `challenge: string`
- `instanceId?: string`
- `timestamp: string`

`AttestationVerificationResult`:
- `approved: boolean`
- `reason: "ok" | "bad_signature" | "measurement_mismatch" | "stale" | "binding_mismatch" | "policy_denied"`
- `measurement: string`
- `expectedMeasurement: string`
- `childPublicKeyHash: string`
- `sessionExpiresAt?: string`

---

## Security Requirements

Minimum controls:

1. **No shared bootstrap secret** between parent/child.
2. **Replay resistance** using parent-issued challenge + freshness window.
3. **Measurement pinning** (`M_expected`) per launch policy.
4. **Key binding**: parent must verify report data binds exactly to `pk_child`.
5. **Root-of-trust validation** for TEE evidence chain.
6. **Auditability**: all verification outcomes are persisted with reason code.
7. **Fail-closed behavior**: no verified attestation, no trusted child session.

---

## Implementation Phases

### Phase 0: Design and Threat Model

- Define trust assumptions and threat model (replay, spoofed child, stale collateral, forked image).
- Choose TEE target(s) and attestation format abstraction.
- Define verification policy contract independent from provider specifics.

Exit criteria:
- approved threat model doc
- agreed verification policy schema

### Phase 1: Parent Build and Measurement Pipeline

- Inject `pk_parent` in image build flow.
- Capture `M_expected` deterministically in build metadata.
- Store launch record mapping `{deploymentId -> M_expected, imageDigest}`.

Exit criteria:
- deterministic measurement capture demonstrated in CI
- parent can look up expected measurement for any live deployment

### Phase 2: Child Keygen + Attestation Binding

- Implement in-enclave child ephemeral key generation.
- Bind `pk_child` + challenge in attestation report data.
- Emit bootstrap payload over existing message transport path.

Exit criteria:
- reproducible report containing correct bound data
- negative test: tampered `pk_child` fails parent verification

### Phase 3: Parent Verification Service

- Validate report signature/cert chain.
- Verify freshness window and challenge echo.
- Verify measurement equality and `pk_child` binding.
- Return explicit typed reason codes.

Exit criteria:
- success path establishes session key
- all major failure modes return correct reason

### Phase 4: Session Lifecycle + Re-attestation

- Add session TTL and scheduled re-attestation via orchestration layer.
- Invalidate channel on expiry or verification drift.
- Add policy for measurement rotation during deploy rollouts.

Exit criteria:
- expired sessions automatically rejected
- planned image rollout supports both old/new pinned measurements during transition window

### Phase 5: Observability and Hardening

- Emit metrics: verification success rate, rejection reasons, freshness failures.
- Add structured security logs for incident response.
- Add chaos/security tests (replay, stale report, wrong measurement, chain failure).

Exit criteria:
- dashboard + alerts for attestation failures
- documented runbook for key/measurement rotation

---

## Test Plan

1. **Happy path**
   - valid report, correct measurement, correct key binding -> trusted session created
2. **Measurement mismatch**
   - valid signature, wrong measurement -> rejected
3. **Replay attempt**
   - old challenge/timestamp -> rejected as stale
4. **Binding mismatch**
   - report binds different key than transmitted key -> rejected
5. **Signature chain failure**
   - invalid or untrusted collateral -> rejected
6. **Rotation scenario**
   - deployment rolls to new image and new `M_expected` without breaking active healthy children

---

## Open Decisions

1. Which attestation provider(s) are first-class in v1?
2. Where verification runs: dedicated extension service or embedded in infrastructure extension?
3. Session key agreement scheme: encrypt-to-`pk_child` vs ECDH handshake.
4. Measurement rotation policy: strict pin vs rollout window.
5. Persistence location for attestation audit logs (local vs decentralized backend extension).

---

## Suggested Next Steps in This Repo

1. Add extension event/type definitions for bootstrap and attestation result.
2. Add a reference `AttestationVerifier` extension interface.
3. Add a new data-flow scenario documenting "Child Enrollment via TEE Attestation".
4. Add safety/liveness properties for "No trusted child without valid attestation" and "Enrollment eventually resolves accepted/rejected".
