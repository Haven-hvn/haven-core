/**
 * Extension: SessionManager
 * Role: REFERENCE EXTENSION — Conversation persistence.
 *
 * Manages session load/save/clear operations. The storage backend is
 * pluggable — local disk, Filecoin, Arweave, or any combination.
 * The core AgentLoop does NOT depend on this — it can function without
 * sessions (stateless mode). This extension adds statefulness.
 *
 * Design principle: Session persistence is opt-in. An agent that doesn't
 * need conversation history simply doesn't register this extension.
 */

machine SessionManager {
    var sessions: map[SessionKey, Session];
    var agent: machine;

    start state Init {
        entry (payload: (agent: machine)) {
            agent = payload.agent;
            sessions = default(map[SessionKey, Session]);

            print "SessionManager: Initialized";
            goto Ready;
        }
    }

    state Ready {
        on eSessionLoad do (key: SessionKey) {
            if (key in sessions) {
                send agent, eSessionLoaded, sessions[key];
            } else {
                // Create new empty session.
                var session: Session;
                session = (
                    key = key,
                    messages = default(seq[map[string, string]]),
                    lastConsolidated = 0,
                    status = ACTIVE
                );
                sessions[key] = session;
                send agent, eSessionLoaded, session;
            }
        }

        on eSessionSave do (session: Session) {
            sessions[session.key] = session;
            // In a real implementation, this would also persist to
            // decentralized storage via eStoreData.
            send agent, eSessionSaved, session.key;
            print format("SessionManager: Session saved — {0}", session.key);
        }

        on eSessionClear do (key: SessionKey) {
            if (key in sessions) {
                sessions -= (key);
                print format("SessionManager: Session cleared — {0}", key);
            }
        }
    }
}
