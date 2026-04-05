/**
 * Machine: MessageBus
 * Role: CORE — The universal event routing layer.
 *
 * Decouples all producers from all consumers. Channels publish inbound
 * messages; the agent loop consumes them. The agent loop publishes outbound
 * messages; channels consume them. Extensions register themselves via
 * eRegisterChannel.
 *
 * Design principle: The bus knows about message shapes (InboundMessage,
 * OutboundMessage) but nothing about specific channels or protocols.
 * XMTP, Solana, webhooks — all are just registered channel handlers.
 * The bus doesn't even queue aggressively — it routes immediately.
 * Buffering strategies are an extension concern.
 */

machine MessageBus {
    // Registered channel handlers, keyed by channel name.
    var channels: map[ChannelName, machine];

    // The agent loop — receives all inbound messages.
    var agent: machine;

    // Running flag.
    var running: bool;

    start state Init {
        entry (payload: (agent: machine)) {
            agent = payload.agent;
            channels = default(map[ChannelName, machine]);
            running = false;
            print "MessageBus: Initialized";
        }

        on eStart do {
            running = true;
            goto Running;
        }
    }

    state Running {
        entry {
            print format("MessageBus: Running with {0} channels", sizeof(channels));
        }

        // --- Channel registration (extension plug-in point) ---

        on eRegisterChannel do (reg: (name: ChannelName, handler: machine)) {
            channels[reg.name] = reg.handler;
            print format("MessageBus: Channel registered — {0}", reg.name);
        }

        on eUnregisterChannel do (name: ChannelName) {
            if (name in channels) {
                channels -= (name);
                print format("MessageBus: Channel unregistered — {0}", name);
            }
        }

        // --- Inbound routing (channels → agent) ---

        on ePublishInbound do (msg: InboundMessage) {
            print format("MessageBus: Routing inbound from {0}", msg.channel);
            send agent, eInboundMessage, msg;
        }

        // --- Outbound routing (agent → channels) ---

        on ePublishOutbound do (msg: OutboundMessage) {
            if (msg.channel in channels) {
                send channels[msg.channel], eOutboundMessage, msg;
                print format("MessageBus: Routed outbound to {0}", msg.channel);
            } else {
                print format("MessageBus: No handler for channel {0} — message dropped", msg.channel);
            }
        }

        // --- Lifecycle ---

        on eStop do {
            running = false;
            print "MessageBus: Stopping";
            raise halt;
        }
    }
}
