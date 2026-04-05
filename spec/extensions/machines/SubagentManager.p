/**
 * Extension: SubagentManager
 * Role: REFERENCE EXTENSION — Parallel task execution.
 *
 * Spawns lightweight agent instances for background work. All subagents
 * share the parent's wallet identity (same economic entity). Results
 * are injected back into the message bus.
 *
 * Design principle: Parallel execution is an optimization, not a
 * requirement. A single-threaded agent works fine — subagents are
 * an extension for when concurrency matters.
 */

machine SubagentManager {
    var bus: machine;
    var runningTasks: map[TaskId, SubagentTask];
    var maxConcurrent: int;

    start state Init {
        entry (payload: (bus: machine, maxConcurrent: int)) {
            bus = payload.bus;
            maxConcurrent = payload.maxConcurrent;
            runningTasks = default(map[TaskId, SubagentTask]);

            print format("SubagentManager: Initialized (max={0})", maxConcurrent);
            goto Idle;
        }
    }

    state Idle {
        on eSubagentSpawn do (task: SubagentTask) {
            if (sizeof(runningTasks) >= maxConcurrent) {
                print "SubagentManager: Max concurrent reached — rejecting spawn";
                return;
            }

            task.status = RUNNING;
            runningTasks[task.id] = task;
            send this, eSubagentStarted, task.id;
            print format("SubagentManager: Spawned — {0}", task.label);
            goto Monitoring;
        }

        on eSubagentCancelled do (taskId: TaskId) {
            // Nothing to cancel in idle state.
        }
    }

    state Monitoring {
        on eSubagentSpawn do (task: SubagentTask) {
            if (sizeof(runningTasks) < maxConcurrent) {
                task.status = RUNNING;
                runningTasks[task.id] = task;
                send this, eSubagentStarted, task.id;
                print format("SubagentManager: Spawned — {0}", task.label);
            }
        }

        on eSubagentComplete do (result: (taskId: TaskId, result: string, status: SubagentStatus)) {
            if (result.taskId in runningTasks) {
                var task: SubagentTask;
                task = runningTasks[result.taskId];

                // Inject result into message bus.
                var resultMsg: InboundMessage;
                resultMsg = (
                    id = format("subagent:{0}", result.taskId),
                    channel = "subagent",
                    senderId = "subagent",
                    chatId = task.originChatId,
                    content = format("Task '{0}' completed: {1}", task.label, result.result),
                    timestamp = 0,
                    sessionKey = format("{0}:{1}", task.originChannel, task.originChatId),
                    metadata = default(map[string, string])
                );
                send bus, ePublishInbound, resultMsg;

                runningTasks -= (result.taskId);
                print format("SubagentManager: Completed — {0}", task.label);
            }

            if (sizeof(runningTasks) == 0) {
                goto Idle;
            }
        }

        on eSubagentCancelled do (taskId: TaskId) {
            if (taskId in runningTasks) {
                runningTasks -= (taskId);
                print format("SubagentManager: Cancelled — {0}", taskId);
            }
            if (sizeof(runningTasks) == 0) {
                goto Idle;
            }
        }
    }
}
