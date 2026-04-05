/**
 * Machine: ProviderStub
 * Role: Stub LLM provider for Phase 0.
 * 
 * Direct TypeScript translation of the ProviderStub from src/Main.p
 * 
 * In real deployments, this is replaced by extension-provided providers
 * (ProviderManager, Gonka, Ritual, centralized pi-ai wrapper, etc.).
 */

import { Machine, MachineRegistry } from "../machine.js";
import {
  type LLMResponse,
  type SessionKey,
  LLMResponseType,
} from "../types.js";

export class ProviderStub extends Machine {
  private responseCount = 0;

  constructor(registry: MachineRegistry, id?: string) {
    super("ProviderStub", registry, id);
    this.defineStates();
  }

  async initialize(): Promise<void> {
    await this.init("Ready");
  }

  private defineStates(): void {
    this.defineState("Ready")
      .onEntry(() => {
        this.log("Ready (stub provider — Phase 0)");
      })
      .on("eLLMRequest", (req) => {
        this.responseCount++;
        const messages = req.messages;
        const lastUserMessage = this.getLastUserMessage(messages);
        const response = this.generateResponse(lastUserMessage, req.sessionKey);

        this.sendById(req.requestor, "eLLMResponse", {
          sessionKey: req.sessionKey,
          response,
        });
      });
  }

  private getLastUserMessage(messages: Record<string, string>[]): string {
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role === "user") return messages[i].content || "";
    }
    return "";
  }

  private generateResponse(userMessage: string, sessionKey: SessionKey): LLMResponse {
    const lower = userMessage.toLowerCase();

    if (lower.includes("hello") || lower.includes("hi")) {
      return {
        responseType: LLMResponseType.CONTENT,
        content: `Hello! I'm a sovereign agent running on the Phase 0 kernel. I have a wallet identity, treasury management, and a message bus — but I'm using a stub LLM provider. My responses are simulated, but all the machinery around me (cost gating, event routing, state machines) is real.`,
        toolCalls: [], reasoning: "",
      };
    }

    if (lower.includes("who are you") || lower.includes("what are you")) {
      return {
        responseType: LLMResponseType.CONTENT,
        content: `I'm a Sovereign Agent — an autonomous, wallet-native AI entity. My identity is my wallet address. I track my own costs through a Treasury that transitions through survival states (Funded → Low → Critical → Depleted). Every action I take is cost-gated. I communicate through a MessageBus that routes messages between channels and my reasoning engine. This is Phase 0 — the kernel is running with stub providers.`,
        toolCalls: [], reasoning: "",
      };
    }

    if (lower.includes("treasury") || lower.includes("balance") || lower.includes("funds")) {
      return {
        responseType: LLMResponseType.CONTENT,
        content: `My Treasury is currently in FUNDED state with a simulated runway. In a real deployment (Phase 2+), I would track actual on-chain balances across multiple chains, enforce budget allocations (40% inference, 15% tools, 30% infrastructure, 10% messaging, 5% reserve), and transition to cost-conscious or survival mode as funds decrease.`,
        toolCalls: [], reasoning: "",
      };
    }

    if (lower.includes("wallet") || lower.includes("identity") || lower.includes("address")) {
      return {
        responseType: LLMResponseType.CONTENT,
        content: `My identity is my wallet. The WalletIdentity machine manages my private key — it never leaves that machine boundary. Other machines request signatures through events; they never access the key directly.`,
        toolCalls: [], reasoning: "",
      };
    }

    if (lower.includes("tool") || lower.includes("execute") || lower.includes("action")) {
      return {
        responseType: LLMResponseType.CONTENT,
        content: `My ToolExecutor manages a registry of pluggable tools with beforeToolCall/afterToolCall hooks. Tools register dynamically via events. Before any tool executes, the ToolExecutor requests cost authorization from Treasury. Extensions can also block tools via hooks for safety, user preferences, etc.`,
        toolCalls: [], reasoning: "",
      };
    }

    if (lower.includes("architecture") || lower.includes("how do you work") || lower.includes("design")) {
      return {
        responseType: LLMResponseType.CONTENT,
        content: `I'm built on 5 core state machines from a P language specification:\n\n1. **WalletIdentity** (L2) — My cryptographic identity\n2. **Treasury** (L3) — My economic survival engine\n3. **MessageBus** (L4) — Universal event routing\n4. **ToolExecutor** (L5) — Pluggable tool execution with cost gating\n5. **AgentLoop** (L6) — Cost-aware reasoning engine\n\nThese follow the Sovereign Agent Layer Model (SALM) — a 7-layer architecture inspired by OSI.`,
        toolCalls: [], reasoning: "",
      };
    }

    return {
      responseType: LLMResponseType.CONTENT,
      content: `[Stub Provider #${this.responseCount}] I received your message: "${userMessage}"\n\nThis is a Phase 0 stub response. In a real deployment, this would be processed by an LLM provider registered as an extension. The full pipeline is active: your message was routed through the MessageBus, cost-checked by Treasury, and processed by the AgentLoop's iteration cycle.`,
      toolCalls: [], reasoning: "",
    };
  }
}
