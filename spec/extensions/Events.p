/**
 * Extension event declarations.
 *
 * Events used by reference extension machines. These are NOT core events —
 * they exist to support the reference implementations. The core kernel
 * does not depend on any of these.
 */

// ============================================================================
// CHANNEL EVENTS
// ============================================================================

event eChannelStart: ChannelName;
event eChannelStop: ChannelName;
event eChannelConnected: ChannelName;
event eChannelDisconnected: ChannelName;
event eChannelError: (channel: ChannelName, error: string);
event eChannelReconnect: ChannelName;

// ============================================================================
// PROVIDER MANAGER EVENTS
// ============================================================================

event eProviderFailover: (fromProvider: ProviderName, toProvider: ProviderName);
event eProviderError: (provider: ProviderName, error: string);
event eProviderRecovered: ProviderName;

// ============================================================================
// SESSION EVENTS
// ============================================================================

event eSessionLoad: SessionKey;
event eSessionSave: Session;
event eSessionLoaded: Session;
event eSessionSaved: SessionKey;
event eSessionClear: SessionKey;
event eConsolidationComplete: SessionKey;

// ============================================================================
// CRON EVENTS
// ============================================================================

event eCronStart;
event eCronStop;
event eCronJobAdd: CronJob;
event eCronJobRemove: JobId;
event eCronTrigger: CronJob;
event eCronJobComplete: (jobId: JobId, success: bool);
event eTimerFired;

// ============================================================================
// HEARTBEAT EVENTS
// ============================================================================

event eHeartbeatStart;
event eHeartbeatStop;
event eHeartbeatTick;
event eHeartbeatDecision: (action: string, tasks: string);
event eHeartbeatExecute: string;
event eHeartbeatComplete: string;

// ============================================================================
// SUBAGENT EVENTS
// ============================================================================

event eSubagentSpawn: SubagentTask;
event eSubagentStarted: TaskId;
event eSubagentComplete: (taskId: TaskId, result: string, status: SubagentStatus);
event eSubagentCancelled: TaskId;
event eSubagentAnnounce: (taskId: TaskId, message: string);

// ============================================================================
// INFRASTRUCTURE EVENTS
// ============================================================================

event eHealthCheck;
event eHealthReport: (provider: string, health: InfraHealth);
event eLeaseExpiring: (lease: Lease, daysLeft: int);
event eLeaseRenew: Lease;
event eLeaseRenewed: Lease;
event eLeaseMigrate: (fromProvider: string, toProvider: string);
event eLeaseMigrationComplete;

// ============================================================================
// STORAGE EVENTS (extension-level)
// ============================================================================

event eStoreData: (key: StorageKey, data: string, provider: string);
event eDataStored: StorageRecord;
event eRetrieveData: (key: StorageKey, provider: string);
event eDataRetrieved: (key: StorageKey, data: string);
event eStorageError: (key: StorageKey, error: string);

// ============================================================================
// PERSISTENCE MIDDLEWARE EVENTS
// ============================================================================
// Events emitted by PersistenceMiddleware during the conversation capture
// and IPFS upload lifecycle. These are extension-level — core does not
// depend on them. Other extensions (e.g., CIDRecorderMiddleware) consume them.

// Persistence middleware formatted a conversation node from pipeline context.
event eConversationCaptured: (sessionKey: SessionKey, node: ConversationNode);

// Conversation node was uploaded to IPFS and assigned a CID.
event eConversationStored: (sessionKey: SessionKey, cid: CID);

// Session DAG was updated with a new conversation link.
event eSessionDAGUpdated: SessionDAGNode;

// ============================================================================
// STORAGE PIN EVENTS
// ============================================================================
// Events for the StoragePinManager — monitors IPFS pin status and
// autonomously renews pins before they expire, funded by Treasury.

// Request pin status for a specific CID.
event ePinCheck: CID;

// Pin status response.
event ePinStatus: PinStatus;

// Request pin renewal (when expiring).
event ePinRenew: (cid: CID, provider: string);

// Pin renewed confirmation.
event ePinRenewed: PinStatus;

// Alert from HeartbeatService — a pin is expiring soon.
event ePinExpiring: (cid: CID, daysLeft: int);

// ============================================================================
// ADAPTER DISCOVERY EVENTS
// ============================================================================
// Events for querying on-chain adapter registries via dPID.
// Used by ToolExecutor or extension managers to discover capabilities.

// Query the adapter registry for a specific capability.
event eAdapterRegistryQuery: (capability: string);

// Registry query result — the adapter's dPID, CID, and reputation score.
event eAdapterRegistryResult: (capability: string, dpid: DPID, cid: CID, reputation: int);
