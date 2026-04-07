# Sovereignty Roadmap

## What haven-core already has right (keep it)

- WalletIdentity as Machine #1 - the agent **is** its wallet.
- Treasury with survival states - the agent manages its own economic existence.
- CryptoAdapter interface - chain-agnostic by design.
- MessageBus with channel adapters - communication-agnostic.
- Typed state machines with event-driven communication - formal, testable, composable.

## Phase 2 - Add IronClaw's sandbox model (the critical missing piece)

- WASM sandbox for tool execution - the agent can write and run its own tools.
- Credential injection at the host boundary - WalletIdentity signs requests without exposing the key to the sandbox.
- Leak detection on inputs and outputs - even if the LLM tries to exfiltrate, the host catches it.
- Endpoint allowlisting - sandboxed tools can only reach approved hosts.
- This is what transforms the agent from "can only use pre-built tools" to "can do whatever it wants safely."

## Phase 3 - Add Agent Kit's governance and autonomy

- Constitution (immutable rules enforced at the kernel level, not just prompt injection).
- `PROCESS.toml`-style workflow definitions - proactive, timer-driven autonomy.
- Self-billing - Treasury triggers on-chain credit purchases when funds are low.
- `SOUL.md`-style identity that the agent can evolve through reflection.

## Phase 4 - Move the trust boundary on-chain

- WalletIdentity backed by a smart contract wallet (session keys, spending limits).
- Treasury rules enforced on-chain (budget categories as smart contract logic).
- Constitution commitments on-chain (creator dividends, spending caps).
- CryptoAdapter talks to KMS/TEE/smart contract instead of holding raw keys.
