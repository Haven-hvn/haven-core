/**
 * Extension: ProviderManager
 * Role: REFERENCE EXTENSION — LLM provider management with failover.
 *
 * Manages multiple LLM providers (decentralized and centralized) with
 * priority-based selection and automatic failover. Communicates with the
 * core via eLLMRequest/eLLMResponse events.
 *
 * Design principle: The core AgentLoop doesn't know about provider
 * management. It sends eLLMRequest to whatever machine is wired as its
 * provider. This extension can sit in that position and add failover,
 * market-based routing, and cost optimization on top.
 */

machine ProviderManager {
    var providers: seq[ProviderEntry];
    var currentIndex: int;
    var treasury: machine;

    start state Init {
        entry (payload: (treasury: machine)) {
            treasury = payload.treasury;
            providers = default(seq[ProviderEntry]);
            currentIndex = 0;

            print "ProviderManager: Initialized — no providers (register via eRegisterProvider)";
            goto Active;
        }
    }

    state Active {
        entry {
            print format("ProviderManager: Active with {0} providers", sizeof(providers));
        }

        on eRegisterProvider do (reg: (name: string, handler: machine)) {
            var entry: ProviderEntry;
            entry = (
                name = reg.name,
                handler = reg.handler,
                priority = sizeof(providers),
                isDecentralized = false
            );
            providers += (entry);
            print format("ProviderManager: Provider registered — {0}", reg.name);
        }

        on eLLMRequest do (req: (sessionKey: SessionKey, messages: seq[map[string, string]],
                                  tools: seq[map[string, string]], requestor: machine,
                                  estimatedCost: CostEstimate)) {
            if (sizeof(providers) == 0) {
                // No providers available.
                var errorResp: LLMResponse;
                errorResp = (
                    responseType = ERROR,
                    content = "No LLM providers available",
                    toolCalls = default(seq[ToolCall]),
                    reasoning = ""
                );
                send req.requestor, eLLMResponse, (
                    sessionKey = req.sessionKey,
                    response = errorResp
                );
                return;
            }

            // Route to current provider.
            if (currentIndex < sizeof(providers)) {
                send providers[currentIndex].handler, eLLMRequest, req;
            }
        }

        on eLLMProviderError do (err: (provider: string, error: string)) {
            print format("ProviderManager: Provider error — {0}: {1}", err.provider, err.error);

            // Failover to next provider.
            if (currentIndex + 1 < sizeof(providers)) {
                var fromName: string;
                fromName = providers[currentIndex].name;
                currentIndex = currentIndex + 1;
                send this, eProviderFailover, (
                    fromProvider = fromName,
                    toProvider = providers[currentIndex].name
                );
                print format("ProviderManager: Failover to {0}", providers[currentIndex].name);
            } else {
                print "ProviderManager: All providers exhausted — degraded mode";
                goto Degraded;
            }
        }

        on eProviderRecovered do (name: ProviderName) {
            // Reset to highest-priority provider.
            currentIndex = 0;
            print format("ProviderManager: Provider recovered — {0}, resetting to primary", name);
        }
    }

    state Degraded {
        entry {
            print "ProviderManager: DEGRADED — no healthy providers";
        }

        on eLLMRequest do (req: (sessionKey: SessionKey, messages: seq[map[string, string]],
                                  tools: seq[map[string, string]], requestor: machine,
                                  estimatedCost: CostEstimate)) {
            var errorResp: LLMResponse;
            errorResp = (
                responseType = ERROR,
                content = "All LLM providers are currently unavailable",
                toolCalls = default(seq[ToolCall]),
                reasoning = ""
            );
            send req.requestor, eLLMResponse, (
                sessionKey = req.sessionKey,
                response = errorResp
            );
        }

        on eProviderRecovered do (name: ProviderName) {
            currentIndex = 0;
            print format("ProviderManager: Provider recovered — {0}, exiting degraded", name);
            goto Active;
        }

        on eRegisterProvider do (reg: (name: string, handler: machine)) {
            var entry: ProviderEntry;
            entry = (
                name = reg.name,
                handler = reg.handler,
                priority = sizeof(providers),
                isDecentralized = false
            );
            providers += (entry);
            currentIndex = sizeof(providers) - 1;
            print format("ProviderManager: New provider in degraded — {0}, recovering", reg.name);
            goto Active;
        }
    }
}
