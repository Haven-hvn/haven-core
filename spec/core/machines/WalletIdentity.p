/**
 * Machine: WalletIdentity
 * Role: CORE — The foundational identity primitive.
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
 * Design principle: This machine is intentionally minimal. It knows how to
 * lock/unlock/sign. It does NOT know about specific chains, protocols, or
 * key derivation schemes. Multi-chain address derivation, TEE integration,
 * and HSM backends are extension concerns — they wrap this machine or
 * provide the key source. dPID resolution is an extension concern — this
 * machine only derives the dPID namespace and emits resolution requests.
 */

machine WalletIdentity {
    // The address derived from the private key (public, safe to share).
    var address: Address;

    // The agent's dPID, derived from its address.
    // This is the resolvable pointer to the agent's persistent state.
    var dpid: DPID;

    // Current root CID of the agent's memory (resolved on boot via dPID).
    var rootCid: CID;

    // Whether a key is currently loaded.
    var walletState: WalletState;

    // Pending signing requests (queued while already signing).
    var pendingRequests: seq[SigningRequest];

    // Current request being signed.
    var currentRequest: SigningRequest;

    start state Locked {
        entry {
            walletState = LOCKED;
            address = "";
            dpid = "";
            rootCid = "";
            pendingRequests = default(seq[SigningRequest]);
            print "WalletIdentity: Locked — awaiting key";
        }

        on eUnlockWallet do (keySource: string) {
            // Load key from the provided source.
            // In a real implementation, keySource identifies the backend:
            //   "env:SOVEREIGN_AGENT_PRIVATE_KEY"
            //   "keystore:/path/to/keystore.json"
            //   "tee:sgx-enclave"
            // The actual key loading is an implementation concern.
            address = DeriveAddress(keySource);

            // Derive the agent's dPID from its address.
            // The dPID is the resolvable pointer to the agent's persistent state.
            dpid = DeriveDPID(address);

            print format("WalletIdentity: Unlocked — address {0}, dPID {1}", address, dpid);

            // Request dPID resolution to find the current root CID.
            // A dPID resolver extension will handle this and respond with eDPIDResolved.
            // If no resolver is registered, the agent boots without memory (graceful).
            send this, eResolveDPID, dpid;

            goto Unlocked;
        }

        on eSignRequest do (req: SigningRequest) {
            // Can't sign while locked.
            var result: SigningResult;
            result = (
                requestId = req.id,
                signature = "",
                success = false,
                error = "Wallet is locked"
            );
            send req.requestor, eSignResult, result;
        }

        on eGetAddress do {
            send this, eAddressResult, "";
        }
    }

    state Unlocked {
        entry {
            walletState = UNLOCKED;
        }

        on eLockWallet do {
            // Clear key and dPID state from memory.
            address = "";
            dpid = "";
            rootCid = "";
            print "WalletIdentity: Locking — key and dPID state cleared";
            goto Locked;
        }

        on eSignRequest do (req: SigningRequest) {
            currentRequest = req;
            goto Signing;
        }

        on eGetAddress do {
            send this, eAddressResult, address;
        }

        // --- dPID lifecycle handlers ---

        on eDPIDResolved do (version: DPIDVersion) {
            // dPID resolver extension responded with the current root CID.
            rootCid = version.cid;
            print format("WalletIdentity: dPID resolved — CID {0} (v{1})",
                         version.cid, version.version);

            // Emit memory restore request so persistence extensions can load state.
            // If rootCid is empty, this is a fresh agent with no prior memory.
            if (rootCid != "") {
                send this, eMemoryRestore, rootCid;
            } else {
                print "WalletIdentity: No prior memory — fresh agent";
            }
        }

        on eUpdateDPID do (req: (newCid: CID, requestor: machine)) {
            // An extension (e.g., PersistenceMiddleware) wants to update the
            // agent's dPID to point to a new root CID. This requires a signature.
            print format("WalletIdentity: dPID update requested — new CID {0}", req.newCid);

            // Sign the dPID version update via existing PerformSign.
            var sigReq: SigningRequest;
            sigReq = (
                id = format("dpid-update:{0}", req.newCid),
                signingType = TYPED_DATA,
                payload = format("dpid:{0}:cid:{1}", dpid, req.newCid),
                chain = "ethereum",
                requestor = req.requestor
            );
            currentRequest = sigReq;
            goto Signing;
        }

        on eDPIDUpdated do (version: DPIDVersion) {
            // Confirmation that the dPID was updated on-chain (or in registry).
            rootCid = version.cid;
            print format("WalletIdentity: dPID updated — CID {0} (v{1})",
                         version.cid, version.version);
        }

        on eStop do {
            // Always lock on shutdown.
            address = "";
            dpid = "";
            rootCid = "";
            print "WalletIdentity: Shutdown — key and dPID state cleared";
            raise halt;
        }
    }

    state Signing {
        entry {
            walletState = SIGNING;
            print format("WalletIdentity: Signing request {0} (type: {1})",
                         currentRequest.id, currentRequest.signingType);

            // Perform the signing operation.
            // This is atomic — no partial signatures.
            var sig: Signature;
            sig = PerformSign(currentRequest);

            var result: SigningResult;
            result = (
                requestId = currentRequest.id,
                signature = sig,
                success = true,
                error = ""
            );

            send currentRequest.requestor, eSignResult, result;

            // Process any queued requests, or return to Unlocked.
            if (sizeof(pendingRequests) > 0) {
                currentRequest = pendingRequests[0];
                pendingRequests -= (0);
                goto Signing;
            } else {
                goto Unlocked;
            }
        }

        // Queue additional requests that arrive while signing.
        on eSignRequest do (req: SigningRequest) {
            pendingRequests += (req);
        }

        on eGetAddress do {
            send this, eAddressResult, address;
        }
    }

    // --- Implementation stubs (replaced by real crypto in implementation) ---

    fun DeriveAddress(keySource: string): Address {
        // Simulate address derivation from key source.
        return "0x742d35Cc6634C0532925a3b844Bc9e7595f2bD18";
    }

    fun PerformSign(req: SigningRequest): Signature {
        // Simulate cryptographic signing.
        // In reality: secp256k1 sign for Ethereum, ed25519 for Solana, etc.
        return "0xsignature_placeholder";
    }
}
