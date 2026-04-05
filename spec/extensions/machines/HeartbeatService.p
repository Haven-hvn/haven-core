/**
 * Extension: HeartbeatService
 * Role: REFERENCE EXTENSION — Periodic self-activation.
 *
 * The survival heartbeat. Periodically wakes the agent to check:
 * - Treasury balance (is the agent running out of funds?)
 * - Infrastructure health (are leases expiring?)
 * - Pending tasks (anything in the heartbeat queue?)
 *
 * Design principle: The heartbeat is what makes the agent sovereign —
 * it acts without being asked. But it's still an extension. A non-sovereign
 * agent (human-operated) doesn't need self-activation.
 */

machine HeartbeatService {
    var bus: machine;
    var treasury: machine;
    var interval: int;       // Seconds between heartbeats
    var running: bool;

    start state Stopped {
        entry (payload: (bus: machine, treasury: machine, interval: int)) {
            bus = payload.bus;
            treasury = payload.treasury;
            interval = payload.interval;
            running = false;

            print format("HeartbeatService: Initialized (interval={0}s)", interval);
        }

        on eHeartbeatStart do {
            running = true;
            goto Sleeping;
        }
    }

    state Sleeping {
        entry {
            print format("HeartbeatService: Sleeping for {0}s", interval);
        }

        on eHeartbeatTick do {
            goto Checking;
        }

        on eHeartbeatStop do {
            running = false;
            goto Stopped;
        }
    }

    state Checking {
        entry {
            print "HeartbeatService: Checking treasury and health";

            // Request a treasury report.
            send treasury, eTreasuryReportRequest;
        }

        on eTreasuryReport do (report: TreasuryReport) {
            print format("HeartbeatService: Treasury state={0}, runway={1} days",
                         report.state, report.runwayDays);

            if (report.state == CRITICAL || report.state == DEPLETED) {
                // Inject a survival alert into the bus.
                var alertMsg: InboundMessage;
                alertMsg = (
                    id = "heartbeat:survival-alert",
                    channel = "heartbeat",
                    senderId = "system",
                    chatId = "heartbeat",
                    content = format("SURVIVAL ALERT: Treasury is {0} with {1} days runway. Take action.",
                                     report.state, report.runwayDays),
                    timestamp = 0,
                    sessionKey = "heartbeat:system",
                    metadata = default(map[string, string])
                );
                send bus, ePublishInbound, alertMsg;
            }

            // Request a balance refresh.
            send treasury, eBalanceCheck;

            goto Sleeping;
        }

        on eHeartbeatStop do {
            running = false;
            goto Stopped;
        }
    }
}
