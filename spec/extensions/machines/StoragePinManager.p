/**
 * Extension: StoragePinManager
 * Role: REFERENCE EXTENSION — Self-sustaining IPFS pin lifecycle.
 * Layer: L2 (Identity & Persistence).
 *
 * Monitors IPFS pin status for the agent's critical CIDs (root memory CID,
 * session DAGs, conversation archives) and autonomously renews pins before
 * they expire, funded by Treasury via the STORAGE budget category.
 *
 * Triggered by HeartbeatService — on each heartbeat tick, checks pin status.
 * If a pin is expiring (within the renewal threshold), requests Treasury
 * authorization and renews.
 *
 * Design principles:
 *   - Autonomous: No human intervention needed for pin renewal.
 *   - Budget-gated: Every renewal costs money — Treasury must approve.
 *   - Survival-critical: In Treasury CRITICAL state, STORAGE is still approved
 *     (same as INFRASTRUCTURE) because losing memory = losing continuity.
 *   - Graceful degradation: If Treasury is DEPLETED, pins expire naturally.
 *     The agent can re-pin from dPID when funds are restored.
 *
 * Extension events consumed:
 *   - eHeartbeatTick (from HeartbeatService)
 *   - ePinStatus (from storage adapter)
 *   - ePinRenewed (from storage adapter)
 *   - eCostAuthorized (from Treasury)
 *   - eDPIDUpdated (from WalletIdentity — tracks root CID changes)
 *
 * Extension events emitted:
 *   - ePinCheck (to storage adapter)
 *   - ePinRenew (to storage adapter)
 *   - eCostAuthorize (to Treasury)
 *   - ePinExpiring (informational — other extensions can listen)
 *
 * States: Init → Monitoring → CheckingPins → Renewing → Monitoring
 */

machine StoragePinManager {
    var treasury: machine;
    var bus: machine;
    var middlewareName: string;

    // The root memory CID to monitor — updated when dPID is updated.
    var rootCid: CID;

    // Additional CIDs to monitor (session DAGs, batch archives).
    var trackedCids: seq[CID];

    // Renewal threshold in days — if a pin expires within this many days, renew.
    var renewalThresholdDays: int;

    // The storage provider to use for pin operations.
    var storageProvider: string;

    // Pending cost authorization request ID.
    var pendingAuthRequestId: string;
    var pendingRenewCid: CID;

    // Stats
    var totalRenewals: int;
    var totalChecks: int;

    start state Init {
        entry (payload: (treasury: machine, bus: machine, storageProvider: string,
                         renewalThresholdDays: int)) {
            treasury = payload.treasury;
            bus = payload.bus;
            storageProvider = payload.storageProvider;
            renewalThresholdDays = payload.renewalThresholdDays;
            middlewareName = "pin-manager";
            rootCid = "";
            trackedCids = default(seq[CID]);
            pendingAuthRequestId = "";
            pendingRenewCid = "";
            totalRenewals = 0;
            totalChecks = 0;

            print format("StoragePinManager: Initialized — provider={0} threshold={1}d",
                         storageProvider, renewalThresholdDays);
            goto Monitoring;
        }
    }

    // ========================================================================
    // Monitoring — Waiting for heartbeat ticks and dPID updates
    // ========================================================================
    state Monitoring {
        entry {
            print format("StoragePinManager: Monitoring — rootCid={0} tracked={1}",
                         rootCid, sizeof(trackedCids));
        }

        // HeartbeatService tick — time to check pin status.
        on eHeartbeatTick do {
            if (rootCid == "") {
                // No root CID yet — nothing to monitor.
                print "StoragePinManager: No root CID — skipping pin check";
                return;
            }

            goto CheckingPins;
        }

        // dPID was updated — track the new root CID.
        on eDPIDUpdated do (version: DPIDVersion) {
            var oldRoot: CID;
            oldRoot = rootCid;
            rootCid = version.cid;

            // If there was a previous root CID, add it to tracked CIDs
            // (we still need to keep old archives pinned).
            if (oldRoot != "" && oldRoot != rootCid) {
                trackedCids += (oldRoot);
            }

            print format("StoragePinManager: Root CID updated — {0} → {1}",
                         oldRoot, rootCid);
        }

        // Conversation stored — track the new CID for monitoring.
        on eConversationStored do (stored: (sessionKey: SessionKey, cid: CID)) {
            trackedCids += (stored.cid);
            print format("StoragePinManager: Tracking new conversation CID — {0}", stored.cid);
        }
    }

    // ========================================================================
    // CheckingPins — Query pin status for all tracked CIDs
    // ========================================================================
    state CheckingPins {
        entry {
            totalChecks = totalChecks + 1;

            // Check the root CID first (most critical).
            print format("StoragePinManager: Checking pin status — rootCid={0}", rootCid);
            send bus, ePinCheck, rootCid;
        }

        on ePinStatus do (status: PinStatus) {
            // Evaluate if this pin needs renewal.
            if (status.expiresAt == 0) {
                // Permanent pin — no renewal needed.
                print format("StoragePinManager: Pin {0} is permanent — OK", status.cid);
                goto Monitoring;
                return;
            }

            // Check if pin is expiring within threshold.
            // In real implementation: (status.expiresAt - now()) < threshold * 86400
            // In the P spec, we simulate by checking a sentinel value.
            if (status.expiresAt > 0 && status.redundancy > 0) {
                // Pin is active but may be expiring — emit alert.
                print format("StoragePinManager: Pin {0} expires at {1} — checking threshold",
                             status.cid, status.expiresAt);

                // Emit informational event for other extensions.
                send bus, ePinExpiring, (
                    cid = status.cid,
                    daysLeft = status.expiresAt  // Simplified — real impl calculates days
                );

                // Request Treasury authorization for renewal.
                pendingRenewCid = status.cid;
                pendingAuthRequestId = format("pin-renew:{0}:{1}", status.cid, totalChecks);

                var estimate: CostEstimate;
                estimate = (
                    amounts = default(seq[TokenAmount]),
                    category = STORAGE
                );

                send treasury, eCostAuthorize, (
                    requestId = pendingAuthRequestId,
                    estimate = estimate,
                    requestor = this
                );

                goto Renewing;
                return;
            }

            // Pin is healthy — return to monitoring.
            print format("StoragePinManager: Pin {0} is healthy — redundancy={1}",
                         status.cid, status.redundancy);
            goto Monitoring;
        }

        // If pin check fails or times out, return to monitoring.
        on eError do (err: string) {
            print format("StoragePinManager: Pin check error — {0}", err);
            goto Monitoring;
        }
    }

    // ========================================================================
    // Renewing — Awaiting Treasury authorization, then renew the pin
    // ========================================================================
    state Renewing {
        entry {
            print format("StoragePinManager: Awaiting Treasury authorization for pin renewal — {0}",
                         pendingRenewCid);
        }

        on eCostAuthorized do (auth: (requestId: string, approved: bool, reason: string)) {
            if (auth.requestId != pendingAuthRequestId) {
                // Not our authorization — ignore.
                return;
            }

            if (auth.approved) {
                // Treasury approved — renew the pin.
                print format("StoragePinManager: Treasury approved — renewing pin {0}",
                             pendingRenewCid);

                send bus, ePinRenew, (
                    cid = pendingRenewCid,
                    provider = storageProvider
                );

                // Wait for renewal confirmation before returning to Monitoring.
            } else {
                // Treasury denied — cannot renew. Log and return to monitoring.
                // The pin will eventually expire.
                print format("StoragePinManager: Treasury denied pin renewal — {0}: {1}",
                             pendingRenewCid, auth.reason);
                pendingRenewCid = "";
                pendingAuthRequestId = "";
                goto Monitoring;
            }
        }

        on ePinRenewed do (status: PinStatus) {
            totalRenewals = totalRenewals + 1;

            print format("StoragePinManager: Pin renewed — cid={0} provider={1} newExpiry={2} (total renewals={3})",
                         status.cid, status.provider, status.expiresAt, totalRenewals);

            // Record the expense.
            var expense: Expense;
            expense = (
                timestamp = 0,  // Real impl fills actual timestamp
                category = STORAGE,
                token = "FIL",  // Depends on provider
                amount = 0,     // Real impl gets actual cost from provider
                description = format("Pin renewal: {0}", status.cid)
            );
            send treasury, eExpenseRecord, expense;

            pendingRenewCid = "";
            pendingAuthRequestId = "";
            goto Monitoring;
        }

        // If renewal fails, return to monitoring.
        on eError do (err: string) {
            print format("StoragePinManager: Pin renewal failed — {0}", err);
            pendingRenewCid = "";
            pendingAuthRequestId = "";
            goto Monitoring;
        }
    }
}
