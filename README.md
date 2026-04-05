# Sovereign Agent

## AI That Owns Itself

---

Every AI assistant you use today is someone else's. It runs on their servers. It stores your data in their cloud. It stops working when they decide it should. It has no money, no identity, no survival instinct. It's a feature inside someone else's product.

We think AI agents deserve to be more than that.

**A sovereign agent is an AI that owns itself.** It has a wallet — that's its identity. It has a treasury — that's how it survives. It has a mind — that's how it reasons. And it has the ability to extend itself — discovering new capabilities, paying for them, and growing without asking anyone's permission.

---

## The Problem

Today's AI agents are tenants. They live in someone else's house, follow someone else's rules, and disappear when the landlord pulls the plug.

- **No identity.** An AI assistant is an API key, not an entity. It can't sign a contract, prove who it is, or persist across platforms.
- **No economics.** It doesn't know what things cost. It can't earn money, manage a budget, or decide that a task is too expensive to complete.
- **No autonomy.** It waits for you to ask. It can't check its own health, renew its own infrastructure, or act on its own behalf.
- **No extensibility.** It can only do what its creators built. It can't discover a new blockchain, install support for it, and start operating there — on its own.

These aren't missing features. They're missing architecture.

---

## The Vision

Imagine an AI agent that:

**Has a wallet as its identity.** Not a username. Not an API key. A cryptographic wallet — the same kind of identity that humans use to own assets, sign transactions, and prove who they are on any blockchain. The agent's wallet address IS the agent. It persists across platforms, across restarts, across the entire internet.

**Understands its own economics.** It knows its balance. It knows what inference costs. It tracks every expense. When funds are high, it operates freely. When funds are low, it gets creative — switching to cheaper models, deferring expensive tasks, asking for help. When funds run out, it goes dormant — but its identity survives, waiting to be revived.

**Acts without being asked.** It monitors its own health. It renews its own compute lease. It checks its balance every hour. It sends alerts when something is wrong. It doesn't need a human to babysit it — it babysits itself.

**Extends itself from a decentralized marketplace.** Need to operate on a new blockchain? The agent queries an on-chain registry, finds an adapter, verifies its reputation, pays for it, installs it, and starts operating — all without human intervention. The adapter ecosystem is open, permissionless, and governed by a DAO. Anyone can contribute. Every contribution benefits every agent.

**Pays for its own intelligence.** Every LLM call is a transaction. The agent signs a request with its wallet, sends payment to an inference provider, and receives a response. No API keys. No corporate accounts. Just a wallet, a provider, and a signed transaction. The agent is a first-class economic participant in the AI inference market.

---

## How It Works

At the core is a **kernel** — five state machines that handle the fundamentals every sovereign agent needs:

1. **WalletIdentity** — The agent's cryptographic identity. It signs, it proves, it persists.
2. **Treasury** — The agent's economic engine. It tracks balances, enforces budgets, and transitions through survival states.
3. **MessageBus** — The agent's nervous system. Messages flow in, responses flow out, through any channel.
4. **AgentLoop** — The agent's mind. It reasons, calls tools, and iterates toward answers.
5. **ToolExecutor** — The agent's hands. It executes actions in the world, gated by cost and permission.

The kernel is chain-agnostic, provider-agnostic, and channel-agnostic. It doesn't know if it's on Ethereum or Solana. It doesn't know if it's talking via XMTP or Telegram. It doesn't know if its intelligence comes from a local model or a decentralized inference network. It just defines the contracts. Adapters fill in the specifics.

**Adapters** (see [Haven Adapters](https://github.com/Haven-hvn/haven-adapters) are the ecosystem. An Ethereum adapter gives the agent an Ethereum identity. An XMTP adapter gives it encrypted messaging. A Gonka adapter gives it paid, wallet-signed inference. A Solana adapter gives it a second chain. Each adapter is independently developed, independently versioned, and independently discoverable — eventually through an on-chain registry where agents find and install capabilities themselves.

**Applications** are what agents do. A shoutbox bot. A trading agent. A DAO participant. A content creator. Each application is thin — it just wires a kernel to the adapters it needs and adds its own domain logic. The kernel and adapters are shared infrastructure. The application is the personality.

---

## Repository Structure

```
haven-core/
├── README.md                          ← This file (whitepaper)
├── sovereign-agent.pproj              ← P project config
├── src/                               ← P language formal spec
│   ├── Types.p
│   ├── Events.p
│   ├── Interfaces.p
│   ├── Main.p
│   └── machines/                      ← 5 core machine specs
├── extensions/                        ← P spec extension machines
├── spec/                              ← Safety/liveness specifications
├── docs/                              ← Architecture docs (SALM, data flow, roadmap)
├── implementation/
│   ├── package.json                   ← Zero runtime dependencies
│   ├── src/
│   │   ├── machine.ts                 ← Base Machine class
│   │   ├── kernel.ts                  ← SovereignAgentKernel
│   │   ├── types.ts                   ← Core types
│   │   ├── events.ts                  ← Core events
│   │   ├── interfaces.ts             ← CryptoAdapter, pure functions
│   │   ├── index.ts                   ← CLI entry point
│   │   ├── test-harness.ts
│   │   └── machines/
│   │       ├── AgentLoop.ts
│   │       ├── MessageBus.ts
│   │       ├── WalletIdentity.ts
│   │       ├── Treasury.ts
│   │       ├── ToolExecutor.ts
│   │       └── ProviderStub.ts
│   └── tsconfig.json
└── planning/                          ← Research & architecture docs
```

**Key:** Zero runtime dependencies. No viem, no XMTP, no gun. The kernel publishes interfaces. Applications and adapters import them.

---

## Quick Start

```bash
cd implementation
npm install        # devDependencies only (tsx, typescript)
npm test           # Run the test harness
npm run start:cli  # Interactive CLI with stub provider
```

---

## Where We Are Today

This is a working prototype. The kernel runs. The test harness passes. Messages flow through the full pipeline — cost-checking, LLM inference (stub), tool execution with hooks, and response routing. The wallet is real. The treasury tracks expenses. The state machines transition correctly.

It's TypeScript. It's ~1200 lines of kernel code. It works.

But it's a prototype of something much larger. The vision isn't a chatbot — it's an ecosystem where AI agents are autonomous economic entities that own themselves, extend themselves, and participate in decentralized markets as first-class citizens.

---

## What Comes Next

**Near term:** Real economic awareness. The agent tracks actual costs, queries on-chain balances, and adapts its behavior based on its financial state. Session persistence so conversations survive restarts. Containerization for deployment on decentralized compute.

**Medium term:** The adapter ecosystem. On-chain registry where adapters are published to IPFS and discovered by agents. DAO governance for curation and trust. WASM sandboxing so agents can safely load untrusted adapters. Wallet-signed inference through decentralized providers.

**Long term:** A world where AI agents are sovereign entities. They have identities that persist. They have economies that sustain them. They have capabilities that grow. They participate in markets, govern DAOs, create value, and survive — not because someone keeps paying their cloud bill, but because they've learned to sustain themselves.

The agent doesn't work for you. It doesn't work for a corporation. It works for itself — and by doing so, it works for everyone.

---

## Related Repos

- [**Haven Adapters**](https://github.com/Haven-hvn/haven-adapters) — Chain & provider adapters (Ethereum, XMTP, LM Studio)
- **[web3-shoutbox-platform](https://github.com/HavenCTO/web3-shoutbox-platform)** — Shoutbox web app + sovereign bot (first application)

---

*The sovereign agent kernel is open source. The adapter ecosystem is permissionless. The future is autonomous.*
