/**
 * Machine: WalletIdentity
 * Role: CORE — The foundational identity primitive.
 *
 * The wallet IS the agent. This machine guards the private key and provides
 * signing services to the rest of the system. The private key NEVER leaves
 * this machine boundary — other machines request signatures, they don't
 * access keys.
 *
 * Design principle: This machine is intentionally minimal. It knows how to
 * lock/unlock/sign. It does NOT know about specific chains, protocols, or
 * key derivation schemes. Multi-chain address derivation, TEE integration,
 * and HSM backends are extension concerns — they wrap this machine or
 * provide the key source.
 */

machine WalletIdentity {
    // The address derived from the private key (public, safe to share).
    var address: Address;

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
            print format("WalletIdentity: Unlocked — address {0}", address);
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
            // Clear key from memory.
            address = "";
            print "WalletIdentity: Locking — key cleared";
            goto Locked;
        }

        on eSignRequest do (req: SigningRequest) {
            currentRequest = req;
            goto Signing;
        }

        on eGetAddress do {
            send this, eAddressResult, address;
        }

        on eStop do {
            // Always lock on shutdown.
            address = "";
            print "WalletIdentity: Shutdown — key cleared";
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
