# Extension Development Guide

## Philosophy

The sovereign agent kernel is 5 machines. Everything else is an extension. This isn't an afterthought — extensibility is the primary design constraint. The kernel exists to provide the thinnest possible surface for extensions to build on.

**If you're adding a capability to the sovereign agent, you're writing an extension.**

## Extension Types

Extensions fall into 6 categories, mapped to SALM layers:

| Extension Type | SALM Layer | Registers Via | Core Contract |
|---------------|-----------|--------------|---------------|
| **Channel** | L4 Messaging | `eRegisterChannel` | Receives `eOutboundMessage`, publishes `ePublishInbound` |
| **Provider** | L6 Reasoning | `eRegisterProvider` | Receives `eLLMRequest`, responds with `eLLMResponse` |
| **Tool** | L5 Orchestration | `eToolRegister` | Receives `eExecuteTool`, responds with `eToolResult` |
| **Storage** | L2 Persistence | `eRegisterStorage` | Receives `eStoreData`, responds with `eDataStored` |
| **Infrastructure** | L1 Infrastructure | `eRegisterInfrastructure` | Receives `eHealthCheck`, responds with `eHealthReport` |
| **Scheduler** | L5 Orchestration | Custom wiring | Injects messages via `ePublishInbound` on schedule |

## How to Build a Channel Extension

Channels are the most common extension. Here's the pattern:

### 1. Create the Machine

```p
machine MyProtocolChannel {
    var bus: machine;
    var channelName: ChannelName;

    start state Init {
        entry (payload: (bus: machine)) {
            bus = payload.bus;
            channelName = "myprotocol";

            // Register with the core message bus.
            send bus, eRegisterChannel, (name = channelName, handler = this);
        }

        // ... connection states ...
    }

    state Connected {
        // Platform delivers a message → convert to InboundMessage → publish.
        on ePlatformMessage do (raw: PlatformSpecificType) {
            var msg: InboundMessage;
            msg = (
                id = raw.id,
                channel = channelName,
                senderId = raw.sender,
                chatId = raw.room,
                content = raw.text,
                timestamp = raw.time,
                sessionKey = GenerateSessionKey(channelName, raw.room),
                metadata = default(map[string, string])
            );
            send bus, ePublishInbound, msg;
        }

        // Core sends a response → convert to platform format → send.
        on eOutboundMessage do (msg: OutboundMessage) {
            // Convert OutboundMessage → platform-specific format.
            // Call platform SDK to deliver.
            SendToPlatform(msg.chatId, msg.content);
        }
    }
}
```

### 2. Key Rules for Channels

- **Always register via `eRegisterChannel`** — the bus won't route to you otherwise.
- **Always use `InboundMessage`/`OutboundMessage`** — the bus doesn't speak your protocol.
- **Handle reconnection yourself** — the bus doesn't manage channel health.
- **Your SDK imports stay in your machine** — never leak protocol types above Layer 4.

### 3. Examples

| Channel | Platform SDK | Key Adaptation |
|---------|-------------|----------------|
| XMTP | `@xmtp/node-sdk` | Wallet-signed registration, MLS encryption |
| Solana Memo | `@solana/web3.js` | Transaction memo encode/decode, gas costs |
| Webhook | `express` or `http` | HTTP server, signature verification |
| Waku | `@waku/sdk` | P2P topic subscription |
| Matrix | `matrix-js-sdk` | Room membership, E2EE |

## How to Build a Tool Extension

Tools are the agent's hands. They're the second most common extension.

### 1. Register the Tool

```p
// In your extension's init:
var def: ToolDefinition;
def = (
    name = "web_search",
    description = "Search the web for information",
    estimatedCost = (
        amounts = default(seq[TokenAmount]),  // Free for off-chain tools
        category = TOOLS
    )
);
send toolExecutor, eToolRegister, def;
```

### 2. Handle Execution

The ToolExecutor routes `eExecuteTool` to registered handlers. In the current spec, execution is simulated. In a real implementation, your extension machine handles the actual logic:

```p
machine WebSearchTool {
    start state Ready {
        on eExecuteTool do (req: (call: ToolCall, sessionKey: SessionKey)) {
            if (req.call.name == "web_search") {
                var query: string;
                query = req.call.arguments["query"];

                // Do the actual search...
                var results: string;
                results = PerformWebSearch(query);

                var result: ToolResult;
                result = (
                    callId = req.call.id,
                    status = SUCCESS,
                    result = results
                );
                send agent, eToolResult, result;
            }
        }
    }
}
```

### 3. Cost Estimation

Tools with real costs (on-chain transactions, paid APIs) must provide accurate `estimatedCost` values. The ToolExecutor sends `eCostAuthorize` to Treasury before executing — if your cost estimate is wrong, the tool might be denied when it shouldn't be, or approved when it's too expensive.

```p
// An on-chain tool with real gas costs:
var def: ToolDefinition;
def = (
    name = "send_tokens",
    description = "Send tokens to an address",
    estimatedCost = (
        amounts = [(token = "ETH", amount = 500000000000000)],  // ~0.0005 ETH gas
        category = TOOLS
    )
);
```

### 4. Tool Categories

| Category | Cost | Examples |
|----------|------|---------|
| Off-chain, free | `amounts = []` | Memory read/write, local computation |
| Off-chain, paid | `amounts = [(token, amount)]` | Paid API calls (web search, etc.) |
| On-chain, gas | `amounts = [(native_token, gas)]` | Token transfers, contract calls |
| On-chain, gas + protocol | Multiple amounts | DEX swaps (gas + slippage), storage deals |

## How to Build a Provider Extension

Providers give the agent its reasoning capability.

### 1. The Contract

A provider receives `eLLMRequest` and responds with `eLLMResponse`. That's the entire contract.

```p
machine GonkaProvider {
    var wallet: machine;

    start state Ready {
        entry (payload: (wallet: machine)) {
            wallet = payload.wallet;
        }

        on eLLMRequest do (req: (...)) {
            // 1. Sign the request with the wallet (Gonka requires this)
            // 2. Send to Gonka network
            // 3. Parse response
            // 4. Respond

            var response: LLMResponse;
            response = (...);
            send req.requestor, eLLMResponse, (
                sessionKey = req.sessionKey,
                response = response
            );
        }
    }
}
```

### 2. Provider vs ProviderManager

- A **provider** is a single LLM source (Gonka, Anthropic, local model).
- The **ProviderManager** is an extension that wraps multiple providers with failover logic.

You can use a provider directly (wire it to AgentLoop) or use the ProviderManager extension for multi-provider setups. The AgentLoop doesn't care — it sends `eLLMRequest` and gets `eLLMResponse`.

## How to Build a Storage Extension

Storage extensions persist the agent's state across restarts and migrations.

### 1. The Contract

```
eStoreData  → extension stores data  → eDataStored
eRetrieveData → extension fetches data → eDataRetrieved
```

### 2. Backends

| Backend | Use Case | Extension Complexity |
|---------|----------|---------------------|
| Local filesystem | Development, single-instance | Simple |
| Filecoin | Durable, verifiable, cheap | Medium (deal management) |
| Arweave | Permanent, immutable | Medium (payment handling) |
| Ceramic | Mutable streams, real-time | Complex (stream management) |
| IPFS + pinning | Content-addressed, distributed | Medium |

### 3. The SessionManager Uses Storage

The SessionManager extension (Layer 5) uses storage extensions (Layer 2) for persistence. This is proper layering — SessionManager manages session semantics, the storage extension manages bytes-on-disk.

## Extension Lifecycle

### Registration

Extensions register themselves during system boot (or dynamically at runtime):

```
1. Kernel boots (5 core machines start)
2. Extensions instantiate and register:
   - Channels → eRegisterChannel to MessageBus
   - Providers → eRegisterProvider (or wired directly)
   - Tools → eToolRegister to ToolExecutor
   - Storage → eRegisterStorage
3. Kernel receives eStart → begins processing
```

### Hot-Plugging

Extensions can register and unregister at runtime:

```
// Add a new channel while running:
send bus, eRegisterChannel, (name = "matrix", handler = matrixChannel);

// Remove a channel:
send bus, eUnregisterChannel, "matrix";

// Add a tool:
send toolExecutor, eToolRegister, myNewTool;

// Remove a tool:
send toolExecutor, eToolUnregister, "old_tool";
```

This follows pi-mono's extension philosophy — the system adapts at runtime without restarts.

## Testing Extensions

### Against the Kernel

Test your extension against the real kernel with stub counterparts:

1. Boot the kernel with `ProviderStub` (from Main.p)
2. Register your extension
3. Send test events
4. Verify responses

### In Isolation

Test your extension's state machine in isolation:

1. Create the extension machine
2. Send it events directly
3. Assert state transitions and output events
4. Use P model checking for exhaustive verification

### Cost-Path Testing

For tools with costs, verify the full cost authorization path:

1. Register tool with specific `estimatedCost`
2. Set Treasury to various states (FUNDED, LOW, CRITICAL)
3. Trigger tool execution
4. Verify: authorized in FUNDED, denied in CRITICAL
