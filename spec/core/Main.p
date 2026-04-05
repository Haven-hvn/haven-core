/**
 * Entry point for the Sovereign Agent system.
 *
 * Creates and wires the 5 core kernel machines. Extensions are registered
 * after kernel boot via events (eRegisterChannel, eRegisterProvider, etc.).
 *
 * Design principle: Main only knows about core machines. It does NOT
 * instantiate extensions — those are plugged in by the host environment.
 * A minimal deployment needs only these 5 machines plus at least one
 * channel extension and one provider extension to be useful.
 */

machine SovereignAgentKernel {
    var wallet: machine;
    var treasury: machine;
    var bus: machine;
    var toolExecutor: machine;
    var agent: machine;

    // Extension-provided machines (set after boot via registration events).
    var provider: machine;

    start state Boot {
        entry {
            print "=== Sovereign Agent Kernel — Boot Sequence ===";

            // 1. WalletIdentity — must exist before anything else.
            //    The wallet IS the agent's identity.
            wallet = new WalletIdentity();

            // 2. Treasury — economic survival depends on this.
            treasury = new Treasury();

            // 3. ToolExecutor — needs treasury for cost gating.
            toolExecutor = new ToolExecutor(
                treasury = treasury,
                agent = this  // Placeholder — agent loop not created yet
            );

            // 4. Create a stub provider reference.
            //    Real providers register via eRegisterProvider after boot.
            //    For model checking, we use a ProviderStub.
            provider = new ProviderStub();

            // 5. AgentLoop — the reasoning engine, wired to everything.
            agent = new AgentLoop(
                bus = this,       // Placeholder — bus not created yet
                provider = provider,
                toolExecutor = toolExecutor,
                treasury = treasury,
                wallet = wallet
            );

            // 6. MessageBus — routes messages between channels and agent.
            bus = new MessageBus(agent = agent);

            // Re-wire: ToolExecutor needs a reference to the real agent.
            // (In P, we work around this with event-based communication.)

            print "=== Kernel Ready — 5 core machines online ===";
            print "  WalletIdentity: Locked (awaiting eUnlockWallet)";
            print "  Treasury:       Initialized (awaiting eBalanceUpdate)";
            print "  ToolExecutor:   Ready (no tools — extensions provide them)";
            print "  AgentLoop:      Idle (awaiting messages)";
            print "  MessageBus:     Initialized (no channels — extensions provide them)";
            print "";
            print "To make this agent useful, extensions must:";
            print "  1. Send eUnlockWallet to WalletIdentity";
            print "  2. Send eBalanceUpdate to Treasury";
            print "  3. Send eRegisterChannel to MessageBus (at least one)";
            print "  4. Send eRegisterProvider (at least one LLM provider)";
            print "  5. Send eToolRegister to ToolExecutor (at least one tool)";
            print "  6. Send eStart to MessageBus and AgentLoop";

            goto Running;
        }
    }

    state Running {
        entry {
            print "=== Sovereign Agent Kernel — Running ===";

            // Start core machines.
            send bus, eStart;
            send agent, eStart;

            // Unlock wallet (in real deployment, key source comes from environment).
            send wallet, eUnlockWallet, "env:SOVEREIGN_AGENT_PRIVATE_KEY";
        }

        on eStop do {
            print "=== Sovereign Agent Kernel — Shutdown ===";
            send agent, eStop;
            send bus, eStop;
            send wallet, eLockWallet;
            goto Shutdown;
        }

        on eError do (err: string) {
            print format("Kernel error: {0}", err);
        }

        // Forward extension registration events to the bus.
        on eRegisterChannel do (reg: (name: ChannelName, handler: machine)) {
            send bus, eRegisterChannel, reg;
        }
    }

    state Shutdown {
        entry {
            print "=== Sovereign Agent Kernel — Shutdown Complete ===";
            raise halt;
        }
    }
}

/**
 * Stub LLM provider for model checking.
 * In real deployments, this is replaced by extension-provided providers
 * (ProviderManager, Gonka, Ritual, centralized pi-ai wrapper, etc.).
 */
machine ProviderStub {
    start state Ready {
        on eLLMRequest do (req: (sessionKey: SessionKey, messages: seq[map[string, string]],
                                 tools: seq[map[string, string]], requestor: machine,
                                 estimatedCost: CostEstimate)) {
            // Simulate a content response.
            var response: LLMResponse;
            response = (
                responseType = CONTENT,
                content = "This is a stub response for model checking.",
                toolCalls = default(seq[ToolCall]),
                reasoning = ""
            );
            send req.requestor, eLLMResponse, (
                sessionKey = req.sessionKey,
                response = response
            );
        }
    }
}

/**
 * Test harness — creates the kernel for model checking.
 */
machine Main {
    start state Init {
        entry {
            new SovereignAgentKernel();
        }
    }
}
