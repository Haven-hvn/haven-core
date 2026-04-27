/**
 * Shared interface definitions for the Sovereign Agent kernel.
 * 
 * Direct TypeScript translation of src/Interfaces.p
 * 
 * Pure functions used across core machines. No side effects, no I/O.
 */

import {
  type TokenAmount,
  type TokenSymbol,
  type ChannelName,
  type SessionKey,
  type Address,
  type Signature,
  type DPID,
  type BudgetAllocation,
  BudgetCategory,
  TreasuryState,
} from "./types.js";

// ============================================================================
// CRYPTO ADAPTER — Chain-agnostic signing interface
// ============================================================================

/**
 * Pluggable cryptographic adapter for WalletIdentity.
 * 
 * The kernel defines this interface but never imports any chain-specific library.
 * The host injects an Ethereum adapter (viem), Solana adapter (@solana/web3.js),
 * or any future chain. WalletIdentity's state machine shape stays identical —
 * only the crypto underneath changes.
 * 
 * Must be set after construction but before initialize() (pi-mono pattern:
 * construction separate from initialization).
 */
export interface CryptoAdapter {
  /** Load a private key from a source string and derive the public address. */
  loadKey(keySource: string): Promise<{ address: Address; keyMaterial: unknown }>;
  /** Sign an arbitrary message with the loaded key material. */
  signMessage(keyMaterial: unknown, payload: string): Promise<Signature>;
  /** Sign a transaction payload with the loaded key material. */
  signTransaction(keyMaterial: unknown, payload: string): Promise<Signature>;
}

// ============================================================================
// STORAGE ADAPTER — Layer 2 persistence interface
// ============================================================================

/**
 * Pluggable storage adapter for the StorageBackend machine.
 *
 * Same pattern as CryptoAdapter: the kernel defines the interface but never
 * imports any storage-specific library (Synapse SDK, Helia, etc.). The host
 * injects a concrete adapter at boot time.
 *
 * SALM Layer 2 boundary: the storage key (if any) lives inside the adapter,
 * not in the pipeline middleware that requests storage. PersistenceMiddleware
 * at Layer 5/6 sends eStoreData events → StorageBackend at Layer 2 holds the
 * adapter and the key material.
 *
 * Must be set after StorageBackend construction but before initialize().
 */
export interface StorageAdapter {
  /**
   * Store data on IPFS (or similar content-addressed storage).
   * Handles serialization to DAG-CBOR internally if needed.
   * Returns the real CID of the stored data.
   */
  store(data: Uint8Array): Promise<{ cid: string }>;

  /**
   * Retrieve data by CID.
   * Returns raw bytes; caller is responsible for deserialization.
   */
  retrieve(cid: string): Promise<{ data: Uint8Array }>;

  /**
   * Check the pin status of a CID.
   * Returns provider name, expiry, and redundancy count.
   */
  checkPin(cid: string): Promise<{
    cid: string;
    provider: string;
    expiresAt: number;   // Unix ms, 0 = permanent
    redundancy: number;  // Number of replicas
  }>;

  /**
   * Renew (extend) the pin for a CID.
   * Returns the updated pin status after renewal.
   */
  renewPin(cid: string): Promise<{
    cid: string;
    provider: string;
    expiresAt: number;
    redundancy: number;
  }>;
}

/** Generate a deterministic session key from channel + chat identifiers. */
export function generateSessionKey(channel: ChannelName, chatId: string): SessionKey {
  return `${channel}:${chatId}`;
}

/** Check if a message is a slash command. */
export function isSlashCommand(content: string): boolean {
  return content.length > 0 && content[0] === "/";
}

/** Extract the command name from a slash command string. */
export function parseCommand(content: string): string {
  const parts = content.split(" ");
  return parts[0];
}

/** Sum token amounts for the same token symbol. */
export function sumTokenAmounts(amounts: TokenAmount[], token: TokenSymbol): number {
  let total = 0;
  for (const a of amounts) {
    if (a.token === token) {
      total += a.amount;
    }
  }
  return total;
}

/** Compute runway in days given total USD value and daily burn. Returns 9999 if no burn. */
export function computeRunway(totalValueUsd: number, dailyBurnUsd: number): number {
  if (dailyBurnUsd <= 0) {
    return 9999; // Effectively infinite if no burn
  }
  return Math.floor(totalValueUsd / dailyBurnUsd);
}

/** Determine treasury state from runway days. */
export function computeTreasuryState(runwayDays: number): TreasuryState {
  if (runwayDays > 30) {
    return TreasuryState.FUNDED;
  } else if (runwayDays > 7) {
    return TreasuryState.LOW;
  } else if (runwayDays > 0) {
    return TreasuryState.CRITICAL;
  } else {
    return TreasuryState.DEPLETED;
  }
}

/** Check if a budget category has remaining allocation. */
export function isBudgetAvailable(
  budget: BudgetAllocation,
  category: BudgetCategory,
  spentPercentage: number
): boolean {
  let limit: number;

  switch (category) {
    case BudgetCategory.INFERENCE:
      limit = budget.inference;
      break;
    case BudgetCategory.TOOLS:
      limit = budget.tools;
      break;
    case BudgetCategory.INFRASTRUCTURE:
      limit = budget.infrastructure;
      break;
    case BudgetCategory.STORAGE:
      limit = budget.storage;
      break;
    case BudgetCategory.MESSAGING:
      limit = budget.messaging;
      break;
    case BudgetCategory.RESERVE:
      limit = budget.reserve;
      break;
    default:
      limit = 0;
  }

  return spentPercentage < limit;
}

/** Default budget allocation — balanced, with storage and emergency reserves.
 *  Percentages: inference=38, tools=14, infrastructure=28, storage=5,
 *               messaging=10, reserve=5. Total = 100.
 */
export function defaultBudgetAllocation(): BudgetAllocation {
  return {
    inference: 38,
    tools: 14,
    infrastructure: 28,
    storage: 5,
    messaging: 10,
    reserve: 5,
  };
}

/**
 * Deterministically derive the agent's dPID namespace from its Ethereum address.
 * Pure function — actual registry lookup is an extension concern.
 * In practice: hash(address) → dPID namespace, or follow dpid.org conventions.
 */
export function deriveDPID(address: Address): DPID {
  return `dpid:${address}`;
}
