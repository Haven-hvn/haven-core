/**
 * Extension: ChatChannel
 * Role: REFERENCE EXTENSION — Generic channel adapter.
 *
 * Concrete implementations (XMTP, Solana memo, Waku, webhook) extend this
 * pattern. Each channel registers itself with the MessageBus via
 * eRegisterChannel and communicates solely through core events.
 *
 * This is a reference — implementors can write their own channel machines
 * from scratch as long as they follow the ePublishInbound / eOutboundMessage
 * contract.
 */

machine ChatChannel {
    var channelName: ChannelName;
    var bus: machine;
    var channelState: ChannelState;
    var config: map[string, string];

    start state Init {
        entry (payload: (name: ChannelName, bus: machine, config: map[string, string])) {
            channelName = payload.name;
            bus = payload.bus;
            config = payload.config;
            channelState = DISCONNECTED;

            // Register with the MessageBus.
            send bus, eRegisterChannel, (name = channelName, handler = this);

            print format("ChatChannel[{0}]: Initialized", channelName);
        }

        on eChannelStart do (name: ChannelName) {
            if (name == channelName) {
                goto Connecting;
            }
        }
    }

    state Connecting {
        entry {
            channelState = CONNECTING;
            print format("ChatChannel[{0}]: Connecting...", channelName);

            // Simulate successful connection.
            send this, eChannelConnected, channelName;
        }

        on eChannelConnected do (name: ChannelName) {
            channelState = CONNECTED;
            goto Connected;
        }

        on eChannelError do (err: (channel: ChannelName, error: string)) {
            channelState = ERROR;
            print format("ChatChannel[{0}]: Connection error — {1}", channelName, err.error);
            goto Disconnected;
        }
    }

    state Connected {
        entry {
            print format("ChatChannel[{0}]: Connected — ready for messages", channelName);
        }

        // Receive a message from the platform and publish to the bus.
        // In a real implementation, this would be triggered by platform-specific
        // event listeners (XMTP stream, Solana subscription, etc.).
        on eInboundMessage do (msg: InboundMessage) {
            if (msg.channel == channelName) {
                send bus, ePublishInbound, msg;
            }
        }

        // Receive an outbound message from the bus and send to the platform.
        on eOutboundMessage do (msg: OutboundMessage) {
            print format("ChatChannel[{0}]: Sending — {1}", channelName, msg.content);
            // Platform-specific send logic goes here.
        }

        on eChannelStop do (name: ChannelName) {
            if (name == channelName) {
                goto Disconnected;
            }
        }

        on eChannelError do (err: (channel: ChannelName, error: string)) {
            if (err.channel == channelName) {
                channelState = RECONNECTING;
                goto Connecting;
            }
        }
    }

    state Disconnected {
        entry {
            channelState = DISCONNECTED;
            print format("ChatChannel[{0}]: Disconnected", channelName);
        }

        on eChannelStart do (name: ChannelName) {
            if (name == channelName) {
                goto Connecting;
            }
        }
    }
}
