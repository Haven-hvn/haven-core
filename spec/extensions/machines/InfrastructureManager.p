/**
 * Extension: InfrastructureManager
 * Role: REFERENCE EXTENSION — Compute lease and infrastructure management.
 *
 * Manages the agent's physical existence — compute leases on decentralized
 * providers (Akash, Phala, Flux). Monitors lease expiry, triggers renewals
 * via the wallet, and handles migration between providers.
 *
 * Design principle: Infrastructure management is the most "sovereign" of
 * the extensions. Without it, the agent is just a bot on someone's machine.
 * With it, the agent manages its own compute lifecycle. But it's still an
 * extension — during development, you run locally without any of this.
 */

machine InfrastructureManager {
    var leases: seq[Lease];
    var wallet: machine;
    var treasury: machine;
    var health: InfraHealth;

    start state Init {
        entry (payload: (wallet: machine, treasury: machine)) {
            wallet = payload.wallet;
            treasury = payload.treasury;
            leases = default(seq[Lease]);
            health = HEALTHY;

            print "InfrastructureManager: Initialized";
            goto Healthy;
        }
    }

    state Healthy {
        entry {
            health = HEALTHY;
            print "InfrastructureManager: All systems healthy";
        }

        on eHealthCheck do {
            // Check all leases for expiry.
            var i: int;
            i = 0;
            while (i < sizeof(leases)) {
                if (leases[i].state == RENEWAL_PENDING) {
                    send this, eLeaseExpiring, (
                        lease = leases[i],
                        daysLeft = 3  // Simplified
                    );
                }
                i = i + 1;
            }
            send this, eHealthReport, (provider = "all", health = health);
        }

        on eLeaseExpiring do (info: (lease: Lease, daysLeft: int)) {
            print format("InfrastructureManager: Lease {0} expiring in {1} days",
                         info.lease.id, info.daysLeft);

            // Request cost authorization for renewal.
            var estimate: CostEstimate;
            estimate = (
                amounts = default(seq[TokenAmount]),
                category = INFRASTRUCTURE
            );
            estimate.amounts += (info.lease.costPerDay);

            send treasury, eCostAuthorize, (
                requestId = format("lease-renew:{0}", info.lease.id),
                estimate = estimate,
                requestor = this
            );
            goto RenewalPending;
        }

        on eLeaseMigrate do (migration: (fromProvider: string, toProvider: string)) {
            print format("InfrastructureManager: Migration requested — {0} → {1}",
                         migration.fromProvider, migration.toProvider);
            goto Migrating;
        }
    }

    state RenewalPending {
        entry {
            print "InfrastructureManager: Lease renewal pending — awaiting authorization";
        }

        on eCostAuthorized do (auth: (requestId: string, approved: bool, reason: string)) {
            if (auth.approved) {
                // Sign the renewal transaction.
                var signReq: SigningRequest;
                signReq = (
                    id = auth.requestId,
                    signingType = TRANSACTION,
                    payload = "lease-renewal-tx-data",
                    chain = "akash",
                    requestor = this
                );
                send wallet, eSignRequest, signReq;
            } else {
                print format("InfrastructureManager: Renewal denied — {0}", auth.reason);
                health = DEGRADED;
                goto Healthy;  // Return but in degraded state
            }
        }

        on eSignResult do (result: SigningResult) {
            if (result.success) {
                print "InfrastructureManager: Lease renewed successfully";
                // Record expense.
                var expense: Expense;
                expense = (
                    timestamp = 0,
                    category = INFRASTRUCTURE,
                    token = "AKT",
                    amount = 75000000,  // Simplified
                    description = "Compute lease renewal"
                );
                send treasury, eExpenseRecord, expense;
            } else {
                print format("InfrastructureManager: Renewal signing failed — {0}", result.error);
                health = DEGRADED;
            }
            goto Healthy;
        }

        on eHealthCheck do {
            send this, eHealthReport, (provider = "all", health = DEGRADED);
        }
    }

    state Migrating {
        entry {
            health = DEGRADED;
            print "InfrastructureManager: Migrating — saving state...";
            // In reality: save all state to decentralized storage,
            // deploy to new provider, verify, switch.
        }

        on eLeaseMigrationComplete do {
            print "InfrastructureManager: Migration complete";
            health = HEALTHY;
            goto Healthy;
        }

        on eHealthCheck do {
            send this, eHealthReport, (provider = "migration", health = DEGRADED);
        }
    }
}
