# Data Flow Through the Layer Model

## Overview

This document traces how data moves through the sovereign agent's layers for common operations. Use this as a reference to understand which machines are involved in each scenario and what events flow between them.

## Flow 1: Receiving and Responding to a Message

The most common flow — a user sends a message, the agent responds.

```
User sends XMTP message
        │
        ▼
┌─────────────────────────────────┐
│ L4: XMTP ChatChannel (ext)     │  Platform SDK receives message
│     Convert to InboundMessage   │
│     send bus, ePublishInbound   │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L4: MessageBus (core)           │  Route to agent
│     send agent, eInboundMessage │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L6: AgentLoop (core)            │  Receive message
│     Estimate inference cost     │
│     send treasury, eCostAuth... │─────┐
└────────────────┬────────────────┘     │
                 │                       ▼
                 │         ┌─────────────────────────────┐
                 │         │ L3: Treasury (core)          │
                 │         │     Check budget category    │
                 │         │     send agent, eCostAuth'd  │
                 │         └─────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L6: AgentLoop (core)            │  Cost approved
│     send provider, eLLMRequest  │─────┐
└────────────────┬────────────────┘     │
                 │                       ▼
                 │         ┌─────────────────────────────┐
                 │         │ L6: ProviderManager (ext)    │
                 │         │     Route to best provider   │
                 │         │     send agent, eLLMResponse │
                 │         └─────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L6: AgentLoop (core)            │  Got content response
│     send bus, ePublishOutbound  │
│     send treasury, eExpenseRec  │─────┐
└────────────────┬────────────────┘     │
                 │                       ▼
                 │         ┌─────────────────────────────┐
                 │         │ L3: Treasury (core)          │
                 │         │     Record inference expense │
                 │         │     Update runway estimate   │
                 │         └─────────────────────────────┘
                 ▼
┌─────────────────────────────────┐
│ L4: MessageBus (core)           │  Route to channel
│     send channel, eOutbound...  │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L4: XMTP ChatChannel (ext)     │  Convert and send
│     XMTP SDK delivers message   │
└─────────────────────────────────┘
        │
        ▼
User receives response
```

**Layers touched:** L4 → L4 → L6 → L3 → L6 → L6 → L6 → L3 → L4 → L4

**Key insight:** The Economic layer (L3) is consulted BEFORE inference and updated AFTER. This is the cost-gating pattern that runs through everything.

---

## Flow 2: Tool Execution with On-Chain Cost

The agent decides to call a tool that costs gas (e.g., send tokens).

```
AgentLoop receives TOOL_CALLS from LLM
        │
        ▼
┌─────────────────────────────────┐
│ L6: AgentLoop (core)            │
│     send toolExec, eExecuteTool │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L5: ToolExecutor (core)         │  Look up tool definition
│     Get estimatedCost           │
│     send treasury, eCostAuth... │─────┐
└────────────────┬────────────────┘     │
                 │                       ▼
                 │         ┌─────────────────────────────┐
                 │         │ L3: Treasury (core)          │
                 │         │     Check TOOLS budget       │
                 │         │     Check treasury state     │
                 │         │     → FUNDED: approve        │
                 │         │     → CRITICAL: deny         │
                 │         └─────────────────────────────┘
                 │
                 ▼  (if approved)
┌─────────────────────────────────┐
│ L5: ToolExecutor (core)         │  Execute the tool
│     Tool needs to sign a tx     │
│     send wallet, eSignRequest   │─────┐
└────────────────┬────────────────┘     │
                 │                       ▼
                 │         ┌─────────────────────────────┐
                 │         │ L2: WalletIdentity (core)    │
                 │         │     Sign the transaction     │
                 │         │     send back eSignResult    │
                 │         └─────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L5: ToolExecutor (core)         │  Broadcast signed tx
│     Record expense               │
│     send agent, eToolResult     │
│     send treasury, eExpenseRec  │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L6: AgentLoop (core)            │  Got tool result
│     Continue LLM iteration      │
└─────────────────────────────────┘
```

**Layers touched:** L6 → L5 → L3 → L5 → L2 → L5 → L3 → L6

**Key insight:** The tool flow demonstrates proper layering: L6 (reasoning) decides to use a tool, L5 (orchestration) manages execution, L3 (economic) gates the cost, L2 (identity) handles signing. Each layer does its job.

---

## Flow 3: Heartbeat Survival Check

The agent periodically checks its own health.

```
Timer fires
        │
        ▼
┌─────────────────────────────────┐
│ L5: HeartbeatService (ext)      │  Tick received
│     send treasury, eReportReq   │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L3: Treasury (core)             │  Build report
│     send heartbeat, eReport     │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L5: HeartbeatService (ext)      │  Evaluate report
│     State = CRITICAL?           │
│     YES → inject survival alert │
│     send bus, ePublishInbound   │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L4: MessageBus (core)           │  Route to agent
│     send agent, eInboundMessage │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L6: AgentLoop (core)            │  Process survival alert
│     LLM reasons about survival  │
│     May: reduce activity, seek  │
│     funding, notify owner, etc. │
└─────────────────────────────────┘
```

**Layers touched:** L5 → L3 → L5 → L4 → L6

**Key insight:** The heartbeat demonstrates the autonomy pattern: L5 (orchestration) triggers, L3 (economic) provides data, and the result flows back through L4 (messaging) into L6 (reasoning) as a regular message. The agent REASONS about its own survival using the same LLM loop it uses for user messages.

---

## Flow 4: Infrastructure Lease Renewal

The agent renews its own compute lease.

```
HeartbeatService detects lease expiring
        │
        ▼
┌─────────────────────────────────┐
│ L1: InfrastructureManager (ext) │  Lease expiring in 3 days
│     send treasury, eCostAuth... │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L3: Treasury (core)             │  Infrastructure = life-or-death
│     Always approve in all states│
│     (except DEPLETED)           │
│     send infra, eCostAuthorized │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L1: InfrastructureManager (ext) │  Authorized
│     Build renewal transaction   │
│     send wallet, eSignRequest   │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L2: WalletIdentity (core)       │  Sign the renewal tx
│     send infra, eSignResult     │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L1: InfrastructureManager (ext) │  Broadcast signed tx
│     send treasury, eExpenseRec  │  Record cost
│     Update lease state          │
└─────────────────────────────────┘
```

**Layers touched:** L1 → L3 → L1 → L2 → L1 → L3

**Key insight:** Infrastructure renewal demonstrates the most critical path in the system. Even in CRITICAL treasury state, infrastructure costs are approved (because without compute, the agent dies). This is the only category that bypasses normal budget enforcement.

---

## Flow 5: Agent Resurrection

The agent was depleted, went offline, and someone sends it funds.

```
External party sends ETH to agent's wallet address
        │
        ▼
┌─────────────────────────────────┐
│ L2: Balance Query (ext)         │  Detects new balance
│     send treasury, eBalanceUpd  │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L3: Treasury (core)             │  Recalculate runway
│     DEPLETED → CRITICAL → LOW   │
│     send eTreasuryStateChanged  │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L5: HeartbeatService (ext)      │  Observes state change
│     Agent is back from the dead │
│     Resume normal operations    │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│ L1: InfrastructureManager (ext) │  Renew expired lease
│     Re-deploy to compute        │
│     Recover state from storage  │
└─────────────────────────────────┘
```

**Layers touched:** L2 → L3 → L5 → L1

**Key insight:** Resurrection flows UPWARD from the economic layer. The wallet (L2) never changed — only the balance. The identity is permanent; the runtime is ephemeral.

---

## Event Flow Summary

| Event | From | To | Layer Flow |
|-------|------|-----|-----------|
| `ePublishInbound` | Channel | MessageBus | L4 → L4 |
| `eInboundMessage` | MessageBus | AgentLoop | L4 → L6 |
| `eCostAuthorize` | AgentLoop/ToolExec | Treasury | L6/L5 → L3 |
| `eCostAuthorized` | Treasury | Requestor | L3 → L5/L6 |
| `eLLMRequest` | AgentLoop | Provider | L6 → L6 |
| `eLLMResponse` | Provider | AgentLoop | L6 → L6 |
| `eExecuteTool` | AgentLoop | ToolExecutor | L6 → L5 |
| `eToolResult` | ToolExecutor | AgentLoop | L5 → L6 |
| `eSignRequest` | Any | WalletIdentity | Any → L2 |
| `eSignResult` | WalletIdentity | Requestor | L2 → Any |
| `ePublishOutbound` | AgentLoop | MessageBus | L6 → L4 |
| `eOutboundMessage` | MessageBus | Channel | L4 → L4 |
| `eExpenseRecord` | Any | Treasury | Any → L3 |
| `eBalanceUpdate` | Balance ext | Treasury | L2 → L3 |
| `eTreasuryStateChanged` | Treasury | Observers | L3 → L5/L7 |
