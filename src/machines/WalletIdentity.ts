/**
 * Machine: WalletIdentity
 * Role: CORE — The foundational identity primitive.
 * 
 * Direct TypeScript translation of src/machines/WalletIdentity.p
 * 
 * The wallet IS the agent. This machine guards the private key and provides
 * signing services to the rest of the system. The private key NEVER leaves
 * this machine boundary — other machines request signatures, they don't
 * access keys.
 * 
 * The wallet also manages the agent's dPID — a Decentralized Persistent
 * Identifier derived from the address. Together, address + dPID form the
 * agent's complete identity: "I am 0xAgent..., my state lives at dpid:XYZ."
 * 
 * States: Locked → Unlocked ↔ Signing
 */

import { Machine, MachineRegistry } from "../machine.js";
import {
  type Address,
  type Signature,
  type SigningRequest,
  type SigningResult,
  type CID,
  type DPID,
  type DPIDVersion,
  WalletState,
  SigningType,
} from "../types.js";
import type { CryptoAdapter } from "../interfaces.js";
import { deriveDPID } from "../interfaces.js";
import { createHash } from "crypto";

export class WalletIdentity extends Machine {
  /** The address derived from the private key (public, safe to share). */
  private address: Address = "";

  /** The agent's dPID, derived from its address. */
  private dpid: DPID = "";

  /** Current root CID of the agent's memory (resolved on boot via dPID). */
  private rootCid: CID = "";

  /** Whether a key is currently loaded. */
  private walletState: WalletState = WalletState.LOCKED;

  /** Private key material — NEVER exposed outside this machine. */
  private privateKey: string = "";

  /** Opaque key material from the crypto adapter (e.g. viem Account object). */
  private keyMaterial: unknown = null;

  /** Pluggable crypto adapter — injected after construction, before initialize(). */
  private cryptoAdapter: CryptoAdapter | null = null;

  /** Pending signing requests (queued while already signing). */
  private pendingRequests: SigningRequest[] = [];

  /** Current request being signed. */
  private currentRequest: SigningRequest | null = null;

  constructor(registry: MachineRegistry, id?: string) {
    super("WalletIdentity", registry, id);
    this.defineStates();
  }

  /** Initialize — transitions to Locked state. */
  async initialize(): Promise<void> {
    await this.init("Locked");
  }

  private defineStates(): void {
    // ========================================================================
    // LOCKED — Wallet exists but no key loaded
    // ========================================================================
    this.defineState("Locked")
      .onEntry(() => {
        this.walletState = WalletState.LOCKED;
        this.address = "";
        this.dpid = "";
        this.rootCid = "";
        this.pendingRequests = [];
        this.log("Locked — awaiting key");
      })
      .on("eUnlockWallet", async (keySource: string) => {
        if (this.cryptoAdapter) {
          try {
            const result = await this.cryptoAdapter.loadKey(keySource);
            this.address = result.address;
            this.keyMaterial = result.keyMaterial;
            this.privateKey = ""; // Not needed when adapter is present
          } catch (err) {
            this.log(`CryptoAdapter loadKey failed: ${err}`);
            this.address = "";
            return;
          }
        } else {
          // Fallback to stub crypto (Phase 0 compatibility)
          this.privateKey = this.loadKey(keySource);
          this.address = this.deriveAddress(this.privateKey);
        }

        // Derive the agent's dPID from its address.
        this.dpid = deriveDPID(this.address);
        this.log(`Unlocked — address ${this.address}, dPID ${this.dpid}`);

        // Request dPID resolution to find the current root CID.
        // A dPID resolver extension will handle this and respond with eDPIDResolved.
        // If no resolver is registered, the agent boots without memory (graceful).
        this.sendSelf("eResolveDPID", this.dpid);

        this.goto("Unlocked");
      })
      .on("eSignRequest", (req: SigningRequest) => {
        // Can't sign while locked — send failure via registry lookup
        // (requestor is a machine ID string in SigningRequest).
        const result: SigningResult = {
          requestId: req.id,
          signature: "",
          success: false,
          error: "Wallet is locked",
        };
        this.sendById(req.requestor, "eSignResult", result);
      })
      .on("eGetAddress", () => {
        this.sendSelf("eAddressResult", "");
      });

    // ========================================================================
    // UNLOCKED — Key loaded, ready to sign
    // ========================================================================
    this.defineState("Unlocked")
      .onEntry(() => {
        this.walletState = WalletState.UNLOCKED;
      })
      .on("eLockWallet", () => {
        this.privateKey = "";
        this.address = "";
        this.dpid = "";
        this.rootCid = "";
        this.log("Locking — key and dPID state cleared");
        this.goto("Locked");
      })
      .on("eSignRequest", (req: SigningRequest) => {
        this.currentRequest = req;
        this.goto("Signing");
      })
      .on("eGetAddress", () => {
        this.sendSelf("eAddressResult", this.address);
      })
      // --- dPID lifecycle handlers ---
      .on("eResolveDPID", (_dpid: string) => {
        // No-op in core — a dPID resolver extension responds with eDPIDResolved.
        // This event just passes through. If no resolver is registered, nothing happens.
        this.log(`dPID resolution requested — ${_dpid}`);
      })
      .on("eDPIDResolved", (version: DPIDVersion) => {
        // dPID resolver extension responded with the current root CID.
        this.rootCid = version.cid;
        this.log(`dPID resolved — CID ${version.cid} (v${version.version})`);

        // Emit memory restore request so persistence extensions can load state.
        // If rootCid is empty, this is a fresh agent with no prior memory.
        if (this.rootCid !== "") {
          this.sendSelf("eMemoryRestore", this.rootCid);
        } else {
          this.log("No prior memory — fresh agent");
        }
      })
      .on("eUpdateDPID", (req: { newCid: CID; requestor: string }) => {
        // An extension (e.g., PersistenceMiddleware) wants to update the
        // agent's dPID to point to a new root CID. This requires a signature.
        this.log(`dPID update requested — new CID ${req.newCid}`);

        // Sign the dPID version update via existing Signing state.
        const sigReq: SigningRequest = {
          id: `dpid-update:${req.newCid}`,
          signingType: SigningType.TYPED_DATA,
          payload: `dpid:${this.dpid}:cid:${req.newCid}`,
          chain: "ethereum",
          requestor: req.requestor,
        };
        this.currentRequest = sigReq;
        this.goto("Signing");
      })
      .on("eDPIDUpdated", (version: DPIDVersion) => {
        // Confirmation that the dPID was updated on-chain (or in registry).
        this.rootCid = version.cid;
        this.log(`dPID updated — CID ${version.cid} (v${version.version})`);
      })
      .on("eStop", () => {
        this.privateKey = "";
        this.address = "";
        this.dpid = "";
        this.rootCid = "";
        this.log("Shutdown — key and dPID state cleared");
        this.halt();
      });

    // ========================================================================
    // SIGNING — Actively signing a payload
    // ========================================================================
    this.defineState("Signing")
      .onEntry(async () => {
        this.walletState = WalletState.SIGNING;

        if (!this.currentRequest) {
          this.goto("Unlocked");
          return;
        }

        this.log(
          `Signing request ${this.currentRequest.id} (type: ${this.currentRequest.signingType})`
        );

        let sig: Signature;
        try {
          sig = await this.performSign(this.currentRequest);
        } catch (err) {
          const errorResult: SigningResult = {
            requestId: this.currentRequest.id,
            signature: "",
            success: false,
            error: `Signing failed: ${err}`,
          };
          this.sendById(this.currentRequest.requestor, "eSignResult", errorResult);
          this.goto("Unlocked");
          return;
        }

        const result: SigningResult = {
          requestId: this.currentRequest.id,
          signature: sig,
          success: true,
          error: "",
        };

        this.sendById(this.currentRequest.requestor, "eSignResult", result);

        if (this.pendingRequests.length > 0) {
          this.currentRequest = this.pendingRequests.shift()!;
          this.goto("Signing");
        } else {
          this.goto("Unlocked");
        }
      })
      .on("eSignRequest", (req: SigningRequest) => {
        this.pendingRequests.push(req);
      })
      .on("eGetAddress", () => {
        this.sendSelf("eAddressResult", this.address);
      });
  }

  // ==========================================================================
  // Public accessors (read-only, safe to expose)
  // ==========================================================================

  getAddress(): Address {
    return this.address;
  }

  getWalletState(): WalletState {
    return this.walletState;
  }

  /**
   * Inject a chain-specific crypto adapter.
   * Must be called after construction but before initialize().
   * The adapter replaces the stub sha256 crypto with real chain signing (e.g. viem for Ethereum).
   */
  setCryptoAdapter(adapter: CryptoAdapter): void {
    this.cryptoAdapter = adapter;
    this.log(`CryptoAdapter injected`);
  }

  // ==========================================================================
  // Implementation stubs (replaced by real crypto in Phase 1)
  // ==========================================================================

  private loadKey(keySource: string): string {
    if (keySource.startsWith("env:")) {
      const envVar = keySource.slice(4);
      const key = process.env[envVar];
      if (key) return key;
    }
    return "0x" + createHash("sha256").update(keySource).digest("hex");
  }

  private deriveAddress(key: string): Address {
    const hash = createHash("sha256").update(key).digest("hex");
    return "0x" + hash.slice(0, 40);
  }

  private async performSign(req: SigningRequest): Promise<Signature> {
    if (this.cryptoAdapter) {
      if (req.signingType === "TRANSACTION") {
        return await this.cryptoAdapter.signTransaction(this.keyMaterial, req.payload);
      }
      return await this.cryptoAdapter.signMessage(this.keyMaterial, req.payload);
    }
    // Fallback to stub crypto
    const combined = this.privateKey + req.payload;
    const sig = createHash("sha256").update(combined).digest("hex");
    return "0x" + sig;
  }
}
