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

/** Default budget allocation — balanced, with a 5% emergency reserve. */
export function defaultBudgetAllocation(): BudgetAllocation {
  return {
    inference: 40,
    tools: 15,
    infrastructure: 30,
    messaging: 10,
    reserve: 5,
  };
}
