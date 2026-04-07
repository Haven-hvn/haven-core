# Implementation Plan: Hybrid LightGBM + Sentence Embedding Binary Classifier for SALM Layer 3 Signing Gate

## Overview

This document specifies the implementation of a binary classifier - `SignatureRiskClassifier` - embedded at SALM Layer 3 (Economic/Treasury) as a signing risk gate. The classifier runs during cost authorization and maps risk labels (`safe (0)`, `malicious (1)`) into the core event contract: `eCostAuthorized(approved: bool, reason: string)`.

The chosen architecture is a **hybrid LightGBM classifier** that fuses two input streams:
1. **Structured tabular features** extracted from the transaction payload (contract address, function selector, recipient, value, token type, EIP-712 fields)
2. **Dense semantic embeddings** of the `InboundMessage` text (the natural language prompt from Layer 4 that triggered the signing decision)

This approach is grounded in PTXPhish's feature engineering for payload-based phishing detection[1][2] and the established pattern of concatenating sentence transformer embeddings with tabular numeric features as input to gradient-boosted classifiers[3][4]. LightGBM is preferred over XGBoost for this context: it achieves 91.2% accuracy vs. XGBoost's 89.5% on blockchain transaction risk datasets, with inference at 10ms vs. 15ms per prediction - critical for a real-time pre-signing gate[5].

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  SALM Layer 3: Treasury — eCostAuthorize Handler                    │
│                                                                     │
│  ┌──────────────────────┐    ┌──────────────────────────────────┐  │
│  │  TransactionPayload  │    │  InboundMessage (Layer 4 text)   │  │
│  │  - contractAddress   │    │  "send ETH to treasury wallet"   │  │
│  │  - functionSelector  │    │  "approve 10000 USDC to xyz"     │  │
│  │  - recipient         │    └──────────────┬───────────────────┘  │
│  │  - value             │                   │                      │
│  │  - tokenStandard     │         SentenceTransformer              │
│  │  - spender           │         (all-MiniLM-L6-v2)              │
│  │  - deadline          │                   │                      │
│  │  - eip712Fields      │           384-dim embedding              │
│  └──────────┬───────────┘                   │                      │
│             │                               │                      │
│        FeatureExtractor                     │                      │
│        (see Section 3)                      │                      │
│             │                               │                      │
│         ~25 numeric                         │                      │
│          features                           │                      │
│             └──────────────┬────────────────┘                      │
│                            │ concat                                │
│                   ~409-dim feature vector                          │
│                            │                                       │
│                    LightGBM Classifier                             │
│                    (binary, focal loss)                            │
│                            │                                       │
│              ┌─────────────┴────────────────┐                      │
│           safe (0)                    malicious (1)                │
│        eCostAuthorized             eCostAuthorized                 │
│  (approved=true, reason=...)   (approved=false, reason="risk")    │
│        + budget check              + eSignBlocked event            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Feature Engineering

### 3.1 Structured Payload Features (~25 features)

These are extracted deterministically from signing context (payload + decoded calldata) by adapter/extension implementations (for example in `haven-adapters`) and passed into Layer 3 as normalized fields. Per SALM, signing operations remain in Layer 2 (`WalletIdentity`) and Treasury remains the Layer 3 authorization gate.

**Function Selector Features**

Derived from the 4-byte function selector of the calldata, matched against a known ABI registry[2][1]:

| Feature | Type | Description |
|---|---|---|
| `func_is_approve` | bool (0/1) | Selector matches ERC-20 `approve(address,uint256)` |
| `func_is_permit` | bool (0/1) | Selector matches EIP-2612 `permit(address,address,uint256,uint256,uint8,bytes32,bytes32)` |
| `func_is_setApprovalForAll` | bool (0/1) | Selector matches ERC-721/1155 `setApprovalForAll(address,bool)` |
| `func_is_transfer` | bool (0/1) | Selector matches `transfer` or `transferFrom` |
| `func_is_unknown` | bool (0/1) | Selector not found in ABI registry (high-risk signal) |
| `func_is_payable` | bool (0/1) | Function is ETH-payable (airdrop/wallet drain vector)[2] |

**Value and Amount Features**

PTXPhish identifies abnormal approval amounts as the primary signal for ice phishing - legitimate approvals rarely use `uint256.max` (unlimited approval)[1][6]:

| Feature | Type | Description |
|---|---|---|
| `value_is_max_uint256` | bool (0/1) | Value equals `2^256 - 1` (unlimited approval) |
| `value_eth_normalized` | float | ETH value of the transaction normalized by agent's current balance |
| `approve_amount_normalized` | float | ERC-20 approval amount / agent's token balance (>1.0 is suspicious) |
| `deadline_seconds_remaining` | float | Seconds until permit deadline (very short = urgency pressure tactic) |
| `deadline_is_max` | bool (0/1) | Permit deadline is `uint256.max` (never expires - high risk) |

**Address Features**

| Feature | Type | Description |
|---|---|---|
| `recipient_is_agent_wallet` | bool (0/1) | Recipient is the agent's own address (self-transfer, likely safe) |
| `spender_is_known_protocol` | bool (0/1) | Spender address matches registry of known DeFi protocols (Uniswap, Aave, etc.) |
| `contract_is_verified` | bool (0/1) | Contract address has verified source on-chain (0 = unverified, high-risk)[7] |
| `contract_age_days` | float | Days since contract deployment (very new = high-risk) |
| `recipient_is_contract` | bool (0/1) | Recipient is a contract address, not an EOA |
| `address_entropy_spender` | float | Shannon entropy of spender address hex (obfuscated vanity addresses have low entropy) |

**EIP-712 Domain Features**

For typed signatures, the `domainSeparator` fields provide additional context[8][9]:

| Feature | Type | Description |
|---|---|---|
| `eip712_chain_id_matches` | bool (0/1) | Domain `chainId` matches current chain (cross-chain replay risk if 0) |
| `eip712_verifying_contract_known` | bool (0/1) | `verifyingContract` address is in known-safe registry |
| `eip712_name_entropy` | float | Shannon entropy of domain `name` string (gibberish names = high-risk) |
| `is_eip712_typed` | bool (0/1) | Signature is typed structured data vs. raw `personal_sign` |

**Behavioral / Context Features**

| Feature | Type | Description |
|---|---|---|
| `treasury_state_numeric` | int | Encoded treasury state: Funded=0, Low=1, Critical=2, Depleted=3 |
| `message_triggered_signing` | bool (0/1) | Signing was triggered by an inbound message (vs. heartbeat/cron) |
| `time_since_last_sign_seconds` | float | Recency of last signing event (burst of sign requests = suspicious) |
| `inbound_message_length` | int | Character length of the original inbound prompt |

### 3.2 Semantic Embedding Features (384 features)

The `InboundMessage.content` string from Layer 4 is encoded using `sentence-transformers/all-MiniLM-L6-v2`, a 22M parameter model that runs in ~5ms CPU and produces a 384-dimensional dense vector[10][11]. This embedding captures semantic intent - urgency framing, social engineering language, impersonation patterns ("I am the Freysa developer"), prompt injection attempts, and concept substitution attacks[3].

```typescript
// Runs inside Treasury at Layer 3 - no external API call
import { pipeline } from '@xenova/transformers'; // WASM/ONNX, TEE-compatible

const embedder = await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');

async function getMessageEmbedding(text: string): Promise<number[]> {
  const output = await embedder(text, { pooling: 'mean', normalize: true });
  return Array.from(output.data); // 384 floats
}
```

The 384-dim embedding is concatenated directly with the ~25 structured features to produce the final ~409-dim input vector for LightGBM[3][4].

---

## Model Selection: LightGBM with Focal Loss

LightGBM is selected over alternatives for the following reasons[5][12]:

| Property | LightGBM | XGBoost | Random Forest | Neural Net |
|---|---|---|---|---|
| Inference latency | ~10ms | ~15ms | ~20ms | ~5-50ms |
| Training time | 80s | 120s | 150s+ | Hours |
| Class imbalance handling | Native `is_unbalance` + focal | Manual weights | Manual weights | Focal loss |
| Heterogeneous features (bool + float + dense) | Native | Native | Native | Requires normalization |
| TEE deployment (no GPU) | ✅ Pure CPU | ✅ Pure CPU | ✅ Pure CPU | ⚠️ GPU preferred |
| Adversarial robustness | Moderate[13] | Moderate | Better[13] | Poor |
| SHAP explainability | Native | Native | Partial | Complex |

The class imbalance problem is real: PTXPhish found only ~4.97% of `approve` transactions were phishing[14], so benign samples will dominate training data. LightGBM's native `is_unbalance=True` flag combined with binary focal loss addresses this without requiring manual SMOTE resampling[5][12].

SHAP (SHapley Additive exPlanations) values are enabled natively in LightGBM and used to generate a human-readable `justification` field in the `eSignBlocked` event - critical for agent observability and debugging[12][15].

---

## Training Data Strategy

### 5.1 Seed Dataset

The PTXPhish dataset (BlockSec, NDSS 2025) provides the best available seed for structured payload features, with 5,000 labeled phishing transactions and 13,557 benign transactions across 11 attack subcategories[2]. The dataset is open-source at `github.com/blocksecteam/PTXPhish`[2].

However, the PTXPhish dataset has no `InboundMessage` text column - it was captured from browser-based wallet interactions, not agent prompts. The NLP embedding branch must be bootstrapped separately:

- **Positive (malicious) prompts**: Collect all documented Freysa Act I/II prompt injection attempts (public on-chain), expand synthetically using the attack taxonomy (concept substitution, virtual environment, urgency framing, authority impersonation)
- **Negative (benign) prompts**: Heartbeat-triggered messages, legitimate treasury queries, cron-scheduled actions, normal user interactions

### 5.2 Label Schema

Each training sample has the form:

```
{
  // Structured features (25 fields)
  func_is_approve: 1,
  value_is_max_uint256: 1,
  spender_is_known_protocol: 0,
  contract_is_verified: 0,
  ...

  // NLP embedding (384 floats - stored as blob, joined at training time)
  message_embedding: Float32Array(384),

  // Label
  label: 1  // 0=safe, 1=malicious
}
```

### 5.3 Ongoing Data Collection

Once deployed, every `eSignRequest` event - whether blocked or approved - is logged (with the signing decision and any post-hoc outcome if observable) to Layer 2 persistent storage (Filecoin/Arweave). This creates a continuously growing labeled dataset for periodic retraining.

---

## SALM Integration: Event Flow

```typescript
// Layer 3: Treasury risk gate (TypeScript pseudocode)
// Note: This is an implementation-level extension around core events.
// Core spec keeps eCostAuthorize(requestId, estimate, requestor) unchanged.
// Signing context can be carried in extension metadata.

import { SignatureRiskClassifier } from './SignatureRiskClassifier';
import { FeatureExtractor } from './FeatureExtractor';

const classifier = new SignatureRiskClassifier(); // loads LightGBM WASM model
const extractor = new FeatureExtractor();

machine.on('eCostAuthorize', async (event: CostAuthorizeEvent) => {
  // 1. Existing budget check
  const budgetOk = treasury.canAfford(event.estimate);

  // 2. Extract features from extension-provided signing context
  const signingContext = event.metadata?.signingContext;
  const structuredFeatures = extractor.fromPayload(signingContext?.payload);
  const messageEmbedding = await embedder.encode(signingContext?.inboundMessage?.content ?? '');
  const featureVector = [...structuredFeatures, ...messageEmbedding]; // ~409 dims

  // 3. Run binary classifier
  const { label, confidence, shapValues } = classifier.predict(featureVector);
  const riskOk = label === 0; // 0=safe, 1=malicious

  // 4. Emit result
  if (budgetOk && riskOk) {
    machine.emit('eCostAuthorized', {
      requestId: event.requestId,
      approved: true,
      reason: 'Authorized'
    });
  } else {
    machine.emit('eCostAuthorized', {
      requestId: event.requestId,
      approved: false,
      reason: budgetOk ? 'risk' : 'budget'
    });
    if (!riskOk) {
      machine.emit('eSignBlocked', {
        requestId: event.requestId,
        confidence,
        topFeatures: shapValues.top(5),      // SHAP top-5 for observability
        inboundMessageSnippet: signingContext?.inboundMessage?.content?.slice(0, 100)
      });
    }
  }
});
```

`eSignBlocked` in this plan is proposed as an extension event (not currently in core `spec/core/Events.p`). Layer 6 (`AgentLoop`) may subscribe to it for user-facing explanations, while Layer 7 autonomy policies can consume aggregated block metrics for survival strategy adjustments.

---

## Implementation Phases

### Phase 1 - Offline Bootstrap (Week 1-2)

- Download and parse PTXPhish dataset[2]
- Build `FeatureExtractor` in TypeScript as an extension/adapter component (not core kernel): ABI decoder for known function selectors, address registry lookup (Uniswap, Aave, 1inch, known phishing address lists), EIP-712 domain parser[8]
- Generate synthetic `InboundMessage` text for PTXPhish samples (prompt templates per attack category)
- Train initial LightGBM model in Python (sklearn API), export to ONNX/WASM for Node.js deployment
- Evaluate: target precision > 0.95, recall > 0.85 on held-out 20% split (asymmetric threshold: prefer false positives over false negatives given irreversible on-chain consequences)

### Phase 2 - Integration (Week 3)

- Integrate `Xenova/all-MiniLM-L6-v2` (ONNX runtime, no external API call, TEE-compatible) as the embedding module[10][11]
- Wire `SignatureRiskClassifier` into the Treasury `eCostAuthorize` handler
- Add `eSignBlocked` as an extension event (for example in `spec/extensions/Events.p`) while keeping core event contracts stable
- Unit tests: inject known-malicious payloads (max-uint256 approve to unknown spender + urgency prompt), verify blocking; inject known-benign payloads, verify pass-through

### Phase 3 - Live Logging and Retraining (Week 4+)

- Persist every `eSignRequest` + classifier decision to Layer 2 storage (Arweave/Filecoin)
- Build retraining pipeline: weekly model refresh on accumulated data, with holdout validation before deployment
- Monitor precision/recall drift via `eSignBlocked` rate; alert if false positive rate exceeds 2% of legitimate signing volume

---

## Adversarial Robustness Considerations

Research on adversarial attacks against Ethereum phishing classifiers shows that Random Forest is more resilient than Decision Trees and KNN against Fast Gradient Sign Method (FGSM) perturbations applied to numeric features like transaction value and gas[13][16]. LightGBM's ensemble nature provides similar resistance. The key mitigations for the SALM deployment:

- **Hard rules as non-negotiable gates**: `value_is_max_uint256 = true AND spender_is_known_protocol = false` always triggers a block regardless of classifier output - these are zero-exception rules, not ML features
- **Adversarial training**: Periodically inject FGSM-perturbed samples during retraining to harden numeric feature branches[16]
- **Embedding branch as tiebreaker**: The semantic embedding of the inbound message is hard to perturb adversarially without changing the natural language meaning - providing a second independent signal that structural feature manipulation cannot easily defeat[3]
- **Confidence thresholding**: Predictions with confidence < 0.70 trigger a human-review escalation event rather than an automatic block/pass decision

---

## Output Events Reference

| Event | Layer | Trigger | Payload |
|---|---|---|---|
| `eSignBlocked` | 3 | Classifier returns `malicious` | `requestId`, `confidence`, `topFeatures` (SHAP), `snippet` |
| `eCostAuthorized(approved=false)` | 3 | Budget or risk check fails | `requestId`, `approved=false`, `reason` (`risk` or budget-related) |
| `eTreasuryStateChanged` | 3 | Runway thresholds crossed (`FUNDED/LOW/CRITICAL/DEPLETED`) | `previous`, `current` |
| `eSignRequest` | 2 | Emitted by requesting workflows after `eCostAuthorized(approved=true)` | `SigningRequest` payload |
