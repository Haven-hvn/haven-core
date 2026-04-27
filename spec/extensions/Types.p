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

// ============================================================================
// MIDDLEWARE PIPELINE TYPES
// ============================================================================

// Registered middleware entry in the InferencePipeline's ordered list.
type MiddlewareEntry = (
    name: MiddlewareName,
    handler: machine,
    priority: int            // Lower = earlier in request chain, later in response chain
);

// ============================================================================
// IPLD CONVERSATION TYPES (for PersistenceMiddleware)
// ============================================================================
// These mirror the IPLD schema from lmstudio-bridge's conversation.ipldsch
// as P records. They define the on-disk format for persisted conversations.
// Used by PersistenceMiddleware, CIDRecorderMiddleware, and memory restoration.

// A single persisted conversation (request + response pair).
// Links to previous conversation via CID, forming an append-only DAG.
type ConversationNode = (
    version: string,                       // Schema version (e.g., "1.0.0")
    request: ConversationRequest,
    response: ConversationResponse,
    metadata: ConversationMetadata,
    timestamp: int,
    previousConversationCid: CID           // "" if first in session
);

// The LLM request that was sent (captured by middleware).
type ConversationRequest = (
    model: string,
    messages: seq[map[string, string]],    // [{role, content}, ...]
    parameters: map[string, string]         // Temperature, max_tokens, etc.
);

// The LLM response that was received.
type ConversationResponse = (
    id: string,
    model: string,
    choices: seq[map[string, string]],     // [{role, content, finish_reason}, ...]
    usage: map[string, int],               // {prompt_tokens, completion_tokens, total_tokens}
    created: int
);

// Metadata about the capture — what processing was applied.
type ConversationMetadata = (
    shimVersion: string,                   // Pipeline version
    captureTimestamp: int,
    encryption: EncryptionConfig,
    compression: CompressionConfig
);

// Encryption state for a persisted conversation.
type EncryptionConfig = (
    encrypted: bool,
    algorithm: string,                     // "aes-256-gcm", "taco", "" if unencrypted
    publicKeyFingerprint: string           // Fingerprint of the encrypting key
);

// Compression state for a persisted conversation.
type CompressionConfig = (
    compressed: bool,
    algorithm: string,                     // "gzip", "" if uncompressed
    originalSize: int                      // Pre-compression size in bytes
);

// A session DAG node — aggregates conversations into a session.
// Links to previous session via CID, forming the session chain.
type SessionDAGNode = (
    sessionId: string,
    timestamp: int,
    conversations: seq[CID],              // Ordered CIDs of ConversationNodes
    statistics: SessionStatistics,
    previousSessionCid: CID               // "" if first session
);

// Aggregate session statistics.
type SessionStatistics = (
    totalRequests: int,
    totalTokens: int,
    totalSize: int,                        // Bytes
    duration: int                          // Seconds
);

// Conversation index entry — for efficient lookup without walking the full DAG.
// Maintained by CIDRecorderMiddleware.
type ConversationIndexEntry = (
    conversationCid: CID,
    timestamp: int,
    model: string,
    firstUserMessage: string,              // Truncated first user message for search
    tokenCount: int
);

// ============================================================================
// PIN / STORAGE TYPES (for StoragePinManager)
// ============================================================================

// IPFS pin status for a specific CID.
type PinStatus = (
    cid: CID,
    provider: string,                      // "pinata", "web3.storage", "local", etc.
    expiresAt: int,                        // Unix timestamp, 0 if permanent
    redundancy: int                        // Number of replicas
);

// Pin lifecycle state.
enum PinState {
    PINNED,      // Pin is active and healthy
    EXPIRING,    // Pin will expire within the renewal threshold
    EXPIRED,     // Pin has expired — data may be garbage collected
    UNPINNED     // Data was never pinned or has been explicitly unpinned
}
