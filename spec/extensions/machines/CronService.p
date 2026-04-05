/**
 * Extension: CronService
 * Role: REFERENCE EXTENSION — Scheduled task execution.
 *
 * Enables the agent to perform actions on a schedule without human
 * triggers. Jobs are registered dynamically and persist across restarts
 * (via the storage extension).
 *
 * Design principle: Autonomous scheduling is an extension, not core.
 * An agent that only responds to messages doesn't need a cron service.
 * A sovereign agent that must renew leases, check balances, and perform
 * maintenance absolutely does — but it's still a pluggable capability.
 */

machine CronService {
    var jobs: map[JobId, CronJob];
    var running: bool;
    var bus: machine;

    start state Stopped {
        entry (payload: (bus: machine)) {
            bus = payload.bus;
            jobs = default(map[JobId, CronJob]);
            running = false;

            print "CronService: Initialized (stopped)";
        }

        on eCronStart do {
            running = true;
            goto Running;
        }
    }

    state Running {
        entry {
            print format("CronService: Running with {0} jobs", sizeof(jobs));
        }

        on eCronJobAdd do (job: CronJob) {
            jobs[job.id] = job;
            print format("CronService: Job added — {0} ({1})", job.name, job.schedule);
        }

        on eCronJobRemove do (jobId: JobId) {
            if (jobId in jobs) {
                jobs -= (jobId);
                print format("CronService: Job removed — {0}", jobId);
            }
        }

        on eTimerFired do {
            // Check for due jobs.
            var jobId: JobId;
            foreach (jobId in keys(jobs)) {
                var job: CronJob;
                job = jobs[jobId];
                if (job.enabled) {
                    // In model checking, trigger all enabled jobs.
                    send this, eCronTrigger, job;
                }
            }
        }

        on eCronTrigger do (job: CronJob) {
            print format("CronService: Triggering job — {0}", job.name);

            // Inject the job's message into the bus as an inbound message.
            var msg: InboundMessage;
            msg = (
                id = format("cron:{0}", job.id),
                channel = "cron",
                senderId = "system",
                chatId = "cron",
                content = job.message,
                timestamp = 0,
                sessionKey = format("cron:{0}", job.id),
                metadata = default(map[string, string])
            );
            send bus, ePublishInbound, msg;
        }

        on eCronJobComplete do (result: (jobId: JobId, success: bool)) {
            print format("CronService: Job {0} completed — success={1}", result.jobId, result.success);
        }

        on eCronStop do {
            running = false;
            goto Stopped;
        }
    }
}
