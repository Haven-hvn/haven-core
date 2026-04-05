/**
 * Extension type definitions.
 *
 * Types used by reference extension machines. These are NOT part of the
 * core kernel — they exist to support the reference implementations of
 * channels, providers, sessions, scheduling, and infrastructure management.
 *
 * Implementors can ignore these entirely and define their own types,
 * as long as they communicate with the core via core events.
 */

// ============================================================================
// TYPE ALIASES
// ============================================================================

type ProviderName = string;
type JobId        = string;
type TaskId       = string;
type StorageKey   = string;

// ============================================================================
// ENUMS
// ============================================================================

// Channel connection state.
enum ChannelState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    RECONNECTING,
    ERROR
}

// Session lifecycle.
enum SessionStatus {
    ACTIVE,
    CONSOLIDATING,
    ARCHIVED
}

// Subagent task lifecycle.
enum SubagentStatus {
    PENDING,
    RUNNING,
    COMPLETED,
    FAILED
}

// Infrastructure lease state.
enum LeaseState {
    ACTIVE,
    RENEWAL_PENDING,
    MIGRATING,
    EXPIRED
}

// Infrastructure health.
enum InfraHealth {
    HEALTHY,
    DEGRADED,
    CRITICAL,
    OFFLINE
}

// Storage operation type.
enum StorageOp {
    STORE,
    RETRIEVE,
    PIN,
    DELETE
}

// ============================================================================
// RECORDS
// ============================================================================

// Conversation session (for SessionManager extension).
type Session = (
    key: SessionKey,
    messages: seq[map[string, string]],
    lastConsolidated: int,
    status: SessionStatus
);

// Scheduled cron job (for CronService extension).
type CronJob = (
    id: JobId,
    name: string,
    enabled: bool,
    schedule: string,   // Cron expression or @hourly/@daily/@weekly
    message: string,
    nextRunAt: int,
    lastRunAt: int
);

// Background subagent task (for SubagentManager extension).
type SubagentTask = (
    id: TaskId,
    label: string,
    task: string,
    originChannel: ChannelName,
    originChatId: string,
    status: SubagentStatus
);

// Infrastructure lease record (for InfrastructureManager extension).
type Lease = (
    id: string,
    provider: string,       // "akash", "phala", "flux"
    state: LeaseState,
    expiresAt: int,
    costPerDay: TokenAmount,
    chain: ChainId
);

// Storage record (for decentralized storage extensions).
type StorageRecord = (
    key: StorageKey,
    provider: string,       // "filecoin", "arweave", "local"
    contentHash: string,    // CID or transaction ID
    size: int,
    storedAt: int
);

// Provider entry for the ProviderManager.
type ProviderEntry = (
    name: ProviderName,
    handler: machine,
    priority: int,          // Lower = higher priority
    isDecentralized: bool
);
